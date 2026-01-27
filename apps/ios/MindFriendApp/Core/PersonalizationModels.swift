// MARK: - Smart Personalization Models
// Models for user preferences, learned preferences, insights, and recommendations

import Foundation
import SwiftUI

// MARK: - Enums

enum SessionLength: String, Codable, CaseIterable {
    case micro
    case short
    case medium
    case long

    var displayName: String {
        switch self {
        case .micro: return "Micro (1-3 min)"
        case .short: return "Short (5-10 min)"
        case .medium: return "Medium (10-20 min)"
        case .long: return "Long (20+ min)"
        }
    }
}

enum PersonalizationContentType: String, Codable, CaseIterable {
    case audio
    case visual
    case text
    case interactive

    var displayName: String {
        switch self {
        case .audio: return "Audio"
        case .visual: return "Visual"
        case .text: return "Reading"
        case .interactive: return "Interactive"
        }
    }

    var icon: String {
        switch self {
        case .audio: return "speaker.wave.2"
        case .visual: return "eye"
        case .text: return "doc.text"
        case .interactive: return "hand.tap"
        }
    }
}

enum VoiceGender: String, Codable, CaseIterable {
    case male
    case female
    case neutral
    case noPreference = "no_preference"

    var displayName: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .neutral: return "Neutral"
        case .noPreference: return "No Preference"
        }
    }
}

enum BackgroundSound: String, Codable, CaseIterable {
    case nature
    case music
    case silence
    case ambient

    var displayName: String {
        switch self {
        case .nature: return "Nature Sounds"
        case .music: return "Soft Music"
        case .silence: return "Silence"
        case .ambient: return "Ambient Noise"
        }
    }
}

enum DifficultyPreference: String, Codable, CaseIterable {
    case easy
    case medium
    case hard
    case adaptive

    var displayName: String {
        switch self {
        case .easy: return "Easier"
        case .medium: return "Moderate"
        case .hard: return "Challenging"
        case .adaptive: return "Adaptive"
        }
    }
}

enum ReminderFrequency: String, Codable, CaseIterable {
    case none
    case daily
    case smart

    var displayName: String {
        switch self {
        case .none: return "None"
        case .daily: return "Daily"
        case .smart: return "Smart (Learn from me)"
        }
    }
}

enum InsightType: String, Codable {
    case pattern
    case milestone
    case suggestion
    case trend
}

enum InsightCategory: String, Codable {
    case mood
    case activity
    case progress
    case habit
}

enum InsightActionType: String, Codable {
    case tryContent = "try_content"
    case adjustSchedule = "adjust_schedule"
    case setGoal = "set_goal"
    case celebrate
    case adjustPreference = "adjust_preference"
}

enum SuggestionStatus: String, Codable {
    case suggested
    case accepted
    case rejected
    case expired
}

enum ConfidenceLevel {
    case low, medium, high

    var color: String {
        switch self {
        case .low: return "gray"
        case .medium: return "yellow"
        case .high: return "green"
        }
    }
}

// MARK: - Database Row Types

struct DBUserPreferenceProfile: Codable {
    let id: String
    let userId: String
    let preferredSessionLength: String?
    let preferredContentTypes: [String]?
    let preferredCategories: [String]?
    let preferredVoiceGender: String?
    let backgroundSoundPreference: String?
    let difficultyPreference: String?
    let preferredTimes: PreferredTimes?
    let quietHoursStart: String?
    let quietHoursEnd: String?
    let reminderFrequency: String?
    let moodBasedRecommendations: Bool?
    let personalizedInsights: Bool?
    let smartScheduling: Bool?
    let adaptiveDifficulty: Bool?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case preferredSessionLength = "preferred_session_length"
        case preferredContentTypes = "preferred_content_types"
        case preferredCategories = "preferred_categories"
        case preferredVoiceGender = "preferred_voice_gender"
        case backgroundSoundPreference = "background_sound_preference"
        case difficultyPreference = "difficulty_preference"
        case preferredTimes = "preferred_times"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case reminderFrequency = "reminder_frequency"
        case moodBasedRecommendations = "mood_based_recommendations"
        case personalizedInsights = "personalized_insights"
        case smartScheduling = "smart_scheduling"
        case adaptiveDifficulty = "adaptive_difficulty"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DBLearnedPreference: Codable, Identifiable {
    let id: String
    let userId: String
    let preferenceType: String
    let preferenceKey: String
    let engagementCount: Int
    let completionCount: Int
    let totalDurationSeconds: Int
    let positiveRatings: Int
    let negativeRatings: Int
    let engagementRate: Double
    let preferenceScore: Double
    let confidenceScore: Double
    let firstInteractionAt: String
    let lastInteractionAt: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case preferenceType = "preference_type"
        case preferenceKey = "preference_key"
        case engagementCount = "engagement_count"
        case completionCount = "completion_count"
        case totalDurationSeconds = "total_duration_seconds"
        case positiveRatings = "positive_ratings"
        case negativeRatings = "negative_ratings"
        case engagementRate = "engagement_rate"
        case preferenceScore = "preference_score"
        case confidenceScore = "confidence_score"
        case firstInteractionAt = "first_interaction_at"
        case lastInteractionAt = "last_interaction_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayName: String {
        preferenceKey
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var confidenceLevel: ConfidenceLevel {
        if confidenceScore < 0.3 { return .low }
        if confidenceScore < 0.7 { return .medium }
        return .high
    }
}

struct DBUsagePattern: Codable, Identifiable {
    let id: String
    let userId: String
    let patternType: String
    let patternData: PatternDataWrapper
    let sampleSize: Int
    let confidence: Double
    let calculatedAt: String
    let validUntil: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case patternType = "pattern_type"
        case patternData = "pattern_data"
        case sampleSize = "sample_size"
        case confidence
        case calculatedAt = "calculated_at"
        case validUntil = "valid_until"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DBPersonalizedInsight: Codable, Identifiable {
    let id: String
    let userId: String
    let insightType: String
    let insightCategory: String
    let title: String
    let description: String
    let dataPoints: [String: AnyCodableValue]
    let confidence: Double
    let actionType: String?
    let actionData: [String: AnyCodableValue]?
    var wasShown: Bool
    var wasDismissed: Bool
    var wasActedUpon: Bool
    let validFrom: String
    let validUntil: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case insightType = "insight_type"
        case insightCategory = "insight_category"
        case title
        case description
        case dataPoints = "data_points"
        case confidence
        case actionType = "action_type"
        case actionData = "action_data"
        case wasShown = "was_shown"
        case wasDismissed = "was_dismissed"
        case wasActedUpon = "was_acted_upon"
        case validFrom = "valid_from"
        case validUntil = "valid_until"
        case createdAt = "created_at"
    }

    var insightTypeEnum: InsightType {
        InsightType(rawValue: insightType) ?? .suggestion
    }

    var insightCategoryEnum: InsightCategory {
        InsightCategory(rawValue: insightCategory) ?? .activity
    }

    var actionTypeEnum: InsightActionType? {
        guard let actionType else { return nil }
        return InsightActionType(rawValue: actionType)
    }

    var icon: String {
        switch insightTypeEnum {
        case .pattern: return "chart.line.uptrend.xyaxis"
        case .milestone: return "star.fill"
        case .suggestion: return "lightbulb.fill"
        case .trend: return "arrow.up.right"
        }
    }

    var color: Color {
        switch insightCategoryEnum {
        case .mood: return .blue
        case .activity: return .green
        case .progress: return .purple
        case .habit: return .orange
        }
    }
}

struct DBScheduleSuggestion: Codable, Identifiable {
    let id: String
    let userId: String
    let suggestedTime: String
    let suggestedDays: [Int]
    let activityType: String
    let confidenceScore: Double
    let basedOnSessions: Int
    let reasoning: String
    let supportingData: [String: AnyCodableValue]?
    var status: String
    let userResponseAt: String?
    let createdAt: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case suggestedTime = "suggested_time"
        case suggestedDays = "suggested_days"
        case activityType = "activity_type"
        case confidenceScore = "confidence_score"
        case basedOnSessions = "based_on_sessions"
        case reasoning
        case supportingData = "supporting_data"
        case status
        case userResponseAt = "user_response_at"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    var formattedDays: String {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return suggestedDays.compactMap { $0 < dayNames.count ? dayNames[$0] : nil }.joined(separator: ", ")
    }

    var statusEnum: SuggestionStatus {
        SuggestionStatus(rawValue: status) ?? .suggested
    }
}

// MARK: - Supporting Types

struct PreferredTimes: Codable {
    var weekday: [String]
    var weekend: [String]

    init(weekday: [String] = [], weekend: [String] = []) {
        self.weekday = weekday
        self.weekend = weekend
    }
}

struct PatternDataWrapper: Codable {
    let slots: [TimeSlot]?
    let days: [DaySlot]?
    let preferred: String?
    let distribution: [String: Double]?

    struct TimeSlot: Codable {
        let hour: Int
        let score: Double
        let sessions: Int
    }

    struct DaySlot: Codable {
        let day: Int
        let score: Double
        let sessions: Int?

        var dayName: String {
            let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            guard day >= 0 && day < dayNames.count else { return "Unknown" }
            return dayNames[day]
        }
    }
}

// MARK: - API Response Types

struct ContentRecommendation: Codable, Identifiable {
    let id: String
    let contentId: String
    let contentType: String
    let score: Double
    let reasons: [String]

    init(id: String = UUID().uuidString, contentId: String, contentType: String = "exercise", score: Double, reasons: [String]) {
        self.id = id
        self.contentId = contentId
        self.contentType = contentType
        self.score = score
        self.reasons = reasons
    }

    enum CodingKeys: String, CodingKey {
        case contentId, score, reasons
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.contentId = try container.decode(String.self, forKey: .contentId)
        self.score = try container.decode(Double.self, forKey: .score)
        self.reasons = try container.decode([String].self, forKey: .reasons)
        self.id = contentId
        self.contentType = "exercise"
    }
}

struct RecommendationContext: Codable {
    var currentMood: String?
    var timeOfDay: String?
    var recentActivity: String?

    // MARK: - New: Anxiety and Energy Levels
    var anxietyLevel: AnxietyLevel?
    var energyLevel: EnergyLevel?

    // MARK: - New: Biometric Context
    var restingHeartRate: Int?
    var hrvScore: Double?
    var sleepQualityScore: Double?
    var sleepDurationHours: Double?
    var recentActivityMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case currentMood
        case timeOfDay
        case recentActivity
        case anxietyLevel
        case energyLevel
        case restingHeartRate
        case hrvScore
        case sleepQualityScore
        case sleepDurationHours
        case recentActivityMinutes
    }

    static var current: RecommendationContext {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay: String

        switch hour {
        case 5..<12: timeOfDay = "morning"
        case 12..<17: timeOfDay = "afternoon"
        case 17..<21: timeOfDay = "evening"
        default: timeOfDay = "night"
        }

        return RecommendationContext(timeOfDay: timeOfDay)
    }
}

// MARK: - Anxiety Level Enum

enum AnxietyLevel: String, Codable, CaseIterable {
    case calm
    case mild
    case moderate
    case elevated
    case high

    var displayName: String {
        switch self {
        case .calm: return "Calm"
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .elevated: return "Elevated"
        case .high: return "High"
        }
    }

    var icon: String {
        switch self {
        case .calm: return "leaf.fill"
        case .mild: return "dot.circle.fill"
        case .moderate: return "exclamationmark.circle.fill"
        case .elevated: return "exclamationmark.triangle.fill"
        case .high: return "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .calm: return .green
        case .mild: return .blue
        case .moderate: return .yellow
        case .elevated: return .orange
        case .high: return .red
        }
    }
}

// MARK: - Energy Level Enum

enum EnergyLevel: String, Codable, CaseIterable {
    case veryLow
    case low
    case moderate
    case high
    case veryHigh

    var displayName: String {
        switch self {
        case .veryLow: return "Very Low"
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .veryHigh: return "Very High"
        }
    }

    var icon: String {
        switch self {
        case .veryLow: return "battery.0.bar"
        case .low: return "battery.25"
        case .moderate: return "battery.50"
        case .high: return "battery.75"
        case .veryHigh: return "battery.100"
        }
    }

    var color: Color {
        switch self {
        case .veryLow: return .red
        case .low: return .orange
        case .moderate: return .yellow
        case .high: return .green
        case .veryHigh: return .green
        }
    }
}

struct RecommendationResponse: Codable {
    let recommendations: [ContentRecommendation]
}

struct UpdatePreferencesResponse: Codable {
    let success: Bool
}

struct GenerateInsightsResponse: Codable {
    let insights: [InsightResponse]

    struct InsightResponse: Codable {
        let insightType: String
        let insightCategory: String
        let title: String
        let description: String
        let dataPoints: [String: AnyCodableValue]
        let confidence: Double
        let actionType: String?
        let actionData: [String: AnyCodableValue]?

        enum CodingKeys: String, CodingKey {
            case insightType = "insight_type"
            case insightCategory = "insight_category"
            case title
            case description
            case dataPoints = "data_points"
            case confidence
            case actionType = "action_type"
            case actionData = "action_data"
        }
    }
}

// MARK: - Domain Models

/// Domain model for view-friendly insight representation
struct PersonalizedInsight: Identifiable {
    let id: String
    let title: String
    let description: String
    let insightType: InsightType
    let insightCategory: InsightCategory
    let confidence: Double
    let actionType: InsightActionType?
    let actionData: InsightAction?
    var wasShown: Bool
    var wasDismissed: Bool
    var wasActedUpon: Bool
    let validUntil: Date

    var icon: String {
        switch insightType {
        case .pattern: return "chart.line.uptrend.xyaxis"
        case .milestone: return "star.fill"
        case .suggestion: return "lightbulb.fill"
        case .trend: return "arrow.up.right"
        }
    }

    var color: Color {
        switch insightCategory {
        case .mood: return .blue
        case .activity: return .green
        case .progress: return .purple
        case .habit: return .orange
        }
    }

    var hasAction: Bool {
        actionType != nil
    }

    init(from db: DBPersonalizedInsight) {
        self.id = db.id
        self.title = db.title
        self.description = db.description
        self.insightType = db.insightTypeEnum
        self.insightCategory = db.insightCategoryEnum
        self.confidence = db.confidence
        self.actionType = db.actionTypeEnum
        self.actionData = InsightAction(
            contentId: db.actionData?["contentId"]?.stringValue,
            suggestedTime: db.actionData?["suggested_time"]?.stringValue,
            goal: db.actionData?["goal"]?.stringValue
        )
        self.wasShown = db.wasShown
        self.wasDismissed = db.wasDismissed
        self.wasActedUpon = db.wasActedUpon
        self.validUntil = ISO8601DateFormatter().date(from: db.validUntil) ?? Date()
    }

    init(id: String, title: String, description: String, insightType: InsightType, insightCategory: InsightCategory, confidence: Double, actionType: InsightActionType?, actionData: InsightAction?, wasShown: Bool, wasDismissed: Bool, wasActedUpon: Bool, validUntil: Date) {
        self.id = id
        self.title = title
        self.description = description
        self.insightType = insightType
        self.insightCategory = insightCategory
        self.confidence = confidence
        self.actionType = actionType
        self.actionData = actionData
        self.wasShown = wasShown
        self.wasDismissed = wasDismissed
        self.wasActedUpon = wasActedUpon
        self.validUntil = validUntil
    }
}

struct InsightAction: Codable {
    let contentId: String?
    let suggestedTime: String?
    let goal: String?
}

struct UserPreferenceProfile: Identifiable {
    let id: String
    let userId: String
    var preferredSessionLength: SessionLength
    var preferredContentTypes: [PersonalizationContentType]
    var preferredCategories: [String]
    var preferredVoiceGender: VoiceGender?
    var backgroundSoundPreference: BackgroundSound
    var difficultyPreference: DifficultyPreference
    var preferredTimes: PreferredTimes
    var quietHoursStart: String
    var quietHoursEnd: String
    var reminderFrequency: ReminderFrequency
    var moodBasedRecommendations: Bool
    var personalizedInsights: Bool
    var smartScheduling: Bool
    var adaptiveDifficulty: Bool
    let createdAt: Date
    var updatedAt: Date

    init(from db: DBUserPreferenceProfile) {
        self.id = db.id
        self.userId = db.userId
        self.preferredSessionLength = SessionLength(rawValue: db.preferredSessionLength ?? "medium") ?? .medium
        self.preferredContentTypes = (db.preferredContentTypes ?? ["audio", "visual", "text"])
            .compactMap { PersonalizationContentType(rawValue: $0) }
        self.preferredCategories = db.preferredCategories ?? []
        self.preferredVoiceGender = db.preferredVoiceGender.flatMap { VoiceGender(rawValue: $0) }
        self.backgroundSoundPreference = BackgroundSound(rawValue: db.backgroundSoundPreference ?? "nature") ?? .nature
        self.difficultyPreference = DifficultyPreference(rawValue: db.difficultyPreference ?? "adaptive") ?? .adaptive
        self.preferredTimes = db.preferredTimes ?? PreferredTimes()
        self.quietHoursStart = db.quietHoursStart ?? "22:00"
        self.quietHoursEnd = db.quietHoursEnd ?? "07:00"
        self.reminderFrequency = ReminderFrequency(rawValue: db.reminderFrequency ?? "daily") ?? .daily
        self.moodBasedRecommendations = db.moodBasedRecommendations ?? true
        self.personalizedInsights = db.personalizedInsights ?? true
        self.smartScheduling = db.smartScheduling ?? true
        self.adaptiveDifficulty = db.adaptiveDifficulty ?? true
        self.createdAt = ISO8601DateFormatter().date(from: db.createdAt) ?? Date()
        self.updatedAt = ISO8601DateFormatter().date(from: db.updatedAt) ?? Date()
    }

    func toUpdatePayload() -> [String: Any] {
        return [
            "preferred_session_length": preferredSessionLength.rawValue,
            "preferred_content_types": preferredContentTypes.map { $0.rawValue },
            "preferred_categories": preferredCategories,
            "preferred_voice_gender": preferredVoiceGender?.rawValue as Any,
            "background_sound_preference": backgroundSoundPreference.rawValue,
            "difficulty_preference": difficultyPreference.rawValue,
            "preferred_times": [
                "weekday": preferredTimes.weekday,
                "weekend": preferredTimes.weekend
            ],
            "quiet_hours_start": quietHoursStart,
            "quiet_hours_end": quietHoursEnd,
            "reminder_frequency": reminderFrequency.rawValue,
            "mood_based_recommendations": moodBasedRecommendations,
            "personalized_insights": personalizedInsights,
            "smart_scheduling": smartScheduling,
            "adaptive_difficulty": adaptiveDifficulty
        ]
    }

    static func createDefault(userId: String) -> [String: Any] {
        return [
            "user_id": userId,
            "preferred_session_length": "medium",
            "preferred_content_types": ["audio", "visual", "text"],
            "preferred_categories": [] as [String],
            "background_sound_preference": "nature",
            "difficulty_preference": "adaptive",
            "preferred_times": ["weekday": [] as [String], "weekend": [] as [String]],
            "quiet_hours_start": "22:00",
            "quiet_hours_end": "07:00",
            "reminder_frequency": "smart",
            "mood_based_recommendations": true,
            "personalized_insights": true,
            "smart_scheduling": true,
            "adaptive_difficulty": true
        ]
    }
}
