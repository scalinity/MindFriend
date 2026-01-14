import Foundation
import UserNotifications
import UIKit

/// Notification types the app can send/receive
enum NotificationType: String {
    case dailyQuest = "daily_quest"
    case questReminder = "quest_reminder"
    case streakReminder = "streak_reminder"
    case circleActivity = "circle_activity"
    case chatMessage = "chat_message"
    case systemMessage = "system_message"
}

/// Deep link destinations from notifications
enum NotificationDeepLink {
    case quest(id: String)
    case chat(conversationId: String)
    case circle(id: String)
    case mood
    case settings
    case none
}

/// Manages push notifications and local notifications
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published private(set) var isAuthorized = false
    @Published private(set) var deviceToken: String?

    private let container: DependencyContainer?
    private var pendingDeepLink: NotificationDeepLink?

    override init() {
        self.container = nil
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    init(container: DependencyContainer) {
        self.container = container
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Authorization

    /// Request notification authorization
    func requestAuthorization() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .badge, .sound, .provisional]
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
            isAuthorized = granted

            if granted {
                await registerForRemoteNotifications()
            }

            Analytics.shared.track(.featureUsed, properties: [
                "feature": "notifications",
                "action": "authorization_requested",
                "granted": granted
            ])

            return granted
        } catch {
            print("[NotificationManager] Authorization error: \(error)")
            error.report(context: ["action": "request_notification_authorization"])
            return false
        }
    }

    /// Check current authorization status
    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Register for remote notifications on the main queue
    private func registerForRemoteNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: - Device Token

    /// Called when device token is received from APNS
    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = tokenString

        print("[NotificationManager] Device token: \(tokenString)")

        // Register with backend
        Task {
            await registerDeviceWithBackend(token: tokenString)
        }
    }

    /// Called when registration fails
    func didFailToRegisterForRemoteNotifications(withError error: Error) {
        print("[NotificationManager] Failed to register: \(error)")
        error.report(context: ["action": "register_remote_notifications"])
    }

    /// Register device token with backend
    private func registerDeviceWithBackend(token: String) async {
        guard let container = container else { return }

        let deviceModel = UIDevice.current.model
        let osVersion = UIDevice.current.systemVersion

        do {
            try await container.supabaseDataService.registerDevice(
                apnsToken: token,
                deviceModel: deviceModel,
                osVersion: osVersion
            )

            Analytics.shared.track(.featureUsed, properties: [
                "feature": "push_notifications",
                "action": "device_registered"
            ])
        } catch {
            print("[NotificationManager] Failed to register device: \(error)")
            error.report(context: ["action": "register_device_backend"])
        }
    }

    // MARK: - Notification Handling

    /// Handle notification when app is in foreground
    func handleForegroundNotification(_ notification: UNNotification) -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        print("[NotificationManager] Foreground notification: \(userInfo)")

        // Add breadcrumb
        CrashReporter.shared.addBreadcrumb(
            category: "notification",
            message: "Received foreground notification",
            data: ["title": notification.request.content.title]
        )

        // Show banner for most notifications
        return [.banner, .sound, .badge]
    }

    /// Handle notification tap/interaction
    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        print("[NotificationManager] Notification tapped: \(userInfo)")

        let deepLink = parseDeepLink(from: userInfo)

        Analytics.shared.track(.featureUsed, properties: [
            "feature": "push_notifications",
            "action": "notification_tapped",
            "notification_type": userInfo["type"] as? String ?? "unknown"
        ])

        // Store deep link for navigation
        pendingDeepLink = deepLink

        // Post notification for app to handle navigation
        NotificationCenter.default.post(
            name: .notificationDeepLinkReceived,
            object: nil,
            userInfo: ["deepLink": deepLink]
        )
    }

    /// Parse deep link from notification payload
    private func parseDeepLink(from userInfo: [AnyHashable: Any]) -> NotificationDeepLink {
        guard let type = userInfo["type"] as? String else { return .none }

        switch type {
        case "daily_quest", "quest_reminder":
            if let questId = userInfo["quest_id"] as? String {
                return .quest(id: questId)
            }
        case "chat_message":
            if let conversationId = userInfo["conversation_id"] as? String {
                return .chat(conversationId: conversationId)
            }
        case "circle_activity":
            if let circleId = userInfo["circle_id"] as? String {
                return .circle(id: circleId)
            }
        case "mood_reminder":
            return .mood
        default:
            break
        }

        return .none
    }

    /// Consume pending deep link
    func consumePendingDeepLink() -> NotificationDeepLink? {
        defer { pendingDeepLink = nil }
        return pendingDeepLink
    }

    // MARK: - Local Notifications

    /// Schedule a local notification
    func scheduleLocalNotification(
        id: String,
        title: String,
        body: String,
        date: Date,
        userInfo: [String: Any] = [:]
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        try await UNUserNotificationCenter.current().add(request)
    }

    /// Schedule daily quest reminder
    func scheduleDailyQuestReminder(at time: DateComponents) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Daily Quest Available"
        content.body = "Your wellness quest for today is ready. Take a moment for yourself."
        content.sound = .default
        content.userInfo = ["type": NotificationType.dailyQuest.rawValue]

        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        let request = UNNotificationRequest(identifier: "daily_quest_reminder", content: content, trigger: trigger)

        try await UNUserNotificationCenter.current().add(request)
    }

    /// Cancel a scheduled notification
    func cancelNotification(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Cancel all notifications
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Badge Management

    /// Update app badge count
    func setBadgeCount(_ count: Int) async {
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(count)
        } catch {
            print("[NotificationManager] Failed to set badge: \(error)")
        }
    }

    /// Clear app badge
    func clearBadge() async {
        await setBadgeCount(0)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            let options = handleForegroundNotification(notification)
            completionHandler(options)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            handleNotificationResponse(response)
            completionHandler()
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let notificationDeepLinkReceived = Notification.Name("notificationDeepLinkReceived")
}
