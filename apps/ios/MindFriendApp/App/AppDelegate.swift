import UIKit
import GoogleSignIn

/// AppDelegate handles system-level callbacks including push notifications
class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Initialize crash reporting first (before anything else can crash)
        CrashReporter.shared.initialize()
        CrashReporter.shared.setAppContext()

        // Track app launch
        Analytics.shared.track(.appLaunched, properties: [
            "launch_options": launchOptions?.keys.map { $0.rawValue } ?? []
        ])

        // Check if launched from notification
        if let notification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            CrashReporter.shared.addBreadcrumb(
                category: "app",
                message: "Launched from notification",
                data: ["notification_type": notification["type"] as? String ?? "unknown"]
            )
        }

        return true
    }

    // MARK: - Push Notifications

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            NotificationManager.shared.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationManager.shared.didFailToRegisterForRemoteNotifications(withError: error)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Handle silent push notifications for background refresh
        CrashReporter.shared.addBreadcrumb(
            category: "notification",
            message: "Received background notification",
            data: userInfo as? [String: Any]
        )

        // Process notification (e.g., refresh data)
        completionHandler(.newData)
    }

    // MARK: - URL Handling

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        // Handle Google Sign-In callback
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }

        // Handle custom deep links (mindfriend://)
        if url.scheme == "mindfriend" {
            handleDeepLink(url)
            return true
        }

        return false
    }

    private func handleDeepLink(_ url: URL) {
        CrashReporter.shared.addBreadcrumb(
            category: "deeplink",
            message: "Received deep link",
            data: ["url": CrashReporter.sanitizeURL(url)]
        )

        Analytics.shared.track(.featureUsed, properties: [
            "feature": "deep_link",
            "host": url.host ?? "unknown",
            "path": url.path
        ])

        // Post notification for app to handle navigation
        NotificationCenter.default.post(
            name: .deepLinkReceived,
            object: nil,
            userInfo: ["url": url]
        )
    }

    // MARK: - Background URL Session (Offline Downloads)

    /// Stores background completion handlers by session identifier
    private var backgroundCompletionHandlers: [String: () -> Void] = [:]

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        // Store the completion handler
        backgroundCompletionHandlers[identifier] = completionHandler

        // TODO: OfflineContentService not added to Xcode project target
        // Temporarily commented out - file exists but not in build target
        // Task { @MainActor in
        //     OfflineContentService.shared.setBackgroundCompletionHandler(completionHandler)
        // }
    }

    /// Call this when background URL session finishes
    func urlSessionDidFinishEvents(forBackgroundURLSession identifier: String) {
        DispatchQueue.main.async {
            if let completionHandler = self.backgroundCompletionHandlers.removeValue(forKey: identifier) {
                completionHandler()
            }
        }
    }

    // MARK: - App Lifecycle

    func applicationDidBecomeActive(_ application: UIApplication) {
        Analytics.shared.track(.appForegrounded)

        // Clear badge when app becomes active
        Task { @MainActor in
            await NotificationManager.shared.clearBadge()
        }
    }

    func applicationWillResignActive(_ application: UIApplication) {
        Analytics.shared.track(.appBackgrounded)
        Analytics.shared.flush()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Flush any pending analytics
        Analytics.shared.flush()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        Analytics.shared.flush()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let deepLinkReceived = Notification.Name("deepLinkReceived")
}
