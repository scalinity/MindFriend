import Foundation
import SwiftUI

// MARK: - Stub Types (from files not yet in Xcode project target)
// TODO: Remove other stubs as their feature modules are added

// MARK: - User

public struct UserProfile: Codable, Identifiable, Equatable {
    public let id: UUID
    public let handle: String?
    public let displayName: String?
    public let email: String?
    public let avatarUrl: String?
    public let timezone: String?
    public let createdAt: Date?
    public let onboardingCompletedAt: Date?
    public let stats: UserStats?
    public let settings: UserSettings?
    public let entitlements: UserEntitlements?
    public let badges: [UserBadge]?

    /// Returns true if the user hasn't completed onboarding yet
    var needsOnboarding: Bool {
        onboardingCompletedAt == nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case displayName = "display_name"
        case email
        case avatarUrl = "avatar_url"
        case timezone
        case createdAt = "created_at"
        case onboardingCompletedAt = "onboarding_completed_at"
        case stats
        case settings
        case entitlements
        case badges
    }
}

// MARK: - User Settings

public struct UserSettings: Codable, Equatable {
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

    // Smart notification system v2 (optional for backwards compatibility)
    var smartNotificationsEnabled: Bool?
    var notificationMaxPerDay: Int?
    var notificationFrequency: String?  // "minimal", "moderate", "frequent"
    var enabledNotificationTypes: [String]?
    var syncQuietHoursWithSleep: Bool?
    var betaNotificationsOptIn: Bool?
    var manualDndEnabled: Bool?

    // Recovery mode fields (optional for backwards compatibility)
    var recoveryModeActive: Bool?
    var recoveryModeEnteredAt: Date?
    var recoveryModeReason: RecoveryModeReason?
}

// MARK: - Recovery Mode

/// Reason for entering recovery mode
enum RecoveryModeReason: String, Codable, Equatable {
    case manual
    case autoConsecutiveLowMood = "auto_consecutive_low_mood"

    var displayText: String {
        switch self {
        case .manual:
            return "You enabled recovery mode"
        case .autoConsecutiveLowMood:
            return "We noticed you've had some tough days"
        }
    }
}

/// Represents the current recovery mode state for a user
struct RecoveryModeState: Codable, Equatable {
    let isActive: Bool
    let enteredAt: Date?
    let reason: RecoveryModeReason?

    /// Whether the user can manually exit (requires 24h minimum)
    var canManuallyExit: Bool {
        guard isActive, let enteredAt = enteredAt else { return true }
        let hoursSinceEntry = Date().timeIntervalSince(enteredAt) / 3600
        return hoursSinceEntry >= 24
    }

    /// Hours remaining until manual exit is allowed
    var hoursUntilExitAllowed: Int? {
        guard isActive, !canManuallyExit, let enteredAt = enteredAt else { return nil }
        let hoursSinceEntry = Date().timeIntervalSince(enteredAt) / 3600
        return max(0, Int(ceil(24 - hoursSinceEntry)))
    }

    /// Time remaining formatted as "Xh Ym"
    var timeUntilExitFormatted: String? {
        guard let hours = hoursUntilExitAllowed else { return nil }
        if hours >= 1 {
            return "\(hours)h"
        }
        return "< 1h"
    }

    enum CodingKeys: String, CodingKey {
        case isActive = "recovery_mode_active"
        case enteredAt = "recovery_mode_entered_at"
        case reason = "recovery_mode_reason"
    }

    static let inactive = RecoveryModeState(isActive: false, enteredAt: nil, reason: nil)
}

/// Result of toggling recovery mode
struct ToggleRecoveryModeResult: Equatable {
    let success: Bool
    let errorMessage: String?
    let newState: RecoveryModeState

    var failed: Bool { !success }
}

public struct UserStats: Codable, Equatable {
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

    enum CodingKeys: String, CodingKey {
        case currentStreakDays = "current_streak"
        case longestStreakDays = "longest_streak"
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
}

// MARK: - User Entitlements

public struct UserEntitlements: Codable, Equatable {
    var subscriptionTier: String
    var premiumExpiresAt: Date?
    var features: [String: Bool]

    enum CodingKeys: String, CodingKey {
        case subscriptionTier = "subscription_tier"
        case premiumExpiresAt = "premium_expires_at"
        case features
    }
}

// MARK: - User Badge

public struct UserBadge: Codable, Identifiable, Equatable {
    public var id: UUID
    var badgeId: String
    var earnedAt: Date
    var progress: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case badgeId = "badge_id"
        case earnedAt = "earned_at"
        case progress
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
            return "Your session has expired. Please sign out (Profile → Settings → Sign Out) and sign back in."
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
// Note: BillingPeriod and PlanType are defined in BusinessModels.swift

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
    let joinedAt: Date?
    let removedAt: Date?

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

// MARK: - App Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    /// UserDefaults key for theme storage
    static let storageKey = "selectedTheme"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .system: return .secondary
        case .light: return .orange
        case .dark: return .indigo
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
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
    let completedAt: Date?
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

    enum CodingKeys: String, CodingKey {
        case step, text
        case durationSeconds = "duration_seconds"
    }
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
    let questDate: String  // PostgreSQL DATE returns "YYYY-MM-DD" string format
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
        formatter.dateFormat = "MMM d"
        guard let startDate = formatter.date(from: weekStart) else {
            return weekStart
        }
        let endDate = Calendar.current.date(byAdding: .day, value: 6, to: startDate) ?? startDate
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
    let memoryUsed: Bool?    // Whether companion memory was used in this response
    let memoryIdsUsed: [String]?  // IDs of memories that were used
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
    let ritualId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case userDisplayName = "user_display_name"
        case kind
        case moodEmoji = "mood_emoji"
        case bodyText = "body_text"
        case localDate = "local_date"
        case createdAt = "created_at"
        case ritualId = "ritual_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        userDisplayName = try container.decodeIfPresent(String.self, forKey: .userDisplayName) ?? "Unknown"
        kind = try container.decode(PostKind.self, forKey: .kind)
        moodEmoji = try container.decodeIfPresent(String.self, forKey: .moodEmoji)
        bodyText = try container.decodeIfPresent(String.self, forKey: .bodyText)
        localDate = try container.decode(String.self, forKey: .localDate)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        ritualId = try container.decodeIfPresent(String.self, forKey: .ritualId)
    }

    init(id: String, circleId: String, userId: String, kind: PostKind, moodEmoji: String?, bodyText: String?, localDate: String, createdAt: Date, userDisplayName: String, ritualId: String? = nil) {
        self.id = id
        self.userId = userId
        self.userDisplayName = userDisplayName
        self.kind = kind
        self.moodEmoji = moodEmoji
        self.bodyText = bodyText
        self.localDate = localDate
        self.createdAt = createdAt
        self.ritualId = ritualId
    }
}

enum PostKind: String, Codable {
    case checkin
    case milestone
    case challengeComplete = "challenge_complete"
    case ritualRecap = "ritual_recap"
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
        case hibernating = "hibernating"
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
            return "Every moment is a chance for a fresh start. Your progress is still saved."
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
struct AbsenceSummary: Codable, Identifiable, Equatable {
    let absenceDays: Int
    let lapseTier: LapseTier
    let hugsReceived: Int
    let circlePosts: Int
    let friendMilestones: [FriendMilestone]

    var id: String { "\(absenceDays)-\(lapseTier.rawValue)" }

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

// MARK: - Proactive Intelligence

/// User engagement state classification for proactive outreach
enum EngagementState: String, Codable, CaseIterable {
    case highlyActive = "HIGHLY_ACTIVE"
    case active = "ACTIVE"
    case moderate = "MODERATE"
    case drifting = "DRIFTING"
    case lapsed = "LAPSED"
    case hibernating = "HIBERNATING"

    var displayName: String {
        switch self {
        case .highlyActive: return "Highly Active"
        case .active: return "Active"
        case .moderate: return "Moderate"
        case .drifting: return "Drifting"
        case .lapsed: return "Lapsed"
        case .hibernating: return "Hibernating"
        }
    }

    var description: String {
        switch self {
        case .highlyActive: return "Multiple daily interactions"
        case .active: return "Regular daily engagement"
        case .moderate: return "Consistent but less frequent"
        case .drifting: return "Starting to disengage"
        case .lapsed: return "Been away for a while"
        case .hibernating: return "Extended absence"
        }
    }

    /// Whether proactive outreach is appropriate for this state
    var shouldReceiveProactive: Bool {
        switch self {
        case .highlyActive, .active:
            return false // They're already engaged
        case .moderate, .drifting, .lapsed, .hibernating:
            return true
        }
    }
}

/// Trigger types for proactive outreach
enum ProactiveTriggerType: String, Codable, CaseIterable {
    case moodDecline = "mood_decline"
    case streakRisk = "streak_risk"
    case milestoneApproach = "milestone_approach"
    case reengagement = "reengagement"
    case patternInsight = "pattern_insight"

    var displayName: String {
        switch self {
        case .moodDecline: return "Mood Support"
        case .streakRisk: return "Streak Reminder"
        case .milestoneApproach: return "Milestone Alert"
        case .reengagement: return "Check-in"
        case .patternInsight: return "Pattern Insight"
        }
    }

    var description: String {
        switch self {
        case .moodDecline: return "Supportive check-in when mood drops"
        case .streakRisk: return "Reminder when streak is at risk"
        case .milestoneApproach: return "Celebration of upcoming milestones"
        case .reengagement: return "Gentle nudge to return after absence"
        case .patternInsight: return "Insights about detected patterns"
        }
    }

    var icon: String {
        switch self {
        case .moodDecline: return "heart.fill"
        case .streakRisk: return "flame.fill"
        case .milestoneApproach: return "trophy.fill"
        case .reengagement: return "hand.wave.fill"
        case .patternInsight: return "lightbulb.fill"
        }
    }

    /// Priority level (lower = higher priority)
    var priority: Int {
        switch self {
        case .moodDecline: return 1
        case .streakRisk: return 2
        case .milestoneApproach: return 3
        case .reengagement: return 4
        case .patternInsight: return 5
        }
    }
}

/// Status of a proactive message
enum ProactiveMessageStatus: String, Codable {
    case scheduled
    case sent
    case read
    case engaged
    case ignored
    case expired
}

/// Delivery channel for proactive messages
enum ProactiveDeliveryChannel: String, Codable {
    case push
    case inApp = "in_app"
    case email
}

/// A proactive message sent to a user
struct ProactiveMessage: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let triggerType: ProactiveTriggerType
    let messageContent: String
    let deliveryChannel: ProactiveDeliveryChannel
    let scheduledFor: Date
    var sentAt: Date?
    var readAt: Date?
    var engagedAt: Date?
    var status: ProactiveMessageStatus
    let metadata: [String: AnyCodable]?
    let createdAt: Date

    /// Whether the user has interacted with this message
    var wasEngaged: Bool {
        engagedAt != nil
    }

    /// Whether the message was seen
    var wasRead: Bool {
        readAt != nil
    }

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
}

/// Pattern types detected in user behavior
enum PatternType: String, Codable, CaseIterable {
    case dayOfWeek = "day_of_week"
    case exerciseCorrelation = "exercise_correlation"
    case questPreference = "quest_preference"

    var displayName: String {
        switch self {
        case .dayOfWeek: return "Weekly Rhythm"
        case .exerciseCorrelation: return "Exercise Impact"
        case .questPreference: return "Quest Preference"
        }
    }

    var description: String {
        switch self {
        case .dayOfWeek: return "Mood patterns by day of week"
        case .exerciseCorrelation: return "How exercise affects your mood"
        case .questPreference: return "Types of quests you enjoy most"
        }
    }

    var icon: String {
        switch self {
        case .dayOfWeek: return "calendar"
        case .exerciseCorrelation: return "figure.run"
        case .questPreference: return "star.fill"
        }
    }
}

/// A detected behavioral pattern for a user
struct UserPattern: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let patternType: PatternType
    let patternKey: String
    let patternData: [String: AnyCodable]
    let confidence: Double
    let firstDetectedAt: Date
    let lastConfirmedAt: Date
    var timesSurfaced: Int
    var userAcknowledged: Bool
    var isActive: Bool
    let createdAt: Date

    /// Whether this pattern has high confidence
    var isHighConfidence: Bool {
        confidence >= 0.7
    }

    /// Whether this pattern should be surfaced to the user
    var shouldSurface: Bool {
        isActive && isHighConfidence && !userAcknowledged
    }

    /// Human-readable insight message based on pattern data
    var insightMessage: String? {
        switch patternType {
        case .dayOfWeek:
            guard let deltaWrapper = patternData["delta"],
                  let delta = deltaWrapper as? Double else { return nil }
            let dayName = patternKey.components(separatedBy: "_").first ?? "thatday"
            let trend = patternKey.contains("dip") ? "dip" : "peak"
            if trend == "dip" {
                return "Your mood tends to dip on \(dayName)s (about \(String(format: "%.1f", abs(delta))) points lower than average)."
            } else {
                return "Your mood tends to peak on \(dayName)s (about \(String(format: "%.1f", abs(delta))) points higher than average)!"
            }

        case .exerciseCorrelation:
            guard let exerciseAvgWrapper = patternData["exercise_day_avg"],
                  let exerciseAvg = exerciseAvgWrapper as? Double,
                  let nonExerciseAvgWrapper = patternData["non_exercise_day_avg"],
                  let nonExerciseAvg = nonExerciseAvgWrapper as? Double else { return nil }
            let delta = exerciseAvg - nonExerciseAvg
            return "On days you exercise, your mood averages \(String(format: "%.1f", exerciseAvg)) compared to \(String(format: "%.1f", nonExerciseAvg)) on rest days. That's a +\(String(format: "%.1f", delta)) improvement!"

        case .questPreference:
            guard let questTypeWrapper = patternData["quest_type"],
                  let questType = questTypeWrapper as? String,
                  let rateWrapper = patternData["completion_rate"],
                  let rate = rateWrapper as? Double else { return nil }
            return "You complete \(questType) quests \(Int(rate * 100))% of the time. We'll try to offer more of these!"
        }
    }

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
    }
}

/// User's engagement state record from the database
struct UserEngagementState: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let currentState: EngagementState
    let stateStartedAt: Date
    let lastActivityAt: Date
    var lastProactiveAt: Date?
    var proactiveMessageCount: Int
    var proactiveEngageCount: Int
    var proactiveIgnoreCount: Int
    var moodDeclineDetected: Bool
    var consecutiveLowMoodDays: Int
    let updatedAt: Date

    /// Whether the user is responding well to proactive messages
    var proactiveEngagementRate: Double {
        guard proactiveMessageCount > 0 else { return 0 }
        return Double(proactiveEngageCount) / Double(proactiveMessageCount)
    }

    /// Whether we should back off from proactive messages
    var shouldBackOff: Bool {
        proactiveIgnoreCount >= 3
    }

    enum CodingKeys: String, CodingKey {
        case id
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
        case updatedAt = "updated_at"
    }
}

/// Proactive Intelligence settings for a user (extension of UserSettings)
struct ProactiveSettings: Codable, Equatable {
    var proactiveEnabled: Bool
    var proactiveMaxDaily: Int
    var proactiveTypesEnabled: [ProactiveTriggerType]
    var calendarIntegrationEnabled: Bool
    var weatherInsightsEnabled: Bool

    /// Default settings for new users
    static let `default` = ProactiveSettings(
        proactiveEnabled: true,
        proactiveMaxDaily: 2,
        proactiveTypesEnabled: ProactiveTriggerType.allCases,
        calendarIntegrationEnabled: false,
        weatherInsightsEnabled: false
    )

    enum CodingKeys: String, CodingKey {
        case proactiveEnabled = "proactive_enabled"
        case proactiveMaxDaily = "proactive_max_daily"
        case proactiveTypesEnabled = "proactive_types_enabled"
        case calendarIntegrationEnabled = "calendar_integration_enabled"
        case weatherInsightsEnabled = "weather_insights_enabled"
    }

    init(proactiveEnabled: Bool = true,
         proactiveMaxDaily: Int = 2,
         proactiveTypesEnabled: [ProactiveTriggerType] = ProactiveTriggerType.allCases,
         calendarIntegrationEnabled: Bool = false,
         weatherInsightsEnabled: Bool = false) {
        self.proactiveEnabled = proactiveEnabled
        self.proactiveMaxDaily = proactiveMaxDaily
        self.proactiveTypesEnabled = proactiveTypesEnabled
        self.calendarIntegrationEnabled = calendarIntegrationEnabled
        self.weatherInsightsEnabled = weatherInsightsEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        proactiveEnabled = try container.decodeIfPresent(Bool.self, forKey: .proactiveEnabled) ?? true
        proactiveMaxDaily = try container.decodeIfPresent(Int.self, forKey: .proactiveMaxDaily) ?? 2
        calendarIntegrationEnabled = try container.decodeIfPresent(Bool.self, forKey: .calendarIntegrationEnabled) ?? false
        weatherInsightsEnabled = try container.decodeIfPresent(Bool.self, forKey: .weatherInsightsEnabled) ?? false

        // Handle proactive_types_enabled which comes as string array from database
        if let typesArray = try container.decodeIfPresent([String].self, forKey: .proactiveTypesEnabled) {
            proactiveTypesEnabled = typesArray.compactMap { ProactiveTriggerType(rawValue: $0) }
        } else {
            proactiveTypesEnabled = ProactiveTriggerType.allCases
        }
    }
}

// MARK: - Live Experiences

/// Represents a scheduled live session (e.g., daily group meditation)
struct LiveSession: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let description: String?
    let sessionType: SessionType
    let scheduledStart: Date
    let scheduledEnd: Date
    let audioUrl: String?
    var participantCount: Int?

    /// Whether the session is currently live
    var isLive: Bool {
        let now = Date()
        return now >= scheduledStart && now <= scheduledEnd
    }

    /// Whether the session hasn't started yet
    var isUpcoming: Bool {
        Date() < scheduledStart
    }

    /// Human-readable time until session starts
    var startsIn: String? {
        guard isUpcoming else { return nil }
        let interval = scheduledStart.timeIntervalSinceNow
        if interval < 60 { return "Starting now" }
        if interval < 3600 { return "In \(Int(interval / 60)) min" }
        return "In \(Int(interval / 3600))h"
    }

    /// Duration of the session in minutes
    var durationMinutes: Int {
        Int(scheduledEnd.timeIntervalSince(scheduledStart) / 60)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case sessionType = "session_type"
        case scheduledStart = "scheduled_start"
        case scheduledEnd = "scheduled_end"
        case audioUrl = "audio_url"
        case participantCount = "participant_count"
    }
}

/// Types of live sessions
enum SessionType: String, Codable, CaseIterable {
    case breathing
    case meditation
    case bodyScan = "body_scan"

    var displayName: String {
        switch self {
        case .breathing: return "Breathing"
        case .meditation: return "Meditation"
        case .bodyScan: return "Body Scan"
        }
    }

    var icon: String {
        switch self {
        case .breathing: return "wind"
        case .meditation: return "brain.head.profile"
        case .bodyScan: return "figure.stand"
        }
    }
}

/// Database representation of live session for Supabase queries
struct DBLiveSession: Codable {
    let id: String
    let title: String
    let description: String?
    let sessionType: String
    let scheduledStart: Date
    let scheduledEnd: Date
    let audioUrl: String?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case sessionType = "session_type"
        case scheduledStart = "scheduled_start"
        case scheduledEnd = "scheduled_end"
        case audioUrl = "audio_url"
        case isActive = "is_active"
    }

    func toLiveSession() -> LiveSession {
        LiveSession(
            id: id,
            title: title,
            description: description,
            sessionType: SessionType(rawValue: sessionType) ?? .breathing,
            scheduledStart: scheduledStart,
            scheduledEnd: scheduledEnd,
            audioUrl: audioUrl,
            participantCount: nil
        )
    }
}

/// Represents a live room within a circle
struct CircleLiveRoom: Codable, Identifiable, Equatable {
    let id: String
    let circleId: String
    let createdBy: String
    let activityType: String
    let exerciseId: String?
    let title: String?
    let durationMinutes: Int
    let startedAt: Date
    let endsAt: Date
    var endedAt: Date?
    let status: RoomStatus
    var participants: [RoomParticipant]?

    // Joined data for display
    var circleName: String?
    var creatorName: String?

    /// Whether the room is still active
    var isActive: Bool {
        status == .active && Date() < endsAt
    }

    /// Seconds remaining until room ends
    var timeRemaining: TimeInterval {
        max(0, endsAt.timeIntervalSinceNow)
    }

    /// Formatted time remaining (e.g., "4:32")
    var timeRemainingFormatted: String {
        let minutes = Int(timeRemaining / 60)
        let seconds = Int(timeRemaining.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case createdBy = "created_by"
        case activityType = "activity_type"
        case exerciseId = "exercise_id"
        case title
        case durationMinutes = "duration_minutes"
        case startedAt = "started_at"
        case endsAt = "ends_at"
        case endedAt = "ended_at"
        case status
        case participants
        case circleName = "circle_name"
        case creatorName = "creator_name"
    }
}

/// Status of a live room
enum RoomStatus: String, Codable {
    case active
    case completed
    case cancelled
}

/// Represents a participant in a circle live room
struct RoomParticipant: Codable, Identifiable, Equatable {
    let id: String
    let roomId: String
    let userId: String
    let joinedAt: Date
    var leftAt: Date?
    var completed: Bool

    // Joined data
    var displayName: String?
    var isOnline: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
        case leftAt = "left_at"
        case completed
        case displayName = "display_name"
        case isOnline = "is_online"
    }
}

/// Database representation of circle live room
struct DBCircleLiveRoom: Codable {
    let id: String
    let circleId: String
    let createdBy: String
    let activityType: String
    let exerciseId: String?
    let title: String?
    let durationMinutes: Int
    let startedAt: Date
    let endsAt: Date
    var endedAt: Date?
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case createdBy = "created_by"
        case activityType = "activity_type"
        case exerciseId = "exercise_id"
        case title
        case durationMinutes = "duration_minutes"
        case startedAt = "started_at"
        case endsAt = "ends_at"
        case endedAt = "ended_at"
        case status
    }

    func toCircleLiveRoom() -> CircleLiveRoom {
        CircleLiveRoom(
            id: id,
            circleId: circleId,
            createdBy: createdBy,
            activityType: activityType,
            exerciseId: exerciseId,
            title: title,
            durationMinutes: durationMinutes,
            startedAt: startedAt,
            endsAt: endsAt,
            endedAt: endedAt,
            status: RoomStatus(rawValue: status) ?? .active,
            participants: nil,
            circleName: nil,
            creatorName: nil
        )
    }
}

/// Represents a buddy accountability window
struct BuddyQuestWindow: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let buddyRelationshipId: String
    let windowStartLocal: String  // "07:00:00"
    let windowEndLocal: String    // "08:00:00"
    let isActive: Bool

    /// Whether the window is currently open based on local time
    var isCurrentlyOpen: Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let now = formatter.string(from: Date())
        return now >= windowStartLocal && now <= windowEndLocal
    }

    /// Formatted window display (e.g., "7:00 AM - 8:00 AM")
    var windowDisplay: String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "HH:mm:ss"

        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "h:mm a"

        if let startDate = inputFormatter.date(from: windowStartLocal),
           let endDate = inputFormatter.date(from: windowEndLocal) {
            return "\(outputFormatter.string(from: startDate)) - \(outputFormatter.string(from: endDate))"
        }
        return "\(windowStartLocal) - \(windowEndLocal)"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case buddyRelationshipId = "buddy_relationship_id"
        case windowStartLocal = "window_start_local"
        case windowEndLocal = "window_end_local"
        case isActive = "is_active"
    }
}

/// Represents user presence status
struct UserPresence: Codable, Equatable {
    let userId: String
    var status: PresenceStatus
    let lastSeenAt: Date
    let currentActivity: String?

    // Joined data
    var displayName: String?
    var isOnline: Bool?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case status
        case lastSeenAt = "last_seen_at"
        case currentActivity = "current_activity"
        case displayName = "display_name"
        case isOnline = "is_online"
    }
}

/// Presence status values
enum PresenceStatus: String, Codable {
    case online
    case away
    case offline
}

/// Database representation of user presence
struct DBUserPresence: Codable {
    let userId: String
    let status: String
    let lastSeenAt: Date
    let currentActivity: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case status
        case lastSeenAt = "last_seen_at"
        case currentActivity = "current_activity"
    }

    func toPresence() -> UserPresence {
        UserPresence(
            userId: userId,
            status: PresenceStatus(rawValue: status) ?? .offline,
            lastSeenAt: lastSeenAt,
            currentActivity: currentActivity,
            displayName: nil,
            isOnline: nil
        )
    }
}

/// Result from joining a live session
struct JoinSessionResult: Codable {
    let session: LiveSession
    let participantCount: Int
    let audioUrl: String?

    enum CodingKeys: String, CodingKey {
        case session
        case participantCount = "participant_count"
        case audioUrl = "audio_url"
    }
}

/// Result from completing a live session
struct CompleteSessionResult: Codable {
    let success: Bool
    let xpAwarded: Int

    enum CodingKeys: String, CodingKey {
        case success
        case xpAwarded = "xp_awarded"
    }
}

/// Live session event types for Realtime subscriptions
enum LiveSessionEvent {
    case participantJoined(count: Int)
    case participantLeft(count: Int)
    case reaction(emoji: String)
    case sessionEnding(secondsRemaining: Int)
    case sessionEnded
}

/// Circle room event types for Realtime subscriptions
enum CircleRoomEvent {
    case memberJoined(userId: String, displayName: String)
    case memberLeft(userId: String)
    case encouragement(fromUserId: String, emoji: String)
    case timerSync(secondsRemaining: Int)
    case roomEnded
}

// MARK: - Creative Expression Models

/// Types of creative works
enum CreativeWorkType: String, Codable, CaseIterable {
    case aiArt = "ai_art"
    case drawing
    case voiceJournal = "voice_journal"
    case collage

    var displayName: String {
        switch self {
        case .aiArt: return "AI Art"
        case .drawing: return "Drawing"
        case .voiceJournal: return "Voice Journal"
        case .collage: return "Collage"
        }
    }

    var icon: String {
        switch self {
        case .aiArt: return "sparkles"
        case .drawing: return "paintbrush.pointed.fill"
        case .voiceJournal: return "waveform"
        case .collage: return "square.grid.2x2.fill"
        }
    }
}

/// Art generation styles
enum ArtStyle: String, Codable, CaseIterable {
    case watercolor
    case abstract
    case serene
    case vibrant
    case dreamy
    case minimalist
    case expressive

    var displayName: String {
        switch self {
        case .watercolor: return "Watercolor"
        case .abstract: return "Abstract"
        case .serene: return "Serene"
        case .vibrant: return "Vibrant"
        case .dreamy: return "Dreamy"
        case .minimalist: return "Minimalist"
        case .expressive: return "Expressive"
        }
    }

    var description: String {
        switch self {
        case .watercolor: return "Soft, flowing colors with delicate brushstrokes"
        case .abstract: return "Bold shapes and colors, modern aesthetic"
        case .serene: return "Peaceful scenes with calming atmosphere"
        case .vibrant: return "Bright, energetic colors full of joy"
        case .dreamy: return "Ethereal and magical qualities"
        case .minimalist: return "Clean lines and simple composition"
        case .expressive: return "Bold, emotional brushwork"
        }
    }

    var icon: String {
        switch self {
        case .watercolor: return "drop.fill"
        case .abstract: return "square.on.circle"
        case .serene: return "leaf.fill"
        case .vibrant: return "sparkles"
        case .dreamy: return "cloud.fill"
        case .minimalist: return "square"
        case .expressive: return "paintbrush.fill"
        }
    }
}

/// Transcription processing status
enum TranscriptionStatus: String, Codable {
    case pending
    case processing
    case completed
    case failed
}

/// A creative work created by the user
struct CreativeWork: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let workType: CreativeWorkType
    var title: String?
    var description: String?
    let storagePath: String?
    let generationPrompt: String?
    let artStyle: ArtStyle?
    let durationSeconds: Int?
    let transcription: String?
    let transcriptionStatus: TranscriptionStatus?
    var moodScore: Int?
    var moodTags: [String]?
    var isFavorite: Bool
    var isSharedToCircle: Bool
    let createdAt: Date
    let updatedAt: Date

    /// Full URL for the creative work image/audio
    var mediaUrl: URL? {
        guard let path = storagePath else { return nil }
        // Construct Supabase storage URL
        return URL(string: "\(SupabaseConfig.projectURL.absoluteString)/storage/v1/object/public/creative-works/\(path)")
    }

    /// Duration formatted as mm:ss
    var formattedDuration: String? {
        guard let seconds = durationSeconds else { return nil }
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

/// Emotion scores from voice journal analysis
struct EmotionScores: Codable, Equatable {
    var joy: Double
    var sadness: Double
    var anger: Double
    var fear: Double
    var surprise: Double
    var trust: Double
    var anticipation: Double
    var disgust: Double

    init(
        joy: Double = 0,
        sadness: Double = 0,
        anger: Double = 0,
        fear: Double = 0,
        surprise: Double = 0,
        trust: Double = 0,
        anticipation: Double = 0,
        disgust: Double = 0
    ) {
        self.joy = joy
        self.sadness = sadness
        self.anger = anger
        self.fear = fear
        self.surprise = surprise
        self.trust = trust
        self.anticipation = anticipation
        self.disgust = disgust
    }

    /// Returns the dominant emotion
    var dominantEmotion: String {
        let emotions: [(String, Double)] = [
            ("joy", joy),
            ("sadness", sadness),
            ("anger", anger),
            ("fear", fear),
            ("surprise", surprise),
            ("trust", trust),
            ("anticipation", anticipation),
            ("disgust", disgust)
        ]
        return emotions.max(by: { $0.1 < $1.1 })?.0 ?? "neutral"
    }

    /// Returns all emotions as a dictionary
    var asDictionary: [String: Double] {
        [
            "joy": joy,
            "sadness": sadness,
            "anger": anger,
            "fear": fear,
            "surprise": surprise,
            "trust": trust,
            "anticipation": anticipation,
            "disgust": disgust
        ]
    }
}

/// Tone analysis levels
enum ToneLevel: String, Codable {
    case low, medium, high
}

enum TonePace: String, Codable {
    case slow, moderate, fast
}

enum ToneConfidence: String, Codable {
    case uncertain, neutral, confident
}

enum ToneIntensity: String, Codable {
    case subdued, moderate, intense
}

/// Tone analysis from voice journal
struct ToneAnalysis: Codable, Equatable {
    var energy: ToneLevel
    var pace: TonePace
    var confidence: ToneConfidence
    var emotionalIntensity: ToneIntensity

    init(
        energy: ToneLevel = .medium,
        pace: TonePace = .moderate,
        confidence: ToneConfidence = .neutral,
        emotionalIntensity: ToneIntensity = .moderate
    ) {
        self.energy = energy
        self.pace = pace
        self.confidence = confidence
        self.emotionalIntensity = emotionalIntensity
    }
}

/// Voice journal analysis result
struct VoiceJournalAnalysis: Identifiable, Codable, Equatable {
    let id: String
    let creativeWorkId: String
    let fullTranscription: String?
    let overallSentiment: Double
    let emotions: EmotionScores
    let toneAnalysis: ToneAnalysis
    let keyThemes: [String]
    let keyQuotes: [String]
    let aiSummary: String?
    let reflectionPrompts: [String]
    let processedAt: Date?

    /// Sentiment as a descriptive string
    var sentimentDescription: String {
        if overallSentiment > 0.3 { return "Positive" }
        if overallSentiment < -0.3 { return "Difficult" }
        return "Balanced"
    }
}

/// Creative exercise types
enum CreativeExerciseType: String, Codable, CaseIterable {
    case drawing
    case collage
    case voice
    case aiArt = "ai_art"
    case mixed

    var displayName: String {
        switch self {
        case .drawing: return "Drawing"
        case .collage: return "Collage"
        case .voice: return "Voice"
        case .aiArt: return "AI Art"
        case .mixed: return "Mixed"
        }
    }

    var icon: String {
        switch self {
        case .drawing: return "paintbrush.pointed.fill"
        case .collage: return "square.grid.2x2.fill"
        case .voice: return "waveform"
        case .aiArt: return "sparkles"
        case .mixed: return "paintpalette.fill"
        }
    }
}

/// Creative exercise categories
enum CreativeExerciseCategory: String, Codable, CaseIterable {
    case emotionProcessing = "emotion_processing"
    case gratitude
    case selfDiscovery = "self_discovery"
    case stressRelief = "stress_relief"

    var displayName: String {
        switch self {
        case .emotionProcessing: return "Emotion Processing"
        case .gratitude: return "Gratitude"
        case .selfDiscovery: return "Self Discovery"
        case .stressRelief: return "Stress Relief"
        }
    }

    var icon: String {
        switch self {
        case .emotionProcessing: return "heart.text.square.fill"
        case .gratitude: return "heart.fill"
        case .selfDiscovery: return "person.fill.questionmark"
        case .stressRelief: return "leaf.fill"
        }
    }

    var color: Color {
        switch self {
        case .emotionProcessing: return .blue
        case .gratitude: return .pink
        case .selfDiscovery: return .purple
        case .stressRelief: return .green
        }
    }
}

/// Exercise difficulty levels
enum ExerciseDifficulty: String, Codable, CaseIterable {
    case beginner
    case intermediate
    case advanced

    var displayName: String {
        rawValue.capitalized
    }
}

/// A creative exercise/prompt
struct CreativeExercise: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let description: String
    let instructions: String
    let exerciseType: CreativeExerciseType
    let category: CreativeExerciseCategory
    let difficulty: ExerciseDifficulty
    let estimatedMinutes: Int
    let promptImageUrl: String?
    let isPremium: Bool
}

/// Creative quota information
struct CreativeQuota: Codable, Equatable {
    let aiArtCount: Int
    let aiArtLimit: Int
    let voiceMinutesUsed: Int
    let voiceMinutesLimit: Int
    let isPremium: Bool

    var aiArtRemaining: Int {
        max(0, aiArtLimit - aiArtCount)
    }

    var voiceMinutesRemaining: Int {
        max(0, voiceMinutesLimit - voiceMinutesUsed)
    }

    var aiArtQuotaExceeded: Bool {
        aiArtCount >= aiArtLimit
    }

    var voiceQuotaExceeded: Bool {
        voiceMinutesUsed >= voiceMinutesLimit
    }
}

/// Drawing tool types
enum DrawingTool: String, CaseIterable, Codable {
    case pen
    case marker
    case watercolor
    case eraser

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .pen: return "pencil"
        case .marker: return "highlighter"
        case .watercolor: return "paintbrush"
        case .eraser: return "eraser"
        }
    }
}

/// Drawing stroke for canvas
struct DrawingStroke: Codable, Equatable, Identifiable {
    let id: UUID
    var points: [CGPoint]
    var color: String // Hex color
    var lineWidth: CGFloat
    var tool: DrawingTool
    var opacity: Double

    init(id: UUID = UUID(), points: [CGPoint] = [], color: String = "#000000", lineWidth: CGFloat = 3, tool: DrawingTool = .pen, opacity: Double = 1.0) {
        self.id = id
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.tool = tool
        self.opacity = opacity
    }

    enum CodingKeys: String, CodingKey {
        case id, points, color, lineWidth, tool, opacity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        color = try container.decode(String.self, forKey: .color)
        lineWidth = try container.decode(CGFloat.self, forKey: .lineWidth)
        tool = try container.decodeIfPresent(DrawingTool.self, forKey: .tool) ?? .pen
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0

        // Decode points as array of arrays
        let pointArrays = try container.decode([[CGFloat]].self, forKey: .points)
        points = pointArrays.compactMap { arr in
            guard arr.count == 2 else { return nil }
            return CGPoint(x: arr[0], y: arr[1])
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(color, forKey: .color)
        try container.encode(lineWidth, forKey: .lineWidth)
        try container.encode(tool, forKey: .tool)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(points.map { [$0.x, $0.y] }, forKey: .points)
    }
}

/// AI Art generation request
struct GenerateArtRequest: Codable {
    let prompt: String
    let style: String?
    let moodScore: Int?
    let moodTags: [String]?
}

/// AI Art generation response
struct GenerateArtResponse: Codable {
    let success: Bool
    let generationId: String?
    let creativeWorkId: String?
    let imageUrl: String?
    let prompt: String?
    let enhancedPrompt: String?
    let style: String?
    let error: String?
    let quotaExceeded: Bool?
}

/// Voice journal analysis request
struct AnalyzeVoiceRequest: Codable {
    let creativeWorkId: String
    let audioUrl: String?
    let durationSeconds: Int
}

/// Voice journal analysis response
struct AnalyzeVoiceResponse: Codable {
    let success: Bool
    let creativeWorkId: String?
    let analysis: VoiceAnalysisResult?
    let error: String?
    let quotaExceeded: Bool?
}

struct VoiceAnalysisResult: Codable {
    let sentiment: Double
    let emotions: EmotionScores
    let toneAnalysis: ToneAnalysis
    let keyThemes: [String]
    let keyQuotes: [String]
    let summary: String
    let reflectionPrompts: [String]
}

// MARK: - Medications

struct Medication: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let name: String
    let dosage: String?
    let purpose: String?
    let color: String?
    let icon: MedicationIcon
    let frequency: MedicationFrequency
    let timesPerDay: Int
    let scheduledTimes: [Date]
    let daysOfWeek: [Int]?
    let reminderEnabled: Bool
    let reminderSound: String
    let notificationText: String?
    let useGenericNotification: Bool
    let supplyCount: Int?
    let refillReminderCount: Int?
    let isActive: Bool
    let archivedAt: Date?
    let startedAt: Date
    let endedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case dosage
        case purpose
        case color
        case icon
        case frequency
        case timesPerDay = "times_per_day"
        case scheduledTimes = "scheduled_times"
        case daysOfWeek = "days_of_week"
        case reminderEnabled = "reminder_enabled"
        case reminderSound = "reminder_sound"
        case notificationText = "notification_text"
        case useGenericNotification = "use_generic_notification"
        case supplyCount = "supply_count"
        case refillReminderCount = "refill_reminder_count"
        case isActive = "is_active"
        case archivedAt = "archived_at"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum MedicationIcon: String, Codable, CaseIterable {
    case pill
    case capsule
    case liquid
    case injection
    case patch
    case drops

    var systemImage: String {
        switch self {
        case .pill: return "pills.fill"
        case .capsule: return "capsule.fill"
        case .liquid: return "drop.fill"
        case .injection: return "syringe.fill"
        case .patch: return "bandage.fill"
        case .drops: return "drop.triangle.fill"
        }
    }
}

enum MedicationFrequency: String, Codable {
    case daily
    case twiceDaily = "twice_daily"
    case threeTimesDaily = "three_times_daily"
    case weekly
    case asNeeded = "as_needed"
    case custom

    var description: String {
        switch self {
        case .daily: return "Once daily"
        case .twiceDaily: return "Twice daily"
        case .threeTimesDaily: return "Three times daily"
        case .weekly: return "Weekly"
        case .asNeeded: return "As needed"
        case .custom: return "Custom schedule"
        }
    }
}

struct MedicationLog: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let medicationId: UUID
    let scheduledAt: Date
    let status: MedicationStatus
    let loggedAt: Date?
    let skipReason: String?
    let notes: String?
    let sideEffects: [String]?
    let moodAtTime: Int?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case medicationId = "medication_id"
        case scheduledAt = "scheduled_at"
        case status
        case loggedAt = "logged_at"
        case skipReason = "skip_reason"
        case notes
        case sideEffects = "side_effects"
        case moodAtTime = "mood_at_time"
        case createdAt = "created_at"
    }
}

enum MedicationStatus: String, Codable {
    case pending
    case taken
    case skipped
    case late
}

struct ScheduledMedication: Identifiable {
    let id: UUID
    let medication: Medication
    let scheduledAt: Date
    let status: MedicationStatus
    let log: MedicationLog?
}

struct MedicationMoodCorrelation: Codable {
    let averageMoodWhenAdherent: Double
    let averageMoodWhenNotAdherent: Double
    let adherentDays: Int
    let nonAdherentDays: Int

    var moodDifference: Double {
        averageMoodWhenAdherent - averageMoodWhenNotAdherent
    }

    var insight: String {
        if moodDifference > 0.5 {
            return "Your mood tends to be better on days you take your medication consistently."
        } else if moodDifference < -0.5 {
            return "Your mood may be affected by your medication. Consider talking to your doctor."
        } else {
            return "Your mood appears stable regardless of medication adherence."
        }
    }
}

// MARK: - Quest Arcs

/// A multi-day quest program with themed journey and milestones
struct QuestArc: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let description: String
    let category: String
    let durationDays: Int
    let difficultyLevel: String
    let isPremium: Bool
    let milestoneDays: [Int]
    let iconName: String?
    let stepCount: Int
    var userEnrolled: Bool
    var userCompleted: Bool
    var userProgress: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case title, description, category
        case durationDays = "duration_days"
        case difficultyLevel = "difficulty_level"
        case isPremium = "is_premium"
        case milestoneDays = "milestone_days"
        case iconName = "icon_name"
        case stepCount = "step_count"
        case userEnrolled = "user_enrolled"
        case userCompleted = "user_completed"
        case userProgress = "user_progress"
    }

    var progressPercentage: Double {
        guard let progress = userProgress, durationDays > 0 else { return 0 }
        return Double(progress) / Double(durationDays)
    }

    var categoryIcon: String {
        if let iconName = iconName, !iconName.isEmpty {
            return iconName
        }
        switch category {
        case "stress": return "brain.head.profile"
        case "sleep": return "moon.zzz.fill"
        case "confidence": return "star.fill"
        case "focus": return "scope"
        case "resilience": return "shield.fill"
        default: return "sparkles"
        }
    }

    var categoryColor: Color {
        switch category {
        case "stress": return .purple
        case "sleep": return .indigo
        case "confidence": return .orange
        case "focus": return .blue
        case "resilience": return .green
        default: return .gray
        }
    }

    var difficultyLabel: String {
        switch difficultyLevel {
        case "easy": return "Beginner"
        case "medium": return "Intermediate"
        case "hard": return "Advanced"
        default: return difficultyLevel.capitalized
        }
    }

    var daysRemaining: Int {
        guard let progress = userProgress else { return durationDays }
        return max(0, durationDays - progress)
    }
}

/// A single day's quest within an arc
struct QuestArcStep: Codable, Identifiable, Equatable {
    let id: UUID
    let arcId: UUID
    let dayNumber: Int
    let questTemplateId: UUID
    let customTitle: String?
    let customDescription: String?
    let isMilestone: Bool
    let milestoneXpBonus: Int

    enum CodingKeys: String, CodingKey {
        case id
        case arcId = "arc_id"
        case dayNumber = "day_number"
        case questTemplateId = "quest_template_id"
        case customTitle = "custom_title"
        case customDescription = "custom_description"
        case isMilestone = "is_milestone"
        case milestoneXpBonus = "milestone_xp_bonus"
    }
}

/// User's enrollment in a quest arc
struct UserQuestArc: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let arcId: UUID
    var currentDay: Int
    var status: ArcStatus
    let startedAt: Date
    var pausedAt: Date?
    var completedAt: Date?
    var abandonedAt: Date?
    var lastQuestCompletedAt: Date?
    let snapshotDurationDays: Int
    let snapshotMilestoneDays: [Int]

    // Joined data from API
    var arc: QuestArc?

    enum ArcStatus: String, Codable {
        case active
        case paused
        case completed
        case abandoned
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case arcId = "arc_id"
        case currentDay = "current_day"
        case status
        case startedAt = "started_at"
        case pausedAt = "paused_at"
        case completedAt = "completed_at"
        case abandonedAt = "abandoned_at"
        case lastQuestCompletedAt = "last_quest_completed_at"
        case snapshotDurationDays = "snapshot_duration_days"
        case snapshotMilestoneDays = "snapshot_milestone_days"
        case arc = "quest_arcs"
    }

    var progressPercentage: Double {
        guard snapshotDurationDays > 0 else { return 0 }
        return Double(currentDay) / Double(snapshotDurationDays)
    }

    var daysRemaining: Int {
        return max(0, snapshotDurationDays - currentDay)
    }

    var isExpired: Bool {
        guard status == .paused, let pausedAt = pausedAt else { return false }
        let daysSincePause = Calendar.current.dateComponents([.day], from: pausedAt, to: Date()).day ?? 0
        return daysSincePause > QuestArcConstants.pauseExpirationDays
    }

    var expiresAt: Date? {
        guard status == .paused, let pausedAt = pausedAt else { return nil }
        return Calendar.current.date(byAdding: .day, value: QuestArcConstants.pauseExpirationDays, to: pausedAt)
    }

    var nextMilestone: Int? {
        snapshotMilestoneDays.first { $0 > currentDay }
    }

    var daysToNextMilestone: Int? {
        guard let next = nextMilestone else { return nil }
        return next - currentDay
    }
    
    // MARK: - Computed Properties for UI
    
    /// Alias for consistency with views (nextMilestone already exists)
    var nextMilestoneDay: Int? {
        nextMilestone
    }
    
    /// Returns array of completed milestone days
    var completedMilestones: [Int] {
        snapshotMilestoneDays.filter { $0 <= currentDay }
    }
    
    /// Convenience accessor for the joined QuestArc (matches property name in CodingKeys)
    var questArc: QuestArc? {
        arc
    }
}

// MARK: - Quest Arc API Response Types

struct GetQuestArcsResponse: Codable {
    let arcs: [QuestArc]
}

struct StartQuestArcResponse: Codable {
    let success: Bool
    let userArcId: String?
    let arc: QuestArc?
    let firstQuestTemplate: QuestTemplate?
    let error: String?
    let code: String?
    let paywallContext: PaywallContext?
    let currentArc: CurrentArcInfo?

    struct PaywallContext: Codable {
        let arcTitle: String
        let arcDescription: String
        let benefits: [String]
    }

    struct CurrentArcInfo: Codable {
        let id: String
        let title: String
        let currentDay: Int
    }
}

struct PauseQuestArcResponse: Codable {
    let success: Bool
    let pausedAt: String
    let currentDay: Int
    let expiresAt: String
}

struct ResumeQuestArcResponse: Codable {
    let success: Bool
    let currentDay: Int
    let nextQuestTemplate: QuestTemplate?
}

struct ExitQuestArcResponse: Codable {
    let success: Bool
    let abandonedAt: String
}

// MARK: - Progress Stories

/// Weekly story containing 3-5 visual story cards for progress recaps
struct WeeklyStory: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let weekStart: String // "YYYY-MM-DD" format (Monday)
    let cards: [StoryCard]
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case weekStart = "week_start"
        case cards
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Individual story card with visual variant and type-specific data
struct StoryCard: Codable, Identifiable, Equatable {
    let id: UUID
    let cardType: StoryCardType
    let variant: StoryCardVariant
    let data: StoryCardData
    let generatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case cardType = "cardType"
        case variant
        case data
        case generatedAt = "generatedAt"
    }
}

/// Card types for story cards
enum StoryCardType: String, Codable, Equatable {
    case streak
    case mood
    case exercise
    case quest
    case insight
    case minimal
    case milestone
    
    /// Display name for the card type
    var displayName: String {
        switch self {
        case .streak: return "Streak"
        case .mood: return "Mood"
        case .exercise: return "Exercise"
        case .quest: return "Quest"
        case .insight: return "Insight"
        case .minimal: return "Encouragement"
        case .milestone: return "Milestone"
        }
    }
    
    /// SF Symbol icon for the card type
    var iconName: String {
        switch self {
        case .streak: return "flame.fill"
        case .mood: return "face.smiling"
        case .exercise: return "figure.run"
        case .quest: return "checkmark.circle.fill"
        case .insight: return "lightbulb.fill"
        case .minimal: return "sparkles"
        case .milestone: return "trophy.fill"
        }
    }
}

/// Visual variants for story cards
enum StoryCardVariant: String, Codable, Equatable {
    case `default`
    case celebration
    case encouragement
    case milestone
    
    /// Background gradient colors for the variant
    var gradientColors: [Color] {
        switch self {
        case .default:
            return [Color.blue.opacity(0.8), Color.purple.opacity(0.8)]
        case .celebration:
            return [Color.orange, Color.pink]
        case .encouragement:
            return [Color.teal, Color.blue]
        case .milestone:
            return [Color.yellow, Color.orange]
        }
    }
}

/// Unified card data structure that handles all card types
struct StoryCardData: Codable, Equatable {
    // Common fields
    let headline: String
    let message: String
    
    // Stat fields (optional)
    let stat: String?
    let statLabel: String?
    
    // Icon field for minimal cards
    let icon: String?
    
    // Call to action (for minimal cards)
    let callToAction: String?
    
    // Streak-specific
    let streakDays: Int?
    
    // Mood-specific
    let trend: String?
    let checkinCount: Int?
    let moodMin: Double?
    let moodMax: Double?
    
    // Exercise-specific
    let exerciseCount: Int?
    let exerciseMinutes: Int?
    
    // Quest-specific
    let questCount: Int?
    
    // Insight-specific
    let aiGenerated: Bool?
    
    // Milestone-specific
    let milestoneType: String?
}

/// Response from generate-weekly-story Edge Function
struct GenerateWeeklyStoryResponse: Codable {
    let success: Bool
    let userId: UUID
    let weekStart: String
    let cards: [StoryCard]
    let generatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case success
        case userId = "userId"
        case weekStart = "weekStart"
        case cards
        case generatedAt = "generatedAt"
    }
}

/// Error codes from generate-weekly-story Edge Function
enum StoryGenerationError: String, Error {
    case unauthorized = "UNAUTHORIZED"
    case invalidToken = "INVALID_TOKEN"
    case missingWeekStart = "MISSING_WEEK_START"
    case invalidDateFormat = "INVALID_DATE_FORMAT"
    case notMonday = "NOT_MONDAY"
    case futureDate = "FUTURE_DATE"
    case internalError = "INTERNAL_ERROR"
    
    var localizedDescription: String {
        switch self {
        case .unauthorized, .invalidToken:
            return "Please sign in again to view your story."
        case .missingWeekStart:
            return "Week start date is required."
        case .invalidDateFormat:
            return "Invalid date format."
        case .notMonday:
            return "Week must start on Monday."
        case .futureDate:
            return "Cannot generate story for future weeks."
        case .internalError:
            return "Unable to generate story. Please try again."
        }
    }
}

/// Helper to get the Monday of a given week
extension Date {
    /// Returns the Monday of the week containing this date
    var weekStartMonday: Date {
        let calendar = Calendar(identifier: .iso8601)
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components) ?? self
    }
    
    /// Returns the week start as a string in "YYYY-MM-DD" format
    var weekStartString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: weekStartMonday)
    }
}

// MARK: - Quest Arc Models
// (Moved to separate file: QuestArcModels.swift)

// MARK: - Safety Plan Models

/// Represents a user's personal safety plan
struct SafetyPlan: Codable, Equatable {
    let id: UUID
    let userId: UUID
    let version: Int
    let payload: SafetyPlanPayload
    let allowAiReference: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, version, payload
        case userId = "user_id"
        case allowAiReference = "allow_ai_reference"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// The content of a safety plan (JSONB payload)
struct SafetyPlanPayload: Codable, Equatable {
    var warningSigns: [SafetyPlanItem]
    var coping: [CopingStrategy]
    var contacts: [TrustedContact]
    var resources: [ProfessionalResource]
    var environmentSteps: [SafetyPlanItem]
    var anchors: [SafetyPlanItem]

    init(
        warningSigns: [SafetyPlanItem] = [],
        coping: [CopingStrategy] = [],
        contacts: [TrustedContact] = [],
        resources: [ProfessionalResource] = [],
        environmentSteps: [SafetyPlanItem] = [],
        anchors: [SafetyPlanItem] = []
    ) {
        self.warningSigns = warningSigns
        self.coping = coping
        self.contacts = contacts
        self.resources = resources
        self.environmentSteps = environmentSteps
        self.anchors = anchors
    }

    static var empty: SafetyPlanPayload {
        SafetyPlanPayload()
    }
}

/// Offline cache payload for safety plan access
struct SafetyPlanCachePayload: Codable, Equatable {
    let payload: SafetyPlanPayload
    let settings: SafetyPlanSettings
    let version: Int
    let cachedAt: Date
    let expiresAt: Date

    var isExpired: Bool {
        Date() > expiresAt
    }
}

/// A single item in the safety plan
struct SafetyPlanItem: Codable, Identifiable, Equatable {
    var id: String
    var text: String
    var isCustom: Bool
    var order: Int
    var isFavorite: Bool

    init(id: String = UUID().uuidString, text: String, isCustom: Bool = false, order: Int = 0, isFavorite: Bool = false) {
        self.id = id
        self.text = text
        self.isCustom = isCustom
        self.order = order
        self.isFavorite = isFavorite
    }
}

/// A coping strategy that can link to in-app exercises
struct CopingStrategy: Codable, Identifiable, Equatable {
    var id: String
    var type: CopingStrategyType
    var exerciseId: String?
    var label: String
    var duration: Int?
    var category: CopingCategory
    var isFavorite: Bool
    var order: Int

    enum CodingKeys: String, CodingKey {
        case id, type, label, duration, category, order
        case exerciseId = "exercise_id"
        case isFavorite = "is_favorite"
    }

    init(
        id: String = UUID().uuidString,
        type: CopingStrategyType,
        exerciseId: String? = nil,
        label: String,
        duration: Int? = nil,
        category: CopingCategory,
        isFavorite: Bool = false,
        order: Int = 0
    ) {
        self.id = id
        self.type = type
        self.exerciseId = exerciseId
        self.label = label
        self.duration = duration
        self.category = category
        self.isFavorite = isFavorite
        self.order = order
    }

    /// Creates a custom coping strategy
    static func custom(label: String, category: CopingCategory, isFavorite: Bool = false) -> CopingStrategy {
        CopingStrategy(type: .custom, label: label, category: category, isFavorite: isFavorite)
    }
}

enum CopingStrategyType: String, Codable {
    case exercise
    case custom
}

enum CopingCategory: String, Codable, CaseIterable {
    case breathing
    case meditation
    case grounding
    case journaling
    case movement
    case custom

    var displayName: String {
        switch self {
        case .breathing: return "Breathing"
        case .meditation: return "Meditation"
        case .grounding: return "Grounding"
        case .journaling: return "Journaling"
        case .movement: return "Movement"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .breathing: return "wind"
        case .meditation: return "leaf"
        case .grounding: return "hand.raised"
        case .journaling: return "pencil"
        case .movement: return "figure.walk"
        case .custom: return "star"
        }
    }
}

/// A trusted contact for the safety plan
struct TrustedContact: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var phone: String
    var relationship: TrustedContactRelationship
    var preferredMethod: ContactMethod
    var whatToSay: String?
    var isPrimary: Bool
    var order: Int

    enum CodingKeys: String, CodingKey {
        case id, name, phone, relationship, order
        case preferredMethod = "preferred_method"
        case whatToSay = "what_to_say"
        case isPrimary = "is_primary"
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        phone: String,
        relationship: TrustedContactRelationship,
        preferredMethod: ContactMethod = .call,
        whatToSay: String? = nil,
        isPrimary: Bool = false,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.phone = phone
        self.relationship = relationship
        self.preferredMethod = preferredMethod
        self.whatToSay = whatToSay
        self.isPrimary = isPrimary
        self.order = order
    }

    /// Returns the phone number formatted for display
    var formattedPhone: String {
        phone
    }

    /// Checks if phone is valid E.164 format
    var isValidPhone: Bool {
        phone.hasPrefix("+") && phone.count >= 10
    }
}

enum TrustedContactRelationship: String, Codable, CaseIterable {
    case friend
    case family
    case partner
    case therapist
    case other

    var displayName: String {
        switch self {
        case .friend: return "Friend"
        case .family: return "Family"
        case .partner: return "Partner"
        case .therapist: return "Therapist"
        case .other: return "Other"
        }
    }
}

enum ContactMethod: String, Codable {
    case call
    case text

    var displayName: String {
        switch self {
        case .call: return "Call"
        case .text: return "Text"
        }
    }

    var icon: String {
        switch self {
        case .call: return "phone.fill"
        case .text: return "message.fill"
        }
    }
}

/// A professional resource (crisis hotline or therapist)
struct ProfessionalResource: Codable, Identifiable, Equatable {
    var id: String
    var type: ProfessionalResourceType
    var name: String
    var phone: String?
    var url: String?
    var country: String?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id, type, name, phone, url, country, notes
    }

    init(
        id: String = UUID().uuidString,
        type: ProfessionalResourceType,
        name: String,
        phone: String? = nil,
        url: String? = nil,
        country: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.phone = phone
        self.url = url
        self.country = country
        self.notes = notes
    }
}

enum ProfessionalResourceType: String, Codable {
    case hotline
    case therapist
    case crisisLine = "crisis-line"
    case custom

    var displayName: String {
        switch self {
        case .hotline: return "Crisis Hotline"
        case .therapist: return "Therapist"
        case .crisisLine: return "Crisis Line"
        case .custom: return "Custom"
        }
    }
}

/// Safety plan settings
struct SafetyPlanSettings: Codable, Equatable {
    var allowAiReference: Bool
    var pinnedToQuickActions: Bool

    enum CodingKeys: String, CodingKey {
        case allowAiReference = "allow_ai_reference"
        case pinnedToQuickActions = "pinned_to_quick_actions"
    }

    init(allowAiReference: Bool = false, pinnedToQuickActions: Bool = false) {
        self.allowAiReference = allowAiReference
        self.pinnedToQuickActions = pinnedToQuickActions
    }

    static var `default`: SafetyPlanSettings {
        SafetyPlanSettings()
    }
}

/// Request body for manage-safety-plan Edge Function
struct SafetyPlanRequest: Codable {
    let operation: SafetyPlanOperation
    let payload: SafetyPlanPayload?
    let settings: SafetyPlanSettings?

    enum CodingKeys: String, CodingKey {
        case operation, payload, settings
    }

    init(operation: SafetyPlanOperation, payload: SafetyPlanPayload? = nil, settings: SafetyPlanSettings? = nil) {
        self.operation = operation
        self.payload = payload
        self.settings = settings
    }

    static func get() -> SafetyPlanRequest {
        SafetyPlanRequest(operation: .get)
    }

    static func create(payload: SafetyPlanPayload) -> SafetyPlanRequest {
        SafetyPlanRequest(operation: .create, payload: payload)
    }

    static func update(payload: SafetyPlanPayload) -> SafetyPlanRequest {
        SafetyPlanRequest(operation: .update, payload: payload)
    }

    static func delete() -> SafetyPlanRequest {
        SafetyPlanRequest(operation: .delete)
    }

    static func updateSettings(_ settings: SafetyPlanSettings) -> SafetyPlanRequest {
        SafetyPlanRequest(operation: .update, payload: nil, settings: settings)
    }
}

enum SafetyPlanOperation: String, Codable {
    case get
    case create
    case update
    case delete
}

/// Response from manage-safety-plan Edge Function
struct SafetyPlanResponse: Codable {
    let success: Bool
    let data: SafetyPlanData?
    let error: SafetyPlanError?

    struct SafetyPlanData: Codable {
        let id: UUID
        let version: Int
        let payload: SafetyPlanPayload
        let settings: SafetyPlanSettings
        let createdAt: String
        let updatedAt: String

        enum CodingKeys: String, CodingKey {
            case id, version, payload, settings
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    struct SafetyPlanError: Codable {
        let code: String
        let message: String
    }
}

// MARK: - AI Coaching Modes

/// Conversation mode for AI coaching
enum ConversationMode: String, Codable, CaseIterable, Identifiable {
    case reflect = "reflect"       // Guided journaling, emotional exploration
    case plan = "plan"            // Action-oriented, goal-focused
    case reframe = "reframe"      // Cognitive restructuring, perspective shift

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reflect: return "Reflect"
        case .plan: return "Plan"
        case .reframe: return "Reframe"
        }
    }

    var shortDescription: String {
        switch self {
        case .reflect:
            return "Explore your thoughts and feelings"
        case .plan:
            return "Take action toward your goals"
        case .reframe:
            return "Shift your perspective"
        }
    }

    var icon: String {
        switch self {
        case .reflect: return "heart.text.square"
        case .plan: return "checkmark.circle"
        case .reframe: return "arrow.triangle.2.circlepath"
        }
    }

    var color: String {
        switch self {
        case .reflect: return "purple"
        case .plan: return "blue"
        case .reframe: return "orange"
        }
    }

    var defaultPrompt: String {
        switch self {
        case .reflect:
            return "I'm here to listen without judgment. What's on your mind today?"
        case .plan:
            return "Let's work together on some actionable steps. What would you like to accomplish?"
        case .reframe:
            return "Let's explore different perspectives together. What's a situation you'd like to look at differently?"
        }
    }

    var exampleTopic: String {
        switch self {
        case .reflect: return "How has your day been affecting you emotionally?"
        case .plan: return "What's one small step you could take toward a goal?"
        case .reframe: return "Let's reframe: What would you tell a friend in this situation?"
        }
    }
}

/// Type of cognitive distortion for thought records
enum CognitiveDistortion: String, Codable, CaseIterable, Identifiable {
    case allOrNothing = "all_or_nothing"           // Black or white thinking
    case catrophizing = "catrophizing"             // Magnifying negatives, minimizing positives
    case emotionalReasoning = "emotional_reasoning" // Assuming feelings reflect reality
    case mindReading = "mind_reading"              // Assuming others' thoughts
    case overgeneralization = "overgeneralization" // Single event = always happens
    case personalization = "personalization"       // Taking undue responsibility
    case shouldStatements = "should_statements"    // Rigid rules about how things "should" be
    case fortuneTelling = "fortune_telling"        // Predicting negative outcomes
    case labeling = "labeling"                     // Global labels instead of behavior
    case discountingPositives = "discounting_positives" // Dismissing positive experiences
    case jumpingToConclusions = "jumping_to_conclusions" // Drawing conclusions without evidence

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allOrNothing: return "All-or-Nothing Thinking"
        case .catrophizing: return "Catastrophizing"
        case .emotionalReasoning: return "Emotional Reasoning"
        case .mindReading: return "Mind Reading"
        case .overgeneralization: return "Overgeneralization"
        case .personalization: return "Personalization"
        case .shouldStatements: return "Should Statements"
        case .fortuneTelling: return "Fortune Telling"
        case .labeling: return "Labeling"
        case .discountingPositives: return "Discounting Positives"
        case .jumpingToConclusions: return "Jumping to Conclusions"
        }
    }

    var description: String {
        switch self {
        case .allOrNothing:
            return "Seeing things in black and white categories"
        case .catrophizing:
            return "Expecting the worst possible outcome"
        case .emotionalReasoning:
            return "Believing something is true because it feels true"
        case .mindReading:
            return "Assuming you know what others are thinking"
        case .overgeneralization:
            return "Viewing negative events as never-ending patterns"
        case .personalization:
            return "Blaming yourself for things outside your control"
        case .shouldStatements:
            return "Rigid rules about how things 'should' be"
        case .fortuneTelling:
            return "Predicting negative outcomes before they happen"
        case .labeling:
            return "Assigning global labels to yourself and others"
        case .discountingPositives:
            return "Dismissing positive experiences"
        case .jumpingToConclusions:
            return "Making negative interpretations without evidence"
        }
    }

    var questionToChallenge: String {
        switch self {
        case .allOrNothing:
            return "Are there any shades of gray in this situation?"
        case .catrophizing:
            return "What's the actual evidence for the worst-case scenario?"
        case .emotionalReasoning:
            return "How would you describe this situation to a neutral observer?"
        case .mindReading:
            return "What facts do you have about what others are thinking?"
        case .overgeneralization:
            return "Is this situation truly representative of all similar situations?"
        case .personalization:
            return "What factors outside your control contributed to this?"
        case .shouldStatements:
            return "Where did this 'should' come from? Is it truly a rule you must follow?"
        case .fortuneTelling:
            return "What's more likely to happen, and what evidence supports that?"
        case .labeling:
            return "Can you describe the behavior without attaching a global label?"
        case .discountingPositives:
            return "What would you tell a friend who achieved this?"
        case .jumpingToConclusions:
            return "What additional information would help you see this more clearly?"
        }
    }
}

/// Represents a thought record entry (ABC format for cognitive restructuring)
struct ThoughtRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let conversationId: UUID?
    let createdAt: Date
    let updatedAt: Date

    // Activating event - What happened or what was the situation
    let activatingEvent: String

    // Beliefs - What thoughts automatically came up
    let automaticThoughts: [String]

    // Consequences - How you felt and behaved
    let emotions: [EmotionIntensity]
    let physicalSensations: String?
    let behaviors: String?

    // Analysis
    let identifiedDistortions: [CognitiveDistortion]
    let evidenceForThoughts: String?
    let evidenceAgainstThoughts: String?

    // Reframing
    let balancedThought: String?
    let alternativePerspective: String?

    // Outcome
    let emotionAfterReframing: [EmotionIntensity]?
    let lessonLearned: String?
    let isCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case conversationId = "conversation_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case activatingEvent = "activating_event"
        case automaticThoughts = "automatic_thoughts"
        case emotions
        case physicalSensations = "physical_sensations"
        case behaviors
        case identifiedDistortions = "identified_distortions"
        case evidenceForThoughts = "evidence_for_thoughts"
        case evidenceAgainstThoughts = "evidence_against_thoughts"
        case balancedThought = "balanced_thought"
        case alternativePerspective = "alternative_perspective"
        case emotionAfterReframing = "emotion_after_reframing"
        case lessonLearned = "lesson_learned"
        case isCompleted = "is_completed"
    }
}

/// Intensity level for emotions in thought records
enum EmotionIntensity: String, Codable, CaseIterable, Identifiable {
    case low = "low"
    case medium = "medium"
    case high = "high"

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    var emoji: String {
        switch self {
        case .low: return "🟢"
        case .medium: return "🟡"
        case .high: return "🔴"
        }
    }
}

/// AI-suggested quest based on conversation context
struct AISuggestedQuest: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let conversationId: UUID?
    let suggestedQuestTemplateId: UUID?

    let title: String
    let description: String
    let category: QuestType
    let difficulty: Int // 1-5
    let estimatedMinutes: Int

    let rationale: String  // Why this quest is suggested based on conversation
    let relatedThoughts: [UUID]?  // Thought record IDs this relates to

    let expiresAt: Date?
    let isAccepted: Bool?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case conversationId = "conversation_id"
        case suggestedQuestTemplateId = "suggested_quest_template_id"
        case title, description, category, difficulty
        case estimatedMinutes = "estimated_minutes"
        case rationale
        case relatedThoughts = "related_thoughts"
        case expiresAt = "expires_at"
        case isAccepted = "is_accepted"
        case createdAt = "created_at"
    }
}

/// User's preferred default coaching mode
struct CoachingModePreferences: Codable, Equatable {
    let userId: UUID
    var defaultMode: ConversationMode?
    var preferredTone: AITone?
    var reflectionPromptsEnabled: Bool
    var reframeRemindersEnabled: Bool
    var weeklyReflectionDay: Int?  // 1-7 (Monday = 1)
    var weeklyReflectionTime: String?  // HH:MM format

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case defaultMode = "default_mode"
        case preferredTone = "preferred_tone"
        case reflectionPromptsEnabled = "reflection_prompts_enabled"
        case reframeRemindersEnabled = "reframe_reminders_enabled"
        case weeklyReflectionDay = "weekly_reflection_day"
        case weeklyReflectionTime = "weekly_reflection_time"
    }

    static var `default`: CoachingModePreferences {
        CoachingModePreferences(
            userId: UUID(),
            defaultMode: nil,
            preferredTone: nil,
            reflectionPromptsEnabled: true,
            reframeRemindersEnabled: true,
            weeklyReflectionDay: nil,
            weeklyReflectionTime: nil
        )
    }
}

/// Request body for AI coaching edge functions
struct CoachingModeRequest: Codable {
    let operation: CoachingModeOperation
    let mode: ConversationMode?
    let thoughtRecord: ThoughtRecord?
    let preferences: CoachingModePreferences?

    enum CodingKeys: String, CodingKey {
        case operation, mode
        case thoughtRecord = "thought_record"
        case preferences
    }

    init(operation: CoachingModeOperation, mode: ConversationMode? = nil, thoughtRecord: ThoughtRecord? = nil, preferences: CoachingModePreferences? = nil) {
        self.operation = operation
        self.mode = mode
        self.thoughtRecord = thoughtRecord
        self.preferences = preferences
    }
}

enum CoachingModeOperation: String, Codable {
    case getState
    case startSession
    case endSession
    case saveThoughtRecord
    case getThoughtRecords
    case getSuggestedQuests
    case acceptQuest
    case updatePreferences
    case getPromptsForMode
}

/// Response from AI coaching edge functions
struct CoachingModeResponse: Codable {
    let success: Bool
    let data: CoachingModeData?
    let error: CoachingModeError?

    struct CoachingModeData: Codable {
        let currentMode: ConversationMode?
        let thoughtRecords: [ThoughtRecord]?
        let suggestedQuests: [AISuggestedQuest]?
        let preferences: CoachingModePreferences?
        let sessionActive: Bool?
        let sessionStartedAt: Date?
        let prompts: [String]?
        let thoughtRecord: ThoughtRecord?

        enum CodingKeys: String, CodingKey {
            case currentMode = "current_mode"
            case thoughtRecords = "thought_records"
            case suggestedQuests = "suggested_quests"
            case preferences
            case sessionActive = "session_active"
            case sessionStartedAt = "session_started_at"
            case prompts
            case thoughtRecord = "thought_record"
        }
    }

    struct CoachingModeError: Codable {
        let code: String
        let message: String
    }
}

// MARK: - Weekly Wellbeing Check

/// Weekly wellbeing assessment metrics
struct WeeklyWellbeingCheck: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let weekStartDate: Date
    let createdAt: Date

    // Core metrics (1-10 scale)
    let overallMood: Int
    let energyLevel: Int
    let stressLevel: Int
    let sleepQuality: Int
    let socialConnection: Int
    let senseOfPurpose: Int

    // Optional context
    let highlightOfWeek: String?
    let challengeOfWeek: String?
    let gratitudeNote: String?

    // Derived
    let totalScore: Int
    let previousWeekScore: Int?
    let trend: WellbeingTrend

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case weekStartDate = "week_start_date"
        case createdAt = "created_at"
        case overallMood = "overall_mood"
        case energyLevel = "energy_level"
        case stressLevel = "stress_level"
        case sleepQuality = "sleep_quality"
        case socialConnection = "social_connection"
        case senseOfPurpose = "sense_of_purpose"
        case highlightOfWeek = "highlight_of_week"
        case challengeOfWeek = "challenge_of_week"
        case gratitudeNote = "gratitude_note"
        case totalScore = "total_score"
        case previousWeekScore = "previous_week_score"
        case trend
    }

    var averageScore: Double {
        Double(totalScore) / 6.0
    }
}

/// Trend direction for wellbeing metrics
enum WellbeingTrend: String, Codable {
    case improving = "improving"
    case declining = "declining"
    case stable = "stable"

    var icon: String {
        switch self {
        case .improving: return "arrow.up.circle.fill"
        case .declining: return "arrow.down.circle.fill"
        case .stable: return "minus.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .improving: return "green"
        case .declining: return "red"
        case .stable: return "gray"
        }
    }
}

/// Individual wellbeing metric for display
struct WellbeingMetric: Identifiable {
    let id = UUID()
    let category: WellbeingCategory
    let score: Int
    let previousScore: Int?
    let trend: WellbeingTrend

    var changeDescription: String {
        guard let previous = previousScore else { return "" }
        let diff = score - previous
        if diff > 0 { return "+\(diff) from last week" }
        if diff < 0 { return "\(diff) from last week" }
        return "Same as last week"
    }
}

/// Categories for weekly wellbeing assessment
enum WellbeingCategory: String, Codable, CaseIterable, Identifiable {
    case mood = "mood"
    case energy = "energy"
    case stress = "stress"
    case sleep = "sleep"
    case social = "social"
    case purpose = "purpose"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mood: return "Mood"
        case .energy: return "Energy"
        case .stress: return "Stress"
        case .sleep: return "Sleep"
        case .social: return "Social"
        case .purpose: return "Purpose"
        }
    }

    var icon: String {
        switch self {
        case .mood: return "face.smiling"
        case .energy: return "bolt.fill"
        case .stress: return "waveform.path"
        case .sleep: return "moon.fill"
        case .social: return "person.2.fill"
        case .purpose: return "sparkles"
        }
    }

    var color: String {
        switch self {
        case .mood: return "yellow"
        case .energy: return "orange"
        case .stress: return "red"
        case .sleep: return "indigo"
        case .social: return "blue"
        case .purpose: return "purple"
        }
    }

    var question: String {
        switch self {
        case .mood: return "How would you rate your overall mood this week?"
        case .energy: return "How energetic have you felt this week?"
        case .stress: return "How stressed have you felt this week?"
        case .sleep: return "How well have you slept this week?"
        case .social: return "How connected have you felt to others?"
        case .purpose: return "How much sense of purpose have you had?"
        }
    }

    var higherIsBetter: Bool {
        switch self {
        case .stress: return false
        default: return true
        }
    }
}

/// Weekly wellbeing check-in request
struct WeeklyWellbeingRequest: Codable {
    let metrics: [WellbeingMetricInput]
    let highlight: String?
    let challenge: String?
    let gratitude: String?

    struct WellbeingMetricInput: Codable {
        let category: WellbeingCategory
        let score: Int
    }
}

/// Response from weekly wellbeing check
struct WeeklyWellbeingResponse: Codable {
    let success: Bool
    let data: WeeklyWellbeingData?
    let error: WeeklyWellbeingError?

    struct WeeklyWellbeingData: Codable {
        let check: WeeklyWellbeingCheck
        let previousTrend: [WellbeingTrendData]
        let insights: [String]

        enum CodingKeys: String, CodingKey {
            case check
            case previousTrend = "previous_trend"
            case insights
        }
    }

    struct WellbeingTrendData: Codable {
        let category: String
        let current: Int
        let previous: Int?
        let trend: String
    }

    struct WeeklyWellbeingError: Codable {
        let code: String
        let message: String
    }
}

// MARK: - Circle Habits

/// Circle template for consistent check-ins
struct CircleTemplate: Codable, Identifiable, Equatable {
    let id: UUID
    let circleId: UUID
    let name: String
    let description: String?
    let questions: [TemplateQuestion]
    let reminderDays: [Int] // 1-7 (Monday = 1)
    let reminderTime: String // HH:MM format
    let isActive: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case name, description, questions
        case reminderDays = "reminder_days"
        case reminderTime = "reminder_time"
        case isActive = "is_active"
        case createdAt = "created_at"
    }
}

/// Question within a circle template
struct TemplateQuestion: Codable, Identifiable, Equatable {
    let id: UUID
    let questionText: String
    let promptType: QuestionPromptType
    let order: Int
    let isRequired: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case questionText = "question_text"
        case promptType = "prompt_type"
        case order, isRequired = "is_required"
    }
}

/// Type of prompt for circle check-in
enum QuestionPromptType: String, Codable, CaseIterable {
    case mood = "mood"
    case gratitude = "gratitude"
    case intention = "intention"
    case reflection = "reflection"
    case numeric = "numeric"
    case freeform = "freeform"

    var icon: String {
        switch self {
        case .mood: return "face.smiling"
        case .gratitude: return "heart.fill"
        case .intention: return "target"
        case .reflection: return "mirror"
        case .numeric: return "number"
        case .freeform: return "text.bubble"
        }
    }

    var displayName: String {
        switch self {
        case .mood: return "Mood"
        case .gratitude: return "Gratitude"
        case .intention: return "Intention"
        case .reflection: return "Reflection"
        case .numeric: return "Rating"
        case .freeform: return "Free Response"
        }
    }
}

/// Circle nudge for missed check-ins
struct CircleNudge: Codable, Identifiable, Equatable {
    let id: UUID
    let circleId: UUID
    let templateId: UUID
    let missedCheckinId: UUID?
    let nudgeType: NudgeType
    let message: String
    let sentAt: Date?
    let acknowledgedAt: Date?
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case templateId = "template_id"
        case missedCheckinId = "missed_checkin_id"
        case nudgeType = "nudge_type"
        case message
        case sentAt = "sent_at"
        case acknowledgedAt = "acknowledged_at"
        case expiresAt = "expires_at"
    }
}

/// Type of nudge
enum NudgeType: String, Codable {
    case reminder = "reminder"
    case encouragement = "encouragement"
    case checkInRequest = "check_in_request"

    var defaultMessage: String {
        switch self {
        case .reminder: return "Your circle is waiting for your check-in"
        case .encouragement: return "We miss seeing you in your circle!"
        case .checkInRequest: return "Take a moment to share with your circle today"
        }
    }
}

/// User settings for circle nudges
struct CircleNudgeSettings: Codable, Equatable {
    let userId: UUID
    let circleId: UUID
    let nudgesEnabled: Bool
    let maxNudgesPerWeek: Int
    let quietHoursEnabled: Bool
    let quietHoursStart: String?
    let quietHoursEnd: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case circleId = "circle_id"
        case nudgesEnabled = "nudges_enabled"
        case maxNudgesPerWeek = "max_nudges_per_week"
        case quietHoursEnabled = "quiet_hours_enabled"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
    }

    static var `default`: CircleNudgeSettings {
        CircleNudgeSettings(
            userId: UUID(),
            circleId: UUID(),
            nudgesEnabled: true,
            maxNudgesPerWeek: 3,
            quietHoursEnabled: false,
            quietHoursStart: nil,
            quietHoursEnd: nil
        )
    }
}

/// Weekly circle recap for a user
struct CircleRecap: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let circleId: UUID
    let weekStartDate: Date
    let totalCheckins: Int
    let memberParticipations: [MemberParticipation]
    let sharedHighlights: [CheckinHighlight]
    let streakStatus: StreakStatus
    let generatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case circleId = "circle_id"
        case weekStartDate = "week_start_date"
        case totalCheckins = "total_checkins"
        case memberParticipations = "member_participations"
        case sharedHighlights = "shared_highlights"
        case streakStatus = "streak_status"
        case generatedAt = "generated_at"
    }
}

/// Participation summary for a circle member
struct MemberParticipation: Codable, Equatable, Identifiable {
    let memberId: UUID
    let memberName: String
    let memberAvatar: String?
    let checkinsCompleted: Int
    let wasActive: Bool

    var id: UUID { memberId }

    enum CodingKeys: String, CodingKey {
        case memberId = "member_id"
        case memberName = "member_name"
        case memberAvatar = "member_avatar"
        case checkinsCompleted = "checkins_completed"
        case wasActive = "was_active"
    }
}

/// Highlight shared in circle check-in
struct CheckinHighlight: Codable, Identifiable, Equatable {
    let id: UUID
    let memberId: UUID
    let memberName: String
    let content: String
    let type: HighlightType
    let reactions: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case memberId = "member_id"
        case memberName = "member_name"
        case content
        case type
        case reactions
    }
}

/// Type of highlight
enum HighlightType: String, Codable {
    case gratitude = "gratitude"
    case win = "win"
    case intention = "intention"
    case reflection = "reflection"
    case mood = "mood"
}

/// Streak tracking for circle participation
struct StreakStatus: Codable, Equatable {
    let currentStreak: Int
    let longestStreak: Int
    let lastCheckinDate: Date?
    let isAtRisk: Bool

    enum CodingKeys: String, CodingKey {
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case lastCheckinDate = "last_checkin_date"
        case isAtRisk = "is_at_risk"
    }

    static var empty: StreakStatus {
        StreakStatus(
            currentStreak: 0,
            longestStreak: 0,
            lastCheckinDate: nil,
            isAtRisk: false
        )
    }
}

/// Request for circle habits operations
struct CircleHabitsRequest: Codable {
    let operation: CircleHabitsOperation
    let circleId: UUID?
    let template: CircleTemplate?
    let settings: CircleNudgeSettings?
    let checkin: CircleCheckin?

    enum CodingKeys: String, CodingKey {
        case operation, circleId, template, settings, checkin
    }
}

enum CircleHabitsOperation: String, Codable {
    case getTemplates
    case createTemplate
    case updateTemplate
    case deleteTemplate
    case getNudges
    case dismissNudge
    case updateNudgeSettings
    case getRecap
    case submitCheckin
    case getStreakStatus
}

/// Circle check-in submission
struct CircleCheckin: Codable, Identifiable, Equatable {
    let id: UUID
    let circleId: UUID
    let templateId: UUID
    let userId: UUID
    let responses: [QuestionResponse]
    let mood: Int?
    let submittedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case templateId = "template_id"
        case userId = "user_id"
        case responses, mood
        case submittedAt = "submitted_at"
    }
}

/// Response to a template question
struct QuestionResponse: Codable, Identifiable, Equatable {
    let id: UUID
    let questionId: UUID
    let responseValue: String
    let responseType: QuestionPromptType

    enum CodingKeys: String, CodingKey {
        case id
        case questionId = "question_id"
        case responseValue = "response_value"
        case responseType = "response_type"
    }
}

/// Response from circle habits operations
struct CircleHabitsResponse: Codable {
    let success: Bool
    let data: CircleHabitsData?
    let error: CircleHabitsError?

    struct CircleHabitsData: Codable {
        let templates: [CircleTemplate]?
        let nudges: [CircleNudge]?
        let settings: CircleNudgeSettings?
        let recap: CircleRecap?
        let checkin: CircleCheckin?
        let streakStatus: StreakStatus?

        enum CodingKeys: String, CodingKey {
            case templates, nudges, settings, recap, checkin
            case streakStatus = "streak_status"
        }
    }

    struct CircleHabitsError: Codable {
        let code: String
        let message: String
    }
}