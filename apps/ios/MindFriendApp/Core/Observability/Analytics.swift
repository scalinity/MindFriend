import Foundation
import UIKit

/// Analytics event names for type-safe tracking
enum AnalyticsEvent: String {
    // Authentication
    case signInStarted = "sign_in_started"
    case signInCompleted = "sign_in_completed"
    case signInFailed = "sign_in_failed"
    case signOut = "sign_out"

    // Onboarding
    case onboardingStarted = "onboarding_started"
    case onboardingStepCompleted = "onboarding_step_completed"
    case onboardingCompleted = "onboarding_completed"
    case onboardingSkipped = "onboarding_skipped"

    // Quests
    case questViewed = "quest_viewed"
    case questStarted = "quest_started"
    case questCompleted = "quest_completed"
    case questSkipped = "quest_skipped"

    // Streak Recovery
    case streakShieldUsed = "streak_shield_used"
    case recoveryQuestOffered = "recovery_quest_offered"
    case recoveryQuestStarted = "recovery_quest_started"
    case recoveryQuestCompleted = "recovery_quest_completed"

    // Quest Choice
    case questVariantSelected = "quest_variant_selected"
    case questRerolled = "quest_rerolled"
    case questQuickVersionSelected = "quest_quick_version_selected"
    case questAlternativeSelected = "quest_alternative_selected"

    // Mood Tracking
    case moodLogged = "mood_logged"
    case moodHistoryViewed = "mood_history_viewed"

    // Chat
    case chatStarted = "chat_started"
    case chatMessageSent = "chat_message_sent"
    case chatConversationCreated = "chat_conversation_created"
    case chatConversationDeleted = "chat_conversation_deleted"
    case crisisDetected = "crisis_detected"
    case quotaExceeded = "quota_exceeded"

    // Exercises
    case exerciseViewed = "exercise_viewed"
    case exerciseStarted = "exercise_started"
    case exerciseCompleted = "exercise_completed"
    case exerciseAbandoned = "exercise_abandoned"

    // Circles
    case circleCreated = "circle_created"
    case circleJoined = "circle_joined"
    case circleLeft = "circle_left"
    case circleCheckinPosted = "circle_checkin_posted"
    case hugSent = "hug_sent"
    case challengeCreated = "challenge_created"
    case challengeCompleted = "challenge_completed"
    case reactionAdded = "reaction_added"
    case inviteSent = "invite_sent"

    // Buddy System
    case buddyInviteSent = "buddy_invite_sent"
    case buddyInviteAccepted = "buddy_invite_accepted"
    case buddyEncouragementSent = "buddy_encouragement_sent"

    // Billing
    case paywallViewed = "paywall_viewed"
    case purchaseStarted = "purchase_started"
    case purchaseCompleted = "purchase_completed"
    case purchaseFailed = "purchase_failed"
    case purchaseRestored = "purchase_restored"

    // Settings
    case settingsViewed = "settings_viewed"
    case settingsChanged = "settings_changed"
    case privacyPolicyViewed = "privacy_policy_viewed"
    case termsViewed = "terms_viewed"

    // App Lifecycle
    case appLaunched = "app_launched"
    case appBackgrounded = "app_backgrounded"
    case appForegrounded = "app_foregrounded"

    // Errors
    case errorOccurred = "error_occurred"

    // Features
    case featureUsed = "feature_used"
    case screenViewed = "screen_viewed"

    // Memory
    case memoryDeleted = "memory_deleted"
    case allMemoriesDeleted = "all_memories_deleted"
    case memoriesDeletedByType = "memories_deleted_by_type"
    case memorySettingsViewed = "memory_settings_viewed"

    // XP & Progression
    case xpAwarded = "xp_awarded"
    case levelUp = "level_up"
    case eventJoined = "event_joined"
    case eventCompleted = "event_completed"
    case weeklyXPReset = "weekly_xp_reset"
    case skillLevelUp = "skill_level_up"

    // Celebrations
    case celebrationShown = "celebration_shown"
    case celebrationDismissed = "celebration_dismissed"
    case celebrationSharedToCircle = "celebration_shared_to_circle"
    case celebrationSharedExternally = "celebration_shared_externally"
    case celebrationReactionAdded = "celebration_reaction_added"

    // Notifications
    case notificationSettingsUpdated = "notification_settings_updated"
    case notificationOpened = "notification_opened"
    case notificationReceived = "notification_received"
    case pushPermissionGranted = "push_permission_granted"
    case pushPermissionDenied = "push_permission_denied"

    // Live Sessions
    case liveSessionJoined = "live_session_joined"
    case liveSessionLeft = "live_session_left"
    case liveSessionCompleted = "live_session_completed"

    // Re-engagement
    case reengagementAbsenceChecked = "reengagement_absence_checked"
    case reengagementEventLogged = "reengagement_event_logged"
    case sessionStarted = "session_started"
    case freshStartPerformed = "fresh_start_performed"
    case welcomeBackShown = "welcome_back_shown"
    case welcomeBackDismissed = "welcome_back_dismissed"
    case welcomeBackFreshStartChosen = "welcome_back_fresh_start_chosen"
    case welcomeBackContinueChosen = "welcome_back_continue_chosen"

    // Structured Programs
    case programViewed = "program_viewed"
    case programEnrolled = "program_enrolled"
    case programDayStarted = "program_day_started"
    case programDayCompleted = "program_day_completed"
    case programCompleted = "program_completed"
    case programPaused = "program_paused"
    case programResumed = "program_resumed"
    case programAbandoned = "program_abandoned"
    case programDaySkipped = "program_day_skipped"
    case certificateShared = "certificate_shared"
}

/// User properties for segmentation
enum AnalyticsUserProperty: String {
    case userId = "user_id"
    case subscriptionTier = "subscription_tier"
    case accountAge = "account_age_days"
    case totalQuestsCompleted = "total_quests_completed"
    case currentStreak = "current_streak"
    case timezone = "timezone"
    case notificationsEnabled = "notifications_enabled"
    case privacyMode = "privacy_mode"
}

/// Analytics provider protocol for multiple backend support
protocol AnalyticsProvider {
    func track(event: String, properties: [String: Any]?)
    func setUserProperty(name: String, value: Any)
    func setUserId(_ userId: String?)
    func flush()
}

/// Console-based analytics for development
final class ConsoleAnalyticsProvider: AnalyticsProvider {
    func track(event: String, properties: [String: Any]?) {
        var message = "[Analytics] Event: \(event)"
        if let properties = properties, !properties.isEmpty {
            let propsString = properties.map { key, value in
                "\(key)=\(String(describing: value))"
            }.joined(separator: ", ")
            message += " | Properties: \(propsString)"
        }
        Log.data.debug("\(message)")
    }

    func setUserProperty(name: String, value: Any) {
        let stringValue = String(describing: value)
        Log.data.debug("[Analytics] User Property: \(name) = \(stringValue)")
    }

    func setUserId(_ userId: String?) {
        Log.data.debug("[Analytics] User ID: \(userId ?? "nil")")
    }

    func flush() {
        Log.data.debug("[Analytics] Flushed")
    }
}

/// Main analytics service
final class Analytics {
    static let shared = Analytics()

    private var providers: [AnalyticsProvider] = []
    private var globalProperties: [String: Any] = [:]
    private var isEnabled = true

    private init() {
        // Always add console provider in debug
        #if DEBUG
        providers.append(ConsoleAnalyticsProvider())
        #endif

        // Set up app version info
        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            globalProperties["app_version"] = appVersion
        }
        if let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            globalProperties["build_number"] = buildNumber
        }
        globalProperties["platform"] = "iOS"
        globalProperties["os_version"] = UIDevice.current.systemVersion
        globalProperties["device_model"] = UIDevice.current.model
    }

    // MARK: - Configuration

    /// Add an analytics provider
    func addProvider(_ provider: AnalyticsProvider) {
        providers.append(provider)
    }

    /// Enable or disable analytics
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    /// Set global properties that will be included in all events
    func setGlobalProperty(key: String, value: Any) {
        globalProperties[key] = value
    }

    // MARK: - User Identification

    /// Set the current user ID
    func identify(userId: String) {
        guard isEnabled else { return }
        providers.forEach { $0.setUserId(userId) }
    }

    /// Clear user identification (call on logout)
    func reset() {
        guard isEnabled else { return }
        providers.forEach { $0.setUserId(nil) }
    }

    /// Set a user property for segmentation
    func setUserProperty(_ property: AnalyticsUserProperty, value: Any) {
        guard isEnabled else { return }
        providers.forEach { $0.setUserProperty(name: property.rawValue, value: value) }
    }

    // MARK: - Event Tracking

    /// Track an analytics event
    func track(_ event: AnalyticsEvent, properties: [String: Any]? = nil) {
        track(event.rawValue, properties: properties)
    }

    /// Track a custom event by name
    func track(_ eventName: String, properties: [String: Any]? = nil) {
        guard isEnabled else { return }

        var mergedProperties = globalProperties
        if let properties = properties {
            mergedProperties.merge(properties) { _, new in new }
        }
        mergedProperties["timestamp"] = ISO8601DateFormatter().string(from: Date())

        providers.forEach { $0.track(event: eventName, properties: mergedProperties) }

        // Also add as Sentry breadcrumb
        CrashReporter.shared.addBreadcrumb(
            category: "analytics",
            message: eventName,
            data: properties
        )
    }

    // MARK: - Screen Tracking

    /// Track a screen view
    func trackScreen(_ screenName: String, additionalProperties: [String: Any]? = nil) {
        var properties: [String: Any] = ["screen_name": screenName]
        if let additional = additionalProperties {
            properties.merge(additional) { _, new in new }
        }
        track(.screenViewed, properties: properties)

        CrashReporter.shared.addNavigationBreadcrumb(from: "previous", to: screenName)
    }

    // MARK: - Convenience Methods

    /// Track sign-in event
    func trackSignIn(provider: String, success: Bool, error: Error? = nil) {
        if success {
            track(.signInCompleted, properties: ["provider": provider])
        } else {
            track(.signInFailed, properties: [
                "provider": provider,
                "error": error?.localizedDescription ?? "Unknown error"
            ])
        }
    }

    /// Track purchase event
    func trackPurchase(productId: String, success: Bool, price: Decimal? = nil, error: Error? = nil) {
        if success {
            var properties: [String: Any] = ["product_id": productId]
            if let price = price {
                properties["price"] = NSDecimalNumber(decimal: price).doubleValue
            }
            track(.purchaseCompleted, properties: properties)
        } else {
            track(.purchaseFailed, properties: [
                "product_id": productId,
                "error": error?.localizedDescription ?? "Unknown error"
            ])
        }
    }

    /// Track feature usage
    func trackFeature(_ featureName: String, action: String? = nil) {
        var properties: [String: Any] = ["feature": featureName]
        if let action = action {
            properties["action"] = action
        }
        track(.featureUsed, properties: properties)
    }

    /// Track error occurrence
    func trackError(_ error: Error, context: String? = nil) {
        var properties: [String: Any] = [
            "error_type": String(describing: type(of: error)),
            "error_message": error.localizedDescription
        ]
        if let context = context {
            properties["context"] = context
        }
        track(.errorOccurred, properties: properties)
    }

    // MARK: - Flush

    /// Flush any pending events
    func flush() {
        providers.forEach { $0.flush() }
    }
}

// MARK: - SwiftUI View Extension

import SwiftUI

extension View {
    /// Track when this view appears
    func trackScreen(_ screenName: String, properties: [String: Any]? = nil) -> some View {
        self.onAppear {
            Analytics.shared.trackScreen(screenName, additionalProperties: properties)
        }
    }
}
