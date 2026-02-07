//
//  QuestNotificationService.swift
//  MindFriendApp
//
//  Schedule and manage daily quest reminder notifications
//

import Foundation
import UserNotifications

/// Errors that can occur when managing quest notifications
enum QuestNotificationError: LocalizedError {
    case permissionDenied
    case schedulingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notification permission denied. Enable in Settings."
        case .schedulingFailed(let error):
            return "Failed to schedule notification: \(error.localizedDescription)"
        }
    }
}

/// Protocol for managing quest reminder notifications
protocol QuestNotificationServicing {
    /// Schedule a daily quest reminder notification at the specified time
    func scheduleQuestReminder(hour: Int, minute: Int) async throws

    /// Cancel the currently scheduled quest reminder
    func cancelQuestReminder() async

    /// Schedule reminder if enabled (called on app launch)
    func scheduleIfEnabled() async throws

    /// Update schedule from settings UI
    func updateSchedule(enabled: Bool, hour: Int, minute: Int) async throws

    /// Check if quest reminder is enabled
    var isEnabled: Bool { get }

    /// Get current reminder hour
    var reminderHour: Int { get }

    /// Get current reminder minute
    var reminderMinute: Int { get }
}

/// Manages daily quest reminder notifications
final class QuestNotificationService: QuestNotificationServicing {
    // MARK: - Properties

    private let notificationCenter: UNUserNotificationCenter
    private let permissionManager: NotificationPermissionManaging
    private let questReminderID = "daily-quest-reminder"

    // UserDefaults keys
    private let enabledKey = "quest_reminder_enabled"
    private let hourKey = "quest_reminder_hour"
    private let minuteKey = "quest_reminder_minute"
    private let hasSetDefaultKey = "quest_reminder_default_set"
    private let hourSetKey = "quest_reminder_hour_set"

    // MARK: - Computed Properties

    var isEnabled: Bool {
        // Default to true for new users
        if !UserDefaults.standard.bool(forKey: hasSetDefaultKey) {
            UserDefaults.standard.set(true, forKey: hasSetDefaultKey)
            UserDefaults.standard.set(true, forKey: enabledKey)
            return true
        }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    var reminderHour: Int {
        if UserDefaults.standard.bool(forKey: hourSetKey) {
            return UserDefaults.standard.integer(forKey: hourKey)
        }
        return 8  // Default: 8 AM
    }

    var reminderMinute: Int {
        UserDefaults.standard.integer(forKey: minuteKey)
    }

    // MARK: - Initialization

    init(
        notificationCenter: UNUserNotificationCenter = .current(),
        permissionManager: NotificationPermissionManaging = NotificationPermissionManager()
    ) {
        self.notificationCenter = notificationCenter
        self.permissionManager = permissionManager
    }

    // MARK: - Public Methods

    func scheduleIfEnabled() async throws {
        guard isEnabled else {
            #if DEBUG
            print("📅 Quest reminder disabled, skipping schedule")
            #endif
            return
        }

        try await scheduleQuestReminder(hour: reminderHour, minute: reminderMinute)
    }

    func updateSchedule(enabled: Bool, hour: Int, minute: Int) async throws {
        // Persist settings
        UserDefaults.standard.set(true, forKey: hasSetDefaultKey)
        UserDefaults.standard.set(true, forKey: hourSetKey)
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        UserDefaults.standard.set(hour, forKey: hourKey)
        UserDefaults.standard.set(minute, forKey: minuteKey)

        if enabled {
            try await scheduleQuestReminder(hour: hour, minute: minute)
        } else {
            await cancelQuestReminder()
        }
    }

    func scheduleQuestReminder(hour: Int, minute: Int) async throws {
        // Validate input
        guard hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 else {
            throw QuestNotificationError.schedulingFailed(
                NSError(domain: "QuestNotificationService",
                       code: -1,
                       userInfo: [NSLocalizedDescriptionKey: "Invalid time: hour must be 0-23, minute must be 0-59"])
            )
        }

        // Check permission first
        let status = await permissionManager.checkPermissionStatus()

        if status != .authorized {
            // Request permission if not determined
            if status == .notDetermined {
                let granted = await permissionManager.requestPermission()
                guard granted else {
                    throw QuestNotificationError.permissionDenied
                }
            } else {
                // Permission was denied
                throw QuestNotificationError.permissionDenied
            }
        }

        // Cancel existing first
        await cancelQuestReminder()

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Daily Quest Available"
        content.body = "Your wellness quest for today is ready. Take a moment for yourself."
        content.sound = .default
        content.categoryIdentifier = "QUEST_REMINDER"
        content.userInfo = [
            "type": "daily_quest",
            "deep_link": "mindfriend://quest"
        ]

        // Create trigger (repeats daily)
        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: true
        )

        // Create request
        let request = UNNotificationRequest(
            identifier: questReminderID,
            content: content,
            trigger: trigger
        )

        // Schedule notification
        do {
            try await notificationCenter.add(request)

            #if DEBUG
            print("📅 Daily quest reminder scheduled for \(hour):\(String(format: "%02d", minute))")
            #endif
        } catch {
            throw QuestNotificationError.schedulingFailed(error)
        }
    }

    func cancelQuestReminder() async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [questReminderID])

        #if DEBUG
        print("📅 Daily quest reminder cancelled")
        #endif
    }
}
