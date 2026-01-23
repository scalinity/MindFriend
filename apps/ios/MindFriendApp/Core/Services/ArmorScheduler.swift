//
//  ArmorScheduler.swift
//  MindFriendApp
//
//  Created: 2026-01-22
//  Spec: N002 - Circadian Vulnerability Shield
//  Purpose: Schedules armor intervention notifications before vulnerable windows
//

import Foundation
import UserNotifications

// Note: Circadian types defined in CircadianModels.swift

/// Schedules armor interventions via notifications
final class ArmorScheduler {

    // MARK: - Dependencies

    private let notificationCenter: UNUserNotificationCenter

    // MARK: - Initialization

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    // MARK: - Public API

    /// Schedule armor intervention notification for a vulnerable window
    /// Delivers 15-30 min before window based on severity
    func scheduleArmor(for window: VulnerableWindow, exerciseId: String) async throws {
        // Calculate delivery time
        let deliveryTime = window.startTime.addingTimeInterval(-window.severity.armorLeadTime)

        // Don't schedule if already passed
        guard deliveryTime > Date() else { return }

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Incoming Challenge"
        content.body = "A vulnerable window is approaching in \(Int(window.severity.armorLeadTime / 60)) minutes. Take a moment to strengthen your resilience."
        content.sound = .default
        content.categoryIdentifier = "ARMOR_INTERVENTION"
        content.userInfo = [
            "windowId": window.id.uuidString,
            "exerciseId": exerciseId,
            "severity": window.severity.rawValue
        ]

        // Create trigger
        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: deliveryTime
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        // Create request
        let request = UNNotificationRequest(
            identifier: "armor_\(window.id.uuidString)",
            content: content,
            trigger: trigger
        )

        // Schedule
        try await notificationCenter.add(request)
    }

    /// Cancel armor notification for a window
    func cancelArmor(for windowId: UUID) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["armor_\(windowId.uuidString)"])
    }

    /// Select appropriate exercise for armor intervention
    /// MVP: Simple selection based on severity
    func selectExercise(for severity: VulnerableWindow.VulnerabilitySeverity) -> String {
        // TODO: Query from armor_interventions function or exercises table
        // For MVP, return hardcoded exercise IDs
        switch severity {
        case .low:
            return "breathing_box"  // 2-3 min breathing
        case .moderate:
            return "grounding_54321"  // 3-4 min grounding
        case .high:
            return "activation_movement"  // 4-5 min movement
        }
    }
}
