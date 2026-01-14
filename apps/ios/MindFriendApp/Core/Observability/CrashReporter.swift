import Foundation
import Sentry
import UIKit

/// Centralized crash reporting and error tracking using Sentry
final class CrashReporter {
    static let shared = CrashReporter()

    private(set) var isInitialized = false

    private init() {}

    // MARK: - Configuration

    /// Initialize Sentry with the provided DSN
    /// Call this early in app launch (before any UI is shown)
    func initialize() {
        guard !isInitialized else { return }

        #if DEBUG
        // Use a different DSN for debug or skip initialization
        let dsn = ProcessInfo.processInfo.environment["SENTRY_DSN_DEBUG"]
        #else
        let dsn = "https://YOUR_SENTRY_DSN_HERE@sentry.io/PROJECT_ID"
        #endif

        guard let sentryDSN = dsn, !sentryDSN.isEmpty, !sentryDSN.contains("YOUR_SENTRY_DSN") else {
            #if DEBUG
            // Silent in debug - this is expected when DSN isn't configured
            #else
            print("[CrashReporter] Sentry DSN not configured, skipping initialization")
            #endif
            return
        }

        SentrySDK.start { options in
            options.dsn = sentryDSN

            // Performance Monitoring
            options.tracesSampleRate = 0.2 // 20% of transactions for performance monitoring

            // Release Health
            options.enableAutoSessionTracking = true
            options.sessionTrackingIntervalMillis = 30000

            // Crash Reporting
            options.attachStacktrace = true
            options.enableCaptureFailedRequests = true

            // Environment
            #if DEBUG
            options.environment = "development"
            options.debug = true
            #else
            options.environment = "production"
            options.debug = false
            #endif

            // App Hang Detection
            options.enableAppHangTracking = true
            options.appHangTimeoutInterval = 2.0

            // Automatic Breadcrumbs
            options.enableAutoBreadcrumbTracking = true

            // Network Breadcrumbs
            options.enableNetworkBreadcrumbs = true

            // Attach Screenshots on Crash
            options.attachScreenshot = true

            // Before Send Hook - scrub sensitive data
            options.beforeSend = { event in
                // Remove any PII from breadcrumbs
                event.breadcrumbs = event.breadcrumbs?.map { breadcrumb in
                    var cleaned = breadcrumb
                    // Remove sensitive query parameters
                    if let urlString = cleaned.data?["url"] as? String,
                       var urlComponents = URLComponents(string: urlString) {
                        urlComponents.queryItems = urlComponents.queryItems?.map { item in
                            if ["token", "key", "password", "email"].contains(item.name.lowercased()) {
                                return URLQueryItem(name: item.name, value: "[REDACTED]")
                            }
                            return item
                        }
                        cleaned.data?["url"] = urlComponents.string
                    }
                    return cleaned
                }
                return event
            }
        }

        isInitialized = true
        print("[CrashReporter] Sentry initialized successfully")
    }

    // MARK: - User Identification

    /// Set the current user for crash reports
    func setUser(id: String, email: String? = nil, username: String? = nil) {
        guard isInitialized else { return }
        let user = User(userId: id)
        user.email = email
        user.username = username
        SentrySDK.setUser(user)
    }

    /// Clear user information (call on logout)
    func clearUser() {
        guard isInitialized else { return }
        SentrySDK.setUser(nil)
    }

    // MARK: - Error Capture

    /// Capture a non-fatal error
    func capture(error: Error, context: [String: Any]? = nil) {
        guard isInitialized else { return }
        let sentryEvent = Event(error: error)

        if let context = context {
            sentryEvent.extra = context.mapValues { "\($0)" }
        }

        SentrySDK.capture(event: sentryEvent)
    }

    /// Capture a message with optional level
    func capture(message: String, level: SentryLevel = .info, context: [String: Any]? = nil) {
        guard isInitialized else { return }
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(level)
            if let context = context {
                for (key, value) in context {
                    scope.setExtra(value: "\(value)", key: key)
                }
            }
        }
    }

    // MARK: - Breadcrumbs

    /// Add a breadcrumb for debugging crash context
    func addBreadcrumb(category: String, message: String, level: SentryLevel = .info, data: [String: Any]? = nil) {
        guard isInitialized else { return }
        let breadcrumb = Breadcrumb(level: level, category: category)
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
        guard isInitialized else { return nil }
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
        guard isInitialized else { return }
        SentrySDK.configureScope { scope in
            scope.setTag(value: value, key: key)
        }
    }

    /// Set extra context data
    func setContext(key: String, value: [String: Any]) {
        guard isInitialized else { return }
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
