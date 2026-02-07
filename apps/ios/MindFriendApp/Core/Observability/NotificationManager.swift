import Foundation
import UserNotifications
import UIKit
import OSLog

/// Notification types the app can send/receive
enum NotificationType: String {
    case dailyQuest = "daily_quest"
    case questReminder = "quest_reminder"
    case streakReminder = "streak_reminder"
    case circleActivity = "circle_activity"
    case chatMessage = "chat_message"
    case systemMessage = "system_message"
    // Smart notification types
    case hug = "hug"
    case streakRisk = "streak_risk"
    case weeklySummary = "weekly_summary"
    case challenge = "challenge"
    // Sleep feature
    case bedtimeReminder = "bedtime_reminder"
}

/// Deep link destinations from notifications
enum NotificationDeepLink {
    case quest(id: String? = nil)
    case chat(conversationId: String)
    case circle(id: String)
    case mood
    case settings
    case insights
    case buddy(code: String)
    case micro(templateId: String? = nil)
    case sleep(contentId: String? = nil)
    case none
}

/// Manages push notifications and local notifications
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published private(set) var isAuthorized = false
    @Published private(set) var deviceToken: String?

    private var container: DependencyContainer?
    private var pendingDeepLink: NotificationDeepLink?
    private var pendingTokenRegistration: String?

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

    /// Configure the notification manager with the dependency container.
    /// Call this after container is initialized to register any pending device token.
    func configure(container: DependencyContainer) {
        self.container = container

        // Register pending token if we received one before container was available
        if let pendingToken = pendingTokenRegistration {
            pendingTokenRegistration = nil
            Task {
                await registerDeviceWithBackend(token: pendingToken)
            }
        }
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
            Log.notifications.debug("[Notifications] Authorization error: \(error)")
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

        // PRIVACY FIX #009: Redact device token in logs - only show prefix in DEBUG builds
        #if DEBUG
        Log.notifications.debug("[Notifications] Device token (first 8): \(tokenString.prefix(8))...")
        #else
        Log.notifications.debug("[Notifications] Device token registered")
        #endif

        // Register with backend
        Task {
            await registerDeviceWithBackend(token: tokenString)
        }
    }

    /// Called when registration fails
    func didFailToRegisterForRemoteNotifications(withError error: Error) {
        Log.notifications.debug("[Notifications] Failed to register: \(error)")
        error.report(context: ["action": "register_remote_notifications"])
    }

    /// Register device token with backend
    private func registerDeviceWithBackend(token: String) async {
        guard let container = container else {
            // Store token for later registration when container is configured
            pendingTokenRegistration = token
            Log.notifications.debug("[Notifications] Container not ready, storing token for later")
            return
        }

        do {
            try await container.supabaseDataService.registerDevice(apnsToken: token)

            Analytics.shared.track(.featureUsed, properties: [
                "feature": "push_notifications",
                "action": "device_registered"
            ])
        } catch {
            Log.notifications.debug("[Notifications] Failed to register device: \(error)")
            error.report(context: ["action": "register_device_backend"])
        }
    }

    // MARK: - Notification Handling

    /// Handle notification when app is in foreground
    func handleForegroundNotification(_ notification: UNNotification) -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        Log.notifications.debug("[Notifications] Foreground notification: \(userInfo)")

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
        Log.notifications.debug("[Notifications] Notification tapped: \(userInfo)")
        
        // Handle medication notification actions (LOG_TAKEN, SKIP_MEDICATION, SNOOZE)
        if let medicationIdString = userInfo["medicationId"] as? String,
           let medicationId = UUID(uuidString: medicationIdString) {
            let scheduledAtString = userInfo["timestamp"] as? String
            let scheduledAt = scheduledAtString.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
            handleMedicationNotificationAction(
                response: response,
                medicationId: medicationId,
                scheduledAt: scheduledAt
            )
            return
        }
        
        // Handle intervention notifications specially
        if let type = userInfo["type"] as? String, type == "intervention" {
            Task {
                await handleInterventionNotificationResponse(response)
            }
            return
        }

        let deepLink = parseDeepLink(from: userInfo)
        let notificationType = userInfo["type"] as? String ?? "unknown"

        Analytics.shared.track(.notificationOpened, properties: [
            "notification_type": notificationType,
            "deep_link": String(describing: deepLink)
        ])

        // Track notification open in backend for analytics
        if let notificationId = userInfo["notification_id"] as? String {
            Task {
                await markNotificationOpened(id: notificationId)
            }
        }

        // Store deep link for navigation
        pendingDeepLink = deepLink

        // Post notification for app to handle navigation
        NotificationCenter.default.post(
            name: .notificationDeepLinkReceived,
            object: nil,
            userInfo: ["deepLink": deepLink]
        )
    }
    
    /// Handle intervention notification with actions (complete, dismiss, remind later)
    private func handleInterventionNotificationResponse(_ response: UNNotificationResponse) async {
        guard let container = container else {
            Log.notifications.debug("[Notifications] Container not available for intervention response")
            return
        }
        
        let notificationManager = container.interventionNotificationManager
        let interventionService = container.interventionService
        
        // Parse intervention deep link
        guard let deepLink = await notificationManager.handleNotificationResponse(response) else {
            Log.notifications.debug("[Notifications] Failed to parse intervention deep link")
            return
        }
        
        // Handle action
        switch deepLink.action {
        case .complete:
            // Navigate to intervention and mark as completed
            do {
                try await interventionService.updateDelivery(
                    deliveryId: deepLink.deliveryId,
                    completed: true
                )
                
                // Navigate to micro-moments hub
                let navDeepLink = NotificationDeepLink.micro(templateId: deepLink.interventionId.uuidString)
                NotificationCenter.default.post(
                    name: .notificationDeepLinkReceived,
                    object: nil,
                    userInfo: ["deepLink": navDeepLink]
                )
                
                Log.notifications.debug("[Notifications] Intervention marked complete via notification action")
            } catch {
                Log.notifications.debug("[Notifications] Failed to mark intervention complete: \(error)")
            }
            
        case .dismiss:
            // Mark as dismissed
            do {
                try await interventionService.updateDelivery(
                    deliveryId: deepLink.deliveryId,
                    completed: false
                )
                Log.notifications.debug("[Notifications] Intervention dismissed via notification action")
            } catch {
                Log.notifications.debug("[Notifications] Failed to mark intervention dismissed: \(error)")
            }
            
        case .remindLater:
            // Reschedule for 30 minutes later using the notification response content
            do {
                try await notificationManager.rescheduleFromResponse(response)
                Log.notifications.debug("[Notifications] Intervention rescheduled for 30 minutes later")
            } catch {
                Log.notifications.error("[Notifications] Failed to reschedule intervention: \(error)")
            }
            
        case .open:
            // Navigate to intervention
            let navDeepLink = NotificationDeepLink.micro(templateId: deepLink.interventionId.uuidString)
            NotificationCenter.default.post(
                name: .notificationDeepLinkReceived,
                object: nil,
                userInfo: ["deepLink": navDeepLink]
            )
            Log.notifications.debug("[Notifications] Opening intervention from notification")
        }
        
        // Remove delivered notification
        notificationManager.removeDeliveredNotification(deliveryId: deepLink.deliveryId)
    }

    /// Mark notification as opened in backend
    private func markNotificationOpened(id: String) async {
        guard let container = container else { return }

        do {
            try await container.supabaseDataService.markNotificationOpened(notificationId: id)
        } catch {
            Log.notifications.debug("[Notifications] Failed to mark notification opened: \(error)")
        }
    }

    /// Parse deep link from notification payload
    private func parseDeepLink(from userInfo: [AnyHashable: Any]) -> NotificationDeepLink {
        // Check for deep_link URL first (from smart notifications)
        if let deepLinkUrl = userInfo["deep_link"] as? String {
            return parseDeepLinkUrl(deepLinkUrl)
        }

        guard let type = userInfo["type"] as? String else { return .none }

        switch type {
        case "daily_quest", "quest_reminder":
            let questId = userInfo["quest_id"] as? String
            return .quest(id: questId)

        case "streak_risk":
            // Streak risk goes to quest screen
            return .quest(id: nil)

        case "chat_message":
            if let conversationId = userInfo["conversation_id"] as? String {
                return .chat(conversationId: conversationId)
            }

        case "circle_activity", "hug", "challenge":
            if let circleId = userInfo["circle_id"] as? String {
                return .circle(id: circleId)
            }

        case "weekly_summary":
            return .insights

        case "mood_reminder":
            return .mood
        
        case "intervention":
            // Intervention notifications from InterventionNotificationManager
            let interventionId = userInfo["intervention_id"] as? String
            return .micro(templateId: interventionId)

        case "bedtime_reminder":
            let contentId = userInfo["content_id"] as? String
            return .sleep(contentId: contentId)

        default:
            break
        }

        return .none
    }

    /// Parse deep link from URL string (e.g., "mindfriend://circle/123")
    /// Internal for testability
    func parseDeepLinkUrl(_ urlString: String) -> NotificationDeepLink {
        guard let url = URL(string: urlString),
              url.scheme == "mindfriend" else {
            return .none
        }

        let path = url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch path {
        case "quest":
            let questId = pathComponents.first
            return .quest(id: questId)

        case "circle":
            if let circleId = pathComponents.first {
                return .circle(id: circleId)
            }

        case "chat":
            if let conversationId = pathComponents.first {
                return .chat(conversationId: conversationId)
            }

        case "insights":
            return .insights

        case "mood":
            return .mood

        case "settings":
            return .settings

        case "buddy":
            if let code = pathComponents.first {
                return .buddy(code: code)
            }

        case "sleep":
            let contentId = pathComponents.first
            return .sleep(contentId: contentId)

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

    /// Schedule bedtime reminder for sleep feature
    /// - Parameter time: DateComponents with hour and minute for daily reminder
    /// - Parameter contentId: Optional specific sleep content to deep link to
    func scheduleBedtimeReminder(at time: DateComponents, contentId: String? = nil) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Time to Wind Down"
        content.body = "Ready for restful sleep? Start your bedtime routine now."
        content.sound = .default

        var userInfo: [String: Any] = [
            "type": NotificationType.bedtimeReminder.rawValue,
            "deep_link": contentId != nil ? "mindfriend://sleep/\(contentId!)" : "mindfriend://sleep"
        ]
        if let contentId = contentId {
            userInfo["content_id"] = contentId
        }
        content.userInfo = userInfo

        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        let request = UNNotificationRequest(identifier: "bedtime_reminder", content: content, trigger: trigger)

        try await UNUserNotificationCenter.current().add(request)

        Analytics.shared.track(.featureUsed, properties: [
            "feature": "sleep",
            "action": "bedtime_reminder_scheduled",
            "hour": time.hour ?? -1,
            "minute": time.minute ?? -1
        ])
    }

    /// Cancel bedtime reminder
    func cancelBedtimeReminder() {
        cancelNotification(id: "bedtime_reminder")
    }

    /// Cancel a scheduled notification
    func cancelNotification(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Cancel all notifications
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - App Activity Tracking

    /// Track app open time for smart notification timing
    /// Call this when app launches or becomes active
    func trackAppOpen() {
        guard let container = container else { return }

        Task {
            do {
                try await container.supabaseDataService.updateTypicalActiveHour()
            } catch {
                Log.notifications.debug("[Notifications] Failed to track app open: \(error)")
            }
        }
    }

    // MARK: - Badge Management

    /// Update app badge count
    func setBadgeCount(_ count: Int) async {
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(count)
        } catch {
            Log.notifications.debug("[Notifications] Failed to set badge: \(error)")
        }
    }

    /// Clear app badge
    func clearBadge() async {
        await setBadgeCount(0)
    }

    // MARK: - Medication Notification Actions

    /// Handle medication notification actions (LOG_TAKEN, SKIP_MEDICATION, SNOOZE)
    private func handleMedicationNotificationAction(
        response: UNNotificationResponse,
        medicationId: UUID,
        scheduledAt: Date
    ) {
        let actionIdentifier = response.actionIdentifier

        switch actionIdentifier {
        case "LOG_TAKEN":
            Task {
                do {
                    let medicationService = DependencyContainer.shared.medicationService
                    try await medicationService.logDose(
                        medicationId: medicationId,
                        scheduledAt: scheduledAt,
                        notes: "Logged from notification"
                    )
                    let current = UIApplication.shared.applicationIconBadgeNumber
                    UIApplication.shared.applicationIconBadgeNumber = max(0, current - 1)
                    Log.notifications.info("[Medications] Logged medication taken: \(medicationId)")
                } catch {
                    Log.notifications.error("[Medications] Failed to log medication: \(error.localizedDescription)")
                }
            }

        case "SKIP_MEDICATION":
            Task {
                do {
                    let medicationService = DependencyContainer.shared.medicationService
                    try await medicationService.skipDose(
                        medicationId: medicationId,
                        scheduledAt: scheduledAt,
                        reason: "Skipped via notification"
                    )
                    Log.notifications.info("[Medications] Skipped medication: \(medicationId)")
                } catch {
                    Log.notifications.error("[Medications] Failed to skip medication: \(error.localizedDescription)")
                }
            }

        case "SNOOZE":
            Task {
                do {
                    let medicationService = DependencyContainer.shared.medicationService
                    let snoozeTime = Date(timeIntervalSinceNow: 15 * 60)

                    if let medication = medicationService.medications.first(where: { $0.id == medicationId }) {
                        let content = UNMutableNotificationContent()
                        content.title = "Medication Reminder"
                        content.body = medication.useGenericNotification
                            ? "Time for your medication"
                            : "Time to take \(medication.name)"
                        content.sound = .default
                        content.categoryIdentifier = "MEDICATION"
                        content.userInfo = [
                            "medicationId": medicationId.uuidString,
                            "medicationName": medication.name,
                            "timestamp": ISO8601DateFormatter().string(from: snoozeTime)
                        ]

                        var dateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: snoozeTime)
                        dateComponents.second = 0

                        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
                        let request = UNNotificationRequest(
                            identifier: "med-snooze-\(medicationId.uuidString)-\(Date().timeIntervalSince1970)",
                            content: content,
                            trigger: trigger
                        )

                        try await UNUserNotificationCenter.current().add(request)
                        Log.notifications.info("[Medications] Snoozed medication: \(medicationId)")
                    }
                } catch {
                    Log.notifications.error("[Medications] Failed to snooze medication: \(error.localizedDescription)")
                }
            }

        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification - navigate to medication detail via deep link
            Log.notifications.info("[Medications] User tapped medication notification: \(medicationId)")

        default:
            break
        }
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
    
    /// Posted when a quest arc is started, paused, resumed, or exited.
    /// HomeView and other views should refresh their quest data when this is received.
    static let questArcDidChange = Notification.Name("questArcDidChange")
}
