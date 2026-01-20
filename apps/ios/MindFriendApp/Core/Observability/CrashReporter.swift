import Foundation
import Sentry
import UIKit
import OSLog

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
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.mindfriend", category: "CrashReporter")

    private(set) var isInitialized = false

    /// Whether Sentry is fully configured (DSN available)
    private var isSentryEnabled = false

    /// Public accessor to check if Sentry tracing is enabled
    var isEnabled: Bool { isSentryEnabled }

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
    private static let emailRegex: NSRegularExpression = {
        if let regex = try? NSRegularExpression(
            pattern: "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}",
            options: []
        ) {
            return regex
        } else {
            // This should never happen as the pattern is hardcoded and valid
            Log.crash.error("Failed to compile email regex - PII scrubbing may be incomplete")
            // Fallback: regex that matches nothing (defensive programming)
            return try! NSRegularExpression(pattern: "a^", options: [])
        }
    }()

    /// Invite code pattern compiled once for reuse
    private static let inviteCodeRegex: NSRegularExpression = {
        if let regex = try? NSRegularExpression(
            pattern: "(invite[/_=])([A-Za-z0-9]{6,12})",
            options: []
        ) {
            return regex
        } else {
            Log.crash.error("Failed to compile invite code regex - PII scrubbing may be incomplete")
            return try! NSRegularExpression(pattern: "a^", options: [])
        }
    }()

    /// URL query parameter token pattern compiled once for reuse
    private static let urlTokenRegex: NSRegularExpression = {
        if let regex = try? NSRegularExpression(
            pattern: "(token|access_token|code|key|secret)=([A-Za-z0-9._-]+)",
            options: []
        ) {
            return regex
        } else {
            Log.crash.error("Failed to compile URL token regex - PII scrubbing may be incomplete")
            return try! NSRegularExpression(pattern: "a^", options: [])
        }
    }()

    /// Phone number pattern compiled once for reuse
    private static let phoneRegex: NSRegularExpression = {
        if let regex = try? NSRegularExpression(
            pattern: "(\\+?1?[-.\\s]?)?(\\(?\\d{3}\\)?[-.\\s]?){2}\\d{4}",
            options: []
        ) {
            return regex
        } else {
            Log.crash.error("Failed to compile phone regex - PII scrubbing may be incomplete")
            return try! NSRegularExpression(pattern: "a^", options: [])
        }
    }()

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
            logger.warning("Sentry DSN not configured, crash reporting disabled")
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

            // MARK: - Structured Logging

            // Enable Sentry structured logs for remote observability
            // options.enableLogs = true // Removed as it is not available in current Sentry SDK

            // PRIVACY: PII scrubbing for logs - same rules as events
            options.beforeSendLog = { log in
                return Self.scrubPIIFromLog(log)
            }

            // MARK: - Performance Monitoring & Tracing

            // Sample rate: 100% in debug, 25% in production for meaningful data
            #if DEBUG
            options.tracesSampleRate = 1.0
            #else
            options.tracesSampleRate = 0.25
            #endif

            // Enable automatic instrumentation features
            options.enableAutoPerformanceTracing = true

            // Network request tracing - tracks all HTTP requests
            options.enableNetworkTracking = true
            options.enableNetworkBreadcrumbs = true

            // File I/O tracing - monitors NSData and NSFileManager operations
            options.enableFileIOTracing = true

            // Core Data tracing - tracks fetch and save operations
            options.enableCoreDataTracing = true

            // User interaction tracing - captures button taps and gestures
            // Note: Limited SwiftUI support, but works for UIKit-backed views
            options.enableUserInteractionTracing = true

            // App start tracing - measures cold/warm start times
            options.enablePreWarmedAppStartTracing = true

            // Time to Full Display tracking for views
            options.enableTimeToFullDisplayTracing = true

            // Trace propagation targets - send trace headers to our backend
            // This enables distributed tracing with Supabase Edge Functions
            options.tracePropagationTargets = [
                "supabase.co",
                "supabase.in",
                "localhost"
            ]

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

            // Session Replay Configuration
            // Enables visual recording of user sessions for debugging while maintaining strict privacy.
            // All text and images are masked by default to protect mental health data.
            #if DEBUG
            // Development: No session replay to avoid unnecessary overhead during active dev
            let sessionSampleRate: Float = 0.0
            let onErrorSampleRate: Float = 0.0
            #else
            // Production: 5% of sessions recorded, 100% of error sessions captured
            // Low sample rate minimizes storage costs while providing sufficient debugging data
            let sessionSampleRate: Float = 0.05
            let onErrorSampleRate: Float = 1.0
            #endif

            options.sessionReplay.sessionSampleRate = sessionSampleRate
            options.sessionReplay.onErrorSampleRate = onErrorSampleRate

            // Privacy Protection: CRITICAL for mental health application
            // - maskAllText: Replaces ALL text with gray blocks (mood scores, journal entries, chat)
            // - maskAllImages: Replaces ALL images with placeholders (user photos, media)
            // - SwiftUI views can use .sentryMask() modifier for explicit defense-in-depth
            options.sessionReplay.maskAllText = true
            options.sessionReplay.maskAllImages = true
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
            event.message?.message = scrubText(message.message) ?? ""
        }

        // Scrub exceptions
        event.exceptions = event.exceptions?.map { exception in
            var scrubbed = exception
            scrubbed.value = scrubText(exception.value) ?? ""
            return scrubbed
        }

        // Scrub breadcrumbs (navigation, user actions, etc.)
        event.breadcrumbs = event.breadcrumbs?.map { crumb in
            var scrubbed = crumb
            scrubbed.message = scrubText(crumb.message) ?? ""
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

    // MARK: - Log PII Scrubbing

    /// Scrub PII from a Sentry log before transmission.
    /// Note: SentryLog properties are read-only, so we can only filter logs containing PII.
    /// Logs with detected PII patterns are dropped entirely for privacy protection.
    private static func scrubPIIFromLog(_ log: SentryLog) -> SentryLog? {
        // Check if the log message contains PII patterns
        // If PII is detected, drop the log entirely since we can't modify it
        let message = log.body
        let containsEmail = emailRegex.firstMatch(
            in: message,
            options: [],
            range: NSRange(location: 0, length: (message as NSString).length)
        ) != nil

        let containsPhone = phoneRegex.firstMatch(
            in: message,
            options: [],
            range: NSRange(location: 0, length: (message as NSString).length)
        ) != nil

        let containsToken = urlTokenRegex.firstMatch(
            in: message,
            options: [],
            range: NSRange(location: 0, length: (message as NSString).length)
        ) != nil

        let containsInviteCode = inviteCodeRegex.firstMatch(
            in: message,
            options: [],
            range: NSRange(location: 0, length: (message as NSString).length)
        ) != nil

        // Drop logs that contain PII
        if containsEmail || containsPhone || containsToken || containsInviteCode {
            return nil
        }

        return log
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
            logger.warning("User ID does not appear to be a UUID format. Refusing to set user context. Received: \(id, privacy: .private)")
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

    // MARK: - Structured Logging

    /// Private helper to reduce code duplication in logging methods
    /// - Parameters:
    ///   - message: The log message
    ///   - attributes: Optional structured attributes
    ///   - logWithAttrs: Closure that logs with attributes
    ///   - logSimple: Closure that logs without attributes
    private func performLog(
        _ message: String,
        attributes: [String: Any]?,
        logWithAttrs: (String, [String: Any]) -> Void,
        logSimple: (String) -> Void
    ) {
        guard isSentryEnabled else { return }
        if let attrs = attributes {
            logWithAttrs(message, attrs)
        } else {
            logSimple(message)
        }
    }

    /// Private helper for error-level logs that include Error objects
    /// - Parameters:
    ///   - message: The log message
    ///   - error: Optional Error object to extract type and message from
    ///   - attributes: Optional structured attributes
    ///   - logWithAttrs: Closure that logs with attributes
    ///   - logSimple: Closure that logs without attributes
    private func performErrorLog(
        _ message: String,
        error: Error?,
        attributes: [String: Any]?,
        logWithAttrs: (String, [String: Any]) -> Void,
        logSimple: (String) -> Void
    ) {
        guard isSentryEnabled else { return }
        var attrs = attributes ?? [:]
        if let error = error {
            attrs["error.type"] = String(describing: type(of: error))
            attrs["error.message"] = error.localizedDescription
        }
        if attrs.isEmpty {
            logSimple(message)
        } else {
            logWithAttrs(message, attrs)
        }
    }

    /// Log a trace-level message (most verbose, for detailed debugging)
    func logTrace(_ message: String, attributes: [String: Any]? = nil) {
        performLog(
            message,
            attributes: attributes,
            logWithAttrs: SentrySDK.logger.trace,
            logSimple: SentrySDK.logger.trace
        )
    }

    /// Log a debug-level message
    func logDebug(_ message: String, attributes: [String: Any]? = nil) {
        performLog(
            message,
            attributes: attributes,
            logWithAttrs: SentrySDK.logger.debug,
            logSimple: SentrySDK.logger.debug
        )
    }

    /// Log an info-level message
    func logInfo(_ message: String, attributes: [String: Any]? = nil) {
        performLog(
            message,
            attributes: attributes,
            logWithAttrs: SentrySDK.logger.info,
            logSimple: SentrySDK.logger.info
        )
    }

    /// Log a warning-level message
    func logWarning(_ message: String, attributes: [String: Any]? = nil) {
        performLog(
            message,
            attributes: attributes,
            logWithAttrs: SentrySDK.logger.warn,
            logSimple: SentrySDK.logger.warn
        )
    }

    /// Log an error-level message
    func logError(_ message: String, error: Error? = nil, attributes: [String: Any]? = nil) {
        performErrorLog(
            message,
            error: error,
            attributes: attributes,
            logWithAttrs: SentrySDK.logger.error,
            logSimple: SentrySDK.logger.error
        )
    }

    /// Log a fatal-level message (critical errors)
    func logFatal(_ message: String, error: Error? = nil, attributes: [String: Any]? = nil) {
        performErrorLog(
            message,
            error: error,
            attributes: attributes,
            logWithAttrs: SentrySDK.logger.fatal,
            logSimple: SentrySDK.logger.fatal
        )
    }

    // MARK: - Performance Monitoring & Tracing

    /// Start a transaction for performance monitoring
    /// - Parameters:
    ///   - name: Transaction name (e.g., "HomeView.loadData")
    ///   - operation: Operation type (e.g., "ui.load", "http.client", "db.query")
    ///   - bindToScope: If true, binds to current scope for child span access
    func startTransaction(name: String, operation: String, bindToScope: Bool = false) -> (any Span)? {
        guard isSentryEnabled else { return nil }
        return SentrySDK.startTransaction(name: name, operation: operation, bindToScope: bindToScope)
    }

    /// Get the current active span from scope (useful for adding child spans)
    var currentSpan: (any Span)? {
        guard isSentryEnabled else { return nil }
        return SentrySDK.span
    }

    /// Start a child span on the current transaction
    /// Use this within a transaction context to track sub-operations
    /// - Parameters:
    ///   - operation: Operation type (e.g., "db.query", "http.client", "serialize")
    ///   - description: Human-readable description of what this span measures
    func startSpan(operation: String, description: String) -> (any Span)? {
        guard isSentryEnabled else { return nil }
        return SentrySDK.span?.startChild(operation: operation, description: description)
    }

    /// Measure the duration of a code block
    func measure<T>(name: String, operation: String, block: () throws -> T) rethrows -> T {
        let transaction = startTransaction(name: name, operation: operation)
        defer { transaction?.finish() }
        return try block()
    }

    /// Measure async operation with optional data attributes
    func measureAsync<T>(
        name: String,
        operation: String,
        data: [String: Any]? = nil,
        block: () async throws -> T
    ) async rethrows -> T {
        let transaction = startTransaction(name: name, operation: operation, bindToScope: true)

        // Add custom data to transaction
        if let data = data {
            for (key, value) in data {
                transaction?.setData(value: value, key: key)
            }
        }

        do {
            let result = try await block()
            transaction?.finish(status: .ok)
            return result
        } catch {
            transaction?.setData(value: error.localizedDescription, key: "error")
            transaction?.finish(status: .internalError)
            throw error
        }
    }

    /// Trace a database operation (Supabase query)
    /// Creates a span within the current transaction context
    func traceDBOperation<T>(
        table: String,
        operation: String,
        block: () async throws -> T
    ) async rethrows -> T {
        let span = startSpan(operation: "db.\(operation)", description: "\(operation) \(table)")

        do {
            let result = try await block()
            span?.setData(value: table, key: "db.table")
            span?.finish(status: .ok)
            return result
        } catch {
            span?.setData(value: error.localizedDescription, key: "error")
            span?.finish(status: .internalError)
            throw error
        }
    }

    /// Trace a network/API call
    /// Creates a span within the current transaction context
    func traceAPICall<T>(
        endpoint: String,
        method: String = "POST",
        block: () async throws -> T
    ) async rethrows -> T {
        let span = startSpan(operation: "http.client", description: "\(method) \(endpoint)")
        span?.setData(value: method, key: "http.method")
        span?.setData(value: endpoint, key: "http.url")

        do {
            let result = try await block()
            span?.setData(value: 200, key: "http.status_code")
            span?.finish(status: .ok)
            return result
        } catch {
            span?.setData(value: error.localizedDescription, key: "error")
            span?.finish(status: .internalError)
            throw error
        }
    }

    /// Report that a view is fully displayed (for TTFD tracking)
    /// Call this after all async data loading is complete
    func reportFullyDisplayed() {
        guard isSentryEnabled else { return }
        SentrySDK.reportFullyDisplayed()
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
