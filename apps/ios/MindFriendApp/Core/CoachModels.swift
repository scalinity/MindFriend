import Foundation

// MARK: - Cognitive Distortion

struct CognitiveDistortionData: Codable, Identifiable {
    let id: UUID
    let code: String
    let name: String
    let shortDescription: String
    let fullDescription: String
    let examples: [String]
    let questionsToChallenge: [String]
    let reframeTemplates: [String]
    let displayOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case name
        case shortDescription = "short_description"
        case fullDescription = "full_description"
        case examples
        case questionsToChallenge = "questions_to_challenge"
        case reframeTemplates = "reframe_templates"
        case displayOrder = "display_order"
    }
}

// Alias for backward compatibility with protocol definitions
typealias CognitiveDistortionDefinition = CognitiveDistortionData

// MARK: - Distortion Encounter

struct DistortionEncounter: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let distortionCode: String
    let conversationId: UUID?
    let originalMessagePreview: String
    let reframeOffered: Bool
    let reframeAccepted: Bool
    let reframeText: String?
    let userAction: String?
    let encounterType: String
    let confidence: Double
    let occurredAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case distortionCode = "distortion_code"
        case conversationId = "conversation_id"
        case originalMessagePreview = "original_message_preview"
        case reframeOffered = "reframe_offered"
        case reframeAccepted = "reframe_accepted"
        case reframeText = "reframe_text"
        case userAction = "user_action"
        case encounterType = "encounter_type"
        case confidence
        case occurredAt = "occurred_at"
    }
}

// MARK: - Coach Settings

struct CoachSettings: Codable {
    var isEnabled: Bool
    var sensitivityLevel: SensitivityLevel
    var silentHoursStart: Date?
    var silentHoursEnd: Date?
    var disabledDistortions: [String]
    var showPatterns: Bool
    var timezone: String  // IANA timezone identifier (e.g., "America/Los_Angeles")

    enum SensitivityLevel: String, Codable, CaseIterable {
        case minimal
        case balanced
        case frequent

        var displayName: String {
            switch self {
            case .minimal: return "Minimal"
            case .balanced: return "Balanced"
            case .frequent: return "Frequent"
            }
        }

        var description: String {
            switch self {
            case .minimal: return "Rare suggestions"
            case .balanced: return "Default"
            case .frequent: return "More frequent"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case sensitivityLevel = "sensitivity_level"
        case silentHoursStart = "silent_hours_start"
        case silentHoursEnd = "silent_hours_end"
        case disabledDistortions = "disabled_distortions"
        case showPatterns = "show_patterns"
        case timezone
    }

    static var defaultSettings: CoachSettings {
        CoachSettings(
            isEnabled: true,
            sensitivityLevel: .balanced,
            silentHoursStart: nil,
            silentHoursEnd: nil,
            disabledDistortions: [],
            showPatterns: true,
            timezone: TimeZone.current.identifier  // Auto-detect user's timezone
        )
    }
}

// MARK: - Coach Interaction

struct CoachInteraction: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let encounterId: UUID?
    let distortionCode: String
    let action: Action
    let confidence: Double?
    let occurredAt: Date

    enum Action: String, Codable {
        case shown
        case dismissed
        case helpful
        case learnMore = "learn_more"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case encounterId = "encounter_id"
        case distortionCode = "distortion_code"
        case action
        case confidence
        case occurredAt = "occurred_at"
    }
}

// MARK: - Weekly Pattern Summary

struct WeeklyPatternSummary: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let weekStart: Date
    let weekEnd: Date
    let totalEncounters: Int
    let distortionCounts: [String: Int]
    let newPatterns: [String]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case weekStart = "week_start"
        case weekEnd = "week_end"
        case totalEncounters = "total_encounters"
        case distortionCounts = "distortion_counts"
        case newPatterns = "new_patterns"
        case createdAt = "created_at"
    }
}

// MARK: - Pattern Analytics (from my-patterns Edge Function)

struct PatternAnalytics: Codable {
    let totalEncounters: Int
    let last7Days: Int
    let last30Days: Int
    let mostCommon: [DistortionStat]
    let byDistortionType: [DistortionStat]

    struct DistortionStat: Codable, Identifiable {
        var id: String { code }
        let code: String
        let name: String
        let count: Int
        let percentage: Double
        let trend: Trend?
        let helpfulRate: Double?

        enum Trend: String, Codable {
            case increasing
            case decreasing
            case stable
        }

        enum CodingKeys: String, CodingKey {
            case code
            case name
            case count
            case percentage
            case trend
            case helpfulRate = "helpful_rate"
        }
    }

    enum CodingKeys: String, CodingKey {
        case totalEncounters = "total_encounters"
        case last7Days = "last_7_days"
        case last30Days = "last_30_days"
        case mostCommon = "most_common"
        case byDistortionType = "by_distortion_type"
    }
}

// MARK: - Coach Data (from chat response)

struct CoachData: Codable {
    let encounterId: UUID?
    let distortionCode: String
    let distortionName: String
    let shortDescription: String
    let reframeText: String
    let educationalContent: String
    let socraticQuestions: [String]
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case encounterId
        case distortionCode
        case distortionName
        case shortDescription
        case reframeText
        case educationalContent
        case socraticQuestions
        case confidence
    }
}
