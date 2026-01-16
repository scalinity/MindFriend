import Foundation
import SwiftUI

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
    var wellnessFocus: WellnessFocus?
    var onboardingCompletedAt: Date?

    /// Returns true if the user hasn't completed onboarding yet
    var needsOnboarding: Bool {
        onboardingCompletedAt == nil
    }

    /// Returns the user's highest priority premium badge (if any)
    var premiumBadge: Badge? {
        // Priority: family_champion > annual_achiever > premium_supporter
        if let familyBadge = badges.first(where: { $0.code == "family_champion" }) {
            return familyBadge
        }
        if let annualBadge = badges.first(where: { $0.code == "annual_achiever" }) {
            return annualBadge
        }
        return badges.first(where: { $0.code == "premium_supporter" })
    }

    /// Returns all premium badges the user has earned
    var premiumBadges: [Badge] {
        badges.filter { $0.isPremiumBadge }
    }
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

    // Smart notification preferences (optional for backwards compatibility)
    var notifyCircleActivity: Bool?
    var notifyHugs: Bool?
    var notifyChallenges: Bool?
    var notifyStreakRisk: Bool?
    var notifyWeeklySummary: Bool?
    var preferredNotifyHour: Int?
}

struct UserStats: Codable, Equatable {
    var currentStreakDays: Int
    var longestStreakDays: Int
    var totalQuestsCompleted: Int
    var totalExercisesCompleted: Int
    // XP & Level progression
    var xpTotal: Int
    var xpThisWeek: Int
    var level: Int
    var levelTitle: String
    var lastXpResetWeek: String?
    // Streak shield properties (added for streak recovery feature)
    var streakShieldsRemaining: Int?
    var streakShieldsMax: Int?
    var recoveryQuestAvailable: Bool?
    var recoveryQuestExpiresAt: Date?
    var streakBeforeBreak: Int?
    var recoveryAttemptsRemaining: Int?
    var recoveryAttemptsMax: Int?

    init(
        currentStreakDays: Int = 0,
        longestStreakDays: Int = 0,
        totalQuestsCompleted: Int = 0,
        totalExercisesCompleted: Int = 0,
        xpTotal: Int = 0,
        xpThisWeek: Int = 0,
        level: Int = 1,
        levelTitle: String = "Beginner",
        lastXpResetWeek: String? = nil,
        streakShieldsRemaining: Int? = 1,
        streakShieldsMax: Int? = 1,
        recoveryQuestAvailable: Bool? = false,
        recoveryQuestExpiresAt: Date? = nil,
        streakBeforeBreak: Int? = nil,
        recoveryAttemptsRemaining: Int? = 1,
        recoveryAttemptsMax: Int? = 1
    ) {
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
        self.totalQuestsCompleted = totalQuestsCompleted
        self.totalExercisesCompleted = totalExercisesCompleted
        self.xpTotal = xpTotal
        self.xpThisWeek = xpThisWeek
        self.level = level
        self.levelTitle = levelTitle
        self.lastXpResetWeek = lastXpResetWeek
        self.streakShieldsRemaining = streakShieldsRemaining
        self.streakShieldsMax = streakShieldsMax
        self.recoveryQuestAvailable = recoveryQuestAvailable
        self.recoveryQuestExpiresAt = recoveryQuestExpiresAt
        self.streakBeforeBreak = streakBeforeBreak
        self.recoveryAttemptsRemaining = recoveryAttemptsRemaining
        self.recoveryAttemptsMax = recoveryAttemptsMax
    }

    enum CodingKeys: String, CodingKey {
        case currentStreakDays = "current_streak_days"
        case longestStreakDays = "longest_streak_days"
        case totalQuestsCompleted = "total_quests_completed"
        case totalExercisesCompleted = "total_exercises_completed"
        case xpTotal = "xp_total"
        case xpThisWeek = "xp_this_week"
        case level
        case levelTitle = "level_title"
        case lastXpResetWeek = "last_xp_reset_week"
        case streakShieldsRemaining = "streak_shields_remaining"
        case streakShieldsMax = "streak_shields_max"
        case recoveryQuestAvailable = "recovery_quest_available"
        case recoveryQuestExpiresAt = "recovery_quest_expires_at"
        case streakBeforeBreak = "streak_before_break"
        case recoveryAttemptsRemaining = "recovery_attempts_remaining"
        case recoveryAttemptsMax = "recovery_attempts_max"
    }
}

// MARK: - Streak Shield Status

/// Represents the current state of a user's streak shields and recovery quest availability
struct StreakShieldStatus: Codable, Equatable {
    let shieldsRemaining: Int
    let shieldsMax: Int
    let shieldsResetAt: Date?
    let lastShieldUsedAt: Date?
    let recoveryQuestAvailable: Bool
    let recoveryQuestExpiresAt: Date?
    let streakBeforeBreak: Int?
    let recoveryAttemptsRemaining: Int
    let recoveryAttemptsMax: Int
    let currentStreak: Int

    /// Number of shields used this week
    var shieldsUsedThisWeek: Int {
        shieldsMax - shieldsRemaining
    }

    /// Whether user has any shields left
    var hasShieldsRemaining: Bool {
        shieldsRemaining > 0
    }

    /// Whether user can attempt recovery
    var canAttemptRecovery: Bool {
        recoveryQuestAvailable && recoveryAttemptsRemaining > 0
    }

    /// Time remaining until recovery expires
    var recoveryTimeRemaining: TimeInterval? {
        guard recoveryQuestAvailable, let expiresAt = recoveryQuestExpiresAt else { return nil }
        return expiresAt.timeIntervalSince(Date())
    }

    /// Formatted time until next shield reset
    var nextResetFormatted: String? {
        guard let resetAt = shieldsResetAt else { return nil }
        // Calculate next Monday at 05:00 UTC
        let calendar = Calendar.current
        let nextMonday = calendar.nextDate(
            after: resetAt,
            matching: DateComponents(hour: 5, minute: 0, weekday: 2),
            matchingPolicy: .nextTime
        ) ?? resetAt.addingTimeInterval(7 * 24 * 60 * 60)

        let days = calendar.dateComponents([.day], from: Date(), to: nextMonday).day ?? 0
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return "\(days) days"
    }

    enum CodingKeys: String, CodingKey {
        case shieldsRemaining = "shields_remaining"
        case shieldsMax = "shields_max"
        case shieldsResetAt = "shields_reset_at"
        case lastShieldUsedAt = "last_shield_used_at"
        case recoveryQuestAvailable = "recovery_quest_available"
        case recoveryQuestExpiresAt = "recovery_quest_expires_at"
        case streakBeforeBreak = "streak_before_break"
        case recoveryAttemptsRemaining = "recovery_attempts_remaining"
        case recoveryAttemptsMax = "recovery_attempts_max"
        case currentStreak = "current_streak"
    }
}

// MARK: - Recovery Quest

/// Status of a recovery quest attempt
enum RecoveryStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case completed
    case expired
    case failed
}

/// Represents a recovery quest attempt
struct RecoveryQuestAttempt: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let streakToRecover: Int
    let questTemplateId: String?
    let attemptNumber: Int
    let startedAt: Date
    var completedAt: Date?
    var expiredAt: Date?
    var status: RecoveryStatus

    /// Associated quest template (loaded separately)
    var questTemplate: QuestTemplate?

    /// Time remaining before attempt expires
    var timeRemaining: TimeInterval? {
        guard status == .pending || status == .inProgress else { return nil }
        guard let expiresAt = expiredAt else { return nil }
        return expiresAt.timeIntervalSince(Date())
    }

    /// Whether the attempt has expired
    var isExpired: Bool {
        guard let expiresAt = expiredAt else { return false }
        return Date() > expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case streakToRecover = "streak_to_recover"
        case questTemplateId = "quest_template_id"
        case attemptNumber = "attempt_number"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case expiredAt = "expired_at"
        case status
        case questTemplate = "quest_templates"
    }
}

/// Result from check_protection action
struct StreakProtectionResult: Codable {
    let success: Bool
    let streakProtected: Bool
    let newStreak: Int
    let shieldsRemaining: Int
    let shieldsMax: Int
    let recoveryAvailable: Bool
    let streakBeforeBreak: Int?
    let recoveryExpiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case success
        case streakProtected = "streak_protected"
        case newStreak = "new_streak"
        case shieldsRemaining = "shields_remaining"
        case shieldsMax = "shields_max"
        case recoveryAvailable = "recovery_available"
        case streakBeforeBreak = "streak_before_break"
        case recoveryExpiresAt = "recovery_expires_at"
    }
}

/// Result from start_recovery action
struct StartRecoveryResult: Codable {
    let success: Bool
    let attemptId: String?
    let quest: RecoveryQuestInfo?
    let error: String?

    struct RecoveryQuestInfo: Codable {
        let id: String
        let title: String
        let description: String
        let estimatedMinutes: Int
        let instructions: [String]?
    }
}

/// Result from complete_recovery action
struct CompleteRecoveryResult: Codable {
    let success: Bool
    let restoredStreak: Int?
    let error: String?
}

struct Entitlements: Codable, Equatable {
    let tier: Tier
    let dailyAiQuota: Int
    var dailyAiUsed: Int

    /// Remaining AI messages for the day. Premium users have unlimited (Int.max).
    var remaining: Int {
        if tier == .premium { return Int.max }
        return max(0, dailyAiQuota - dailyAiUsed)
    }

    /// Whether the user has exceeded their daily quota. Premium users never exceed.
    var isQuotaExceeded: Bool {
        if tier == .premium { return false }
        return dailyAiUsed >= dailyAiQuota
    }

    /// Whether the user is approaching their quota limit (for warning display)
    var isNearQuotaLimit: Bool {
        if tier == .premium { return false }
        return remaining <= 3 && remaining > 0
    }

    static let free = Entitlements(tier: .free, dailyAiQuota: 20, dailyAiUsed: 0)
    static let premium = Entitlements(tier: .premium, dailyAiQuota: 9999, dailyAiUsed: 0)
}

enum Tier: String, Codable {
    case free
    case premium
}

// MARK: - Voice Mode Models

/// Available Grok voice personalities
enum GrokVoice: String, CaseIterable, Identifiable, Codable {
    case ara = "ara"
    case rex = "rex"
    case sal = "sal"
    case eve = "eve"
    case leo = "leo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ara: return "Ara"
        case .rex: return "Rex"
        case .sal: return "Sal"
        case .eve: return "Eve"
        case .leo: return "Leo"
        }
    }

    var description: String {
        switch self {
        case .ara: return "Warm & conversational"
        case .rex: return "Professional & clear"
        case .sal: return "Calm & balanced"
        case .eve: return "Energetic & upbeat"
        case .leo: return "Authoritative & strong"
        }
    }

    var gender: String {
        switch self {
        case .ara, .eve: return "Female"
        case .rex, .leo: return "Male"
        case .sal: return "Neutral"
        }
    }
}

/// Response from voice-token Edge Function
struct VoiceTokenResponse: Codable {
    let token: String
    let expiresAt: String
    let minutesRemaining: Double
    let voice: String
    let isPremium: Bool
    let availableVoices: [String]
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
        case minutesRemaining = "minutes_remaining"
        case voice
        case isPremium = "is_premium"
        case availableVoices = "available_voices"
        case sessionId = "session_id"
    }

    var grokVoice: GrokVoice {
        GrokVoice(rawValue: voice) ?? .ara
    }

    var grokAvailableVoices: [GrokVoice] {
        availableVoices.compactMap { GrokVoice(rawValue: $0) }
    }
}

/// Voice error types
enum VoiceError: LocalizedError {
    case notAuthorized
    case notConnected
    case connectionFailed(String)
    case connectionTimeout
    case quotaExceeded
    case premiumRequired
    case tokenGenerationFailed
    case audioSessionFailed(String)
    case microphonePermissionDenied
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Voice mode is not authorized. Please check your settings."
        case .notConnected:
            return "Voice service is not connected. Please try again."
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .connectionTimeout:
            return "Connection timed out. Please check your network and try again."
        case .quotaExceeded:
            return "You've used all your voice minutes this month. Upgrade to Premium for unlimited voice conversations."
        case .premiumRequired:
            return "Premium subscription required to use additional voices."
        case .tokenGenerationFailed:
            return "Failed to start voice session. Please try again."
        case .audioSessionFailed(let reason):
            return "Audio error: \(reason)"
        case .microphonePermissionDenied:
            return "Microphone access denied. Please enable it in Settings to use voice mode."
        case .networkUnavailable:
            return "No network connection. Voice mode requires an internet connection."
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .quotaExceeded, .premiumRequired, .microphonePermissionDenied:
            return false
        default:
            return true
        }
    }
}

/// Voice settings stored in database
struct VoiceSettings: Codable {
    let id: UUID
    let userId: UUID
    var voiceEnabled: Bool
    var preferredVoice: String
    var autoPlayResponses: Bool
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case voiceEnabled = "voice_enabled"
        case preferredVoice = "preferred_voice"
        case autoPlayResponses = "auto_play_responses"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Subscription & Family Plans

enum PlanType: String, Codable, CaseIterable {
    case individual
    case couples
    case family

    var displayName: String {
        switch self {
        case .individual: return "Individual"
        case .couples: return "Couples"
        case .family: return "Family"
        }
    }

    var maxSeats: Int {
        switch self {
        case .individual: return 1
        case .couples: return 2
        case .family: return 6
        }
    }

    var description: String {
        switch self {
        case .individual: return "Just for you"
        case .couples: return "For 2 people"
        case .family: return "Up to 6 people"
        }
    }

    var isFamilyPlan: Bool {
        self == .family || self == .couples
    }
}

enum BillingPeriod: String, Codable, CaseIterable {
    case monthly
    case annual

    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .annual: return "Annual"
        }
    }

    var savingsPercent: Int? {
        switch self {
        case .monthly: return nil
        case .annual: return 50
        }
    }
}

struct Subscription: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let productId: String
    let originalTransactionId: String?  // StoreKit transaction ID for validation
    let status: SubscriptionStatus
    let planType: PlanType
    let billingPeriod: BillingPeriod
    let familyId: String?
    let isFamilyAdmin: Bool
    let seatsUsed: Int
    let seatsTotal: Int
    let expiresAt: Date?
    let createdAt: Date
    let updatedAt: Date

    var isActive: Bool {
        status == .active || status == .gracePeriod
    }

    var isFamily: Bool {
        planType == .couples || planType == .family
    }

    var availableSeats: Int {
        seatsTotal - seatsUsed
    }

    // CodingKeys for snake_case database column mapping
    // Note: Consider using JSONDecoder.KeyDecodingStrategy.convertFromSnakeCase
    // at the Supabase client level to reduce boilerplate
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case productId = "product_id"
        case originalTransactionId = "original_transaction_id"
        case status
        case planType = "plan_type"
        case billingPeriod = "billing_period"
        case familyId = "family_id"
        case isFamilyAdmin = "is_family_admin"
        case seatsUsed = "seats_used"
        case seatsTotal = "seats_total"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum SubscriptionStatus: String, Codable {
    case active
    case expired
    case cancelled
    case gracePeriod = "grace_period"
}

struct FamilyGroup: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    let adminUserId: String
    let circleId: String?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case adminUserId = "admin_user_id"
        case circleId = "circle_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct FamilyMember: Codable, Identifiable, Equatable {
    let id: String
    let familyId: String
    let userId: String
    let invitedEmail: String?
    var status: MemberStatus
    let invitedAt: Date
    var joinedAt: Date?
    var removedAt: Date?

    // Joined profile data (optional from joined query)
    var displayName: String?
    var handle: String?

    var isActive: Bool {
        status == .active
    }

    enum MemberStatus: String, Codable {
        case pending
        case active
        case removed
    }

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case userId = "user_id"
        case invitedEmail = "invited_email"
        case status
        case invitedAt = "invited_at"
        case joinedAt = "joined_at"
        case removedAt = "removed_at"
        case displayName = "display_name"
        case handle
    }
}

struct FamilyInvitation: Codable, Identifiable, Equatable {
    let id: String
    let familyId: String
    let email: String
    let inviteCode: String
    let expiresAt: Date
    var acceptedAt: Date?
    let createdAt: Date

    var isExpired: Bool {
        Date() > expiresAt
    }

    var isPending: Bool {
        acceptedAt == nil && !isExpired
    }

    var daysUntilExpiry: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: expiresAt).day ?? 0)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case email
        case inviteCode = "invite_code"
        case expiresAt = "expires_at"
        case acceptedAt = "accepted_at"
        case createdAt = "created_at"
    }
}

/// Response from send-family-invite Edge Function
struct SendInviteResponse: Codable {
    let success: Bool
    let inviteCode: String?
    let expiresAt: String?
    let emailSent: Bool?
    let message: String

    enum CodingKeys: String, CodingKey {
        case success
        case inviteCode = "invite_code"
        case expiresAt = "expires_at"
        case emailSent = "email_sent"
        case message
    }
}

/// Response from accept-family-invite Edge Function
struct AcceptInviteResponse: Codable {
    let success: Bool
    let familyId: String?
    let circleId: String?
    let message: String

    enum CodingKeys: String, CodingKey {
        case success
        case familyId = "family_id"
        case circleId = "circle_id"
        case message
    }
}

/// Response from verify-purchase Edge Function (extended)
struct VerifyPurchaseResponse: Codable {
    let valid: Bool
    let productId: String?
    let planType: String?
    let billingPeriod: String?
    let familyId: String?
    let circleId: String?
    let expiresAt: String?
    let message: String?
    let mock: Bool?

    enum CodingKeys: String, CodingKey {
        case valid
        case productId = "productId"
        case planType = "planType"
        case billingPeriod = "billingPeriod"
        case familyId = "familyId"
        case circleId = "circleId"
        case expiresAt = "expiresAt"
        case message
        case mock
    }
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

// MARK: - Wellness Focus

enum WellnessFocus: String, Codable, CaseIterable {
    case anxiety
    case stress
    case loneliness
    case productivity
    case general

    var displayTitle: String {
        switch self {
        case .anxiety: return "Managing anxiety"
        case .stress: return "Reducing stress"
        case .loneliness: return "Feeling less lonely"
        case .productivity: return "Staying productive"
        case .general: return "General wellness"
        }
    }

    var emoji: String {
        switch self {
        case .anxiety: return "😰"
        case .stress: return "😓"
        case .loneliness: return "💙"
        case .productivity: return "🎯"
        case .general: return "✨"
        }
    }

    var aiGreeting: String {
        switch self {
        case .anxiety:
            return "I hear you - anxiety can feel overwhelming. I'm here to help you find moments of calm. What's been weighing on you lately?"
        case .stress:
            return "Life can pile up fast. I'm here to help you decompress and find some balance. What's been stressing you out most?"
        case .loneliness:
            return "It takes courage to reach out. I'm glad you're here - you don't have to go through things alone. How are you feeling today?"
        case .productivity:
            return "I love that you're investing in yourself! Mental clarity is key to getting things done. What would you like to focus on?"
        case .general:
            return "Hey there! I'm your AI wellness buddy. I'm here to help however you need - whether that's venting, building habits, or just checking in. What's on your mind?"
        }
    }

    /// Selectable options for the onboarding quiz (excludes .general which is the skip default)
    static var selectableOptions: [WellnessFocus] {
        [.anxiety, .stress, .loneliness, .productivity]
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
        // Seasonal event badges
        case "gratitude_champion": return "heart.text.square.fill"
        case "mindful_start": return "sparkles"
        case "spring_renewal": return "leaf.fill"
        // Premium badges
        case "premium_supporter": return "star.fill"
        case "annual_achiever": return "star.circle.fill"
        case "family_champion": return "person.3.fill"
        default: return "medal.fill"
        }
    }

    /// Whether this is a premium subscription badge
    var isPremiumBadge: Bool {
        ["premium_supporter", "annual_achiever", "family_champion"].contains(code)
    }

    /// Color for the badge (premium badges get special colors)
    var badgeColor: String {
        switch code {
        case "premium_supporter": return "yellow"
        case "annual_achiever": return "purple"
        case "family_champion": return "blue"
        default: return "yellow"
        }
    }
}

// MARK: - Quest

struct Quest: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let localDate: String
    var status: QuestStatus
    let assignedAt: Date
    var completedAt: Date?
    let template: QuestTemplate

    // Quest Choice feature properties
    var isQuickVariant: Bool = false
    var xpMultiplier: Double = 1.0

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
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
    var category: QuestType?  // Quest Choice feature: category for preference tracking

    enum CodingKeys: String, CodingKey {
        case id, type, title, description, estimatedMinutes, difficulty, tags, instructions, category
    }

    init(id: String, type: QuestType, title: String, description: String, estimatedMinutes: Int, difficulty: String, tags: [String], instructions: [QuestInstruction], category: QuestType? = nil) {
        self.id = id
        self.type = type
        self.title = title
        self.description = description
        self.estimatedMinutes = estimatedMinutes
        self.difficulty = difficulty
        self.tags = tags
        self.instructions = instructions
        self.category = category ?? type  // Default to type if category not specified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(QuestType.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        estimatedMinutes = try container.decode(Int.self, forKey: .estimatedMinutes)
        difficulty = try container.decode(String.self, forKey: .difficulty)
        tags = try container.decode([String].self, forKey: .tags)
        instructions = try container.decode([QuestInstruction].self, forKey: .instructions)
        category = try container.decodeIfPresent(QuestType.self, forKey: .category) ?? type
    }
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

    /// Maps quest types to their corresponding event activity types (ExerciseType raw values)
    var eventActivityType: String? {
        switch self {
        case .breathing: return "breathing"
        case .walk, .stretch: return "movement"
        case .journal, .gratitude: return "journaling"
        case .focus: return "meditation"
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

// MARK: - Quest Alternatives (Quest Choice Feature)

/// Represents the daily quest alternatives offered to a user
struct QuestAlternatives: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let questDate: Date
    let primaryQuestId: UUID
    let quickVariantId: UUID?
    let altQuestId: UUID?
    let rerollsUsed: Int
    let rerollsMax: Int
    let selectedVariant: SelectedVariant
    let createdAt: Date?

    // Joined template data (populated when fetching)
    var primaryQuest: QuestTemplate?
    var quickVariant: QuestQuickVariant?
    var altQuest: QuestTemplate?

    enum SelectedVariant: String, Codable {
        case primary
        case quick
        case alt
        case reroll
    }

    var rerollsRemaining: Int {
        max(0, rerollsMax - rerollsUsed)
    }

    var canReroll: Bool {
        rerollsRemaining > 0 || rerollsMax == 999 // Premium unlimited
    }

    var isPremiumUnlimited: Bool {
        rerollsMax == 999
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case questDate = "quest_date"
        case primaryQuestId = "primary_quest_id"
        case quickVariantId = "quick_variant_id"
        case altQuestId = "alt_quest_id"
        case rerollsUsed = "rerolls_used"
        case rerollsMax = "rerolls_max"
        case selectedVariant = "selected_variant"
        case createdAt = "created_at"
        case primaryQuest = "primary_quest_template"
        case quickVariant = "quest_quick_variant"
        case altQuest = "alt_quest_template"
    }
}

/// A shortened version of a quest (2-3 minutes, 50% XP)
struct QuestQuickVariant: Identifiable, Codable, Equatable {
    let id: UUID
    let parentTemplateId: UUID
    let title: String
    let description: String
    let steps: [QuestInstruction]
    let estimatedMinutes: Int
    let xpMultiplier: Double

    enum CodingKeys: String, CodingKey {
        case id
        case parentTemplateId = "parent_template_id"
        case title, description, steps
        case estimatedMinutes = "estimated_minutes"
        case xpMultiplier = "xp_multiplier"
    }
}

/// Tracks user preferences for quest categories (for smart recommendations)
struct QuestPreference: Codable, Equatable {
    let userId: UUID
    let questCategory: String
    let completionCount: Int
    let skipCount: Int
    let totalRatingSum: Int
    let ratingCount: Int
    let lastCompletedAt: Date?

    var avgRating: Double? {
        guard ratingCount > 0 else { return nil }
        return Double(totalRatingSum) / Double(ratingCount)
    }

    var preferenceScore: Double {
        let completionRate = Double(completionCount) / Double(max(1, completionCount + skipCount))
        let ratingScore = (avgRating ?? 3.0) / 5.0
        return (completionRate * 0.7) + (ratingScore * 0.3)
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case questCategory = "quest_category"
        case completionCount = "completion_count"
        case skipCount = "skip_count"
        case totalRatingSum = "total_rating_sum"
        case ratingCount = "rating_count"
        case lastCompletedAt = "last_completed_at"
    }
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

// MARK: - Weekly Summary / Insights

struct WeeklySummary: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let weekStart: String  // YYYY-MM-DD format
    let checkinCount: Int
    let questCount: Int
    let exerciseCount: Int
    let avgMood: Double?
    let moodTrend: MoodTrend?
    let generatedAt: Date

    // Extended insights fields
    let moodMin: Int?
    let moodMax: Int?
    let moodByDay: [String: Double]?
    let circleCheckinCount: Int?
    let exerciseMinutes: Int?
    let patternsDetected: [DetectedPattern]?
    let aiInsight: String?
    let aiRecommendations: [InsightRecommendation]?

    /// Friendly message based on mood trend
    var moodTrendMessage: String {
        guard let trend = moodTrend, avgMood != nil else {
            return "Keep tracking to see your trends!"
        }
        switch trend {
        case .improving:
            return "Your mood is trending up!"
        case .stable:
            return "Your mood has been steady."
        case .declining:
            return "It's been a tough week. We're here for you."
        case .insufficientData:
            return "Log more moods to see trends."
        }
    }

    /// Check if there's meaningful activity to report
    var hasActivity: Bool {
        checkinCount > 0 || questCount > 0 || exerciseCount > 0
    }

    /// Formatted week date range label
    var weekLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let startDate = formatter.date(from: weekStart) else {
            return weekStart
        }
        let endDate = Calendar.current.date(byAdding: .day, value: 6, to: startDate) ?? startDate
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }

    /// Check if we have enough data for meaningful insights
    var hasInsights: Bool {
        (patternsDetected?.isEmpty == false) || aiInsight != nil
    }
}

/// A pattern detected in user behavior
struct DetectedPattern: Codable, Equatable {
    let type: String  // "time", "activity", "streak"
    let description: String
    let confidence: Double

    var icon: String {
        switch type {
        case "time": return "clock"
        case "activity": return "figure.walk"
        case "streak": return "flame"
        default: return "lightbulb"
        }
    }
}

/// AI-generated recommendation
struct InsightRecommendation: Codable, Equatable {
    let title: String
    let reason: String
}

enum MoodTrend: String, Codable {
    case improving
    case stable
    case declining
    case insufficientData = "insufficient_data"

    var icon: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .stable: return "arrow.right"
        case .declining: return "arrow.down.right"
        case .insufficientData: return "questionmark.circle"
        }
    }

    var color: String {
        switch self {
        case .improving: return "green"
        case .stable: return "blue"
        case .declining: return "orange"
        case .insufficientData: return "gray"
        }
    }

    var emoji: String {
        switch self {
        case .improving: return "📈"
        case .stable: return "➡️"
        case .declining: return "📉"
        case .insufficientData: return "❓"
        }
    }
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
    let quotaUsed: Int?      // Server-authoritative: sync UI from this
    let quotaLimit: Int?     // Server-authoritative: limit value
    let crisisDetected: Bool?
    let conversationTitle: String?
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
    let premiumBadge: String?

    /// Whether this member has a premium subscription
    var isPremium: Bool {
        premiumBadge != nil
    }

    /// SF Symbol name for the premium badge
    var premiumBadgeIcon: String? {
        guard let badge = premiumBadge else { return nil }
        switch badge {
        case "premium_supporter": return "star.fill"
        case "annual_achiever": return "star.circle.fill"
        case "family_champion": return "person.3.fill"
        default: return "star.fill"
        }
    }

    /// Color for the premium badge
    var premiumBadgeColor: Color {
        guard let badge = premiumBadge else { return .yellow }
        switch badge {
        case "annual_achiever": return .purple
        case "family_champion": return .blue
        default: return .yellow
        }
    }
}

enum CircleRole: String, Codable {
    case owner
    case member
}

struct CircleDetail: Equatable {
    let circle: FriendCircle
    let members: [CircleMember]
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
    case challengeComplete = "challenge_complete"
}

// MARK: - Circle Virality

/// A hug sent between circle members
struct CircleHug: Codable, Identifiable, Equatable {
    let id: String
    let senderId: String
    let recipientId: String
    let circleId: String
    let createdAt: Date

    var senderName: String?
}

/// A 24-hour challenge created by circle owner
struct CircleChallenge: Codable, Identifiable, Equatable {
    let id: String
    let circleId: String
    let createdBy: String
    let challengeType: ChallengeType
    let title: String
    let description: String?
    let targetExerciseId: String?
    let startsAt: Date
    let endsAt: Date
    let createdAt: Date

    var completions: [ChallengeCompletion]?
    var creatorName: String?

    var isActive: Bool {
        let now = Date()
        return now >= startsAt && now <= endsAt
    }

    var timeRemaining: String {
        let remaining = endsAt.timeIntervalSince(Date())
        let hours = Int(remaining / 3600)
        if hours > 0 {
            return "\(hours)h left"
        }
        let minutes = Int(remaining / 60)
        return "\(max(0, minutes))m left"
    }
}

enum ChallengeType: String, Codable {
    case exercise
    case moodCheckin = "mood_checkin"
    case quest
    case custom
}

/// Tracks completion of a challenge by a user
struct ChallengeCompletion: Codable, Identifiable, Equatable {
    let id: String
    let challengeId: String
    let userId: String
    let completedAt: Date

    var userName: String?
}

/// An emoji reaction on a circle post
struct CircleReaction: Codable, Identifiable, Equatable {
    let id: String
    let postId: String
    let userId: String
    let emoji: String
    let createdAt: Date
}

/// The allowed emoji reactions
enum ReactionEmoji: String, CaseIterable {
    case party = "🎉"
    case clap = "👏"
    case strong = "💪"
    case heart = "❤️"
    case fire = "🔥"
}

/// A pending invite to a circle
struct CircleInvite: Codable, Identifiable, Equatable {
    let id: String
    let circleId: String
    let inviterId: String
    let inviteeEmail: String?
    let inviteePhone: String?
    let inviteCode: String
    let sentAt: Date
    let acceptedAt: Date?
    let reminderSentAt: Date?

    var inviterName: String?
    var circleName: String?

    var isPending: Bool {
        acceptedAt == nil
    }

    var displayContact: String {
        inviteeEmail ?? inviteePhone ?? "Unknown"
    }
}

/// Aggregated reactions for display
struct ReactionSummary: Equatable {
    let emoji: String
    let count: Int
    let userReacted: Bool
}

// MARK: - Buddy System

/// A buddy relationship from the onboarding invite flow
struct BuddyRelationship: Codable, Identifiable, Equatable {
    let id: String
    let inviterId: String
    let inviteeId: String?
    let inviteCode: String
    let inviteMethod: InviteMethod?
    let inviteeContact: String?
    var status: BuddyStatus
    let invitedAt: Date
    var acceptedAt: Date?
    let buddyCircleId: String?
    let expiresAt: Date

    // Joined data from profiles
    var inviter: BuddyProfile?
    var invitee: BuddyProfile?

    /// Get the buddy (the other person in the relationship)
    func buddy(currentUserId: String) -> BuddyProfile? {
        if inviterId == currentUserId {
            return invitee
        } else {
            return inviter
        }
    }

    /// Check if this relationship is active
    var isActive: Bool {
        status == .accepted
    }

    /// Check if this invite has expired
    var isExpired: Bool {
        status == .pending && Date() > expiresAt
    }

    enum InviteMethod: String, Codable {
        case sms
        case email
        case link
    }

    enum BuddyStatus: String, Codable {
        case pending
        case accepted
        case declined
        case expired
    }

    enum CodingKeys: String, CodingKey {
        case id
        case inviterId = "inviter_id"
        case inviteeId = "invitee_id"
        case inviteCode = "invite_code"
        case inviteMethod = "invite_method"
        case inviteeContact = "invitee_contact"
        case status
        case invitedAt = "invited_at"
        case acceptedAt = "accepted_at"
        case buddyCircleId = "buddy_circle_id"
        case expiresAt = "expires_at"
        case inviter
        case invitee
    }
}

/// Lightweight profile for buddy display
struct BuddyProfile: Codable, Equatable {
    let id: String
    let displayName: String
    let currentStreakDays: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case currentStreakDays = "current_streak_days"
    }
}

/// An encouragement message between buddies
struct BuddyEncouragement: Codable, Identifiable, Equatable {
    let id: String
    let buddyRelationshipId: String
    let senderId: String
    let recipientId: String
    let messageType: MessageType
    let message: String?
    let seenAt: Date?
    let createdAt: Date

    var senderName: String?

    /// Display message (uses default if custom message is nil)
    var displayMessage: String {
        message ?? defaultMessage
    }

    /// Default message based on type
    var defaultMessage: String {
        switch messageType {
        case .encouragement: return "You've got this!"
        case .celebration: return "Amazing work!"
        case .checkIn: return "Hey, checking in on you!"
        }
    }

    /// Emoji for the message type
    var emoji: String {
        switch messageType {
        case .encouragement: return "💪"
        case .celebration: return "🎉"
        case .checkIn: return "💙"
        }
    }

    enum MessageType: String, Codable {
        case encouragement
        case celebration
        case checkIn = "check_in"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case buddyRelationshipId = "buddy_relationship_id"
        case senderId = "sender_id"
        case recipientId = "recipient_id"
        case messageType = "message_type"
        case message
        case seenAt = "seen_at"
        case createdAt = "created_at"
        case senderName
    }
}

/// Data for the buddy widget on home screen
struct BuddyWidgetData: Codable, Equatable {
    let buddyName: String
    let buddyStreak: Int
    let buddyId: String
    let relationshipId: String
    let hasCompletedToday: Bool
    let needsCheckIn: Bool
    let lastEncouragementId: String?
    let lastEncouragementType: String?
    let lastEncouragementAt: Date?

    /// Status message for display
    var statusMessage: String {
        if hasCompletedToday {
            return "Completed today's quest!"
        } else if needsCheckIn {
            return "Hasn't checked in recently"
        } else {
            return "\(buddyStreak) day streak"
        }
    }

    /// Status icon name
    var statusIcon: String {
        if hasCompletedToday {
            return "checkmark.circle.fill"
        } else if needsCheckIn {
            return "exclamationmark.circle.fill"
        } else {
            return "flame.fill"
        }
    }

    /// Status color
    var statusColor: Color {
        if hasCompletedToday {
            return .green
        } else if needsCheckIn {
            return .orange
        } else {
            return .orange
        }
    }

    enum CodingKeys: String, CodingKey {
        case buddyName = "buddy_name"
        case buddyStreak = "buddy_streak"
        case buddyId = "buddy_id"
        case relationshipId = "relationship_id"
        case hasCompletedToday = "has_completed_today"
        case needsCheckIn = "needs_check_in"
        case lastEncouragementId = "last_encouragement_id"
        case lastEncouragementType = "last_encouragement_type"
        case lastEncouragementAt = "last_encouragement_at"
    }
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

    // Credibility fields
    let evidenceBasis: EvidenceBasis?
    let therapistReviewed: Bool?
    let reviewDate: String?
    let methodologyNote: String?

    /// Whether this exercise has been reviewed by a mental health professional
    var isTherapistReviewed: Bool {
        therapistReviewed ?? false
    }
}

// MARK: - Credibility

/// Evidence-based methodology for exercises
enum EvidenceBasis: String, Codable, CaseIterable {
    case CBT
    case DBT
    case ACT
    case Mindfulness
    case Somatic
    case Breathwork
    case General

    var displayName: String {
        switch self {
        case .CBT: return "Cognitive Behavioral Therapy"
        case .DBT: return "Dialectical Behavior Therapy"
        case .ACT: return "Acceptance & Commitment Therapy"
        case .Mindfulness: return "Mindfulness-Based"
        case .Somatic: return "Somatic Practice"
        case .Breathwork: return "Breathwork"
        case .General: return "Evidence-Informed"
        }
    }

    var shortLabel: String {
        switch self {
        case .CBT: return "CBT"
        case .DBT: return "DBT"
        case .ACT: return "ACT"
        case .Mindfulness: return "Mindfulness"
        case .Somatic: return "Somatic"
        case .Breathwork: return "Breathwork"
        case .General: return "Wellness"
        }
    }

    var color: Color {
        switch self {
        case .CBT: return .blue
        case .DBT: return .purple
        case .ACT: return .green
        case .Mindfulness: return .teal
        case .Somatic: return .orange
        case .Breathwork: return .cyan
        case .General: return .gray
        }
    }
}

/// Information about a therapeutic methodology
struct MethodologyInfo: Codable, Identifiable, Equatable {
    let code: String
    let name: String
    let description: String
    let source: String?

    var id: String { code }
}

/// A user testimonial for social proof
struct Testimonial: Codable, Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let location: String?
    let content: String
    let rating: Int
    let featureHighlight: String?
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

    var displayName: String {
        switch self {
        case .breathing: return "Breathing"
        case .meditation: return "Meditation"
        case .grounding: return "Grounding"
        case .journaling: return "Journaling"
        case .movement: return "Movement"
        }
    }

    var themeColor: Color {
        switch self {
        case .breathing: return .cyan
        case .meditation: return .purple
        case .grounding: return .green
        case .journaling: return .orange
        case .movement: return .pink
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

// MARK: - Memory

struct MemoryFragment: Codable, Identifiable, Equatable {
    let id: String
    let fragmentType: MemoryType
    let key: String           // e.g., "dog_name", "work_location"
    let value: String         // e.g., "Max", "San Francisco"
    let confidence: Double    // 0.0-1.0 extraction confidence
    let extractedAt: Date
    let expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return expiresAt < Date()
    }

    /// Display string combining key and value
    var displayContent: String {
        // Format key nicely: dog_name -> Dog name
        let formattedKey = key.replacingOccurrences(of: "_", with: " ").capitalized
        return "\(formattedKey): \(value)"
    }
}

enum MemoryType: String, Codable, CaseIterable {
    case person
    case event
    case preference
    case fact

    var displayName: String {
        switch self {
        case .person: return "People"
        case .event: return "Events"
        case .preference: return "Preferences"
        case .fact: return "Facts"
        }
    }

    var icon: String {
        switch self {
        case .person: return "person.2.fill"
        case .event: return "calendar"
        case .preference: return "heart.fill"
        case .fact: return "info.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .person: return "Names of family, friends, pets, and coworkers"
        case .event: return "Upcoming events and past experiences"
        case .preference: return "Likes, dislikes, and communication style"
        case .fact: return "Job, location, hobbies, and other facts"
        }
    }
}

// MARK: - XP & Progression

/// User's current level and XP progress
struct UserLevel: Equatable {
    let level: Int
    let title: String
    let currentXP: Int
    let nextLevelXP: Int
    let xpThisWeek: Int

    /// Progress toward next level (0.0 to 1.0)
    var progress: Double {
        guard nextLevelXP > currentXP else { return 1.0 }
        // Find current level threshold
        let currentThreshold = Self.xpThresholds[min(level - 1, 49)]
        let nextThreshold = Self.xpThresholds[min(level, 49)]
        guard nextThreshold > currentThreshold else { return 1.0 }
        return Double(currentXP - currentThreshold) / Double(nextThreshold - currentThreshold)
    }

    /// XP needed to reach next level
    var xpToNextLevel: Int {
        max(0, nextLevelXP - currentXP)
    }

    /// Level thresholds (from database)
    static let xpThresholds = [
        0, 100, 250, 450, 700, 1000, 1350, 1750, 2200, 2700,
        3250, 3850, 4500, 5200, 5950, 6750, 7600, 8500, 9450, 10450,
        11500, 12600, 13750, 14950, 16200, 17500, 18850, 20250, 21700, 23200,
        24750, 26350, 28000, 29700, 31450, 33250, 35100, 37000, 38950, 40950,
        43000, 45100, 47250, 49450, 51700, 54000, 56350, 58750, 61200, 63700
    ]

    /// Create from UserStats
    static func from(stats: UserStats) -> UserLevel {
        let nextXP = stats.level < 50 ? xpThresholds[stats.level] : stats.xpTotal
        return UserLevel(
            level: stats.level,
            title: stats.levelTitle,
            currentXP: stats.xpTotal,
            nextLevelXP: nextXP,
            xpThisWeek: stats.xpThisWeek
        )
    }
}

/// Shared constants for skill level progression
struct SkillLevel {
    /// XP thresholds for each skill level (index = level, value = XP required)
    /// Level 0: 0, Level 1: 150, Level 2: 500, Level 3: 1200, Level 4: 3000, Level 5: 7500
    static let thresholds = [0, 150, 500, 1200, 3000, 7500]

    /// Titles for each skill level (index = level)
    static let titles = ["Novice", "Apprentice", "Practitioner", "Expert", "Master", "Grandmaster"]

    /// Maximum skill level
    static let maxLevel = 5
}

/// User's progress in a specific skill type
struct SkillProgress: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let skillType: ExerciseType
    let xp: Int
    let skillLevel: Int
    let exercisesCompleted: Int
    let createdAt: Date
    let updatedAt: Date

    // MARK: - Coding Keys for database field mapping

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case skillType = "skill_type"
        case xp
        case skillLevel = "skill_level"
        case exercisesCompleted = "exercises_completed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - Custom Decoding for ExerciseType

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        let skillTypeString = try container.decode(String.self, forKey: .skillType)
        skillType = ExerciseType(rawValue: skillTypeString) ?? .breathing
        xp = try container.decode(Int.self, forKey: .xp)
        skillLevel = try container.decode(Int.self, forKey: .skillLevel)
        exercisesCompleted = try container.decode(Int.self, forKey: .exercisesCompleted)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(skillType.rawValue, forKey: .skillType)
        try container.encode(xp, forKey: .xp)
        try container.encode(skillLevel, forKey: .skillLevel)
        try container.encode(exercisesCompleted, forKey: .exercisesCompleted)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    // MARK: - Memberwise Initializer for Previews/Tests

    init(
        id: String,
        userId: String,
        skillType: ExerciseType,
        xp: Int,
        skillLevel: Int,
        exercisesCompleted: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.skillType = skillType
        self.xp = xp
        self.skillLevel = skillLevel
        self.exercisesCompleted = exercisesCompleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Computed Properties

    /// User-friendly title for the skill level
    var levelTitle: String {
        guard skillLevel >= 0 && skillLevel < SkillLevel.titles.count else {
            return SkillLevel.titles[0]
        }
        return SkillLevel.titles[skillLevel]
    }

    /// XP needed for next skill level
    var nextLevelXP: Int {
        guard skillLevel < SkillLevel.maxLevel else {
            return SkillLevel.thresholds[SkillLevel.maxLevel]
        }
        return SkillLevel.thresholds[skillLevel + 1]
    }

    /// Current skill level threshold
    var currentLevelXP: Int {
        guard skillLevel >= 0 && skillLevel <= SkillLevel.maxLevel else {
            return 0
        }
        return SkillLevel.thresholds[skillLevel]
    }

    /// Progress toward next skill level (0.0 to 1.0)
    var progress: Double {
        guard skillLevel < SkillLevel.maxLevel else { return 1.0 }
        let current = currentLevelXP
        let next = nextLevelXP
        guard next > current else { return 1.0 }
        return Double(xp - current) / Double(next - current)
    }
}

/// A time-limited seasonal event/challenge
struct SeasonalEvent: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String?
    let startsAt: Date
    let endsAt: Date
    let eventType: String
    let requiredActivityType: String?
    let rewardBadgeId: String?
    let targetCount: Int
    let xpMultiplier: Double
    let createdAt: Date

    /// Whether the event is currently active
    var isActive: Bool {
        let now = Date()
        return now >= startsAt && now <= endsAt
    }

    /// Days remaining in the event
    var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: endsAt).day ?? 0)
    }

    /// Human-readable time remaining
    var timeRemainingText: String {
        let days = daysRemaining
        if days == 0 {
            let hours = Calendar.current.dateComponents([.hour], from: Date(), to: endsAt).hour ?? 0
            return hours > 0 ? "\(hours)h left" : "Ending soon"
        }
        return "\(days) day\(days == 1 ? "" : "s") left"
    }
}

/// User's participation and progress in an event
struct EventParticipation: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let eventId: String
    let progress: Int
    let completedAt: Date?
    let joinedAt: Date

    var isCompleted: Bool {
        completedAt != nil
    }
}

/// Result of awarding XP
struct XPAward: Equatable {
    let amount: Int
    let newTotal: Int
    let newLevel: Int
    let newTitle: String
    let leveledUp: Bool
}

/// Types of activities that earn XP
enum XPActivity: Equatable {
    case questComplete
    case exerciseComplete(ExerciseType)
    case moodCheckin
    case circleCheckin

    /// XP amount for each activity type
    var xpAmount: Int {
        switch self {
        case .questComplete: return 50
        case .exerciseComplete: return 30
        case .moodCheckin: return 10
        case .circleCheckin: return 20
        }
    }

    /// Activity type string for database
    var activityTypeString: String {
        switch self {
        case .questComplete: return "quest"
        case .exerciseComplete: return "exercise"
        case .moodCheckin: return "mood"
        case .circleCheckin: return "circle"
        }
    }

    /// Skill type string if applicable (for exercise completion)
    var skillType: String? {
        if case .exerciseComplete(let type) = self {
            return type.rawValue
        }
        return nil
    }
}

/// Progress update from event increment
struct EventProgressUpdate: Equatable {
    let eventId: String
    let eventName: String
    let newProgress: Int
    let targetCount: Int
    let justCompleted: Bool
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

// MARK: - Data Export

struct UserDataExport: Codable {
    let exportedAt: String
    let user: UserExportData
    let settings: SettingsExportData?
    let moods: [MoodExportData]
    let quests: [QuestExportData]
    let conversations: [ConversationExportData]
    let circles: [CircleExportData]
    let exerciseSessions: [ExerciseSessionExportData]
    // EXE-010: Added subscription and crisis events to comprehensive export
    let subscription: SubscriptionExportData?
    let crisisEvents: [CrisisEventExportData]

    struct UserExportData: Codable {
        let id: String
        let handle: String
        let displayName: String
        let email: String?
        let timezone: String?
        let createdAt: String?
    }

    struct SettingsExportData: Codable {
        let notificationsEnabled: Bool?
        let quietHoursStart: String?
        let quietHoursEnd: String?
        let privacyMode: Bool?
        let aiTone: String?
    }

    struct MoodExportData: Codable {
        let date: String
        let moodScore: Int
        let anxietyScore: Int?
        let energyScore: Int?
        let notes: String?
        let tags: [String]?
    }

    struct QuestExportData: Codable {
        let id: String
        let title: String
        let assignedAt: String
        let completedAt: String?
        let status: String
    }

    struct ConversationExportData: Codable {
        let id: String
        let title: String?
        let createdAt: String
        let messages: [MessageExportData]
    }

    struct MessageExportData: Codable {
        let role: String
        let content: String
        let createdAt: String
    }

    struct CircleExportData: Codable {
        let id: String
        let name: String
        let role: String
        let joinedAt: String
    }

    struct ExerciseSessionExportData: Codable {
        let exerciseName: String
        let exerciseType: String
        let completedAt: String
        let durationSeconds: Int?
    }

    /// EXE-010: Subscription data for comprehensive export
    struct SubscriptionExportData: Codable {
        let productId: String?
        let planType: String?
        let billingPeriod: String?
        let status: String?
        let expiresAt: String?
        let createdAt: String?
    }

    /// EXE-010: Crisis event data for export (keyword + timestamp only, no content)
    struct CrisisEventExportData: Codable {
        let triggerKeyword: String?  // Only the matched keyword, not actual user content
        let detectedAt: String
    }
}

// MARK: - Re-engagement

/// Tier classification for user absence duration
enum LapseTier: String, Codable, CaseIterable {
    case active = "active"
    case briefBreak = "brief_break"
    case extendedBreak = "extended_break"
    case longAbsence = "long_absence"
    case hiatus = "hiatus"

    /// Warm welcome message for the tier
    var welcomeMessage: String {
        switch self {
        case .active:
            return ""
        case .briefBreak:
            return "Good to see you!"
        case .extendedBreak:
            return "Welcome back! We missed you."
        case .longAbsence:
            return "It's great to have you back."
        case .hiatus:
            return "Welcome back, friend. We're glad you're here."
        }
    }

    /// Supportive sub-message for the tier
    var subMessage: String {
        switch self {
        case .active:
            return ""
        case .briefBreak:
            return "Ready to continue your wellness journey?"
        case .extendedBreak:
            return "Life gets busy sometimes. No judgment here."
        case .longAbsence:
            return "Whatever brought you back, we're here for you."
        case .hiatus:
            return "Every moment is a chance for a fresh start. Your progress is still saved."
        }
    }

    /// Whether to show the Fresh Start option
    var showFreshStart: Bool {
        switch self {
        case .active, .briefBreak:
            return false
        case .extendedBreak, .longAbsence, .hiatus:
            return true
        }
    }

    /// Whether this tier should trigger the welcome back modal
    var shouldShowWelcomeBack: Bool {
        self != .active
    }

    /// Minimum days for this tier
    var minimumDays: Int {
        switch self {
        case .active: return 0
        case .briefBreak: return 3
        case .extendedBreak: return 7
        case .longAbsence: return 14
        case .hiatus: return 30
        }
    }
}

/// Summary of what the user missed while away
struct AbsenceSummary: Codable, Equatable {
    let absenceDays: Int
    let lapseTier: LapseTier
    let hugsReceived: Int
    let circlePosts: Int
    let friendMilestones: [FriendMilestone]

    /// Nested type for friend milestone info
    struct FriendMilestone: Codable, Equatable, Identifiable {
        let name: String
        let milestone: String
        let isStreak: Bool

        var id: String { "\(name)-\(milestone)" }

        enum CodingKeys: String, CodingKey {
            case name
            case milestone
            case isStreak = "isStreak"
        }
    }

    /// Whether there's any activity to show
    var hasActivity: Bool {
        hugsReceived > 0 || circlePosts > 0 || !friendMilestones.isEmpty
    }

    /// Whether this absence warrants showing the welcome back modal
    var shouldShowWelcomeBack: Bool {
        absenceDays >= 3
    }

    enum CodingKeys: String, CodingKey {
        case absenceDays = "absence_days"
        case lapseTier = "lapse_tier"
        case hugsReceived = "hugs_received"
        case circlePosts = "circle_posts"
        case friendMilestones = "friend_milestones"
    }
}

/// Types of re-engagement events for analytics and tracking
enum ReengagementEventType: String, Codable {
    case welcomeBackShown = "welcome_back_shown"
    case welcomeBackDismissed = "welcome_back_dismissed"
    case freshStartChosen = "fresh_start_chosen"
    case continueChosen = "continue_chosen"
    case notificationSent = "notification_sent"
    case notificationOpened = "notification_opened"
}

/// A re-engagement event for logging
struct ReengagementEvent: Codable {
    let userId: UUID
    let eventType: ReengagementEventType
    let absenceDays: Int
    let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case eventType = "event_type"
        case absenceDays = "absence_days"
        case metadata
    }
}

/// Result from recording a session start
struct SessionStartResult: Codable {
    let previousAbsenceDays: Int
    let lapseTier: LapseTier
    let isReturning: Bool

    enum CodingKeys: String, CodingKey {
        case previousAbsenceDays = "previous_absence_days"
        case lapseTier = "lapse_tier"
        case isReturning = "is_returning"
    }
}

/// Result from performing a fresh start
struct FreshStartResult: Codable {
    let success: Bool
    let newStreak: Int
    let freshStartBonus: Int

    enum CodingKeys: String, CodingKey {
        case success
        case newStreak = "new_streak"
        case freshStartBonus = "fresh_start_bonus"
    }
}

// MARK: - Mood-Adaptive Home Experience

/// Time of day categories for contextual content
enum TimeOfDay: String, Codable, CaseIterable {
    case morning
    case afternoon
    case evening
    case night

    /// Returns the current time of day based on system time
    static var current: TimeOfDay {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }

    /// Greeting text for this time of day
    var greeting: String {
        switch self {
        case .morning: return "Good morning"
        case .afternoon: return "Good afternoon"
        case .evening: return "Good evening"
        case .night: return "Hello"
        }
    }

    /// Subtitle text encouraging engagement
    var subtitle: String {
        switch self {
        case .morning: return "Ready to start your day?"
        case .afternoon: return "How's your day going?"
        case .evening: return "Time to wind down"
        case .night: return "Rest well tonight"
        }
    }

    /// SF Symbol icon for this time of day
    var icon: String {
        switch self {
        case .morning: return "sun.max.fill"
        case .afternoon: return "sun.min.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }

    /// Suggested activity type for this time of day
    var suggestedActivityType: String {
        switch self {
        case .morning: return "energizing"
        case .afternoon: return "focusing"
        case .evening: return "calming"
        case .night: return "sleep"
        }
    }
}

/// Mood context categories based on mood score
enum MoodContext: String, Codable {
    case low      // Mood score 1-2
    case neutral  // Mood score 3
    case high     // Mood score 4-5

    /// Initialize from a mood score (1-5)
    init(score: Int) {
        switch score {
        case 1...2: self = .low
        case 3: self = .neutral
        default: self = .high
        }
    }

    /// Background color for this mood context
    var backgroundColor: Color {
        switch self {
        case .low: return Color.blue.opacity(0.05)
        case .neutral: return Color(uiColor: .systemBackground)
        case .high: return Color.green.opacity(0.05)
        }
    }

    /// Accent color for this mood context
    var accentColor: Color {
        switch self {
        case .low: return .blue
        case .neutral: return .purple
        case .high: return .green
        }
    }

    /// Default supportive message for this mood context
    var defaultMessage: String? {
        switch self {
        case .low: return "It's okay to have tough days. We're here for you."
        case .neutral: return nil
        case .high: return "Wonderful! Your positive energy is inspiring."
        }
    }
}

/// Recommended action for the home screen quick actions
struct RecommendedAction: Codable, Identifiable, Equatable {
    let type: ActionType
    let title: String
    let icon: String
    let priority: Int

    var id: String { type.rawValue }

    enum ActionType: String, Codable {
        case exercise
        case chat
        case circle
        case quest
        case breathing
        case journal
        case celebrate
        case share
    }

    enum CodingKeys: String, CodingKey {
        case type, title, icon, priority
    }
}

/// Home context containing all personalization data for the home screen
struct HomeContext: Codable, Equatable {
    let todayMood: Int?
    let moodTrend: String?
    let consecutiveLowMoodDays: Int
    let daysSinceExercise: Int
    let daysSinceCircleCheckin: Int
    let questCompletedToday: Bool
    let moodContextValue: String?
    let showCrisisSupport: Bool
    let supportiveMessage: String?
    let recommendedActions: [RecommendedAction]
    let recommendedExerciseIds: [UUID]

    /// Computed mood context from the raw value
    var moodContext: MoodContext {
        if let value = moodContextValue {
            return MoodContext(rawValue: value) ?? .neutral
        }
        guard let mood = todayMood else { return .neutral }
        return MoodContext(score: mood)
    }

    /// Time of day (calculated client-side)
    var timeOfDay: TimeOfDay {
        TimeOfDay.current
    }

    /// Whether we should prominently show crisis resources
    var shouldShowCrisisSupport: Bool {
        showCrisisSupport || consecutiveLowMoodDays >= 2 || (todayMood ?? 3) <= 1
    }

    enum CodingKeys: String, CodingKey {
        case todayMood = "today_mood"
        case moodTrend = "mood_trend"
        case consecutiveLowMoodDays = "consecutive_low_mood_days"
        case daysSinceExercise = "days_since_exercise"
        case daysSinceCircleCheckin = "days_since_circle_checkin"
        case questCompletedToday = "quest_completed_today"
        case moodContextValue = "mood_context"
        case showCrisisSupport = "show_crisis_support"
        case supportiveMessage = "supportive_message"
        case recommendedActions = "recommended_actions"
        case recommendedExerciseIds = "recommended_exercise_ids"
    }

    /// Default context when no data is available
    static let `default` = HomeContext(
        todayMood: nil,
        moodTrend: nil,
        consecutiveLowMoodDays: 0,
        daysSinceExercise: 0,
        daysSinceCircleCheckin: 0,
        questCompletedToday: false,
        moodContextValue: "neutral",
        showCrisisSupport: false,
        supportiveMessage: nil,
        recommendedActions: [],
        recommendedExerciseIds: []
    )
}
