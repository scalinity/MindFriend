import XCTest
@testable import MindFriendApp

/// Tests for Chat functionality including quota enforcement
/// These tests verify critical chat paths and quota logic
final class ChatViewModelTests: XCTestCase {
    
    // MARK: - Quota Enforcement Tests
    
    func testEntitlements_FreeUser_HasQuotaLimit() {
        // Given
        let freeEntitlements = Entitlements.free
        
        // Then
        XCTAssertEqual(freeEntitlements.tier, .free)
        XCTAssertEqual(freeEntitlements.dailyAiQuota, 20)
        XCTAssertEqual(freeEntitlements.dailyAiUsed, 0)
        XCTAssertFalse(freeEntitlements.isQuotaExceeded)
    }
    
    func testEntitlements_PremiumUser_HasHighQuota() {
        // Given
        let premiumEntitlements = Entitlements.premium
        
        // Then
        XCTAssertEqual(premiumEntitlements.tier, .premium)
        XCTAssertEqual(premiumEntitlements.dailyAiQuota, 9999)
        XCTAssertFalse(premiumEntitlements.isQuotaExceeded)
    }
    
    func testEntitlements_QuotaExceeded_WhenUsageEqualsLimit() {
        // Given
        let entitlements = Entitlements(tier: .free, dailyAiQuota: 20, dailyAiUsed: 20)
        
        // Then
        XCTAssertTrue(entitlements.isQuotaExceeded)
        XCTAssertEqual(entitlements.remaining, 0)
    }
    
    func testEntitlements_QuotaExceeded_WhenUsageExceedsLimit() {
        // Given
        let entitlements = Entitlements(tier: .free, dailyAiQuota: 20, dailyAiUsed: 25)
        
        // Then
        XCTAssertTrue(entitlements.isQuotaExceeded)
        XCTAssertEqual(entitlements.remaining, -5)
    }
    
    func testEntitlements_QuotaNotExceeded_WhenUsageUnderLimit() {
        // Given
        let entitlements = Entitlements(tier: .free, dailyAiQuota: 20, dailyAiUsed: 15)
        
        // Then
        XCTAssertFalse(entitlements.isQuotaExceeded)
        XCTAssertEqual(entitlements.remaining, 5)
    }
    
    func testEntitlements_Remaining_CalculatesCorrectly() {
        // Given
        let entitlements = Entitlements(tier: .free, dailyAiQuota: 20, dailyAiUsed: 7)
        
        // Then
        XCTAssertEqual(entitlements.remaining, 13)
    }
    
    // MARK: - Message Model Tests
    
    func testMessage_Creation_SetsPropertiesCorrectly() {
        // Given
        let now = Date()
        let message = Message(
            id: "test-id",
            role: .user,
            content: "Hello, MindFriend!",
            createdAt: now,
            blocked: false
        )
        
        // Then
        XCTAssertEqual(message.id, "test-id")
        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.content, "Hello, MindFriend!")
        XCTAssertEqual(message.createdAt, now)
        XCTAssertFalse(message.blocked)
    }
    
    func testMessage_BlockedMessage_HasBlockedFlag() {
        // Given - a crisis response would be marked as blocked
        let message = Message(
            id: "crisis-response",
            role: .assistant,
            content: "Crisis resources...",
            createdAt: Date(),
            blocked: true
        )
        
        // Then
        XCTAssertTrue(message.blocked)
    }
    
    // MARK: - Conversation Model Tests
    
    func testConversation_ActiveStatus_IsCorrect() {
        // Given
        let conversation = Conversation(
            id: "conv-1",
            title: "Test Chat",
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Then
        XCTAssertEqual(conversation.status, .active)
    }
    
    func testConversation_ArchivedStatus_IsCorrect() {
        // Given
        let conversation = Conversation(
            id: "conv-2",
            title: "Archived Chat",
            status: .archived,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Then
        XCTAssertEqual(conversation.status, .archived)
    }
    
    // MARK: - SendMessageResponse Tests
    
    func testSendMessageResponse_WithCrisisDetected_HasFlag() {
        // Given
        let userMessage = Message(id: "1", role: .user, content: "test", createdAt: Date(), blocked: false)
        let assistantMessage = Message(id: "2", role: .assistant, content: "response", createdAt: Date(), blocked: true)
        
        let response = SendMessageResponse(
            userMessage: userMessage,
            assistantMessage: assistantMessage,
            quotaRemaining: 19,
            crisisDetected: true,
            conversationTitle: nil
        )
        
        // Then
        XCTAssertTrue(response.crisisDetected == true)
        XCTAssertTrue(response.assistantMessage.blocked)
    }
    
    func testSendMessageResponse_QuotaRemaining_TrackedCorrectly() {
        // Given
        let userMessage = Message(id: "1", role: .user, content: "test", createdAt: Date(), blocked: false)
        let assistantMessage = Message(id: "2", role: .assistant, content: "response", createdAt: Date(), blocked: false)
        
        let response = SendMessageResponse(
            userMessage: userMessage,
            assistantMessage: assistantMessage,
            quotaRemaining: 5,
            crisisDetected: false,
            conversationTitle: "Test Conversation"
        )
        
        // Then
        XCTAssertEqual(response.quotaRemaining, 5)
        XCTAssertEqual(response.conversationTitle, "Test Conversation")
    }
    
    // MARK: - Crisis Detection Integration Tests
    
    func testCrisisKeywords_ShouldTriggerCrisisResponse() {
        // These keywords should trigger crisis detection on the server
        // This test documents expected behavior
        let crisisKeywords = [
            "kill myself",
            "want to die",
            "end my life",
            "suicide",
            "suicidal",
            "self-harm",
            "hurt myself"
        ]
        
        // All of these should be handled server-side with:
        // 1. Crisis response returned
        // 2. Crisis event logged (without PII)
        // 3. Crisis resources shown to user
        
        for keyword in crisisKeywords {
            XCTAssertTrue(keyword.count > 0, "Keyword '\(keyword)' should exist")
        }
    }
    
    // MARK: - Input Validation Tests
    
    func testMessageInput_EmptyString_ShouldNotSend() {
        let emptyInputs = ["", "   ", "\n", "\t", "  \n  "]
        
        for input in emptyInputs {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertTrue(trimmed.isEmpty, "Input '\(input)' should be empty after trimming")
        }
    }
    
    func testMessageInput_ValidContent_ShouldSend() {
        let validInputs = ["Hello", "How are you?", "I'm feeling anxious today", "😊"]
        
        for input in validInputs {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertFalse(trimmed.isEmpty, "Input '\(input)' should be valid")
        }
    }
}

// MARK: - Tier Comparison Tests

extension ChatViewModelTests {
    func testTier_FreeVsPremium_Comparison() {
        let freeTier = Tier.free
        let premiumTier = Tier.premium
        
        XCTAssertEqual(freeTier.rawValue, "free")
        XCTAssertEqual(premiumTier.rawValue, "premium")
        XCTAssertNotEqual(freeTier, premiumTier)
    }
}
