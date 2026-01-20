import Foundation

/// Service for AI chat - uses Supabase Edge Functions
@MainActor
final class ChatService: ObservableObject {
    private let dataService: SupabaseDataService

    init(dataService: SupabaseDataService) {
        self.dataService = dataService
    }

    func createConversation(title: String? = nil) async throws -> Conversation {
        try await dataService.createConversation(title: title)
    }

    func getConversations() async throws -> [Conversation] {
        try await dataService.getConversations()
    }

    func deleteConversation(id: String) async throws {
        try await dataService.deleteConversation(id: id)
    }

    func getMessages(conversationId: String, limit: Int = 50) async throws -> [Message] {
        try await dataService.getMessages(conversationId: conversationId, limit: limit)
    }

    /// Send a message and get AI response via Edge Function
    func sendMessage(conversationId: String, content: String) async throws -> SendMessageResponse {
        // Call Edge Function which saves both messages and returns AI response
        let response = try await dataService.sendMessage(
            conversationId: conversationId,
            content: content
        )

        // Create user message with server-provided ID for consistency
        let userMessage = Message(
            id: response.userMessageId ?? UUID().uuidString,  // Use server ID, fallback for safety
            role: .user,
            content: content,
            createdAt: Date(),
            blocked: false
        )

        // Calculate quota remaining - use Int.max for unlimited (safer than sentinel -1)
        let quotaRemaining: Int
        if let limit = response.quotaLimit, limit > 0, let used = response.quotaUsed {
            quotaRemaining = max(0, limit - used)
        } else {
            quotaRemaining = Int.max // Unlimited (premium)
        }

        return SendMessageResponse(
            userMessage: userMessage,
            assistantMessage: response.message,
            quotaRemaining: quotaRemaining,
            quotaUsed: response.quotaUsed,       // Pass through for UI syncing
            quotaLimit: response.quotaLimit,     // Pass through for UI syncing
            crisisDetected: response.isCrisisResponse,
            conversationTitle: response.conversationTitle
        )
    }

    /// Insert a message directly (used for voice transcripts and offline flows)
    func insertMessage(conversationId: String, role: MessageRole, content: String) async throws -> Message {
        try await dataService.insertMessage(conversationId: conversationId, role: role, content: content)
    }

    /// Generate a title for a conversation based on content (used for voice mode)
    func generateConversationTitle(conversationId: String, content: String) async throws -> String {
        try await dataService.generateConversationTitle(conversationId: conversationId, content: content)
    }
}
