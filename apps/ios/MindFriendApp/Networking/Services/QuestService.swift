import Foundation

/// Service for daily quests
final class QuestService: Sendable {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func getTodayQuest() async throws -> Quest {
        try await apiClient.request(.getTodayQuest)
    }

    func completeQuest(id: String, reflectionNote: String?, rating: Int?) async throws -> QuestCompletion {
        try await apiClient.request(.completeQuest(id: id, reflectionNote: reflectionNote, rating: rating))
    }

    func skipQuest(id: String) async throws {
        try await apiClient.requestVoid(.skipQuest(id: id))
    }
}
