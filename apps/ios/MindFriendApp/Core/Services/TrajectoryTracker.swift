//
//  TrajectoryTracker.swift
//  MindFriendApp
//
//  Intervention Efficacy Engine - Trajectory Tracking Service
//  Samples emotional state every 30 seconds during exercise sessions
//

import Foundation
import Supabase

@MainActor
final class TrajectoryTracker: ObservableObject {
    @Published private(set) var isTracking = false
    @Published private(set) var currentTrajectory: [TrajectoryPoint] = []
    
    private let supabase: SupabaseClient
    private var timer: Timer?
    private var sessionId: UUID?
    private var exerciseId: UUID?
    private var userId: UUID?
    private var startTime: Date?
    
    private let samplingInterval: TimeInterval = 30 // seconds
    
    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }
    
    /// Start tracking emotional trajectory for a session
    func startTracking(sessionId: UUID, exerciseId: UUID, userId: UUID) {
        self.sessionId = sessionId
        self.exerciseId = exerciseId
        self.userId = userId
        self.startTime = Date()
        self.currentTrajectory = []
        self.isTracking = true
        
        // Capture initial state immediately
        captureSample()
        
        // Start periodic sampling
        timer = Timer.scheduledTimer(withTimeInterval: samplingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureSample()
            }
        }
    }
    
    /// Stop tracking and return completed trajectory
    /// - Throws: Database error if trajectory save fails
    func stopTracking() async throws -> [TrajectoryPoint] {
        timer?.invalidate()
        timer = nil
        isTracking = false

        // Capture final state
        captureSample()

        // Save trajectory to database (throws on failure to prevent silent data loss)
        if let sessionId = sessionId,
           let exerciseId = exerciseId,
           let userId = userId,
           let startTime = startTime,
           !currentTrajectory.isEmpty {

            let trajectoryData: [String: Any] = [
                "session_id": sessionId.uuidString,
                "user_id": userId.uuidString,
                "exercise_id": exerciseId.uuidString,
                "start_time": ISO8601DateFormatter().string(from: startTime),
                "end_time": ISO8601DateFormatter().string(from: Date()),
                "samples": currentTrajectory.map { point in
                    [
                        "timestamp": ISO8601DateFormatter().string(from: point.timestamp),
                        "seconds_from_start": point.secondsFromStart,
                        "nervous_system_state": point.nervousSystemState ?? "unknown",
                        "emotion_classification": point.emotionClassification.map { emotion in
                            [
                                "primary": emotion.primary,
                                "valence": emotion.valence,
                                "arousal": emotion.arousal ?? 0
                            ]
                        } ?? [:],
                        "hrv_reading": point.hrvReading ?? 0,
                        "composite_score": point.compositeScore
                    ]
                }
            ]

            try await supabase
                .from("emotional_trajectories")
                .insert(trajectoryData)
                .execute()
        }

        let trajectory = currentTrajectory

        // Clear state
        self.sessionId = nil
        self.exerciseId = nil
        self.userId = nil
        self.startTime = nil
        self.currentTrajectory = []

        return trajectory
    }
    
    private func captureSample() {
        guard let startTime = startTime else { return }
        
        let secondsFromStart = Int(Date().timeIntervalSince(startTime))
        
        // Calculate composite score from available signals
        // Note: In production, this would query NervousSystemStateEngine and EmotionAnalyzer
        // For now, using mock data as placeholder
        let compositeScore = calculateCompositeScore()
        
        let point = TrajectoryPoint(
            id: UUID(),
            timestamp: Date(),
            secondsFromStart: secondsFromStart,
            nervousSystemState: getMockNervousSystemState(),
            emotionClassification: getMockEmotionClassification(),
            hrvReading: getMockHRV(),
            compositeScore: compositeScore
        )
        
        currentTrajectory.append(point)
    }
    
    private func calculateCompositeScore() -> Double {
        // CORRECTED FORMULA: 2 * (weighted_sum) - 1
        // This is a simplified version - in production, integrate with:
        // - NervousSystemStateEngine for state
        // - EmotionAnalyzer for emotion valence
        // - HealthKit for HRV (if available)

        // Mock implementation: Simulate realistic improvement trajectory
        // Start at negative state, gradually improve with some variability
        guard let startTime = startTime else { return 0.0 }
        let elapsed = Date().timeIntervalSince(startTime)
        let progress = min(1.0, elapsed / 300.0) // 5 minutes to full improvement

        // Base improvement curve: starts at -0.3, ends at +0.6
        let baseScore = -0.3 + (0.9 * progress)

        // Add realistic variability (±0.15)
        let noise = Double.random(in: -0.15...0.15)

        return max(-1.0, min(1.0, baseScore + noise))
    }

    // MARK: - Mock Data Providers (Replace with real integrations)

    private func getMockNervousSystemState() -> String? {
        // TODO: Integrate with NervousSystemStateEngine.getCurrentState()
        // Mock: Transition from fight_flight -> rest over time
        guard let startTime = startTime else { return "rest" }
        let elapsed = Date().timeIntervalSince(startTime)

        if elapsed < 60 { return "fight_flight" }
        else if elapsed < 180 { return "transition" }
        else { return "rest" }
    }

    private func getMockEmotionClassification() -> EmotionClassification? {
        // TODO: Integrate with EmotionAnalyzer.getCurrentEmotion()
        // Mock: Transition from anxious -> calm
        guard let startTime = startTime else {
            return EmotionClassification(primary: "neutral", valence: 0.0, arousal: 0.5)
        }
        let elapsed = Date().timeIntervalSince(startTime)
        let progress = min(1.0, elapsed / 300.0)

        if progress < 0.3 {
            return EmotionClassification(primary: "anxious", valence: -0.4, arousal: 0.8)
        } else if progress < 0.7 {
            return EmotionClassification(primary: "neutral", valence: 0.0, arousal: 0.5)
        } else {
            return EmotionClassification(primary: "calm", valence: 0.6, arousal: 0.3)
        }
    }

    private func getMockHRV() -> Double? {
        // TODO: Integrate with HealthKit HRV readings
        // Mock: HRV increases as user relaxes (40ms → 80ms)
        guard let startTime = startTime else { return 50.0 }
        let elapsed = Date().timeIntervalSince(startTime)
        let progress = min(1.0, elapsed / 300.0)

        return 40.0 + (40.0 * progress) + Double.random(in: -5.0...5.0)
    }
    
    deinit {
        timer?.invalidate()
    }
}
