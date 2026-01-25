import Foundation
import AVFoundation
import Combine
import Supabase

/// Service for managing AR exercise data and session tracking
@MainActor
public final class ARExerciseService: ObservableObject, ARExerciseServiceProtocol {

    // MARK: - Dependencies

    private let dataService: SupabaseDataService
    private let authService: SupabaseAuthService
    private let capabilityService: ARCapabilityService

    // MARK: - Published State

    @Published public private(set) var exercises: [ARExercise] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var error: ARExerciseError?

    // MARK: - Voice Guidance

    private let speechSynthesizer = AVSpeechSynthesizer()
    private var currentVoiceIndex: Int = 0

    // MARK: - Session Tracking

    private var currentSessionId: UUID?
    private var currentSessionStartTime: Date?
    private var trackingQualities: [Double] = []
    private var interruptionCount: Int = 0

    // MARK: - Network Configuration

    private static let maxRetryAttempts = 3
    private static let baseRetryDelay: TimeInterval = 1.0
    private static let requestTimeout: TimeInterval = 30.0

    // MARK: - Initialization

    init(
        supabase dataService: SupabaseDataService,
        authService: SupabaseAuthService,
        capabilityService: ARCapabilityService
    ) {
        self.dataService = dataService
        self.authService = authService
        self.capabilityService = capabilityService
    }

    // MARK: - Fetch Exercises

    /// Fetch AR exercises from backend filtered by device capabilities
    public func fetchARExercises() async throws -> [ARExercise] {
        guard let userId = authService.currentUser?.id else {
            throw ARExerciseError.notAuthenticated
        }

        isLoading = true
        error = nil

        do {
            let capability = capabilityService.capabilityLevel.rawValue

            // Call the database function with retry logic
            let response: [ARExercise] = try await withRetry(maxAttempts: Self.maxRetryAttempts) {
                try await supabase
                    .rpc("get_ar_exercises_for_user", params: [
                        "p_user_id": userId.uuidString,
                        "p_device_capability": capability
                    ])
                    .execute()
                    .value
            }

            exercises = response
            isLoading = false
            return response
        } catch {
            isLoading = false
            let arError = ARExerciseError.networkFailure(error)
            self.error = arError
            throw arError
        }
    }

    /// Get exercises from cache or fetch if empty
    public func getExercises() async -> [ARExercise] {
        if !exercises.isEmpty {
            return exercises
        }
        do {
            return try await fetchARExercises()
        } catch {
            return []
        }
    }

    // MARK: - Session Management

    /// Start a new AR exercise session
    /// - Parameter exercise: The exercise being started
    /// - Returns: Session ID
    public func startSession(exercise: ARExercise) async throws -> UUID {
        guard let userId = authService.currentUser?.id else {
            throw ARExerciseError.notAuthenticated
        }

        // Validate premium access
        if exercise.isPremium {
            let hasPremium = await checkPremiumAccess()
            guard hasPremium else {
                throw ARExerciseError.premiumRequired
            }
        }

        let sessionId = UUID()
        currentSessionId = sessionId
        currentSessionStartTime = Date()
        trackingQualities = []
        interruptionCount = 0
        currentVoiceIndex = 0

        // Insert session record with retry logic
        do {
            let session = ARExerciseSession(
                id: sessionId,
                userId: userId,
                exerciseTypeId: exercise.id,
                startedAt: Date(),
                deviceCapability: capabilityService.capabilityLevel.rawValue,
                usedVoiceGuidance: false,
                completedSteps: 0
            )

            try await withRetry(maxAttempts: Self.maxRetryAttempts) {
                try await supabase
                    .from("ar_exercise_sessions")
                    .insert(session)
                    .execute()
            }

            return sessionId
        } catch {
            // Reset state on failure
            currentSessionId = nil
            currentSessionStartTime = nil
            throw ARExerciseError.networkFailure(error)
        }
    }

    /// Complete the current AR exercise session
    /// - Parameters:
    ///   - sessionId: Session ID to complete
    ///   - completedSteps: Number of steps completed
    ///   - rating: Optional effectiveness rating (1-5)
    public func completeSession(
        sessionId: UUID,
        completedSteps: Int,
        rating: Int? = nil
    ) async throws {
        guard let userId = authService.currentUser?.id else {
            throw ARExerciseError.notAuthenticated
        }
        
        guard currentSessionId == sessionId else {
            throw ARExerciseError.sessionNotFound
        }

        // Validate rating bounds
        let validatedRating: Int?
        if let r = rating {
            validatedRating = max(1, min(5, r))
        } else {
            validatedRating = nil
        }

        // Validate completed steps (non-negative)
        let validatedSteps = max(0, completedSteps)

        let avgTrackingQuality: Double?
        if trackingQualities.isEmpty {
            avgTrackingQuality = nil
        } else {
            avgTrackingQuality = trackingQualities.reduce(0, +) / Double(trackingQualities.count)
        }

        // Update session record with retry logic
        // SECURITY: Filter by both session ID AND user_id to prevent IDOR attacks
        do {
            let updateData = ARSessionCompletionUpdate(
                completedAt: ISO8601DateFormatter().string(from: Date()),
                effectivenessRating: validatedRating,
                trackingQualityAvg: avgTrackingQuality,
                interruptionsCount: interruptionCount,
                usedVoiceGuidance: currentVoiceIndex > 0,
                completedSteps: validatedSteps
            )

            try await withRetry(maxAttempts: Self.maxRetryAttempts) {
                try await supabase
                    .from("ar_exercise_sessions")
                    .update(updateData)
                    .eq("id", value: sessionId.uuidString)
                    .eq("user_id", value: userId.uuidString)
                    .execute()
            }

            // Clear session state
            currentSessionId = nil
            currentSessionStartTime = nil
            trackingQualities = []
        } catch {
            throw ARExerciseError.networkFailure(error)
        }
    }

    /// Record a tracking quality sample
    /// - Parameter quality: Quality value 0-1
    public func recordTrackingQuality(_ quality: Double) {
        trackingQualities.append(min(1.0, max(0.0, quality)))
    }

    /// Record session interruption
    public func recordInterruption() {
        interruptionCount += 1
    }

    /// Abandon current session without completing
    public func abandonSession() async {
        guard let sessionId = currentSessionId,
              let userId = authService.currentUser?.id else { return }

        // Update session with null completion (abandoned)
        // SECURITY: Filter by both session ID AND user_id to prevent IDOR attacks
        let updateData = ARSessionAbandonUpdate(
            interruptionsCount: interruptionCount,
            usedVoiceGuidance: currentVoiceIndex > 0
        )

        try? await supabase
            .from("ar_exercise_sessions")
            .update(updateData)
            .eq("id", value: sessionId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()

        currentSessionId = nil
        currentSessionStartTime = nil
        trackingQualities = []
    }

    // MARK: - Voice Guidance

    /// Speak voice guidance text
    /// - Parameters:
    ///   - text: Text to speak
    ///   - rate: Speech rate (0.0 - 1.0, default 0.5)
    public func speakGuidance(_ text: String, rate: Float = 0.45) {
        // Sanitize text input - remove potential control characters
        let sanitizedText = sanitizeVoiceText(text)
        guard !sanitizedText.isEmpty else { return }
        
        let utterance = AVSpeechUtterance(string: sanitizedText)
        utterance.rate = max(0.0, min(1.0, rate)) // Clamp rate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.8

        // Use default voice for current locale
        if let voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en") {
            utterance.voice = voice
        }

        speechSynthesizer.speak(utterance)
        currentVoiceIndex += 1
    }

    /// Sanitize voice guidance text to prevent injection
    private func sanitizeVoiceText(_ text: String) -> String {
        // Remove control characters and limit length
        let cleaned = text.unicodeScalars
            .filter { !$0.properties.isPatternSyntax && $0.value >= 32 }
            .map { Character($0) }
        return String(String(cleaned).prefix(500))
    }

    /// Speak next guidance from exercise script
    /// - Parameter exercise: Exercise containing voice guidance script
    public func speakNextGuidance(for exercise: ARExercise) {
        guard currentVoiceIndex < exercise.voiceGuidanceScript.count else { return }
        let text = exercise.voiceGuidanceScript[currentVoiceIndex]
        speakGuidance(text)
    }

    /// Stop any ongoing speech
    public func stopGuidance() {
        speechSynthesizer.stopSpeaking(at: .immediate)
    }

    /// Check if speech is in progress
    public var isSpeaking: Bool {
        speechSynthesizer.isSpeaking
    }

    /// Reset voice guidance index
    public func resetVoiceGuidance() {
        currentVoiceIndex = 0
        stopGuidance()
    }

    // MARK: - Premium Access

    /// Check if user has premium access
    private func checkPremiumAccess() async -> Bool {
        guard let userId = authService.currentUser?.id else { return false }
        
        do {
            let subscriptions: [SubscriptionRecord] = try await supabase
                .from("subscriptions")
                .select("status")
                .eq("user_id", value: userId.uuidString)
                .eq("status", value: "active")
                .limit(1)
                .execute()
                .value
            
            return !subscriptions.isEmpty
        } catch {
            // If we can't verify, deny premium access for safety
            return false
        }
    }

    // MARK: - Network Retry Helper

    /// Execute an async operation with exponential backoff retry
    private func withRetry<T>(
        maxAttempts: Int,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Don't retry on auth errors
                if case ARExerciseError.notAuthenticated = error {
                    throw error
                }
                
                // Exponential backoff
                if attempt < maxAttempts - 1 {
                    let delay = Self.baseRetryDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? ARExerciseError.networkFailure(NSError(domain: "ARExercise", code: -1))
    }

    // MARK: - Session History

    /// Fetch user's AR exercise session history
    /// - Parameter limit: Maximum number of sessions to fetch
    /// - Returns: Array of past sessions
    public func fetchSessionHistory(limit: Int = 20) async throws -> [ARExerciseSession] {
        guard let userId = authService.currentUser?.id else {
            throw ARExerciseError.notAuthenticated
        }

        do {
            let sessions: [ARExerciseSession] = try await supabase
                .from("ar_exercise_sessions")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("started_at", ascending: false)
                .limit(limit)
                .execute()
                .value

            return sessions
        } catch {
            throw ARExerciseError.networkFailure(error)
        }
    }

    // MARK: - Scene Preferences

    /// Save scene preference (Safe Space)
    /// - Parameters:
    ///   - name: Scene name
    ///   - data: Scene data
    ///   - isDefault: Whether this is the default scene
    public func saveScenePreference(
        name: String,
        data: ARSceneData,
        isDefault: Bool = false
    ) async throws {
        guard let userId = authService.currentUser?.id else {
            throw ARExerciseError.notAuthenticated
        }

        do {
            // If setting as default, unset any existing defaults first
            if isDefault {
                try await supabase
                    .from("ar_scene_preferences")
                    .update(["is_default": false])
                    .eq("user_id", value: userId.uuidString)
                    .eq("is_default", value: true)
                    .execute()
            }

            // Insert new scene preference
            let insertData = ARScenePreferenceInsert(
                userId: userId.uuidString,
                sceneName: name,
                sceneData: data,
                isDefault: isDefault
            )

            try await supabase
                .from("ar_scene_preferences")
                .insert(insertData)
                .execute()
        } catch {
            throw ARExerciseError.networkFailure(error)
        }
    }

    /// Fetch user's saved scene preferences
    /// - Returns: Array of saved scenes
    public func fetchScenePreferences() async throws -> [ARScenePreference] {
        guard let userId = authService.currentUser?.id else {
            throw ARExerciseError.notAuthenticated
        }

        do {
            let scenes: [ARScenePreference] = try await supabase
                .from("ar_scene_preferences")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("updated_at", ascending: false)
                .execute()
                .value

            return scenes
        } catch {
            throw ARExerciseError.networkFailure(error)
        }
    }

    /// Get default scene preference
    /// - Returns: Default scene or nil
    public func getDefaultScene() async -> ARScenePreference? {
        guard let userId = authService.currentUser?.id else { return nil }

        do {
            let scenes: [ARScenePreference] = try await supabase
                .from("ar_scene_preferences")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("is_default", value: true)
                .limit(1)
                .execute()
                .value

            return scenes.first
        } catch {
            return nil
        }
    }

    /// Delete a scene preference
    /// - Parameter sceneId: ID of scene to delete
    public func deleteScenePreference(_ sceneId: UUID) async throws {
        guard let userId = authService.currentUser?.id else {
            throw ARExerciseError.notAuthenticated
        }
        
        // SECURITY: Filter by both scene ID AND user_id to prevent IDOR attacks
        do {
            try await supabase
                .from("ar_scene_preferences")
                .delete()
                .eq("id", value: sceneId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .execute()
        } catch {
            throw ARExerciseError.networkFailure(error)
        }
    }
}

// MARK: - Helper Encodable Types for Supabase Updates

/// Update data for session completion
private struct ARSessionCompletionUpdate: Encodable {
    let completedAt: String
    let effectivenessRating: Int?
    let trackingQualityAvg: Double?
    let interruptionsCount: Int
    let usedVoiceGuidance: Bool
    let completedSteps: Int

    enum CodingKeys: String, CodingKey {
        case completedAt = "completed_at"
        case effectivenessRating = "effectiveness_rating"
        case trackingQualityAvg = "tracking_quality_avg"
        case interruptionsCount = "interruptions_count"
        case usedVoiceGuidance = "used_voice_guidance"
        case completedSteps = "completed_steps"
    }
}

/// Update data for session abandonment
private struct ARSessionAbandonUpdate: Encodable {
    let interruptionsCount: Int
    let usedVoiceGuidance: Bool

    enum CodingKeys: String, CodingKey {
        case interruptionsCount = "interruptions_count"
        case usedVoiceGuidance = "used_voice_guidance"
    }
}

/// Insert data for scene preferences
private struct ARScenePreferenceInsert: Encodable {
    let userId: String
    let sceneName: String
    let sceneData: ARSceneData
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case sceneName = "scene_name"
        case sceneData = "scene_data"
        case isDefault = "is_default"
    }
}

/// Simple subscription record for premium check
private struct SubscriptionRecord: Decodable {
    let status: String
}
