import XCTest
@testable import MindFriendApp

@MainActor
final class SupportSessionCoordinatorTests: XCTestCase {
    private func make(_ io: FaultyJournalIO, owner: UUID = UUID()) async throws -> SupportSessionCoordinator {
        let coordinator = SupportSessionCoordinator(repository: SupportSessionRepository(
            identity: SupportSessionIdentity(ownerID: owner), io: io))
        try await coordinator.load()
        return coordinator
    }

    func testDoneDuringDebounceKeepsLatestDraftAndSessionOpen() async throws {
        let coordinator = try await make(FaultyJournalIO())
        let session = try await coordinator.createSession()
        coordinator.scheduleDraft("Still writing", sessionID: session.id)
        try await coordinator.doneForNow(session.id)
        XCTAssertEqual(coordinator.journal.drafts[session.id], "Still writing")
        XCTAssertEqual(coordinator.journal.sessions[session.id]?.status, .open)
    }

    func testNavigationFlushCannotBeOverwrittenByOlderDebounce() async throws {
        let coordinator = try await make(FaultyJournalIO())
        let session = try await coordinator.createSession()
        coordinator.scheduleDraft("Earlier", sessionID: session.id)
        try await coordinator.flushDraft("Latest", sessionID: session.id)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(coordinator.journal.drafts[session.id], "Latest")
    }

    func testFailedCheckpointDoesNotPublishAdvanceOrSaved() async throws {
        let io = FaultyJournalIO()
        let coordinator = try await make(io)
        let activity = try await coordinator.start(.groundPresentV1, origin: .today)
        io.failCommits = true
        do {
            try await coordinator.checkpoint(activity.id, value: SupportCheckpoint(completedStepIDs: ["see"]))
            XCTFail("Write failure must propagate")
        } catch {}
        XCTAssertTrue(coordinator.journal.activities[activity.id]!.checkpoint.completedStepIDs.isEmpty)
        XCTAssertNotNil(coordinator.localSaveError)
    }

    func testInvalidatedCoordinatorCannotStartOrPublishIntoAnotherAccount() async throws {
        let io = FaultyJournalIO()
        let previous = try await make(io)
        let session = try await previous.createSession()
        previous.scheduleDraft("Owner A draft", sessionID: session.id)
        previous.invalidate()
        let next = try await make(io)
        do { _ = try await previous.start(.untangleThoughtV1, origin: .today); XCTFail("Ended scope") }
        catch { XCTAssertEqual(error as? SupportSessionError, .invalidated) }
        XCTAssertNil(previous.activityPresentation)
        XCTAssertTrue(next.journal.sessions.isEmpty)
        XCTAssertTrue(next.journal.drafts.isEmpty)
    }

    func testUnknownExplicitSessionDoesNotCreateAnotherSession() async throws {
        let coordinator = try await make(FaultyJournalIO())
        let missing = UUID()
        do { _ = try await coordinator.start(.groundPresentV1, in: missing, origin: .today); XCTFail("Missing session") }
        catch { XCTAssertEqual(error as? SupportSessionError, .sessionNotFound(missing)) }
        XCTAssertTrue(coordinator.journal.sessions.isEmpty)
    }

    func testExternalDiscardReconcilesActivityAndClosedSessionRejectsLateDraft() async throws {
        let coordinator = try await make(FaultyJournalIO())
        let activity = try await coordinator.start(.untangleThoughtV1, origin: .today)
        try await coordinator.repository.discardActivityAnswers(epoch: coordinator.identity.epochID, activityID: activity.id)
        for _ in 0..<50 where coordinator.activityPresentation != nil { await Task.yield() }
        XCTAssertNil(coordinator.activityPresentation)
        try await coordinator.close(activity.sessionID)
        coordinator.scheduleDraft("Late plaintext", sessionID: activity.sessionID)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertNil(coordinator.journal.drafts[activity.sessionID])
        XCTAssertNil(coordinator.localSaveError)
    }

    func testInvalidationCompletionPrecedesSameOwnerReload() async throws {
        let io = FaultyJournalIO()
        let owner = UUID()
        let previous = try await make(io, owner: owner)
        let session = try await previous.createSession()
        await previous.invalidate().value
        let next = try await make(io, owner: owner)
        XCTAssertEqual(next.journal.sessions[session.id]?.id, session.id)
        do { try await previous.rename(session.id, title: "Old callback"); XCTFail("Invalidated") } catch {}
        XCTAssertNotEqual(next.journal.sessions[session.id]?.title, "Old callback")
    }
}
