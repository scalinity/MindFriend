import UIKit
import UserNotifications

/// Extension to AppDelegate for medication notification category registration.
///
/// Note: Medication notification **action handling** (LOG_TAKEN, SKIP_MEDICATION, SNOOZE)
/// lives in NotificationManager.handleMedicationNotificationAction() because
/// UNUserNotificationCenter supports only a single delegate, and NotificationManager
/// is the delegate for the lifetime of the app.
extension AppDelegate {

    /// Register notification categories for medication actions.
    /// Call this during app launch setup.
    func registerMedicationNotificationCategories() {
        let logAction = UNNotificationAction(
            identifier: "LOG_TAKEN",
            title: "Take",
            options: [.foreground]
        )

        let skipAction = UNNotificationAction(
            identifier: "SKIP_MEDICATION",
            title: "Skip",
            options: []
        )

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE",
            title: "Snooze 15 min",
            options: []
        )

        let medicationCategory = UNNotificationCategory(
            identifier: "MEDICATION",
            actions: [logAction, skipAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([medicationCategory])
    }
}
