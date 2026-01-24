//
//  NotificationPermissionManager.swift
//  MindFriendApp
//
//  Centralized manager for requesting and checking notification permissions
//

import Foundation
import UserNotifications
import UIKit

/// Protocol for managing notification permissions
protocol NotificationPermissionManaging {
    /// Request notification permissions from user
    /// - Returns: True if authorized, false otherwise
    func requestPermission() async -> Bool

    /// Check current permission status without prompting
    /// - Returns: Current authorization status
    func checkPermissionStatus() async -> UNAuthorizationStatus

    /// Open system settings to notification page
    @MainActor func openSettings()
}

/// Manages notification permissions and authorization flow
final class NotificationPermissionManager: NotificationPermissionManaging {
    // MARK: - Properties

    private let notificationCenter: UNUserNotificationCenter

    // MARK: - Initialization

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    // MARK: - Public Methods

    func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            return granted
        } catch {
            print("Failed to request notification permission: \(error)")
            return false
        }
    }

    func checkPermissionStatus() async -> UNAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        return settings.authorizationStatus
    }

    @MainActor
    func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        if UIApplication.shared.canOpenURL(settingsURL) {
            Task {
                await UIApplication.shared.open(settingsURL)
            }
        }
    }
}
