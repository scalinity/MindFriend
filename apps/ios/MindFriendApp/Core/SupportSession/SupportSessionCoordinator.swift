import Foundation
import Combine

enum SupportEntryOrigin: Equatable {
    case today, explore, onboarding
    case chat(conversationID: UUID)
}

struct SupportActivityPresentation: Identifiable, Equatable {
    let id: UUID
    let sessionID: UUID
    let origin: SupportEntryOrigin
}

/// One foreground session authority for one immutable authenticated account epoch.
@MainActor
final class SupportSessionCoordinator: ObservableObject {
    let identity: SupportSessionIdentity
    let repository: SupportSessionRepository

    @Published private(set) var journal: SupportJournal
    @Published private(set) var isLoaded = false
    @Published private(set) var localSaveError: String?
    @Published private(set) var foregroundSessionID: UUID?
    @Published var activityPresentation: SupportActivityPresentation?

    private var active = true
    private var observation: Task<Void, Never>?
    private var draftTasks: [UUID: Task<Void, Error>] = [:]
    private var draftGenerations: [UUID: UUID] = [:]
    private var pendingDrafts: [UUID: String] = [:]
    private var invalidation: Task<Void, Never>?

    init(repository: SupportSessionRepository) {
        self.repository = repository
        identity = repository.identity
        journal = SupportJournal(ownerID: repository.identity.ownerID)
    }

    func load() async throws {
        guard active else { throw SupportSessionError.invalidated }
        let loaded = try await repository.load(epoch: identity.epochID)
        try requireActive()
        journal = loaded
        isLoaded = true
        observation?.cancel()
        let stream = try await repository.updates(epoch: identity.epochID)
        observation = Task { [weak self] in
            for await value in stream {
                guard let self, self.active, !Task.isCancelled else { return }
                self.journal = value
                self.reconcilePresentation()
            }
        }
    }

    /// Clear presentation synchronously; an old callback can only reach its old owner repository.
    @discardableResult
    func invalidate() -> Task<Void, Never> {
        if let invalidation { return invalidation }
        active = false
        observation?.cancel()
        observation = nil
        draftTasks.values.forEach { $0.cancel() }
        draftTasks.removeAll()
        draftGenerations.removeAll()
        pendingDrafts.removeAll()
        activityPresentation = nil
        foregroundSessionID = nil
        journal = SupportJournal(ownerID: identity.ownerID)
        isLoaded = false
        let task = Task { await repository.invalidate() }
        invalidation = task
        return task
    }

    var openSessions: [SupportSession] {
        journal.sessions.values.filter { $0.status == .open }.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var unfinishedSessions: [SupportSession] {
        openSessions.filter { session in
            !(journal.drafts[session.id] ?? "").isEmpty ||
            journal.activities(in: session.id).contains { $0.status.isUnfinished } ||
            session.conversationID != nil
        }
    }

    var savedSteps: [SupportActivity] {
        journal.activities.values.filter {
            $0.step?.state == .saved && journal.sessions[$0.sessionID]?.status != .deleted
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func createSession(conversationID: UUID? = nil, previousSessionID: UUID? = nil,
                       scope: SupportContextScope = .conversationOnly) async throws -> SupportSession {
        try requireReady()
        if let conversationID, let existing = journal.sessions.values.first(where: {
            $0.conversationID == conversationID && $0.status == .open
        }) {
            foregroundSessionID = existing.id
            return existing
        }
        return try await command {
            let session = try await self.repository.createSession(
                epoch: self.identity.epochID, id: UUID(), conversationID: conversationID,
                previousSessionID: previousSessionID, contextScope: scope)
            try self.requireActive()
            self.foregroundSessionID = session.id
            return session
        }
    }

    func selectSession(_ id: UUID) throws {
        try requireReady()
        guard journal.sessions[id] != nil else { throw SupportSessionError.sessionNotFound(id) }
        foregroundSessionID = id
    }

    @discardableResult
    func start(_ template: SupportActivityTemplateKey, in sessionID: UUID? = nil,
               origin: SupportEntryOrigin, previous: SupportPreviousActivityDisposition? = nil) async throws -> SupportActivity {
        try requireReady()
        let session: SupportSession
        if let sessionID {
            guard let existing = journal.sessions[sessionID] else { throw SupportSessionError.sessionNotFound(sessionID) }
            session = existing
        } else { session = try await createSession() }
        return try await command {
            let activity = try await self.repository.startActivity(
                epoch: self.identity.epochID, sessionID: session.id, activityID: UUID(),
                template: template, previous: previous)
            try self.requireActive()
            self.foregroundSessionID = session.id
            self.activityPresentation = SupportActivityPresentation(id: activity.id, sessionID: session.id, origin: origin)
            return activity
        }
    }

    func resume(_ activityID: UUID, origin: SupportEntryOrigin,
                previous: SupportPreviousActivityDisposition? = nil) async throws {
        try await command {
            let activity = try await self.repository.resumeActivity(
                epoch: self.identity.epochID, activityID: activityID, previous: previous)
            try self.requireActive()
            self.foregroundSessionID = activity.sessionID
            self.activityPresentation = SupportActivityPresentation(id: activityID, sessionID: activity.sessionID, origin: origin)
        }
    }

    func checkpoint(_ activityID: UUID, value: SupportCheckpoint) async throws {
        _ = try await command {
            try await self.repository.checkpointActivity(epoch: self.identity.epochID, activityID: activityID, checkpoint: value)
        }
    }

    func pause(_ activityID: UUID, checkpoint: SupportCheckpoint) async throws {
        try await command {
            try await self.repository.pauseActivity(epoch: self.identity.epochID, activityID: activityID, checkpoint: checkpoint)
            try self.requireActive()
            self.activityPresentation = nil
        }
    }

    func finish(_ activityID: UUID, checkpoint: SupportCheckpoint?, stoppedReason: String? = nil) async throws {
        _ = try await command {
            try await self.repository.finishActivity(
                epoch: self.identity.epochID, activityID: activityID,
                outcome: stoppedReason.map { .stopped(reason: $0) } ?? .completed, checkpoint: checkpoint)
        }
    }

    func chooseStep(_ activityID: UUID, choice: SupportStepChoice, text: String?) async throws {
        _ = try await command {
            try await self.repository.applyStepChoice(
                epoch: self.identity.epochID, activityID: activityID, choice: choice, actionText: text)
        }
    }

    func reflect(_ activityID: UUID, outcome: SupportReflectionOutcome, note: String?, includeAnswers: Bool) async throws {
        _ = try await command {
            try await self.repository.recordReflection(
                epoch: self.identity.epochID, activityID: activityID, outcome: outcome,
                note: note, includeWrittenAnswers: includeAnswers)
        }
    }

    func discardAnswers(_ activityID: UUID) async throws {
        _ = try await command {
            try await self.repository.discardActivityAnswers(epoch: self.identity.epochID, activityID: activityID)
        }
    }

    /// Caller confirms removal of unreadable recovery files, which may contain otherwise unrecoverable work.
    func discardRecoveryCopies() async throws {
        try await command { try await self.repository.discardRecoveryCopies(epoch: self.identity.epochID) }
    }

    func retryDeletion(_ sessionID: UUID) async throws {
        try await command { try await self.repository.retryFailedDeletion(epoch: self.identity.epochID, sessionID: sessionID) }
    }

    func rename(_ sessionID: UUID, title: String) async throws {
        _ = try await command {
            try await self.repository.updateSession(epoch: self.identity.epochID, id: sessionID, title: title)
        }
    }

    func setScope(_ scope: SupportContextScope, sessionID: UUID) async throws {
        _ = try await command {
            try await self.repository.updateSession(epoch: self.identity.epochID, id: sessionID, contextScope: scope)
        }
    }

    func close(_ sessionID: UUID) async throws {
        // The caller first confirms ending unfinished work. Pending draft writes must settle before close scrubs them.
        try await settleDraft(sessionID)
        try await command {
            try await self.repository.closeSession(epoch: self.identity.epochID, id: sessionID)
            try self.requireActive()
            if self.activityPresentation?.sessionID == sessionID { self.activityPresentation = nil }
        }
    }

    func doneForNow(_ sessionID: UUID) async throws {
        try await settleDraft(sessionID)
        try await command {
            _ = try await self.repository.doneForNow(epoch: self.identity.epochID, id: sessionID)
            try self.requireActive()
            if self.activityPresentation?.sessionID == sessionID { self.activityPresentation = nil }
        }
    }

    func delete(_ sessionID: UUID) async throws {
        try await settleDraft(sessionID)
        try await command {
            try await self.repository.deleteSession(epoch: self.identity.epochID, id: sessionID)
            try self.requireActive()
            if self.foregroundSessionID == sessionID { self.foregroundSessionID = nil }
            if self.activityPresentation?.sessionID == sessionID { self.activityPresentation = nil }
        }
    }

    /// Editable offline text remains a draft; this method never queues a chat send.
    func scheduleDraft(_ text: String, sessionID: UUID) {
        guard active, isLoaded, journal.sessions[sessionID]?.status == .open else { return }
        let previous = draftTasks[sessionID]
        previous?.cancel()
        let generation = UUID()
        draftGenerations[sessionID] = generation
        pendingDrafts[sessionID] = text
        draftTasks[sessionID] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                _ = await previous?.result
                try Task.checkCancellation()
                guard let self, self.active, self.draftGenerations[sessionID] == generation else { return }
                try await self.saveDraft(text, sessionID: sessionID)
                if self.draftGenerations[sessionID] == generation { self.pendingDrafts[sessionID] = nil }
            } catch is CancellationError { throw CancellationError() }
            catch {
                if let self, self.active, self.draftGenerations[sessionID] == generation {
                    self.localSaveError = Self.message(for: error)
                }
                throw error
            }
        }
    }

    func flushDraft(_ text: String, sessionID: UUID) async throws {
        pendingDrafts[sessionID] = text
        try await settleDraft(sessionID)
    }

    private func settleDraft(_ sessionID: UUID) async throws {
        let task = draftTasks.removeValue(forKey: sessionID)
        draftGenerations[sessionID] = nil
        task?.cancel()
        _ = await task?.result
        try requireReady()
        if let text = pendingDrafts[sessionID] {
            try await saveDraft(text, sessionID: sessionID)
            if pendingDrafts[sessionID] == text { pendingDrafts[sessionID] = nil }
        }
    }

    private func saveDraft(_ text: String, sessionID: UUID) async throws {
        try await command {
            try await self.repository.setDraft(epoch: self.identity.epochID, sessionID: sessionID, text: text)
        }
    }

    private func command<T>(_ body: () async throws -> T) async throws -> T {
        try requireReady()
        do {
            let value = try await body()
            try requireActive()
            journal = try await repository.currentJournal(epoch: identity.epochID)
            try requireActive()
            reconcilePresentation()
            localSaveError = nil
            return value
        } catch {
            if active { localSaveError = Self.message(for: error) }
            throw error
        }
    }

    private func requireActive() throws {
        guard active else { throw SupportSessionError.invalidated }
    }

    private func clearDraft(_ sessionID: UUID) {
        draftTasks.removeValue(forKey: sessionID)?.cancel()
        draftGenerations[sessionID] = nil
        pendingDrafts[sessionID] = nil
    }

    private func reconcilePresentation() {
        if let id = foregroundSessionID, journal.sessions[id]?.status != .open { foregroundSessionID = nil }
        if let presentation = activityPresentation,
           journal.sessions[presentation.sessionID]?.status != .open ||
            journal.activities[presentation.id] == nil || journal.discardedActivityIDs.contains(presentation.id) {
            activityPresentation = nil
        }
        for id in Array(pendingDrafts.keys) where journal.sessions[id]?.status != .open { clearDraft(id) }
    }

    private func requireReady() throws {
        try requireActive()
        guard isLoaded else { throw SupportSessionError.notLoaded }
    }

    static func message(for error: Error) -> String {
        switch error as? SupportSessionError {
        case .protectedDataUnavailable: return "Unlock this device to save and continue."
        case .journalCorrupt: return "Saved work needs recovery. Its files have been kept on this device."
        case .anotherActivityUnfinished: return "Choose whether to save or end the current activity before starting another."
        case .activityTemplateUnavailable, .unsupportedTemplateVersion: return "This activity needs a compatible version. Its saved work has been kept."
        case .unresolvedConflict: return "Choose which saved version to keep before syncing this session."
        case .recoveryCopiesNeedDecision: return "Earlier recovery files may contain this content. Review the recovery-file choice before removing it."
        case .valueTooLong, .checkpointTooLarge: return "This entry is too long to save. Shorten it and try again."
        default: return "This device could not save the change. Keep this screen open and try again."
        }
    }
}
