import Foundation

/// Service for mood tracking
final class MoodService: Sendable {
    private let apiClient: APIClient

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func createMood(_ mood: MoodEntry) async throws -> MoodEntry {
        try await apiClient.request(.createMood(mood))
    }

    func getMoods(from: String, to: String) async throws -> [MoodEntry] {
        try await apiClient.request(.getMoods(from: from, to: to))
    }

    func getMoodsForPast(days: Int) async throws -> [MoodEntry] {
        let to = Self.dateFormatter.string(from: Date())
        let from: String
        if let pastDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) {
            from = Self.dateFormatter.string(from: pastDate)
        } else {
            from = to
        }

        return try await getMoods(from: from, to: to)
    }
}
