import Foundation
import SwiftUI

// MARK: - Risk Level

/// Risk classification for mental health predictions
enum RiskLevel: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case crisis

    var id: String { rawValue }

    /// Color for visual representation
    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .crisis: return .red
        }
    }

    /// Human-readable description
    var description: String {
        switch self {
        case .low: return "You're doing well"
        case .medium: return "Some signs to watch"
        case .high: return "We're here for you"
        case .crisis: return "Let's get you support"
        }
    }

    /// Icon for risk level
    var icon: String {
        switch self {
        case .low: return "checkmark.circle.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .high: return "exclamationmark.triangle.fill"
        case .crisis: return "heart.fill"
        }
    }

    /// Numeric threshold for this level (lower bound)
    var threshold: Int {
        switch self {
        case .low: return 0
        case .medium: return 26
        case .high: return 51
        case .crisis: return 76
        }
    }
}

// MARK: - Trend Direction

/// Direction of mood trend prediction
enum TrendDirection: String, Codable {
    case improving
    case stable
    case declining

    var description: String {
        switch self {
        case .improving: return "Things are looking up"
        case .stable: return "Staying steady"
        case .declining: return "May need extra support"
        }
    }

    var icon: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .stable: return "arrow.right"
        case .declining: return "arrow.down.right"
        }
    }

    var color: Color {
        switch self {
        case .improving: return .green
        case .stable: return .blue
        case .declining: return .orange
        }
    }
}

// MARK: - Risk Factors

/// Contributing factors to risk assessment
struct RiskFactors: Codable, Equatable {
    let moodTrend: Double?
    let moodVolatility: Double?
    let appEngagement: Double?
    let sleepQuality: Double?
    let hrvDrop: Double?
    let streakBroken: Bool?
    let daysSinceChat: Int?
    let socialEngagement: Double?

    enum CodingKeys: String, CodingKey {
        case moodTrend = "mood_trend"
        case moodVolatility = "mood_volatility"
        case appEngagement = "app_engagement"
        case sleepQuality = "sleep_quality"
        case hrvDrop = "hrv_drop"
        case streakBroken = "streak_broken"
        case daysSinceChat = "days_since_chat"
        case socialEngagement = "social_engagement"
    }

    /// Get top contributing factors as human-readable strings
    var topFactors: [String] {
        var factors: [(String, Double)] = []

        if let trend = moodTrend, trend < -0.2 {
            factors.append(("Mood has been declining", abs(trend) * 10))
        }
        if let volatility = moodVolatility, volatility > 2 {
            factors.append(("Mood has been variable", volatility * 3))
        }
        if let engagement = appEngagement, engagement < -2 {
            factors.append(("Less active in the app lately", abs(engagement)))
        }
        if let sleep = sleepQuality, sleep < -2 {
            factors.append(("Sleep quality has dropped", abs(sleep)))
        }
        if let hrv = hrvDrop, hrv < -1 {
            factors.append(("HRV has decreased", abs(hrv)))
        }
        if streakBroken == true {
            factors.append(("Quest streak was broken", 5))
        }
        if let days = daysSinceChat, days > 3 {
            factors.append(("Haven't chatted in a while", Double(days)))
        }
        if let social = socialEngagement, social < -2 {
            factors.append(("Social activity has dropped", abs(social)))
        }

        return factors
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map { $0.0 }
    }

    static let empty = RiskFactors(
        moodTrend: nil,
        moodVolatility: nil,
        appEngagement: nil,
        sleepQuality: nil,
        hrvDrop: nil,
        streakBroken: nil,
        daysSinceChat: nil,
        socialEngagement: nil
    )
}

// MARK: - Risk Assessment

/// A risk assessment result from the prediction system
struct RiskAssessment: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let assessedAt: Date
    let riskScore: Int
    let riskLevel: RiskLevel
    let factors: RiskFactors
    let topFactors: [String]
    let predictedMood24h: Double?
    let predictedTrend7d: TrendDirection?
    let modelVersion: String
    let confidence: Double?
    let dailySignalId: UUID?
    let interventionTriggered: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case assessedAt = "assessed_at"
        case riskScore = "risk_score"
        case riskLevel = "risk_level"
        case factors
        case topFactors = "top_factors"
        case predictedMood24h = "predicted_mood_24h"
        case predictedTrend7d = "predicted_trend_7d"
        case modelVersion = "model_version"
        case confidence
        case dailySignalId = "daily_signal_id"
        case interventionTriggered = "intervention_triggered"
    }

    /// Display-friendly confidence percentage
    var confidencePercent: Int? {
        confidence.map { Int($0 * 100) }
    }

    /// Relative time since assessment
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: assessedAt, relativeTo: Date())
    }
}

// MARK: - Intervention Types

/// Type of intervention to deliver
enum InterventionType: String, Codable {
    case gentleNudge = "gentle_nudge"
    case activeCheckin = "active_checkin"
    case crisisProtocol = "crisis_protocol"
    case familyAlert = "family_alert"

    var title: String {
        switch self {
        case .gentleNudge: return "Check-in"
        case .activeCheckin: return "How are you?"
        case .crisisProtocol: return "We're here for you"
        case .familyAlert: return "Family notified"
        }
    }

    var icon: String {
        switch self {
        case .gentleNudge: return "hand.wave.fill"
        case .activeCheckin: return "heart.fill"
        case .crisisProtocol: return "phone.fill"
        case .familyAlert: return "person.2.fill"
        }
    }
}

/// Channel for delivering intervention
enum InterventionChannel: String, Codable {
    case push
    case inApp = "in_app"
    case sms
    case email
}

/// User's response to an intervention
enum InterventionResponse: String, Codable {
    case accepted
    case dismissed
    case ignored
    case pending
}

// MARK: - Intervention

/// A proactive intervention offered to the user
struct Intervention: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let riskAssessmentId: UUID?
    let interventionType: InterventionType
    let channel: InterventionChannel
    let messageTemplate: String
    let personalization: [String: AnyCodableValue]?
    let suggestedActions: [String]
    let suggestedExerciseId: UUID?
    let scheduledAt: Date
    var deliveredAt: Date?
    var expiresAt: Date?
    var response: InterventionResponse
    var respondedAt: Date?
    var actionTaken: String?
    var moodBefore: Int?
    var mood24hAfter: Int?
    var helpfulRating: Int?
    var userFeedback: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case riskAssessmentId = "risk_assessment_id"
        case interventionType = "intervention_type"
        case channel
        case messageTemplate = "message_template"
        case personalization
        case suggestedActions = "suggested_actions"
        case suggestedExerciseId = "suggested_exercise_id"
        case scheduledAt = "scheduled_at"
        case deliveredAt = "delivered_at"
        case expiresAt = "expires_at"
        case response
        case respondedAt = "responded_at"
        case actionTaken = "action_taken"
        case moodBefore = "mood_before"
        case mood24hAfter = "mood_24h_after"
        case helpfulRating = "helpful_rating"
        case userFeedback = "user_feedback"
    }

    /// Whether the intervention is still pending
    var isPending: Bool {
        response == .pending
    }

    /// Whether the intervention has expired
    var isExpired: Bool {
        if let expiresAt {
            return Date() > expiresAt
        }
        return false
    }

    /// Suggested action labels for UI
    var actionLabels: [String] {
        suggestedActions.map { action in
            switch action {
            case "breathing_exercise": return "Breathing Exercise"
            case "chat": return "Talk to Me"
            case "crisis_line": return "Crisis Support"
            case "grounding_exercise": return "Grounding Exercise"
            case "sleep_meditation": return "Sleep Meditation"
            case "circle_checkin": return "Check in with Circle"
            default: return action.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
    }
}

// MARK: - Prediction Settings

/// User's settings for predictive intervention feature
struct PredictionSettings: Codable, Equatable {
    var predictionsEnabled: Bool
    var useMoodData: Bool
    var useChatSentiment: Bool
    var useBiometrics: Bool
    var useAppUsage: Bool
    var useSleepData: Bool
    var allowGentleNudges: Bool
    var allowActiveCheckins: Bool
    /// Stored as TIME string from PostgreSQL (e.g., "14:30:00")
    var preferredInterventionTimeString: String?
    var allowFamilyAlerts: Bool
    var familyAlertThreshold: RiskLevel

    enum CodingKeys: String, CodingKey {
        case predictionsEnabled = "predictions_enabled"
        case useMoodData = "use_mood_data"
        case useChatSentiment = "use_chat_sentiment"
        case useBiometrics = "use_biometrics"
        case useAppUsage = "use_app_usage"
        case useSleepData = "use_sleep_data"
        case allowGentleNudges = "allow_gentle_nudges"
        case allowActiveCheckins = "allow_active_checkins"
        case preferredInterventionTimeString = "preferred_intervention_time"
        case allowFamilyAlerts = "allow_family_alerts"
        case familyAlertThreshold = "family_alert_threshold"
    }

    /// Default settings (predictions disabled by default for privacy)
    static var defaults: PredictionSettings {
        PredictionSettings(
            predictionsEnabled: false, // Opt-in required
            useMoodData: true,
            useChatSentiment: true,
            useBiometrics: true,
            useAppUsage: true,
            useSleepData: true,
            allowGentleNudges: true,
            allowActiveCheckins: true,
            preferredInterventionTimeString: nil,
            allowFamilyAlerts: false,
            familyAlertThreshold: .high
        )
    }

    // MARK: - Time Conversion Helpers

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// Preferred intervention time as Date for UI binding
    var preferredInterventionTime: Date? {
        get {
            guard let timeString = preferredInterventionTimeString else { return nil }
            return Self.timeFormatter.date(from: timeString)
        }
        set {
            preferredInterventionTimeString = newValue.map { Self.timeFormatter.string(from: $0) }
        }
    }

    /// Data sources that are enabled
    var enabledDataSources: [String] {
        var sources: [String] = []
        if useMoodData { sources.append("Mood check-ins") }
        if useChatSentiment { sources.append("Chat conversations") }
        if useBiometrics { sources.append("Health data (HRV, heart rate)") }
        if useAppUsage { sources.append("App activity") }
        if useSleepData { sources.append("Sleep patterns") }
        return sources
    }
}

// MARK: - Daily Signals

/// Aggregated daily signals used for risk scoring
struct DailySignals: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let signalDate: Date
    let biometricSummaryId: UUID?

    // Mood signals
    let moodAverage: Double?
    let moodMin: Int?
    let moodMax: Int?
    let moodVariance: Double?
    let moodTrend: Double?
    let moodEntryCount: Int

    // Engagement signals
    let appSessions: Int
    let totalActiveMinutes: Int
    let featuresUsed: [String]
    let questsCompleted: Int
    let exercisesCompleted: Int
    let chatMessagesSent: Int

    // Social signals
    let circlePosts: Int
    let circleReactionsReceived: Int
    let circleCommentsMade: Int

    // Computed scores
    let engagementScore: Int?
    let socialScore: Int?
    let biometricScore: Int?

    // Streak
    let currentStreak: Int
    let streakBrokenToday: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case signalDate = "signal_date"
        case biometricSummaryId = "biometric_summary_id"
        case moodAverage = "mood_average"
        case moodMin = "mood_min"
        case moodMax = "mood_max"
        case moodVariance = "mood_variance"
        case moodTrend = "mood_trend"
        case moodEntryCount = "mood_entry_count"
        case appSessions = "app_sessions"
        case totalActiveMinutes = "total_active_minutes"
        case featuresUsed = "features_used"
        case questsCompleted = "quests_completed"
        case exercisesCompleted = "exercises_completed"
        case chatMessagesSent = "chat_messages_sent"
        case circlePosts = "circle_posts"
        case circleReactionsReceived = "circle_reactions_received"
        case circleCommentsMade = "circle_comments_made"
        case engagementScore = "engagement_score"
        case socialScore = "social_score"
        case biometricScore = "biometric_score"
        case currentStreak = "current_streak"
        case streakBrokenToday = "streak_broken_today"
    }
}

// Note: AnyCodableValue is defined in PersonalizationModels.swift

// MARK: - Mood Prediction Models

/// A mood prediction for a specific day
struct MoodPrediction: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let predictedFor: Date
    let predictedMood: Decimal
    let confidence: Decimal
    let factors: [MoodPredictionFactor]
    let modelVersion: String
    let featuresUsed: [String: AnyCodableValue]?
    var actualMood: Decimal?
    var predictionAccuracy: Decimal?
    let notificationSent: Bool
    let notificationSentAt: Date?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case predictedFor = "predicted_for"
        case predictedMood = "predicted_mood"
        case confidence
        case factors
        case modelVersion = "model_version"
        case featuresUsed = "features_used"
        case actualMood = "actual_mood"
        case predictionAccuracy = "prediction_accuracy"
        case notificationSent = "notification_sent"
        case notificationSentAt = "notification_sent_at"
        case createdAt = "created_at"
    }
    
    /// Convert predicted mood (1-10) to display-friendly value
    var predictedMoodValue: Double {
        Double(truncating: predictedMood as NSNumber)
    }
    
    /// Whether this is a low mood prediction
    var isLowMoodPredicted: Bool {
        predictedMoodValue < 4.0
    }
    
    /// Outlook label based on predicted mood
    var outlookLabel: String {
        switch predictedMoodValue {
        case 0..<4: return "Challenging"
        case 4..<6: return "Moderate"
        case 6..<8: return "Good"
        default: return "Great"
        }
    }
    
    /// Confidence level label
    var confidenceLabel: String {
        let conf = Double(truncating: confidence as NSNumber)
        switch conf {
        case 0..<0.5: return "Low"
        case 0.5..<0.75: return "Medium"
        default: return "High"
        }
    }
    
    /// Confidence as percentage
    var confidencePercent: Int {
        Int(Double(truncating: confidence as NSNumber) * 100)
    }
    
    /// Color for the mood prediction indicator
    var moodColor: Color {
        switch predictedMoodValue {
        case 0..<4: return .orange
        case 4..<6: return .yellow
        case 6..<8: return .green
        default: return .mint
        }
    }
    
    /// SF Symbol for the mood
    var moodIcon: String {
        switch predictedMoodValue {
        case 0..<3: return "cloud.rain.fill"
        case 3..<5: return "cloud.fill"
        case 5..<7: return "cloud.sun.fill"
        case 7..<9: return "sun.max.fill"
        default: return "sparkles"
        }
    }
}

/// A factor contributing to the mood prediction
struct MoodPredictionFactor: Codable, Equatable, Identifiable {
    var id: String { factor }
    
    let factor: String
    let impact: Double
    let description: String
    
    /// Display-friendly impact label
    var impactLabel: String {
        if impact > 0 {
            return "+\(String(format: "%.1f", impact))"
        } else {
            return String(format: "%.1f", impact)
        }
    }
    
    /// Whether this factor has positive impact
    var isPositive: Bool {
        impact > 0
    }
    
    /// Color for the impact indicator
    var impactColor: Color {
        isPositive ? .green : .orange
    }
    
    /// SF Symbol for the factor type
    var icon: String {
        switch factor {
        case let f where f.contains("sleep"):
            return "moon.zzz.fill"
        case let f where f.contains("steps"):
            return "figure.walk"
        case let f where f.contains("exercise"):
            return "figure.run"
        case let f where f.contains("streak"):
            return "flame.fill"
        case let f where f.contains("trend"):
            return "chart.line.uptrend.xyaxis"
        case let f where f.contains("day_of_week"):
            return "calendar"
        default:
            return "chart.bar.fill"
        }
    }
}

/// Type of preemptive intervention
enum PreemptiveInterventionType: String, Codable {
    case restSuggestion = "rest_suggestion"
    case movementSuggestion = "movement_suggestion"
    case patternBreak = "pattern_break"
    case generalSupport = "general_support"
    
    var title: String {
        switch self {
        case .restSuggestion: return "Rest & Recharge"
        case .movementSuggestion: return "Get Moving"
        case .patternBreak: return "Try Something New"
        case .generalSupport: return "We're Here for You"
        }
    }
    
    var icon: String {
        switch self {
        case .restSuggestion: return "moon.stars.fill"
        case .movementSuggestion: return "figure.walk"
        case .patternBreak: return "sparkles"
        case .generalSupport: return "heart.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .restSuggestion: return .purple
        case .movementSuggestion: return .green
        case .patternBreak: return .orange
        case .generalSupport: return .blue
        }
    }
}

/// Status of a preemptive intervention
enum PreemptiveInterventionStatus: String, Codable {
    case pending
    case delivered
    case accepted
    case dismissed
    case expired
}

/// A preemptive intervention offered before a predicted low mood day
struct PreemptiveIntervention: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let predictionId: UUID
    let interventionType: PreemptiveInterventionType
    let content: String
    let suggestedExerciseId: UUID?
    var status: PreemptiveInterventionStatus
    var deliveredAt: Date?
    var userResponse: String?
    var responseRecordedAt: Date?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case predictionId = "prediction_id"
        case interventionType = "intervention_type"
        case content
        case suggestedExerciseId = "suggested_exercise_id"
        case status
        case deliveredAt = "delivered_at"
        case userResponse = "user_response"
        case responseRecordedAt = "response_recorded_at"
        case createdAt = "created_at"
    }
    
    /// Whether this intervention is still pending
    var isPending: Bool {
        status == .pending || status == .delivered
    }
    
    /// Whether this intervention has been acted upon
    var isActedUpon: Bool {
        status == .accepted || status == .dismissed
    }
}
