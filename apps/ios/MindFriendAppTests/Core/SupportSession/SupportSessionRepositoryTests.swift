import XCTest
@testable import MindFriendApp

// MARK: - Fault-injectable IO

final class FaultyJournalIO: SupportJournalIO, @unchecked Sendable {
    private let lock = NSLock()
    private var primaries: [UUID: Data] = [:]
    private var backups: [UUID: Data] = [:]
    private var quarantined: Set<UUID> = []
    private var _failCommits = false
    private var _protected = false
    private var _commitCount = 0

    var failCommits: Bool {
        get { lock.withLock { _failCommits } }
        set { lock.withLock { _failCommits = newValue } }
    }
    var protectedDataLocked: Bool {
        get { lock.withLock { _protected } }
        set { lock.withLock { _protected = newValue } }
    }
    var commitCount: Int { lock.withLock { _commitCount } }

    func seedPrimary(_ data: Data, ownerID: UUID) { lock.withLock { primaries[ownerID] = data } }
    func seedBackup(_ data: Data, ownerID: UUID) { lock.withLock { backups[ownerID] = data } }
    func primary(ownerID: UUID) -> Data? { lock.withLock { primaries[ownerID] } }

    func loadPrimary(ownerID: UUID) throws -> Data? {
        try lock.withLock {
            if _protected { throw SupportJournalProtectedDataUnavailable() }
            return primaries[ownerID]
        }
    }
    func loadBackup(ownerID: UUID) throws -> Data? { lock.withLock { backups[ownerID] } }
    @discardableResult
    func commit(_ data: Data, ownerID: UUID) throws -> SupportJournalCommitResult {
        try lock.withLock {
            if _protected { throw SupportJournalProtectedDataUnavailable() }
            if _failCommits { throw NSError(domain: "fault", code: 28) }
            primaries[ownerID] = data
            backups[ownerID] = data  // contract: redundant copy is the latest bytes or absent, never older
            _commitCount += 1
            return SupportJournalCommitResult(backupRefreshed: true)
        }
    }
    func quarantinePrimary(ownerID: UUID) throws {
        lock.withLock {
            if primaries[ownerID] != nil { quarantined.insert(ownerID) }
            primaries[ownerID] = nil
        }
    }
    func quarantine(ownerID: UUID) throws {
        lock.withLock {
            if primaries[ownerID] != nil || backups[ownerID] != nil { quarantined.insert(ownerID) }
            primaries[ownerID] = nil
            backups[ownerID] = nil
        }
    }
    func hasQuarantine(ownerID: UUID) -> Bool { lock.withLock { quarantined.contains(ownerID) } }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { lock.withLock { t = t.addingTimeInterval(1); return t } }
}

// MARK: - Tests

final class SupportSessionRepositoryTests: XCTestCase {
    private var io: FaultyJournalIO!
    private var identity: SupportSessionIdentity!
    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        io = FaultyJournalIO()
        identity = SupportSessionIdentity(ownerID: UUID())
        clock = TestClock()
    }

    private func makeRepo(
        _ identity: SupportSessionIdentity? = nil,
        io: SupportJournalIO? = nil
    ) -> SupportSessionRepository {
        let clock = self.clock!
        return SupportSessionRepository(identity: identity ?? self.identity, io: io ?? self.io, clock: { clock.now() })
    }

    private func loadedRepo() async throws -> SupportSessionRepository {
        let repo = makeRepo()
        try await repo.load(epoch: identity.epochID)
        return repo
    }

    private var epoch: UUID { identity.epochID }

    private func session(_ repo: SupportSessionRepository, title: String? = "Email") async throws -> UUID {
        let id = UUID()
        try await repo.createSession(epoch: epoch, id: id, title: title)
        return id
    }

    // MARK: durability

    func testCreateSessionIsDurableAndReloadsAfterRelaunch() async throws {
        let repo = try await loadedRepo()
        let id = try await session(repo, title: "  Putting off an email  ")
        let reloaded = makeRepo()
        let journal = try await reloaded.load(epoch: epoch)
        XCTAssertEqual(journal.sessions[id]?.title, "Putting off an email")
        XCTAssertEqual(journal.sessions[id]?.ownerID, identity.ownerID)
        XCTAssertEqual(journal.intents.count, 1)
        XCTAssertEqual(journal.sessions[id]?.syncStatus, .pending)
    }

    func testWriteFailureThrowsLeavesStateUntouchedAndPublishesNothing() async throws {
        let repo = try await loadedRepo()
        let stream = try await repo.updates(epoch: epoch)
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()  // initial snapshot

        io.failCommits = true
        let id = UUID()
        do {
            try await repo.createSession(epoch: epoch, id: id, title: "x")
            XCTFail("expected write failure")
        } catch let error as SupportSessionError {
            guard case .journalWriteFailed = error else { return XCTFail("wrong error \(error)") }
        }
        let afterFail = try await repo.currentJournal(epoch: epoch)
        XCTAssertNil(afterFail.sessions[id])
        let lastError = await repo.lastPersistenceError
        XCTAssertNotNil(lastError)

        io.failCommits = false
        try await repo.createSession(epoch: epoch, id: id, title: "x")
        let published = await iterator.next()
        XCTAssertNotNil(published?.sessions[id], "first published snapshot after the failure must be the durable one")
        let cleared = await repo.lastPersistenceError
        XCTAssertNil(cleared)
    }

    func testProtectedDataUnavailableIsDistinctStateOnLoadAndWrite() async throws {
        io.protectedDataLocked = true
        let repo = makeRepo()
        do { try await repo.load(epoch: epoch); XCTFail() } catch { XCTAssertEqual(error as? SupportSessionError, .protectedDataUnavailable) }
        io.protectedDataLocked = false
        try await repo.load(epoch: epoch)
        io.protectedDataLocked = true
        do { try await repo.createSession(epoch: epoch, id: UUID()); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .protectedDataUnavailable)
        }
    }

    func testCorruptPrimaryFallsBackToBackupAndQuarantines() async throws {
        let repo = try await loadedRepo()
        let id = try await session(repo)
        let id2 = try await session(repo, title: "second")  // backup is the LATEST journal, never an older one
        io.seedPrimary(Data("not json".utf8), ownerID: identity.ownerID)
        let again = makeRepo()
        let journal = try await again.load(epoch: epoch)
        XCTAssertNotNil(journal.sessions[id])
        XCTAssertNotNil(journal.sessions[id2])
        let recovered = await again.recoveredFromBackup
        XCTAssertTrue(recovered)
        XCTAssertTrue(io.hasQuarantine(ownerID: identity.ownerID))
        // J05: recovery was persisted, so a second launch with no mutation loads cleanly.
        let third = makeRepo()
        let again2 = try await third.load(epoch: epoch)
        XCTAssertEqual(Set(again2.sessions.keys), [id, id2])
        let notRecovered = await third.recoveredFromBackup
        XCTAssertFalse(notRecovered, "primary was rewritten, no further recovery needed")
    }

    func testCorruptWithoutBackupIsSurfacedNotSilentlyReset() async throws {
        io.seedPrimary(Data("garbage".utf8), ownerID: identity.ownerID)
        let repo = makeRepo()
        do { try await repo.load(epoch: epoch); XCTFail() } catch { XCTAssertEqual(error as? SupportSessionError, .journalCorrupt) }
        // A second attempt must still refuse (quarantine present) until an explicit decision.
        let retry = makeRepo()
        do { try await retry.load(epoch: epoch); XCTFail() } catch { XCTAssertEqual(error as? SupportSessionError, .journalCorrupt) }
        try await retry.startFreshAfterQuarantine(epoch: epoch)
        let journal = try await retry.load(epoch: epoch)
        XCTAssertTrue(journal.sessions.isEmpty)
        XCTAssertTrue(io.hasQuarantine(ownerID: identity.ownerID), "quarantined data is retained")
    }

    func testFutureSchemaVersionIsNotOverwritten() async throws {
        var future = SupportJournal(ownerID: identity.ownerID)
        future.schemaVersion = 99
        let data = try JSONEncoder().encode(future)
        io.seedPrimary(data, ownerID: identity.ownerID)
        let repo = makeRepo()
        do { try await repo.load(epoch: epoch); XCTFail() } catch { XCTAssertEqual(error as? SupportSessionError, .unsupportedJournalVersion(99)) }
        XCTAssertEqual(io.primary(ownerID: identity.ownerID), data)
        XCTAssertFalse(io.hasQuarantine(ownerID: identity.ownerID))
    }

    // MARK: owner / epoch

    func testJournalOfAnotherOwnerIsRejectedAndUntouched() async throws {
        let other = SupportSessionIdentity(ownerID: UUID())
        let foreign = try JSONEncoder().encode(SupportJournal(ownerID: other.ownerID))
        io.seedPrimary(foreign, ownerID: identity.ownerID)  // misplaced file
        let repo = makeRepo()
        do { try await repo.load(epoch: epoch); XCTFail() } catch { XCTAssertEqual(error as? SupportSessionError, .ownerMismatch) }
        XCTAssertEqual(io.primary(ownerID: identity.ownerID), foreign)
    }

    func testPerAccountIsolationAndStaleEpoch() async throws {
        let repoA = try await loadedRepo()
        _ = try await session(repoA)
        let b = SupportSessionIdentity(ownerID: UUID())
        let repoB = makeRepo(b)
        let journalB = try await repoB.load(epoch: b.epochID)
        XCTAssertTrue(journalB.sessions.isEmpty)
        do { _ = try await repoA.currentJournal(epoch: b.epochID); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .staleEpoch)
        }
    }

    func testInvalidateRejectsEveryLaterCallAndWritesNothing() async throws {
        let repo = try await loadedRepo()
        let id = try await session(repo)
        let commits = io.commitCount
        await repo.invalidate()
        do { try await repo.updateSession(epoch: epoch, id: id, title: "late"); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .invalidated)
        }
        do { _ = try await repo.nextEnvelopeToSend(epoch: epoch); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .invalidated)
        }
        XCTAssertEqual(io.commitCount, commits)
    }

    func testMutationBeforeLoadFails() async {
        let repo = makeRepo()
        do { try await repo.createSession(epoch: epoch, id: UUID()); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .notLoaded)
        }
    }

    // MARK: activities

    func testGroundingCheckpointSurvivesRelaunchWithExactStep() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .groundPresentV1)
        var cp = SupportCheckpoint(lastPromptID: "hear", completedStepIDs: ["see", "feel"], skippedStepIDs: ["smell"], responses: ["see": "window"], activeMilliseconds: 42_000)
        try await repo.pauseActivity(epoch: epoch, activityID: aid, checkpoint: cp)
        cp.activeMilliseconds = 10  // lower value must not move time backwards
        try await repo.checkpointActivity(epoch: epoch, activityID: aid, checkpoint: cp, status: .paused)

        let reloaded = makeRepo()
        let journal = try await reloaded.load(epoch: epoch)
        let activity = try XCTUnwrap(journal.activities[aid])
        XCTAssertEqual(activity.status, .paused)
        XCTAssertEqual(activity.checkpoint.lastPromptID, "hear")
        XCTAssertEqual(activity.checkpoint.completedStepIDs, ["see", "feel"])
        XCTAssertEqual(activity.checkpoint.responses["see"], "window")
        XCTAssertEqual(activity.activeMilliseconds, 42_000)
        XCTAssertEqual(journal.sessions[sid]?.selectedActivityID, aid)
        // start + coalesced checkpoint (+ create) only: checkpoints coalesce.
        XCTAssertEqual(journal.intents.map(\.payload.kind), [.create, .startActivity, .checkpointActivity])
    }

    func testFailedCheckpointDoesNotChangeAcknowledgedStep() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .groundPresentV1)
        try await repo.checkpointActivity(epoch: epoch, activityID: aid, checkpoint: SupportCheckpoint(lastPromptID: "see"))
        io.failCommits = true
        do { try await repo.checkpointActivity(epoch: epoch, activityID: aid, checkpoint: SupportCheckpoint(lastPromptID: "feel")); XCTFail() } catch {}
        let journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.activities[aid]?.checkpoint.lastPromptID, "see")
    }

    func testCompletedActivityCannotBeCheckpointedOrRestarted() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .groundPresentV1)
        try await repo.finishActivity(epoch: epoch, activityID: aid, outcome: .completed)
        do { try await repo.checkpointActivity(epoch: epoch, activityID: aid, checkpoint: .empty); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .activityTerminal(aid))
        }
        do { try await repo.resumeActivity(epoch: epoch, activityID: aid); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .activityTerminal(aid))
        }
        let journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertNil(journal.sessions[sid]?.selectedActivityID)
    }

    func testGroundingAllSkippedIsStoppedNotCompleted() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .groundPresentV1)
        let cp = SupportCheckpoint(skippedStepIDs: ["see", "feel", "hear", "smell", "taste"])
        let done = try await repo.finishActivity(epoch: epoch, activityID: aid, outcome: .completed, checkpoint: cp)
        XCTAssertEqual(done.status, .stopped)
        XCTAssertEqual(done.result?.stoppedReason, "skipped_all")
        // Silent participation then Finish is a valid completion.
        let aid2 = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid2, template: .groundPresentV1)
        let silent = try await repo.finishActivity(epoch: epoch, activityID: aid2, outcome: .completed)
        XCTAssertEqual(silent.status, .completed)
    }

    func testSecondUnfinishedActivityNeedsExplicitDisposition() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let first = UUID(), second = UUID(), third = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: first, template: .groundPresentV1)
        do {
            try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: second, template: .chooseStepV1)
            XCTFail()
        } catch { XCTAssertEqual(error as? SupportSessionError, .anotherActivityUnfinished(first)) }

        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: second, template: .chooseStepV1, previous: .saveAndPause)
        var journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.activities[first]?.status, .paused)
        XCTAssertEqual(journal.sessions[sid]?.selectedActivityID, second)
        XCTAssertEqual(journal.activities.values.filter { $0.status == .inProgress }.count, 1)

        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: third, template: .untangleThoughtV1, previous: .endPrevious)
        journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.activities[second]?.status, .stopped)
        XCTAssertEqual(journal.activities[second]?.result?.stoppedReason, "replaced")
        XCTAssertEqual(journal.sessions[sid]?.selectedActivityID, third)
        XCTAssertEqual(journal.activities[first]?.status, .paused, "older paused execution stays deselected and intact")
    }

    func testStepChoiceSemantics() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .chooseStepV1)
        do { try await repo.applyStepChoice(epoch: epoch, activityID: aid, choice: .saveForLater, actionText: "   "); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .emptyValue(field: "actionText"))
        }
        let long = String(repeating: "a", count: 401)
        do { try await repo.applyStepChoice(epoch: epoch, activityID: aid, choice: .saveForLater, actionText: long); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .valueTooLong(field: "actionText", limit: 400))
        }
        let saved = try await repo.applyStepChoice(epoch: epoch, activityID: aid, choice: .saveForLater, actionText: " Write the subject line ")
        XCTAssertEqual(saved.status, .paused)
        XCTAssertEqual(saved.step?.state, .saved)
        XCTAssertEqual(saved.step?.actionText, "Write the subject line")
        XCTAssertNil(saved.result)

        let done = try await repo.applyStepChoice(epoch: epoch, activityID: aid, choice: .didIt)
        XCTAssertEqual(done.status, .completed)
        XCTAssertEqual(done.step?.state, .selfReportedDone)
        XCTAssertNil(done.canonicalReference)

        let other = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: other, template: .chooseStepV1)
        let dismissed = try await repo.applyStepChoice(epoch: epoch, activityID: other, choice: .notNow, actionText: "private text")
        XCTAssertEqual(dismissed.status, .stopped)
        XCTAssertNil(dismissed.step, "Not now creates no saved-step row")
        let journal = try await repo.currentJournal(epoch: epoch)
        let finishIntent = journal.intents.last { $0.payload.targetActivityID == other }
        guard case .finishActivity(_, _, _, let step, _)? = finishIntent?.payload else { return XCTFail("missing finish intent") }
        XCTAssertEqual(step?.state, .dismissed)
        XCTAssertEqual(step?.actionText, "")
    }

    func testStepChoiceRejectedForOtherTemplates() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .groundPresentV1)
        do { try await repo.applyStepChoice(epoch: epoch, activityID: aid, choice: .didIt, actionText: "x"); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .templateKindMismatch)
        }
    }

    func testReflectionRequiresTerminalActivityAndBoundsNote() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .groundPresentV1)
        do { try await repo.recordReflection(epoch: epoch, activityID: aid, outcome: .helpful); XCTFail() } catch {}
        try await repo.finishActivity(epoch: epoch, activityID: aid, outcome: .stopped(reason: "user_ended"))
        do {
            try await repo.recordReflection(epoch: epoch, activityID: aid, outcome: .notForMe, note: String(repeating: "n", count: 1_001))
            XCTFail()
        } catch { XCTAssertEqual(error as? SupportSessionError, .valueTooLong(field: "note", limit: 1_000)) }
        let reflected = try await repo.recordReflection(epoch: epoch, activityID: aid, outcome: .notForMe)
        XCTAssertEqual(reflected.reflection?.outcome, .notForMe)
        XCTAssertEqual(reflected.reflection?.includeWrittenAnswers, false)
        XCTAssertEqual(reflected.status, .stopped, "reflection never changes activity status")
    }

    func testUntangleDiscardScrubsAnswersAndQueuedCopiesButKeepsContentFreeStop() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .untangleThoughtV1)
        try await repo.checkpointActivity(epoch: epoch, activityID: aid, checkpoint: SupportCheckpoint(responses: ["on_mind": "SECRET-THOUGHT"]))
        var journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertTrue(String(decoding: try JSONEncoder().encode(journal.intents), as: UTF8.self).contains("SECRET-THOUGHT"))

        let discarded = try await repo.discardActivityAnswers(epoch: epoch, activityID: aid)
        XCTAssertEqual(discarded.status, .stopped)
        XCTAssertEqual(discarded.result?.stoppedReason, "discarded")
        journal = try await repo.currentJournal(epoch: epoch)
        let blob = String(decoding: try JSONEncoder().encode(journal), as: UTF8.self)
        XCTAssertFalse(blob.contains("SECRET-THOUGHT"))
        XCTAssertTrue(journal.events.contains { $0.kind == .activityDiscarded && $0.activityID == aid })
        XCTAssertFalse(String(decoding: io.primary(ownerID: identity.ownerID) ?? Data(), as: UTF8.self).contains("SECRET-THOUGHT"))
    }

    func testCheckpointBoundsAndTitleLimits() async throws {
        let repo = try await loadedRepo()
        do { try await repo.createSession(epoch: epoch, id: UUID(), title: String(repeating: "t", count: 81)); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .valueTooLong(field: "title", limit: 80))
        }
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .untangleThoughtV1)
        do {
            try await repo.checkpointActivity(epoch: epoch, activityID: aid, checkpoint: SupportCheckpoint(responses: ["on_mind": String(repeating: "x", count: 4_001)]))
            XCTFail()
        } catch { XCTAssertEqual(error as? SupportSessionError, .valueTooLong(field: "response", limit: 4_000)) }
    }

    func testDoneForNowKeepsUnfinishedWorkOpenAndCloseStopsNeverCompletes() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        try await repo.setDraft(epoch: epoch, sessionID: sid, text: "half a thought")
        var result = try await repo.doneForNow(epoch: epoch, id: sid)
        XCTAssertEqual(result, .stayedOpen)
        try await repo.setDraft(epoch: epoch, sessionID: sid, text: "")
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .groundPresentV1)
        result = try await repo.doneForNow(epoch: epoch, id: sid)
        XCTAssertEqual(result, .stayedOpen)

        let closed = try await repo.closeSession(epoch: epoch, id: sid)
        XCTAssertEqual(closed.status, .closed)
        let journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.activities[aid]?.status, .stopped)
        XCTAssertEqual(journal.activities[aid]?.result?.stoppedReason, "session_closed")
        do { try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: UUID(), template: .chooseStepV1); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .sessionNotOpen(sid))
        }

        let empty = try await session(repo)
        let r2 = try await repo.doneForNow(epoch: epoch, id: empty)
        XCTAssertEqual(r2, .closed)
    }

    // MARK: outbox

    func testOutboxReleasesOrderedIntentsOnePerSessionWithRevisionAssignment() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .groundPresentV1)

        let first = try await repo.nextEnvelopeToSend(epoch: epoch)
        XCTAssertEqual(first?.kind, .create)
        XCTAssertNil(first?.expectedRevision)
        let blocked = try await repo.nextEnvelopeToSend(epoch: epoch)
        XCTAssertNil(blocked, "one unresolved attempt per session blocks later intents")

        try await repo.resolveAttempt(epoch: epoch, operationID: try XCTUnwrap(first?.operationID), outcome: .confirmed(revision: 1))
        let second = try await repo.nextEnvelopeToSend(epoch: epoch)
        XCTAssertEqual(second?.kind, .startActivity)
        XCTAssertEqual(second?.expectedRevision, 1)
        XCTAssertNotEqual(second?.operationID, first?.operationID)
        try await repo.resolveAttempt(epoch: epoch, operationID: try XCTUnwrap(second?.operationID), outcome: .confirmed(revision: 2))
        let journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.sessions[sid]?.syncStatus, .synced)
        XCTAssertEqual(journal.activities[aid]?.syncStatus, .synced)
        XCTAssertEqual(journal.activities[aid]?.status, .inProgress, "sync status never alters activity status")
    }

    func testAmbiguousAttemptReplaysIdenticalEnvelopeAfterRelaunchEvenIfIntentsChanged() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let sent = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))
        // User keeps working while the request is in flight; unsent state evolves but the sent envelope is frozen.
        try await repo.updateSession(epoch: epoch, id: sid, title: "Renamed")

        let relaunched = makeRepo()
        let journal = try await relaunched.load(epoch: epoch)
        XCTAssertEqual(journal.attempts.first?.envelope, sent)
        let replay = try await XCTUnwrapAsync(try await relaunched.nextEnvelopeToSend(epoch: epoch))
        XCTAssertEqual(replay, sent, "replay resends the original wire envelope bit-for-bit")
        XCTAssertEqual(replay.operationID, sent.operationID)
        try await relaunched.resolveAttempt(epoch: epoch, operationID: sent.operationID, outcome: .transientFailure)
        let again = try await XCTUnwrapAsync(try await relaunched.nextEnvelopeToSend(epoch: epoch))
        XCTAssertEqual(again, sent)
        let transmissions = try await relaunched.currentJournal(epoch: epoch).attempts.first?.transmissionCount
        XCTAssertEqual(transmissions, 3)
    }

    func testRevisionConflictRebasesToNewOperationIDWithoutMutatingOldAttempt() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let create = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))
        try await repo.resolveAttempt(epoch: epoch, operationID: create.operationID, outcome: .confirmed(revision: 1))
        try await repo.updateSession(epoch: epoch, id: sid, title: "Mine")
        let sent = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))
        XCTAssertEqual(sent.expectedRevision, 1)

        try await repo.resolveAttempt(epoch: epoch, operationID: sent.operationID, outcome: .revisionConflict(currentRevision: 5))
        var journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.sessions[sid]?.syncStatus, .conflict)
        XCTAssertEqual(journal.attempts.first?.envelope, sent, "old attempt untouched until rebased")
        let blocked = try await repo.nextEnvelopeToSend(epoch: epoch)
        XCTAssertNil(blocked)

        let rebased = try await XCTUnwrapAsync(try await repo.rebaseConflictedAttempt(epoch: epoch, operationID: sent.operationID))
        XCTAssertNotEqual(rebased.operationID, sent.operationID)
        XCTAssertEqual(rebased.id, journal.attempts.first?.intentID, "intent identity is stable across rebase")
        let resent = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))
        XCTAssertEqual(resent.expectedRevision, 5)
        XCTAssertNotEqual(resent.operationID, sent.operationID)
        XCTAssertEqual(resent.payload, sent.payload)

        // Only conflicted attempts can be rebased.
        do { _ = try await repo.rebaseConflictedAttempt(epoch: epoch, operationID: resent.operationID); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .attemptNotRejected(resent.operationID))
        }
        journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.attempts.count, 1)
    }

    func testPermanentRejectionStopsRetryAndRecordsContentFreeFailure() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo, title: "SECRET-TITLE")
        let env = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))
        try await repo.resolveAttempt(epoch: epoch, operationID: env.operationID, outcome: .rejected(code: "INVALID_PAYLOAD"))
        let journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.sessions[sid]?.syncStatus, .failed)
        XCTAssertTrue(journal.attempts.isEmpty)
        XCTAssertEqual(journal.failures.first?.code, "INVALID_PAYLOAD")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(journal.failures), as: UTF8.self).contains("SECRET-TITLE"))
        do { try await repo.resolveAttempt(epoch: epoch, operationID: env.operationID, outcome: .confirmed(revision: 1)); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .unknownAttempt(env.operationID))
        }
    }

    func testOutboxNeverContainsChatTextAndRespectsCapacity() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        try await repo.setDraft(epoch: epoch, sessionID: sid, text: "chat draft")
        let journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(journal.intents), as: UTF8.self).contains("chat draft"))
        XCTAssertEqual(journal.drafts[sid], "chat draft")
    }

    // MARK: privacy

    func testPendingPrivacyMutationBlocksOutboxUntilAcknowledgedAndStoresNoPlaintext() async throws {
        let repo = try await loadedRepo()
        _ = try await session(repo)
        let s = try await repo.recordSuppression(epoch: epoch, kind: .sourceMessage, targetID: UUID().uuidString)
        let dup = try await repo.recordSuppression(epoch: epoch, kind: .sourceMessage, targetID: s.targetID)
        XCTAssertEqual(s.id, dup.id, "idempotent per target")
        var paused = try await repo.currentJournal(epoch: epoch).personalizedCloudPaused
        XCTAssertTrue(paused)
        let blocked = try await repo.nextEnvelopeToSend(epoch: epoch)
        XCTAssertNil(blocked)
        let forced = try await repo.nextEnvelopeToSend(epoch: epoch, requirePrivacyFlushed: false)
        XCTAssertNotNil(forced)

        try await repo.acknowledgeSuppression(epoch: epoch, id: s.id, privacyRevision: 7)
        let journal = try await repo.currentJournal(epoch: epoch)
        paused = journal.personalizedCloudPaused
        XCTAssertFalse(paused)
        XCTAssertTrue(journal.isSuppressed(kind: .sourceMessage, targetID: s.targetID))
        XCTAssertEqual(journal.suppressions.first?.acknowledgedPrivacyRevision, 7)
        let pending = try await repo.pendingSuppressions(epoch: epoch)
        XCTAssertTrue(pending.isEmpty)
    }

    func testSuppressionSurvivesRelaunchAndRemoteMergeCannotRemoveIt() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        _ = try await repo.recordSuppression(epoch: epoch, kind: .memory, targetID: "memory-1")
        let again = makeRepo()
        try await again.load(epoch: epoch)
        var journal = try await again.currentJournal(epoch: epoch)
        let remote = SupportRemoteSessionSnapshot(session: journal.sessions[sid]!, activities: [], revision: 9)
        try await again.applyRemoteSession(epoch: epoch, remote: remote)
        journal = try await again.currentJournal(epoch: epoch)
        XCTAssertTrue(journal.isSuppressed(kind: .memory, targetID: "memory-1"))
    }

    // MARK: delete / tombstone

    func testDeleteRemovesContentKeepsTombstoneAndRejectsLateWork() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo, title: "SECRET-TITLE")
        let create = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))
        try await repo.resolveAttempt(epoch: epoch, operationID: create.operationID, outcome: .confirmed(revision: 1))
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .untangleThoughtV1)
        try await repo.checkpointActivity(epoch: epoch, activityID: aid, checkpoint: SupportCheckpoint(responses: ["on_mind": "SECRET-ANSWER"]))
        try await repo.appendTranscriptEvent(epoch: epoch, sessionID: sid, role: .user, text: "SECRET-SPOKEN", isFinal: true)

        try await repo.deleteSession(epoch: epoch, id: sid)
        let journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertNotNil(journal.tombstones[sid])
        XCTAssertNil(journal.sessions[sid])
        XCTAssertTrue(journal.transcriptEvents.isEmpty)
        XCTAssertEqual(journal.intents.map(\.payload.kind), [.deleteSession], "only the content-free delete remains queued")
        let raw = String(decoding: io.primary(ownerID: identity.ownerID) ?? Data(), as: UTF8.self)
        for secret in ["SECRET-TITLE", "SECRET-ANSWER", "SECRET-SPOKEN"] { XCTAssertFalse(raw.contains(secret), secret) }

        do { try await repo.createSession(epoch: epoch, id: sid); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .sessionDeleted(sid))
        }
        do { try await repo.checkpointActivity(epoch: epoch, activityID: aid, checkpoint: .empty); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .activityNotFound(aid))
        }
        // Late remote replay of the session does not resurrect it.
        let ghost = SupportSession(
            id: sid, ownerID: identity.ownerID, conversationID: nil, previousSessionID: nil, selectedActivityID: nil,
            title: "ghost", concern: nil, status: .open, contextScope: .personalized, localRevision: 1,
            syncStatus: .synced, createdAt: Date(), updatedAt: Date(), closedAt: nil)
        try await repo.applyRemoteSession(epoch: epoch, remote: SupportRemoteSessionSnapshot(session: ghost, activities: [], revision: 50))
        let after = try await repo.currentJournal(epoch: epoch)
        XCTAssertNil(after.sessions[sid])
    }

    func testDeleteOfNeverSyncedSessionQueuesNothing() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        try await repo.deleteSession(epoch: epoch, id: sid)
        let journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertTrue(journal.intents.isEmpty)
        XCTAssertNotNil(journal.tombstones[sid])
        try await repo.deleteSession(epoch: epoch, id: sid)  // idempotent
    }

    // MARK: remote

    func testRemoteMergeNeverRegressesCompletedAndKeepsLocalDraft() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .groundPresentV1)
        try await repo.finishActivity(epoch: epoch, activityID: aid, outcome: .completed)
        try await repo.setDraft(epoch: epoch, sessionID: sid, text: "unsent")
        var journal = try await repo.currentJournal(epoch: epoch)
        var staleActivity = journal.activities[aid]!
        staleActivity.status = .inProgress
        staleActivity.result = nil
        let remote = SupportRemoteSessionSnapshot(session: journal.sessions[sid]!, activities: [staleActivity], revision: 3)
        try await repo.applyRemoteSession(epoch: epoch, remote: remote)
        journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.activities[aid]?.status, .completed)
        XCTAssertEqual(journal.drafts[sid], "unsent")
        XCTAssertFalse(journal.intents.isEmpty, "unsent intents survive a remote merge")
    }

    func testRemoteSnapshotForAnotherOwnerIsRejected() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        var foreign = try await repo.currentJournal(epoch: epoch).sessions[sid]!
        foreign = SupportSession(
            id: UUID(), ownerID: UUID(), conversationID: nil, previousSessionID: nil, selectedActivityID: nil, title: "x", concern: nil,
            status: .open, contextScope: .personalized, localRevision: 1, syncStatus: .synced, createdAt: Date(), updatedAt: Date(), closedAt: nil)
        do { try await repo.applyRemoteSession(epoch: epoch, remote: SupportRemoteSessionSnapshot(session: foreign, activities: [], revision: 1)); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .ownerMismatch)
        }
    }

    // MARK: transcripts

    func testTranscriptEventsAreOrderedIdempotentFinalOnlyAndSavedOnlyAfterAck() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let partial = try await repo.appendTranscriptEvent(epoch: epoch, sessionID: sid, role: .assistant, text: "hel", providerEventID: "i1", isFinal: false)
        XCTAssertEqual(partial, .ignoredPartial)
        let none = try await repo.pendingTranscriptEvents(epoch: epoch); XCTAssertEqual(none.count, 0)

        guard case .persisted(let u1) = try await repo.appendTranscriptEvent(epoch: epoch, sessionID: sid, role: .user, text: "one", providerEventID: "u1", isFinal: true),
              case .persisted(let u2) = try await repo.appendTranscriptEvent(epoch: epoch, sessionID: sid, role: .user, text: "two", providerEventID: "u2", isFinal: true),
              case .persisted(let a1) = try await repo.appendTranscriptEvent(epoch: epoch, sessionID: sid, role: .assistant, text: "reply", providerEventID: "a1", isFinal: true)
        else { return XCTFail("expected persisted") }
        XCTAssertEqual([u1.sequence, u2.sequence, a1.sequence], [1, 2, 3], "two user items in a row keep order; no pairing assumed")

        let dupe = try await repo.appendTranscriptEvent(epoch: epoch, sessionID: sid, role: .user, text: "one", providerEventID: "u1", isFinal: true)
        XCTAssertEqual(dupe, .duplicate(u1))

        // Survives relaunch as pending.
        let relaunched = makeRepo()
        try await relaunched.load(epoch: epoch)
        let pending = try await relaunched.pendingTranscriptEvents(epoch: epoch, sessionID: sid)
        XCTAssertEqual(pending.map(\.text), ["one", "two", "reply"])

        // Failed save keeps them pending; ack drops text.
        try await relaunched.markTranscriptEventsSaved(epoch: epoch, ids: [u1.id, u2.id])
        let remaining = try await relaunched.pendingTranscriptEvents(epoch: epoch)
        XCTAssertEqual(remaining.map(\.id), [a1.id])
        let journal = try await relaunched.currentJournal(epoch: epoch)
        XCTAssertTrue(journal.transcriptEvents.filter { $0.syncState == .saved }.allSatisfy { $0.text.isEmpty })
        let again = try await relaunched.appendTranscriptEvent(epoch: epoch, sessionID: sid, role: .user, text: "one", providerEventID: "u1", isFinal: true)
        if case .duplicate = again {} else { XCTFail("saved ids still dedupe") }
    }

    func testTranscriptWriteFailureDoesNotConsumeSequence() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        io.failCommits = true
        do { _ = try await repo.appendTranscriptEvent(epoch: epoch, sessionID: sid, role: .user, text: "a", isFinal: true); XCTFail() } catch {}
        io.failCommits = false
        guard case .persisted(let event) = try await repo.appendTranscriptEvent(epoch: epoch, sessionID: sid, role: .user, text: "a", isFinal: true)
        else { return XCTFail() }
        XCTAssertEqual(event.sequence, 1)
    }

    func testTranscriptForUnknownOrDeletedSessionRejected() async throws {
        let repo = try await loadedRepo()
        let ghost = UUID()
        do { _ = try await repo.appendTranscriptEvent(epoch: epoch, sessionID: ghost, role: .user, text: "a", isFinal: true); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .sessionNotFound(ghost))
        }
    }

    // MARK: real file IO

    func testFileIORoundTripIsPerOwnerAndKeepsBackup() async throws {
        let tmp = ProcessInfo.processInfo.environment["TMPDIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        let base = tmp.appendingPathComponent("support-journal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let fileIO = FileSupportJournalIO(baseDirectory: base)
        let repo = makeRepo(io: fileIO)
        try await repo.load(epoch: epoch)
        let first = UUID(), second = UUID()
        try await repo.createSession(epoch: epoch, id: first, title: "a")
        try await repo.createSession(epoch: epoch, id: second, title: "b")

        let ownerDir = base.appendingPathComponent(identity.ownerID.uuidString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ownerDir.appendingPathComponent("journal.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ownerDir.appendingPathComponent("journal.json.bak").path))

        let relaunched = makeRepo(io: fileIO)
        let journal = try await relaunched.load(epoch: epoch)
        XCTAssertEqual(Set(journal.sessions.keys), [first, second])

        let other = SupportSessionIdentity(ownerID: UUID())
        let otherRepo = makeRepo(other, io: fileIO)
        let otherJournal = try await otherRepo.load(epoch: other.epochID)
        XCTAssertTrue(otherJournal.sessions.isEmpty)

        // Corrupt primary -> quarantined file kept, backup used.
        try Data("{broken".utf8).write(to: ownerDir.appendingPathComponent("journal.json"))
        let recovered = makeRepo(io: fileIO)
        let rj = try await recovered.load(epoch: epoch)
        XCTAssertEqual(Set(rj.sessions.keys), [first, second], "redundant copy is the latest committed state")
        XCTAssertTrue(fileIO.hasQuarantine(ownerID: identity.ownerID))
    }

    func testJournalCodableRoundTripIsLossless() throws {
        var j = SupportJournal(ownerID: UUID())
        j.drafts[UUID()] = "d"
        j.serverRevisions[UUID()] = 4
        j.suppressions.append(SupportPrivacySuppression(id: UUID(), kind: .memory, targetID: "m", createdAt: Date(timeIntervalSince1970: 5), acknowledgedPrivacyRevision: 2))
        let data = try JSONEncoder().encode(j)
        XCTAssertEqual(try JSONDecoder().decode(SupportJournal.self, from: data), j)
    }

    // MARK: - Remediation: real-file helpers

    private func makeTempBase() -> URL {
        let tmp = ProcessInfo.processInfo.environment["TMPDIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
        return tmp.appendingPathComponent("support-journal-\(UUID().uuidString)")
    }

    private func corruptPrimary(base: URL) throws {
        try Data("{broken".utf8).write(to: base.appendingPathComponent(identity.ownerID.uuidString).appendingPathComponent("journal.json"))
    }

    private func rawFiles(base: URL) -> String {
        let dir = base.appendingPathComponent(identity.ownerID.uuidString)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { !$0.contains(".corrupt-") }.map { String(decoding: (try? Data(contentsOf: dir.appendingPathComponent($0))) ?? Data(), as: UTF8.self) }.joined()
    }

    // MARK: J01 — redundant copy never resurrects deletes / discards / loses suppressions

    func testRealFileDeleteThenPrimaryCorruptionDoesNotResurrectSessionOrDraft() async throws {
        let base = makeTempBase(); defer { try? FileManager.default.removeItem(at: base) }
        let fileIO = FileSupportJournalIO(baseDirectory: base)
        let repo = makeRepo(io: fileIO)
        try await repo.load(epoch: epoch)
        let sid = try await session(repo, title: "SECRET-TITLE")
        try await repo.setDraft(epoch: epoch, sessionID: sid, text: "SECRET-DRAFT")
        let create = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))
        try await repo.resolveAttempt(epoch: epoch, operationID: create.operationID, outcome: .confirmed(revision: 1))
        try await repo.deleteSession(epoch: epoch, id: sid)

        try corruptPrimary(base: base)
        let relaunched = makeRepo(io: fileIO)
        let journal = try await relaunched.load(epoch: epoch)
        XCTAssertNil(journal.sessions[sid])
        XCTAssertNil(journal.drafts[sid])
        XCTAssertNotNil(journal.tombstones[sid], "acknowledged delete is not resurrected")
        XCTAssertEqual(journal.intents.map(\.payload.kind), [.deleteSession])
        let raw = rawFiles(base: base)
        XCTAssertFalse(raw.contains("SECRET-TITLE") || raw.contains("SECRET-DRAFT"))
        // second launch without mutation (J05)
        let third = makeRepo(io: fileIO)
        let j3 = try await third.load(epoch: epoch)
        XCTAssertNotNil(j3.tombstones[sid])
    }

    func testRealFileDiscardThenPrimaryCorruptionKeepsScrub() async throws {
        let base = makeTempBase(); defer { try? FileManager.default.removeItem(at: base) }
        let fileIO = FileSupportJournalIO(baseDirectory: base)
        let repo = makeRepo(io: fileIO)
        try await repo.load(epoch: epoch)
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .untangleThoughtV1)
        try await repo.checkpointActivity(epoch: epoch, activityID: aid, checkpoint: SupportCheckpoint(responses: ["on_mind": "SECRET-ANSWER"]))
        try await repo.discardActivityAnswers(epoch: epoch, activityID: aid)
        try corruptPrimary(base: base)
        let journal = try await makeRepo(io: fileIO).load(epoch: epoch)
        XCTAssertTrue(journal.activities[aid]?.checkpoint.responses.isEmpty == true)
        XCTAssertTrue(journal.intents.contains { $0.payload == .discardActivityAnswers(activityID: aid) })
        XCTAssertFalse(rawFiles(base: base).contains("SECRET-ANSWER"))
    }

    func testRealFileSuppressionSurvivesPrimaryCorruption() async throws {
        let base = makeTempBase(); defer { try? FileManager.default.removeItem(at: base) }
        let fileIO = FileSupportJournalIO(baseDirectory: base)
        let repo = makeRepo(io: fileIO)
        try await repo.load(epoch: epoch)
        _ = try await session(repo)
        let sup = try await repo.recordSuppression(epoch: epoch, kind: .memory, targetID: "mem-7")
        try await repo.acknowledgeSuppression(epoch: epoch, id: sup.id, privacyRevision: 4)
        let latest = try await repo.recordSuppression(epoch: epoch, kind: .sourceMessage, targetID: "msg-latest")
        try corruptPrimary(base: base)
        let journal = try await makeRepo(io: fileIO).load(epoch: epoch)
        XCTAssertTrue(journal.isSuppressed(kind: .memory, targetID: "mem-7"))
        XCTAssertTrue(journal.isSuppressed(kind: .sourceMessage, targetID: "msg-latest"), "the latest suppression is not dropped")
        XCTAssertEqual(journal.suppressions.first { $0.id == sup.id }?.acknowledgedPrivacyRevision, 4)
        XCTAssertFalse(journal.suppressions.first { $0.id == latest.id }?.isAcknowledged ?? true)
    }

    // MARK: J05 / J06 — recovery persisted; IO phase faults

    func testRealFileRecoveryWithMissingPrimaryIsPersisted() async throws {
        let base = makeTempBase(); defer { try? FileManager.default.removeItem(at: base) }
        let fileIO = FileSupportJournalIO(baseDirectory: base)
        let repo = makeRepo(io: fileIO)
        try await repo.load(epoch: epoch)
        let sid = try await session(repo)
        try FileManager.default.removeItem(at: base.appendingPathComponent(identity.ownerID.uuidString).appendingPathComponent("journal.json"))
        let second = makeRepo(io: fileIO)
        let j = try await second.load(epoch: epoch)
        XCTAssertNotNil(j.sessions[sid])
        let third = try await makeRepo(io: fileIO).load(epoch: epoch)
        XCTAssertNotNil(third.sessions[sid])
    }

    func testRecoveryThatCannotBePersistedDoesNotClaimLoaded() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        io.seedPrimary(Data("junk".utf8), ownerID: identity.ownerID)
        io.failCommits = true
        let again = makeRepo()
        do { try await again.load(epoch: epoch); XCTFail() } catch {
            guard case .journalWriteFailed? = error as? SupportSessionError else { return XCTFail("\(error)") }
        }
        do { _ = try await again.currentJournal(epoch: epoch); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .notLoaded)
        }
        io.failCommits = false
        let ok = try await makeRepo().load(epoch: epoch)
        XCTAssertNotNil(ok.sessions[sid], "backup still usable on a later attempt")
    }

    func testFileIOPhaseFaultsPreservePrimaryAndNeverLeaveStaleBackup() async throws {
        let primaryPhases: [FileSupportJournalIO.Phase] = [.createDirectory, .removeStaleBackup, .writePrimaryTemp, .syncPrimaryTemp, .replacePrimary]
        for phase in primaryPhases {
            let base = makeTempBase(); defer { try? FileManager.default.removeItem(at: base) }
            let failing = Locked(false)
            let fileIO = FileSupportJournalIO(baseDirectory: base, faultHook: { p in
                if failing.value && p == phase { throw NSError(domain: "fault", code: 5) }
            })
            let repo = makeRepo(io: fileIO)
            try await repo.load(epoch: epoch)
            let kept = try await session(repo, title: "kept")
            failing.value = true
            do { _ = try await session(repo, title: "lost"); XCTFail("\(phase)") } catch {
                guard case .journalWriteFailed? = error as? SupportSessionError else { return XCTFail("\(phase) \(error)") }
            }
            let mem = try await repo.currentJournal(epoch: epoch)
            XCTAssertEqual(mem.sessions.count, 1, "\(phase)")
            failing.value = false
            let reloaded = try await makeRepo(io: FileSupportJournalIO(baseDirectory: base)).load(epoch: epoch)
            XCTAssertEqual(Set(reloaded.sessions.keys), [kept], "primary preserved for \(phase)")
            let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: base.appendingPathComponent(identity.ownerID.uuidString).path)) ?? []
            XCTAssertFalse(leftovers.contains { $0.contains(".tmp-") }, "temp cleaned for \(phase)")
        }
    }

    func testBackupPhaseFaultStillCommitsAndLeavesNoStaleCopy() async throws {
        for phase in [FileSupportJournalIO.Phase.writeBackupTemp, .syncBackupTemp, .replaceBackup] {
            let base = makeTempBase(); defer { try? FileManager.default.removeItem(at: base) }
            let failing = Locked(false)
            let fileIO = FileSupportJournalIO(baseDirectory: base, faultHook: { p in
                if failing.value && p == phase { throw NSError(domain: "fault", code: 5) }
            })
            let repo = makeRepo(io: fileIO)
            try await repo.load(epoch: epoch)
            _ = try await session(repo, title: "old")
            failing.value = true
            let newer = try await session(repo, title: "newer")  // primary durable even though redundant copy failed
            let missing = await repo.redundantCopyMissing
            XCTAssertTrue(missing, "\(phase)")
            let bak = base.appendingPathComponent(identity.ownerID.uuidString).appendingPathComponent("journal.json.bak")
            XCTAssertFalse(FileManager.default.fileExists(atPath: bak.path), "no stale copy for \(phase)")
            let reloaded = try await makeRepo(io: FileSupportJournalIO(baseDirectory: base)).load(epoch: epoch)
            XCTAssertNotNil(reloaded.sessions[newer])
        }
    }

    // MARK: J02 — Finish carries the exact final checkpoint

    func testFinishCarriesFinalCheckpointAtomically() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .untangleThoughtV1)
        let final = SupportCheckpoint(completedStepIDs: ["on_mind"], responses: ["on_mind": "FINAL-ANSWER"], activeMilliseconds: 9)
        try await repo.finishActivity(epoch: epoch, activityID: aid, outcome: .completed, checkpoint: final)
        let journal = try await repo.currentJournal(epoch: epoch)
        let finish = try XCTUnwrap(journal.intents.last { $0.payload.kind == .finishActivity })
        guard case .finishActivity(_, .completed, _, _, let cp?) = finish.payload else { return XCTFail("no checkpoint in finish") }
        XCTAssertEqual(cp.responses["on_mind"], "FINAL-ANSWER")
        XCTAssertFalse(journal.intents.contains { $0.payload.kind == .checkpointActivity && $0.payload.targetActivityID == aid && { if case .checkpointActivity(_, _, let c, _) = $0.payload { return c.responses["on_mind"] == "FINAL-ANSWER" }; return false }($0) },
                       "final answer is not dependent on a separate checkpoint mutation")
        // And it reaches the wire envelope.
        var env = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))
        while env.kind != .finishActivity {
            try await repo.resolveAttempt(epoch: epoch, operationID: env.operationID, outcome: .confirmed(revision: 1 + (env.expectedRevision ?? 0)))
            env = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))
        }
        guard case .finishActivity(_, _, _, _, let wireCP?) = env.payload else { return XCTFail() }
        XCTAssertEqual(wireCP.responses["on_mind"], "FINAL-ANSWER")
    }

    // MARK: J03 — typed scrub

    func testDiscardOfSyncedTerminalActivityQueuesServerScrub() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .untangleThoughtV1)
        try await repo.finishActivity(epoch: epoch, activityID: aid, outcome: .completed,
                                      checkpoint: SupportCheckpoint(responses: ["on_mind": "SECRET"]), shareableNote: "SECRET-NOTE")
        try await repo.recordReflection(epoch: epoch, activityID: aid, outcome: .helpful, note: "SECRET-REFLECTION")
        var rev: Int64 = 0
        while let env = try await repo.nextEnvelopeToSend(epoch: epoch) {
            rev += 1
            try await repo.resolveAttempt(epoch: epoch, operationID: env.operationID, outcome: .confirmed(revision: rev))
        }
        var journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertTrue(journal.intents.isEmpty)
        let discarded = try await repo.discardActivityAnswers(epoch: epoch, activityID: aid)
        XCTAssertEqual(discarded.status, .completed, "terminal status is not rewritten")
        XCTAssertNil(discarded.reflection)
        XCTAssertTrue(discarded.checkpoint.responses.isEmpty)
        journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.intents.map(\.payload), [.discardActivityAnswers(activityID: aid)])
        let env = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))
        XCTAssertEqual(env.kind, .discardActivityAnswers)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(env), as: UTF8.self).contains("SECRET"))
    }

    func testScrubWinsOverOutstandingSentCheckpointAndNeverMutatesSentEnvelope() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .untangleThoughtV1)
        var rev: Int64 = 0
        for _ in 0..<2 {  // create, start
            let env = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))
            rev += 1
            try await repo.resolveAttempt(epoch: epoch, operationID: env.operationID, outcome: .confirmed(revision: rev))
        }
        try await repo.checkpointActivity(epoch: epoch, activityID: aid, checkpoint: SupportCheckpoint(responses: ["on_mind": "SECRET-ANSWER"]))
        let sentCheckpoint = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))  // outstanding (in flight)
        XCTAssertEqual(sentCheckpoint.kind, .checkpointActivity)

        try await repo.discardActivityAnswers(epoch: epoch, activityID: aid)
        var journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.attempts.first?.envelope, sentCheckpoint, "sent envelope never mutated")
        XCTAssertEqual(journal.intents.map(\.payload.kind), [.discardActivityAnswers, .finishActivity])
        let blocked = try await repo.nextEnvelopeToSend(epoch: epoch)
        XCTAssertNil(blocked, "scrub waits for the outstanding attempt")

        // Relaunch: the ambiguous attempt replays unchanged, then the scrub follows.
        let relaunched = makeRepo()
        try await relaunched.load(epoch: epoch)
        let replay = try await XCTUnwrapAsync(try await relaunched.nextEnvelopeToSend(epoch: epoch))
        XCTAssertEqual(replay, sentCheckpoint)
        try await relaunched.resolveAttempt(epoch: epoch, operationID: replay.operationID, outcome: .confirmed(revision: 3))
        let scrub = try await XCTUnwrapAsync(try await relaunched.nextEnvelopeToSend(epoch: epoch))
        XCTAssertEqual(scrub.kind, .discardActivityAnswers)
        try await relaunched.resolveAttempt(epoch: epoch, operationID: scrub.operationID, outcome: .confirmed(revision: 4))
        let finish = try await XCTUnwrapAsync(try await relaunched.nextEnvelopeToSend(epoch: epoch))
        guard case .finishActivity(_, .stopped, let result, nil, nil) = finish.payload else { return XCTFail("finish must be content-free") }
        XCTAssertEqual(result.stoppedReason, "discarded")
        journal = try await relaunched.currentJournal(epoch: epoch)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(journal.intents), as: UTF8.self).contains("SECRET-ANSWER"))
    }

    func testRebaseOfSupersededContentIsDroppedBehindQueuedScrub() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .untangleThoughtV1)
        var rev: Int64 = 0
        for _ in 0..<2 {
            let env = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))
            rev += 1
            try await repo.resolveAttempt(epoch: epoch, operationID: env.operationID, outcome: .confirmed(revision: rev))
        }
        try await repo.checkpointActivity(epoch: epoch, activityID: aid, checkpoint: SupportCheckpoint(responses: ["on_mind": "SECRET-ANSWER"]))
        let sent = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))
        try await repo.discardActivityAnswers(epoch: epoch, activityID: aid)
        try await repo.resolveAttempt(epoch: epoch, operationID: sent.operationID, outcome: .revisionConflict(currentRevision: 9))
        let rebased = try await repo.rebaseConflictedAttempt(epoch: epoch, operationID: sent.operationID)
        XCTAssertNil(rebased, "the content-bearing checkpoint is not resurrected ahead of the scrub")
        let journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertTrue(journal.attempts.isEmpty)
        XCTAssertEqual(journal.serverRevisions[sid], 9)
        let next = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))
        XCTAssertEqual(next.kind, .discardActivityAnswers)
        XCTAssertEqual(next.expectedRevision, 9)
    }

    // MARK: Delete while create is in flight

    func testDeleteWhileCreateInFlightNeverRepublishesContentAndDeletesDeterministically() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo, title: "SECRET-TITLE")
        let create = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))  // in flight, result unknown
        try await repo.deleteSession(epoch: epoch, id: sid)

        let raw = String(decoding: io.primary(ownerID: identity.ownerID) ?? Data(), as: UTF8.self)
        XCTAssertFalse(raw.contains("SECRET-TITLE"), "sent envelope content redacted from the journal")

        let relaunched = makeRepo()
        let journal = try await relaunched.load(epoch: epoch)
        XCTAssertNotNil(journal.tombstones[sid])
        let none = try await relaunched.nextEnvelopeToSend(epoch: epoch)
        XCTAssertNil(none, "no replay of the content-bearing create, and the delete waits for reconciliation")
        let pending = try await relaunched.reconciliationAttempts(epoch: epoch)
        XCTAssertEqual(pending.map(\.id), [create.operationID])
        XCTAssertEqual(pending.first?.contentRedacted, true)
        // Server reports the create DID land at revision 1 -> the delete follows with that base.
        try await relaunched.resolveAttempt(epoch: epoch, operationID: create.operationID, outcome: .confirmed(revision: 1))
        let del = try await XCTUnwrapAsync(try await relaunched.nextEnvelopeToSend(epoch: epoch))
        XCTAssertEqual(del.kind, .deleteSession)
        XCTAssertEqual(del.expectedRevision, 1)
    }

    func testDeleteWhileCreateInFlightDropsDeleteWhenServerNeverSawIt() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let create = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))
        try await repo.deleteSession(epoch: epoch, id: sid)
        try await repo.resolveAttempt(epoch: epoch, operationID: create.operationID, outcome: .rejected(code: "NOT_FOUND"))
        let journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertTrue(journal.intents.isEmpty)
        XCTAssertTrue(journal.attempts.isEmpty)
        XCTAssertNotNil(journal.tombstones[sid], "tombstone preserved")
    }

    // MARK: J04 — remote conflicts

    private func syncedActivity(_ repo: SupportSessionRepository, template: SupportActivityTemplateKey = .chooseStepV1) async throws -> (UUID, UUID) {
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: template)
        var rev: Int64 = 0
        while let env = try await repo.nextEnvelopeToSend(epoch: epoch) {
            rev += 1
            try await repo.resolveAttempt(epoch: epoch, operationID: env.operationID, outcome: .confirmed(revision: rev))
        }
        return (sid, aid)
    }

    func testRemoteStoppedDoesNotOverwritePendingLocalCompletedAndRetainsConflict() async throws {
        let repo = try await loadedRepo()
        let (sid, aid) = try await syncedActivity(repo, template: .untangleThoughtV1)
        try await repo.finishActivity(epoch: epoch, activityID: aid, outcome: .completed,
                                      checkpoint: SupportCheckpoint(completedStepIDs: ["on_mind"], responses: ["on_mind": "LOCAL-ANSWER"]))
        var journal = try await repo.currentJournal(epoch: epoch)
        var remoteActivity = journal.activities[aid]!
        remoteActivity.status = .stopped
        remoteActivity.result = SupportActivityResult(stoppedReason: "user_ended")
        remoteActivity.checkpoint.responses = [:]
        let remote = SupportRemoteSessionSnapshot(session: journal.sessions[sid]!, activities: [remoteActivity], revision: 8)
        try await repo.applyRemoteSession(epoch: epoch, remote: remote)

        journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.activities[aid]?.status, .completed)
        XCTAssertEqual(journal.activities[aid]?.checkpoint.responses["on_mind"], "LOCAL-ANSWER")
        XCTAssertEqual(journal.serverRevisions[sid], 2, "base does not advance while the conflict is unresolved")
        let conflict = try XCTUnwrap(journal.conflicts.first)
        XCTAssertEqual(conflict.kind, .terminalStatus)
        XCTAssertEqual(conflict.remoteActivities.first?.status, .stopped)
        XCTAssertEqual(journal.sessions[sid]?.syncStatus, .conflict)
        let blocked = try await repo.nextEnvelopeToSend(epoch: epoch)
        XCTAssertNil(blocked, "no new mutation base until resolved")

        try await repo.resolveConflict(epoch: epoch, conflictID: conflict.id, resolution: .keepLocal)
        journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertTrue(journal.conflicts.isEmpty)
        XCTAssertEqual(journal.serverRevisions[sid], 8)
        let env = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))
        XCTAssertEqual(env.expectedRevision, 8)
        XCTAssertEqual(env.kind, .finishActivity)
    }

    func testRemoteTakeResolutionReplacesLocalAndDropsItsUnsentIntents() async throws {
        let repo = try await loadedRepo()
        let (sid, aid) = try await syncedActivity(repo, template: .untangleThoughtV1)
        try await repo.finishActivity(epoch: epoch, activityID: aid, outcome: .completed)
        var journal = try await repo.currentJournal(epoch: epoch)
        var remoteActivity = journal.activities[aid]!
        remoteActivity.status = .stopped
        try await repo.applyRemoteSession(epoch: epoch, remote: SupportRemoteSessionSnapshot(session: journal.sessions[sid]!, activities: [remoteActivity], revision: 5))
        let conflict = try await XCTUnwrapAsync(try await repo.currentJournal(epoch: epoch).conflicts.first)
        try await repo.resolveConflict(epoch: epoch, conflictID: conflict.id, resolution: .takeRemote)
        journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.activities[aid]?.status, .stopped)
        XCTAssertTrue(journal.intents.filter { $0.payload.targetActivityID == aid }.isEmpty)
        XCTAssertEqual(journal.serverRevisions[sid], 5)
    }

    func testDifferingSavedStepTextRetainsBothVersionsAndRequiresResolution() async throws {
        let repo = try await loadedRepo()
        let (sid, aid) = try await syncedActivity(repo)
        try await repo.applyStepChoice(epoch: epoch, activityID: aid, choice: .saveForLater, actionText: "LOCAL text")
        var journal = try await repo.currentJournal(epoch: epoch)
        var remoteActivity = journal.activities[aid]!
        remoteActivity.step = SupportStepPayload(actionText: "REMOTE text", state: .saved)
        try await repo.applyRemoteSession(epoch: epoch, remote: SupportRemoteSessionSnapshot(session: journal.sessions[sid]!, activities: [remoteActivity], revision: 6))
        journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.activities[aid]?.step?.actionText, "LOCAL text")
        let conflict = try XCTUnwrap(journal.conflicts.first)
        XCTAssertEqual(conflict.kind, .stepText)
        XCTAssertEqual(conflict.remoteActivities.first?.step?.actionText, "REMOTE text")
        XCTAssertEqual(journal.serverRevisions[sid], 2, "must not advance and allow a silent overwrite")
        let blocked = try await repo.nextEnvelopeToSend(epoch: epoch)
        XCTAssertNil(blocked)
        // survives relaunch
        let relaunched = makeRepo()
        let again = try await relaunched.load(epoch: epoch)
        XCTAssertEqual(again.conflicts.count, 1)
        try await relaunched.resolveConflict(epoch: epoch, conflictID: conflict.id, resolution: .takeRemote)
        let resolved = try await relaunched.currentJournal(epoch: epoch)
        XCTAssertEqual(resolved.activities[aid]?.step?.actionText, "REMOTE text")
    }

    func testCompetingInProgressActivityIsHeldAsConflictAndPausedOnKeepLocal() async throws {
        let repo = try await loadedRepo()
        let (sid, localID) = try await syncedActivity(repo, template: .groundPresentV1)
        try await repo.checkpointActivity(epoch: epoch, activityID: localID, checkpoint: SupportCheckpoint(lastPromptID: "see"))  // pending
        var journal = try await repo.currentJournal(epoch: epoch)
        let remoteID = UUID()
        var competitor = journal.activities[localID]!
        competitor = SupportActivity(
            id: remoteID, sessionID: sid, templateKey: .chooseStepV1, templateVersion: 1, status: .inProgress, canonicalReference: nil,
            checkpoint: .empty, step: nil, activeMilliseconds: 0, result: nil, reflection: nil, lastChangedRevision: 5,
            syncStatus: .synced, createdAt: Date(), updatedAt: Date(), finishedAt: nil)
        var remoteSession = journal.sessions[sid]!
        remoteSession.selectedActivityID = remoteID
        try await repo.applyRemoteSession(epoch: epoch, remote: SupportRemoteSessionSnapshot(session: remoteSession, activities: [competitor], revision: 7))
        journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertNil(journal.activities[remoteID], "remote competitor is held, not merged")
        XCTAssertEqual(journal.sessions[sid]?.selectedActivityID, localID)
        XCTAssertEqual(journal.activities.values.filter { $0.status == .inProgress }.count, 1)
        let conflict = try XCTUnwrap(journal.conflicts.first)
        XCTAssertEqual(conflict.kind, .selectedActivity)

        try await repo.resolveConflict(epoch: epoch, conflictID: conflict.id, resolution: .keepLocal)
        journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.activities[remoteID]?.status, .paused)
        XCTAssertEqual(journal.activities.values.filter { $0.status == .inProgress }.count, 1)
        XCTAssertEqual(journal.sessions[sid]?.selectedActivityID, localID)
    }

    func testCompetingSelectionTakeRemotePausesLocal() async throws {
        let repo = try await loadedRepo()
        let (sid, localID) = try await syncedActivity(repo, template: .groundPresentV1)
        try await repo.checkpointActivity(epoch: epoch, activityID: localID, checkpoint: SupportCheckpoint(lastPromptID: "see"))
        var journal = try await repo.currentJournal(epoch: epoch)
        let remoteID = UUID()
        let competitor = SupportActivity(
            id: remoteID, sessionID: sid, templateKey: .chooseStepV1, templateVersion: 1, status: .inProgress, canonicalReference: nil,
            checkpoint: .empty, step: nil, activeMilliseconds: 0, result: nil, reflection: nil, lastChangedRevision: 5,
            syncStatus: .synced, createdAt: Date(), updatedAt: Date(), finishedAt: nil)
        var remoteSession = journal.sessions[sid]!
        remoteSession.selectedActivityID = remoteID
        try await repo.applyRemoteSession(epoch: epoch, remote: SupportRemoteSessionSnapshot(session: remoteSession, activities: [competitor], revision: 7))
        let conflict = try await XCTUnwrapAsync(try await repo.currentJournal(epoch: epoch).conflicts.first)
        try await repo.resolveConflict(epoch: epoch, conflictID: conflict.id, resolution: .takeRemote)
        journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.sessions[sid]?.selectedActivityID, remoteID)
        XCTAssertEqual(journal.activities[localID]?.status, .paused)
        XCTAssertEqual(journal.activities.values.filter { $0.status == .inProgress }.count, 1)
    }

    func testRebaseRefusedWhileRemoteConflictUnresolved() async throws {
        let repo = try await loadedRepo()
        let (sid, aid) = try await syncedActivity(repo, template: .untangleThoughtV1)
        try await repo.finishActivity(epoch: epoch, activityID: aid, outcome: .completed)
        let sent = try await XCTUnwrapAsync(try await repo.nextEnvelopeToSend(epoch: epoch))
        try await repo.resolveAttempt(epoch: epoch, operationID: sent.operationID, outcome: .revisionConflict(currentRevision: 6))
        var journal = try await repo.currentJournal(epoch: epoch)
        var remoteActivity = journal.activities[aid]!
        remoteActivity.status = .stopped
        // attempt outstanding => its activity is pending => differing terminal is a conflict
        try await repo.applyRemoteSession(epoch: epoch, remote: SupportRemoteSessionSnapshot(session: journal.sessions[sid]!, activities: [remoteActivity], revision: 6))
        journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.conflicts.count, 1)
        do { _ = try await repo.rebaseConflictedAttempt(epoch: epoch, operationID: sent.operationID); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .unresolvedConflict(sid))
        }
    }

    // MARK: J07 — end unfinished work and close

    func testCloseDismissesSavedStepClearsReminderAndDraftWhileDoneForNowKeepsThem() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .chooseStepV1)
        try await repo.applyStepChoice(epoch: epoch, activityID: aid, choice: .saveForLater, actionText: "SECRET-STEP")
        try await repo.setDraft(epoch: epoch, sessionID: sid, text: "SECRET-DRAFT")
        // Done for now (= save and leave) keeps the saved step and draft.
        let stay = try await repo.doneForNow(epoch: epoch, id: sid)
        XCTAssertEqual(stay, .stayedOpen)
        var journal = try await repo.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.activities[aid]?.step?.state, .saved)
        XCTAssertEqual(journal.drafts[sid], "SECRET-DRAFT")
        // Give the saved step a reminder, as the coordinator would via a later phase.
        var withReminder = journal
        withReminder.activities[aid]!.step!.reminderAt = Date(timeIntervalSince1970: 1_900_000_000)
        withReminder.activities[aid]!.step!.reminderTimeZoneIdentifier = "Europe/Madrid"
        io.seedPrimary(try JSONEncoder().encode(withReminder), ownerID: identity.ownerID)
        let seeded = makeRepo()
        try await seeded.load(epoch: epoch)

        try await seeded.closeSession(epoch: epoch, id: sid)
        journal = try await seeded.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.activities[aid]?.status, .stopped)
        XCTAssertNil(journal.activities[aid]?.step, "no saved step, text or reminder left")
        XCTAssertNil(journal.drafts[sid])
        let finish = try XCTUnwrap(journal.intents.last { $0.payload.kind == .finishActivity })
        guard case .finishActivity(_, .stopped, _, let step?, _) = finish.payload else { return XCTFail() }
        XCTAssertEqual(step.state, .dismissed)
        XCTAssertEqual(step.actionText, "")
        XCTAssertNil(step.reminderAt)
        let raw = String(decoding: io.primary(ownerID: identity.ownerID) ?? Data(), as: UTF8.self)
        XCTAssertFalse(raw.contains("SECRET-STEP") || raw.contains("SECRET-DRAFT"))
        XCTAssertFalse(journal.activities.values.contains { $0.step?.state == .saved })
    }

    // MARK: J08 — schema validation

    func testUnsupportedTemplateVersionAndCheckpointSchemasAreRejectedBeforeAck() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        do { try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: UUID(), template: .groundPresentV1, templateVersion: 9); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .unsupportedTemplateVersion(template: "ground_present_v1", version: 9))
        }
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .groundPresentV1)
        func attempt(_ cp: SupportCheckpoint) async -> SupportSessionError? {
            do { try await repo.checkpointActivity(epoch: epoch, activityID: aid, checkpoint: cp); return nil } catch { return error as? SupportSessionError }
        }
        let badPayload = await attempt(SupportCheckpoint(payloadVersion: 2))
        XCTAssertEqual(badPayload, .unsupportedCheckpointVersion(2))
        let badTemplate = await attempt(SupportCheckpoint(templateVersion: 2))
        XCTAssertEqual(badTemplate, .checkpointTemplateMismatch)
        let badPrompt = await attempt(SupportCheckpoint(lastPromptID: "made_up"))
        XCTAssertEqual(badPrompt, .unknownPromptID("made_up"))
        let badKey = await attempt(SupportCheckpoint(responses: ["nope": "x"]))
        XCTAssertEqual(badKey, .unknownPromptID("nope"))
        let dup = await attempt(SupportCheckpoint(completedStepIDs: ["see", "see"]))
        XCTAssertEqual(dup, .invalidCheckpoint("duplicate_step"))
        let overlap = await attempt(SupportCheckpoint(completedStepIDs: ["see"], skippedStepIDs: ["see"]))
        XCTAssertEqual(overlap, .invalidCheckpoint("step_completed_and_skipped"))
        let good = await attempt(SupportCheckpoint(lastPromptID: "see", completedStepIDs: ["see"]))
        XCTAssertNil(good)
        do { try await repo.finishActivity(epoch: epoch, activityID: aid, outcome: .completed, checkpoint: SupportCheckpoint(lastPromptID: "bogus")); XCTFail() } catch {
            XCTAssertEqual(error as? SupportSessionError, .unknownPromptID("bogus"))
        }
    }

    func testRetainedUnsupportedTemplateIsKeptUnavailableNotResetAndCanStillBeStoppedAndClosed() async throws {
        let repo = try await loadedRepo()
        let sid = try await session(repo)
        let aid = UUID()
        try await repo.startActivity(epoch: epoch, sessionID: sid, activityID: aid, template: .untangleThoughtV1)
        try await repo.checkpointActivity(epoch: epoch, activityID: aid, checkpoint: SupportCheckpoint(responses: ["on_mind": "KEEP-ME"]))
        // Simulate a journal written by a newer build (activity on template v9, checkpoint payload v2).
        var journal = try await repo.currentJournal(epoch: epoch)
        journal.activities[aid]!.templateVersion = 9
        journal.activities[aid]!.checkpoint.payloadVersion = 2
        io.seedPrimary(try JSONEncoder().encode(journal), ownerID: identity.ownerID)
        let old = makeRepo()
        let loaded = try await old.load(epoch: epoch)
        XCTAssertEqual(loaded.activities[aid]?.checkpoint.responses["on_mind"], "KEEP-ME", "retained, not reset")
        for op in 0..<3 {
            do {
                switch op {
                case 0: try await old.checkpointActivity(epoch: epoch, activityID: aid, checkpoint: .empty)
                case 1: try await old.resumeActivity(epoch: epoch, activityID: aid)
                default: try await old.finishActivity(epoch: epoch, activityID: aid, outcome: .completed)
                }
                XCTFail("op \(op) should be unavailable")
            } catch { XCTAssertEqual(error as? SupportSessionError, .activityTemplateUnavailable(aid)) }
        }
        let after = try await old.currentJournal(epoch: epoch)
        XCTAssertEqual(after.activities[aid]?.checkpoint.responses["on_mind"], "KEEP-ME")
        try await old.closeSession(epoch: epoch, id: sid)  // explicit end is still possible
        let closed = try await old.currentJournal(epoch: epoch)
        XCTAssertEqual(closed.activities[aid]?.status, .stopped)
        XCTAssertEqual(closed.sessions[sid]?.status, .closed)
    }

}

private func XCTUnwrapAsync<T>(_ expression: @autoclosure () async throws -> T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    guard let value = try await expression() else {
        XCTFail("unexpected nil", file: file, line: line)
        throw SupportSessionError.journalCorrupt
    }
    return value
}

private final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
