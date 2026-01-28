// Spec 11: Family Wellness - Data Models
// Extended family models with Codable conformance and CodingKeys for snake_case conversion

import Foundation
import SwiftUI

// MARK: - Family Group

struct FamilyWellnessGroup: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    let adminUserId: String
    let circleId: String?

    // Wellness features (new)
    var avatarUrl: String?
    var inviteCode: String?
    var defaultChildAgeFilter: Int?
    var requireParentApprovalForContent: Bool?
    var shareActivityByDefault: Bool?
    var maxMembers: Int?

    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case adminUserId = "admin_user_id"
        case circleId = "circle_id"
        case avatarUrl = "avatar_url"
        case inviteCode = "invite_code"
        case defaultChildAgeFilter = "default_child_age_filter"
        case requireParentApprovalForContent = "require_parent_approval_for_content"
        case shareActivityByDefault = "share_activity_by_default"
        case maxMembers = "max_members"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Family Member

struct FamilyWellnessMember: Codable, Identifiable, Equatable {
    let id: String
    let familyId: String
    let userId: String

    var role: FamilyRole
    var nickname: String?
    var avatarEmoji: String?

    var birthDate: Date?
    var ageFilterOverride: Int?

    var shareMoodWithFamily: Bool
    var shareActivityWithFamily: Bool
    var shareAchievementsWithFamily: Bool

    var status: FamilyMemberStatus
    let invitedBy: String?
    let joinedAt: Date?

    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case userId = "user_id"
        case role
        case nickname
        case avatarEmoji = "avatar_emoji"
        case birthDate = "birth_date"
        case ageFilterOverride = "age_filter_override"
        case shareMoodWithFamily = "share_mood_with_family"
        case shareActivityWithFamily = "share_activity_with_family"
        case shareAchievementsWithFamily = "share_achievements_with_family"
        case status
        case invitedBy = "invited_by"
        case joinedAt = "joined_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var calculatedAge: Int? {
        guard let birthDate = birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }

    var effectiveAgeFilter: Int {
        if let override = ageFilterOverride, let age = calculatedAge, override > age {
            return override
        }
        return calculatedAge ?? 18
    }

    var displayName: String {
        nickname ?? "Family Member"
    }
}

enum FamilyRole: String, Codable, CaseIterable, Equatable {
    case admin
    case parent
    case teen
    case child

    var displayName: String {
        switch self {
        case .admin: return "Admin"
        case .parent: return "Parent"
        case .teen: return "Teen"
        case .child: return "Child"
        }
    }

    var canManageFamily: Bool {
        self == .admin || self == .parent
    }

    var hasFullAIAccess: Bool {
        self != .child
    }
}

enum FamilyMemberStatus: String, Codable, Equatable {
    case active
    case pending
    case removed
}

// MARK: - Family Challenge

struct FamilyChallenge: Codable, Identifiable, Equatable {
    let id: String
    let familyId: String

    let title: String
    let description: String?
    let challengeType: FamilyChallengeType

    let targetValue: Int
    let minimumParticipants: Int

    let startDate: Date
    let endDate: Date?

    let requiresAllMembers: Bool
    let allowMakeupActivities: Bool

    var status: FamilyChallengeStatus
    var currentProgress: Int

    let badgeId: String?
    let rewardDescription: String?

    let createdBy: String
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case title, description
        case challengeType = "challenge_type"
        case targetValue = "target_value"
        case minimumParticipants = "minimum_participants"
        case startDate = "start_date"
        case endDate = "end_date"
        case requiresAllMembers = "requires_all_members"
        case allowMakeupActivities = "allow_makeup_activities"
        case status
        case currentProgress = "current_progress"
        case badgeId = "badge_id"
        case rewardDescription = "reward_description"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var progressPercentage: Double {
        guard targetValue > 0 else { return 0 }
        return min(1.0, Double(currentProgress) / Double(targetValue))
    }
}

enum FamilyChallengeType: String, Codable, Equatable {
    case streak
    case cumulative
    case event
    case custom
}

enum FamilyChallengeStatus: String, Codable, Equatable {
    case active
    case completed
    case failed
    case cancelled
}

// MARK: - Family Challenge Template

struct FamilyChallengeTemplate: Codable, Identifiable, Equatable {
    let id: String

    let title: String
    let description: String
    let challengeType: FamilyChallengeType
    let targetValue: Int
    let suggestedDurationDays: Int?

    let iconName: String?
    let category: String
    let difficulty: String

    let minimumAge: Int
    let requiresPremium: Bool
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title, description
        case challengeType = "challenge_type"
        case targetValue = "target_value"
        case suggestedDurationDays = "suggested_duration_days"
        case iconName = "icon_name"
        case category
        case difficulty
        case minimumAge = "minimum_age"
        case requiresPremium = "requires_premium"
        case isActive = "is_active"
    }
}

// MARK: - Family Activity Summary

struct FamilyActivitySummary: Codable, Identifiable, Equatable {
    let id: String
    let familyId: String
    let memberId: String

    let periodStart: Date
    let periodEnd: Date

    let sessionsCompleted: Int
    let totalDurationMinutes: Int
    let streakDays: Int

    let moodTrend: MoodTrend?
    let averageMoodScore: Double?

    let badgesEarned: Int
    let challengesContributed: Int

    let daysActive: Int
    let mostUsedCategory: String?

    let calculatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case memberId = "member_id"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case sessionsCompleted = "sessions_completed"
        case totalDurationMinutes = "total_duration_minutes"
        case streakDays = "streak_days"
        case moodTrend = "mood_trend"
        case averageMoodScore = "average_mood_score"
        case badgesEarned = "badges_earned"
        case challengesContributed = "challenges_contributed"
        case daysActive = "days_active"
        case mostUsedCategory = "most_used_category"
        case calculatedAt = "calculated_at"
    }
}

enum MoodTrend: String, Codable, Equatable, Hashable {
    case improving
    case stable
    case declining
    case baseline
    case insufficientData = "insufficient_data"

    var icon: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .stable: return "arrow.right"
        case .declining: return "arrow.down.right"
        case .baseline, .insufficientData: return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .improving: return .green
        case .stable: return .yellow
        case .declining: return .orange
        case .baseline, .insufficientData: return .gray
        }
    }

    var emoji: String {
        switch self {
        case .improving: return "📈"
        case .stable: return "➡️"
        case .declining: return "📉"
        case .baseline, .insufficientData: return "❓"
        }
    }

    /// User-friendly display name for the trend
    var displayName: String {
        switch self {
        case .improving: return String(localized: "Improving")
        case .stable: return String(localized: "Stable")
        case .declining: return String(localized: "Declining")
        case .baseline: return String(localized: "Baseline")
        case .insufficientData: return String(localized: "Not enough data")
        }
    }
}

// MARK: - Family Alert

struct FamilyAlert: Codable, Identifiable, Equatable {
    let id: String
    let familyId: String
    let aboutMemberId: String
    let forParentId: String

    let alertType: FamilyAlertType
    let severity: FamilyAlertSeverity
    let title: String
    let message: String

    let actionType: AlertActionType?
    let actionData: [String: String]?
    let conversationStarters: [String]?

    var wasRead: Bool
    var wasActedUpon: Bool
    var readAt: Date?

    let expiresAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case aboutMemberId = "about_member_id"
        case forParentId = "for_parent_id"
        case alertType = "alert_type"
        case severity
        case title, message
        case actionType = "action_type"
        case actionData = "action_data"
        case conversationStarters = "conversation_starters"
        case wasRead = "was_read"
        case wasActedUpon = "was_acted_upon"
        case readAt = "read_at"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

enum FamilyAlertType: String, Codable, Equatable {
    case moodConcern = "mood_concern"
    case inactivity
    case achievement
    case milestone
}

enum FamilyAlertSeverity: String, Codable, Equatable {
    case info
    case attention
    case concern

    var color: String {
        switch self {
        case .info: return "blue"
        case .attention: return "yellow"
        case .concern: return "red"
        }
    }
}

enum AlertActionType: String, Codable, Equatable {
    case startConversation = "start_conversation"
    case checkIn = "check_in"
    case celebrate
}

// MARK: - Parental Consent (COPPA)

struct ParentalConsent: Codable, Identifiable, Equatable {
    let id: String
    let childUserId: String
    let parentUserId: String
    let parentEmail: String

    let consentType: ConsentType
    let verificationCode: String?
    let verifiedAt: Date?
    let expiresAt: Date

    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case childUserId = "child_user_id"
        case parentUserId = "parent_user_id"
        case parentEmail = "parent_email"
        case consentType = "consent_type"
        case verificationCode = "verification_code"
        case verifiedAt = "verified_at"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

enum ConsentType: String, Codable, Equatable {
    case initial
    case annualRenewal = "annual_renewal"
}
