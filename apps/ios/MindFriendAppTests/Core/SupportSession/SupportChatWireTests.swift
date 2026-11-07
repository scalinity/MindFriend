import XCTest
@testable import MindFriendApp

@MainActor
final class SupportChatWireTests: XCTestCase {
    private let owner = OfflineOwnerProof(userId: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!, epoch: 3)
    private let session = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let conversation = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    private let request = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
    private let assistant = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
    private var context: SupportChatRequestContext { .init(owner: owner, sessionID: session, scope: .conversationOnly, privacyRevision: 7) }

    private func metadata(_ edit: (inout [String: Any]) -> Void = { _ in }) throws -> SupportChatMetadata {
        var body: [String: Any] = ["schema_version":1, "request_id":request.uuidString, "support_session_id":session.uuidString,
            "conversation_id":conversation.uuidString, "scope":"conversation_only", "privacy_revision":7, "content_origin":"model",
            "status":"completed", "suppress_ordinary_cards":false, "confirmed":true,
            "context_receipt":["schema_version":1,"receipt_id":"66666666-6666-4666-8666-666666666666",
                "request_id":request.uuidString,"support_session_id":session.uuidString,"conversation_id":conversation.uuidString,
                "assistant_message_id":assistant.uuidString,"privacy_revision":7,"scope":"conversation_only",
                "provider":["vendor":"openai","model":"gpt-6-luna","route_version":"responses-chat-1"],
                "sources":[["kind":"safety_policy","id":"00000000-0000-0000-0000-000000000001","revision":0]],
                "exclusions":["saved_memory","daily_intent"],"created_at":"2026-11-06T22:00:00.123Z"]]
        edit(&body)
        return try JSONDecoder().decode(SupportChatMetadata.self, from: JSONSerialization.data(withJSONObject: body))
    }

    func testRequestBodyCarriesExactContextAndReplayIsByteStable() throws {
        let first = try SupabaseDataService.chatRequestBody(conversationID: conversation.uuidString, content: "Synthetic concern",
            requestID: request.uuidString, retryFailed: false, context: context)
        let replay = try SupabaseDataService.chatRequestBody(conversationID: conversation.uuidString, content: "Synthetic concern",
            requestID: request.uuidString, retryFailed: false, context: context)
        XCTAssertEqual(first, replay)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: first) as? [String: Any])
        XCTAssertEqual(body["expected_owner"] as? String, owner.userId.uuidString.lowercased())
        XCTAssertEqual(body["support_session_id"] as? String, session.uuidString.lowercased())
        XCTAssertEqual(body["context_scope"] as? String, "conversation_only")
        XCTAssertEqual(body["expected_privacy_revision"] as? Int, 7)
        XCTAssertNil(body["accountEpoch"])
        let legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: SupabaseDataService.chatRequestBody(
            conversationID: conversation.uuidString, content: "Synthetic", requestID: request.uuidString,
            retryFailed: false, context: nil)) as? [String: Any])
        XCTAssertNil(legacy["schema_version"])
    }

    func testLegacyReplyMetadataIsUnavailableAndNotInvented() throws {
        let data = try JSONSerialization.data(withJSONObject: ["message":["id":assistant.uuidString,"role":"assistant",
            "content":"Synthetic response","createdAt":1_000,"blocked":false]])
        let response = try ChatFunctionResponse.decode(data)
        XCTAssertNil(response.support)
        XCTAssertNil(response.memoryUsed)
    }

    func testReceiptMustMatchPreparedRequestMessageScopeAndPrivacy() throws {
        let valid = try metadata()
        XCTAssertTrue(valid.validates(context: context, conversationID: conversation, requestID: request, assistantID: assistant.uuidString, isSafety: false))
        for changed in ["request_id", "support_session_id", "conversation_id"] {
            let value = try metadata { $0[changed] = UUID().uuidString }
            XCTAssertFalse(value.validates(context: context, conversationID: conversation, requestID: request, assistantID: assistant.uuidString, isSafety: false))
        }
        for key in ["assistant_message_id", "request_id", "support_session_id", "conversation_id"] {
            let value = try metadata { var receipt = $0["context_receipt"] as! [String:Any];receipt[key] = UUID().uuidString;$0["context_receipt"] = receipt }
            XCTAssertFalse(value.validates(context: context, conversationID: conversation, requestID: request, assistantID: assistant.uuidString, isSafety: false))
        }
        let stale = try metadata { $0["privacy_revision"] = 6 }
        XCTAssertFalse(stale.validates(context: context, conversationID: conversation, requestID: request, assistantID: assistant.uuidString, isSafety: false))
    }

    func testConversationOnlyCannotAcceptAReceiptContainingSavedMemory() throws {
        let value = try metadata {
            var receipt = $0["context_receipt"] as! [String: Any]
            receipt["sources"] = [["kind":"companion_memory","id":UUID().uuidString,"revision":2]]
            $0["context_receipt"] = receipt
        }
        XCTAssertFalse(value.validates(context: context, conversationID: conversation, requestID: request, assistantID: assistant.uuidString, isSafety: false))
    }

    func testCapabilityHandshakeFailsClosedWhenAnyRequiredLayerIsMissing() throws {
        for body in [[:], ["chat_contract":1], ["chat_contract":1,"session_contract":1,"context_policy":1]] as [[String:Any]] {
            let value = try JSONDecoder().decode(SupportChatCapabilities.self, from: JSONSerialization.data(withJSONObject: body))
            XCTAssertFalse(value.allowsSessionChat)
        }
        let data = Data(#"{"chat_contract":1,"session_contract":1,"context_policy":1,"privacy_revision":true,"chat_confirmation":true,"voice_context":0}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(SupportChatCapabilities.self, from: data).allowsSessionChat)
    }

    func testProposalExpiresAndCannotSurviveAChangedScopeOrRevision() throws {
        let expiry = "2026-11-07T22:00:00Z"
        let value = try metadata { $0["proposal"] = ["id":UUID().uuidString,"template_key":"ground_present_v1",
            "reason_code":"general_option","status":"offered","expires_at":expiry] }
        let before = SupportChatTimestamp.date("2026-11-06T23:00:00Z")!
        XCTAssertNotNil(value.actionableProposal(now: before, scope: .conversationOnly, privacyRevision: 7))
        XCTAssertNil(value.actionableProposal(now: SupportChatTimestamp.date(expiry)!, scope: .conversationOnly, privacyRevision: 7))
        XCTAssertNil(value.actionableProposal(now: before, scope: .personalized, privacyRevision: 7))
        XCTAssertNil(value.actionableProposal(now: before, scope: .conversationOnly, privacyRevision: 8))
    }
}
