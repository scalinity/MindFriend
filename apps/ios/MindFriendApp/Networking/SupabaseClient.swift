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
            fatalError("SUPABASE_URL not configured. Add Debug.xcconfig/Release.xcconfig with SUPABASE_URL.")
        }
        return url
    }()

    static let anonKey: String = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty,
              !key.contains("$(") else {  // Not substituted
            fatalError("SUPABASE_ANON_KEY not configured. Add Debug.xcconfig/Release.xcconfig with SUPABASE_ANON_KEY.")
        }
        return key
    }()

    // OAuth redirect URL for Sign in with Apple/Google
    static let redirectURL = URL(string: "mindfriend://auth/callback")!
}

/// Shared Supabase client instance
let supabase = SupabaseClient(
    supabaseURL: SupabaseConfig.projectURL,
    supabaseKey: SupabaseConfig.anonKey,
    options: SupabaseClientOptions(
        auth: .init(
            redirectToURL: SupabaseConfig.redirectURL,
            flowType: .pkce,
            emitLocalSessionAsInitialSession: true
        )
    )
)

// MARK: - Database Table Names

enum Tables {
    // Core user data (split across 3 tables per schema)
    static let profiles = "profiles"
    static let userSettings = "user_settings"
    static let userStats = "user_stats"

    // Mood tracking
    static let moods = "moods"

    // Quests (correct table name - not "user_quests")
    static let questTemplates = "quest_templates"
    static let quests = "quests"

    // Exercises
    static let exercises = "exercises"
    static let exerciseSessions = "exercise_sessions"

    // Chat
    static let conversations = "conversations"
    static let messages = "messages"

    // Circles (correct table name for posts - not "circle_checkins")
    static let circles = "circles"
    static let circleMembers = "circle_members"
    static let circlePosts = "circle_posts"

    // Badges
    static let badges = "badges"
    static let userBadges = "user_badges"

    // Crisis
    static let crisisResources = "crisis_resources"
    static let crisisEvents = "crisis_events"

    // Subscriptions
    static let subscriptions = "subscriptions"

    // Action Autopilot
    static let actionPlans = "action_plans"
    static let actionPlanItems = "action_plan_items"
    static let actionPlanFeedback = "action_plan_feedback"

    // Memory
    static let memoryFragments = "memory_fragments"

    // Push notifications (correct table name - not "devices")
    static let pushTokens = "push_tokens"

    // Progression system
    static let skillProgress = "skill_progress"
    static let seasonalEvents = "seasonal_events"
    static let eventParticipation = "event_participation"

    // Credibility signals
    static let testimonials = "testimonials"
    static let methodologyInfo = "methodology_info"

    // Proactive Intelligence
    static let userEngagementStates = "user_engagement_states"
    static let userPatterns = "user_patterns"
    static let proactiveMessages = "proactive_messages"

    // Structured Programs
    static let programs = "programs"
    static let programDays = "program_days"
    static let programEnrollments = "program_enrollments"
    static let programDayProgress = "program_day_progress"
    static let programCertificates = "program_certificates"

    // Live Experiences
    static let liveSessions = "live_sessions"
    static let liveSessionParticipants = "live_session_participants"
    static let circleLiveRooms = "circle_live_rooms"
    static let circleRoomParticipants = "circle_room_participants"
    static let buddyQuestWindows = "buddy_quest_windows"
    static let buddyWindowEvents = "buddy_window_events"
    static let userPresence = "user_presence"

    // Creative Expression
    static let creativeWorks = "creative_works"
    static let voiceJournalAnalysis = "voice_journal_analysis"
    static let aiArtGenerations = "ai_art_generations"
    static let drawingSessions = "drawing_sessions"
    static let creativeExercises = "creative_exercises"
    static let creativeExerciseCompletions = "creative_exercise_completions"
    static let musicMoodEntries = "music_mood_entries"
    static let creativeQuotaUsage = "creative_quota_usage"

    // Biometric Intelligence
    static let healthkitConnections = "healthkit_connections"
    static let biometricDailySummaries = "biometric_daily_summaries"
    static let biometricWorkouts = "biometric_workouts"
    static let biometricInsights = "biometric_insights"
    static let biometricBaselines = "biometric_baselines"
    static let biometricAlerts = "biometric_alerts"
    static let moodBiometricCorrelations = "mood_biometric_correlations"

    // Therapist Marketplace
    static let therapistProfiles = "therapist_profiles"
}

// MARK: - Database Models (matching Supabase schema)

/// Minimal profile struct for existence checks
struct DBProfileId: Codable {
    let id: UUID
}

// MARK: - Schema-Correct Row Structs (Issue #003)
// These match the actual Supabase migrations where profiles, user_settings, and user_stats are separate tables

/// Profile row from `profiles` table - identity and entitlements only
struct DBProfileRow: Codable {
    let id: UUID
    var handle: String
    var displayName: String
    var email: String?
    var avatarUrl: String?
    var timezone: String
    var subscriptionTier: String
    var dailyAiQuota: Int
    var dailyAiUsed: Int
    var quotaResetAt: Date?
    var premiumBadge: String?
    var wellnessFocus: String?
    var onboardingCompletedAt: Date?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, handle, email, timezone
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case subscriptionTier = "subscription_tier"
        case dailyAiQuota = "daily_ai_quota"
        case dailyAiUsed = "daily_ai_used"
        case quotaResetAt = "quota_reset_at"
        case premiumBadge = "premium_badge"
        case wellnessFocus = "wellness_focus"
        case onboardingCompletedAt = "onboarding_completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Settings row from `user_settings` table
struct DBUserSettingsRow: Codable {
    let userId: UUID
    var dailyQuestTimeLocal: String
    var quietHoursStartLocal: String?
    var quietHoursEndLocal: String?
    var remindersEnabled: Bool
    var nudgeAfterDaysInactive: Int
    var shareMoodInCircles: Bool
    var aiTone: String
    var privacyMode: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case dailyQuestTimeLocal = "daily_quest_time_local"
        case quietHoursStartLocal = "quiet_hours_start_local"
        case quietHoursEndLocal = "quiet_hours_end_local"
        case remindersEnabled = "reminders_enabled"
        case nudgeAfterDaysInactive = "nudge_after_days_inactive"
        case shareMoodInCircles = "share_mood_in_circles"
        case aiTone = "ai_tone"
        case privacyMode = "privacy_mode"
    }
}

/// Stats row from `user_stats` table
struct DBUserStatsRow: Codable {
    let userId: UUID
    var currentStreakDays: Int
    var longestStreakDays: Int
    var totalQuestsCompleted: Int
    var totalExercisesCompleted: Int
    var lastQuestDate: String?
    var xpTotal: Int
    var xpThisWeek: Int
    var level: Int
    var levelTitle: String
    var lastXpResetWeek: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case currentStreakDays = "current_streak_days"
        case longestStreakDays = "longest_streak_days"
        case totalQuestsCompleted = "total_quests_completed"
        case totalExercisesCompleted = "total_exercises_completed"
        case lastQuestDate = "last_quest_date"
        case xpTotal = "xp_total"
        case xpThisWeek = "xp_this_week"
        case level
        case levelTitle = "level_title"
        case lastXpResetWeek = "last_xp_reset_week"
    }
}

/// Compose UserProfile from the three separate table rows
extension DBProfileRow {
    func toUserProfile(settings: DBUserSettingsRow, stats: DBUserStatsRow) -> UserProfile {
        UserProfile(
            id: id.uuidString,
            handle: handle,
            displayName: displayName,
            email: email,
            timezone: timezone,
            createdAt: createdAt,
            settings: UserSettings(
                dailyQuestTimeLocal: settings.dailyQuestTimeLocal,
                quietHoursStartLocal: settings.quietHoursStartLocal,
                quietHoursEndLocal: settings.quietHoursEndLocal,
                remindersEnabled: settings.remindersEnabled,
                nudgeAfterDaysInactive: settings.nudgeAfterDaysInactive,
                shareMoodInCircles: settings.shareMoodInCircles,
                aiTone: AITone(rawValue: settings.aiTone) ?? .friendly,
                privacyMode: PrivacyMode(rawValue: settings.privacyMode) ?? .standard
            ),
            stats: UserStats(
                currentStreakDays: stats.currentStreakDays,
                longestStreakDays: stats.longestStreakDays,
                totalQuestsCompleted: stats.totalQuestsCompleted,
                totalExercisesCompleted: stats.totalExercisesCompleted,
                xpTotal: stats.xpTotal,
                xpThisWeek: stats.xpThisWeek,
                level: stats.level,
                levelTitle: stats.levelTitle,
                lastXpResetWeek: stats.lastXpResetWeek
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

// MARK: - Quest Row (correct schema - uses "quests" table with "local_date")

/// Quest row from `quests` table (not the legacy "user_quests")
struct DBQuest: Codable {
    let id: UUID?
    let userId: UUID
    let templateId: UUID
    let localDate: String
    var status: String
    var reflectionNote: String?
    var rating: Int?
    var assignedAt: Date?
    var completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case templateId = "template_id"
        case localDate = "local_date"
        case status
        case reflectionNote = "reflection_note"
        case rating
        case assignedAt = "assigned_at"
        case completedAt = "completed_at"
    }
}

/// Quest with template (for joined queries)
struct DBQuestWithTemplate: Codable {
    let id: UUID
    let userId: UUID
    let templateId: UUID
    let localDate: String
    var status: String
    var reflectionNote: String?
    var rating: Int?
    var assignedAt: Date?
    var completedAt: Date?
    let questTemplates: DBQuestTemplate?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case templateId = "template_id"
        case localDate = "local_date"
        case status
        case reflectionNote = "reflection_note"
        case rating
        case assignedAt = "assigned_at"
        case completedAt = "completed_at"
        case questTemplates = "quest_templates"
    }

    func toQuest() -> Quest? {
        guard let dbTemplate = questTemplates else { return nil }
        let questTemplate = QuestTemplate(
            id: dbTemplate.id.uuidString,
            type: QuestType(rawValue: dbTemplate.category.lowercased()) ?? .focus,
            title: dbTemplate.title,
            description: dbTemplate.description,
            estimatedMinutes: dbTemplate.estimatedMinutes,
            difficulty: "medium",
            tags: [],
            instructions: dbTemplate.defaultInstructions()
        )
        return Quest(
            id: id.uuidString,
            localDate: localDate,
            status: QuestStatus(rawValue: status) ?? .assigned,
            assignedAt: assignedAt ?? Date(),
            completedAt: completedAt,
            template: questTemplate
        )
    }
}

// MARK: - Circle Post Row (correct schema - uses "circle_posts" table with "kind")

/// Circle post row from `circle_posts` table (not the legacy "circle_checkins")
struct DBCirclePost: Codable {
    let id: UUID?
    let circleId: UUID
    let userId: UUID
    let kind: String // "checkin", "milestone", "encouragement"
    let moodEmoji: String?
    let bodyText: String?
    let localDate: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case userId = "user_id"
        case kind
        case moodEmoji = "mood_emoji"
        case bodyText = "body_text"
        case localDate = "local_date"
        case createdAt = "created_at"
    }
}

/// Helper struct for embedded profile in circle post/member queries
struct DBMemberProfile: Codable {
    let displayName: String?
    let handle: String?
    let avatarUrl: String?
    let premiumBadge: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case handle
        case avatarUrl = "avatar_url"
        case premiumBadge = "premium_badge"
    }
}

/// Circle post with profile data (for joined queries)
struct DBCirclePostWithProfile: Codable {
    let id: UUID?
    let circleId: UUID
    let userId: UUID
    let kind: String
    let moodEmoji: String?
    let bodyText: String?
    let localDate: String?
    let createdAt: Date?
    let profiles: DBMemberProfile?

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case userId = "user_id"
        case kind
        case moodEmoji = "mood_emoji"
        case bodyText = "body_text"
        case localDate = "local_date"
        case createdAt = "created_at"
        case profiles
    }

    func toCirclePost() -> CirclePost {
        CirclePost(
            id: id?.uuidString ?? UUID().uuidString,
            userId: userId.uuidString,
            userDisplayName: profiles?.displayName ?? "Member",
            kind: PostKind(rawValue: kind) ?? .checkin,
            moodEmoji: moodEmoji,
            bodyText: bodyText,
            localDate: localDate ?? "",
            createdAt: createdAt ?? Date()
        )
    }
}

// MARK: - DBProfile (used for data export - queries all profile fields in a single fetch)

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
    let category: String  // Resolved from either "category" or "type" column
    let estimatedMinutes: Int
    let xpReward: Int
    let isPremium: Bool
    let instructions: [DBQuestInstruction]?

    enum CodingKeys: String, CodingKey {
        case id, title, description, category, instructions
        case type  // Legacy column name - fallback for older schemas
        case estimatedMinutes = "estimated_minutes"
        case xpReward = "xp_reward"
        case isPremium = "is_premium"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)

        // Handle both "category" (new schema) and "type" (old schema)
        if let categoryValue = try container.decodeIfPresent(String.self, forKey: .category) {
            category = categoryValue
        } else if let typeValue = try container.decodeIfPresent(String.self, forKey: .type) {
            // Map old "type" values to category-like values for display
            category = typeValue
        } else {
            category = "focus"  // Default fallback
        }

        estimatedMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedMinutes) ?? 5
        xpReward = try container.decodeIfPresent(Int.self, forKey: .xpReward) ?? 50
        isPremium = try container.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
        instructions = try container.decodeIfPresent([DBQuestInstruction].self, forKey: .instructions)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(category, forKey: .category)
        try container.encode(estimatedMinutes, forKey: .estimatedMinutes)
        try container.encode(xpReward, forKey: .xpReward)
        try container.encode(isPremium, forKey: .isPremium)
        try container.encodeIfPresent(instructions, forKey: .instructions)
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
                QuestInstruction(step: 1, text: "Find a comfortable seated position", durationSeconds: 30),
                QuestInstruction(step: 2, text: "Close your eyes and take 3 deep breaths", durationSeconds: 30),
                QuestInstruction(step: 3, text: "Focus your attention on the present moment", durationSeconds: 60),
                QuestInstruction(step: 4, text: "Scan through your body, noticing sensations", durationSeconds: 150),
                QuestInstruction(step: 5, text: "Gently bring your awareness back when you're ready", durationSeconds: 30)
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

    /// Convert DB model to app's QuestTemplate model
    func toQuestTemplate() -> QuestTemplate {
        // Map category string to QuestType, with fallback mapping
        let questType = mapCategoryToQuestType(category)

        return QuestTemplate(
            id: id.uuidString,
            type: questType,
            title: title,
            description: description,
            estimatedMinutes: estimatedMinutes,
            difficulty: "medium",  // Default, as DB may not have this
            tags: [],  // Default, as DB may not have this
            instructions: defaultInstructions(),
            category: questType
        )
    }

    /// Map database category values to QuestType enum
    private func mapCategoryToQuestType(_ category: String) -> QuestType {
        switch category.lowercased() {
        case "mindfulness", "breathing", "focus":
            return .breathing
        case "physical", "walk", "stretch":
            return .walk
        case "creative", "journal":
            return .journal
        case "gratitude":
            return .gratitude
        case "reflection":
            return .focus
        case "social":
            return .journal  // Map social to journal as closest match
        default:
            return .focus  // Default fallback
        }
    }
}

// Note: DBUserQuest removed - quests now use RPC functions (assign_daily_quest, complete_quest)
// and DBQuestWithTemplate struct for fetching active quests with template data

/// Quick variant from quest_quick_variants table
struct DBQuestQuickVariant: Codable {
    let id: UUID
    let parentTemplateId: UUID
    let title: String
    let description: String
    let steps: [DBQuestInstruction]?
    let estimatedMinutes: Int
    let xpMultiplier: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case parentTemplateId = "parent_template_id"
        case title, description, steps
        case estimatedMinutes = "estimated_minutes"
        case xpMultiplier = "xp_multiplier"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        parentTemplateId = try container.decode(UUID.self, forKey: .parentTemplateId)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        steps = try container.decodeIfPresent([DBQuestInstruction].self, forKey: .steps)
        estimatedMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedMinutes) ?? 3
        xpMultiplier = try container.decodeIfPresent(Double.self, forKey: .xpMultiplier)
    }

    func toQuestQuickVariant() -> QuestQuickVariant {
        QuestQuickVariant(
            id: id,
            parentTemplateId: parentTemplateId,
            title: title,
            description: description,
            steps: steps?.map { QuestInstruction(step: $0.step, text: $0.text, durationSeconds: nil) } ?? [],
            estimatedMinutes: estimatedMinutes,
            xpMultiplier: xpMultiplier ?? 0.5
        )
    }
}

struct DBExerciseInstruction: Codable {
    let step: Int
    let text: String
}

/// Exercise row matching actual schema (duration_seconds, premium_only)
struct DBExercise: Codable {
    let id: UUID
    let title: String
    let description: String
    let type: String
    let durationSeconds: Int  // Schema uses duration_seconds, not duration_minutes
    let contentKind: String
    let contentText: String?
    let audioUrl: String?
    let premiumOnly: Bool  // Schema uses premium_only, not is_premium
    let instructions: [DBExerciseInstruction]?

    // Credibility fields (from later migration)
    let evidenceBasis: String?
    let therapistReviewed: Bool?
    let reviewDate: String?
    let methodologyNote: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, type, instructions
        case durationSeconds = "duration_seconds"
        case contentKind = "content_kind"
        case contentText = "content_text"
        case audioUrl = "audio_url"
        case premiumOnly = "premium_only"
        case evidenceBasis = "evidence_basis"
        case therapistReviewed = "therapist_reviewed"
        case reviewDate = "review_date"
        case methodologyNote = "methodology_note"
    }

    /// Convenience computed property for duration in minutes (for UI display)
    var durationMinutes: Int {
        durationSeconds / 60
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
    let kind: String
    let moodEmoji: String?
    let bodyText: String?
    let localDate: String
    let createdAt: Date?
    let postType: String

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case userId = "user_id"
        case kind
        case moodEmoji = "mood_emoji"
        case bodyText = "body_text"
        case localDate = "local_date"
        case createdAt = "created_at"
        case postType = "post_type"
    }
}

struct DBCircleCheckinWithProfile: Codable {
    let id: UUID?
    let circleId: UUID
    let userId: UUID
    let kind: String?
    let moodEmoji: String?
    let bodyText: String?
    let localDate: String?
    let createdAt: Date?
    let postType: String?
    let profiles: DBMemberProfile?

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case userId = "user_id"
        case kind
        case moodEmoji = "mood_emoji"
        case bodyText = "body_text"
        case localDate = "local_date"
        case createdAt = "created_at"
        case postType = "post_type"
        case profiles
    }
}

// DBBadge moved to AchievementModels.swift (more comprehensive version)

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

// MARK: - Proactive Intelligence Database Models

/// User engagement state from `user_engagement_states` table
struct DBUserEngagementState: Codable {
    let userId: UUID
    let currentState: String
    let stateStartedAt: Date?
    let lastActivityAt: Date?
    let lastProactiveAt: Date?
    let proactiveMessageCount: Int?
    let proactiveEngageCount: Int?
    let proactiveIgnoreCount: Int?
    let moodDeclineDetected: Bool?
    let consecutiveLowMoodDays: Int?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case currentState = "current_state"
        case stateStartedAt = "state_started_at"
        case lastActivityAt = "last_activity_at"
        case lastProactiveAt = "last_proactive_at"
        case proactiveMessageCount = "proactive_message_count"
        case proactiveEngageCount = "proactive_engage_count"
        case proactiveIgnoreCount = "proactive_ignore_count"
        case moodDeclineDetected = "mood_decline_detected"
        case consecutiveLowMoodDays = "consecutive_low_mood_days"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toModel() -> UserEngagementState {
        UserEngagementState(
            id: userId.uuidString,
            userId: userId.uuidString,
            currentState: EngagementState(rawValue: currentState) ?? .active,
            stateStartedAt: stateStartedAt ?? Date(),
            lastActivityAt: lastActivityAt ?? Date(),
            lastProactiveAt: lastProactiveAt,
            proactiveMessageCount: proactiveMessageCount ?? 0,
            proactiveEngageCount: proactiveEngageCount ?? 0,
            proactiveIgnoreCount: proactiveIgnoreCount ?? 0,
            moodDeclineDetected: moodDeclineDetected ?? false,
            consecutiveLowMoodDays: consecutiveLowMoodDays ?? 0,
            updatedAt: updatedAt ?? Date()
        )
    }
}

/// User pattern from `user_patterns` table
struct DBUserPattern: Codable {
    let id: UUID
    let userId: UUID
    let patternType: String
    let patternKey: String
    let patternData: [String: AnyCodable]?
    let confidence: Double
    let firstDetectedAt: Date?
    let lastConfirmedAt: Date?
    let timesSurfaced: Int?
    let userAcknowledged: Bool?
    let isActive: Bool?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case patternType = "pattern_type"
        case patternKey = "pattern_key"
        case patternData = "pattern_data"
        case confidence
        case firstDetectedAt = "first_detected_at"
        case lastConfirmedAt = "last_confirmed_at"
        case timesSurfaced = "times_surfaced"
        case userAcknowledged = "user_acknowledged"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toModel() -> UserPattern {
        UserPattern(
            id: id.uuidString,
            userId: userId.uuidString,
            patternType: PatternType(rawValue: patternType) ?? .dayOfWeek,
            patternKey: patternKey,
            patternData: patternData ?? [:],
            confidence: confidence,
            firstDetectedAt: firstDetectedAt ?? Date(),
            lastConfirmedAt: lastConfirmedAt ?? Date(),
            timesSurfaced: timesSurfaced ?? 0,
            userAcknowledged: userAcknowledged ?? false,
            isActive: isActive ?? true,
            createdAt: createdAt ?? Date()
        )
    }
}

/// Proactive message from `proactive_messages` table
struct DBProactiveMessage: Codable {
    let id: UUID
    let userId: UUID
    let triggerType: String
    let messageContent: String
    let deliveryChannel: String?
    let scheduledFor: Date?
    let sentAt: Date?
    let readAt: Date?
    let engagedAt: Date?
    let status: String?
    let metadata: [String: AnyCodable]?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case triggerType = "trigger_type"
        case messageContent = "message_content"
        case deliveryChannel = "delivery_channel"
        case scheduledFor = "scheduled_for"
        case sentAt = "sent_at"
        case readAt = "read_at"
        case engagedAt = "engaged_at"
        case status
        case metadata
        case createdAt = "created_at"
    }

    func toModel() -> ProactiveMessage {
        ProactiveMessage(
            id: id.uuidString,
            userId: userId.uuidString,
            triggerType: ProactiveTriggerType(rawValue: triggerType) ?? .reengagement,
            messageContent: messageContent,
            deliveryChannel: ProactiveDeliveryChannel(rawValue: deliveryChannel ?? "in_app") ?? .inApp,
            scheduledFor: scheduledFor ?? Date(),
            sentAt: sentAt,
            readAt: readAt,
            engagedAt: engagedAt,
            status: ProactiveMessageStatus(rawValue: status ?? "scheduled") ?? .scheduled,
            metadata: metadata,
            createdAt: createdAt ?? Date()
        )
    }
}

/// Proactive settings (partial view of user_settings for proactive fields)
struct DBProactiveSettings: Codable {
    let proactiveEnabled: Bool?
    let proactiveMaxDaily: Int?
    let proactiveTypesEnabled: [String]?
    let calendarIntegrationEnabled: Bool?
    let weatherInsightsEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case proactiveEnabled = "proactive_enabled"
        case proactiveMaxDaily = "proactive_max_daily"
        case proactiveTypesEnabled = "proactive_types_enabled"
        case calendarIntegrationEnabled = "calendar_integration_enabled"
        case weatherInsightsEnabled = "weather_insights_enabled"
    }

    func toModel() -> ProactiveSettings {
        let enabledTypes: [ProactiveTriggerType] = (proactiveTypesEnabled ?? []).compactMap {
            ProactiveTriggerType(rawValue: $0)
        }
        return ProactiveSettings(
            proactiveEnabled: proactiveEnabled ?? true,
            proactiveMaxDaily: proactiveMaxDaily ?? 2,
            proactiveTypesEnabled: enabledTypes.isEmpty ? ProactiveTriggerType.allCases : enabledTypes,
            calendarIntegrationEnabled: calendarIntegrationEnabled ?? false,
            weatherInsightsEnabled: weatherInsightsEnabled ?? false
        )
    }
}

// MARK: - Creative Expression Database Models

/// Creative work from `creative_works` table
struct DBCreativeWork: Codable {
    let id: UUID
    let userId: UUID
    let workType: String
    let title: String?
    let description: String?
    let storagePath: String?
    let generationPrompt: String?
    let artStyle: String?
    let generationModel: String?
    let generationParams: [String: AnyCodable]?
    let durationSeconds: Int?
    let transcription: String?
    let transcriptionStatus: String?
    let canvasData: [String: AnyCodable]?
    let moodScore: Int?
    let moodTags: [String]?
    let emotionsDetected: [String: AnyCodable]?
    let isFavorite: Bool
    let isSharedToCircle: Bool
    let circlePostId: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case workType = "work_type"
        case title, description
        case storagePath = "storage_path"
        case generationPrompt = "generation_prompt"
        case artStyle = "art_style"
        case generationModel = "generation_model"
        case generationParams = "generation_params"
        case durationSeconds = "duration_seconds"
        case transcription
        case transcriptionStatus = "transcription_status"
        case canvasData = "canvas_data"
        case moodScore = "mood_score"
        case moodTags = "mood_tags"
        case emotionsDetected = "emotions_detected"
        case isFavorite = "is_favorite"
        case isSharedToCircle = "is_shared_to_circle"
        case circlePostId = "circle_post_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toModel() -> CreativeWork {
        CreativeWork(
            id: id.uuidString,
            userId: userId.uuidString,
            workType: CreativeWorkType(rawValue: workType) ?? .aiArt,
            title: title,
            description: description,
            storagePath: storagePath,
            generationPrompt: generationPrompt,
            artStyle: artStyle != nil ? ArtStyle(rawValue: artStyle!) : nil,
            durationSeconds: durationSeconds,
            transcription: transcription,
            transcriptionStatus: transcriptionStatus != nil ? TranscriptionStatus(rawValue: transcriptionStatus!) : nil,
            moodScore: moodScore,
            moodTags: moodTags,
            isFavorite: isFavorite,
            isSharedToCircle: isSharedToCircle,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

/// Voice journal analysis from `voice_journal_analysis` table
struct DBVoiceJournalAnalysis: Codable {
    let id: UUID
    let creativeWorkId: UUID
    let fullTranscription: String?
    let wordTimestamps: [String: AnyCodable]?
    let overallSentiment: Double?
    let emotions: [String: AnyCodable]?
    let toneAnalysis: [String: AnyCodable]?
    let keyThemes: [String]?
    let keyQuotes: [String]?
    let aiSummary: String?
    let reflectionPrompts: [String]?
    let analysisModel: String?
    let processedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case creativeWorkId = "creative_work_id"
        case fullTranscription = "full_transcription"
        case wordTimestamps = "word_timestamps"
        case overallSentiment = "overall_sentiment"
        case emotions
        case toneAnalysis = "tone_analysis"
        case keyThemes = "key_themes"
        case keyQuotes = "key_quotes"
        case aiSummary = "ai_summary"
        case reflectionPrompts = "reflection_prompts"
        case analysisModel = "analysis_model"
        case processedAt = "processed_at"
        case createdAt = "created_at"
    }

    func toModel() -> VoiceJournalAnalysis {
        VoiceJournalAnalysis(
            id: id.uuidString,
            creativeWorkId: creativeWorkId.uuidString,
            fullTranscription: fullTranscription,
            overallSentiment: overallSentiment ?? 0,
            emotions: parseEmotions(emotions),
            toneAnalysis: parseToneAnalysis(toneAnalysis),
            keyThemes: keyThemes ?? [],
            keyQuotes: keyQuotes ?? [],
            aiSummary: aiSummary,
            reflectionPrompts: reflectionPrompts ?? [],
            processedAt: processedAt
        )
    }

    private func parseEmotions(_ data: [String: AnyCodable]?) -> EmotionScores {
        guard let data = data else {
            return EmotionScores()
        }
        return EmotionScores(
            joy: (data["joy"]?.value as? Double) ?? 0,
            sadness: (data["sadness"]?.value as? Double) ?? 0,
            anger: (data["anger"]?.value as? Double) ?? 0,
            fear: (data["fear"]?.value as? Double) ?? 0,
            surprise: (data["surprise"]?.value as? Double) ?? 0,
            trust: (data["trust"]?.value as? Double) ?? 0,
            anticipation: (data["anticipation"]?.value as? Double) ?? 0,
            disgust: (data["disgust"]?.value as? Double) ?? 0
        )
    }

    private func parseToneAnalysis(_ data: [String: AnyCodable]?) -> ToneAnalysis {
        guard let data = data else {
            return ToneAnalysis()
        }
        return ToneAnalysis(
            energy: ToneLevel(rawValue: (data["energy"]?.value as? String) ?? "medium") ?? .medium,
            pace: TonePace(rawValue: (data["pace"]?.value as? String) ?? "moderate") ?? .moderate,
            confidence: ToneConfidence(rawValue: (data["confidence"]?.value as? String) ?? "neutral") ?? .neutral,
            emotionalIntensity: ToneIntensity(rawValue: (data["emotional_intensity"]?.value as? String) ?? "moderate") ?? .moderate
        )
    }
}

/// Creative exercise from `creative_exercises` table
struct DBCreativeExercise: Codable {
    let id: UUID
    let title: String
    let description: String
    let instructions: String
    let exerciseType: String
    let category: String
    let difficulty: String
    let estimatedMinutes: Int
    let promptImageUrl: String?
    let exampleWorks: [String: AnyCodable]?
    let isPremium: Bool
    let isActive: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, description, instructions, category, difficulty
        case exerciseType = "exercise_type"
        case estimatedMinutes = "estimated_minutes"
        case promptImageUrl = "prompt_image_url"
        case exampleWorks = "example_works"
        case isPremium = "is_premium"
        case isActive = "is_active"
        case createdAt = "created_at"
    }

    func toModel() -> CreativeExercise {
        CreativeExercise(
            id: id.uuidString,
            title: title,
            description: description,
            instructions: instructions,
            exerciseType: CreativeExerciseType(rawValue: exerciseType) ?? .drawing,
            category: CreativeExerciseCategory(rawValue: category) ?? .emotionProcessing,
            difficulty: ExerciseDifficulty(rawValue: difficulty) ?? .beginner,
            estimatedMinutes: estimatedMinutes,
            promptImageUrl: promptImageUrl,
            isPremium: isPremium
        )
    }
}

/// Drawing session from `drawing_sessions` table
struct DBDrawingSession: Codable {
    let id: UUID
    let userId: UUID
    let creativeWorkId: UUID?
    let canvasWidth: Int
    let canvasHeight: Int
    let backgroundColor: String?
    let strokes: [String: AnyCodable]
    let durationSeconds: Int?
    let strokeCount: Int?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case creativeWorkId = "creative_work_id"
        case canvasWidth = "canvas_width"
        case canvasHeight = "canvas_height"
        case backgroundColor = "background_color"
        case strokes
        case durationSeconds = "duration_seconds"
        case strokeCount = "stroke_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Creative quota usage from `creative_quota_usage` table
struct DBCreativeQuotaUsage: Codable {
    let id: UUID
    let userId: UUID
    let date: String
    let aiArtCount: Int
    let voiceMinutesUsed: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case aiArtCount = "ai_art_count"
        case voiceMinutesUsed = "voice_minutes_used"
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
