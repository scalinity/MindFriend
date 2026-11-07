import XCTest
@testable import MindFriendApp

final class SupportChatJournalTests: XCTestCase {
    private func make(_ io: FaultyJournalIO = FaultyJournalIO(), owner: UUID = UUID()) async throws -> SupportSessionRepository {
        let repository = SupportSessionRepository(identity: .init(ownerID: owner), io: io)
        _ = try await repository.load(epoch: repository.identity.epochID)
        return repository
    }

    func testLazyAttachmentCanRewriteOnlyAnUnsentCreate() async throws {
        let repository = try await make(), epoch = repository.identity.epochID
        let session = try await repository.createSession(epoch: epoch, id: UUID())
        let before = try await repository.currentJournal(epoch: epoch)
        let conversation = UUID()
        try await repository.attachConversation(epoch: epoch, sessionID: session.id, conversationID: conversation)
        let after = try await repository.currentJournal(epoch: epoch)
        XCTAssertEqual(after.intents.count, 1)
        XCTAssertEqual(after.intents[0].operationID, before.intents[0].operationID)
        guard case .create(_, _, let attached, _, _) = after.intents[0].payload else { return XCTFail("Still an unsent create") }
        XCTAssertEqual(attached, conversation)
    }

    func testAttachmentNeverRewritesATransmittedCreate() async throws {
        let repository = try await make(), epoch = repository.identity.epochID
        let session = try await repository.createSession(epoch: epoch, id: UUID())
        let pendingOriginal = try await repository.nextEnvelopeToSend(epoch: epoch)
        let original = try XCTUnwrap(pendingOriginal)
        let conversation = UUID()
        try await repository.attachConversation(epoch: epoch, sessionID: session.id, conversationID: conversation)
        let after = try await repository.currentJournal(epoch: epoch)
        XCTAssertEqual(after.attempts[0].envelope, original)
        try await repository.resolveAttempt(epoch: epoch, operationID: original.operationID, outcome: .confirmed(revision: 1))
        let pendingNext = try await repository.nextEnvelopeToSend(epoch: epoch)
        let next = try XCTUnwrap(pendingNext)
        XCTAssertEqual(next.expectedRevision, 1)
        XCTAssertEqual(next.payload, .attachConversation(conversationID: conversation))
    }

    func testDeliberateSendSurvivesReloadWithSameIdentityAndNeverQueuesItself() async throws {
        let io = FaultyJournalIO(), owner = UUID(), repository = try await make(io, owner: owner)
        let epoch = repository.identity.epochID, conversation = UUID(), id = UUID()
        let session = try await repository.createSession(epoch: epoch, id: UUID(), conversationID: conversation, contextScope: .conversationOnly)
        let before = try await repository.currentJournal(epoch: epoch)
        let pending = try await repository.prepareChatRequest(epoch: epoch, sessionID: session.id, requestID: id,
            content: "Synthetic concern", scope: .conversationOnly, privacyRevision: 4)
        let after = try await repository.currentJournal(epoch: epoch)
        XCTAssertEqual(after.intents, before.intents)
        await repository.invalidate()
        let reloaded = try await make(io, owner: owner)
        let journal = try await reloaded.currentJournal(epoch: reloaded.identity.epochID)
        XCTAssertEqual(journal.pendingChatRequests[id], pending)
        XCTAssertEqual(journal.intents, before.intents, "No hidden send appears after relaunch")
    }

    func testPendingIdentityCannotBeChangedOrReplacedBeforeReconciliation() async throws {
        let repository = try await make(), epoch = repository.identity.epochID, id = UUID()
        let session = try await repository.createSession(epoch: epoch, id: UUID(), conversationID: UUID(), contextScope: .conversationOnly)
        _ = try await repository.prepareChatRequest(epoch: epoch, sessionID: session.id, requestID: id,
            content: "Synthetic concern", scope: .conversationOnly, privacyRevision: 2)
        do {
            _ = try await repository.prepareChatRequest(epoch: epoch, sessionID: session.id, requestID: id,
                content: "Changed concern", scope: .conversationOnly, privacyRevision: 2)
            XCTFail("Changed request identity")
        } catch { XCTAssertEqual(error as? SupportSessionError, .operationIDReused(id)) }
        do {
            _ = try await repository.prepareChatRequest(epoch: epoch, sessionID: session.id, requestID: UUID(),
                content: "Another concern", scope: .conversationOnly, privacyRevision: 2)
            XCTFail("Unknown previous outcome")
        } catch { XCTAssertEqual(error as? SupportSessionError, .chatRequestNeedsReconciliation(id)) }
    }

    func testRequestAcknowledgementWriteFailureKeepsOriginalForReconciliation() async throws {
        let io = FaultyJournalIO(), repository = try await make(io), epoch = repository.identity.epochID
        let session = try await repository.createSession(epoch: epoch, id: UUID(), conversationID: UUID(), contextScope: .conversationOnly), id = UUID()
        _ = try await repository.prepareChatRequest(epoch: epoch, sessionID: session.id, requestID: id,
            content: "Synthetic concern", scope: .conversationOnly, privacyRevision: 2)
        io.failCommits = true
        do { try await repository.settleChatRequest(epoch: epoch, requestID: id); XCTFail("Local acknowledgement failed") }
        catch {}
        let journal = try await repository.currentJournal(epoch: epoch)
        XCTAssertNotNil(journal.pendingChatRequests[id])
    }

    func testDeleteRemovesPendingTextCopies() async throws {
        let io = FaultyJournalIO(), repository = try await make(io), epoch = repository.identity.epochID
        let session = try await repository.createSession(epoch: epoch, id: UUID(), conversationID: UUID(), contextScope: .conversationOnly)
        _ = try await repository.prepareChatRequest(epoch: epoch, sessionID: session.id, requestID: UUID(),
            content: "UNIQUE_SYNTHETIC_PENDING_CONTENT", scope: .conversationOnly, privacyRevision: 2)
        try await repository.deleteSession(epoch: epoch, id: session.id)
        let journal = try await repository.currentJournal(epoch: epoch)
        XCTAssertTrue(journal.pendingChatRequests.isEmpty)
        XCTAssertFalse(String(decoding: try XCTUnwrap(io.primary(ownerID: repository.identity.ownerID)), as: UTF8.self).contains("UNIQUE_SYNTHETIC_PENDING_CONTENT"))
    }

    func testProposalAcceptanceCreatesOneExecutionAndNoAutomaticCompletion() async throws {
        let repository = try await make(), epoch = repository.identity.epochID, proposal = UUID()
        let session = try await repository.createSession(epoch: epoch, id: UUID())
        let first = try await repository.startActivity(epoch: epoch, sessionID: session.id, activityID: UUID(),
            template: .chooseStepV1, acceptedProposalID: proposal, suggestedStep: "Editable synthetic suggestion")
        let second = try await repository.startActivity(epoch: epoch, sessionID: session.id, activityID: UUID(),
            template: .chooseStepV1, acceptedProposalID: proposal)
        XCTAssertEqual(first.id, second.id)
        let journal = try await repository.currentJournal(epoch: epoch)
        XCTAssertEqual(journal.activities.count, 1)
        XCTAssertEqual(journal.intents.filter { $0.payload.kind == .acceptProposal }.count, 1)
        XCTAssertEqual(first.checkpoint.responses["action"], "Editable synthetic suggestion")
        XCTAssertNil(first.step)
        XCTAssertEqual(first.status, .inProgress)
        XCTAssertFalse(journal.events.contains { $0.kind == .activityCompleted })
    }

    func testLateVoiceFinalKeepsProviderOrderAcrossRelaunchAndLaterCall() async throws {
        let io = FaultyJournalIO(), owner = UUID(), repository = try await make(io, owner: owner)
        let epoch = repository.identity.epochID, conversation = UUID(), firstCall = UUID()
        let session = try await repository.createSession(epoch: epoch, id: UUID(), conversationID: conversation)
        let base = try await repository.reserveVoiceTranscriptOrder(epoch: epoch, sessionID: session.id)
        _ = try await repository.appendTranscriptEvent(epoch: epoch, sessionID: session.id, conversationID: conversation,
            role: .assistant, text: "Synthetic reply", providerEventID: "assistant-final", isFinal: true,
            orderedSequence: base + 2, voiceCallID: firstCall, providerOrder: 2)
        _ = try await repository.appendTranscriptEvent(epoch: epoch, sessionID: session.id, conversationID: conversation,
            role: .user, text: "Synthetic earlier speech", providerEventID: "user-final", isFinal: true,
            orderedSequence: base + 1, voiceCallID: firstCall, providerOrder: 1)
        let secondBase = try await repository.reserveVoiceTranscriptOrder(epoch: epoch, sessionID: session.id)
        _ = try await repository.appendTranscriptEvent(epoch: epoch, sessionID: session.id, conversationID: conversation,
            role: .user, text: "Synthetic later call", providerEventID: "user-final", isFinal: true,
            orderedSequence: secondBase + 1, voiceCallID: UUID(), providerOrder: 1)
        await repository.invalidate()
        let reloaded = try await make(io, owner: owner)
        let events = try await reloaded.pendingTranscriptEvents(epoch: reloaded.identity.epochID)
        XCTAssertEqual(events.map(\.role), [.user, .assistant, .user])
        XCTAssertEqual(events.map(\.text), ["Synthetic earlier speech", "Synthetic reply", "Synthetic later call"])
        XCTAssertEqual(events.map(\.sequence), [base + 1, base + 2, secondBase + 1])
        XCTAssertEqual(events.first?.voiceCallID, firstCall)
    }

    func testVoiceOrderReservationDoesNotAcknowledgeAFailedLocalWrite() async throws {
        let io = FaultyJournalIO(), repository = try await make(io), epoch = repository.identity.epochID
        let session = try await repository.createSession(epoch: epoch, id: UUID())
        io.failCommits = true
        do { _ = try await repository.reserveVoiceTranscriptOrder(epoch: epoch, sessionID: session.id); XCTFail("Reservation was not saved") }
        catch {}
        io.failCommits = false
        let base = try await repository.reserveVoiceTranscriptOrder(epoch: epoch, sessionID: session.id)
        XCTAssertEqual(base, 0)
    }

    func testPendingVoiceEventCannotChangeTextOrOwnerContextUnderSameIdentity() async throws {
        let repository = try await make(), epoch = repository.identity.epochID, id = UUID()
        let session = try await repository.createSession(epoch: epoch, id: UUID(), conversationID: UUID())
        _ = try await repository.appendTranscriptEvent(epoch: epoch, sessionID: session.id,
            conversationID: session.conversationID, role: .user, text: "Original synthetic final", isFinal: true, localID: id)
        do {
            _ = try await repository.appendTranscriptEvent(epoch: epoch, sessionID: session.id,
                conversationID: session.conversationID, role: .user, text: "Changed synthetic final", isFinal: true, localID: id)
            XCTFail("Changed immutable final")
        } catch { XCTAssertEqual(error as? SupportSessionError, .operationIDReused(id)) }
        let events = try await repository.pendingTranscriptEvents(epoch: epoch)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.text, "Original synthetic final")
    }
}
