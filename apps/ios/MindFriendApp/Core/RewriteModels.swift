import Foundation

// MARK: - Rewrite Models

enum RewriteType: String, CaseIterable, Codable {
    case lessCatastrophic = "less_catastrophic"
    case moreBalanced = "more_balanced"
    case moreActionable = "more_actionable"
    case moreCompassionate = "more_compassionate"

    var isPremium: Bool {
        switch self {
        case .lessCatastrophic, .moreBalanced: return false
        case .moreActionable, .moreCompassionate: return true
        }
    }

    var displayName: String {
        switch self {
        case .lessCatastrophic: return "Less Catastrophic"
        case .moreBalanced: return "More Balanced"
        case .moreActionable: return "More Actionable"
        case .moreCompassionate: return "More Self-Compassionate"
        }
    }

    var description: String {
        switch self {
        case .lessCatastrophic: return "See situations more proportionally"
        case .moreBalanced: return "Consider both positive and negative"
        case .moreActionable: return "Focus on steps you can take"
        case .moreCompassionate: return "Be kind to yourself"
        }
    }

    var iconName: String {
        switch self {
        case .lessCatastrophic: return "exclamationmark.triangle"
        case .moreBalanced: return "scale.3d"
        case .moreActionable: return "figure.walk"
        case .moreCompassionate: return "heart"
        }
    }
}

struct RewriteOption: Identifiable, Codable {
    let id: String
    let text: String
    let explanation: String
}

struct RewriteSession: Codable {
    let id: String
    let conversationId: String
    let messageId: String
    let originalMessage: String
    let rewriteType: RewriteType
    let options: [RewriteOption]
    var selectedOption: RewriteOption?
    var wasApplied: Bool
    let createdAt: Date
}

struct RewriteQuota: Codable {
    let dailyCount: Int
    let lastResetAt: Date
    let isPremium: Bool

    var remaining: Int {
        isPremium ? -1 : max(0, 5 - dailyCount)
    }
}

struct RewriteHistoryEntry: Identifiable, Codable {
    let id: String
    let createdAt: Date
    let originalMessage: String
    let rewriteType: String
    let rewrittenMessage: String?
    let wasApplied: Bool
    let feedbackRating: Int?
}

struct RewriteHistoryResponse: Codable {
    let entries: [RewriteHistoryEntry]
    let total: Int
    let hasMore: Bool
    let stats: RewriteStats
}

struct RewriteStats: Codable {
    let totalRewrites: Int
    let appliedCount: Int
    let averageRating: Double?
    let favoriteType: String?
}

// MARK: - API Request/Response Models

struct GenerateRewritesRequest: Codable {
    let conversationId: String
    let messageId: String
    let messageText: String
    let rewriteType: String
    let locale: String?
}

struct GenerateRewritesResponse: Codable {
    let rewrites: [RewriteOption]
    let remainingQuota: Int
    let isPremiumUser: Bool
    let historyId: String?
}

struct ApplyRewriteRequest: Codable {
    let conversationId: String
    let messageId: String
    let rewrittenText: String
    let rewriteHistoryId: String
}

struct ApplyRewriteResponse: Codable {
    let success: Bool
    let updatedMessageId: String
    let appliedAt: String
}

struct RewriteFeedbackRequest: Codable {
    let rewriteHistoryId: String
    let rating: Int
    let comment: String?
}

struct RewriteFeedbackResponse: Codable {
    let success: Bool
    let recordedAt: String
}

// MARK: - Error Types

enum RewriteError: Error, LocalizedError {
    case quotaExceeded(remainingQuota: Int)
    case premiumRequired
    case crisisContentDetected
    case invalidResponse
    case serverError(message: String)

    var errorDescription: String? {
        switch self {
        case .quotaExceeded(let remaining):
            return "Daily rewrite limit reached. \(remaining) rewrites remaining."
        case .premiumRequired:
            return "This rewrite type requires a premium subscription."
        case .crisisContentDetected:
            return "It sounds like you're going through a difficult time. Please reach out for help."
        case .invalidResponse:
            return "Invalid response from server."
        case .serverError(let message):
            return message
        }
    }
}

struct RewriteErrorResponse: Codable {
    let error: String
    let message: String?
    let upgradeRequired: Bool?
    let crisisResources: Bool?
    let remainingQuota: Int?

    enum CodingKeys: String, CodingKey {
        case error
        case message
        case upgradeRequired = "upgrade_required"
        case crisisResources = "crisis_resources"
        case remainingQuota = "remaining_quota"
    }
}
