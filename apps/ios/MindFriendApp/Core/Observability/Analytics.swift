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
            let propsString = properties.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            message += " | Properties: \(propsString)"
        }
        print(message)
    }

    func setUserProperty(name: String, value: Any) {
        print("[Analytics] User Property: \(name) = \(value)")
    }

    func setUserId(_ userId: String?) {
        print("[Analytics] User ID: \(userId ?? "nil")")
    }

    func flush() {
        print("[Analytics] Flushed")
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
