import Foundation
import Sentry
import UIKit

/// Centralized crash reporting and error tracking using Sentry
///
/// PRIVACY NOTICE: This module implements comprehensive PII scrubbing for mental health app data.
/// All events are processed through a beforeSend callback that redacts:
/// - User emails and usernames
/// - Message/chat content
/// - Mood entries and personal notes
/// - URLs containing invite codes
/// - Other sensitive identifiers
///
/// Screenshots and view hierarchy capture are DISABLED to prevent accidental capture of
/// sensitive on-screen content (mood entries, crisis resources, chat conversations).
final class CrashReporter {
    static let shared = CrashReporter()

    private(set) var isInitialized = false

    /// Whether Sentry is fully configured (DSN available)
    private var isSentryEnabled = false

    private init() {}

    // MARK: - PII Scrubbing Constants

    /// Maximum recursion depth for dictionary/array scrubbing (prevent stack overflow)
    private static let maxScrubDepth = 10

    /// Keys that should always be redacted in extra/tags data
    private static let sensitiveKeys: Set<String> = [
        // User identifiers and contact info
        "email", "user_email", "recipient_email",
        "name", "username", "display_name", "fullname",
        "phone", "phone_number", "mobile", "cell", "phone_number_backup", "emergency_contact_phone",
        "address", "location",
        // Authentication
        "invite_code", "redemption_code",
        "token", "access_token", "refresh_token", "auth_token",
        // Sensitive message content
        "message", "content", "text", "body",
        "personal_message", "mood_note", "journal_entry",
        // Emergency contact
        "emergency_contact", "emergency_name", "emergency_relation"
    ]

    // MARK: - Compiled Regex Patterns (Performance Optimization)

    /// Email pattern compiled once for reuse
    private static let emailRegex = try! NSRegularExpression(
        pattern: "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}",
        options: []
    )

    /// Invite code pattern compiled once for reuse
    private static let inviteCodeRegex = try! NSRegularExpression(
        pattern: "(invite[/_=])([A-Za-z0-9]{6,12})",
        options: []
    )

    /// URL query parameter token pattern compiled once for reuse
    private static let urlTokenRegex = try! NSRegularExpression(
        pattern: "(token|access_token|code|key|secret)=([A-Za-z0-9._-]+)",
        options: []
    )

    /// Phone number pattern compiled once for reuse
    private static let phoneRegex = try! NSRegularExpression(
        pattern: "(\\+?1?[-.\\s]?)?(\\(?\\d{3}\\)?[-.\\s]?){2}\\d{4}",
        options: []
    )

    // MARK: - Configuration

    /// Initialize Sentry with the provided DSN from Info.plist
    /// Call this early in app launch (before any UI is shown)
    func initialize() {
        guard !isInitialized else { return }

        // Load DSN from Info.plist (set via xcconfig for different environments)
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String,
              !dsn.isEmpty,
              !dsn.contains("$(") else {
            // DSN not configured - run without crash reporting
            isInitialized = true
            isSentryEnabled = false
            #if DEBUG
            print("[CrashReporter] Sentry DSN not configured, crash reporting disabled")
            #endif
            return
        }

        // Start Sentry SDK
        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = false

            // PRIVACY: PII scrubbing callback - processes all events before transmission
            // Redacts emails, usernames, message content, invite codes, etc.
            options.beforeSend = { event in
                return Self.scrubPII(from: event)
            }

            // Performance monitoring
            options.tracesSampleRate = 0.2  // 20% of transactions

            // Session tracking
            options.enableAutoSessionTracking = true
            options.sessionTrackingIntervalMillis = 30000  // 30 seconds

            // Breadcrumbs
            options.maxBreadcrumbs = 100
            options.enableAutoBreadcrumbTracking = true

            // PRIVACY: Disabled for mental health app - screenshots may contain:
            // - Chat conversations with sensitive content
            // - Mood entries and personal reflections
            // - User profile information
            // - Crisis resources screen (indicates user was in crisis)
            options.attachScreenshot = false
            options.attachViewHierarchy = false

            // Environment from build config
            #if DEBUG
            options.environment = "development"
            #else
            options.environment = "production"
            #endif

            // App version
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                options.releaseName = "com.mindfriend.app@\(version)+\(build)"
            }
        }

        isInitialized = true
        isSentryEnabled = true
    }

    // MARK: - PII Scrubbing

    /// Scrub personally identifiable information from a Sentry event before transmission.
    /// Processes all event properties: message, exceptions, breadcrumbs, user, extra, tags.
    private static func scrubPII(from event: Event) -> Event? {
        // Scrub message
        if let message = event.message {
            event.message?.message = scrubText(message.message)
        }

        // Scrub exceptions
        event.exceptions = event.exceptions?.map { exception in
            var scrubbed = exception
            scrubbed.value = scrubText(exception.value)
            return scrubbed
        }

        // Scrub breadcrumbs (navigation, user actions, etc.)
        event.breadcrumbs = event.breadcrumbs?.map { crumb in
            var scrubbed = crumb
            scrubbed.message = scrubText(crumb.message)
            scrubbed.data = scrubDictionary(crumb.data)
            return scrubbed
        }

        // Scrub user context - NEVER transmit email or username
        if event.user != nil {
            event.user?.email = nil
            event.user?.username = nil
            // Keep userId (UUID) for issue correlation
        }

        // Scrub extra context (arbitrary debug data)
        event.extra = scrubDictionary(event.extra)

        // Scrub tags
        if let tags = event.tags as? [String: String] {
            event.tags = scrubDictionary(tags as [String: Any]) as? [String: String]
        }

        return event
    }

    /// Sanitize URLs by removing sensitive query parameters before logging
    /// Prevents tokens, codes, and other secrets from being sent to Sentry in breadcrumbs
    static func sanitizeURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "[invalid-url]"
        }

        // List of query parameter names that should not be logged
        let sensitiveParams = ["token", "code", "invite", "key", "secret", "access_token",
                              "refresh_token", "api_key", "password", "auth"]

        // Replace sensitive query parameters with redacted values
        components.queryItems = components.queryItems?.map { item in
            if sensitiveParams.contains(item.name.lowercased()) {
                return URLQueryItem(name: item.name, value: "[redacted]")
            }
            return item
        }

        return components.string ?? url.host ?? "[url]"
    }

    /// Scrub sensitive text patterns: emails, invite codes, tokens, etc.
    /// Uses pre-compiled regex patterns for performance.
    private static func scrubText(_ text: String?) -> String? {
        guard var result = text else { return nil }

        let nsString = result as NSString
        let range = NSRange(location: 0, length: nsString.length)

        // Remove email addresses: user@example.com → [email]
        result = emailRegex.stringByReplacingMatches(
            in: result,
            options: [],
            range: range,
            withTemplate: "[email]"
        )

        // Remove invite codes from URLs: /invite/ABC123 → /invite/[redacted]
        result = inviteCodeRegex.stringByReplacingMatches(
            in: result,
            options: [],
            range: NSRange(location: 0, length: (result as NSString).length),
            withTemplate: "$1[redacted]"
        )

        // Remove URL query parameter tokens: ?token=xxx, ?code=xxx, ?access_token=xxx → ?token=[redacted]
        result = urlTokenRegex.stringByReplacingMatches(
            in: result,
            options: [],
            range: NSRange(location: 0, length: (result as NSString).length),
            withTemplate: "$1=[redacted]"
        )

        // Remove phone numbers: +1-234-567-8901, (234) 567-8901, 234.567.8901 → [phone]
        result = phoneRegex.stringByReplacingMatches(
            in: result,
            options: [],
            range: NSRange(location: 0, length: (result as NSString).length),
            withTemplate: "[phone]"
        )

        return result
    }

    /// Scrub sensitive key-value pairs in a dictionary.
    /// Redacts keys like "email", "token", "message" and recursively scrubs nested dicts and arrays.
    /// Uses depth limiting to prevent stack overflow on deeply nested data.
    private static func scrubDictionary(_ dict: [String: Any]?, depth: Int = 0) -> [String: Any]? {
        guard let dict = dict else { return nil }

        // Stop recursion if we've reached maximum depth (protects against stack overflow)
        if depth >= maxScrubDepth {
            return dict
        }

        var scrubbed = [String: Any]()
        for (key, value) in dict {
            let lowercasedKey = key.lowercased()

            // Check if this key is known to contain sensitive data
            if sensitiveKeys.contains(lowercasedKey) {
                scrubbed[key] = "[redacted]"
            } else if let stringValue = value as? String {
                // Scrub string values for patterns
                scrubbed[key] = scrubText(stringValue)
            } else if let nestedDict = value as? [String: Any] {
                // Recursively scrub nested dictionaries with depth tracking
                scrubbed[key] = scrubDictionary(nestedDict, depth: depth + 1)
            } else if let arrayValue = value as? [Any] {
                // Recursively scrub arrays with depth tracking
                scrubbed[key] = scrubArray(arrayValue, depth: depth + 1)
            } else {
                // Pass through other values as-is
                scrubbed[key] = value
            }
        }
        return scrubbed
    }

    /// Scrub array values recursively with depth limiting
    private static func scrubArray(_ array: [Any], depth: Int = 0) -> [Any] {
        // Stop recursion if we've reached maximum depth
        if depth >= maxScrubDepth {
            return array
        }

        return array.map { item in
            if let stringValue = item as? String {
                return scrubText(stringValue) ?? item
            } else if let nestedDict = item as? [String: Any] {
                return scrubDictionary(nestedDict, depth: depth + 1) ?? item
            } else if let nestedArray = item as? [Any] {
                return scrubArray(nestedArray, depth: depth + 1)
            } else {
                return item
            }
        }
    }

    // MARK: - User Identification

    /// Set the current user for crash reports
    /// Note: NEVER set email or username - the beforeSend callback cannot scrub
    /// user context set via SentrySDK.setUser(). Only use userId for issue correlation.
    /// userId should be a UUID for anonymity and to prevent PII exposure.
    func setUser(id: String, email: String? = nil, username: String? = nil) {
        guard isSentryEnabled else { return }

        // Validate that userId looks like a UUID (36 chars with hyphens, hexadecimal)
        // This prevents accidentally passing email addresses or other PII as the ID
        let isValidUUID = id.count == 36 && id.filter({ $0 == "-" }).count == 4
        guard isValidUUID else {
            #if DEBUG
            print("[CrashReporter] WARNING: User ID does not appear to be a UUID format. Refusing to set user context. Received: \(id)")
            #endif
            return
        }

        let user = Sentry.User(userId: id)
        // SECURITY: Do NOT set email/username - they bypass beforeSend callback
        // and are transmitted to Sentry before PII scrubbing can occur.
        // Only use userId (which must be a UUID, not identifiable)
        user.email = nil
        user.username = nil
        SentrySDK.setUser(user)
    }

    /// Clear user information (call on logout)
    func clearUser() {
        guard isSentryEnabled else { return }
        SentrySDK.setUser(nil)
    }

    // MARK: - Error Capture

    /// Capture a non-fatal error
    func capture(error: Error, context: [String: Any]? = nil) {
        guard isSentryEnabled else { return }
        let sentryEvent = Sentry.Event(error: error)

        if let context = context {
            sentryEvent.extra = context.mapValues { "\($0)" }
        }

        SentrySDK.capture(event: sentryEvent)
    }

    /// Capture a message with optional context
    func capture(message: String, context: [String: Any]? = nil) {
        guard isSentryEnabled else { return }
        SentrySDK.capture(message: message) { scope in
            if let context = context {
                for (key, value) in context {
                    scope.setExtra(value: "\(value)", key: key)
                }
            }
        }
    }

    // MARK: - Breadcrumbs

    /// Add a breadcrumb for debugging crash context
    func addBreadcrumb(category: String, message: String, data: [String: Any]? = nil) {
        guard isSentryEnabled else { return }
        let breadcrumb = Sentry.Breadcrumb(level: .info, category: category)
        breadcrumb.message = message
        if let data = data {
            breadcrumb.data = data.mapValues { "\($0)" }
        }
        SentrySDK.addBreadcrumb(breadcrumb)
    }

    /// Add navigation breadcrumb
    func addNavigationBreadcrumb(from: String, to: String) {
        addBreadcrumb(
            category: "navigation",
            message: "Navigated from \(from) to \(to)",
            data: ["from": from, "to": to]
        )
    }

    /// Add user action breadcrumb
    func addUserActionBreadcrumb(action: String, target: String? = nil) {
        var data: [String: Any] = ["action": action]
        if let target = target {
            data["target"] = target
        }
        addBreadcrumb(category: "user", message: action, data: data)
    }

    // MARK: - Performance Monitoring

    /// Start a transaction for performance monitoring
    func startTransaction(name: String, operation: String) -> (any Span)? {
        guard isSentryEnabled else { return nil }
        return SentrySDK.startTransaction(name: name, operation: operation)
    }

    /// Measure the duration of a code block
    func measure<T>(name: String, operation: String, block: () throws -> T) rethrows -> T {
        let transaction = startTransaction(name: name, operation: operation)
        defer { transaction?.finish() }
        return try block()
    }

    /// Measure async operation
    func measureAsync<T>(name: String, operation: String, block: () async throws -> T) async rethrows -> T {
        let transaction = startTransaction(name: name, operation: operation)
        defer { transaction?.finish() }
        return try await block()
    }

    // MARK: - Tags & Context

    /// Set a tag that will be attached to all future events
    func setTag(key: String, value: String) {
        guard isSentryEnabled else { return }
        SentrySDK.configureScope { scope in
            scope.setTag(value: value, key: key)
        }
    }

    /// Set extra context data
    func setContext(key: String, value: [String: Any]) {
        guard isSentryEnabled else { return }
        SentrySDK.configureScope { scope in
            scope.setContext(value: value, key: key)
        }
    }

    /// Set app version context
    func setAppContext() {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let deviceModel = UIDevice.current.model
        let osVersion = UIDevice.current.systemVersion

        setContext(key: "app", value: [
            "version": appVersion,
            "build": buildNumber,
            "device_model": deviceModel,
            "os_version": osVersion
        ])
    }
}

// MARK: - Convenience Extensions

extension Error {
    /// Report this error to Sentry
    func report(context: [String: Any]? = nil) {
        CrashReporter.shared.capture(error: self, context: context)
    }
}
