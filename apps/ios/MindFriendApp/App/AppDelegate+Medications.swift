import UIKit
import UserNotifications

/// Extension to AppDelegate for handling medication notification actions
extension AppDelegate: UNUserNotificationCenterDelegate {
    // MARK: - Notification Handling

    /// Called when a notification arrives while app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        // Handle medication notifications
        if let medicationId = userInfo["medicationId"] as? String {
            Log.general.info("[Notifications] Medication reminder received: \(medicationId)")
        }

        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    /// Called when user interacts with a notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        guard let medicationIdString = userInfo["medicationId"] as? String,
              let medicationId = UUID(uuidString: medicationIdString) else {
            completionHandler()
            return
        }

        let scheduledAtString = userInfo["timestamp"] as? String
        let scheduledAt = scheduledAtString.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()

        // Handle different notification actions
        switch response.actionIdentifier {
        case "LOG_TAKEN":
            handleLogMedicationTaken(
                medicationId: medicationId,
                scheduledAt: scheduledAt,
                completionHandler: completionHandler
            )

        case "SKIP_MEDICATION":
            handleSkipMedication(
                medicationId: medicationId,
                scheduledAt: scheduledAt,
                completionHandler: completionHandler
            )

        case "SNOOZE":
            handleSnooze(
                medicationId: medicationId,
                scheduledAt: scheduledAt,
                completionHandler: completionHandler
            )

        case UNNotificationDefaultActionIdentifier:
            // User tapped on the notification (not an action button)
            handleNotificationTap(medicationId: medicationId)
            completionHandler()

        default:
            completionHandler()
        }
    }

    // MARK: - Action Handlers

    private func handleLogMedicationTaken(
        medicationId: UUID,
        scheduledAt: Date,
        completionHandler: @escaping () -> Void
    ) {
        Log.general.info("[Medications] User marked medication as taken: \(medicationId)")

        Task {
            do {
                let medicationService = DependencyContainer.shared.medicationService
                try await medicationService.logDose(
                    medicationId: medicationId,
                    scheduledAt: scheduledAt,
                    notes: "Logged from notification"
                )

                // Update badge count
                await updateBadgeCount()

                completionHandler()
            } catch {
                Log.general.error("[Medications] Failed to log medication: \(error.localizedDescription)")
                completionHandler()
            }
        }
    }

    private func handleSkipMedication(
        medicationId: UUID,
        scheduledAt: Date,
        completionHandler: @escaping () -> Void
    ) {
        Log.general.info("[Medications] User skipped medication: \(medicationId)")

        Task {
            do {
                let medicationService = DependencyContainer.shared.medicationService
                try await medicationService.skipDose(
                    medicationId: medicationId,
                    scheduledAt: scheduledAt,
                    reason: "Skipped via notification"
                )

                completionHandler()
            } catch {
                Log.general.error("[Medications] Failed to skip medication: \(error.localizedDescription)")
                completionHandler()
            }
        }
    }

    private func handleSnooze(
        medicationId: UUID,
        scheduledAt: Date,
        completionHandler: @escaping () -> Void
    ) {
        Log.general.info("[Medications] User snoozed medication: \(medicationId)")

        // Schedule a new notification 15 minutes from now
        let snoozeTime = Date(timeIntervalSinceNow: 15 * 60)

        Task {
            do {
                let medicationService = DependencyContainer.shared.medicationService

                // Find the medication to reschedule
                if let medication = medicationService.medications.first(where: { $0.id == medicationId }) {
                    // Create a one-time snooze notification
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
                    Log.general.info("[Medications] Scheduled snooze notification for medication: \(medicationId)")
                }

                completionHandler()
            } catch {
                Log.general.error("[Medications] Failed to schedule snooze: \(error.localizedDescription)")
                completionHandler()
            }
        }
    }

    private func handleNotificationTap(medicationId: UUID) {
        Log.general.info("[Medications] User tapped medication notification: \(medicationId)")

        // Navigate to medication detail screen
        // This would be handled by the DeepLinkRouter in the app state
    }

    // MARK: - Helper Methods

    @MainActor
    private func updateBadgeCount() async {
        // Decrement badge count when medication is logged
        let current = UIApplication.shared.applicationIconBadgeNumber
        UIApplication.shared.applicationIconBadgeNumber = max(0, current - 1)
    }
}
