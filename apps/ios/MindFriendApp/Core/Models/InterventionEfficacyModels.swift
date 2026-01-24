//
//  InterventionEfficacyModels.swift
//  MindFriendApp
//
//  Intervention Efficacy Engine - Data Models
//  Defines all data structures for efficacy tracking, calculation, and recommendations
//

import Foundation

// MARK: - Emotional Trajectory

struct EmotionalTrajectory: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let userId: UUID
    let exerciseId: UUID
    let startTime: Date
    let endTime: Date?
    let samples: [TrajectoryPoint]
    
    var startingState: Double {
        samples.first?.compositeScore ?? 0
    }
    
    var endingState: Double {
        samples.last?.compositeScore ?? 0
    }
    
    var netChange: Double {
        endingState - startingState
    }
    
    var trajectory: TrajectoryShape {
        guard samples.count >= 3 else { return .flat }
        
        let midpoint = samples[samples.count / 2].compositeScore
        
        if netChange > 0.3 && midpoint > startingState {
            return .steadyImprovement
        } else if netChange > 0.3 && midpoint < startingState {
            return .lateBreakthrough
        } else if netChange > 0.3 && midpoint > endingState {
            return .earlyPeak
        } else if netChange < -0.1 {
            return .deterioration
        } else {
            return .flat
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case userId = "user_id"
        case exerciseId = "exercise_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case samples
    }
}

struct TrajectoryPoint: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let secondsFromStart: Int
    let nervousSystemState: String?
    let emotionClassification: EmotionClassification?
    let hrvReading: Double?
    let compositeScore: Double
    
    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case secondsFromStart = "seconds_from_start"
        case nervousSystemState = "nervous_system_state"
        case emotionClassification = "emotion_classification"
        case hrvReading = "hrv_reading"
        case compositeScore = "composite_score"
    }
}

struct EmotionClassification: Codable {
    let primary: String
    let valence: Double
    let arousal: Double?
}

enum TrajectoryShape: String, Codable {
    case steadyImprovement = "steadyImprovement"
    case lateBreakthrough = "lateBreakthrough"
    case earlyPeak = "earlyPeak"
    case deterioration = "deterioration"
    case flat = "flat"
    
    var displayName: String {
        switch self {
        case .steadyImprovement: return "Steady Improvement"
        case .lateBreakthrough: return "Late Breakthrough"
        case .earlyPeak: return "Early Peak"
        case .deterioration: return "Deterioration"
        case .flat: return "No Change"
        }
    }
}

// MARK: - Intervention Efficacy

struct InterventionEfficacy: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let exerciseId: UUID
    let sessionId: UUID
    let completedAt: Date
    
    // Core metrics
    let efficacyScore: Double
    let netEmotionalChange: Double
    let trajectoryShape: TrajectoryShape
    let breakthroughDetected: Bool
    let breakthroughSecond: Int?
    
    // Context
    let startingState: InterventionContext
    let timeOfDay: TimeOfDay
    let dayOfWeek: Int
    let priorSleepQuality: Double?
    let stressLevel: Double?
    
    let createdAt: Date
    
    struct InterventionContext: Codable {
        let nervousSystemState: String
        let primaryEmotion: String
        let stressLevel: Double
        
        enum CodingKeys: String, CodingKey {
            case nervousSystemState = "nervous_system_state"
            case primaryEmotion = "primary_emotion"
            case stressLevel = "stress_level"
        }
    }
    
    enum TimeOfDay: String, Codable {
        case morning = "morning"
        case afternoon = "afternoon"
        case evening = "evening"
        case night = "night"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case exerciseId = "exercise_id"
        case sessionId = "session_id"
        case completedAt = "completed_at"
        case efficacyScore = "efficacy_score"
        case netEmotionalChange = "net_emotional_change"
        case trajectoryShape = "trajectory_shape"
        case breakthroughDetected = "breakthrough_detected"
        case breakthroughSecond = "breakthrough_second"
        case startingState = "starting_state"
        case timeOfDay = "time_of_day"
        case dayOfWeek = "day_of_week"
        case priorSleepQuality = "prior_sleep_quality"
        case stressLevel = "stress_level"
        case createdAt = "created_at"
    }
}

// MARK: - User Efficacy Profile

struct UserEfficacyProfile: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let exerciseId: UUID
    
    let overallEfficacyScore: Double
    let completionCount: Int
    let confidence: Double
    
    let efficacyByState: [String: Double]
    let efficacyByTimeOfDay: [String: Double]
    let efficacyByEmotion: [String: Double]
    
    let bestContext: String?
    let trend: EfficacyTrend
    let updatedAt: Date
    
    enum EfficacyTrend: String, Codable {
        case improving = "improving"
        case stable = "stable"
        case declining = "declining"
        
        var displayName: String {
            switch self {
            case .improving: return "Improving"
            case .stable: return "Stable"
            case .declining: return "Declining"
            }
        }
        
        var icon: String {
            switch self {
            case .improving: return "arrow.up.circle.fill"
            case .stable: return "minus.circle.fill"
            case .declining: return "arrow.down.circle.fill"
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case exerciseId = "exercise_id"
        case overallEfficacyScore = "overall_efficacy_score"
        case completionCount = "completion_count"
        case confidence
        case efficacyByState = "efficacy_by_state"
        case efficacyByTimeOfDay = "efficacy_by_time_of_day"
        case efficacyByEmotion = "efficacy_by_emotion"
        case bestContext = "best_context"
        case trend
        case updatedAt = "updated_at"
    }
}

// MARK: - Exercise Recommendation

struct ExerciseRecommendation: Identifiable {
    let id: UUID
    let exerciseId: UUID
    let exerciseName: String
    let exerciseType: String
    let duration: Int
    let predictedEfficacy: Double
    let confidence: Double
    let completionCount: Int
    let reason: String
    let trend: UserEfficacyProfile.EfficacyTrend?
    
    init(exerciseId: UUID, exerciseName: String, exerciseType: String, duration: Int, predictedEfficacy: Double, confidence: Double, completionCount: Int, reason: String, trend: UserEfficacyProfile.EfficacyTrend?) {
        self.id = UUID()
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.exerciseType = exerciseType
        self.duration = duration
        self.predictedEfficacy = predictedEfficacy
        self.confidence = confidence
        self.completionCount = completionCount
        self.reason = reason
        self.trend = trend
    }
}

// MARK: - Dashboard Data

struct EfficacyDashboardData {
    let topExercises: [TopExercise]
    let recentSessions: [RecentSession]
    let insights: DashboardInsights
    
    struct TopExercise: Identifiable {
        let id: UUID
        let exerciseId: UUID
        let exerciseName: String
        let efficacyScore: Double
        let completionCount: Int
        let bestContext: String?
        let trend: UserEfficacyProfile.EfficacyTrend
        
        init(exerciseId: UUID, exerciseName: String, efficacyScore: Double, completionCount: Int, bestContext: String?, trend: UserEfficacyProfile.EfficacyTrend) {
            self.id = UUID()
            self.exerciseId = exerciseId
            self.exerciseName = exerciseName
            self.efficacyScore = efficacyScore
            self.completionCount = completionCount
            self.bestContext = bestContext
            self.trend = trend
        }
    }
    
    struct RecentSession: Identifiable {
        let id: UUID
        let sessionId: UUID
        let exerciseId: UUID
        let exerciseName: String
        let completedAt: Date
        let efficacyScore: Double
        let netChange: Double
        let breakthroughDetected: Bool
        
        init(sessionId: UUID, exerciseId: UUID, exerciseName: String, completedAt: Date, efficacyScore: Double, netChange: Double, breakthroughDetected: Bool) {
            self.id = UUID()
            self.sessionId = sessionId
            self.exerciseId = exerciseId
            self.exerciseName = exerciseName
            self.completedAt = completedAt
            self.efficacyScore = efficacyScore
            self.netChange = netChange
            self.breakthroughDetected = breakthroughDetected
        }
    }
}

struct DashboardInsights {
    let totalBreakthroughs: Int
    let averageEfficacy: Double
    let mostEffectiveContext: String
    let messages: [String]
}
