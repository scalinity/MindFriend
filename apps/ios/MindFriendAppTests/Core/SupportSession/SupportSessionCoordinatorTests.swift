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
    func testDiscussionPreviewSharesOnlyChosenAnswersPreservesTheDraftAndNeverQueuesASend() async throws {
        let coordinator = try await make(FaultyJournalIO())
        let activity = try await coordinator.start(.untangleThoughtV1, origin: .today)
        var checkpoint = activity.checkpoint
        checkpoint.responses = ["on_mind": "Chosen synthetic answer", "certain_unclear": "Private unselected answer"]
        try await coordinator.checkpoint(activity.id, value: checkpoint)
        coordinator.scheduleDraft("Existing unsent draft", sessionID: activity.sessionID)
        let snapshot = try coordinator.discussionSnapshot(activityID: activity.id)
        let handoff = try await coordinator.prepareActivityDiscussion(snapshot, selected: ["on_mind"], question: "A deliberate question")
        XCTAssertEqual(handoff.sessionID, activity.sessionID)
        XCTAssertNil(handoff.conversationID)
        XCTAssertTrue(handoff.text.hasPrefix("Existing unsent draft"))
        XCTAssertTrue(handoff.text.contains("Chosen synthetic answer"))
        XCTAssertFalse(handoff.text.contains("Private unselected answer"))
        XCTAssertTrue(coordinator.journal.pendingChatRequests.isEmpty)
        XCTAssertEqual(coordinator.journal.drafts[activity.sessionID], handoff.text)
        XCTAssertEqual(coordinator.journal.activities[activity.id]?.checkpoint.responses["certain_unclear"], "Private unselected answer")
        XCTAssertNil(coordinator.consumeChatDraftHandoff(UUID(), sessionID: activity.sessionID))
        XCTAssertEqual(coordinator.consumeChatDraftHandoff(handoff.id, sessionID: activity.sessionID), handoff)
        XCTAssertNil(coordinator.chatDraftHandoff)
        await coordinator.invalidate().value
    }

    func testReflectionStoresOnlyTheApprovedBoundedPreviewAndDiscardScrubsItsQueuedCopy() async throws {
        let coordinator = try await make(FaultyJournalIO())
        let activity = try await coordinator.start(.untangleThoughtV1, origin: .today)
        var checkpoint = activity.checkpoint
        let answer = String(repeating: "👩‍💻", count: 600)
        checkpoint.responses = ["on_mind": answer, "fairer_way": "A later private answer"]
        try await coordinator.finish(activity.id, checkpoint: checkpoint)
        let finished = try XCTUnwrap(coordinator.journal.activities[activity.id])
        let preview = SupportActivityDiscussion.reflectionPreview(finished, note: "Synthetic reflection note")
        XCTAssertLessThanOrEqual(preview.utf16.count, 1_000)
        XCTAssertTrue(preview.contains("👩‍💻"))
        XCTAssertEqual(preview.last, Character("👩‍💻"), "The preview must stop before a whole grapheme rather than split its joiner sequence")
        try await coordinator.reflect(activity.id, outcome: .helpful, note: "Synthetic reflection note", includeAnswers: true)
        let reflected = try XCTUnwrap(coordinator.journal.activities[activity.id])
        XCTAssertEqual(reflected.reflection?.shareableText, preview)
        XCTAssertEqual(reflected.reflection?.note, "Synthetic reflection note")
        XCTAssertEqual(reflected.checkpoint.responses["on_mind"], answer)
        let intent = try XCTUnwrap(coordinator.journal.intents.last)
        guard case .recordReflection(_, let payload) = intent.payload else { return XCTFail("Expected reflection") }
        XCTAssertEqual(payload.shareableText, preview)
        guard case .recordReflection(_, let redacted) = intent.payload.contentRedacted else { return XCTFail("Expected redacted reflection") }
        XCTAssertNil(redacted.shareableText)
        XCTAssertNil(redacted.note)
        XCTAssertFalse(redacted.includeWrittenAnswers)
        try await coordinator.discardAnswers(activity.id)
        XCTAssertNil(coordinator.journal.activities[activity.id]?.reflection)
        let encoded = String(decoding: try JSONEncoder().encode(coordinator.journal), as: UTF8.self)
        XCTAssertFalse(encoded.contains("Synthetic reflection note"))
        XCTAssertFalse(encoded.contains("A later private answer"))
        await coordinator.invalidate().value
    }

    func testDiscussionRejectsAScalarValidEmojiMessageThatExceedsTheChatWireLimit() async throws {
        let coordinator = try await make(FaultyJournalIO())
        let activity = try await coordinator.start(.untangleThoughtV1, origin: .today)
        let snapshot = try coordinator.discussionSnapshot(activityID: activity.id)
        let emoji = String(repeating: "🙂", count: 2_001)
        XCTAssertLessThan(emoji.unicodeScalars.count, SupportSessionLimits.draftMaxCharacters)
        do {
            _ = try await coordinator.prepareActivityDiscussion(snapshot, selected: [], question: emoji)
            XCTFail("The server counts UTF-16 units")
        } catch { XCTAssertEqual(error as? SupportSessionError, .valueTooLong(field: "draft", limit: 4_000)) }
        XCTAssertTrue(coordinator.journal.drafts.isEmpty)
        XCTAssertTrue(coordinator.journal.pendingChatRequests.isEmpty)
        await coordinator.invalidate().value
    }

    func testClosedActivityDiscussionCreatesOneLinkedDraftAtomicallyAndKeepsOldHistoryClosed() async throws {
        let io = FaultyJournalIO(), owner = UUID()
        let coordinator = try await make(io, owner: owner)
        let activity = try await coordinator.start(.chooseStepV1, origin: .today)
        try await coordinator.chooseStep(activity.id, choice: .didIt, text: "A completed synthetic step")
        try await coordinator.reflect(activity.id, outcome: .helpful, note: "A private note", includeAnswers: false)
        try await coordinator.doneForNow(activity.sessionID)
        let old = coordinator.journal.sessions[activity.sessionID]
        let snapshot = try coordinator.discussionSnapshot(activityID: activity.id)
        io.failCommits = true
        do { _ = try await coordinator.prepareActivityDiscussion(snapshot, selected: ["action"], question: "What next?"); XCTFail("Write failed") } catch {}
        XCTAssertEqual(coordinator.journal.sessions.count, 1)
        XCTAssertNil(coordinator.chatDraftHandoff)
        io.failCommits = false
        let handoff = try await coordinator.prepareActivityDiscussion(snapshot, selected: ["action"], question: "What next?")
        XCTAssertEqual(coordinator.journal.sessions.count, 2)
        XCTAssertNotEqual(handoff.sessionID, activity.sessionID)
        XCTAssertNil(handoff.conversationID)
        XCTAssertEqual(coordinator.journal.sessions[handoff.sessionID]?.previousSessionID, activity.sessionID)
        XCTAssertEqual(coordinator.journal.sessions[activity.sessionID], old)
        XCTAssertFalse(handoff.text.contains("A private note"))
        XCTAssertTrue(coordinator.journal.pendingChatRequests.isEmpty)
        await coordinator.invalidate().value
        let relaunched = try await make(io, owner: owner)
        XCTAssertEqual(relaunched.journal.drafts[handoff.sessionID], handoff.text)
        XCTAssertNil(relaunched.chatDraftHandoff, "relaunch restores a draft, never an automatic send")
        await relaunched.invalidate().value
    }

    func testChangedOrDiscardedActivityCannotBeCopiedFromAStaleSharingPreview() async throws {
        let coordinator = try await make(FaultyJournalIO())
        let activity = try await coordinator.start(.untangleThoughtV1, origin: .today)
        var checkpoint = activity.checkpoint
        checkpoint.responses = ["on_mind": "Must be discarded"]
        try await coordinator.checkpoint(activity.id, value: checkpoint)
        let snapshot = try coordinator.discussionSnapshot(activityID: activity.id)
        try await coordinator.discardAnswers(activity.id)
        do { _ = try await coordinator.prepareActivityDiscussion(snapshot, selected: ["on_mind"], question: "Question"); XCTFail("Stale preview") }
        catch { XCTAssertEqual(error as? SupportSessionError, .chatContextChanged) }
        XCTAssertTrue(coordinator.journal.drafts.isEmpty)
        XCTAssertNil(coordinator.chatDraftHandoff)
        await coordinator.invalidate().value
    }

    func testDiscussionDraftBoundsAndUnknownFieldsNeverTruncateOrReplaceSavedWork() async throws {
        let coordinator = try await make(FaultyJournalIO())
        let activity = try await coordinator.start(.untangleThoughtV1, origin: .today)
        try await coordinator.flushDraft("Existing draft", sessionID: activity.sessionID)
        let snapshot = try coordinator.discussionSnapshot(activityID: activity.id)
        do { _ = try await coordinator.prepareActivityDiscussion(snapshot, selected: ["unknown"], question: "Question"); XCTFail("Unknown field") }
        catch { XCTAssertEqual(error as? SupportSessionError, .chatContextChanged) }
        do { _ = try await coordinator.prepareActivityDiscussion(snapshot, selected: [], question: String(repeating: "e\u{301}", count: 2_001)); XCTFail("Oversized") }
        catch { XCTAssertEqual(error as? SupportSessionError, .valueTooLong(field: "draft", limit: SupportSessionLimits.draftMaxCharacters)) }
        XCTAssertEqual(coordinator.journal.drafts[activity.sessionID], "Existing draft")
        XCTAssertNil(coordinator.chatDraftHandoff)
        await coordinator.invalidate().value
    }

    func testConversationActivityRowsReflectAcknowledgedStateAndCarryNoAnswerText() async throws {
        let coordinator = try await make(FaultyJournalIO())
        let activity = try await coordinator.start(.chooseStepV1, origin: .today)
        try await coordinator.chooseStep(activity.id, choice: .saveForLater, text: "Private action text")
        let saved = SupportActivityChatEvent.rows(in: coordinator.journal, sessionID: activity.sessionID)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].stepState, .saved)
        XCTAssertEqual(saved[0].status, .paused)
        try await coordinator.chooseStep(activity.id, choice: .didIt, text: "Private action text")
        try await coordinator.reflect(activity.id, outcome: .notSure, note: "Private note", includeAnswers: false)
        let finished = SupportActivityChatEvent.rows(in: coordinator.journal, sessionID: activity.sessionID)
        XCTAssertEqual(finished.count, 1)
        XCTAssertEqual(finished[0].id, saved[0].id)
        XCTAssertEqual(finished[0].stepState, .selfReportedDone)
        XCTAssertEqual(finished[0].reflection, .notSure)
        XCTAssertFalse(finished[0].answersShared)
        let message = Message(id: UUID().uuidString, role: .user, content: "Later text", createdAt: finished[0].date.addingTimeInterval(1), blocked: false)
        XCTAssertEqual(SupportChatRow.merge(messages: [message], localEvents: [], activityEvents: finished).map(\.id), [finished[0].id, message.id.lowercased()])
        await coordinator.invalidate().value
    }

}
