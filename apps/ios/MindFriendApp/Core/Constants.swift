import Foundation

/// Centralized constants for the MindFriend app
/// All magic numbers and configurable values should be defined here
enum Constants {
    // MARK: - Quotas & Limits

    /// Free tier daily AI chat quota (reduced to drive conversions)
    static let freeUserDailyAiQuota = 5

    /// Premium tier effectively unlimited quota
    static let premiumUserDailyAiQuota = 9999

    /// Number of remaining messages before showing quota warning
    static let quotaWarningThreshold = 3

    /// Maximum message length (characters)
    static let maxMessageLength = 4000

    // MARK: - Timeouts

    /// Network request timeout in seconds
    static let networkTimeoutSeconds: TimeInterval = 30

    /// Session refresh interval in seconds
    static let sessionRefreshIntervalSeconds: TimeInterval = 300 // 5 minutes

    // MARK: - Pagination

    /// Default page size for list fetches
    static let defaultPageSize = 20

    /// Maximum messages to fetch for conversation context
    static let maxConversationContextMessages = 20

    // MARK: - UI

    /// Minimum touch target size (Apple HIG)
    static let minTouchTargetSize: CGFloat = 44

    /// Standard corner radius
    static let standardCornerRadius: CGFloat = 12

    /// Large corner radius
    static let largeCornerRadius: CGFloat = 20

    /// Animation duration for standard transitions
    static let standardAnimationDuration: TimeInterval = 0.3

    // MARK: - Streaks

    /// Days of inactivity before showing nudge notification
    static let defaultNudgeAfterDaysInactive = 3

    // MARK: - Voice Mode

    /// Voice session token validity in seconds
    static let voiceTokenValiditySeconds = 300 // 5 minutes

    /// Free tier monthly voice minutes (voice mode is premium-only)
    static let freeUserMonthlyVoiceMinutes = 0.0

    /// Premium tier monthly voice minutes (effectively unlimited)
    static let premiumUserMonthlyVoiceMinutes = 999.0

    // MARK: - Handle Validation

    /// Minimum handle length
    static let minHandleLength = 3

    /// Maximum handle length
    static let maxHandleLength = 30

    // MARK: - Cache

    /// Memory cache limit in bytes
    static let memoryCacheLimitBytes = 50 * 1024 * 1024 // 50 MB

    /// Disk cache limit in bytes
    static let diskCacheLimitBytes = 100 * 1024 * 1024 // 100 MB

    // MARK: - Feature Flags

    /// Enable debug logging in debug builds
    #if DEBUG
    static let enableDebugLogging = true
    #else
    static let enableDebugLogging = false
    #endif
}

// MARK: - Edge Function Constants

extension Constants {
    enum EdgeFunctions {
        static let chat = "chat"
        static let verifyPurchase = "verify-purchase"
        static let sendNotification = "send-notification"
        static let assignQuest = "assign-quest"
        static let deleteAccount = "delete-account"
        static let voiceToken = "voice-token"
        static let voiceSessionEnd = "voice-session-end"
        static let sendFamilyInvite = "send-family-invite"
        static let acceptFamilyInvite = "accept-family-invite"
    }
}

// MARK: - Analytics Event Names

extension Constants {
    enum AnalyticsEvents {
        static let signInCompleted = "sign_in_completed"
        static let signOut = "sign_out"
        static let questCompleted = "quest_completed"
        static let moodLogged = "mood_logged"
        static let chatMessageSent = "chat_message_sent"
        static let exerciseCompleted = "exercise_completed"
        static let circleJoined = "circle_joined"
        static let purchaseCompleted = "purchase_completed"
    }
}

// MARK: - Public Legal & Marketing URLs

enum AppURLs {
    static let termsOfUse = URL(string: "https://getmindfriend.app/terms")!
    static let privacyPolicy = URL(string: "https://getmindfriend.app/privacy")!
    static let accessibility = URL(string: "https://getmindfriend.app/accessibility")!
    static let marketing = URL(string: "https://getmindfriend.app")!
}
