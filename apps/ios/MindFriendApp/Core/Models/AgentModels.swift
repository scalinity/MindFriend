import Foundation
import SwiftUI

// MARK: - Agent Settings

struct AgentSettings: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var autonomyLevel: AutonomyLevel
    var enabledSignals: [String]
    var quietHoursStart: String
    var quietHoursEnd: String
    var maxDailyOutreach: Int
    var preferredChannels: [String]
    var explainReasoning: Bool
    var isEnabled: Bool
    var timezone: String
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case autonomyLevel = "autonomy_level"
        case enabledSignals = "enabled_signals"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case maxDailyOutreach = "max_daily_outreach"
        case preferredChannels = "preferred_channels"
        case explainReasoning = "explain_reasoning"
        case isEnabled = "is_enabled"
        case timezone
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static var defaultSettings: AgentSettings {
        AgentSettings(
            id: UUID(),
            userId: UUID(),
            autonomyLevel: .balanced,
            enabledSignals: SignalType.allCases.map { $0.rawValue },
            quietHoursStart: "22:00",
            quietHoursEnd: "08:00",
            maxDailyOutreach: 3,
            preferredChannels: ["push", "in_app"],
            explainReasoning: true,
            isEnabled: false,
            timezone: TimeZone.current.identifier,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - Autonomy Level

enum AutonomyLevel: String, Codable, CaseIterable, Identifiable {
    case minimal
    case balanced
    case proactive
    case guardian

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .balanced: return "Balanced"
        case .proactive: return "Proactive"
        case .guardian: return "Guardian"
        }
    }

    var description: String {
        switch self {
        case .minimal: return "Only reach out for critical concerns"
        case .balanced: return "Balanced check-ins when helpful"
        case .proactive: return "Frequent supportive outreach"
        case .guardian: return "Maximum care and attention"
        }
    }

    var maxDailyActions: Int {
        switch self {
        case .minimal: return 1
        case .balanced: return 3
        case .proactive: return 6
        case .guardian: return 10
        }
    }

    var confidenceThreshold: Double {
        switch self {
        case .minimal: return 0.85
        case .balanced: return 0.70
        case .proactive: return 0.50
        case .guardian: return 0.30
        }
    }

    var iconName: String {
        switch self {
        case .minimal: return "bell.slash"
        case .balanced: return "bell"
        case .proactive: return "bell.badge"
        case .guardian: return "bell.badge.fill"
        }
    }
}

// MARK: - Signal Types

enum SignalType: String, Codable, CaseIterable, Identifiable {
    case moodDecline = "mood_decline"
    case moodImprovement = "mood_improvement"
    case activityDrop = "activity_drop"
    case streakRisk = "streak_risk"
    case inactivity = "inactivity"
    case stressSpike = "stress_spike"
    case positiveMomentum = "positive_momentum"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .moodDecline: return "Mood Decline"
        case .moodImprovement: return "Mood Improvement"
        case .activityDrop: return "Activity Drop"
        case .streakRisk: return "Streak at Risk"
        case .inactivity: return "Extended Inactivity"
        case .stressSpike: return "Stress Increase"
        case .positiveMomentum: return "Positive Momentum"
        }
    }

    var iconName: String {
        switch self {
        case .moodDecline: return "arrow.down.circle"
        case .moodImprovement: return "arrow.up.circle"
        case .activityDrop: return "figure.walk.motion"
        case .streakRisk: return "flame"
        case .inactivity: return "moon.zzz"
        case .stressSpike: return "waveform.path.ecg"
        case .positiveMomentum: return "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .moodDecline: return .orange
        case .moodImprovement: return .green
        case .activityDrop: return .yellow
        case .streakRisk: return .red
        case .inactivity: return .gray
        case .stressSpike: return .purple
        case .positiveMomentum: return .blue
        }
    }

    var suggestedActions: [ActionType] {
        switch self {
        case .moodDecline: return [.checkIn, .suggestExercise]
        case .moodImprovement: return [.encouragement]
        case .activityDrop: return [.checkIn, .suggestExercise]
        case .streakRisk: return [.streakReminder]
        case .inactivity: return [.checkIn, .moodPrompt]
        case .stressSpike: return [.suggestExercise, .checkIn]
        case .positiveMomentum: return [.encouragement]
        }
    }
}

// MARK: - Severity

enum Severity: String, Codable, CaseIterable {
    case low
    case medium
    case high
    case critical

    var displayName: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }

    var priority: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        case .critical: return 4
        }
    }
}

// MARK: - Agent Signal

struct AgentSignal: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let signalType: SignalType
    let severity: Severity
    let confidence: Double
    let evidence: SignalEvidence
    let detectedAt: Date
    let expiresAt: Date?
    var isResolved: Bool
    var resolvedAt: Date?
    var resolutionType: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case signalType = "signal_type"
        case severity
        case confidence
        case evidence
        case detectedAt = "detected_at"
        case expiresAt = "expires_at"
        case isResolved = "is_resolved"
        case resolvedAt = "resolved_at"
        case resolutionType = "resolution_type"
        case createdAt = "created_at"
    }
}

struct SignalEvidence: Codable {
    let dataPoints: [EvidencePoint]?
    let trend: TrendInfo?
    let comparison: ComparisonInfo?

    enum CodingKeys: String, CodingKey {
        case dataPoints = "dataPoints"
        case trend
        case comparison
    }
}

struct EvidencePoint: Codable {
    let metric: String
    let value: Double
    let timestamp: String
    let context: String?
}

struct TrendInfo: Codable {
    let direction: String
    let magnitude: Double
    let durationDays: Int

    enum CodingKeys: String, CodingKey {
        case direction
        case magnitude
        case durationDays = "durationDays"
    }
}

struct ComparisonInfo: Codable {
    let baseline: Double
    let current: Double
    let percentChange: Double

    enum CodingKeys: String, CodingKey {
        case baseline
        case current
        case percentChange = "percentChange"
    }
}

// MARK: - Action Types

enum ActionType: String, Codable, CaseIterable, Identifiable {
    case checkIn = "check_in"
    case suggestExercise = "suggest_exercise"
    case morningBriefing = "morning_briefing"
    case encouragement = "encouragement"
    case streakReminder = "streak_reminder"
    case moodPrompt = "mood_prompt"
    case contentRecommendation = "content_recommendation"
    case concernAlert = "concern_alert"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .checkIn: return "Check-In"
        case .suggestExercise: return "Exercise Suggestion"
        case .morningBriefing: return "Morning Briefing"
        case .encouragement: return "Encouragement"
        case .streakReminder: return "Streak Reminder"
        case .moodPrompt: return "Mood Prompt"
        case .contentRecommendation: return "Content Recommendation"
        case .concernAlert: return "Concern Alert"
        }
    }

    var iconName: String {
        switch self {
        case .checkIn: return "message"
        case .suggestExercise: return "figure.mind.and.body"
        case .morningBriefing: return "sun.horizon"
        case .encouragement: return "hands.clap"
        case .streakReminder: return "flame"
        case .moodPrompt: return "face.smiling"
        case .contentRecommendation: return "book"
        case .concernAlert: return "heart.text.square"
        }
    }
}

// MARK: - Action Status

enum ActionStatus: String, Codable, CaseIterable {
    case planned
    case scheduled
    case delivered
    case opened
    case responded
    case dismissed
    case cancelled

    var displayName: String {
        rawValue.capitalized
    }

    var isTerminal: Bool {
        switch self {
        case .responded, .dismissed, .cancelled:
            return true
        default:
            return false
        }
    }
}

// MARK: - Agent Action

struct AgentAction: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let signalId: UUID?
    let actionType: ActionType
    var status: ActionStatus
    var scheduledFor: Date?
    var deliveredAt: Date?
    let content: ActionContent
    let channel: String
    let reasoning: String?
    var userResponse: UserResponse?
    var effectivenessScore: Double?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case signalId = "signal_id"
        case actionType = "action_type"
        case status
        case scheduledFor = "scheduled_for"
        case deliveredAt = "delivered_at"
        case content
        case channel
        case reasoning
        case userResponse = "user_response"
        case effectivenessScore = "effectiveness_score"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ActionContent: Codable {
    let title: String
    let body: String
    let quickActions: [QuickAction]?
    let deepLink: String?
    let metadata: [String: AnyCodableValue]?

    enum CodingKeys: String, CodingKey {
        case title
        case body
        case quickActions = "quickActions"
        case deepLink = "deepLink"
        case metadata
    }
}

struct QuickAction: Codable, Identifiable {
    let label: String
    let action: String
    let value: String?

    var id: String { action + (value ?? "") }
}

struct UserResponse: Codable {
    let responseType: String
    let selectedAction: String?
    let timestamp: Date
    let sentiment: String?

    enum CodingKeys: String, CodingKey {
        case responseType = "response_type"
        case selectedAction = "selected_action"
        case timestamp
        case sentiment
    }
}

// MARK: - Agent Learning

struct AgentLearning: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let learningType: LearningType
    var learnedValue: [String: AnyCodableValue]
    var confidence: Double
    var sampleCount: Int
    var lastUpdated: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case learningType = "learning_type"
        case learnedValue = "learned_value"
        case confidence
        case sampleCount = "sample_count"
        case lastUpdated = "last_updated"
        case createdAt = "created_at"
    }
}

enum LearningType: String, Codable, CaseIterable {
    case optimalTime = "optimal_time"
    case responsePreference = "response_preference"
    case contentPreference = "content_preference"
    case signalSensitivity = "signal_sensitivity"
    case channelPreference = "channel_preference"
    case frequencyTolerance = "frequency_tolerance"

    var displayName: String {
        switch self {
        case .optimalTime: return "Optimal Timing"
        case .responsePreference: return "Response Preferences"
        case .contentPreference: return "Content Preferences"
        case .signalSensitivity: return "Signal Sensitivity"
        case .channelPreference: return "Channel Preferences"
        case .frequencyTolerance: return "Frequency Tolerance"
        }
    }
}

// MARK: - Agent Decision

struct AgentDecision: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let decisionType: String
    let inputs: [String: AnyCodableValue]
    let reasoning: String
    let outcome: String
    let actionTaken: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case decisionType = "decision_type"
        case inputs
        case reasoning
        case outcome
        case actionTaken = "action_taken"
        case createdAt = "created_at"
    }
}

// MARK: - Helper Types
// Note: AnyCodableValue is defined in Models.swift - use that instead

// MARK: - API Request/Response Types

struct AgentLearnRequest: Codable {
    let actionId: String
    let userResponse: UserResponse

    enum CodingKeys: String, CodingKey {
        case actionId = "action_id"
        case userResponse = "user_response"
    }
}

struct AgentLearnResponse: Codable {
    let learningsUpdated: Int
    let effectivenessScore: Double

    enum CodingKeys: String, CodingKey {
        case learningsUpdated = "learnings_updated"
        case effectivenessScore = "effectiveness_score"
    }
}

// MARK: - Dashboard View Models

struct AgentDashboardData {
    let settings: AgentSettings
    let activeSignals: [AgentSignal]
    let recentActions: [AgentAction]
    let actionsToday: Int

    var isAgentActive: Bool {
        settings.isEnabled
    }

    var remainingActionsToday: Int {
        max(0, settings.maxDailyOutreach - actionsToday)
    }
}
