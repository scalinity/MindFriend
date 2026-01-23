//
//  SocialVitalityModels.swift
//  MindFriend
//
//  Created: 2026-01-23
//  Feature: N004 - Social Vitality Index
//

import Foundation

// MARK: - Social Vitality Score

/// Daily social vitality score with 4 components (0-100 total)
struct SocialVitalityScore: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: String
    let date: Date
    let overallScore: Int  // 0-100
    let trend: ScoreTrend
    let interactionFrequency: Int  // 0-25
    let interactionDepth: Int      // 0-25
    let reciprocity: Int           // 0-25
    let diversity: Int             // 0-25
    let createdAt: Date

    enum ScoreTrend: String, Codable, Hashable {
        case improving
        case stable
        case declining
        case plummeting

        var displayName: String {
            switch self {
            case .improving: return "Improving"
            case .stable: return "Stable"
            case .declining: return "Declining"
            case .plummeting: return "Needs Attention"
            }
        }

        var icon: String {
            switch self {
            case .improving: return "arrow.up.right"
            case .stable: return "arrow.forward"
            case .declining: return "arrow.down.right"
            case .plummeting: return "exclamationmark.triangle"
            }
        }

        var color: String {
            switch self {
            case .improving: return "green"
            case .stable: return "blue"
            case .declining: return "orange"
            case .plummeting: return "red"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case overallScore = "overall_score"
        case trend
        case interactionFrequency = "interaction_frequency"
        case interactionDepth = "interaction_depth"
        case reciprocity
        case diversity
        case createdAt = "created_at"
    }
}

// MARK: - Relationship Correlation

/// Mood correlation analysis for a relationship
struct RelationshipCorrelation: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: String
    let otherUserId: String
    let otherUserDisplayName: String
    let moodCorrelation: Double  // -1.0 to +1.0
    let interactionCount: Int
    let confidenceLevel: Double  // 0.0 to 1.0
    let classification: RelationshipType
    let updatedAt: Date

    enum RelationshipType: String, Codable, Hashable {
        case supportPillar = "support_pillar"
        case neutral = "neutral"
        case draining = "draining"

        var displayName: String {
            switch self {
            case .supportPillar: return "Support Pillar"
            case .neutral: return "Neutral"
            case .draining: return "Needs Reflection"
            }
        }

        var icon: String {
            switch self {
            case .supportPillar: return "heart.fill"
            case .neutral: return "circle"
            case .draining: return "exclamationmark.circle"
            }
        }

        var color: String {
            switch self {
            case .supportPillar: return "green"
            case .neutral: return "gray"
            case .draining: return "orange"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case otherUserId = "other_user_id"
        case otherUserDisplayName = "other_user_display_name"
        case moodCorrelation = "mood_correlation"
        case interactionCount = "interaction_count"
        case confidenceLevel = "confidence_level"
        case classification
        case updatedAt = "updated_at"
    }

    /// Formatted correlation percentage (e.g., "+45%", "-23%")
    var correlationPercentage: String {
        let percent = Int(moodCorrelation * 100)
        let sign = percent >= 0 ? "+" : ""
        return "\(sign)\(percent)%"
    }

    /// Is this correlation statistically significant?
    var isSignificant: Bool {
        return confidenceLevel >= 0.8 && interactionCount >= 10
    }
}

// MARK: - Peer Alert Preferences

/// User preferences for peer support alert system
struct PeerAlertPreferences: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: String
    var enabled: Bool
    var alertThreshold: Threshold
    var designatedSupporters: [String]  // Max 3 UUIDs
    let createdAt: Date
    let updatedAt: Date

    enum Threshold: String, Codable, Hashable {
        case moderate
        case severe

        var displayName: String {
            switch self {
            case .moderate: return "Moderate"
            case .severe: return "Severe"
            }
        }

        var description: String {
            switch self {
            case .moderate: return "Notify when score declines 15+ points"
            case .severe: return "Notify only when score declines 25+ points"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case enabled
        case alertThreshold = "alert_threshold"
        case designatedSupporters = "designated_supporters"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Can add more supporters?
    var canAddMoreSupporters: Bool {
        return designatedSupporters.count < 3
    }

    /// Number of supporters configured
    var supportersConfigured: Int {
        return designatedSupporters.count
    }
}

// MARK: - Withdrawal Status

/// Withdrawal pattern detection result
struct WithdrawalStatus: Codable, Hashable {
    let severity: Severity
    let declinePercent: Int
    let daysSincePeak: Int
    let shouldAlert: Bool

    enum Severity: String, Codable, Hashable {
        case moderate
        case severe

        var displayName: String {
            switch self {
            case .moderate: return "Moderate Withdrawal"
            case .severe: return "Severe Withdrawal"
            }
        }

        var description: String {
            switch self {
            case .moderate: return "Your social connections have been quieter lately."
            case .severe: return "Your social connections have declined significantly."
            }
        }

        var color: String {
            switch self {
            case .moderate: return "orange"
            case .severe: return "red"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case severity
        case declinePercent = "decline_percent"
        case daysSincePeak = "days_since_peak"
        case shouldAlert = "should_alert"
    }
}

// MARK: - Social Vitality Dashboard

/// Aggregate dashboard data
struct SocialVitalityDashboard: Codable, Hashable {
    let currentScore: Int
    let trend: SocialVitalityScore.ScoreTrend
    let components: ScoreComponents
    let weeklyChange: Int
    let topSupporters: [SupporterInfo]
    let insight: String?
    let alertStatus: AlertStatus

    struct ScoreComponents: Codable, Hashable {
        let frequency: Int
        let depth: Int
        let reciprocity: Int
        let diversity: Int
    }

    struct SupporterInfo: Codable, Identifiable, Hashable {
        let id: String
        let name: String
        let correlation: Double

        var correlationPercentage: String {
            let percent = Int(correlation * 100)
            return "+\(percent)%"
        }
    }

    struct AlertStatus: Codable, Hashable {
        let enabled: Bool
        let supportersConfigured: Int
    }

    enum CodingKeys: String, CodingKey {
        case currentScore
        case trend
        case components
        case weeklyChange
        case topSupporters
        case insight
        case alertStatus
    }
}

// MARK: - Peer Support Consent

/// Supporter's consent to receive peer alerts
struct PeerSupportConsent: Codable, Identifiable, Hashable {
    let id: UUID
    let supporterId: String
    let requestingUserId: String
    var accepted: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case supporterId = "supporter_id"
        case requestingUserId = "requesting_user_id"
        case accepted
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Peer Alert

/// Record of a peer support alert sent
struct PeerAlert: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: String
    let supporterId: String
    let alertType: AlertType
    let message: String
    var acknowledged: Bool
    let deliveryFailed: Bool
    let createdAt: Date

    enum AlertType: String, Codable, Hashable {
        case withdrawalDetected = "withdrawal_detected"
        case reachOutReminder = "reach_out_reminder"

        var displayName: String {
            switch self {
            case .withdrawalDetected: return "Withdrawal Detected"
            case .reachOutReminder: return "Reach Out Reminder"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case supporterId = "supporter_id"
        case alertType = "alert_type"
        case message
        case acknowledged
        case deliveryFailed = "delivery_failed"
        case createdAt = "created_at"
    }
}

// MARK: - Helper Extensions

extension SocialVitalityScore {
    /// Is this a provisional score (days 7-13)?
    var isProvisional: Bool {
        let daysAgo = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        return daysAgo <= 7
    }

    /// Score as a decimal (0.0 to 1.0) for progress views
    var scoreDecimal: Double {
        return Double(overallScore) / 100.0
    }
}

extension SocialVitalityDashboard {
    /// Is collecting baseline data?
    var isCollectingBaseline: Bool {
        return currentScore == 0 && topSupporters.isEmpty
    }

    /// Weekly change as formatted string (e.g., "+5", "-12")
    var weeklyChangeFormatted: String {
        let sign = weeklyChange >= 0 ? "+" : ""
        return "\(sign)\(weeklyChange)"
    }
}
