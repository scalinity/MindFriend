import Foundation
import Combine

/// Connects voice to the existing account journal and sync driver. Presentation is read-only;
/// only an explicit Start can attach a conversation. Captured calls never acquire a new owner.
@MainActor
final class SessionVoiceAccess: VoiceSupportAccess {
    private let coordinator: SupportSessionCoordinator
    private let sync: SupportSessionSync
    private let ownerID: UUID
    private let accountEpoch: UInt64
    private var sessionID: UUID?
    private let existingConversationID: UUID?
    private var calls: [UUID: (base: Int64, startedAt: Date, sessionRevision: Int64)] = [:]
    private var subscriptions: [UUID: [AnyCancellable]] = [:]
    private let ownerProof: @MainActor () -> Bool
    private let createConversation: @MainActor (UUID) async throws -> Void
    private let ownerChanges: AnyPublisher<Void, Never>

    convenience init?(container: DependencyContainer, appState: AppState, sessionID: UUID? = nil, conversationID: UUID? = nil) {
        guard let coordinator = container.supportSessionCoordinator, let sync = container.supportSync,
              coordinator.identity.ownerID == appState.currentUser?.id,
              container.supportSessionAccountEpoch == appState.accountEpoch else { return nil }
        let owner = coordinator.identity.ownerID, epoch = appState.accountEpoch
        let signals = Publishers.Merge(appState.$accountEpoch.map { _ in () },
            container.$supportSessionCoordinator.map { _ in () }).eraseToAnyPublisher()
        self.init(coordinator: coordinator, sync: sync, ownerID: owner, accountEpoch: epoch,
            sessionID: sessionID, conversationID: conversationID, ownerProof: { [weak container, weak appState] in
                guard let container, let appState else { return false }
                return container.supportSessionCoordinator === coordinator && container.supportSync === sync
                    && container.supportSessionAccountEpoch == epoch && appState.accountEpoch == epoch
                    && appState.currentUser?.id == owner && container.supabaseAuthService.userId == owner
                    && container.supabaseClient.auth.currentSession?.user.id == owner
            }, createConversation: { [weak container] id in
                guard let container else { throw VoiceSupportAccessError.unavailable }
                _ = try await container.supabaseDataService.createConversation(title: nil, id: id, expectedOwner: owner)
            }, ownerChanges: signals)
    }

    init(coordinator: SupportSessionCoordinator, sync: SupportSessionSync, ownerID: UUID, accountEpoch: UInt64,
         sessionID: UUID? = nil, conversationID: UUID? = nil, ownerProof: @escaping @MainActor () -> Bool,
         createConversation: @escaping @MainActor (UUID) async throws -> Void,
         ownerChanges: AnyPublisher<Void, Never>) {
        self.coordinator = coordinator
        self.sync = sync
        self.ownerID = ownerID
        self.accountEpoch = accountEpoch
        self.sessionID = sessionID
        existingConversationID = conversationID
        self.ownerProof = ownerProof
        self.createConversation = createConversation
        self.ownerChanges = ownerChanges
    }

    func preview() -> VoiceSupportPreview {
        let session = sessionID.flatMap { coordinator.journal.sessions[$0] }
        return .init(title: session?.title, scope: session?.contextScope ?? .conversationOnly,
                     conversationWillBeAttached: session?.conversationID == nil)
    }

    var selectedSessionID: UUID? { ownerIsCurrent ? sessionID : nil }
    var attachedConversationID: UUID? {
        guard ownerIsCurrent, let sessionID else { return nil }
        return coordinator.journal.sessions[sessionID]?.conversationID
    }

    func prepare() async throws -> VoiceSupportBinding {
        try requireOwner()
        // Verify the selected route and flush privacy choices before attaching an empty conversation.
        try await sync.retry()
        try requireOwner()
        try await coordinator.refreshJournal()
        guard sync.capabilities?.voiceContextAvailable == true, !coordinator.journal.personalizedCloudPaused else {
            throw VoiceSupportAccessError.contextUnavailable
        }
        let session: SupportSession
        if let id = sessionID, let current = coordinator.journal.sessions[id], current.status == .open {
            session = current
        } else if sessionID == nil {
            session = try await coordinator.createSession(conversationID: existingConversationID, scope: .conversationOnly)
            sessionID = session.id
        } else if let id = sessionID, existingConversationID == nil, coordinator.journal.sessions[id]?.status == .closed {
            // A closed session continues as a new linked session with a conversation of its own:
            // a conversation belongs to one session, and a closed one stays as it was.
            session = try await coordinator.createSession(previousSessionID: id, scope: .conversationOnly)
            sessionID = session.id
        } else { throw VoiceSupportAccessError.unavailable }
        try requireOwner()
        let conversationID: UUID
        if let attached = session.conversationID {
            guard existingConversationID == nil || existingConversationID == attached else { throw VoiceSupportAccessError.sessionMismatch }
            conversationID = attached
        } else {
            conversationID = try await coordinator.repository.reserveConversationID(epoch: coordinator.identity.epochID, sessionID: session.id)
            try await createConversation(conversationID)
            try requireOwner()
            try await coordinator.repository.attachConversation(epoch: coordinator.identity.epochID, sessionID: session.id,
                                                                 conversationID: conversationID)
        }
        try await sync.retry() // Flush acknowledged privacy choices before obtaining current context.
        try requireOwner()
        try await coordinator.refreshJournal()
        guard sync.capabilities?.voiceContextAvailable == true, let privacyRevision = sync.privacyRevision,
              !coordinator.journal.personalizedCloudPaused,
              let current = coordinator.journal.sessions[session.id], current.status == .open,
              current.conversationID == conversationID else { throw VoiceSupportAccessError.contextUnavailable }
        let base = try await coordinator.repository.reserveVoiceTranscriptOrder(epoch: coordinator.identity.epochID, sessionID: session.id)
        try requireOwner()
        let binding = VoiceSupportBinding(ownerUUID: ownerID, accountEpoch: accountEpoch, supportSessionUUID: session.id,
            conversationUUID: conversationID, scope: current.contextScope, privacyRevision: privacyRevision)
        calls[binding.callUUID] = (base, Date(), current.localRevision)
        return binding
    }

    func isCurrent(_ binding: VoiceSupportBinding) -> Bool {
        guard ownerIsCurrent, binding.ownerUUID == ownerID, binding.accountEpoch == accountEpoch,
              let call = calls[binding.callUUID],
              let session = coordinator.journal.sessions[binding.supportSessionUUID],
              session.status == .open, session.conversationID == binding.conversationUUID,
              session.contextScope == binding.scope, session.localRevision == call.sessionRevision,
              !coordinator.journal.personalizedCloudPaused, sync.privacyRevision == binding.privacyRevision else { return false }
        return true
    }

    func appendFinalEvent(_ binding: VoiceSupportBinding, _ event: VoiceTranscriptEvent) async throws {
        try await appendFinalEvent(binding, event, retryRejected: false)
    }

    func retryFinalEvent(_ binding: VoiceSupportBinding, _ event: VoiceTranscriptEvent) async throws {
        try await appendFinalEvent(binding, event, retryRejected: true)
    }

    private func appendFinalEvent(_ binding: VoiceSupportBinding, _ event: VoiceTranscriptEvent, retryRejected: Bool) async throws {
        try Task.checkCancellation()
        guard isCurrent(binding), event.binding == binding else { throw VoiceSupportAppendError.bindingNotCurrent }
        guard event.finality == .final, !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...Int64(SupportSessionLimits.maxPendingTranscriptEvents)).contains(event.order),
              let call = calls[binding.callUUID] else { throw VoiceSupportAppendError.rejected }
        let result: SupportTranscriptAppendResult
        do {
            result = try await coordinator.repository.appendTranscriptEvent(epoch: coordinator.identity.epochID,
                sessionID: binding.supportSessionUUID, conversationID: binding.conversationUUID,
                role: event.role == .user ? .user : .assistant, text: event.text,
                providerEventID: event.providerEventID, isFinal: true, localID: event.localUUID,
                occurredAt: event.occurredAt, orderedSequence: call.base + event.order,
                voiceCallID: binding.callUUID, providerOrder: event.order, providerItemID: event.providerItemID,
                voiceCallStartedAt: call.startedAt)
        } catch let error as SupportSessionError {
            switch error {
            case .invalidated, .staleEpoch, .ownerMismatch, .notLoaded, .sessionNotFound, .sessionNotOpen, .sessionDeleted:
                throw VoiceSupportAppendError.bindingNotCurrent
            case .protectedDataUnavailable, .journalReadFailed, .journalWriteFailed, .journalCorrupt:
                throw VoiceSupportAppendError.retryable
            default: throw VoiceSupportAppendError.rejected
            }
        } catch is CancellationError { throw CancellationError() }
        catch { throw VoiceSupportAppendError.retryable }
        guard ownerIsCurrent else { throw VoiceSupportAppendError.bindingNotCurrent }
        switch result {
        case .persisted(let saved), .duplicate(let saved):
            if saved.syncState == .saved { return }
            if saved.syncState == .rejected {
                guard retryRejected else { throw VoiceSupportAppendError.rejected }
                try await coordinator.repository.retryRejectedTranscriptEvent(epoch: coordinator.identity.epochID, id: saved.id)
            }
            do {
                try await sync.uploadTranscript(saved)
                try requireOwner()
            } catch let error as SupportCloudError {
                if case .rejected = error { throw VoiceSupportAppendError.rejected }
                if case .invalidRequest = error { throw VoiceSupportAppendError.rejected }
                if case .ownerChanged = error { throw VoiceSupportAppendError.bindingNotCurrent }
                if case .cancelled = error { throw CancellationError() }
                throw VoiceSupportAppendError.retryable
            } catch is CancellationError { throw CancellationError() }
            catch VoiceSupportAccessError.ownerMismatch { throw VoiceSupportAppendError.bindingNotCurrent }
            catch { throw VoiceSupportAppendError.retryable }
        case .ignoredPartial: throw VoiceSupportAppendError.rejected
        }
    }

    func reconcile(_ binding: VoiceSupportBinding) async {
        guard ownerIsCurrent, binding.ownerUUID == ownerID, binding.accountEpoch == accountEpoch else { return }
        try? await sync.retry()
    }

    /// Each subscriber owns its stream and cancellation; a view cannot consume the service's signal.
    func invalidations() -> AsyncStream<Void>? {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            var stamp = self.contextStamp
            let changed: () -> Void = { [weak self] in
                guard let self else { continuation.finish(); return }
                let next = self.contextStamp
                if next != stamp { stamp = next; continuation.yield(()) }
            }
            var values = [AnyCancellable]()
            values.append(coordinator.$journal.sink { _ in Task { @MainActor in changed() } })
            values.append(sync.$privacyRevision.sink { _ in Task { @MainActor in changed() } })
            values.append(ownerChanges.sink { _ in Task { @MainActor in changed() } })
            subscriptions[id] = values
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.subscriptions[id] = nil }
            }
        }
    }

    private var ownerIsCurrent: Bool {
        ownerProof()
    }

    private func requireOwner() throws {
        try Task.checkCancellation()
        guard ownerIsCurrent else { throw VoiceSupportAccessError.ownerMismatch }
    }

    private struct ContextStamp: Equatable {
        let current: Bool
        let sessionID: UUID?
        let conversationID: UUID?
        let scope: SupportContextScope?
        let status: SupportSessionStatus?
        let revision: Int64?
        let privacyRevision: Int64?
        let privacyPending: Bool
    }

    private var contextStamp: ContextStamp {
        let session = sessionID.flatMap { coordinator.journal.sessions[$0] }
        return ContextStamp(current: ownerIsCurrent, sessionID: sessionID, conversationID: session?.conversationID,
            scope: session?.contextScope, status: session?.status, revision: session?.localRevision,
            privacyRevision: sync.privacyRevision, privacyPending: coordinator.journal.personalizedCloudPaused)
    }
}
