import Foundation
import UserNotifications
import UIKit

// MARK: - Habit Notification Service Errors

enum HabitNotificationServiceError: LocalizedError {
    case notificationPermissionDenied
    case invalidReminderTime
    case invalidQuietHours
    case timeZoneError
    case notificationSchedulingFailed(String)

    var errorDescription: String? {
        switch self {
        case .notificationPermissionDenied:
            return "User has not granted notification permission"
        case .invalidReminderTime:
            return "Reminder time must be between 0 and 1440 minutes before anchor time"
        case .invalidQuietHours:
            return "Quiet hours configuration is invalid"
        case .timeZoneError:
            return "Unable to determine user timezone"
        case .notificationSchedulingFailed(let reason):
            return "Failed to schedule notification: \(reason)"
        }
    }
}

// MARK: - Notification Models

struct HabitNotificationPayload {
    let habitId: UUID
    let habitName: String
    let anchorBehavior: String
    let streakCount: Int
    let notificationType: HabitNotificationType

    var userInfo: [AnyHashable: Any] {
        [
            "habitId": habitId.uuidString,
            "habitName": habitName,
            "notificationType": notificationType.rawValue,
            "streakCount": streakCount
        ]
    }
}

enum HabitNotificationType: String {
    case habitReminder = "habit_reminder"
    case streakMilestone = "streak_milestone"
    case habitGraduation = "habit_graduation"
}

// MARK: - Habit Notification Service

@MainActor
final class HabitNotificationService {
    private let userNotificationCenter = UNUserNotificationCenter.current()
    private let calendar = Calendar.current
    private var notificationRequests: [String: UNNotificationRequest] = [:]

    // Configuration constants
    private enum NotificationConfig {
        static let defaultQuietHoursStart = 21  // 9 PM
        static let defaultQuietHoursEnd = 7     // 7 AM
        static let maxReminderMinutes = 1440    // 24 hours
        static let minReminderMinutes = 0
    }

    init() {
        setupNotificationDelegate()
    }

    // MARK: - Permission Management

    /// Request user permission for notifications
    func requestNotificationPermission() async throws -> Bool {
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]

        do {
            let granted = try await userNotificationCenter.requestAuthorization(options: options)
            return granted
        } catch {
            throw HabitNotificationServiceError.notificationPermissionDenied
        }
    }

    /// Check if notifications are authorized
    func checkNotificationAuthorization() async throws -> Bool {
        let settings = await userNotificationCenter.notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    // MARK: - Notification Scheduling

    /// Schedule a reminder for a habit based on anchor time
    /// - Parameters:
    ///   - habit: The habit to schedule notifications for
    ///   - anchorTime: The time of day the anchor habit occurs (e.g., "After breakfast" typically 8 AM)
    ///   - reminderMinutesBefore: How many minutes before anchor time to send reminder (default 5)
    ///   - userTimezone: User's timezone for scheduling
    func scheduleHabitReminder(
        habit: Habit,
        anchorTime: Date,
        userTimezone: TimeZone = TimeZone.current
    ) async throws {
        // Validate reminder time
        guard let reminderMinutes = habit.reminderMinutesBefore,
              reminderMinutes >= NotificationConfig.minReminderMinutes &&
              reminderMinutes <= NotificationConfig.maxReminderMinutes else {
            throw HabitNotificationServiceError.invalidReminderTime
        }

        // Check permission
        let authorized = try await checkNotificationAuthorization()
        guard authorized else {
            throw HabitNotificationServiceError.notificationPermissionDenied
        }

        // Calculate notification time (subtract reminder minutes from anchor time)
        let notificationTime = calendar.date(
            byAdding: .minute,
            value: -reminderMinutes,
            to: anchorTime
        ) ?? anchorTime

        // Check if notification time is outside quiet hours
        guard !isInQuietHours(notificationTime: notificationTime) else {
            // Don't schedule - notification would fall during quiet hours
            return
        }

        // Extract time components for daily trigger
        let components = calendar.dateComponents([.hour, .minute], from: notificationTime)
        guard let hour = components.hour, let minute = components.minute else {
            throw HabitNotificationServiceError.timeZoneError
        }

        // Create notification content
        let payload = HabitNotificationPayload(
            habitId: habit.id,
            habitName: habit.name,
            anchorBehavior: habit.behavior,
            streakCount: 0,
            notificationType: .habitReminder
        )

        let content = createNotificationContent(
            title: "Time for \(habit.name)",
            body: "After \(habit.anchor), \(habit.behavior)",
            payload: payload
        )

        // Create daily trigger
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        dateComponents.timeZone = userTimezone

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )

        // Create and schedule request
        let requestId = "habit_reminder_\(habit.id.uuidString)"
        let request = UNNotificationRequest(identifier: requestId, content: content, trigger: trigger)

        do {
            try await userNotificationCenter.add(request)
            notificationRequests[requestId] = request
        } catch {
            throw HabitNotificationServiceError.notificationSchedulingFailed(error.localizedDescription)
        }
    }

    /// Schedule a streak milestone notification
    /// - Parameters:
    ///   - habit: The habit with streak
    ///   - streak: Current streak count
    ///   - milestone: Milestone number (7, 14, 21, 30, etc.)
    func scheduleStreakMilestoneNotification(
        habit: Habit,
        streak: Int,
        milestone: Int
    ) async throws {
        // Check permission
        let authorized = try await checkNotificationAuthorization()
        guard authorized else {
            throw HabitNotificationServiceError.notificationPermissionDenied
        }

        let payload = HabitNotificationPayload(
            habitId: habit.id,
            habitName: habit.name,
            anchorBehavior: habit.behavior,
            streakCount: streak,
            notificationType: .streakMilestone
        )

        let content = createNotificationContent(
            title: "🔥 \(streak)-Day Streak!",
            body: "Amazing progress with \(habit.name)! You've maintained this habit for \(streak) days!",
            payload: payload
        )
        content.sound = .default
        content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)

        // Schedule immediately with a small delay
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)

        let requestId = "streak_milestone_\(habit.id.uuidString)_\(milestone)"
        let request = UNNotificationRequest(identifier: requestId, content: content, trigger: trigger)

        do {
            try await userNotificationCenter.add(request)
            notificationRequests[requestId] = request
        } catch {
            throw HabitNotificationServiceError.notificationSchedulingFailed(error.localizedDescription)
        }
    }

    /// Schedule a habit graduation notification
    /// - Parameters:
    ///   - habit: The habit that's graduating
    ///   - fromDifficulty: Current difficulty level
    ///   - toDifficulty: New difficulty level
    func scheduleHabitGraduationNotification(
        habit: Habit,
        fromDifficulty: HabitDifficulty,
        toDifficulty: HabitDifficulty
    ) async throws {
        // Check permission
        let authorized = try await checkNotificationAuthorization()
        guard authorized else {
            throw HabitNotificationServiceError.notificationPermissionDenied
        }

        let payload = HabitNotificationPayload(
            habitId: habit.id,
            habitName: habit.name,
            anchorBehavior: habit.behavior,
            streakCount: 0,
            notificationType: .habitGraduation
        )

        let content = createNotificationContent(
            title: "🎉 Habit Graduated!",
            body: "\(habit.name) has leveled up from \(fromDifficulty.displayName) to \(toDifficulty.displayName)!",
            payload: payload
        )
        content.sound = .default
        content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)

        // Schedule immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)

        let requestId = "graduation_\(habit.id.uuidString)"
        let request = UNNotificationRequest(identifier: requestId, content: content, trigger: trigger)

        do {
            try await userNotificationCenter.add(request)
            notificationRequests[requestId] = request
        } catch {
            throw HabitNotificationServiceError.notificationSchedulingFailed(error.localizedDescription)
        }
    }

    // MARK: - Notification Management

    /// Cancel a scheduled notification for a habit
    func cancelHabitReminder(habitId: UUID) {
        let requestId = "habit_reminder_\(habitId.uuidString)"
        userNotificationCenter.removePendingNotificationRequests(withIdentifiers: [requestId])
        notificationRequests.removeValue(forKey: requestId)
    }

    /// Cancel all notifications for a habit
    func cancelAllNotifications(for habitId: UUID) {
        let habitIdString = habitId.uuidString
        let requestsToRemove = notificationRequests.keys.filter { $0.contains(habitIdString) }

        userNotificationCenter.removePendingNotificationRequests(withIdentifiers: requestsToRemove)
        requestsToRemove.forEach { notificationRequests.removeValue(forKey: $0) }
    }

    /// Get all pending notifications for a habit
    func getPendingNotifications(for habitId: UUID) async -> [UNNotificationRequest] {
        let allRequests = await userNotificationCenter.pendingNotificationRequests()
        let habitIdString = habitId.uuidString
        return allRequests.filter { $0.identifier.contains(habitIdString) }
    }

    // MARK: - Quiet Hours Management

    /// Validate quiet hours configuration
    private func isInQuietHours(notificationTime: Date) -> Bool {
        // This is a simplified check. In production, would integrate with user settings
        // from the database (user_settings.quiet_hours_start_local, quiet_hours_end_local)

        let components = calendar.dateComponents([.hour, .minute], from: notificationTime)
        guard let hour = components.hour else { return false }

        // Default quiet hours: 9 PM (21:00) to 7 AM (07:00)
        // In production, fetch from user preferences
        let quietHourStart = NotificationConfig.defaultQuietHoursStart
        let quietHourEnd = NotificationConfig.defaultQuietHoursEnd

        if quietHourStart > quietHourEnd {
            // Quiet hours span midnight (e.g., 21:00 to 07:00)
            return hour >= quietHourStart || hour < quietHourEnd
        } else {
            // Quiet hours don't span midnight
            return hour >= quietHourStart && hour < quietHourEnd
        }
    }

    // MARK: - Helper Methods

    private func createNotificationContent(
        title: String,
        body: String,
        payload: HabitNotificationPayload
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = payload.userInfo
        content.sound = .default
        return content
    }

    private func setupNotificationDelegate() {
        userNotificationCenter.delegate = NotificationDelegate.shared
    }
}

// MARK: - Notification Delegate

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Display notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // Extract habit ID and notification type
        if let habitIdString = userInfo["habitId"] as? String,
           let habitId = UUID(uuidString: habitIdString),
           let notificationTypeRaw = userInfo["notificationType"] as? String,
           let notificationType = HabitNotificationType(rawValue: notificationTypeRaw) {

            // Handle notification interaction based on type
            handleNotificationTap(habitId: habitId, type: notificationType)
        }

        completionHandler()
    }

    private func handleNotificationTap(habitId: UUID, type: HabitNotificationType) {
        // In production, would send analytics event or navigate to specific view
        // For now, log the interaction
        switch type {
        case .habitReminder:
            break // Navigate to habit completion view
        case .streakMilestone:
            break // Show celebration/badge view
        case .habitGraduation:
            break // Show habit upgrade confirmation
        }
    }
}
