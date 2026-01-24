//
//  InterventionEfficacyEngine.swift
//  MindFriendApp
//
//  Intervention Efficacy Engine - Main Coordinator Service
//  Orchestrates trajectory tracking, efficacy calculation, and recommendations
//

import Foundation
import Supabase

@MainActor
final class InterventionEfficacyEngine: ObservableObject {
    @Published private(set) var isTrackingSession = false
    
    private let tracker: TrajectoryTracker
    private let calculator: EfficacyCalculator
    private let recommender: EfficacyBasedRecommender
    private let supabase: SupabaseClient
    
    private var currentSessionId: UUID?
    private var currentExerciseId: UUID?
    private var sessionStartTime: Date?
    
    init(
        tracker: TrajectoryTracker,
        calculator: EfficacyCalculator,
        recommender: EfficacyBasedRecommender,
        supabase: SupabaseClient
    ) {
        self.tracker = tracker
        self.calculator = calculator
        self.recommender = recommender
        self.supabase = supabase
    }
    
    // MARK: - Session Lifecycle
    
    /// Start tracking efficacy for an exercise session
    func startSession(sessionId: UUID, exerciseId: UUID, userId: UUID) async throws {
        guard !isTrackingSession else {
            throw EfficacyError.sessionAlreadyActive
        }
        
        currentSessionId = sessionId
        currentExerciseId = exerciseId
        sessionStartTime = Date()
        isTrackingSession = true
        
        tracker.startTracking(sessionId: sessionId, exerciseId: exerciseId, userId: userId)
    }
    
    /// End session and calculate efficacy
    /// Returns efficacy result if calculation successful, nil if insufficient data
    func endSession() async throws -> InterventionEfficacy? {
        guard isTrackingSession,
              let sessionId = currentSessionId,
              let exerciseId = currentExerciseId,
              let startTime = sessionStartTime else {
            throw EfficacyError.noActiveSession
        }
        
        // Stop tracking and get trajectory
        let trajectory = try await tracker.stopTracking()
        
        guard trajectory.count >= 3 else {
            // Insufficient data for efficacy calculation
            isTrackingSession = false
            currentSessionId = nil
            currentExerciseId = nil
            sessionStartTime = nil
            return nil
        }
        
        // Calculate efficacy locally
        let sessionDuration = Date().timeIntervalSince(startTime)
        guard var efficacy = calculator.calculateEfficacy(
            trajectory: trajectory,
            sessionDuration: sessionDuration
        ) else {
            isTrackingSession = false
            currentSessionId = nil
            currentExerciseId = nil
            sessionStartTime = nil
            return nil
        }
        
        // Update with correct IDs
        efficacy = InterventionEfficacy(
            id: efficacy.id,
            userId: try await getCurrentUserId(),
            exerciseId: exerciseId,
            sessionId: sessionId,
            completedAt: efficacy.completedAt,
            efficacyScore: efficacy.efficacyScore,
            netEmotionalChange: efficacy.netEmotionalChange,
            trajectoryShape: efficacy.trajectoryShape,
            breakthroughDetected: efficacy.breakthroughDetected,
            breakthroughSecond: efficacy.breakthroughSecond,
            startingState: efficacy.startingState,
            timeOfDay: efficacy.timeOfDay,
            dayOfWeek: efficacy.dayOfWeek,
            priorSleepQuality: efficacy.priorSleepQuality,
            stressLevel: efficacy.stressLevel,
            createdAt: efficacy.createdAt
        )
        
        // Send to Edge Function for server-side validation and storage
        do {
            let requestBody: [String: Any] = [
                "sessionId": sessionId.uuidString,
                "exerciseId": exerciseId.uuidString,
                "trajectoryPoints": trajectory.map { point in
                    [
                        "timestamp": ISO8601DateFormatter().string(from: point.timestamp),
                        "secondsFromStart": point.secondsFromStart,
                        "nervousSystemState": point.nervousSystemState ?? "",
                        "emotionClassification": point.emotionClassification.map { emotion in
                            [
                                "primary": emotion.primary,
                                "valence": emotion.valence,
                                "arousal": emotion.arousal ?? 0
                            ]
                        } ?? [:],
                        "hrvReading": point.hrvReading ?? 0,
                        "compositeScore": point.compositeScore
                    ]
                },
                "sessionDuration": sessionDuration
            ]
            
            let _ = try await supabase.functions.invoke(
                "calculate-efficacy",
                options: FunctionInvokeOptions(body: requestBody)
            )
        } catch {
            print("Failed to sync efficacy to server: \(error)")
            // Continue anyway - we have local calculation
        }
        
        // Clear session state
        isTrackingSession = false
        currentSessionId = nil
        currentExerciseId = nil
        sessionStartTime = nil
        
        return efficacy
    }
    
    // MARK: - Data Fetching
    
    /// Fetch dashboard data (top exercises, recent sessions, insights)
    func getDashboardData() async throws -> EfficacyDashboardData {
        let response = try await supabase.functions.invoke(
            "get-efficacy-dashboard",
            options: FunctionInvokeOptions()
        )
        
        guard let data = response.data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EfficacyError.invalidResponse
        }
        
        // Parse top exercises
        let topExercises = (json["topExercises"] as? [[String: Any]])?.compactMap { dict -> EfficacyDashboardData.TopExercise? in
            guard let exerciseId = dict["exerciseId"] as? String,
                  let exerciseName = dict["exerciseName"] as? String,
                  let efficacyScore = dict["efficacyScore"] as? Double,
                  let completionCount = dict["completionCount"] as? Int,
                  let trendString = dict["trend"] as? String,
                  let trend = UserEfficacyProfile.EfficacyTrend(rawValue: trendString) else {
                return nil
            }
            
            return EfficacyDashboardData.TopExercise(
                exerciseId: UUID(uuidString: exerciseId) ?? UUID(),
                exerciseName: exerciseName,
                efficacyScore: efficacyScore,
                completionCount: completionCount,
                bestContext: dict["bestContext"] as? String,
                trend: trend
            )
        } ?? []
        
        // Parse recent sessions
        let recentSessions = (json["recentSessions"] as? [[String: Any]])?.compactMap { dict -> EfficacyDashboardData.RecentSession? in
            guard let sessionId = dict["sessionId"] as? String,
                  let exerciseId = dict["exerciseId"] as? String,
                  let exerciseName = dict["exerciseName"] as? String,
                  let completedAtString = dict["completedAt"] as? String,
                  let efficacyScore = dict["efficacyScore"] as? Double,
                  let netChange = dict["netChange"] as? Double,
                  let breakthroughDetected = dict["breakthroughDetected"] as? Bool else {
                return nil
            }
            
            let completedAt = ISO8601DateFormatter().date(from: completedAtString) ?? Date()
            
            return EfficacyDashboardData.RecentSession(
                sessionId: UUID(uuidString: sessionId) ?? UUID(),
                exerciseId: UUID(uuidString: exerciseId) ?? UUID(),
                exerciseName: exerciseName,
                completedAt: completedAt,
                efficacyScore: efficacyScore,
                netChange: netChange,
                breakthroughDetected: breakthroughDetected
            )
        } ?? []
        
        // Parse insights
        let insightsDict = json["insights"] as? [String: Any]
        let insights = DashboardInsights(
            totalBreakthroughs: insightsDict?["totalBreakthroughs"] as? Int ?? 0,
            averageEfficacy: insightsDict?["averageEfficacy"] as? Double ?? 0,
            mostEffectiveContext: insightsDict?["mostEffectiveContext"] as? String ?? "",
            messages: insightsDict?["messages"] as? [String] ?? []
        )
        
        return EfficacyDashboardData(
            topExercises: topExercises,
            recentSessions: recentSessions,
            insights: insights
        )
    }
    
    /// Get personalized exercise recommendations
    func getRecommendations(
        currentState: String,
        currentEmotion: String,
        timeOfDay: String? = nil
    ) async throws -> [ExerciseRecommendation] {
        let hour = Calendar.current.component(.hour, from: Date())
        let time = timeOfDay ?? {
            if hour >= 5 && hour < 12 { return "morning" }
            else if hour >= 12 && hour < 17 { return "afternoon" }
            else if hour >= 17 && hour < 21 { return "evening" }
            else { return "night" }
        }()
        
        return try await recommender.getRecommendations(
            currentState: currentState,
            currentEmotion: currentEmotion,
            timeOfDay: time
        )
    }
    
    // MARK: - Helpers
    
    private func getCurrentUserId() async throws -> UUID {
        let session = try await supabase.auth.session
        guard let userIdString = session.user.id.uuidString,
              let userId = UUID(uuidString: userIdString) else {
            throw EfficacyError.invalidUserId
        }
        return userId
    }
}

// MARK: - Errors

enum EfficacyError: Error {
    case sessionAlreadyActive
    case noActiveSession
    case invalidResponse
    case invalidUserId
}
