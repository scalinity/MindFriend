import Foundation
import Combine

/// Protocol for AR exercise service operations
/// Enables dependency injection and testability
@MainActor
public protocol ARExerciseServiceProtocol: ObservableObject {
    // MARK: - Published State

    var exercises: [ARExercise] { get }
    var isLoading: Bool { get }
    var error: ARExerciseError? { get }

    // MARK: - Voice Guidance State

    var isSpeaking: Bool { get }

    // MARK: - Exercise Fetching

    /// Fetch AR exercises from backend filtered by device capabilities
    func fetchARExercises() async throws -> [ARExercise]

    /// Get exercises from cache or fetch if empty
    func getExercises() async -> [ARExercise]

    // MARK: - Session Management

    /// Start a new AR exercise session
    /// - Parameter exercise: The exercise being started
    /// - Returns: Session ID
    func startSession(exercise: ARExercise) async throws -> UUID

    /// Complete the current AR exercise session
    /// - Parameters:
    ///   - sessionId: Session ID to complete
    ///   - completedSteps: Number of steps completed
    ///   - rating: Optional effectiveness rating (1-5)
    func completeSession(sessionId: UUID, completedSteps: Int, rating: Int?) async throws

    /// Record a tracking quality sample
    /// - Parameter quality: Quality value 0-1
    func recordTrackingQuality(_ quality: Double)

    /// Record session interruption
    func recordInterruption()

    /// Abandon current session without completing
    func abandonSession() async

    // MARK: - Voice Guidance

    /// Speak voice guidance text
    /// - Parameters:
    ///   - text: Text to speak
    ///   - rate: Speech rate (0.0 - 1.0, default 0.45)
    func speakGuidance(_ text: String, rate: Float)

    /// Speak next guidance from exercise script
    /// - Parameter exercise: Exercise containing voice guidance script
    func speakNextGuidance(for exercise: ARExercise)

    /// Stop any ongoing speech
    func stopGuidance()

    /// Reset voice guidance index
    func resetVoiceGuidance()

    // MARK: - Session History

    /// Fetch user's AR exercise session history
    /// - Parameter limit: Maximum number of sessions to fetch
    /// - Returns: Array of past sessions
    func fetchSessionHistory(limit: Int) async throws -> [ARExerciseSession]

    // MARK: - Scene Preferences

    /// Save scene preference (Safe Space)
    func saveScenePreference(name: String, data: ARSceneData, isDefault: Bool) async throws

    /// Fetch user's saved scene preferences
    func fetchScenePreferences() async throws -> [ARScenePreference]

    /// Get default scene preference
    func getDefaultScene() async -> ARScenePreference?

    /// Delete a scene preference
    func deleteScenePreference(_ sceneId: UUID) async throws
}

/// Protocol for AR capability detection service
/// Enables dependency injection and testability
public protocol ARCapabilityServiceProtocol: ObservableObject {
    /// Current device capabilities
    var capabilities: ARCapabilities { get }

    /// Overall capability level
    var capabilityLevel: ARCapability { get }

    /// Refresh capability detection
    func refreshCapabilities()

    /// Check if exercise can run on current device
    /// - Parameter exercise: Exercise to check
    /// - Returns: Tuple of (canRun, reason if cannot)
    func canRun(exercise: ARExercise) -> (canRun: Bool, reason: String?)

    /// Check if fallback should be used for exercise
    /// - Parameter exercise: Exercise to check
    /// - Returns: Whether to use fallback mode
    func shouldUseFallback(for exercise: ARExercise) -> Bool

    /// Get fallback suggestions for exercise
    /// - Parameter exercise: Exercise to suggest alternatives for
    /// - Returns: Array of fallback exercise suggestions
    func suggestFallback(for exercise: ARExercise) -> [String]
}

// MARK: - Default Implementations

public extension ARExerciseServiceProtocol {
    func speakGuidance(_ text: String) {
        speakGuidance(text, rate: 0.45)
    }

    func fetchSessionHistory() async throws -> [ARExerciseSession] {
        try await fetchSessionHistory(limit: 20)
    }

    func saveScenePreference(name: String, data: ARSceneData) async throws {
        try await saveScenePreference(name: name, data: data, isDefault: false)
    }
}
