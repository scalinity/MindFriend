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
        // First, add the user's message to the local list immediately
        let userMessage = Message(
            id: UUID().uuidString,
            role: .user,
            content: content,
            createdAt: Date(),
            blocked: false
        )

        // Call Edge Function which saves both messages and returns AI response
        let response = try await dataService.sendMessage(
            conversationId: conversationId,
            content: content
        )

        // Calculate quota remaining
        let quotaRemaining: Int
        if let limit = response.quotaLimit, limit > 0, let used = response.quotaUsed {
            quotaRemaining = max(0, limit - used)
        } else {
            quotaRemaining = -1 // Unlimited (premium)
        }

        return SendMessageResponse(
            userMessage: userMessage,
            assistantMessage: response.message,
            quotaRemaining: quotaRemaining,
            crisisDetected: response.isCrisisResponse,
            conversationTitle: response.conversationTitle
        )
    }
}
