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

    func saveVoiceTranscript(conversationId: UUID, title: String?, messages: [VoiceTranscriptMessage]) async throws {
        try await dataService.saveVoiceTranscript(conversationId: conversationId, title: title, messages: messages)
    }

    func getConversations() async throws -> [Conversation] {
        try await dataService.getConversations()
    }

    func getConversationPage(before cursor: ChatHistoryCursor? = nil) async throws -> ChatHistoryPage<Conversation> {
        try await dataService.getConversationPage(before: cursor)
    }

    func deleteConversation(id: String) async throws {
        try await dataService.deleteConversation(id: id)
    }

    func getMessages(conversationId: String, limit: Int = 50) async throws -> [Message] {
        try await dataService.getMessages(conversationId: conversationId, limit: limit)
    }

    func getMessagePage(conversationId: String, before cursor: ChatHistoryCursor? = nil) async throws -> ChatHistoryPage<Message> {
        try await dataService.getMessagePage(conversationId: conversationId, before: cursor)
    }

    /// Send a message and get AI response via Edge Function
    func sendMessage(conversationId: String, content: String, requestId: UUID = UUID(), retryFailed: Bool = false, supportContext: SupportChatRequestContext? = nil, ownerProof: (@Sendable () async -> OfflineOwnerProof?)? = nil, onDelta: ((String) -> Void)? = nil) async throws -> SendMessageResponse {
        // Call Edge Function which saves both messages and returns AI response
        let response = try await dataService.sendMessage(
            conversationId: conversationId,
            content: content,
            requestId: requestId,
            retryFailed: retryFailed,
            supportContext: supportContext, ownerProof: ownerProof,
            onDelta: onDelta
        )

        // Create user message (server saves it, we create local representation)
        let userMessage = response.userMessage ?? Message(
            id: UUID().uuidString,
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
            conversationTitle: response.conversationTitle,
            memoryUsed: response.memoryUsed,
            memoryIdsUsed: response.memoryIdsUsed,
            coachData: response.coachData,
            support: response.support
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
