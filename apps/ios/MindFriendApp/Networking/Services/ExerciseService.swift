import Foundation

/// Service for exercises
final class ExerciseService: Sendable {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func getExercises(type: ExerciseType? = nil) async throws -> [Exercise] {
        try await apiClient.request(.getExercises(type: type))
    }

    func startExercise(id: String) async throws -> ExerciseSession {
        try await apiClient.request(.startExercise(id: id))
    }

    func completeSession(sessionId: String, rating: Int?, note: String?) async throws {
        try await apiClient.requestVoid(.completeExerciseSession(sessionId: sessionId, rating: rating, note: note))
    }
}
