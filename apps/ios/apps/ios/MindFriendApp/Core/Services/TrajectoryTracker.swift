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
    func stopTracking() async -> [TrajectoryPoint] {
        timer?.invalidate()
        timer = nil
        isTracking = false
        
        // Capture final state
        captureSample()
        
        // Save trajectory to database
        if let sessionId = sessionId,
           let exerciseId = exerciseId,
           let userId = userId,
           let startTime = startTime,
           !currentTrajectory.isEmpty {
            
            do {
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
                
            } catch {
                print("Failed to save trajectory: \(error)")
            }
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
        
        // Mock implementation returns baseline neutral state
        return 0.0
    }
    
    // MARK: - Mock Data Providers (Replace with real integrations)
    
    private func getMockNervousSystemState() -> String? {
        // TODO: Integrate with NervousSystemStateEngine.getCurrentState()
        return "rest"
    }
    
    private func getMockEmotionClassification() -> EmotionClassification? {
        // TODO: Integrate with EmotionAnalyzer.getCurrentEmotion()
        return EmotionClassification(primary: "neutral", valence: 0.0, arousal: 0.5)
    }
    
    private func getMockHRV() -> Double? {
        // TODO: Integrate with HealthKit HRV readings
        return nil
    }
    
    deinit {
        timer?.invalidate()
    }
}
