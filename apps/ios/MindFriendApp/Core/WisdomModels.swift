import Foundation

// MARK: - Wisdom Consent

/// User consent preferences for community wisdom participation
struct WisdomConsent: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var contributeAnonymousData: Bool
    var receiveRecommendations: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case contributeAnonymousData = "contribute_anonymous_data"
        case receiveRecommendations = "receive_recommendations"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Wisdom Insight Type (renamed to avoid conflict with PersonalizationModels.InsightType)

enum WisdomInsightType: String, Codable {
    case notAlone = "not_alone"
    case trend
    case strategyHighlight = "strategy_highlight"
    case milestone
    case exerciseEffectiveness = "exercise_effectiveness"
}

// MARK: - Wisdom Insight

/// Aggregated insight from community wisdom
struct WisdomInsight: Codable, Identifiable {
    let id: UUID
    let insightType: WisdomInsightType
    let contextTags: [String]
    let insightContent: String
    let confidenceScore: Double
    let sampleSize: Int
    let aggregateData: [String: AnyCodableValue]?
    let createdAt: Date
    let validFrom: Date
    let validUntil: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case insightType = "insight_type"
        case contextTags = "context_tags"
        case insightContent = "insight_content"
        case confidenceScore = "confidence_score"
        case sampleSize = "sample_size"
        case aggregateData = "aggregate_data"
        case createdAt = "created_at"
        case validFrom = "valid_from"
        case validUntil = "valid_until"
    }

    /// Formatted sample size for display (e.g., "2,340+")
    var formattedSampleSize: String {
        if sampleSize >= 1000 {
            let thousands = sampleSize / 1000
            let hundreds = (sampleSize % 1000) / 100
            if hundreds > 0 {
                return "\(thousands),\(hundreds)00+"
            }
            return "\(thousands),000+"
        }
        return "\(sampleSize)+"
    }

    /// Human-readable confidence level
    var confidenceLevel: String {
        switch confidenceScore {
        case 0.9...1.0: return "Very High"
        case 0.75..<0.9: return "High"
        case 0.5..<0.75: return "Moderate"
        default: return "Low"
        }
    }
}

// MARK: - Wisdom Recommendation

/// Personalized recommendation shown to user
struct WisdomRecommendation: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let insightId: UUID
    let content: String
    let relevanceScore: Double
    let contextTags: [String]
    let shownAt: Date
    var helpful: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case insightId = "insight_id"
        case content
        case relevanceScore = "relevance_score"
        case contextTags = "context_tags"
        case shownAt = "shown_at"
        case helpful
    }
}

// MARK: - Community Strategy

/// User-submitted coping strategy
struct CommunityStrategy: Codable, Identifiable {
    let id: UUID
    let category: StrategyCategory
    let subcategory: String?
    let strategyText: String
    let context: String?
    let contributorDemographic: String?
    let transitionContext: String?
    var helpfulCount: Int
    var notHelpfulCount: Int
    let viewCount: Int
    let status: ModerationStatus
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case subcategory
        case strategyText = "strategy_text"
        case context
        case contributorDemographic = "contributor_demographic"
        case transitionContext = "transition_context"
        case helpfulCount = "helpful_count"
        case notHelpfulCount = "not_helpful_count"
        case viewCount = "view_count"
        case status
        case createdAt = "created_at"
    }

    /// Calculated helpful percentage (0-100)
    var helpfulPercentage: Int {
        let total = helpfulCount + notHelpfulCount
        guard total > 0 else { return 0 }
        return Int((Double(helpfulCount) / Double(total)) * 100)
    }

    /// User's vote on this strategy (set locally, not from API)
    var myVote: VoteType?
}

enum StrategyCategory: String, Codable, CaseIterable {
    case anxiety
    case depression
    case stress
    case grief
    case anger
    case loneliness
    case overwhelm
    case sleep
    case motivation
    case general

    var displayName: String {
        rawValue.capitalized
    }

    var iconName: String {
        switch self {
        case .anxiety: return "waveform.path.ecg"
        case .depression: return "cloud.rain"
        case .stress: return "bolt.fill"
        case .grief: return "heart.slash"
        case .anger: return "flame"
        case .loneliness: return "person.crop.circle.badge.minus"
        case .overwhelm: return "tornado"
        case .sleep: return "moon.zzz"
        case .motivation: return "battery.25"
        case .general: return "sparkles"
        }
    }
}

enum ModerationStatus: String, Codable {
    case pending
    case approved
    case rejected
    case flagged
}

enum VoteType: String, Codable {
    case helpful
    case notHelpful = "not_helpful"
}

// MARK: - Strategy Vote

/// User's vote on a strategy
struct StrategyVote: Codable, Identifiable {
    let id: UUID
    let strategyId: UUID
    let userId: UUID
    var voteType: VoteType
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case strategyId = "strategy_id"
        case userId = "user_id"
        case voteType = "vote_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Aggregate Stats

/// Community-wide aggregated statistics
struct CommunityAggregateStat: Codable, Identifiable {
    let id: UUID
    let statDate: Date
    let statType: StatType
    let category: String?
    let statData: [String: AnyCodableValue]
    let sampleSize: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case statDate = "stat_date"
        case statType = "stat_type"
        case category
        case statData = "stat_data"
        case sampleSize = "sample_size"
        case createdAt = "created_at"
    }

    enum StatType: String, Codable {
        case dailyMood = "daily_mood"
        case moodByDayOfWeek = "mood_by_day_of_week"
        case moodByTime = "mood_by_time"
        case commonEmotions = "common_emotions"
        case exerciseEffectiveness = "exercise_effectiveness"
        case pathwayStats = "pathway_stats"
    }
}

// MARK: - Contribution Types

/// Types of data that can be contributed to community wisdom
enum ContributionType: String, Codable {
    case moodPattern = "mood_pattern"
    case exerciseEffectiveness = "exercise_effectiveness"
    case pathwayProgress = "pathway_progress"
    case strategySuccess = "strategy_success"
}

/// Data for mood pattern contribution
struct MoodPatternData: Codable {
    let moodScore: Int
    let timeOfDay: String?
    let emotion: String?

    enum CodingKeys: String, CodingKey {
        case moodScore
        case timeOfDay
        case emotion
    }
}

/// Data for exercise effectiveness contribution
struct ExerciseEffectivenessData: Codable {
    let exerciseType: String
    let effectivenessRating: Int

    enum CodingKeys: String, CodingKey {
        case exerciseType
        case effectivenessRating
    }
}

/// Data for pathway progress contribution
struct PathwayProgressData: Codable {
    let pathwayType: String
    let phaseNumber: Int

    enum CodingKeys: String, CodingKey {
        case pathwayType
        case phaseNumber
    }
}

// MARK: - API Response Models

/// Response from get-wisdom-recommendations endpoint
struct WisdomRecommendationsResponse: Codable {
    let notAloneInsight: InsightResponse?
    let insights: [InsightResponse]
    let strategies: [StrategyResponse]
    let trendInsight: InsightResponse?
}

struct InsightResponse: Codable, Identifiable {
    let id: UUID
    let insightType: String
    let content: String
    let contextTags: [String]
    let confidenceScore: Double
    let sampleSize: Int
    let relevanceScore: Double?
}

struct StrategyResponse: Codable, Identifiable {
    let id: UUID
    let category: String
    let strategyText: String
    let context: String?
    let helpfulPercentage: Int
    let helpfulCount: Int
}

/// Response from contribute-wisdom endpoint
struct ContributeWisdomResponse: Codable {
    let success: Bool
    let contributionId: UUID?
    let userHash: String?
    let error: String?
    let message: String?
}

/// Response from submit-strategy endpoint
struct SubmitStrategyResponse: Codable {
    let success: Bool
    let strategyId: UUID?
    let status: String?
    let message: String?
    let error: String?
}

/// Response from vote-strategy endpoint
struct VoteStrategyResponse: Codable {
    let success: Bool
    let strategyId: UUID?
    let voteType: String?
    let strategy: StrategyVoteStats?
    let error: String?
}

struct StrategyVoteStats: Codable {
    let helpfulCount: Int
    let notHelpfulCount: Int
    let helpfulPercentage: Int
}

// MARK: - Display Models

/// "Not alone" insight for display
struct NotAloneInsight {
    let count: Int
    let timeframe: String
    let context: String
    let message: String

    var formattedCount: String {
        if count >= 1000 {
            return "\(count / 1000)k+"
        }
        return "\(count)+"
    }
}

// NOTE: AnyCodableValue is defined in Core/Models.swift to avoid duplication
