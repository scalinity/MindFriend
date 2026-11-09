import Foundation

// MARK: - Journal IO (injectable, spec §9.6)

public struct SupportJournalCommitResult: Equatable, Sendable {
    /// False when the primary was durably replaced but the redundant copy could not be refreshed.
    /// The stale copy has then been removed, so no older state can ever be recovered over the newer primary.
    public var backupRefreshed: Bool
    public init(backupRefreshed: Bool) { self.backupRefreshed = backupRefreshed }
}

/// Synchronous, per-owner durable byte storage for the journal. Injectable so tests can fault every step.
///
/// Contract: after `commit` returns (or throws) the redundant copy is either byte-identical to the latest committed
/// primary or absent; it is NEVER an older state. A deletion, discard or privacy suppression therefore cannot be
/// resurrected by recovering from the redundant copy. A failed `commit` leaves the previous primary intact.
public protocol SupportJournalIO: Sendable {
    func loadPrimary(ownerID: UUID) throws -> Data?
    func loadBackup(ownerID: UUID) throws -> Data?
    @discardableResult
    func commit(_ data: Data, ownerID: UUID) throws -> SupportJournalCommitResult
    /// Restore the validated backup without removing it if the replacement fails.
    func restorePrimary(_ data: Data, ownerID: UUID) throws
    /// Only after an explicit choice: unreadable copies may contain otherwise unrecoverable work.
    func discardQuarantine(ownerID: UUID) throws
    /// Move only the unreadable primary aside (keeps a good redundant copy for recovery).
    func quarantinePrimary(ownerID: UUID) throws
    /// Move every unreadable journal file aside (same owner scope) without deleting them.
    func quarantine(ownerID: UUID) throws
    func hasQuarantine(ownerID: UUID) -> Bool
    func removeTemporaryFiles(ownerID: UUID) throws
}

public extension SupportJournalIO {
    func removeTemporaryFiles(ownerID: UUID) throws {}
    func restorePrimary(_ data: Data, ownerID: UUID) throws { _ = try commit(data, ownerID: ownerID) }
    func discardQuarantine(ownerID: UUID) throws {
        if hasQuarantine(ownerID: ownerID) { throw SupportSessionError.recoveryCopiesNeedDecision }
    }
}

/// Thrown by IO implementations when protected storage is locked.
public struct SupportJournalProtectedDataUnavailable: Error, Equatable, Sendable {
    public init() {}
}

/// File-backed journal: `<base>/<ownerUUID>/journal.json` (+ `.bak`, `.corrupt-*`).
/// The base directory is injected and must never be an identity-less shared path; the owner UUID is always a path component.
public struct FileSupportJournalIO: SupportJournalIO {
    /// Real IO phases, exposed so tests can fault each one.
    public enum Phase: Equatable, Sendable {
        case createDirectory, removeStaleBackup
        case writePrimaryTemp, syncPrimaryTemp, replacePrimary
        case writeBackupTemp, syncBackupTemp, replaceBackup
    }

    public let baseDirectory: URL
    private let faultHook: (@Sendable (Phase) throws -> Void)?

    public init(baseDirectory: URL, faultHook: (@Sendable (Phase) throws -> Void)? = nil) {
        self.baseDirectory = baseDirectory
        self.faultHook = faultHook
    }

    private func ownerDirectory(_ ownerID: UUID) -> URL {
        baseDirectory.appendingPathComponent(ownerID.uuidString, isDirectory: true)
    }
    private func primaryURL(_ ownerID: UUID) -> URL { ownerDirectory(ownerID).appendingPathComponent("journal.json") }
    private func backupURL(_ ownerID: UUID) -> URL { ownerDirectory(ownerID).appendingPathComponent("journal.json.bak") }

    private func read(_ url: URL) throws -> Data? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain, ns.code == NSFileReadNoPermissionError {
                throw SupportJournalProtectedDataUnavailable()
            }
            throw error
        }
    }

    public func loadPrimary(ownerID: UUID) throws -> Data? { try read(primaryURL(ownerID)) }
    public func loadBackup(ownerID: UUID) throws -> Data? { try read(backupURL(ownerID)) }

    public func removeTemporaryFiles(ownerID: UUID) throws {
        let fm = FileManager.default
        let dir = ownerDirectory(ownerID)
        guard fm.fileExists(atPath: dir.path) else { return }
        for url in try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        where url.lastPathComponent.hasPrefix(".journal.json.tmp-") || url.lastPathComponent.hasPrefix(".journal.json.bak.tmp-") {
            try fm.removeItem(at: url)
        }
    }

    /// Explicit confirmed account deletion removes all of this owner's local journal copies.
    public func eraseOwner(ownerID: UUID) throws {
        let dir = ownerDirectory(ownerID)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
    }

    public func restorePrimary(_ data: Data, ownerID: UUID) throws {
        // The caller supplies the exact validated backup bytes, so either file remains a valid recovery source.
        try atomicWrite(data, to: primaryURL(ownerID), write: .writePrimaryTemp, sync: .syncPrimaryTemp, replace: .replacePrimary)
    }

    public func discardQuarantine(ownerID: UUID) throws {
        let fm = FileManager.default
        let dir = ownerDirectory(ownerID)
        guard fm.fileExists(atPath: dir.path) else { return }
        for url in try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        where url.lastPathComponent.hasPrefix("journal.json.corrupt-") || url.lastPathComponent.hasPrefix("journal.json.bak.corrupt-") {
            try fm.removeItem(at: url)
        }
    }

    @discardableResult
    public func commit(_ data: Data, ownerID: UUID) throws -> SupportJournalCommitResult {
        let fm = FileManager.default
        let dir = ownerDirectory(ownerID)
        do {
            try faultHook?(.createDirectory)
            var attributes: [FileAttributeKey: Any] = [:]
            #if os(iOS) || os(watchOS) || os(tvOS)
            attributes[.protectionKey] = FileProtectionType.complete
            #endif
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: attributes.isEmpty ? nil : attributes)
            try removeTemporaryFiles(ownerID: ownerID)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDir = dir
            try? mutableDir.setResourceValues(values)  // best-effort hint, not a durability property

            let primary = primaryURL(ownerID)
            let backup = backupURL(ownerID)
            // 1. Drop the redundant copy BEFORE touching the primary: at no instant can an older backup coexist with a newer primary.
            try faultHook?(.removeStaleBackup)
            if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
            // 2. Atomically replace the primary.
            try atomicWrite(data, to: primary, write: .writePrimaryTemp, sync: .syncPrimaryTemp, replace: .replacePrimary)
        } catch {
            throw Self.mapped(error)
        }
        // 3. Refresh the redundant copy with the same latest bytes. Failure here is non-fatal: the primary is already durable,
        //    and the stale copy is gone, so recovery can only ever see "latest" or "nothing".
        do {
            try atomicWrite(data, to: backupURL(ownerID), write: .writeBackupTemp, sync: .syncBackupTemp, replace: .replaceBackup)
            return SupportJournalCommitResult(backupRefreshed: true)
        } catch {
            try? fm.removeItem(at: backupURL(ownerID))
            return SupportJournalCommitResult(backupRefreshed: false)
        }
    }

    private static func mapped(_ error: Error) -> Error {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileWriteNoPermissionError { return SupportJournalProtectedDataUnavailable() }
        return error
    }

    /// Temp file + fsync (errors propagate) + rename, so a crash leaves either the old or the new file, never a torn one.
    private func atomicWrite(_ data: Data, to url: URL, write: Phase, sync: Phase, replace: Phase) throws {
        let fm = FileManager.default
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString.prefix(8))")
        var options: Data.WritingOptions = []
        #if os(iOS) || os(watchOS) || os(tvOS)
        options.insert(.completeFileProtection)
        #endif
        do {
            try faultHook?(write)
            try data.write(to: temp, options: options)
            try faultHook?(sync)
            let handle = try FileHandle(forWritingTo: temp)
            do {
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            try faultHook?(replace)
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: temp)
            } else {
                try fm.moveItem(at: temp, to: url)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    public func quarantinePrimary(ownerID: UUID) throws {
        try move(aside: [primaryURL(ownerID)])
    }

    public func quarantine(ownerID: UUID) throws {
        try move(aside: [primaryURL(ownerID), backupURL(ownerID)])
    }

    private func move(aside urls: [URL]) throws {
        let fm = FileManager.default
        let stamp = Int(Date().timeIntervalSince1970)
        for url in urls where fm.fileExists(atPath: url.path) {
            let target = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)-\(UUID().uuidString.prefix(8))")
            try fm.moveItem(at: url, to: target)
        }
    }

    public func hasQuarantine(ownerID: UUID) -> Bool {
        let dir = ownerDirectory(ownerID)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.contains { $0.contains(".corrupt-") }
    }
}

// MARK: - Repository API types

public enum SupportPreviousActivityDisposition: Equatable, Sendable {
    /// Pause and deselect the previous execution.
    case saveAndPause
    /// Stop the previous execution (reason `replaced`).
    case endPrevious
}

public enum SupportFinishOutcome: Equatable, Sendable {
    case completed
    case stopped(reason: String)
}

public enum SupportDoneForNowResult: Equatable, Sendable {
    case stayedOpen
    case closed
}

public enum SupportTranscriptAppendResult: Equatable, Sendable {
    case persisted(SupportTranscriptEvent)
    case duplicate(SupportTranscriptEvent)
    /// Partial transcripts are never persisted as turns (spec §9.8); the caller keeps them in memory.
    case ignoredPartial
}

/// Server snapshot used by `applyRemoteSession`.
public struct SupportRemoteSessionSnapshot: Equatable, Sendable {
    public var session: SupportSession
    public var activities: [SupportActivity]
    public var revision: Int64
    public var isDeleted: Bool
    public var discardedActivityIDs: Set<UUID>

    public init(session: SupportSession, activities: [SupportActivity], revision: Int64, isDeleted: Bool = false,
                discardedActivityIDs: Set<UUID> = []) {
        self.session = session
        self.activities = activities
        self.revision = revision
        self.isDeleted = isDeleted
        self.discardedActivityIDs = discardedActivityIDs
    }
}

// MARK: - Repository

/// Per-account actor owning the durable support-session journal (spec §9.1, §9.6).
///
/// Guarantees:
/// * Bound to one immutable owner + epoch; every call carries the epoch and fails after `invalidate()`.
/// * Every mutation is built on a copy, encoded, size-checked and written atomically; the in-memory journal and
///   published snapshots change only after the write succeeds. Write failures throw and leave state untouched.
/// * Ordered unsent intents are kept apart from immutable transmitted attempts.
/// * Nothing here ever sends chat text; the outbox carries structured activity mutations only.
public actor SupportSessionRepository {
    public nonisolated let identity: SupportSessionIdentity

    private let io: SupportJournalIO
    private let clock: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID
    private let catalog: SupportTemplateCatalog

    private var journal: SupportJournal
    private var isLoaded = false
    private var isInvalidated = false
    private var allowFreshStartAfterQuarantine = false
    private var continuations: [UUID: AsyncStream<SupportJournal>.Continuation] = [:]

    /// Last persistence error surfaced to the coordinator; cleared by the next successful commit.
    public private(set) var lastPersistenceError: SupportSessionError?
    /// True when the primary was unreadable and the backup was used.
    public private(set) var recoveredFromBackup = false
    /// True when the last commit made the primary durable but could not refresh the redundant copy (it was removed).
    public private(set) var redundantCopyMissing = false

    public init(
        identity: SupportSessionIdentity,
        io: SupportJournalIO,
        clock: @escaping @Sendable () -> Date = { Date() },
        makeID: @escaping @Sendable () -> UUID = { UUID() },
        catalog: SupportTemplateCatalog = .standard
    ) {
        self.catalog = catalog
        self.identity = identity
        self.io = io
        self.clock = clock
        self.makeID = makeID
        self.journal = SupportJournal(ownerID: identity.ownerID)
    }

    // MARK: Lifecycle

    /// Load (or create in memory) the journal. Unreadable files are quarantined, never silently reset.
    /// Recovery from the redundant copy is persisted (primary rewritten) BEFORE the repository reports loaded, so a
    /// second launch without any mutation still succeeds.
    @discardableResult
    public func load(epoch: UUID) throws -> SupportJournal {
        try requireLive(epoch)
        if isLoaded { return journal }
        let owner = identity.ownerID
        _ = try readFile { try self.io.removeTemporaryFiles(ownerID: owner); return nil }
        let primaryData = try readFile { try self.io.loadPrimary(ownerID: owner) }
        let backupData = try readFile { try self.io.loadBackup(ownerID: owner) }
        let primary = primaryData.map { decode($0) }
        let backup = backupData.map { decode($0) }
        for result in [primary, backup] {
            if case .failure(let error)? = result {
                switch error {
                case .ownerMismatch, .unsupportedJournalVersion:
                    throw error  // never touch another owner's / newer-version data
                default: break
                }
            }
        }
        if case .success(let loaded)? = primary {
            journal = Self.normalizedAfterLoad(loaded)
            isLoaded = true
            return journal
        }
        if case .success(let loaded)? = backup {
            if primaryData != nil {
                do { try io.quarantinePrimary(ownerID: owner) } catch { throw SupportSessionError.journalReadFailed(Self.describe(error)) }
            }
            let recovered = Self.normalizedAfterLoad(loaded)
            do { try io.restorePrimary(backupData!, ownerID: owner) }
            catch is SupportJournalProtectedDataUnavailable { throw SupportSessionError.protectedDataUnavailable }
            catch { throw SupportSessionError.journalWriteFailed(Self.describe(error)) }
            journal = recovered
            recoveredFromBackup = true
            isLoaded = true
            return journal
        }
        if primaryData != nil || backupData != nil {
            do { try io.quarantine(ownerID: owner) } catch { throw SupportSessionError.journalReadFailed(Self.describe(error)) }
            throw SupportSessionError.journalCorrupt
        }
        if io.hasQuarantine(ownerID: owner), !allowFreshStartAfterQuarantine {
            throw SupportSessionError.journalCorrupt
        }
        journal = SupportJournal(ownerID: owner)
        if allowFreshStartAfterQuarantine { try persist(journal) }
        isLoaded = true
        return journal
    }

    private func readFile(_ body: () throws -> Data?) throws -> Data? {
        do { return try body() } catch is SupportJournalProtectedDataUnavailable {
            throw SupportSessionError.protectedDataUnavailable
        } catch {
            throw SupportSessionError.journalReadFailed(Self.describe(error))
        }
    }

    /// Explicit recovery decision after `journalCorrupt`: continue with an empty journal. Quarantined files are kept.
    public func startFreshAfterQuarantine(epoch: UUID) throws {
        try requireLive(epoch)
        allowFreshStartAfterQuarantine = true
    }

    /// Account logout / switch: drop in-memory state and reject every later call.
    public func invalidate() {
        isInvalidated = true
        isLoaded = false
        journal = SupportJournal(ownerID: identity.ownerID)
        for continuation in continuations.values { continuation.finish() }
        continuations.removeAll()
    }

    public func isActive(epoch: UUID) -> Bool {
        !isInvalidated && epoch == identity.epochID
    }

    // MARK: Reads and observation

    public func currentJournal(epoch: UUID) throws -> SupportJournal {
        try requireLoaded(epoch)
        return journal
    }

    /// Emits the current journal immediately, then one value per durable commit. Never emits unpersisted state.
    public func updates(epoch: UUID) throws -> AsyncStream<SupportJournal> {
        try requireLoaded(epoch)
        let id = makeID()
        let (stream, continuation) = AsyncStream<SupportJournal>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeContinuation(id) }
        }
        continuation.yield(journal)
        return stream
    }

    private func removeContinuation(_ id: UUID) { continuations[id] = nil }

    public func pendingTranscriptEvents(epoch: UUID, sessionID: UUID? = nil) throws -> [SupportTranscriptEvent] {
        try requireLoaded(epoch)
        return journal.transcriptEvents
            .filter { $0.syncState == .pending && (sessionID == nil || $0.sessionID == sessionID) }
            .sorted { ($0.sessionID.uuidString, $0.sequence) < ($1.sessionID.uuidString, $1.sequence) }
    }

    public func pendingSuppressions(epoch: UUID) throws -> [SupportPrivacySuppression] {
        try requireLoaded(epoch)
        return journal.suppressions.filter { !$0.isAcknowledged }
    }

    // MARK: Sessions

    @discardableResult
    public func createSession(
        epoch: UUID,
        id: UUID,
        title: String? = nil,
        concern: String? = nil,
        conversationID: UUID? = nil,
        previousSessionID: UUID? = nil,
        contextScope: SupportContextScope = .personalized
    ) throws -> SupportSession {
        let cleanTitle = try Self.cleanTitle(title)
        let cleanConcern = try Self.cleanOptional(concern, field: "concern", limit: SupportSessionLimits.concernMaxCharacters)
        return try commit(epoch: epoch) { j, now in
            try self.createSessionLocked(&j, id: id, title: cleanTitle, concern: cleanConcern,
                conversationID: conversationID, previousSessionID: previousSessionID, contextScope: contextScope, now: now)
        }
    }

    private func createSessionLocked(_ j: inout SupportJournal, id: UUID, title cleanTitle: String, concern cleanConcern: String?,
                                     conversationID: UUID?, previousSessionID: UUID?, contextScope: SupportContextScope,
                                     now: Date) throws -> SupportSession {
        if j.tombstones[id] != nil { throw SupportSessionError.sessionDeleted(id) }
        if let existing = j.sessions[id] {
            if existing.title == cleanTitle, existing.concern == cleanConcern, existing.conversationID == conversationID,
               existing.previousSessionID == previousSessionID, existing.contextScope == contextScope { return existing }
            throw SupportSessionError.sessionAlreadyExists(id)
        }
        guard j.sessions.count < SupportSessionLimits.maxSessions else { throw SupportSessionError.capacityExceeded("sessions") }
        let session = SupportSession(
            id: id, ownerID: identity.ownerID, conversationID: conversationID, previousSessionID: previousSessionID,
            selectedActivityID: nil, title: cleanTitle, concern: cleanConcern, status: .open,
            contextScope: contextScope, localRevision: 1, syncStatus: .pending, createdAt: now, updatedAt: now, closedAt: nil)
        j.sessions[id] = session
        try appendEvent(&j, sessionID: id, activityID: nil, kind: .sessionCreated, detail: nil, now: now)
        try enqueue(&j, sessionID: id, payload: .create(title: cleanTitle, concern: cleanConcern, conversationID: conversationID,
            previousSessionID: previousSessionID, contextScope: contextScope), now: now)
        return session
    }

    @discardableResult
    public func updateSession(epoch: UUID, id: UUID, title: String? = nil, contextScope: SupportContextScope? = nil) throws -> SupportSession {
        let cleanTitle = try title.map { try Self.cleanTitle($0) }
        return try commit(epoch: epoch) { j, now in
            var session = try Self.requireSession(j, id, mustBeOpen: false)
            // History may rename a closed session; its context and completed work stay closed.
            if session.status == .closed, contextScope != nil { throw SupportSessionError.sessionNotOpen(id) }
            var changed = false
            if let cleanTitle, cleanTitle != session.title {
                session.title = cleanTitle
                try self.appendEvent(&j, sessionID: id, activityID: nil, kind: .sessionRenamed, detail: nil, now: now)
                changed = true
            }
            if let contextScope, contextScope != session.contextScope {
                session.contextScope = contextScope
                try self.appendEvent(&j, sessionID: id, activityID: nil, kind: .scopeChanged, detail: contextScope.rawValue, now: now)
                changed = true
            }
            guard changed else { return session }
            session.localRevision += 1
            session.updatedAt = now
            j.sessions[id] = session
            try self.enqueue(&j, sessionID: id, payload: .updateSession(title: cleanTitle, contextScope: contextScope, status: nil), now: now)
            return j.sessions[id] ?? session
        }
    }

    /// Atomically preserves the existing draft and prepares selected activity text for a deliberate Chat Send.
    /// This transaction creates neither a cloud conversation nor a pending network request.
    func prepareActivityDiscussion(epoch: UUID, snapshot: SupportActivityDiscussionSnapshot,
                                   selected: Set<String>, question: String) throws -> SupportChatDraftHandoff {
        try commit(epoch: epoch) { j, now in
            let original = try Self.requireSession(j, snapshot.sessionID, mustBeOpen: false)
            let activity = try Self.requireActivity(j, snapshot.activityID)
            guard activity.sessionID == original.id, activity.lastChangedRevision == snapshot.activityRevision,
                  activity.templateKey.title == snapshot.title, original.localRevision == snapshot.sessionRevision,
                  snapshot.sessionIsClosed == (original.status == .closed),
                  SupportActivityDiscussion.fields(activity) == snapshot.fields,
                  (j.drafts[original.id] ?? "") == snapshot.existingDraft else { throw SupportSessionError.chatContextChanged }
            guard selected.isSubset(of: Set(snapshot.fields.map(\.id))) else { throw SupportSessionError.chatContextChanged }
            if let pending = j.pendingChatRequests.values.first(where: { $0.sessionID == original.id }) {
                throw SupportSessionError.chatRequestNeedsReconciliation(pending.id)
            }
            if j.hasUnresolvedConflict(sessionID: original.id) { throw SupportSessionError.unresolvedConflict(original.id) }
            let text = SupportActivityDiscussion.message(title: snapshot.title, fields: snapshot.fields,
                selected: selected, question: question, existingDraft: snapshot.existingDraft)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SupportSessionError.emptyValue(field: "draft") }
            guard text.utf16.count <= SupportSessionLimits.draftMaxCharacters else {
                throw SupportSessionError.valueTooLong(field: "draft", limit: SupportSessionLimits.draftMaxCharacters)
            }
            let target: SupportSession
            if original.status == .closed {
                target = try self.createSessionLocked(&j, id: self.makeID(), title: "Conversation", concern: nil,
                    conversationID: nil, previousSessionID: original.id, contextScope: original.contextScope, now: now)
            } else { target = original }
            j.drafts[target.id] = text
            return SupportChatDraftHandoff(id: self.makeID(), sessionID: target.id, conversationID: target.conversationID, text: text)
        }
    }

    /// Explicit "End unfinished work and close": stops (never completes) unfinished activities, deselects, closes.
    @discardableResult
    public func closeSession(epoch: UUID, id: UUID) throws -> SupportSession {
        try commit(epoch: epoch) { j, now in
            try self.closeLocked(&j, id: id, now: now)
        }
    }

    /// "Done for now": leaves the session open while it has an unfinished activity, saved step or unsent draft; otherwise closes it.
    @discardableResult
    public func doneForNow(epoch: UUID, id: UUID) throws -> SupportDoneForNowResult {
        try commit(epoch: epoch) { j, now in
            let session = try Self.requireSession(j, id)
            let unfinished = j.activities(in: id).contains { $0.status.isUnfinished || $0.step?.state == .saved }
            let hasDraft = !(j.drafts[id] ?? "").isEmpty
            if unfinished || hasDraft { return .stayedOpen }
            _ = session
            _ = try self.closeLocked(&j, id: id, now: now)
            return .closed
        }
    }

    public func setDraft(epoch: UUID, sessionID: UUID, text: String) throws {
        guard text.unicodeScalars.count <= SupportSessionLimits.draftMaxCharacters else {
            throw SupportSessionError.valueTooLong(field: "draft", limit: SupportSessionLimits.draftMaxCharacters)
        }
        try commit(epoch: epoch) { j, _ in
            _ = try Self.requireSession(j, sessionID)
            if text.isEmpty { j.drafts[sessionID] = nil } else { j.drafts[sessionID] = text }
        }
    }

    /// Deletes local content, keeps a content-free tombstone, and queues a server delete only when the server may know the session.
    public func deleteSession(epoch: UUID, id: UUID) throws {
        try requireLoaded(epoch)
        guard !io.hasQuarantine(ownerID: identity.ownerID) else { throw SupportSessionError.recoveryCopiesNeedDecision }
        try commit(epoch: epoch) { j, now in
            if j.tombstones[id] != nil { return }
            guard j.sessions[id] != nil else { throw SupportSessionError.sessionNotFound(id) }
            let serverMayKnow = j.serverRevisions[id] != nil || j.attempts.contains { $0.envelope.sessionID == id }
            self.purge(&j, sessionID: id)  // also redacts any sent attempt: it is reconciled, never replayed
            j.tombstones[id] = SupportSessionTombstone(sessionID: id, deletedAt: now)
            if serverMayKnow {
                j.intents.append(SupportMutationIntent(
                    id: self.makeID(), operationID: self.makeID(), sessionID: id, payload: .deleteSession, createdAt: now, rebaseCount: 0))
            }
        }
    }

    public func declineTemplate(epoch: UUID, sessionID: UUID, template: SupportActivityTemplateKey) throws {
        try commit(epoch: epoch) { j, now in
            _ = try Self.requireSession(j, sessionID)
            guard j.declinedTemplates[sessionID]?.contains(template) != true else { return }
            j.declinedTemplates[sessionID, default: []].insert(template)
            try self.enqueue(&j, sessionID: sessionID, payload: .declineTemplate(template), now: now)
        }
    }

    /// A server-rejected proposal never becomes runnable or earns a canonical completion.
    public func abandonRejectedProposal(epoch: UUID, activityID: UUID) throws {
        try commit(epoch: epoch) { j, now in
            guard var activity = j.activities[activityID], activity.status == .ready,
                  activity.acceptedProposalID != nil, activity.syncStatus == .failed else { return }
            activity.status = .stopped; activity.step = nil; activity.checkpoint.responses = [:]
            activity.result = .init(stoppedReason: "proposal_not_accepted"); activity.finishedAt = now
            j.activities[activityID] = activity
            if j.sessions[activity.sessionID]?.selectedActivityID == activityID { j.sessions[activity.sessionID]?.selectedActivityID = nil }
        }
    }

    // MARK: Activities

    @discardableResult
    public func startActivity(
        epoch: UUID,
        sessionID: UUID,
        activityID: UUID,
        template: SupportActivityTemplateKey,
        templateVersion: Int = 1,
        canonicalReference: SupportCanonicalReference? = nil,
        initialStatus: SupportActivityStatus = .inProgress,
        previous: SupportPreviousActivityDisposition? = nil,
        acceptedProposalID: UUID? = nil, suggestedStep: String? = nil
    ) throws -> SupportActivity {
        guard initialStatus == .inProgress || initialStatus == .ready else {
            throw SupportSessionError.invalidTransition(from: .ready, to: initialStatus)
        }
        guard catalog.supports(template: template, version: templateVersion) else {
            throw SupportSessionError.unsupportedTemplateVersion(template: template.rawValue, version: templateVersion)
        }
        let suggestion = try Self.cleanOptional(suggestedStep, field: "suggestedStep", limit: SupportSessionLimits.stepActionMaxCharacters)
        return try commit(epoch: epoch) { j, now in
            var session = try Self.requireSession(j, sessionID)
            if let acceptedProposalID, let existing = j.activities.values.first(where: { $0.acceptedProposalID == acceptedProposalID }) {
                guard existing.sessionID == sessionID else { throw SupportSessionError.operationIDReused(acceptedProposalID) }
                return existing
            }
            if j.activities[activityID] != nil { throw SupportSessionError.activityAlreadyExists(activityID) }
            guard j.activities(in: sessionID).count < SupportSessionLimits.maxActivitiesPerSession else {
                throw SupportSessionError.capacityExceeded("activities")
            }
            try self.settlePreviousSelection(&j, session: &session, incoming: activityID, disposition: previous, now: now)
            session.localRevision += 1
            session.updatedAt = now
            session.selectedActivityID = activityID
            j.sessions[sessionID] = session
            var activity = SupportActivity(
                id: activityID, sessionID: sessionID, templateKey: template, templateVersion: templateVersion,
                status: initialStatus, canonicalReference: canonicalReference,
                checkpoint: SupportCheckpoint(templateVersion: templateVersion, lastDurableWrite: now), step: nil,
                activeMilliseconds: 0, result: nil, reflection: nil, lastChangedRevision: session.localRevision,
                syncStatus: .pending, createdAt: now, updatedAt: now, finishedAt: nil)
            activity.acceptedProposalID = acceptedProposalID
            if template == .chooseStepV1, let suggestion { activity.checkpoint.responses["action"] = suggestion }
            j.activities[activityID] = activity
            try self.appendEvent(&j, sessionID: sessionID, activityID: activityID, kind: .activityStarted, detail: template.rawValue, now: now)
            if let acceptedProposalID {
                try self.enqueue(&j, sessionID: sessionID, payload: .acceptProposal(proposalID: acceptedProposalID, activityID: activityID), now: now)
            } else {
                try self.enqueue(&j, sessionID: sessionID, payload: .startActivity(
                    activityID: activityID, templateKey: template, templateVersion: templateVersion, canonicalReference: canonicalReference), now: now)
            }
            return activity
        }
    }

    /// Persist an acknowledged step/prompt. Returns only after the durable write; callers must not show "Saved" or advance before this returns.
    @discardableResult
    public func checkpointActivity(
        epoch: UUID,
        activityID: UUID,
        checkpoint: SupportCheckpoint,
        status: SupportActivityStatus = .inProgress
    ) throws -> SupportActivity {
        guard status == .inProgress || status == .paused else {
            throw SupportSessionError.invalidTransition(from: .inProgress, to: status)
        }
        return try commit(epoch: epoch) { j, now in
            var activity = try Self.requireActivity(j, activityID)
            var session = try Self.requireSession(j, activity.sessionID)
            if activity.status.isTerminal { throw SupportSessionError.activityTerminal(activityID) }
            try self.ensureRunnable(activity)
            try self.validate(checkpoint: checkpoint, template: activity.templateKey, templateVersion: activity.templateVersion)
            if status == .inProgress {
                if let selected = session.selectedActivityID, selected != activityID,
                   j.activities[selected]?.status.isUnfinished == true {
                    throw SupportSessionError.anotherActivityUnfinished(selected)
                }
                session.selectedActivityID = activityID
            }
            var cp = checkpoint
            cp.lastDurableWrite = now
            cp.activeMilliseconds = max(cp.activeMilliseconds, activity.checkpoint.activeMilliseconds)
            let wasStatus = activity.status
            activity.status = status
            activity.checkpoint = cp
            activity.activeMilliseconds = cp.activeMilliseconds
            session.localRevision += 1
            session.updatedAt = now
            activity.lastChangedRevision = session.localRevision
            activity.updatedAt = now
            activity.syncStatus = .pending
            j.activities[activityID] = activity
            j.sessions[session.id] = session
            let kind: SupportEventKind = status == .paused && wasStatus != .paused ? .activityPaused
                : (wasStatus == .paused && status == .inProgress ? .activityResumed : .checkpointSaved)
            try self.appendEvent(&j, sessionID: session.id, activityID: activityID, kind: kind, detail: nil, now: now)
            try self.enqueue(&j, sessionID: session.id, payload: .checkpointActivity(
                activityID: activityID, status: status, checkpoint: cp, step: activity.step), now: now)
            return activity
        }
    }

    /// Save checkpoint and leave: pauses (keeps selected so Today can offer "continue from step N").
    @discardableResult
    public func pauseActivity(epoch: UUID, activityID: UUID, checkpoint: SupportCheckpoint) throws -> SupportActivity {
        try checkpointActivity(epoch: epoch, activityID: activityID, checkpoint: checkpoint, status: .paused)
    }

    /// Explicit resume of a paused/ready execution. A different unfinished selection requires an explicit disposition.
    @discardableResult
    public func resumeActivity(epoch: UUID, activityID: UUID, previous: SupportPreviousActivityDisposition? = nil) throws -> SupportActivity {
        try commit(epoch: epoch) { j, now in
            var activity = try Self.requireActivity(j, activityID)
            var session = try Self.requireSession(j, activity.sessionID)
            if activity.status.isTerminal { throw SupportSessionError.activityTerminal(activityID) }
            try self.ensureRunnable(activity)
            if activity.status == .inProgress { return activity }
            try self.settlePreviousSelection(&j, session: &session, incoming: activityID, disposition: previous, now: now)
            let wasReady = activity.status == .ready
            session.selectedActivityID = activityID
            session.localRevision += 1
            session.updatedAt = now
            activity.status = .inProgress
            activity.lastChangedRevision = session.localRevision
            activity.updatedAt = now
            activity.syncStatus = .pending
            j.activities[activityID] = activity
            j.sessions[session.id] = session
            try self.appendEvent(&j, sessionID: session.id, activityID: activityID, kind: wasReady ? .activityStarted : .activityResumed, detail: nil, now: now)
            try self.enqueue(&j, sessionID: session.id, payload: .checkpointActivity(
                activityID: activityID, status: .inProgress, checkpoint: activity.checkpoint, step: activity.step), now: now)
            return activity
        }
    }

    /// Finish an activity. Grounding with only skipped prompts becomes `stopped(skipped_all)` (no canonical completion).
    @discardableResult
    public func finishActivity(
        epoch: UUID,
        activityID: UUID,
        outcome: SupportFinishOutcome,
        checkpoint: SupportCheckpoint? = nil,
        shareableNote: String? = nil
    ) throws -> SupportActivity {
        let note = try Self.cleanOptional(shareableNote, field: "shareableNote", limit: SupportSessionLimits.shareableNoteMaxCharacters)
        return try commit(epoch: epoch) { j, now in
            var activity = try Self.requireActivity(j, activityID)
            if activity.status.isTerminal { throw SupportSessionError.activityTerminal(activityID) }
            var completing = false
            if case .completed = outcome { completing = true }
            if completing || checkpoint != nil { try self.ensureRunnable(activity) }
            if let checkpoint {
                try self.validate(checkpoint: checkpoint, template: activity.templateKey, templateVersion: activity.templateVersion)
            }
            return try self.finishLocked(&j, activity: &activity, outcome: outcome, checkpoint: checkpoint, note: note, now: now)
        }
    }

    /// "Choose one next step" adapter. saveForLater→paused+saved, didIt→completed+self_reported_done, notNow→stopped+dismissed (no saved row).
    @discardableResult
    public func applyStepChoice(epoch: UUID, activityID: UUID, choice: SupportStepChoice, actionText: String? = nil) throws -> SupportActivity {
        let trimmed = actionText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, trimmed.unicodeScalars.count > SupportSessionLimits.stepActionMaxCharacters {
            throw SupportSessionError.valueTooLong(field: "actionText", limit: SupportSessionLimits.stepActionMaxCharacters)
        }
        return try commit(epoch: epoch) { j, now in
            var activity = try Self.requireActivity(j, activityID)
            guard activity.kind == .chooseStep else { throw SupportSessionError.templateKindMismatch }
            if activity.status.isTerminal { throw SupportSessionError.activityTerminal(activityID) }
            var session = try Self.requireSession(j, activity.sessionID)
            if choice != .notNow { try self.ensureRunnable(activity) }
            switch choice {
            case .saveForLater:
                let text = (trimmed?.isEmpty == false ? trimmed : activity.step?.actionText) ?? ""
                guard !text.isEmpty else { throw SupportSessionError.emptyValue(field: "actionText") }
                var step = activity.step ?? SupportStepPayload(actionText: text, state: .saved)
                step.actionText = text
                step.state = .saved
                activity.step = step
                activity.status = .paused
                session.localRevision += 1
                session.updatedAt = now
                activity.lastChangedRevision = session.localRevision
                activity.updatedAt = now
                activity.syncStatus = .pending
                j.activities[activityID] = activity
                j.sessions[session.id] = session
                try self.appendEvent(&j, sessionID: session.id, activityID: activityID, kind: .stepSaved, detail: nil, now: now)
                try self.enqueue(&j, sessionID: session.id, payload: .checkpointActivity(
                    activityID: activityID, status: .paused, checkpoint: activity.checkpoint, step: step), now: now)
                return activity
            case .didIt:
                let text = (trimmed?.isEmpty == false ? trimmed : activity.step?.actionText) ?? ""
                guard !text.isEmpty else { throw SupportSessionError.emptyValue(field: "actionText") }
                let step = SupportStepPayload(
                    actionText: text, state: .selfReportedDone, reminderAt: nil, reminderTimeZoneIdentifier: nil, confirmedAt: now)
                activity.step = step
                return try self.finishLocked(&j, activity: &activity, outcome: .completed, checkpoint: nil, note: nil, now: now, step: step)
            case .notNow:
                let step = SupportStepPayload(actionText: "", state: .dismissed, confirmedAt: now)
                activity.step = nil
                return try self.finishLocked(&j, activity: &activity, outcome: .stopped(reason: "not_now"), checkpoint: nil, note: nil, now: now, step: step)
            }
        }
    }

    /// A notification belongs only to this device. This metadata creates no cloud mutation.
    public func setLocalReminder(epoch: UUID, activityID: UUID, at: Date?, timeZoneIdentifier: String?, state: SupportReminderState?) throws {
        try commit(epoch: epoch) { j, _ in
            var activity = try Self.requireActivity(j, activityID)
            _ = try Self.requireSession(j, activity.sessionID)
            guard activity.kind == .chooseStep, var step = activity.step, step.state == .saved,
                  activity.status.isUnfinished else { throw SupportSessionError.invalidTransition(from: activity.status, to: .paused) }
            if let at {
                guard at.timeIntervalSince1970.isFinite, let timeZoneIdentifier,
                      TimeZone(identifier: timeZoneIdentifier) != nil, state != nil else {
                    throw SupportSessionError.invalidReminder
                }
            }
            step.reminderAt = at
            step.reminderTimeZoneIdentifier = at == nil ? nil : timeZoneIdentifier
            step.reminderState = at == nil ? nil : state
            activity.step = step
            j.activities[activityID] = activity
        }
    }

    @discardableResult
    public func recordReflection(
        epoch: UUID,
        activityID: UUID,
        outcome: SupportReflectionOutcome,
        note: String? = nil,
        includeWrittenAnswers: Bool = false
    ) throws -> SupportActivity {
        let cleanNote = try Self.cleanOptional(note, field: "note", limit: SupportSessionLimits.reflectionNoteMaxCharacters)
        return try commit(epoch: epoch) { j, now in
            var activity = try Self.requireActivity(j, activityID)
            var session = try Self.requireSession(j, activity.sessionID, mustBeOpen: false)
            guard activity.status.isTerminal else { throw SupportSessionError.invalidTransition(from: activity.status, to: .completed) }
            let preview = includeWrittenAnswers ? SupportActivityDiscussion.reflectionPreview(activity, note: cleanNote ?? "") : ""
            let reflection = SupportReflection(outcome: outcome, note: cleanNote, includeWrittenAnswers: includeWrittenAnswers,
                recordedAt: now, shareableText: preview.isEmpty ? nil : preview)
            activity.reflection = reflection
            session.localRevision += 1
            session.updatedAt = now
            activity.lastChangedRevision = session.localRevision
            activity.updatedAt = now
            activity.syncStatus = .pending
            j.activities[activityID] = activity
            j.sessions[session.id] = session
            try self.appendEvent(&j, sessionID: session.id, activityID: activityID, kind: .reflected, detail: outcome.rawValue, now: now)
            try self.enqueue(&j, sessionID: session.id, payload: .recordReflection(activityID: activityID, reflection: reflection), now: now)
            return activity
        }
    }

    /// "Discard this reflection": scrubs answer drafts, the checkpoint, reflection and queued unsent copies locally, and
    /// queues a typed idempotent `discard_activity_answers` mutation so the server scrub also happens when the activity is
    /// already terminal or its answers were already sent. Unfinished activities are then stopped with a content-free
    /// `discarded` finish (no checkpoint). Already-transmitted envelopes are never edited: they replay unchanged, and the
    /// scrub is released only after they resolve (one unresolved attempt per session), so the scrub always lands last.
    /// A rebase of a superseded content-bearing attempt is sanitized/dropped (see `rebaseConflictedAttempt`).
    @discardableResult
    public func discardActivityAnswers(epoch: UUID, activityID: UUID) throws -> SupportActivity {
        try requireLoaded(epoch)
        guard !io.hasQuarantine(ownerID: identity.ownerID) else { throw SupportSessionError.recoveryCopiesNeedDecision }
        return try commit(epoch: epoch) { j, now in
            var activity = try Self.requireActivity(j, activityID)
            var session = try Self.requireSession(j, activity.sessionID, mustBeOpen: false)
            j.intents.removeAll { intent in
                guard intent.payload.targetActivityID == activityID else { return false }
                switch intent.payload.kind {
                case .checkpointActivity, .recordReflection: return true
                default: return false
                }
            }
            for i in j.intents.indices {
                if case .finishActivity(let id, let status, var result, _, _) = j.intents[i].payload, id == activityID {
                    result.shareableNote = nil
                    j.intents[i].payload = .finishActivity(activityID: id, status: status, result: result, step: nil, checkpoint: nil)
                }
            }
            activity.checkpoint = SupportCheckpoint(
                templateVersion: activity.checkpoint.templateVersion, activeMilliseconds: activity.checkpoint.activeMilliseconds, lastDurableWrite: now)
            activity.result?.shareableNote = nil
            activity.reflection = nil
            activity.step = nil
            j.discardedActivityIDs.insert(activityID)
            self.redactActivityAttempts(&j, activityID: activityID)
            let target = activityID.uuidString.lowercased()
            if !j.suppressions.contains(where: { $0.kind == .derivedRecord && $0.targetID == target && !$0.isAcknowledged }) {
                j.suppressions.append(.init(id: self.makeID(), kind: .derivedRecord, targetID: target, createdAt: now, acknowledgedPrivacyRevision: nil))
            }
            for i in j.conflicts.indices {
                j.conflicts[i].remoteActivities = j.conflicts[i].remoteActivities.map {
                    $0.id == activityID ? Self.scrubbedAnswers($0) : $0
                }
            }
            session.localRevision += 1
            session.updatedAt = now
            activity.lastChangedRevision = session.localRevision
            activity.updatedAt = now
            activity.syncStatus = .pending
            j.activities[activityID] = activity
            j.sessions[session.id] = session
            try self.enqueue(&j, sessionID: session.id, payload: .discardActivityAnswers(activityID: activityID), now: now)
            if activity.status.isUnfinished {
                var a = activity
                return try self.finishLocked(
                    &j, activity: &a, outcome: .stopped(reason: "discarded"), checkpoint: nil, note: nil, now: now,
                    kind: .activityDiscarded, includeCheckpoint: false)
            }
            try self.appendEvent(&j, sessionID: session.id, activityID: activityID, kind: .activityDiscarded, detail: nil, now: now)
            return activity
        }
    }

    /// Reserve the canonical ID only on deliberate Send. This is not an attachment and cannot
    /// make automatic session sync reference a conversation whose insert is still unconfirmed.
    public func reserveConversationID(epoch: UUID, sessionID: UUID) throws -> UUID {
        try commit(epoch: epoch) { j, _ in
            let session = try Self.requireSession(j, sessionID)
            if let id = session.conversationID ?? j.reservedConversationIDs[sessionID] { return id }
            let id = self.makeID()
            j.reservedConversationIDs[sessionID] = id
            return id
        }
    }

    /// Attach only an acknowledged, owned cloud conversation. Unsent create may be rewritten;
    /// a transmitted create keeps its exact bytes and receives a later attachment operation.
    public func attachConversation(epoch: UUID, sessionID: UUID, conversationID: UUID) throws {
        try commit(epoch: epoch) { j, now in
            var session = try Self.requireSession(j, sessionID)
            if session.conversationID == conversationID { return }
            guard session.conversationID == nil,
                  !j.sessions.values.contains(where: { $0.id != sessionID && $0.conversationID == conversationID }) else {
                throw SupportSessionError.conversationAlreadyAttached
            }
            session.conversationID = conversationID
            j.reservedConversationIDs[sessionID] = nil
            session.localRevision += 1
            session.updatedAt = now
            session.syncStatus = .pending
            j.sessions[sessionID] = session
            if let index = j.intents.firstIndex(where: { $0.sessionID == sessionID && $0.payload.kind == .create }),
               case .create(let title, let concern, _, let previous, let scope) = j.intents[index].payload {
                j.intents[index].payload = .create(title: title, concern: concern, conversationID: conversationID,
                    previousSessionID: previous, contextScope: scope)
            } else {
                try self.enqueue(&j, sessionID: sessionID, payload: .attachConversation(conversationID: conversationID), now: now)
            }
        }
    }

    public func prepareChatRequest(epoch: UUID, sessionID: UUID, requestID: UUID, content: String,
                                   scope: SupportContextScope, privacyRevision: Int64) throws -> SupportPendingChatRequest {
        guard content.utf16.count <= SupportSessionLimits.draftMaxCharacters else {
            throw SupportSessionError.valueTooLong(field: "message", limit: SupportSessionLimits.draftMaxCharacters)
        }
        guard let text = try Self.cleanOptional(content, field: "message", limit: SupportSessionLimits.draftMaxCharacters) else {
            throw SupportSessionError.emptyValue(field: "message")
        }
        return try commit(epoch: epoch) { j, now in
            let session = try Self.requireSession(j, sessionID)
            guard let conversationID = session.conversationID else { throw SupportSessionError.conversationNotAttached }
            guard privacyRevision >= 1, session.contextScope == scope else { throw SupportSessionError.chatContextChanged }
            if let existing = j.pendingChatRequests[requestID] {
                guard existing.sessionID == sessionID, existing.conversationID == conversationID, existing.content == text,
                      existing.scope == scope, existing.privacyRevision == privacyRevision else { throw SupportSessionError.operationIDReused(requestID) }
                return existing
            }
            if let pending = j.pendingChatRequests.values.first(where: { $0.sessionID == sessionID }) {
                throw SupportSessionError.chatRequestNeedsReconciliation(pending.id)
            }
            let request = SupportPendingChatRequest(id: requestID, sessionID: sessionID, conversationID: conversationID,
                content: text, scope: scope, privacyRevision: privacyRevision, createdAt: now)
            j.pendingChatRequests[requestID] = request
            j.drafts[sessionID] = nil
            return request
        }
    }

    public func settleChatRequest(epoch: UUID, requestID: UUID, rejectedBeforeSend: Bool = false) throws {
        try commit(epoch: epoch) { j, _ in
            guard let request = j.pendingChatRequests.removeValue(forKey: requestID) else { return }
            if rejectedBeforeSend, j.drafts[request.sessionID] == nil { j.drafts[request.sessionID] = request.content }
        }
    }

    // MARK: Outbox

    /// Next envelope to transmit, or nil. Replays an ambiguous attempt (identical wire envelope) before freezing a new unsent intent.
    /// With `requirePrivacyFlushed` (default) nothing is released while privacy mutations are unacknowledged (spec §8.5).
    public func nextEnvelopeToSend(epoch: UUID, requirePrivacyFlushed: Bool = true) throws -> SupportMutationEnvelope? {
        try requireLoaded(epoch)
        if requirePrivacyFlushed && journal.personalizedCloudPaused { return nil }
        if let replay = journal.nextReplayableAttempt {
            let envelope = replay.envelope
            try commit(epoch: epoch) { j, _ in
                guard let i = j.attempts.firstIndex(where: { $0.id == envelope.operationID }) else { return }
                j.attempts[i].state = .inFlight
                j.attempts[i].transmissionCount += 1
            }
            return envelope
        }
        // One unresolved attempt per session, and no new mutation base while a remote conflict is unresolved.
        guard let intent = journal.nextSendableIntent else { return nil }
        let expected: Int64? = intent.payload.kind == .create ? nil : journal.serverRevisions[intent.sessionID]
        let envelope = SupportMutationEnvelope(
            schemaVersion: SupportSessionLimits.schemaVersion, operationID: intent.operationID, sessionID: intent.sessionID,
            expectedRevision: expected, kind: intent.payload.kind, payload: intent.payload,
            payloadFingerprint: SupportFingerprint.fingerprint(intent.payload, sessionID: intent.sessionID))
        try commit(epoch: epoch) { j, now in
            guard let i = j.intents.firstIndex(where: { $0.id == intent.id }) else { return }
            j.intents.remove(at: i)
            j.attempts.append(SupportTransmittedAttempt(
                intentID: intent.id, envelope: envelope, state: .inFlight, firstTransmittedAt: now,
                transmissionCount: 1, rebaseCount: intent.rebaseCount))
        }
        return envelope
    }

    /// Sent attempts of deleted sessions: their outcome is unknown and they must be reconciled by querying the server
    /// (`get`), then reported through `resolveAttempt`. They are never replayed.
    public func reconciliationAttempts(epoch: UUID) throws -> [SupportTransmittedAttempt] {
        try requireLoaded(epoch)
        return journal.attempts.filter { $0.contentRedacted }
    }

    /// A redacted request is never replayed. A current server snapshot supplies the base for the
    /// following erasure; an identifier-only diagnostic preserves that its original outcome is unknown.
    public func adoptServerStateForErasure(epoch: UUID, operationID: UUID, revision: Int64?) throws {
        try commit(epoch: epoch) { j, now in
            guard let index = j.attempts.firstIndex(where: { $0.id == operationID }), j.attempts[index].contentRedacted else { return }
            let old = j.attempts.remove(at: index)
            guard j.tombstones[old.envelope.sessionID] != nil || old.envelope.payload.targetActivityID.map({ j.discardedActivityIDs.contains($0) }) == true else {
                throw SupportSessionError.invalidTransition(from: .inProgress, to: .stopped)
            }
            j.erasedUnknownRequests.append(.init(operationID: old.id, sessionID: old.envelope.sessionID, kind: old.envelope.kind,
                observedServerRevision: revision, recordedAt: now))
            if let revision { j.serverRevisions[old.envelope.sessionID] = max(revision, j.serverRevisions[old.envelope.sessionID] ?? 0) }
            else if j.tombstones[old.envelope.sessionID] != nil {
                j.serverRevisions[old.envelope.sessionID] = nil
                j.intents.removeAll { $0.sessionID == old.envelope.sessionID && $0.payload.kind == .deleteSession }
            }
        }
    }

    /// Record the definite or ambiguous outcome of a transmitted attempt.
    public func resolveAttempt(epoch: UUID, operationID: UUID, outcome: SupportAttemptOutcome) throws {
        try commit(epoch: epoch) { j, now in
            guard let index = j.attempts.firstIndex(where: { $0.id == operationID }) else {
                throw SupportSessionError.unknownAttempt(operationID)
            }
            let attempt = j.attempts[index]
            let sessionID = attempt.envelope.sessionID
            switch outcome {
            case .confirmed(let revision):
                j.attempts.remove(at: index)
                if attempt.envelope.kind == .deleteSession {
                    j.serverRevisions[sessionID] = nil
                    j.failures.removeAll { $0.sessionID == sessionID && $0.kind == .deleteSession }
                }
                if attempt.envelope.kind != .deleteSession {
                    j.serverRevisions[sessionID] = max(revision, j.serverRevisions[sessionID] ?? 0)
                }
                self.refreshSync(&j, sessionID: sessionID, clearFailed: true)
            case .revisionConflict(let current):
                if attempt.contentRedacted || j.tombstones[sessionID] != nil {
                    // Deleted locally: never rebase (that would re-publish content). Adopt the base so the delete can follow.
                    j.attempts.remove(at: index)
                    j.serverRevisions[sessionID] = max(current, j.serverRevisions[sessionID] ?? 0)
                    if attempt.envelope.kind == .deleteSession {
                        j.intents.insert(SupportMutationIntent(id: attempt.intentID, operationID: self.makeID(),
                            sessionID: sessionID, payload: .deleteSession, createdAt: now,
                            rebaseCount: attempt.rebaseCount + 1), at: 0)
                    }
                } else {
                    j.attempts[index].state = .rejectedConflict(currentRevision: current)
                    self.refreshSync(&j, sessionID: sessionID, clearFailed: false)
                }
            case .rejected(let code):
                j.attempts.remove(at: index)
                if (attempt.contentRedacted || j.tombstones[sessionID] != nil),
                   code == "NOT_FOUND", (attempt.envelope.kind == .deleteSession || j.serverRevisions[sessionID] == nil) {
                    // Only authoritative absence proves that no delete is necessary. A rejected update does not.
                    j.intents.removeAll { $0.sessionID == sessionID && $0.payload.kind == .deleteSession }
                    j.serverRevisions[sessionID] = nil
                    if attempt.envelope.kind == .deleteSession {
                        j.failures.removeAll { $0.sessionID == sessionID && $0.kind == .deleteSession }
                        return
                    }
                }
                j.failures.append(SupportSyncFailure(
                    operationID: operationID, sessionID: sessionID, kind: attempt.envelope.kind, code: String(code.prefix(64)), at: now))
                if j.failures.count > SupportSessionLimits.maxFailureRecords {
                    j.failures.removeFirst(j.failures.count - SupportSessionLimits.maxFailureRecords)
                }
                if var s = j.sessions[sessionID] { s.syncStatus = .failed; j.sessions[sessionID] = s }
                for a in j.activities(in: sessionID) { var copy = a; copy.syncStatus = .failed; j.activities[a.id] = copy }
            case .transientFailure:
                j.attempts[index].state = .ambiguous
            }
        }
    }

    /// A definite rejection needs a deliberate retry; unknown outcomes retain their original operation ID instead.
    public func retryFailedDeletion(epoch: UUID, sessionID: UUID) throws {
        try commit(epoch: epoch) { j, now in
            guard j.tombstones[sessionID] != nil,
                  j.failures.contains(where: { $0.sessionID == sessionID && $0.kind == .deleteSession }),
                  !j.attempts.contains(where: { $0.envelope.sessionID == sessionID }),
                  !j.intents.contains(where: { $0.sessionID == sessionID }) else { return }
            j.intents.append(SupportMutationIntent(id: self.makeID(), operationID: self.makeID(),
                sessionID: sessionID, payload: .deleteSession, createdAt: now, rebaseCount: 0))
            j.failures.removeAll { $0.sessionID == sessionID && $0.kind == .deleteSession }
        }
    }

    /// After a definite 409, create a compatible rebased intent with a NEW operation ID and the current expected revision.
    /// `replacementPayload` lets the coordinator re-express the intent against the newer snapshot; the old attempt is discarded.
    @discardableResult
    public func rebaseConflictedAttempt(
        epoch: UUID,
        operationID: UUID,
        newOperationID: UUID? = nil,
        replacementPayload: SupportMutationPayload? = nil
    ) throws -> SupportMutationIntent? {
        try commit(epoch: epoch) { j, now in
            guard let index = j.attempts.firstIndex(where: { $0.id == operationID }) else {
                throw SupportSessionError.unknownAttempt(operationID)
            }
            let attempt = j.attempts[index]
            guard case .rejectedConflict(let current) = attempt.state else { throw SupportSessionError.attemptNotRejected(operationID) }
            if j.hasUnresolvedConflict(sessionID: attempt.envelope.sessionID) {
                throw SupportSessionError.unresolvedConflict(attempt.envelope.sessionID)
            }
            let newID = newOperationID ?? self.makeID()
            if j.intents.contains(where: { $0.operationID == newID }) || j.attempts.contains(where: { $0.id == newID }) {
                throw SupportSessionError.operationIDReused(newID)
            }
            var payload = replacementPayload ?? attempt.envelope.payload
            // A queued scrub supersedes content in a rejected attempt: never resurrect it ahead of the scrub.
            if let target = payload.targetActivityID,
               j.intents.contains(where: { $0.sessionID == attempt.envelope.sessionID && $0.payload == .discardActivityAnswers(activityID: target) }) {
                switch payload {
                case .checkpointActivity, .recordReflection:
                    j.attempts.remove(at: index)
                    j.serverRevisions[attempt.envelope.sessionID] = max(current, j.serverRevisions[attempt.envelope.sessionID] ?? 0)
                    self.refreshSync(&j, sessionID: attempt.envelope.sessionID, clearFailed: false)
                    return nil
                case .finishActivity(let id, let status, var result, _, _):
                    result.shareableNote = nil
                    payload = .finishActivity(activityID: id, status: status, result: result, step: nil, checkpoint: nil)
                default: break
                }
            }
            let intent = SupportMutationIntent(
                id: attempt.intentID, operationID: newID, sessionID: attempt.envelope.sessionID,
                payload: payload, createdAt: now, rebaseCount: attempt.rebaseCount + 1)
            j.attempts.remove(at: index)
            j.serverRevisions[attempt.envelope.sessionID] = max(current, j.serverRevisions[attempt.envelope.sessionID] ?? 0)
            j.intents.insert(intent, at: 0)
            self.refreshSync(&j, sessionID: attempt.envelope.sessionID, clearFailed: false)
            return intent
        }
    }

    // MARK: Remote reconciliation

    /// Merge a server snapshot without ever silently overwriting local work:
    /// * tombstones and remote deletions win; completed/stopped never regress;
    /// * unsent/unconfirmed local activity changes are preserved; a differing remote terminal status, differing
    ///   user-authored step text, or competing selected/in-progress executions are retained as `SupportRemoteConflict`
    ///   (remote version kept) and the session's server revision does NOT advance until `resolveConflict`;
    /// * local drafts and unsent intents survive.
    public func applyRemoteSession(epoch: UUID, remote: SupportRemoteSessionSnapshot) throws {
        let id = remote.session.id
        guard remote.session.ownerID == identity.ownerID else { throw SupportSessionError.ownerMismatch }
        try commit(epoch: epoch) { j, now in
            var remote = remote
            for target in remote.discardedActivityIDs {
                j.discardedActivityIDs.insert(target)
                j.intents.removeAll { $0.payload.targetActivityID == target }
                if let incoming = remote.activities.first(where: { $0.id == target }) { j.activities[target] = Self.scrubbedAnswers(incoming) }
                self.redactActivityAttempts(&j, activityID: target)
                for index in j.conflicts.indices {
                    j.conflicts[index].remoteActivities = j.conflicts[index].remoteActivities.map { $0.id == target ? Self.scrubbedAnswers($0) : $0 }
                }
            }
            remote.activities = remote.activities.map { j.discardedActivityIDs.contains($0.id) ? Self.scrubbedAnswers($0) : $0 }
            if j.tombstones[id] != nil { return }
            if remote.isDeleted {
                self.purge(&j, sessionID: id)
                j.tombstones[id] = SupportSessionTombstone(sessionID: id, deletedAt: now)
                return
            }
            let existing = j.conflicts.filter { $0.sessionID == id }
            if let known = j.serverRevisions[id], remote.revision <= known, existing.isEmpty { return }
            if let top = existing.map(\.remoteRevision).max(), remote.revision <= top { return }

            let sessionIntents = j.intents.filter { $0.sessionID == id }
            let sessionAttempts = j.attempts.filter { $0.envelope.sessionID == id }
            let hasPending = !sessionIntents.isEmpty || !sessionAttempts.isEmpty
            let inFlight = !sessionAttempts.isEmpty
            let pendingActs = Set(sessionIntents.compactMap { $0.payload.targetActivityID } + sessionAttempts.compactMap { $0.envelope.payload.targetActivityID })
            let local = j.sessions[id]

            var merged = remote.session
            if let local {
                if hasPending { merged = local } else { merged.localRevision = max(local.localRevision, remote.session.localRevision) }
            }

            var detected: [(kind: SupportConflictKind, activityID: UUID?, remote: [SupportActivity])] = []
            var held = Set<UUID>()
            var applied: [SupportActivity] = []
            for incoming in remote.activities where incoming.sessionID == id {
                guard let l = j.activities[incoming.id] else { applied.append(incoming); continue }
                var take = incoming
                if !pendingActs.contains(incoming.id) {
                    if l.status.isTerminal && !incoming.status.isTerminal { take = l }
                    if l.reflection != nil && take.reflection == nil { take.reflection = l.reflection }
                } else {
                    take = l
                    let differingTerminal = incoming.status.isTerminal && (l.status.isUnfinished || incoming.status != l.status)
                    if differingTerminal {
                        detected.append((.terminalStatus, incoming.id, [incoming]))
                    } else if let lt = l.step?.actionText, let rt = incoming.step?.actionText, !lt.isEmpty, !rt.isEmpty, lt != rt {
                        detected.append((.stepText, incoming.id, [incoming]))
                    }
                }
                applied.append(take)
            }
            // Competing selection / second in-progress execution: keep local, hold the remote one.
            if hasPending {
                let localUnfinishedSelected = local?.selectedActivityID.flatMap { j.activities[$0] }.flatMap { $0.status.isUnfinished ? $0 : nil }
                var competitor: SupportActivity?
                if let ls = localUnfinishedSelected,
                   let rs = remote.session.selectedActivityID, rs != ls.id,
                   let r = remote.activities.first(where: { $0.id == rs }), r.status.isUnfinished {
                    competitor = r
                }
                if competitor == nil,
                   let li = j.activities(in: id).first(where: { $0.status == .inProgress }),
                   let r = remote.activities.first(where: { $0.status == .inProgress && $0.id != li.id }) {
                    competitor = r
                }
                if let competitor {
                    detected.append((.selectedActivity, nil, [competitor]))
                    held.insert(competitor.id)
                }
            }

            j.sessions[id] = merged
            for activity in applied where !held.contains(activity.id) {
                var take = Self.preservingDeviceState(activity, from: j.activities[activity.id])
                take.syncStatus = hasPending ? .pending : .synced
                j.activities[activity.id] = take
            }
            if detected.isEmpty {
                var s = merged
                s.syncStatus = hasPending ? .pending : .synced
                j.sessions[id] = s
                if !inFlight { j.serverRevisions[id] = remote.revision }
                return
            }
            // Refresh previously retained conflicts, then add new ones (one per kind+activity).
            for i in j.conflicts.indices where j.conflicts[i].sessionID == id {
                j.conflicts[i].remoteRevision = remote.revision
                j.conflicts[i].remoteSession = remote.session
                if let aid = j.conflicts[i].activityID, let fresh = remote.activities.first(where: { $0.id == aid }) {
                    j.conflicts[i].remoteActivities = [fresh]
                }
            }
            for d in detected where !j.conflicts.contains(where: { $0.sessionID == id && $0.kind == d.kind && $0.activityID == d.activityID }) {
                j.conflicts.append(SupportRemoteConflict(
                    id: self.makeID(), sessionID: id, activityID: d.activityID, kind: d.kind, remoteRevision: remote.revision,
                    remoteSession: remote.session, remoteActivities: d.remote, detectedAt: now))
            }
            if var s = j.sessions[id] { s.syncStatus = .conflict; j.sessions[id] = s }
        }
    }

    /// Explicit resolution of a retained remote conflict. Only after the last conflict of a session is resolved does the
    /// session's known server revision advance (the new mutation base).
    public func resolveConflict(epoch: UUID, conflictID: UUID, resolution: SupportConflictResolution) throws {
        try commit(epoch: epoch) { j, now in
            guard let ci = j.conflicts.firstIndex(where: { $0.id == conflictID }) else {
                throw SupportSessionError.conflictNotFound(conflictID)
            }
            let c = j.conflicts[ci]
            let sid = c.sessionID
            guard var session = j.sessions[sid] else { throw SupportSessionError.sessionNotFound(sid) }
            if resolution == .takeRemote {
                let targets = Set(c.remoteActivities.map(\.id) + [c.activityID].compactMap { $0 })
                let relevant = j.attempts.filter { $0.envelope.sessionID == sid &&
                    $0.envelope.payload.targetActivityID.map(targets.contains) == true }
                guard relevant.allSatisfy({ if case .rejectedConflict = $0.state { return true }; return false }) else {
                    throw SupportSessionError.unresolvedConflict(sid)
                }
                // An explicit take-remote choice abandons definitely rejected local payloads permanently.
                let abandoned = Set(relevant.map(\.id))
                j.attempts.removeAll { abandoned.contains($0.id) }
            }
            switch (c.kind, resolution) {
            case (.selectedActivity, .keepLocal):
                for r in c.remoteActivities where j.activities[r.id] == nil || j.activities[r.id]?.status.isUnfinished == true {
                    var paused = Self.preservingDeviceState(r, from: j.activities[r.id])
                    if paused.status == .inProgress { paused.status = .paused }
                    paused.syncStatus = .pending
                    j.activities[r.id] = paused
                    try self.enqueue(&j, sessionID: sid, payload: .checkpointActivity(
                        activityID: r.id, status: paused.status, checkpoint: r.checkpoint, step: r.step), now: now)
                }
            case (.selectedActivity, .takeRemote):
                if let prevID = session.selectedActivityID, var prev = j.activities[prevID], prev.status.isUnfinished {
                    if prev.status == .inProgress { prev.status = .paused }
                    prev.syncStatus = .pending
                    j.activities[prevID] = prev
                    try self.enqueue(&j, sessionID: sid, payload: .checkpointActivity(
                        activityID: prevID, status: prev.status, checkpoint: prev.checkpoint, step: prev.step), now: now)
                }
                for r in c.remoteActivities { var t = Self.preservingDeviceState(r, from: j.activities[r.id]); t.syncStatus = .pending; j.activities[r.id] = t }
                session.selectedActivityID = c.remoteSession.selectedActivityID
                j.sessions[sid] = session
            case (_, .keepLocal):
                break  // local version stays and will be sent against the adopted base
            case (_, .takeRemote):
                if let aid = c.activityID, let r = c.remoteActivities.first {
                    j.intents.removeAll { $0.sessionID == sid && $0.payload.targetActivityID == aid && $0.payload.kind != .discardActivityAnswers }
                    var t = Self.preservingDeviceState(r, from: j.activities[r.id])
                    t.syncStatus = .pending
                    j.activities[aid] = t
                    if session.selectedActivityID == aid, t.status.isTerminal { session.selectedActivityID = nil }
                    j.sessions[sid] = session
                }
            }
            j.conflicts.remove(at: ci)
            if !j.hasUnresolvedConflict(sessionID: sid), !j.attempts.contains(where: { $0.envelope.sessionID == sid }) {
                j.serverRevisions[sid] = max(c.remoteRevision, j.serverRevisions[sid] ?? 0)
            }
            self.refreshSync(&j, sessionID: sid, clearFailed: false)
        }
    }

    /// Remote sync cannot import another device's notification choices or erase local acceptance identity.
    nonisolated private static func preservingDeviceState(_ remote: SupportActivity, from local: SupportActivity?) -> SupportActivity {
        var value = remote
        value.acceptedProposalID = local?.acceptedProposalID ?? remote.acceptedProposalID
        if var step = value.step {
            if step.state == .saved, local?.step?.state == .saved {
                step.reminderAt = local?.step?.reminderAt
                step.reminderTimeZoneIdentifier = local?.step?.reminderTimeZoneIdentifier
                step.reminderState = local?.step?.reminderState
            } else {
                step.reminderAt = nil; step.reminderTimeZoneIdentifier = nil; step.reminderState = nil
            }
            value.step = step
        }
        return value
    }

    // MARK: Privacy suppression

    /// Requires an explicit recovery-file discard choice in the UI. Never runs implicitly on logout or ordinary save.
    public func discardRecoveryCopies(epoch: UUID) throws {
        try requireLoaded(epoch)
        try io.discardQuarantine(ownerID: identity.ownerID)
    }

    nonisolated private static func scrubbedAnswers(_ activity: SupportActivity) -> SupportActivity {
        var copy = activity
        copy.checkpoint.responses = [:]
        copy.result?.shareableNote = nil
        copy.reflection = nil
        copy.step = nil
        return copy
    }

    @discardableResult
    public func recordSuppression(epoch: UUID, kind: SupportSuppressionKind, targetID: String) throws -> SupportPrivacySuppression {
        let target = targetID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { throw SupportSessionError.emptyValue(field: "targetID") }
        guard target.count <= 200 else { throw SupportSessionError.valueTooLong(field: "targetID", limit: 200) }
        return try commit(epoch: epoch) { j, now in
            if let existing = j.suppressions.first(where: { $0.kind == kind && $0.targetID == target }) { return existing }
            let record = SupportPrivacySuppression(id: self.makeID(), kind: kind, targetID: target, createdAt: now, acknowledgedPrivacyRevision: nil)
            j.suppressions.append(record)
            return record
        }
    }

    public func acknowledgeSuppression(epoch: UUID, id: UUID, privacyRevision: Int64) throws {
        try commit(epoch: epoch) { j, _ in
            guard let i = j.suppressions.firstIndex(where: { $0.id == id }) else { return }
            if j.suppressions[i].acknowledgedPrivacyRevision == nil || (j.suppressions[i].acknowledgedPrivacyRevision ?? 0) < privacyRevision {
                j.suppressions[i].acknowledgedPrivacyRevision = privacyRevision
            }
        }
    }

    // MARK: Deliberate memory changes

    public func cacheMemoryRecords(epoch: UUID, records: [SupportMemoryRecord], privacyRevision: Int64) throws {
        try requireLoaded(epoch)
        guard privacyRevision >= (journal.accountPrivacyRevision ?? 0) else { return }
        let pending = Set(journal.memoryChanges.map(\.targetID))
        var values = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for id in pending { values[id] = journal.memoryRecords[id] }
        guard journal.memoryUpdatedAt == nil || journal.memoryRecords != values || journal.accountPrivacyRevision != privacyRevision else { return }
        try commit(epoch: epoch) { j, now in
            // A late page cannot restore a locally forgotten record while its deletion is pending.
            j.memoryRecords = values
            j.accountPrivacyRevision = privacyRevision
            j.memoryUpdatedAt = now
        }
    }

    @discardableResult
    public func queueMemoryChange(epoch: UUID, targetID: UUID, action: SupportMemoryAction,
                                  content: String? = nil, category: String? = nil, expectedRevision: Int? = nil) throws -> SupportMemoryChange {
        if let content, content.unicodeScalars.count > 500 { throw SupportSessionError.valueTooLong(field: "memory", limit: 500) }
        if action == .edit || action == .approveCandidate {
            if let content, content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw SupportSessionError.emptyValue(field: "memory") }
        }
        if action == .forgetMemory || action == .forgetCandidate || action == .edit {
            guard !io.hasQuarantine(ownerID: identity.ownerID) else { throw SupportSessionError.recoveryCopiesNeedDecision }
        }
        return try commit(epoch: epoch) { j, now in
            guard j.memoryChanges.count < 100 else { throw SupportSessionError.capacityExceeded("memory_changes") }
            let change = SupportMemoryChange(id: self.makeID(), targetID: targetID, action: action,
                content: content, category: category, expectedRevision: expectedRevision, createdAt: now)
            switch action {
            case .forgetMemory, .forgetCandidate:
                // Forget dominates earlier corrections even if their outcome is unknown. The server's
                // tombstone makes a late update reject; retaining old plaintext is unnecessary.
                j.memoryChanges.removeAll { $0.targetID == targetID }
                j.memoryRecords[targetID] = nil
            case .dismissCandidate: j.memoryRecords[targetID] = nil
            case .edit:
                if var item = j.memoryRecords[targetID] {
                    item.content = content ?? item.content
                    item.category = category ?? item.category
                    j.memoryRecords[targetID] = item
                }
            case .stopUsing: j.memoryRecords[targetID]?.state = "disabled"
            case .resumeUsing, .approveCandidate: break
            }
            if action == .edit || action == .stopUsing || action == .forgetMemory || action == .forgetCandidate {
                let kind: SupportSuppressionKind = action == .forgetCandidate ? .memoryFragment : .memory
                let target = targetID.uuidString.lowercased()
                if let i = j.suppressions.firstIndex(where: { $0.kind == kind && $0.targetID == target }) {
                    j.suppressions[i].acknowledgedPrivacyRevision = nil
                } else {
                    j.suppressions.append(.init(id: self.makeID(), kind: kind, targetID: target, createdAt: now, acknowledgedPrivacyRevision: nil))
                }
            }
            j.memoryChanges.append(change)
            return change
        }
    }

    public func markMemoryChangeSent(epoch: UUID, id: UUID) throws {
        try commit(epoch: epoch) { j, _ in
            if let i = j.memoryChanges.firstIndex(where: { $0.id == id }) { j.memoryChanges[i].sent = true }
        }
    }

    public func confirmMemoryChange(epoch: UUID, id: UUID, privacyRevision: Int64) throws {
        try commit(epoch: epoch) { j, _ in
            guard let i = j.memoryChanges.firstIndex(where: { $0.id == id }) else { return }
            let change = j.memoryChanges.remove(at: i), target = change.targetID.uuidString.lowercased()
            j.accountPrivacyRevision = max(j.accountPrivacyRevision ?? 0, privacyRevision)
            for index in j.suppressions.indices where j.suppressions[index].targetID == target {
                j.suppressions[index].acknowledgedPrivacyRevision = privacyRevision
            }
            if change.action == .edit || change.action == .resumeUsing {
                j.suppressions.removeAll { $0.kind == .memory && $0.targetID == target }
            }
        }
    }

    public func rejectMemoryChange(epoch: UUID, id: UUID, code: String,
                                   conflictingContent: String? = nil, conflictingRevision: Int? = nil) throws {
        try commit(epoch: epoch) { j, _ in
            guard let i = j.memoryChanges.firstIndex(where: { $0.id == id }) else { return }
            j.memoryChanges[i].failureCode = String(code.prefix(80))
            j.memoryChanges[i].conflictingContent = conflictingContent
            j.memoryChanges[i].conflictingRevision = conflictingRevision
        }
    }

    /// Only a definite conflict can be resolved with a new semantic request. Unknown outcomes keep their ID.
    public func resolveMemoryConflict(epoch: UUID, id: UUID, keepLocal: Bool) throws {
        try commit(epoch: epoch) { j, now in
            guard let i = j.memoryChanges.firstIndex(where: { $0.id == id }),
                  let revision = j.memoryChanges[i].conflictingRevision else { return }
            let old = j.memoryChanges.remove(at: i)
            if keepLocal {
                j.memoryChanges.insert(.init(id: self.makeID(), targetID: old.targetID, action: old.action,
                    content: old.content, category: old.category, expectedRevision: revision, createdAt: now), at: i)
            } else {
                j.memoryRecords[old.targetID]?.content = old.conflictingContent ?? ""
                j.memoryRecords[old.targetID]?.revision = revision
                j.suppressions.removeAll { $0.kind == .memory && $0.targetID == old.targetID.uuidString.lowercased() }
            }
        }
    }

    // MARK: Transcript events

    /// Reserve an order range before a deliberate voice start. A delayed earlier final keeps its
    /// original position even when another turn is acknowledged first or a later call starts.
    public func reserveVoiceTranscriptOrder(epoch: UUID, sessionID: UUID) throws -> Int64 {
        try commit(epoch: epoch) { j, _ in
            _ = try Self.requireSession(j, sessionID)
            let base = j.nextTranscriptSequence[sessionID] ?? 0
            guard base <= Int64.max - Int64(SupportSessionLimits.maxPendingTranscriptEvents) else {
                throw SupportSessionError.capacityExceeded("transcript_sequence")
            }
            j.nextTranscriptSequence[sessionID] = base + Int64(SupportSessionLimits.maxPendingTranscriptEvents)
            return base
        }
    }

    @discardableResult
    public func appendTranscriptEvent(
        epoch: UUID,
        sessionID: UUID,
        conversationID: UUID? = nil,
        role: SupportTranscriptRole,
        text: String,
        providerEventID: String? = nil,
        isFinal: Bool,
        localID: UUID? = nil,
        occurredAt: Date? = nil,
        orderedSequence: Int64? = nil,
        voiceCallID: UUID? = nil,
        providerOrder: Int64? = nil,
        providerItemID: String? = nil,
        voiceCallStartedAt: Date? = nil
    ) throws -> SupportTranscriptAppendResult {
        guard text.unicodeScalars.count <= SupportSessionLimits.transcriptTextMaxCharacters else {
            throw SupportSessionError.valueTooLong(field: "transcript", limit: SupportSessionLimits.transcriptTextMaxCharacters)
        }
        try requireLoaded(epoch)
        guard isFinal else {
            _ = try Self.requireSession(journal, sessionID)
            return .ignoredPartial
        }
        return try commit(epoch: epoch) { j, now in
            _ = try Self.requireSession(j, sessionID)
            if let existing = j.transcriptEvents.first(where: { event in
                if let localID, event.id == localID { return true }
                if let providerEventID, event.providerEventID == providerEventID, event.sessionID == sessionID,
                   event.role == role, event.voiceCallID == voiceCallID { return true }
                return false
            }) {
                guard existing.sessionID == sessionID, existing.conversationID == conversationID, existing.role == role,
                      existing.voiceCallID == voiceCallID, existing.providerOrder == providerOrder,
                      existing.providerItemID == providerItemID,
                      existing.syncState == .saved || existing.text == text else {
                    throw SupportSessionError.operationIDReused(existing.id)
                }
                return .duplicate(existing)
            }
            let pending = j.transcriptEvents.filter { $0.syncState != .saved }.count
            guard pending < SupportSessionLimits.maxPendingTranscriptEvents else {
                throw SupportSessionError.capacityExceeded("transcript_events")
            }
            let high = j.nextTranscriptSequence[sessionID] ?? 0
            let seq: Int64
            if let orderedSequence {
                guard orderedSequence > 0, orderedSequence <= high,
                      !j.transcriptEvents.contains(where: { $0.sessionID == sessionID && $0.sequence == orderedSequence }) else {
                    throw SupportSessionError.capacityExceeded("transcript_sequence")
                }
                seq = orderedSequence
            } else {
                guard high < Int64.max else { throw SupportSessionError.capacityExceeded("transcript_sequence") }
                seq = high + 1
                j.nextTranscriptSequence[sessionID] = seq
            }
            let event = SupportTranscriptEvent(
                id: localID ?? self.makeID(), providerEventID: providerEventID, sessionID: sessionID, conversationID: conversationID,
                role: role, sequence: seq, occurredAt: occurredAt ?? now, text: text, syncState: .pending,
                voiceCallID: voiceCallID, providerOrder: providerOrder, providerItemID: providerItemID,
                voiceCallStartedAt: voiceCallStartedAt)
            j.transcriptEvents.append(event)
            return .persisted(event)
        }
    }

    /// Mark server-acknowledged events saved; their text is dropped locally. Only then may the UI say "saved".
    public func markTranscriptEventsSaved(epoch: UUID, ids: Set<UUID>) throws {
        try commit(epoch: epoch) { j, _ in
            for i in j.transcriptEvents.indices where ids.contains(j.transcriptEvents[i].id) {
                j.transcriptEvents[i].syncState = .saved
                j.transcriptEvents[i].failureCode = nil
                j.transcriptEvents[i].text = ""
            }
            let saved = j.transcriptEvents.enumerated().filter { $0.element.syncState == .saved }
            let excess = saved.count - SupportSessionLimits.maxRetainedSavedTranscriptIDs
            if excess > 0 {
                let drop = Set(saved.prefix(excess).map { $0.element.id })
                j.transcriptEvents.removeAll { drop.contains($0.id) }
            }
        }
    }

    public func markTranscriptEventRejected(epoch: UUID, id: UUID, code: String) throws {
        try requireLoaded(epoch)
        guard let event = journal.transcriptEvents.first(where: { $0.id == id }), event.syncState == .pending else { return }
        try commit(epoch: epoch) { j, _ in
            guard let index = j.transcriptEvents.firstIndex(where: { $0.id == id }) else { return }
            j.transcriptEvents[index].syncState = .rejected
            j.transcriptEvents[index].failureCode = String(code.prefix(80))
        }
    }

    /// Explicit user retry only. The same event and immutable wire values are retained.
    public func retryRejectedTranscriptEvent(epoch: UUID, id: UUID) throws {
        try commit(epoch: epoch) { j, _ in
            guard let index = j.transcriptEvents.firstIndex(where: { $0.id == id && $0.syncState == .rejected }) else { return }
            j.transcriptEvents[index].syncState = .pending
            j.transcriptEvents[index].failureCode = nil
        }
    }

    /// Removes only the selected protected local copy; server messages are separate records.
    public func discardTranscriptEvents(epoch: UUID, ids: Set<UUID>) throws {
        try commit(epoch: epoch) { j, _ in j.transcriptEvents.removeAll { ids.contains($0.id) } }
    }

    public func discardConversationTranscripts(epoch: UUID, conversationID: UUID) throws {
        try commit(epoch: epoch) { j, _ in j.transcriptEvents.removeAll { $0.conversationID == conversationID } }
    }

    // MARK: Internals — commit

    private func requireLive(_ epoch: UUID) throws {
        if isInvalidated { throw SupportSessionError.invalidated }
        if epoch != identity.epochID { throw SupportSessionError.staleEpoch }
    }

    private func requireLoaded(_ epoch: UUID) throws {
        try requireLive(epoch)
        if !isLoaded { throw SupportSessionError.notLoaded }
    }

    @discardableResult
    private func commit<T>(epoch: UUID, _ body: (inout SupportJournal, Date) throws -> T) throws -> T {
        try requireLoaded(epoch)
        var working = journal
        let result = try body(&working, clock())
        working.commitSequence += 1
        try persist(working)
        journal = working
        for continuation in continuations.values { continuation.yield(working) }
        return result
    }

    /// Encode + bound + durable write. Throws (and records `lastPersistenceError`) without touching in-memory state.
    private func persist(_ working: SupportJournal) throws {
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(working)
        } catch {
            let err = SupportSessionError.journalWriteFailed("encode")
            lastPersistenceError = err
            throw err
        }
        guard data.count <= SupportSessionLimits.journalMaxBytes else {
            lastPersistenceError = .journalTooLarge
            throw SupportSessionError.journalTooLarge
        }
        do {
            let result = try io.commit(data, ownerID: identity.ownerID)
            redundantCopyMissing = !result.backupRefreshed
        } catch is SupportJournalProtectedDataUnavailable {
            lastPersistenceError = .protectedDataUnavailable
            throw SupportSessionError.protectedDataUnavailable
        } catch {
            let err = SupportSessionError.journalWriteFailed(Self.describe(error))
            lastPersistenceError = err
            throw err
        }
        lastPersistenceError = nil
    }

    private func decode(_ data: Data) -> Result<SupportJournal, SupportSessionError> {
        struct Header: Decodable { let schemaVersion: Int; let ownerID: UUID }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { return .failure(.journalCorrupt) }
        guard header.ownerID == identity.ownerID else { return .failure(.ownerMismatch) }
        guard header.schemaVersion <= SupportJournal.currentSchemaVersion else {
            return .failure(.unsupportedJournalVersion(header.schemaVersion))
        }
        guard let journal = try? JSONDecoder().decode(SupportJournal.self, from: data) else { return .failure(.journalCorrupt) }
        return .success(journal)
    }

    /// A process that died mid-request cannot know the outcome: in-flight attempts become ambiguous and replay with the same ID.
    nonisolated private static func normalizedAfterLoad(_ loaded: SupportJournal) -> SupportJournal {
        var copy = loaded
        for i in copy.attempts.indices where copy.attempts[i].state == .inFlight { copy.attempts[i].state = .ambiguous }
        return copy
    }

    nonisolated private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain)#\(ns.code)"  // content-free
    }

    // MARK: Internals — domain helpers

    nonisolated private static func cleanTitle(_ title: String?) throws -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return "Conversation" }
        guard trimmed.unicodeScalars.count <= SupportSessionLimits.titleMaxCharacters else {
            throw SupportSessionError.valueTooLong(field: "title", limit: SupportSessionLimits.titleMaxCharacters)
        }
        return trimmed
    }

    nonisolated private static func cleanOptional(_ text: String?, field: String, limit: Int) throws -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard trimmed.unicodeScalars.count <= limit else { throw SupportSessionError.valueTooLong(field: field, limit: limit) }
        return trimmed
    }

    /// Validate a checkpoint against the retained activity's exact schema. Unknown versions/prompt IDs are rejected
    /// before acknowledgement; nothing is ever coerced to a "similar" step.
    private func validate(checkpoint: SupportCheckpoint, template: SupportActivityTemplateKey, templateVersion: Int) throws {
        guard checkpoint.payloadVersion == SupportCheckpoint.currentVersion else {
            throw SupportSessionError.unsupportedCheckpointVersion(checkpoint.payloadVersion)
        }
        guard checkpoint.templateVersion == templateVersion else { throw SupportSessionError.checkpointTemplateMismatch }
        guard let ids = catalog.promptIDs(template: template, version: templateVersion) else {
            throw SupportSessionError.unsupportedTemplateVersion(template: template.rawValue, version: templateVersion)
        }
        let known = Set(ids)
        let referenced = (checkpoint.lastPromptID.map { [$0] } ?? []) + checkpoint.completedStepIDs + checkpoint.skippedStepIDs + Array(checkpoint.responses.keys)
        for id in referenced where !known.contains(id) { throw SupportSessionError.unknownPromptID(String(id.prefix(64))) }
        guard Set(checkpoint.completedStepIDs).count == checkpoint.completedStepIDs.count,
              Set(checkpoint.skippedStepIDs).count == checkpoint.skippedStepIDs.count else {
            throw SupportSessionError.invalidCheckpoint("duplicate_step")
        }
        guard Set(checkpoint.completedStepIDs).isDisjoint(with: checkpoint.skippedStepIDs) else {
            throw SupportSessionError.invalidCheckpoint("step_completed_and_skipped")
        }
        guard checkpoint.activeMilliseconds >= 0 else { throw SupportSessionError.invalidCheckpoint("negative_time") }
        for value in checkpoint.responses.values where value.unicodeScalars.count > SupportSessionLimits.responseMaxCharacters {
            throw SupportSessionError.valueTooLong(field: "response", limit: SupportSessionLimits.responseMaxCharacters)
        }
        let size = (try? JSONEncoder().encode(checkpoint).count) ?? Int.max
        guard size <= SupportSessionLimits.checkpointMaxBytes else { throw SupportSessionError.checkpointTooLarge }
    }

    /// A retained activity whose template/checkpoint schema this build cannot run is preserved, not reset.
    private func ensureRunnable(_ activity: SupportActivity) throws {
        guard catalog.supports(template: activity.templateKey, version: activity.templateVersion),
              activity.checkpoint.payloadVersion == SupportCheckpoint.currentVersion else {
            throw SupportSessionError.activityTemplateUnavailable(activity.id)
        }
    }

    nonisolated private static func requireSession(_ j: SupportJournal, _ id: UUID, mustBeOpen: Bool = true) throws -> SupportSession {
        if j.tombstones[id] != nil { throw SupportSessionError.sessionDeleted(id) }
        guard let session = j.sessions[id] else { throw SupportSessionError.sessionNotFound(id) }
        if mustBeOpen && session.status != .open { throw SupportSessionError.sessionNotOpen(id) }
        return session
    }

    nonisolated private static func requireActivity(_ j: SupportJournal, _ id: UUID) throws -> SupportActivity {
        guard let activity = j.activities[id] else { throw SupportSessionError.activityNotFound(id) }
        if j.tombstones[activity.sessionID] != nil { throw SupportSessionError.sessionDeleted(activity.sessionID) }
        return activity
    }

    private func appendEvent(_ j: inout SupportJournal, sessionID: UUID, activityID: UUID?, kind: SupportEventKind, detail: String?, now: Date) throws {
        if kind == .checkpointSaved,
           let last = j.events.last, last.sessionID == sessionID,
           last.activityID == activityID, last.kind == .checkpointSaved {
            j.events.removeLast()
        }
        let count = j.events.reduce(0) { $0 + ($1.sessionID == sessionID ? 1 : 0) }
        if count >= SupportSessionLimits.maxEventsPerSession {
            // State and terminal/privacy actions remain writable when a long timeline reaches its bound.
            if kind == .checkpointSaved { return }
            if let oldest = j.events.firstIndex(where: { $0.sessionID == sessionID && $0.kind == .checkpointSaved }) ??
                j.events.firstIndex(where: { $0.sessionID == sessionID }) { j.events.remove(at: oldest) }
        }
        j.events.append(SupportSessionEvent(id: makeID(), sessionID: sessionID, activityID: activityID, kind: kind, occurredAt: now, detail: detail))
    }

    /// Append an unsent intent; consecutive checkpoints for the same activity coalesce (nothing was transmitted yet).
    private func enqueue(_ j: inout SupportJournal, sessionID: UUID, payload originalPayload: SupportMutationPayload, now: Date) throws {
        let payload: SupportMutationPayload
        switch originalPayload {
        case .checkpointActivity(let id, let status, let checkpoint, let step):
            payload = .checkpointActivity(activityID: id, status: status, checkpoint: checkpoint, step: step?.accountPayload)
        case .finishActivity(let id, let status, let result, let step, let checkpoint):
            payload = .finishActivity(activityID: id, status: status, result: result, step: step?.accountPayload, checkpoint: checkpoint)
        default: payload = originalPayload
        }
        if j.tombstones[sessionID] != nil { throw SupportSessionError.sessionDeleted(sessionID) }
        if case .checkpointActivity(let activityID, _, _, _) = payload,
           let lastIndex = j.intents.lastIndex(where: { $0.sessionID == sessionID }),
           case .checkpointActivity(let lastID, _, _, _) = j.intents[lastIndex].payload, lastID == activityID {
            j.intents[lastIndex].payload = payload
        } else {
            let terminalOrPrivacy: Bool
            switch payload {
            case .finishActivity, .discardActivityAnswers: terminalOrPrivacy = true
            case .updateSession(_, _, let status): terminalOrPrivacy = status == .closed
            case .checkpointActivity(_, let status, _, _): terminalOrPrivacy = status == .paused
            default: terminalOrPrivacy = false
            }
            guard terminalOrPrivacy || j.intents.count < SupportSessionLimits.maxUnsentIntents else {
                throw SupportSessionError.capacityExceeded("outbox")
            }
            j.intents.append(SupportMutationIntent(
                id: makeID(), operationID: makeID(), sessionID: sessionID, payload: payload, createdAt: now, rebaseCount: 0))
        }
        if var s = j.sessions[sessionID], s.syncStatus != .conflict { s.syncStatus = .pending; j.sessions[sessionID] = s }
    }

    private func refreshSync(_ j: inout SupportJournal, sessionID: UUID, clearFailed: Bool) {
        guard var session = j.sessions[sessionID] else { return }
        let conflicted = j.attempts.contains { attempt in
            if attempt.envelope.sessionID == sessionID, case .rejectedConflict = attempt.state { return true }
            return false
        }
        let hasWork = j.intents.contains { $0.sessionID == sessionID } || j.attempts.contains { $0.envelope.sessionID == sessionID }
        let status: SupportSyncStatus
        if conflicted || j.hasUnresolvedConflict(sessionID: sessionID) { status = .conflict }
        else if hasWork { status = .pending }
        else if session.syncStatus == .failed && !clearFailed { status = .failed }
        else { status = .synced }
        session.syncStatus = status
        j.sessions[sessionID] = session
        for activity in j.activities(in: sessionID) {
            var copy = activity
            copy.syncStatus = status
            j.activities[activity.id] = copy
        }
    }

    /// Replace content-bearing sent envelopes of a deleted session with content-free equivalents and mark them
    /// reconcile-only: they are resolved by querying the server (`reconciliationAttempts`), never replayed, so deleted
    /// content cannot be re-published. Content already transmitted before the delete is the unavoidable boundary.
    private func redactActivityAttempts(_ j: inout SupportJournal, activityID: UUID) {
        for index in j.attempts.indices where j.attempts[index].envelope.payload.targetActivityID == activityID {
            let old = j.attempts[index].envelope
            j.attempts[index].envelope = SupportMutationEnvelope(schemaVersion: old.schemaVersion, operationID: old.operationID,
                sessionID: old.sessionID, expectedRevision: old.expectedRevision, kind: old.kind,
                payload: old.payload.contentRedacted, payloadFingerprint: old.payloadFingerprint)
            j.attempts[index].contentRedacted = true
        }
    }

    private func redactAttempts(_ j: inout SupportJournal, sessionID: UUID) {
        for i in j.attempts.indices where j.attempts[i].envelope.sessionID == sessionID && !j.attempts[i].contentRedacted {
            let e = j.attempts[i].envelope
            j.attempts[i].envelope = SupportMutationEnvelope(
                schemaVersion: e.schemaVersion, operationID: e.operationID, sessionID: e.sessionID,
                expectedRevision: e.expectedRevision, kind: e.kind, payload: e.payload.contentRedacted,
                payloadFingerprint: e.payloadFingerprint)
            j.attempts[i].contentRedacted = true
        }
    }

    private func purge(_ j: inout SupportJournal, sessionID: UUID) {
        redactAttempts(&j, sessionID: sessionID)
        j.conflicts.removeAll { $0.sessionID == sessionID }
        j.sessions[sessionID] = nil
        for activity in j.activities(in: sessionID) { j.activities[activity.id] = nil }
        j.events.removeAll { $0.sessionID == sessionID }
        j.drafts[sessionID] = nil
        j.intents.removeAll { $0.sessionID == sessionID }
        j.transcriptEvents.removeAll { $0.sessionID == sessionID }
        j.pendingChatRequests = j.pendingChatRequests.filter { $0.value.sessionID != sessionID }
        j.reservedConversationIDs[sessionID] = nil
        j.nextTranscriptSequence[sessionID] = nil
    }

    private func settlePreviousSelection(
        _ j: inout SupportJournal,
        session: inout SupportSession,
        incoming: UUID,
        disposition: SupportPreviousActivityDisposition?,
        now: Date
    ) throws {
        guard let selectedID = session.selectedActivityID, selectedID != incoming,
              var previous = j.activities[selectedID], previous.status.isUnfinished else { return }
        guard let disposition else { throw SupportSessionError.anotherActivityUnfinished(selectedID) }
        switch disposition {
        case .saveAndPause:
            if previous.status == .inProgress { previous.status = .paused }
            session.localRevision += 1
            previous.lastChangedRevision = session.localRevision
            previous.updatedAt = now
            previous.syncStatus = .pending
            j.activities[selectedID] = previous
            j.sessions[session.id] = session
            try appendEvent(&j, sessionID: session.id, activityID: selectedID, kind: .activityPaused, detail: nil, now: now)
            try enqueue(&j, sessionID: session.id, payload: .checkpointActivity(
                activityID: selectedID, status: previous.status, checkpoint: previous.checkpoint, step: previous.step), now: now)
        case .endPrevious:
            j.sessions[session.id] = session
            _ = try finishLocked(&j, activity: &previous, outcome: .stopped(reason: "replaced"), checkpoint: nil, note: nil, now: now)
            session = j.sessions[session.id] ?? session
        }
        session.selectedActivityID = nil
    }

    private func finishLocked(
        _ j: inout SupportJournal,
        activity: inout SupportActivity,
        outcome: SupportFinishOutcome,
        checkpoint: SupportCheckpoint?,
        note: String?,
        now: Date,
        step: SupportStepPayload? = nil,
        kind overrideKind: SupportEventKind? = nil,
        includeCheckpoint: Bool = true
    ) throws -> SupportActivity {
        var session = try Self.requireSession(j, activity.sessionID, mustBeOpen: false)
        if let checkpoint {
            var cp = checkpoint
            cp.lastDurableWrite = now
            cp.activeMilliseconds = max(cp.activeMilliseconds, activity.checkpoint.activeMilliseconds)
            activity.checkpoint = cp
        }
        var finalOutcome = outcome
        if activity.kind == .grounding, case .completed = outcome,
           activity.checkpoint.completedStepIDs.isEmpty, !activity.checkpoint.skippedStepIDs.isEmpty {
            finalOutcome = .stopped(reason: "skipped_all")
        }
        let status: SupportActivityStatus
        var reason: String?
        switch finalOutcome {
        case .completed: status = .completed
        case .stopped(let r): status = .stopped; reason = String(r.prefix(64))
        }
        activity.status = status
        activity.activeMilliseconds = activity.checkpoint.activeMilliseconds
        // A stopped activity can no longer own a pending saved step: dismiss it and drop its text and reminder.
        let payloadStep: SupportStepPayload?
        if status == .stopped {
            if let step { payloadStep = step }
            else if activity.step != nil { payloadStep = SupportStepPayload(actionText: "", state: .dismissed, confirmedAt: now) }
            else { payloadStep = nil }
            if activity.step != nil {
                // Unsent copies of the dismissed step text are scrubbed too (sent ones are superseded by this finish).
                for i in j.intents.indices where j.intents[i].payload.targetActivityID == activity.id {
                    if case .checkpointActivity(let id, let st, let cp, _) = j.intents[i].payload {
                        j.intents[i].payload = .checkpointActivity(activityID: id, status: st, checkpoint: cp, step: nil)
                    }
                }
            }
            activity.step = nil
        } else {
            payloadStep = step ?? activity.step
        }
        let result = SupportActivityResult(
            acknowledgedStepCount: activity.checkpoint.completedStepIDs.count,
            skippedStepCount: activity.checkpoint.skippedStepIDs.count,
            activeMilliseconds: activity.checkpoint.activeMilliseconds,
            stoppedReason: reason, shareableNote: note)
        activity.result = result
        activity.finishedAt = now
        activity.updatedAt = now
        activity.syncStatus = .pending
        session.localRevision += 1
        session.updatedAt = now
        if session.selectedActivityID == activity.id { session.selectedActivityID = nil }
        activity.lastChangedRevision = session.localRevision
        j.activities[activity.id] = activity
        j.sessions[session.id] = session
        let eventKind = overrideKind ?? (status == .completed ? .activityCompleted : .activityStopped)
        try appendEvent(&j, sessionID: session.id, activityID: activity.id, kind: eventKind, detail: reason, now: now)
        try enqueue(&j, sessionID: session.id, payload: .finishActivity(
            activityID: activity.id, status: status, result: result, step: payloadStep,
            checkpoint: includeCheckpoint ? activity.checkpoint : nil), now: now)
        return activity
    }

    private func closeLocked(_ j: inout SupportJournal, id: UUID, now: Date) throws -> SupportSession {
        let session = try Self.requireSession(j, id, mustBeOpen: false)
        if session.status == .closed { return session }
        for activity in j.activities(in: id) where activity.status.isUnfinished {
            var a = activity
            _ = try finishLocked(&j, activity: &a, outcome: .stopped(reason: "session_closed"), checkpoint: nil, note: nil, now: now)
        }
        // "End unfinished work and close" settles everything pending: saved steps were dismissed above (text + reminder
        // dropped; the coordinator cancels the local notification) and the unsent draft is discarded, since a closed
        // session cannot own a draft. "Save and leave" is `doneForNow`/pause, which keeps both.
        j.drafts[id] = nil
        var closing = j.sessions[id] ?? session
        closing.status = .closed
        closing.closedAt = now
        closing.selectedActivityID = nil
        closing.localRevision += 1
        closing.updatedAt = now
        j.sessions[id] = closing
        try appendEvent(&j, sessionID: id, activityID: nil, kind: .sessionClosed, detail: nil, now: now)
        try enqueue(&j, sessionID: id, payload: .updateSession(title: nil, contextScope: nil, status: .closed), now: now)
        return j.sessions[id] ?? closing
    }
}
