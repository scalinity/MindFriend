import Foundation
import Combine

enum SupportEntryOrigin: Equatable {
    case today, explore, onboarding
    case chat(conversationID: UUID)
    /// Chat before its first Send: the session exists, its conversation does not yet.
    case chatDraft
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
    @Published private(set) var chatDraftHandoff: SupportChatDraftHandoff?

    private var active = true
    private var observation: Task<Void, Never>?
    private var draftTasks: [UUID: Task<Void, Error>] = [:]
    private var draftGenerations: [UUID: UUID] = [:]
    private var pendingDrafts: [UUID: String] = [:]
    private var invalidation: Task<Void, Never>?
    private let reminders: (any SupportStepReminding)?
    private var reminderGenerations: [UUID: UUID] = [:]
    private var remindersInFlight: Set<UUID> = []

    init(repository: SupportSessionRepository, reminders: (any SupportStepReminding)? = nil) {
        self.reminders = reminders
        self.repository = repository
        identity = repository.identity
        journal = SupportJournal(ownerID: repository.identity.ownerID)
    }

    func load() async throws {
        guard active else { throw SupportSessionError.invalidated }
        let loaded = try await repository.load(epoch: identity.epochID)
        try requireActive()
        installJournal(loaded)
        isLoaded = true
        observation?.cancel()
        let stream = try await repository.updates(epoch: identity.epochID)
        observation = Task { [weak self] in
            for await value in stream {
                guard let self, self.active, !Task.isCancelled else { return }
                self.installJournal(value)
                self.reconcilePresentation()
            }
        }
        await reconcileReminders()
    }

    func refreshJournal() async throws {
        let value = try await repository.currentJournal(epoch: identity.epochID)
        try requireActive()
        installJournal(value)
        reconcilePresentation()
    }

    /// Clear presentation synchronously; an old callback can only reach its old owner repository.
    @discardableResult
    func invalidate() -> Task<Void, Never> {
        if let invalidation { return invalidation }
        active = false
        reminderGenerations.removeAll()
        for activity in journal.activities.values where activity.step?.reminderAt != nil {
            reminders?.cancel(ownerID: identity.ownerID, activityID: activity.id)
        }
        observation?.cancel()
        observation = nil
        draftTasks.values.forEach { $0.cancel() }
        draftTasks.removeAll()
        draftGenerations.removeAll()
        pendingDrafts.removeAll()
        activityPresentation = nil
        chatDraftHandoff = nil
        foregroundSessionID = nil
        journal = SupportJournal(ownerID: identity.ownerID)
        isLoaded = false
        let endedOwner = identity.ownerID
        let task = Task {
            await reminders?.cancelAll(ownerID: endedOwner)
            await repository.invalidate()
        }
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

    func suppressTemplate(_ template: SupportActivityTemplateKey, sessionID: UUID) async throws {
        try await command { try await self.repository.declineTemplate(epoch: self.identity.epochID, sessionID: sessionID, template: template) }
    }

    func acceptProposal(_ proposal: SupportChatProposal, sessionID: UUID, sync: SupportSessionSync, conversationID: UUID) async throws {
        try requireReady()
        guard let expiry = proposal.expiry, expiry > Date() else { throw SupportSessionError.chatContextChanged }
        let activity = try await command {
            try await self.repository.startActivity(epoch: self.identity.epochID, sessionID: sessionID,
                activityID: UUID(), template: proposal.template, initialStatus: .ready,
                acceptedProposalID: proposal.id, suggestedStep: proposal.suggestedStep)
        }
        do {
            try await sync.synchronize()
            try requireActive()
            let current = try await repository.currentJournal(epoch: identity.epochID)
            guard current.activities[activity.id]?.syncStatus == .synced,
                  current.activities[activity.id]?.acceptedProposalID == proposal.id else { throw SupportSessionError.chatContextChanged }
            try await resume(activity.id, origin: .chat(conversationID: conversationID))
        } catch {
            try? await repository.abandonRejectedProposal(epoch: identity.epochID, activityID: activity.id)
            throw error
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

    func setReminder(_ activityID: UUID, at date: Date, timeZoneIdentifier: String) async throws {
        try requireReady()
        guard let reminders else { throw SupportStepReminderError.schedulingFailed }
        guard date.timeIntervalSinceNow > 0 else { throw SupportStepReminderError.invalidDate }
        guard !remindersInFlight.contains(activityID) else { throw SupportStepReminderError.requestInProgress }
        remindersInFlight.insert(activityID)
        defer { remindersInFlight.remove(activityID) }
        let generation = UUID()
        reminderGenerations[activityID] = generation
        try await command {
            try await self.repository.setLocalReminder(epoch: self.identity.epochID, activityID: activityID,
                at: date, timeZoneIdentifier: timeZoneIdentifier, state: .pending)
        }
        reminders.cancel(ownerID: identity.ownerID, activityID: activityID)
        do {
            try await reminders.schedule(ownerID: identity.ownerID, activityID: activityID, at: date)
            try requireActive()
            guard reminderGenerations[activityID] == generation,
                  journal.activities[activityID]?.step?.state == .saved,
                  journal.activities[activityID]?.step?.reminderAt == date else { throw CancellationError() }
            try await command {
                try await self.repository.setLocalReminder(epoch: self.identity.epochID, activityID: activityID,
                    at: date, timeZoneIdentifier: timeZoneIdentifier, state: .scheduled)
            }
        } catch {
            if reminderGenerations[activityID] == generation || reminderGenerations[activityID] == nil {
                reminders.cancel(ownerID: identity.ownerID, activityID: activityID)
            }
            if active, reminderGenerations[activityID] == generation,
               journal.activities[activityID]?.step?.state == .saved,
               journal.activities[activityID]?.step?.reminderAt == date {
                try? await command {
                    try await self.repository.setLocalReminder(epoch: self.identity.epochID, activityID: activityID,
                        at: date, timeZoneIdentifier: timeZoneIdentifier, state: .failed)
                }
            }
            throw error
        }
    }

    func cancelReminder(_ activityID: UUID) async throws {
        reminderGenerations[activityID] = nil
        reminders?.cancel(ownerID: identity.ownerID, activityID: activityID)
        try await command {
            try await self.repository.setLocalReminder(epoch: self.identity.epochID, activityID: activityID,
                at: nil, timeZoneIdentifier: nil, state: nil)
        }
    }

    /// Read existing OS requests after restart; never reschedule or ask permission here.
    private func reconcileReminders() async {
        guard active, let reminders else { return }
        let pending = await reminders.pending(ownerID: identity.ownerID)
        let authorized = await reminders.authorizationAllowsDelivery()
        guard active else { return }
        for (id, _) in pending where journal.activities[id]?.step?.state != .saved || journal.activities[id]?.step?.reminderAt == nil {
            reminders.cancel(ownerID: identity.ownerID, activityID: id)
        }
        for activity in journal.activities.values {
            guard active, let step = activity.step, step.state == .saved, let date = step.reminderAt,
                  let zone = step.reminderTimeZoneIdentifier else { continue }
            let state: SupportReminderState = authorized && date > Date() && pending[activity.id].map { abs($0.timeIntervalSince(date)) < 1 } == true ? .scheduled : .failed
            if !authorized || date <= Date() { reminders.cancel(ownerID: identity.ownerID, activityID: activity.id) }
            if step.reminderState != state {
                try? await command {
                    try await self.repository.setLocalReminder(epoch: self.identity.epochID, activityID: activity.id,
                        at: date, timeZoneIdentifier: zone, state: state)
                }
            }
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

    /// Leaving a finished or paused activity. From Chat the conversation goes on, so its session stays open;
    /// elsewhere this is "Done for now", which closes a session with nothing left in it.
    func leaveActivity(_ presentation: SupportActivityPresentation) async throws {
        switch presentation.origin {
        case .chat, .chatDraft:
            if activityPresentation?.id == presentation.id { activityPresentation = nil }
        case .today, .explore, .onboarding:
            try await doneForNow(presentation.sessionID)
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

    func discussionSnapshot(activityID: UUID) throws -> SupportActivityDiscussionSnapshot {
        try requireReady()
        guard let activity = journal.activities[activityID], let session = journal.sessions[activity.sessionID],
              session.status != .deleted else { throw SupportSessionError.activityNotFound(activityID) }
        return .init(id: UUID(), activityID: activity.id, activityRevision: activity.lastChangedRevision,
            sessionID: session.id, sessionRevision: session.localRevision, sessionIsClosed: session.status == .closed, title: activity.templateKey.title,
            fields: SupportActivityDiscussion.fields(activity), existingDraft: pendingDrafts[session.id] ?? journal.drafts[session.id] ?? "")
    }

    func prepareActivityDiscussion(_ snapshot: SupportActivityDiscussionSnapshot, selected: Set<String>, question: String) async throws -> SupportChatDraftHandoff {
        try await settleDraft(snapshot.sessionID)
        return try await command {
            let handoff = try await self.repository.prepareActivityDiscussion(epoch: self.identity.epochID,
                snapshot: snapshot, selected: selected, question: question)
            try self.requireActive()
            self.foregroundSessionID = handoff.sessionID
            self.chatDraftHandoff = handoff
            self.activityPresentation = nil
            return handoff
        }
    }

    func consumeChatDraftHandoff(_ id: UUID, sessionID: UUID) -> SupportChatDraftHandoff? {
        guard active, let handoff = chatDraftHandoff, handoff.id == id, handoff.sessionID == sessionID else { return nil }
        chatDraftHandoff = nil
        return handoff
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
            installJournal(try await repository.currentJournal(epoch: identity.epochID))
            try requireActive()
            reconcilePresentation()
            localSaveError = nil
            return value
        } catch {
            if active { localSaveError = Self.message(for: error) }
            throw error
        }
    }

    private func installJournal(_ next: SupportJournal) {
        guard next.commitSequence >= journal.commitSequence else { return }
        for activity in journal.activities.values where activity.step?.reminderAt != nil {
            if next.activities[activity.id]?.step?.state != .saved || next.activities[activity.id]?.step?.reminderAt == nil
                || next.sessions[activity.sessionID]?.status != .open {
                reminderGenerations[activity.id] = nil
                reminders?.cancel(ownerID: identity.ownerID, activityID: activity.id)
            }
        }
        journal = next
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
        if let reminder = error as? SupportStepReminderError { return reminder.localizedDescription }
        switch error as? SupportSessionError {
        case .protectedDataUnavailable: return "Unlock this device to save and continue."
        case .journalCorrupt: return "Saved work needs recovery. Its files have been kept on this device."
        case .anotherActivityUnfinished: return "Choose whether to save or end the current activity before starting another."
        case .activityTemplateUnavailable, .unsupportedTemplateVersion: return "This activity needs a compatible version. Its saved work has been kept."
        case .unresolvedConflict: return "Choose which saved version to keep before syncing this session."
        case .recoveryCopiesNeedDecision: return "Earlier recovery files may contain this content. Review the recovery-file choice before removing it."
        case .chatRequestNeedsReconciliation: return "A previous send is still being checked. Resolve it before sending another message."
        case .conversationNotAttached: return "The conversation is not yet attached. Your draft is saved here."
        case .conversationAlreadyAttached: return "This session already belongs to another conversation."
        case .chatContextChanged: return "The shared context changed. Review it before sending again."
        case .invalidReminder: return "Choose a valid future time and time zone for this reminder."
        case .valueTooLong, .checkpointTooLarge: return "This entry is too long to save. Shorten it and try again."
        default: return "This device could not save the change. Keep this screen open and try again."
        }
    }
}
