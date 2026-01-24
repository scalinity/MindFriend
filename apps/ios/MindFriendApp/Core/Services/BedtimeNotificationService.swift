//
//  BedtimeNotificationService.swift
//  MindFriendApp
//
//  Schedule and manage daily bedtime reminder notifications
//

import Foundation
import UserNotifications

/// Errors that can occur when managing bedtime notifications
enum NotificationError: LocalizedError {
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

/// Protocol for managing bedtime reminder notifications
protocol BedtimeNotificationServicing {
    /// Schedule a daily bedtime reminder notification
    /// - Parameters:
    ///   - targetBedtime: User's desired bedtime (time component used)
    ///   - windDownMinutes: Minutes before bedtime to send reminder
    ///   - routineSuggestion: Personalized routine suggestion text
    /// - Throws: NotificationError if permission denied or scheduling fails
    func scheduleBedtimeReminder(
        targetBedtime: Date,
        windDownMinutes: Int,
        routineSuggestion: String
    ) async throws

    /// Cancel the currently scheduled bedtime reminder
    func cancelBedtimeReminder() async

    /// Update existing reminder schedule (cancels old, schedules new)
    /// - Parameters:
    ///   - newBedtime: Updated bedtime
    ///   - windDownMinutes: Updated wind-down period
    ///   - routineSuggestion: Updated routine suggestion
    /// - Throws: NotificationError if permission denied or scheduling fails
    func updateReminderSchedule(
        newBedtime: Date,
        windDownMinutes: Int,
        routineSuggestion: String
    ) async throws
}

/// Manages bedtime reminder notifications
final class BedtimeNotificationService: BedtimeNotificationServicing {
    // MARK: - Properties

    private let notificationCenter: UNUserNotificationCenter
    private let permissionManager: NotificationPermissionManaging
    private let bedtimeReminderID = "bedtime-reminder"

    // MARK: - Initialization

    init(
        notificationCenter: UNUserNotificationCenter = .current(),
        permissionManager: NotificationPermissionManaging
    ) {
        self.notificationCenter = notificationCenter
        self.permissionManager = permissionManager
    }

    // MARK: - Public Methods

    func scheduleBedtimeReminder(
        targetBedtime: Date,
        windDownMinutes: Int,
        routineSuggestion: String
    ) async throws {
        // Validate input
        guard windDownMinutes > 0 && windDownMinutes <= 1440 else {
            throw NotificationError.schedulingFailed(
                NSError(domain: "BedtimeNotificationService", 
                       code: -1, 
                       userInfo: [NSLocalizedDescriptionKey: "Wind-down minutes must be between 1 and 1440"])
            )
        }
        
        // Check permission first
        let status = await permissionManager.checkPermissionStatus()
        
        if status != .authorized {
            // Request permission if not determined
            if status == .notDetermined {
                let granted = await permissionManager.requestPermission()
                guard granted else {
                    throw NotificationError.permissionDenied
                }
            } else {
                // Permission was denied
                throw NotificationError.permissionDenied
            }
        }

        // Calculate notification time using Calendar arithmetic (handles midnight wrap correctly)
        let calendar = Calendar.current
        guard let notificationTime = calendar.date(
            byAdding: .minute,
            value: -windDownMinutes,
            to: targetBedtime
        ) else {
            throw NotificationError.schedulingFailed(
                NSError(domain: "BedtimeNotificationService",
                       code: -2,
                       userInfo: [NSLocalizedDescriptionKey: "Failed to calculate notification time"])
            )
        }
        
        let components = calendar.dateComponents([.hour, .minute], from: notificationTime)

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Time to start winding down 🌙"
        content.body = "Your bedtime goal is in \(windDownMinutes) minutes. \(routineSuggestion)"
        content.sound = .default
        content.categoryIdentifier = "SLEEP_REMINDER"

        // Create trigger (repeats daily)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: true
        )

        // Create request
        let request = UNNotificationRequest(
            identifier: bedtimeReminderID,
            content: content,
            trigger: trigger
        )

        // Schedule notification
        do {
            try await notificationCenter.add(request)
        } catch {
            throw NotificationError.schedulingFailed(error)
        }
    }

    func cancelBedtimeReminder() async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [bedtimeReminderID])
    }

    func updateReminderSchedule(
        newBedtime: Date,
        windDownMinutes: Int,
        routineSuggestion: String
    ) async throws {
        // Cancel existing reminder first
        await cancelBedtimeReminder()

        // Schedule new reminder
        try await scheduleBedtimeReminder(
            targetBedtime: newBedtime,
            windDownMinutes: windDownMinutes,
            routineSuggestion: routineSuggestion
        )
    }
}
