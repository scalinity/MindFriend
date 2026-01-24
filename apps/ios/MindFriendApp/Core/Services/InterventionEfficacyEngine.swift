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
    
    // Make tracker internal so views can observe trajectory
    let tracker: TrajectoryTracker
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
            let request = CalculateEfficacyRequest(
                sessionId: sessionId.uuidString,
                exerciseId: exerciseId.uuidString,
                trajectoryPoints: trajectory.map { point in
                    CalculateEfficacyRequest.TrajectoryPoint(
                        timestamp: ISO8601DateFormatter().string(from: point.timestamp),
                        secondsFromStart: point.secondsFromStart,
                        nervousSystemState: point.nervousSystemState ?? "",
                        emotionClassification: point.emotionClassification.map { emotion in
                            CalculateEfficacyRequest.TrajectoryPoint.EmotionClassification(
                                primary: emotion.primary,
                                valence: emotion.valence,
                                arousal: emotion.arousal ?? 0
                            )
                        },
                        hrvReading: point.hrvReading ?? 0,
                        compositeScore: point.compositeScore
                    )
                },
                sessionDuration: Int(sessionDuration)
            )
            
            struct EmptyResponseLocal: Decodable {}
            
            let _: EmptyResponseLocal = try await supabase.functions.invoke(
                "calculate-efficacy",
                options: FunctionInvokeOptions(body: request)
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
        let response: DashboardResponse = try await supabase.functions.invoke(
            "get-efficacy-dashboard",
            options: FunctionInvokeOptions()
        )
        
        // Parse top exercises
        let topExercises = response.topExercises.compactMap { dict -> EfficacyDashboardData.TopExercise? in
            guard let trend = UserEfficacyProfile.EfficacyTrend(rawValue: dict.trend) else {
                return nil
            }
            
            return EfficacyDashboardData.TopExercise(
                exerciseId: UUID(uuidString: dict.exerciseId) ?? UUID(),
                exerciseName: dict.exerciseName,
                efficacyScore: dict.efficacyScore,
                completionCount: dict.completionCount,
                bestContext: dict.bestContext,
                trend: trend
            )
        }
        
        // Parse recent sessions
        let recentSessions = response.recentSessions.compactMap { dict -> EfficacyDashboardData.RecentSession? in
            guard let completedAt = ISO8601DateFormatter().date(from: dict.completedAt) else {
                return nil
            }

            return EfficacyDashboardData.RecentSession(
                sessionId: UUID(uuidString: dict.sessionId) ?? UUID(),
                exerciseId: UUID(uuidString: dict.exerciseId) ?? UUID(),
                exerciseName: dict.exerciseName,
                completedAt: completedAt,
                efficacyScore: dict.efficacyScore,
                netChange: dict.netChange,
                breakthroughDetected: dict.breakthroughDetected
            )
        }
        
        // Parse insights
        let insights = DashboardInsights(
            totalBreakthroughs: response.insights.totalBreakthroughs,
            averageEfficacy: response.insights.averageEfficacy,
            mostEffectiveContext: response.insights.mostEffectiveContext,
            messages: response.insights.messages
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
        return session.user.id
    }
}

// MARK: - Edge Function Request/Response Types

private struct CalculateEfficacyRequest: Encodable {
    struct TrajectoryPoint: Encodable {
        struct EmotionClassification: Encodable {
            let primary: String
            let valence: Double
            let arousal: Double
        }
        
        let timestamp: String
        let secondsFromStart: Int
        let nervousSystemState: String
        let emotionClassification: EmotionClassification?
        let hrvReading: Double
        let compositeScore: Double
    }
    
    let sessionId: String
    let exerciseId: String
    let trajectoryPoints: [TrajectoryPoint]
    let sessionDuration: Int
}

private struct DashboardResponse: Decodable {
    struct TopExercise: Decodable {
        let exerciseId: String
        let exerciseName: String
        let efficacyScore: Double
        let completionCount: Int
        let bestContext: String?
        let trend: String
    }
    
    struct RecentSession: Decodable {
        let sessionId: String
        let exerciseId: String
        let exerciseName: String
        let completedAt: String
        let efficacyScore: Double
        let netChange: Double
        let breakthroughDetected: Bool
    }
    
    struct Insights: Decodable {
        let totalBreakthroughs: Int
        let averageEfficacy: Double
        let mostEffectiveContext: String
        let messages: [String]
    }
    
    let topExercises: [TopExercise]
    let recentSessions: [RecentSession]
    let insights: Insights
}

// MARK: - Errors

enum EfficacyError: Error {
    case sessionAlreadyActive
    case noActiveSession
    case invalidResponse
    case invalidUserId
}
