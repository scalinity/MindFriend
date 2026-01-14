import Foundation
import Supabase

/// Supabase configuration loaded from Info.plist
/// 
/// IMPORTANT: Do not hardcode credentials in source code.
/// Set SUPABASE_URL and SUPABASE_ANON_KEY in your xcconfig or build settings.
/// 
/// For local development, create a Debug.xcconfig with:
///   SUPABASE_URL = https://your-project.supabase.co
///   SUPABASE_ANON_KEY = your-anon-key
enum SupabaseConfig {
    static let projectURL: URL = {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !urlString.isEmpty,
              !urlString.contains("$("),  // Not substituted
              let url = URL(string: urlString) else {
            // Fallback for development - will be removed in production builds
            #if DEBUG
            return URL(string: "https://***REMOVED***")!
            #else
            fatalError("SUPABASE_URL not configured in build settings. Add to xcconfig or Info.plist.")
            #endif
        }
        return url
    }()
    
    static let anonKey: String = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty,
              !key.contains("$(") else {  // Not substituted
            // Fallback for development - will be removed in production builds
            #if DEBUG
            return "***REMOVED***"
            #else
            fatalError("SUPABASE_ANON_KEY not configured in build settings. Add to xcconfig or Info.plist.")
            #endif
        }
        return key
    }()

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
    static let userSettings = "user_settings"
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
    static let memoryFragments = "memory_fragments"
    // Progression system
    static let userStats = "user_stats"
    static let skillProgress = "skill_progress"
    static let seasonalEvents = "seasonal_events"
    static let eventParticipation = "event_participation"
    // Credibility signals
    static let testimonials = "testimonials"
    static let methodologyInfo = "methodology_info"
}

// MARK: - Database Models (matching Supabase schema)

/// Minimal profile struct for existence checks
struct DBProfileId: Codable {
    let id: UUID
}

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

    // XP & Level Progression
    var xpTotal: Int
    var xpThisWeek: Int
    var level: Int
    var levelTitle: String
    var lastXpResetWeek: String?

    // Subscription
    var subscriptionTier: String
    var dailyAiQuota: Int
    var dailyAiUsed: Int

    // Onboarding
    var wellnessFocus: String?
    var onboardingCompletedAt: Date?

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
        case xpTotal = "xp_total"
        case xpThisWeek = "xp_this_week"
        case level
        case levelTitle = "level_title"
        case lastXpResetWeek = "last_xp_reset_week"
        case subscriptionTier = "subscription_tier"
        case dailyAiQuota = "daily_ai_quota"
        case dailyAiUsed = "daily_ai_used"
        case wellnessFocus = "wellness_focus"
        case onboardingCompletedAt = "onboarding_completed_at"
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

struct DBQuestInstruction: Codable {
    let step: Int
    let text: String
}

struct DBQuestTemplate: Codable {
    let id: UUID
    let title: String
    let description: String
    let category: String
    let estimatedMinutes: Int
    let xpReward: Int
    let isPremium: Bool
    let instructions: [DBQuestInstruction]?

    enum CodingKeys: String, CodingKey {
        case id, title, description, category, instructions
        case estimatedMinutes = "estimated_minutes"
        case xpReward = "xp_reward"
        case isPremium = "is_premium"
    }

    /// Generate default instructions based on quest category and title
    func defaultInstructions() -> [QuestInstruction] {
        // If database has instructions, use those
        if let dbInstructions = instructions, !dbInstructions.isEmpty {
            return dbInstructions.map { QuestInstruction(step: $0.step, text: $0.text, durationSeconds: nil) }
        }

        // Generate default instructions based on category
        switch category.lowercased() {
        case "gratitude":
            return [
                QuestInstruction(step: 1, text: "Find a quiet moment to reflect", durationSeconds: nil),
                QuestInstruction(step: 2, text: "Think about what you're thankful for today", durationSeconds: 60),
                QuestInstruction(step: 3, text: "Write down or mentally note 3 specific things", durationSeconds: 120),
                QuestInstruction(step: 4, text: "For each one, consider why it matters to you", durationSeconds: 60),
                QuestInstruction(step: 5, text: "Take a moment to feel the gratitude", durationSeconds: 30)
            ]
        case "mindfulness":
            return [
                QuestInstruction(step: 1, text: "Find a comfortable seated position", durationSeconds: nil),
                QuestInstruction(step: 2, text: "Close your eyes and take 3 deep breaths", durationSeconds: 30),
                QuestInstruction(step: 3, text: "Focus your attention on the present moment", durationSeconds: 60),
                QuestInstruction(step: 4, text: "Notice any sensations without judgment", durationSeconds: 120),
                QuestInstruction(step: 5, text: "Gently bring your awareness back when you're ready", durationSeconds: nil)
            ]
        case "social":
            return [
                QuestInstruction(step: 1, text: "Think of someone you'd like to connect with", durationSeconds: nil),
                QuestInstruction(step: 2, text: "Consider what you appreciate about them", durationSeconds: 60),
                QuestInstruction(step: 3, text: "Craft a genuine, heartfelt message", durationSeconds: 120),
                QuestInstruction(step: 4, text: "Send your message through your preferred method", durationSeconds: nil),
                QuestInstruction(step: 5, text: "Notice how reaching out makes you feel", durationSeconds: nil)
            ]
        case "physical":
            return [
                QuestInstruction(step: 1, text: "Prepare for your activity (comfortable clothes, water)", durationSeconds: nil),
                QuestInstruction(step: 2, text: "Start with a gentle warm-up", durationSeconds: 60),
                QuestInstruction(step: 3, text: "Begin your main activity at a comfortable pace", durationSeconds: nil),
                QuestInstruction(step: 4, text: "Stay present and notice how your body feels", durationSeconds: nil),
                QuestInstruction(step: 5, text: "Cool down and take a few deep breaths", durationSeconds: 60)
            ]
        case "creative":
            return [
                QuestInstruction(step: 1, text: "Gather your creative materials", durationSeconds: nil),
                QuestInstruction(step: 2, text: "Set aside any expectations of perfection", durationSeconds: nil),
                QuestInstruction(step: 3, text: "Begin creating freely without self-judgment", durationSeconds: 300),
                QuestInstruction(step: 4, text: "Let your intuition guide your choices", durationSeconds: nil),
                QuestInstruction(step: 5, text: "Appreciate what you've created, no matter how it looks", durationSeconds: nil)
            ]
        case "reflection", "focus":
            return [
                QuestInstruction(step: 1, text: "Find a quiet space where you won't be disturbed", durationSeconds: nil),
                QuestInstruction(step: 2, text: "Take a few deep breaths to center yourself", durationSeconds: 30),
                QuestInstruction(step: 3, text: "Reflect on the topic at hand", durationSeconds: 180),
                QuestInstruction(step: 4, text: "Notice any thoughts or feelings that arise", durationSeconds: 60),
                QuestInstruction(step: 5, text: "Consider what insights you've gained", durationSeconds: nil)
            ]
        default:
            return [
                QuestInstruction(step: 1, text: "Read through the quest description carefully", durationSeconds: nil),
                QuestInstruction(step: 2, text: "Prepare yourself mentally for the activity", durationSeconds: nil),
                QuestInstruction(step: 3, text: "Complete the quest mindfully and with intention", durationSeconds: nil),
                QuestInstruction(step: 4, text: "Reflect on how the experience felt", durationSeconds: nil),
                QuestInstruction(step: 5, text: "Celebrate completing your quest!", durationSeconds: nil)
            ]
        }
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

struct DBExerciseInstruction: Codable {
    let step: Int
    let text: String
}

struct DBExercise: Codable {
    let id: UUID
    let title: String
    let description: String
    let type: String
    let durationMinutes: Int
    let instructions: [DBExerciseInstruction]?
    let isPremium: Bool

    // Credibility fields
    let evidenceBasis: String?
    let therapistReviewed: Bool?
    let reviewDate: String?
    let methodologyNote: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, type
        case durationMinutes = "duration_minutes"
        case instructions
        case isPremium = "is_premium"
        case evidenceBasis = "evidence_basis"
        case therapistReviewed = "therapist_reviewed"
        case reviewDate = "review_date"
        case methodologyNote = "methodology_note"
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

struct DBCircleCheckinWithProfile: Codable {
    let id: UUID?
    let circleId: UUID
    let userId: UUID
    let moodEmoji: String
    let bodyText: String?
    let createdAt: Date?
    let profiles: DBMemberProfile?

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case userId = "user_id"
        case moodEmoji = "mood_emoji"
        case bodyText = "body_text"
        case createdAt = "created_at"
        case profiles
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

struct DBMemoryFragment: Codable {
    let id: UUID
    let userId: UUID
    let fragmentType: String
    let key: String
    let value: String
    let confidence: Double
    let sourceConversationId: UUID?
    let sourceMessageId: UUID?
    let extractedAt: Date
    let expiresAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case fragmentType = "fragment_type"
        case key, value, confidence
        case sourceConversationId = "source_conversation_id"
        case sourceMessageId = "source_message_id"
        case extractedAt = "extracted_at"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toMemoryFragment() -> MemoryFragment {
        MemoryFragment(
            id: id.uuidString,
            fragmentType: MemoryType(rawValue: fragmentType) ?? .fact,
            key: key,
            value: value,
            confidence: confidence,
            extractedAt: extractedAt,
            expiresAt: expiresAt
        )
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
                totalExercisesCompleted: totalExercisesCompleted,
                xpTotal: xpTotal,
                xpThisWeek: xpThisWeek,
                level: level,
                levelTitle: levelTitle,
                lastXpResetWeek: lastXpResetWeek
            ),
            entitlements: Entitlements(
                tier: Tier(rawValue: subscriptionTier) ?? .free,
                dailyAiQuota: dailyAiQuota,
                dailyAiUsed: dailyAiUsed
            ),
            badges: [],
            wellnessFocus: wellnessFocus.flatMap { WellnessFocus(rawValue: $0) },
            onboardingCompletedAt: onboardingCompletedAt
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

// MARK: - Progression System Database Models

struct DBSkillProgress: Codable {
    let id: UUID
    let userId: UUID
    let skillType: String
    let xp: Int
    let level: Int
    let exercisesCompleted: Int
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case skillType = "skill_type"
        case xp, level
        case exercisesCompleted = "exercises_completed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DBSeasonalEvent: Codable {
    let id: UUID
    let name: String
    let description: String?
    let startsAt: Date
    let endsAt: Date
    let eventType: String
    let requiredActivityType: String?
    let rewardBadgeId: UUID?
    let targetCount: Int
    let xpMultiplier: Double
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case eventType = "event_type"
        case requiredActivityType = "required_activity_type"
        case rewardBadgeId = "reward_badge_id"
        case targetCount = "target_count"
        case xpMultiplier = "xp_multiplier"
        case createdAt = "created_at"
    }
}

struct DBEventParticipation: Codable {
    let id: UUID
    let userId: UUID
    let eventId: UUID
    let progress: Int
    let completedAt: Date?
    let joinedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case eventId = "event_id"
        case progress
        case completedAt = "completed_at"
        case joinedAt = "joined_at"
    }
}

/// Response from the award_xp RPC function
struct DBHugLimitResult: Codable {
    let allowed: Bool
}

struct DBXPAwardResult: Codable {
    let newXp: Int
    let newLevel: Int
    let newTitle: String
    let levelUp: Bool

    enum CodingKeys: String, CodingKey {
        case newXp = "new_xp"
        case newLevel = "new_level"
        case newTitle = "new_title"
        case levelUp = "level_up"
    }
}

/// Response from the increment_event_progress RPC function
struct DBEventProgressResult: Codable {
    let eventId: UUID
    let eventName: String
    let newProgress: Int
    let targetCount: Int
    let justCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case eventName = "event_name"
        case newProgress = "new_progress"
        case targetCount = "target_count"
        case justCompleted = "just_completed"
    }
}

// MARK: - Date Formatter Extension

extension ISO8601DateFormatter {
    static let full: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
