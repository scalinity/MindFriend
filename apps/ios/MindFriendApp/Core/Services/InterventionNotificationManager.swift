//  InterventionNotificationManager.swift
//  MindFriendApp
//
//  Created by Contextual Micro-Interventions Feature
//  Manages push notification delivery for interventions with deep linking and actionable notifications

import Foundation
import UserNotifications
import UIKit

// MARK: - Protocol

protocol InterventionNotificationManaging {
    func requestNotificationPermission() async -> Bool
    func hasNotificationPermission() async -> Bool
    func deliverIntervention(_ intervention: MicroMomentTemplate, context: String, deliveryId: UUID) async throws
    func scheduleIntervention(_ intervention: MicroMomentTemplate, at date: Date, context: String, deliveryId: UUID) async throws
    func handleNotificationResponse(_ response: UNNotificationResponse) async -> InterventionDeepLink?
    func updateBadgeCount() async
    func cancelPendingInterventions() async
    func getPendingCount() async -> Int
}

// MARK: - Configuration Constants

private enum NotificationConstants {
    static let categoryIdentifier = "INTERVENTION"
    static let completeActionIdentifier = "COMPLETE_INTERVENTION"
    static let remindLaterActionIdentifier = "REMIND_LATER"
    static let dismissActionIdentifier = "DISMISS_INTERVENTION"
    static let remindLaterDelayMinutes = 30
    static let notificationThreadIdentifier = "interventions"
}

// MARK: - Implementation

@MainActor
final class InterventionNotificationManager: NSObject, InterventionNotificationManaging {
    // MARK: - Properties

    private let notificationCenter: UNUserNotificationCenter
    private var pendingInterventionCount = 0

    // MARK: - Initialization

    override init() {
        self.notificationCenter = UNUserNotificationCenter.current()
        super.init()
        setupNotificationCategories()
    }

    // MARK: - Public Methods

    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Notification permission request failed: \(error.localizedDescription)")
            return false
        }
    }

    func hasNotificationPermission() async -> Bool {
        let settings = await notificationCenter.notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    func deliverIntervention(_ intervention: MicroMomentTemplate, context: String, deliveryId: UUID) async throws {
        let content = buildNotificationContent(
            intervention: intervention,
            context: context,
            deliveryId: deliveryId
        )

        let request = UNNotificationRequest(
            identifier: deliveryId.uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        try await notificationCenter.add(request)

        // Update badge count
        pendingInterventionCount += 1
        await updateBadgeCount()

        print("Intervention notification delivered: \(intervention.title)")
    }

    func scheduleIntervention(_ intervention: MicroMomentTemplate, at date: Date, context: String, deliveryId: UUID) async throws {
        let content = buildNotificationContent(
            intervention: intervention,
            context: context,
            deliveryId: deliveryId
        )

        // Create time-based trigger
        let timeInterval = max(1, date.timeIntervalSinceNow) // Minimum 1 second
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: timeInterval,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: deliveryId.uuidString,
            content: content,
            trigger: trigger
        )

        try await notificationCenter.add(request)

        print("Intervention notification scheduled for: \(date)")
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) async -> InterventionDeepLink? {
        let userInfo = response.notification.request.content.userInfo

        // Parse deep link
        guard let deepLink = InterventionDeepLink.parse(from: userInfo) else {
            print("Failed to parse intervention deep link")
            return nil
        }

        // Handle action
        switch response.actionIdentifier {
        case NotificationConstants.completeActionIdentifier:
            // User tapped "Complete" action
            return InterventionDeepLink(
                deliveryId: deepLink.deliveryId,
                interventionId: deepLink.interventionId,
                action: .complete
            )

        case NotificationConstants.remindLaterActionIdentifier:
            // Reschedule for 30 minutes later
            return InterventionDeepLink(
                deliveryId: deepLink.deliveryId,
                interventionId: deepLink.interventionId,
                action: .remindLater
            )

        case NotificationConstants.dismissActionIdentifier:
            // User dismissed
            return InterventionDeepLink(
                deliveryId: deepLink.deliveryId,
                interventionId: deepLink.interventionId,
                action: .dismiss
            )

        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification itself (not an action button)
            return InterventionDeepLink(
                deliveryId: deepLink.deliveryId,
                interventionId: deepLink.interventionId,
                action: .open
            )

        default:
            return nil
        }
    }

    func updateBadgeCount() async {
        let pending = await getPendingCount()
        await UIApplication.shared.applicationIconBadgeNumber = pending
    }

    func cancelPendingInterventions() async {
        // Get all pending notification requests
        let requests = await notificationCenter.pendingNotificationRequests()

        // Filter for intervention notifications
        let interventionIds = requests
            .filter { $0.content.categoryIdentifier == NotificationConstants.categoryIdentifier }
            .map { $0.identifier }

        // Cancel them
        notificationCenter.removePendingNotificationRequests(withIdentifiers: interventionIds)

        print("Cancelled \(interventionIds.count) pending intervention notifications")

        // Update badge
        pendingInterventionCount = 0
        await updateBadgeCount()
    }

    func getPendingCount() async -> Int {
        let requests = await notificationCenter.pendingNotificationRequests()
        return requests.filter { $0.content.categoryIdentifier == NotificationConstants.categoryIdentifier }.count
    }

    // MARK: - Private Methods

    private func setupNotificationCategories() {
        // Create actions
        let completeAction = UNNotificationAction(
            identifier: NotificationConstants.completeActionIdentifier,
            title: "Complete",
            options: [.foreground]
        )

        let remindLaterAction = UNNotificationAction(
            identifier: NotificationConstants.remindLaterActionIdentifier,
            title: "Remind Me Later",
            options: []
        )

        let dismissAction = UNNotificationAction(
            identifier: NotificationConstants.dismissActionIdentifier,
            title: "Dismiss",
            options: [.destructive]
        )

        // Create category
        let interventionCategory = UNNotificationCategory(
            identifier: NotificationConstants.categoryIdentifier,
            actions: [completeAction, remindLaterAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Register category
        notificationCenter.setNotificationCategories([interventionCategory])
    }

    private func buildNotificationContent(
        intervention: MicroMomentTemplate,
        context: String,
        deliveryId: UUID
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()

        // Title with intervention type icon
        let icon = getIconForType(intervention.type)
        content.title = "\(icon) \(intervention.title)"

        // Body with context message and duration
        let durationText = formatDuration(intervention.durationSeconds)
        if !context.isEmpty {
            content.body = "\(context) (\(durationText))"
        } else {
            content.body = "\(intervention.description ?? "Quick wellness moment") (\(durationText))"
        }

        // Sound
        content.sound = .default

        // Badge (increment)
        content.badge = NSNumber(value: pendingInterventionCount + 1)

        // Category for actionable notifications
        content.categoryIdentifier = NotificationConstants.categoryIdentifier

        // Thread identifier for grouping
        content.threadIdentifier = NotificationConstants.notificationThreadIdentifier

        // Relevance score (for notification priority)
        content.relevanceScore = 0.8

        // User info for deep linking
        let deepLink = InterventionDeepLink(
            deliveryId: deliveryId,
            interventionId: UUID(uuidString: intervention.id) ?? UUID(),
            action: .open
        )
        content.userInfo = deepLink.userInfo

        return content
    }

    private func getIconForType(_ type: MicroMomentType) -> String {
        switch type {
        case .breathing:
            return "🌬️"
        case .checkIn:
            return "💭"
        case .grounding:
            return "🌿"
        case .movement:
            return "🚶"
        case .transition:
            return "🌅"
        case .gratitude:
            return "🙏"
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) seconds"
        } else {
            let minutes = seconds / 60
            return "\(minutes) min"
        }
    }

    /// Reschedule intervention for later (30 minutes)
    func rescheduleIntervention(deliveryId: UUID, intervention: MicroMomentTemplate, context: String) async throws {
        // Cancel current notification
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [deliveryId.uuidString])

        // Schedule for 30 minutes later
        let newDate = Date().addingTimeInterval(TimeInterval(NotificationConstants.remindLaterDelayMinutes * 60))
        try await scheduleIntervention(intervention, at: newDate, context: context, deliveryId: deliveryId)

        print("Intervention rescheduled for \(NotificationConstants.remindLaterDelayMinutes) minutes later")
    }

    /// Remove delivered notification from notification center
    func removeDeliveredNotification(deliveryId: UUID) {
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [deliveryId.uuidString])

        // Decrement badge if needed
        if pendingInterventionCount > 0 {
            pendingInterventionCount -= 1
        }

        Task {
            await updateBadgeCount()
        }
    }
}

// MARK: - Error Types

enum NotificationError: LocalizedError {
    case permissionDenied
    case deliveryFailed
    case invalidDeepLink

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notification permission is required to receive intervention reminders. Please enable in Settings."
        case .deliveryFailed:
            return "Failed to deliver notification. Try again later."
        case .invalidDeepLink:
            return "Invalid notification data. Please report this issue."
        }
    }
}
