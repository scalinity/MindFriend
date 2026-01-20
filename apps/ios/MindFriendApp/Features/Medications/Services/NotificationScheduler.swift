import UserNotifications
import Foundation
import OSLog
#if canImport(UIKit)
import UIKit
#endif

protocol NotificationSchedulerProtocol {
    func schedule(medication: Medication) async
    func cancel(medicationId: UUID) async
    func reschedule(medication: Medication) async
}

@MainActor
final class NotificationScheduler: NotificationSchedulerProtocol {
    private let notificationCenter = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.mindfriend", category: "Notifications")

    func schedule(medication: Medication) async {
        guard medication.reminderEnabled else { return }

        // Request notification permissions if needed
        do {
            let settings = await notificationCenter.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            }
        } catch {
            logger.error("Failed to request notification permission: \(error.localizedDescription)")
            return
        }

        // Schedule a notification for each scheduled time
        for (index, time) in medication.scheduledTimes.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Medication Reminder"
            content.body = medication.useGenericNotification
                ? "Time for your medication"
                : "Time to take \(medication.name)"
            content.sound = .default
            content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)
            content.categoryIdentifier = "MEDICATION"
            content.userInfo["timestamp"] = ISO8601DateFormatter().string(from: Date())

            // User info for handling actions
            content.userInfo = [
                "medicationId": medication.id.uuidString,
                "medicationName": medication.name,
                "index": index,
            ]

            // Extract hour and minute from scheduled time
            let hour = Calendar.current.component(.hour, from: time)
            let minute = Calendar.current.component(.minute, from: time)

            var dateComponents = DateComponents()
            dateComponents.hour = hour
            dateComponents.minute = minute

            // Repeat daily by default
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

            // Create unique identifier for this notification
            let identifier = "med-\(medication.id.uuidString)-\(String(format: "%02d", hour))-\(String(format: "%02d", minute))-\(index)"

            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            do {
                try await notificationCenter.add(request)
                logger.info("Scheduled medication notification: \(identifier)")
            } catch {
                logger.error("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }

    func cancel(medicationId: UUID) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()

        let toRemove = pending
            .filter { $0.identifier.hasPrefix("med-\(medicationId.uuidString)") }
            .map { $0.identifier }

        center.removePendingNotificationRequests(withIdentifiers: toRemove)
        logger.info("Cancelled \(toRemove.count) notifications for medication: \(medicationId.uuidString)")
    }

    func reschedule(medication: Medication) async {
        await cancel(medicationId: medication.id)
        await schedule(medication: medication)
    }
}

// MARK: - Notification Category Setup

final class NotificationCategoryManager {
    static let shared = NotificationCategoryManager()

    private let notificationCenter = UNUserNotificationCenter.current()

    func registerCategories() {
        let logTakenAction = UNNotificationAction(
            identifier: "LOG_TAKEN",
            title: "Mark as Taken",
            options: [.foreground]
        )

        let skipAction = UNNotificationAction(
            identifier: "SKIP_MEDICATION",
            title: "Skip",
            options: [.destructive]
        )

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE",
            title: "Snooze",
            options: []
        )

        let medicationCategory = UNNotificationCategory(
            identifier: "MEDICATION",
            actions: [logTakenAction, skipAction, snoozeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        notificationCenter.setNotificationCategories([medicationCategory])
    }
}
