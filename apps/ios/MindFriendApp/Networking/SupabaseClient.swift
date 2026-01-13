import Foundation
import Supabase

/// Supabase configuration and client
enum SupabaseConfig {
    static let projectURL = URL(string: "https://***REMOVED***")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpmYXVjaXZ0emZ3bnJpanNiZnVnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzY2OTg0MDAsImV4cCI6MjA1MjI3NDQwMH0.sb_publishable_tn0k28wWJEV2zmKhX9Vmtg_VK_ZdpLP"

    // OAuth redirect URL for Sign in with Apple/Google
    static let redirectURL = URL(string: "mindfriend://auth/callback")!
}

/// Shared Supabase client instance
let supabase = SupabaseClient(
    supabaseURL: SupabaseConfig.projectURL,
    supabaseKey: SupabaseConfig.anonKey
)

// MARK: - Database Table Names

enum Tables {
    static let profiles = "profiles"
    static let devices = "devices"
    static let moods = "moods"
    static let questTemplates = "quest_templates"
    static let userQuests = "user_quests"
    static let exercises = "exercises"
    static let exerciseSessions = "exercise_sessions"
    static let conversations = "conversations"
    static let messages = "messages"
    static let circles = "circles"
    static let circleMembers = "circle_members"
    static let circleCheckins = "circle_checkins"
    static let badges = "badges"
    static let userBadges = "user_badges"
    static let crisisResources = "crisis_resources"
}

// MARK: - Database Models (matching Supabase schema)

struct DBProfile: Codable {
    let id: UUID
    var handle: String?
    var displayName: String?
    var email: String?
    var avatarUrl: String?
    var timezone: String
    let createdAt: Date
    var updatedAt: Date

    // Settings
    var dailyQuestTimeLocal: String
    var quietHoursStartLocal: String?
    var quietHoursEndLocal: String?
    var remindersEnabled: Bool
    var nudgeAfterDaysInactive: Int
    var shareMoodInCircles: Bool
    var aiTone: String
    var privacyMode: String

    // Stats
    var currentStreakDays: Int
    var longestStreakDays: Int
    var totalQuestsCompleted: Int
    var totalExercisesCompleted: Int

    // Subscription
    var subscriptionTier: String
    var dailyAiQuota: Int
    var dailyAiUsed: Int

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case displayName = "display_name"
        case email
        case avatarUrl = "avatar_url"
        case timezone
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case dailyQuestTimeLocal = "daily_quest_time_local"
        case quietHoursStartLocal = "quiet_hours_start_local"
        case quietHoursEndLocal = "quiet_hours_end_local"
        case remindersEnabled = "reminders_enabled"
        case nudgeAfterDaysInactive = "nudge_after_days_inactive"
        case shareMoodInCircles = "share_mood_in_circles"
        case aiTone = "ai_tone"
        case privacyMode = "privacy_mode"
        case currentStreakDays = "current_streak_days"
        case longestStreakDays = "longest_streak_days"
        case totalQuestsCompleted = "total_quests_completed"
        case totalExercisesCompleted = "total_exercises_completed"
        case subscriptionTier = "subscription_tier"
        case dailyAiQuota = "daily_ai_quota"
        case dailyAiUsed = "daily_ai_used"
    }
}

struct DBMood: Codable {
    let id: UUID?
    let userId: UUID
    let localDate: String
    let moodScore: Int
    let anxietyScore: Int?
    let energyScore: Int?
    let note: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case localDate = "local_date"
        case moodScore = "mood_score"
        case anxietyScore = "anxiety_score"
        case energyScore = "energy_score"
        case note
        case createdAt = "created_at"
    }
}

struct DBQuestTemplate: Codable {
    let id: UUID
    let title: String
    let description: String
    let category: String
    let estimatedMinutes: Int
    let xpReward: Int
    let isPremium: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, description, category
        case estimatedMinutes = "estimated_minutes"
        case xpReward = "xp_reward"
        case isPremium = "is_premium"
    }
}

struct DBUserQuest: Codable {
    let id: UUID?
    let userId: UUID
    let questTemplateId: UUID
    let assignedDate: String
    var status: String
    var reflectionNote: String?
    var rating: Int?
    var completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case questTemplateId = "quest_template_id"
        case assignedDate = "assigned_date"
        case status
        case reflectionNote = "reflection_note"
        case rating
        case completedAt = "completed_at"
    }
}

struct DBExercise: Codable {
    let id: UUID
    let title: String
    let description: String
    let type: String
    let durationMinutes: Int
    let instructions: [[String: String]]?
    let isPremium: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, description, type
        case durationMinutes = "duration_minutes"
        case instructions
        case isPremium = "is_premium"
    }
}

struct DBConversation: Codable {
    let id: UUID?
    let userId: UUID
    var title: String?
    let createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DBMessage: Codable {
    let id: UUID?
    let conversationId: UUID
    let role: String
    let content: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case role, content
        case createdAt = "created_at"
    }
}

struct DBCircle: Codable {
    let id: UUID?
    let name: String
    let description: String?
    let inviteCode: String?
    let ownerId: UUID
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case inviteCode = "invite_code"
        case ownerId = "owner_id"
        case createdAt = "created_at"
    }
}

struct DBCircleMember: Codable {
    let id: UUID?
    let circleId: UUID
    let userId: UUID
    let joinedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
    }
}

struct DBCircleCheckin: Codable {
    let id: UUID?
    let circleId: UUID
    let userId: UUID
    let moodEmoji: String
    let bodyText: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case userId = "user_id"
        case moodEmoji = "mood_emoji"
        case bodyText = "body_text"
        case createdAt = "created_at"
    }
}

struct DBBadge: Codable {
    let id: UUID
    let name: String
    let description: String
    let iconName: String
    let requirementType: String
    let requirementValue: Int

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case iconName = "icon_name"
        case requirementType = "requirement_type"
        case requirementValue = "requirement_value"
    }
}

struct DBCrisisResource: Codable {
    let id: UUID
    let countryCode: String
    let name: String
    let phone: String?
    let textLine: String?
    let website: String?
    let description: String?
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case countryCode = "country_code"
        case name, phone
        case textLine = "text_line"
        case website, description
        case isDefault = "is_default"
    }
}

// MARK: - Model Conversion Extensions

extension DBProfile {
    func toUserProfile() -> UserProfile {
        UserProfile(
            id: id.uuidString,
            handle: handle ?? "",
            displayName: displayName ?? "User",
            email: email,
            timezone: timezone,
            createdAt: createdAt,
            settings: UserSettings(
                dailyQuestTimeLocal: dailyQuestTimeLocal,
                quietHoursStartLocal: quietHoursStartLocal,
                quietHoursEndLocal: quietHoursEndLocal,
                remindersEnabled: remindersEnabled,
                nudgeAfterDaysInactive: nudgeAfterDaysInactive,
                shareMoodInCircles: shareMoodInCircles,
                aiTone: AITone(rawValue: aiTone) ?? .friendly,
                privacyMode: PrivacyMode(rawValue: privacyMode) ?? .standard
            ),
            stats: UserStats(
                currentStreakDays: currentStreakDays,
                longestStreakDays: longestStreakDays,
                totalQuestsCompleted: totalQuestsCompleted,
                totalExercisesCompleted: totalExercisesCompleted
            ),
            entitlements: Entitlements(
                tier: Tier(rawValue: subscriptionTier) ?? .free,
                dailyAiQuota: dailyAiQuota,
                dailyAiUsed: dailyAiUsed
            ),
            badges: []
        )
    }
}

extension DBMood {
    func toMoodEntry() -> MoodEntry {
        MoodEntry(
            id: id?.uuidString ?? UUID().uuidString,
            localDate: localDate,
            moodScore: moodScore,
            anxietyScore: anxietyScore,
            energyScore: energyScore,
            note: note,
            source: .manual,
            createdAt: createdAt ?? Date()
        )
    }
}
