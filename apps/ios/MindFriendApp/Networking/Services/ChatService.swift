import Foundation

/// Service for AI chat
final class ChatService: Sendable {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func createConversation(title: String? = nil) async throws -> Conversation {
        try await apiClient.request(.createConversation(title: title))
    }

    func getConversations() async throws -> [Conversation] {
        try await apiClient.request(.getConversations)
    }

    func getMessages(conversationId: String, limit: Int = 50) async throws -> [Message] {
        try await apiClient.request(.getMessages(conversationId: conversationId, limit: limit))
    }

    func sendMessage(conversationId: String, content: String) async throws -> SendMessageResponse {
        try await apiClient.request(.sendMessage(conversationId: conversationId, content: content))
    }
}
