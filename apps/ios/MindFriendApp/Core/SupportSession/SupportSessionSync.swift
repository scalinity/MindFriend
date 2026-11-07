import Foundation
import Combine

/// Drives the existing protected outbox for one account epoch. Chat drafts are never dispatched here.
@MainActor
final class SupportSessionSync: ObservableObject {
    let cloud: SupportSessionCloudService
    let repository: SupportSessionRepository
    @Published private(set) var capabilities: SupportCloudCapabilities?
    @Published private(set) var privacyRevision: Int64?
    @Published private(set) var status = "Account sync pending"
    @Published private(set) var isSyncing = false
    @Published private(set) var history: [SupportCloudSessionSummary] = []
    @Published private(set) var hasMoreHistory = true
    @Published private(set) var memory: SupportCloudMemoryPage?
    private var cursor: SupportCloudListCursor?
    private var active = true
    private var paused = false
    private var transcriptPaused = false
    private var task: Task<Void, Error>?
    private var observation: Task<Void, Never>?
    private var reconnect: AnyCancellable?
    private var retryTask: Task<Void, Never>?
    private var retryCount = 0
    private var isRefreshing = false
    private var transcriptUploads: [UUID: Task<Void, Error>] = [:]

    init(cloud: SupportSessionCloudService, repository: SupportSessionRepository) {
        self.cloud = cloud
        self.repository = repository
    }

    func start() {
        guard observation == nil else { return }
        reconnect = ConnectivityMonitor.shared.$isConnected.removeDuplicates().dropFirst().sink { [weak self] connected in
            guard connected else { return }
            Task { @MainActor in try? await self?.refresh() }
        }
        observation = Task { [weak self] in
            guard let self else { return }
            do {
                let updates = try await repository.updates(epoch: repository.identity.epochID)
                try? await synchronize()
                for await journal in updates {
                    guard active, !Task.isCancelled else { return }
                    if !paused, journal.hasAutomaticNonTranscriptWork || (!transcriptPaused && journal.hasAutomaticTranscriptWork) {
                        try? await synchronize()
                    }
                }
            } catch { if active { status = "Account sync is paused. Local work is saved." } }
        }
    }

    @discardableResult
    func invalidate() -> Task<Void, Never> {
        active = false
        observation?.cancel()
        observation = nil
        reconnect = nil
        retryTask?.cancel()
        retryTask = nil
        let pending = task
        pending?.cancel()
        task = nil
        memory = nil
        history = []
        capabilities = nil
        let uploads = Array(transcriptUploads.values)
        uploads.forEach { $0.cancel() }
        transcriptUploads = [:]
        return Task {
            _ = try? await pending?.value
            for upload in uploads { _ = try? await upload.value }
        }
    }

    /// An explicit retry may replay an unchanged unknown operation. It never sends a chat draft.
    func retry() async throws {
        // A deliberate retry starts a fresh bounded retry window even if the capability read fails.
        retryCount = 0
        // Keep the last verified snapshot visible while joining an in-flight pass or refreshing it.
        if task == nil {
            do {
                let refreshed = try await cloud.capabilities()
                try checkActive()
                capabilities = refreshed
            } catch {
                scheduleRetry(error)
                throw error
            }
        }
        retryTask?.cancel()
        retryTask = nil
        retryCount = 0
        paused = false
        transcriptPaused = false
        try await synchronize()
    }

    func synchronize() async throws {
        try checkActive()
        if let task { return try await task.value }
        let work = Task { @MainActor in try await self.drain() }
        task = work
        defer { task = nil }
        try await work.value
    }

    private func drain() async throws {
        isSyncing = true
        defer { isSyncing = false }
        do {
            try checkActive()
            if capabilities == nil { capabilities = try await cloud.capabilities() }
            try checkActive()
            guard capabilities?.sessionContractAvailable == true,
                  capabilities?.canEnforcePrivacyForChat == true else {
                paused = true
                status = "Account sync is unavailable. Work is saved on this device."
                throw SupportCloudError.capabilityUnavailable(.rpcNotDeployed)
            }
            try await drainMemoryChanges()
            try await reconcileErasedRequests()
            var conflicts: [UUID: Int] = [:]
            while let envelope = try await repository.nextEnvelopeToSend(epoch: repository.identity.epochID, requirePrivacyFlushed: false) {
                try checkActive()
                do {
                    let result = try await cloud.mutate(envelope)
                    try checkActive()
                    try await repository.resolveAttempt(epoch: repository.identity.epochID,
                        operationID: envelope.operationID, outcome: result.attemptOutcome)
                    let snapshot: SupportCloudSnapshot?
                    switch result {
                    case .confirmed(let receipt): snapshot = receipt.snapshot
                    case .conflict(let conflict): snapshot = conflict.snapshot
                    }
                    if let snapshot {
                        try await repository.applyRemoteSession(epoch: repository.identity.epochID,
                            remote: cloud.remoteSnapshot(from: snapshot))
                    }
                    if case .conflict = result {
                        conflicts[envelope.sessionID, default: 0] += 1
                        let current = try await repository.currentJournal(epoch: repository.identity.epochID)
                        guard !current.hasUnresolvedConflict(sessionID: envelope.sessionID), conflicts[envelope.sessionID, default: 0] <= 3 else {
                            throw SupportCloudError.rejected(.init(code: .revisionConflict, message: nil, httpStatus: 409, currentPrivacyRevision: nil))
                        }
                        if current.attempts.contains(where: { $0.id == envelope.operationID }) {
                            _ = try await repository.rebaseConflictedAttempt(epoch: repository.identity.epochID, operationID: envelope.operationID)
                        }
                    }
                } catch let error as SupportCloudError {
                    try checkActive()
                    let pending = try await repository.currentJournal(epoch: repository.identity.epochID)
                    if pending.attempts.contains(where: { $0.id == envelope.operationID && $0.state == .inFlight }) {
                        try await repository.resolveAttempt(epoch: repository.identity.epochID,
                            operationID: envelope.operationID, outcome: error.attemptOutcome)
                    }
                    throw error
                }
            }
            let page = try await cloud.listMemory()
            try checkActive()
            try await cacheMemory(page)
            memory = page
            privacyRevision = max(privacyRevision ?? 0, page.privacyRevision)
            var transcriptFailure: Error?
            for event in try await repository.pendingTranscriptEvents(epoch: repository.identity.epochID) where !transcriptPaused {
                try checkActive()
                let journal = try await repository.currentJournal(epoch: repository.identity.epochID)
                if journal.hasOutstandingMutations(sessionID: event.sessionID) { continue }
                do { try await uploadTranscript(event) }
                catch let error as SupportCloudError {
                    if case .rejected = error { continue }
                    if case .invalidRequest = error { continue }
                    if case .transcriptTargetPending = error { continue }
                    transcriptFailure = error
                    break
                }
            }
            try checkActive()
            paused = false
            if let transcriptFailure {
                // Transcript transport trouble does not block a deliberate text send or privacy refresh.
                transcriptPaused = true
                scheduleRetry(transcriptFailure)
                status = "Voice turns are saved on this device. Account sync is pending."
            } else {
                if !transcriptPaused {
                    retryCount = 0
                    retryTask?.cancel()
                    retryTask = nil
                }
                let journal = try await repository.currentJournal(epoch: repository.identity.epochID)
                if journal.transcriptEvents.contains(where: { $0.syncState == .pending }) {
                    status = "Voice turns are saved on this device. Account sync is pending."
                } else {
                    status = journal.transcriptEvents.contains { $0.syncState == .rejected }
                        ? "Some voice turns could not be saved to your account. Their local copies are kept."
                        : "Account changes synced"
                }
            }
        } catch {
            if active {
                paused = true
                if capabilities?.sessionContractAvailable == true {
                    status = "Account sync paused. Local work is saved; retry when ready."
                }
                scheduleRetry(error)
            }
            throw error
        }
    }

    /// The voice screen and background sync join the same upload for an event identity.
    func uploadTranscript(_ event: SupportTranscriptEvent) async throws {
        try checkActive()
        if let upload = transcriptUploads[event.id] { return try await upload.value }
        let journal = try await repository.currentJournal(epoch: repository.identity.epochID)
        try checkActive()
        if let upload = transcriptUploads[event.id] { return try await upload.value }
        guard !journal.hasOutstandingMutations(sessionID: event.sessionID) else { throw SupportCloudError.transcriptTargetPending }
        let upload = Task { @MainActor in
            do {
                try await cloud.appendTranscript(event)
                try checkActive()
                try await repository.markTranscriptEventsSaved(epoch: repository.identity.epochID, ids: [event.id])
            } catch let error as SupportCloudError {
                try checkActive()
                let code: String?
                switch error {
                case .rejected(let failure):
                    if failure.code == .notFound || failure.code == .sessionConversationMismatch {
                        let current = try await repository.currentJournal(epoch: repository.identity.epochID)
                        if current.hasOutstandingMutations(sessionID: event.sessionID) { throw SupportCloudError.transcriptTargetPending }
                    }
                    code = failure.code.rawValue
                case .invalidRequest: code = "CLIENT_ENCODING_FAILED"
                default: code = nil
                }
                if let code {
                    try await repository.markTranscriptEventRejected(epoch: repository.identity.epochID, id: event.id, code: code)
                }
                throw error
            }
        }
        transcriptUploads[event.id] = upload
        defer { transcriptUploads[event.id] = nil }
        try await upload.value
    }

    /// Foreground/reconnection refreshes structured work only; text drafts require deliberate Send.
    func refresh() async throws {
        try checkActive()
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        try await retry()
        var next: SupportCloudListCursor?
        var inspected = 0
        repeat {
            let page = try await cloud.list(limit: 100, cursor: next, includeDeleted: true)
            try checkActive()
            for item in page.items {
                let journal = try await repository.currentJournal(epoch: repository.identity.epochID)
                if (journal.sessions[item.id] != nil || item.status == .open),
                   journal.serverRevisions[item.id] != item.revision {
                    try await refreshSession(item.id)
                }
            }
            inspected += page.items.count
            guard page.nextCursor == nil || page.nextCursor != next else {
                throw SupportCloudError.malformedResponse("refresh cursor did not advance")
            }
            next = page.nextCursor
        } while next != nil && inspected < SupportSessionLimits.maxSessions
    }

    private func scheduleRetry(_ error: Error) {
        guard active, retryCount < 3 else { return }
        let hint: TimeInterval?
        switch error as? SupportCloudError {
        case .transport(let failure) where failure != .cancelled: hint = nil
        case .serverTemporary(_, let retryAfter): hint = retryAfter
        default: return
        }
        retryCount += 1
        let delay = max(hint ?? 0, min(30, pow(2, Double(retryCount))) + Double.random(in: 0...0.5))
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.active, !Task.isCancelled else { return }
            self.retryTask = nil
            self.paused = false
            self.transcriptPaused = false
            try? await self.synchronize()
        }
    }

    func refreshSession(_ id: UUID) async throws {
        try checkActive()
        let detail = try await cloud.get(sessionID: id)
        try checkActive()
        try await repository.applyRemoteSession(epoch: repository.identity.epochID,
            remote: cloud.remoteSnapshot(from: detail.snapshot))
    }

    func loadHistory(reset: Bool = false) async throws {
        try checkActive()
        let previous = reset ? nil : cursor
        let page = try await cloud.list(limit: 50, cursor: previous, includeDeleted: true)
        try checkActive()
        if reset { history = [] }
        for item in page.items {
            if let index = history.firstIndex(where: { $0.id == item.id }) { history[index] = item }
            else { history.append(item) }
        }
        guard page.nextCursor == nil || page.nextCursor != previous else {
            throw SupportCloudError.malformedResponse("history cursor did not advance")
        }
        cursor = page.nextCursor
        hasMoreHistory = cursor != nil
        privacyRevision = max(privacyRevision ?? 0, page.privacyRevision)
    }

    func refreshMemory() async throws {
        try checkActive()
        let page = try await cloud.listMemory()
        try checkActive()
        try await cacheMemory(page)
        memory = page
        privacyRevision = max(privacyRevision ?? 0, page.privacyRevision)
    }

    private func cacheMemory(_ page: SupportCloudMemoryPage) async throws {
        let saved = page.saved.map { item in
            SupportMemoryRecord(id: item.id, content: item.content, category: item.category.rawValue,
                origin: item.origin.rawValue, state: item.state.rawValue, revision: Int(item.revision),
                confirmedAt: item.confirmedAt, reviewDueAt: item.reviewDueAt, expiresAt: item.expiresAt,
                lastUsedAt: item.lastUsedAt, sourceMessageID: item.sourceMessageID, sourceConversationID: nil, isSuggestion: false)
        }
        let candidates = page.candidates.map { item in
            SupportMemoryRecord(id: item.id, content: item.value, category: item.fragmentType.rawValue,
                origin: item.provenance.rawValue, state: item.reviewState.rawValue, revision: 0,
                confirmedAt: nil, reviewDueAt: nil, expiresAt: item.candidateExpiresAt, lastUsedAt: nil,
                sourceMessageID: item.sourceMessageID, sourceConversationID: item.sourceConversationID, isSuggestion: true)
        }
        try await repository.cacheMemoryRecords(epoch: repository.identity.epochID, records: saved + candidates,
            privacyRevision: page.privacyRevision)
    }

    private func reconcileErasedRequests() async throws {
        let attempts = try await repository.reconciliationAttempts(epoch: repository.identity.epochID)
        for attempt in attempts {
            try checkActive()
            do {
                let detail = try await cloud.get(sessionID: attempt.envelope.sessionID)
                try checkActive()
                try await repository.adoptServerStateForErasure(epoch: repository.identity.epochID,
                    operationID: attempt.id, revision: detail.snapshot.session.revision)
                try await repository.applyRemoteSession(epoch: repository.identity.epochID, remote: cloud.remoteSnapshot(from: detail.snapshot))
            } catch SupportCloudError.rejected(let rejection) where rejection.code == .notFound {
                try checkActive()
                try await repository.adoptServerStateForErasure(epoch: repository.identity.epochID, operationID: attempt.id, revision: nil)
            }
        }
    }

    private func drainMemoryChanges() async throws {
        while let change = try await repository.currentJournal(epoch: repository.identity.epochID).memoryChanges.first {
            try checkActive()
            if change.failureCode != nil { throw SupportCloudError.rejected(.init(code: .revisionConflict, message: nil, httpStatus: 409, currentPrivacyRevision: nil)) }
            try await repository.markMemoryChangeSent(epoch: repository.identity.epochID, id: change.id)
            do {
                let mutation = try SupportCloudMemoryMutation(operationID: change.id, operation: change.cloudOperation)
                let result = try await cloud.mutateMemory(mutation)
                try checkActive()
                switch result {
                case .confirmed(let receipt):
                    try await repository.confirmMemoryChange(epoch: repository.identity.epochID, id: change.id, privacyRevision: receipt.privacyRevision)
                    privacyRevision = max(privacyRevision ?? 0, receipt.privacyRevision)
                case .conflict(let conflict):
                    try await repository.rejectMemoryChange(epoch: repository.identity.epochID, id: change.id, code: "REVISION_CONFLICT",
                        conflictingContent: conflict.content, conflictingRevision: Int(conflict.revision))
                    throw SupportCloudError.rejected(.init(code: .revisionConflict, message: nil, httpStatus: 409, currentPrivacyRevision: nil))
                }
            } catch let error as SupportCloudError {
                try checkActive()
                if case .rejected(let rejection) = error {
                    // Keep conflict details already recorded above; other definite errors stay visible.
                    let journal = try await repository.currentJournal(epoch: repository.identity.epochID)
                    if journal.memoryChanges.first(where: { $0.id == change.id })?.failureCode == nil {
                        try await repository.rejectMemoryChange(epoch: repository.identity.epochID, id: change.id, code: rejection.code.rawValue)
                    }
                }
                throw error
            }
        }
    }

    private func checkActive() throws {
        guard active, !Task.isCancelled else { throw CancellationError() }
    }
}

private extension SupportTransmittedAttempt {
    var isReplayable: Bool {
        guard !contentRedacted else { return false }
        switch state {
        case .inFlight, .ambiguous: return true
        default: return false
        }
    }
}

private extension SupportMemoryChange {
    var cloudOperation: SupportCloudMemoryOperation {
        get throws {
            switch action {
            case .edit:
                guard let content, let revision = expectedRevision else { throw SupportCloudError.invalidRequest(.emptyValue(field: "memory correction")) }
                return .edit(memoryID: targetID, content: content, category: category.flatMap(SupportCloudMemoryCategory.init(rawValue:)), expectedRevision: revision)
            case .stopUsing: return .stopUsing(memoryID: targetID, expectedRevision: expectedRevision)
            case .resumeUsing: return .resumeUsing(memoryID: targetID, expectedRevision: expectedRevision)
            case .forgetMemory: return .forgetMemory(memoryID: targetID)
            case .forgetCandidate: return .forgetCandidate(fragmentID: targetID)
            case .approveCandidate: return .approveCandidate(fragmentID: targetID, editedContent: content)
            case .dismissCandidate: return .dismissCandidate(fragmentID: targetID)
            }
        }
    }
}
