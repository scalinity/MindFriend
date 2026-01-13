import Foundation

// MARK: - User

struct UserProfile: Codable, Identifiable, Equatable {
    let id: String
    let handle: String
    let displayName: String
    let email: String?
    let timezone: String
    let createdAt: Date
    var settings: UserSettings
    var stats: UserStats
    var entitlements: Entitlements
    var badges: [Badge]
}

struct UserSettings: Codable, Equatable {
    var dailyQuestTimeLocal: String
    var quietHoursStartLocal: String?
    var quietHoursEndLocal: String?
    var remindersEnabled: Bool
    var nudgeAfterDaysInactive: Int
    var shareMoodInCircles: Bool
    var aiTone: AITone
    var privacyMode: PrivacyMode
}

struct UserStats: Codable, Equatable {
    var currentStreakDays: Int
    var longestStreakDays: Int
    var totalQuestsCompleted: Int
    var totalExercisesCompleted: Int
}

struct Entitlements: Codable, Equatable {
    let tier: Tier
    let dailyAiQuota: Int
    var dailyAiUsed: Int

    var remaining: Int { dailyAiQuota - dailyAiUsed }
    var isQuotaExceeded: Bool { dailyAiUsed >= dailyAiQuota }

    static let free = Entitlements(tier: .free, dailyAiQuota: 20, dailyAiUsed: 0)
    static let premium = Entitlements(tier: .premium, dailyAiQuota: 9999, dailyAiUsed: 0)
}

enum Tier: String, Codable {
    case free
    case premium
}

enum AITone: String, Codable, CaseIterable {
    case friendly
    case professional
    case motivational
    case gentle

    var displayName: String {
        switch self {
        case .friendly: return "Friendly"
        case .professional: return "Professional"
        case .motivational: return "Motivational"
        case .gentle: return "Gentle"
        }
    }

    var description: String {
        switch self {
        case .friendly: return "Warm and casual with light humor"
        case .professional: return "Calm and measured tone"
        case .motivational: return "Enthusiastic and empowering"
        case .gentle: return "Extra soft and nurturing"
        }
    }
}

enum PrivacyMode: String, Codable, CaseIterable {
    case standard
    case enhanced

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .enhanced: return "Enhanced"
        }
    }
}

struct Badge: Codable, Identifiable, Equatable {
    let id: String
    let code: String
    let title: String
    let description: String
    let earnedAt: Date
    let iconName: String?

    var icon: String {
        // Use iconName from API if available, otherwise fall back to code-based lookup
        if let iconName = iconName, !iconName.isEmpty {
            return iconName
        }
        switch code {
        case "first_quest", "first_steps": return "star.fill"
        case "first_chat", "opening_up": return "bubble.left.fill"
        case "first_mood", "mood_tracker": return "chart.bar.fill"
        case "first_exercise", "moving_forward": return "figure.walk"
        case "profile_complete", "all_set": return "person.crop.circle.badge.checkmark"
        case "quests_10", "consistent": return "checkmark.circle.fill"
        case "quests_25", "committed": return "checkmark.seal.fill"
        case "quests_50", "mindful_master": return "brain.head.profile"
        case "quests_100", "century_seeker": return "star.circle.fill"
        case "quests_250", "wellness_warrior": return "shield.fill"
        case "quests_500", "enlightened": return "sun.max.fill"
        case "streak_3": return "flame"
        case "streak_7", "week_warrior": return "flame.fill"
        case "streak_14", "fortnight_focus": return "flame.circle"
        case "streak_30", "dedicated", "monthly_master": return "calendar"
        case "streak_60", "two_month_titan": return "calendar.badge.clock"
        case "streak_100", "century_club": return "trophy.fill"
        case "streak_365", "year_of_growth": return "crown.fill"
        case "exercises_5", "exercise_explorer": return "figure.walk"
        case "exercises_25", "active_mind": return "figure.mind.and.body"
        case "exercises_50", "body_and_soul": return "heart.circle.fill"
        case "exercises_100", "wellness_champion": return "medal.fill"
        case "all_exercise_types", "well_rounded": return "circle.grid.3x3.fill"
        case "circle_join", "circle_joiner": return "person.2.fill"
        case "circle_create", "circle_creator": return "person.3.fill"
        case "checkin_10", "community_spirit": return "hand.wave.fill"
        case "invite_friend", "spreading_wellness": return "gift.fill"
        case "night_owl": return "moon.fill"
        case "early_bird": return "sunrise.fill"
        case "perfect_week": return "sparkles"
        case "mood_streak_7", "mood_master": return "chart.line.uptrend.xyaxis"
        case "comeback": return "arrow.counterclockwise"
        default: return "medal.fill"
        }
    }
}

// MARK: - Quest

struct Quest: Codable, Identifiable, Equatable {
    let id: String
    let localDate: String
    var status: QuestStatus
    let assignedAt: Date
    var completedAt: Date?
    let template: QuestTemplate
}

struct QuestTemplate: Codable, Equatable {
    let id: String
    let type: QuestType
    let title: String
    let description: String
    let estimatedMinutes: Int
    let difficulty: String
    let tags: [String]
    let instructions: [QuestInstruction]
}

struct QuestInstruction: Codable, Equatable {
    let step: Int
    let text: String
    let durationSeconds: Int?
}

enum QuestType: String, Codable, CaseIterable {
    case breathing
    case walk
    case journal
    case focus
    case gratitude
    case stretch

    var icon: String {
        switch self {
        case .breathing: return "wind"
        case .walk: return "figure.walk"
        case .journal: return "book.fill"
        case .focus: return "target"
        case .gratitude: return "heart.fill"
        case .stretch: return "figure.flexibility"
        }
    }

    var color: String {
        switch self {
        case .breathing: return "blue"
        case .walk: return "green"
        case .journal: return "purple"
        case .focus: return "orange"
        case .gratitude: return "pink"
        case .stretch: return "teal"
        }
    }
}

enum QuestStatus: String, Codable {
    case assigned
    case completed
    case skipped
}

struct QuestCompletion: Codable {
    let questId: String
    let status: QuestStatus
    let completedAt: Date?
    let streakDays: Int
    let badgesEarned: [Badge]
}

// MARK: - Mood

struct MoodEntry: Codable, Identifiable, Equatable {
    let id: String
    let localDate: String
    var moodScore: Int
    var anxietyScore: Int?
    var energyScore: Int?
    var note: String?
    let source: MoodSource
    let createdAt: Date
}

enum MoodSource: String, Codable {
    case manual
    case postQuest = "post_quest"
    case postExercise = "post_exercise"
}

// MARK: - Chat

struct Conversation: Codable, Identifiable, Equatable {
    let id: String
    var title: String?
    let status: ConversationStatus
    let createdAt: Date
    let updatedAt: Date
    var lastMessage: MessagePreview?
}

struct MessagePreview: Codable, Equatable {
    let role: MessageRole
    let content: String
    let createdAt: Date
}

struct Message: Codable, Identifiable, Equatable {
    let id: String
    let role: MessageRole
    let content: String
    let createdAt: Date
    let blocked: Bool
}

enum MessageRole: String, Codable {
    case user
    case assistant
}

enum ConversationStatus: String, Codable {
    case active
    case archived
}

struct SendMessageResponse: Codable {
    let userMessage: Message
    let assistantMessage: Message
    let quotaRemaining: Int
    let crisisDetected: Bool?
}

// MARK: - Circle

struct FriendCircle: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String?
    let inviteCode: String
    let maxMembers: Int
    let memberCount: Int
    let role: CircleRole
    let joinedAt: Date
}

struct CircleMember: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let displayName: String
    let role: CircleRole
    let joinedAt: Date
}

enum CircleRole: String, Codable {
    case owner
    case member
}

struct CirclePost: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let userDisplayName: String
    let kind: PostKind
    let moodEmoji: String?
    let bodyText: String?
    let localDate: String
    let createdAt: Date
}

enum PostKind: String, Codable {
    case checkin
    case milestone
}

// MARK: - Exercise

struct Exercise: Codable, Identifiable, Equatable {
    let id: String
    let type: ExerciseType
    let title: String
    let description: String
    let durationSeconds: Int
    let contentKind: ContentKind
    let contentText: String?
    let audioUrl: String?
}

enum ExerciseType: String, Codable, CaseIterable {
    case breathing
    case meditation
    case grounding
    case journaling
    case movement

    var icon: String {
        switch self {
        case .breathing: return "wind"
        case .meditation: return "brain.head.profile"
        case .grounding: return "leaf.fill"
        case .journaling: return "pencil.and.scribble"
        case .movement: return "figure.walk"
        }
    }
}

enum ContentKind: String, Codable {
    case text
    case audio
    case guided
}

struct ExerciseSession: Codable, Identifiable {
    let id: String
    let exerciseId: String
    let startedAt: Date
    var endedAt: Date?
    var completed: Bool
    var rating: Int?
    var note: String?
}

// MARK: - Crisis Resources

struct CrisisResource: Codable, Identifiable {
    let id: String
    let country: String
    let countryCode: String
    let name: String
    let phone: String?
    let sms: String?
    let chat: String?
    let available: String
}

// MARK: - Auth

struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

struct AppleSignInRequest: Codable {
    let identityToken: String
    let authorizationCode: String
    let fullName: String?
    let email: String?
}

struct GoogleSignInRequest: Codable {
    let idToken: String
    let email: String?
    let fullName: String?
}

struct RefreshTokenRequest: Codable {
    let refreshToken: String
}
