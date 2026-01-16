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

        // TODO: Re-enable Sentry when SDK compatibility is resolved
        // For now, initialize crash reporter without Sentry

        isInitialized = true
        print("[CrashReporter] Initialized (Sentry SDK disabled)")
    }

    // MARK: - User Identification

    /// Set the current user for crash reports
    func setUser(id: String, email: String? = nil, username: String? = nil) {
        guard isInitialized else { return }
        let user = Sentry.User(userId: id)
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
        let sentryEvent = Sentry.Event(error: error)

        if let context = context {
            sentryEvent.extra = context.mapValues { "\($0)" }
        }

        SentrySDK.capture(event: sentryEvent)
    }

    /// Capture a message with optional context
    func capture(message: String, context: [String: Any]? = nil) {
        guard isInitialized else { return }
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
        guard isInitialized else { return }
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
