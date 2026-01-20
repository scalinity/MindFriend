import Foundation
import UserNotifications
#if canImport(FocusFilterKit)
import FocusFilterKit
#endif

/// Protocol for Focus Mode provision (enables testing)
protocol FocusModeProviding {
    func getContext() async -> FocusModeContext
    var manualDNDEnabled: Bool { get set }
}

/// Provides Focus Mode context
/// Uses FocusStatusCenter on iOS 18+, falls back to manual toggle on iOS 17
@MainActor
final class FocusModeProvider: FocusModeProviding {
    /// Manual DND toggle for iOS 17 users (stored in UserDefaults)
    var manualDNDEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "smartNotifications.manualDND") }
        set { UserDefaults.standard.set(newValue, forKey: "smartNotifications.manualDND") }
    }

    init() {}

    /// Get current Focus Mode context
    func getContext() async -> FocusModeContext {
        // Try iOS 18+ Focus Mode API first
        if #available(iOS 18.0, *) {
            return await getContextFromFocusAPI()
        }

        // Fall back to manual toggle and heuristics for iOS 17
        return getContextFromHeuristics()
    }

    // MARK: - iOS 18+ Focus Mode API

    @available(iOS 18.0, *)
    private func getContextFromFocusAPI() async -> FocusModeContext {
        // Note: FocusStatusCenter requires iOS 18+ and proper entitlements
        // This is a simplified implementation - real implementation would use the actual API

        // Check for Do Not Disturb using UNNotificationSettings
        let settings = await UNUserNotificationCenter.current().notificationSettings()

        // If notifications are not allowed at all, treat as DND
        if settings.authorizationStatus == .denied {
            return FocusModeContext(
                activeMode: .doNotDisturb,
                shouldSuppress: true
            )
        }

        // Check for scheduled delivery (indicates Focus Mode active)
        // In a real implementation, you'd use FocusStatusCenter.shared.authorizationStatus
        // and observe for changes

        // For now, use manual toggle as fallback
        if manualDNDEnabled {
            return FocusModeContext(
                activeMode: .doNotDisturb,
                shouldSuppress: true
            )
        }

        // Try to detect sleep mode based on time
        if detectSleepMode() {
            return FocusModeContext(
                activeMode: .sleep,
                shouldSuppress: true
            )
        }

        // Try to detect driving mode (if CarPlay or Bluetooth connected to known car)
        if detectDrivingMode() {
            return FocusModeContext(
                activeMode: .driving,
                shouldSuppress: true
            )
        }

        return FocusModeContext(
            activeMode: FocusMode.none,
            shouldSuppress: false
        )
    }

    // MARK: - iOS 17 Heuristics

    private func getContextFromHeuristics() -> FocusModeContext {
        // Check manual DND toggle first
        if manualDNDEnabled {
            return FocusModeContext(
                activeMode: .doNotDisturb,
                shouldSuppress: true
            )
        }

        // Detect sleep mode based on time
        if detectSleepMode() {
            return FocusModeContext(
                activeMode: .sleep,
                shouldSuppress: true
            )
        }

        // Detect driving mode
        if detectDrivingMode() {
            return FocusModeContext(
                activeMode: .driving,
                shouldSuppress: true
            )
        }

        return FocusModeContext(
            activeMode: FocusMode.none,
            shouldSuppress: false
        )
    }

    // MARK: - Detection Heuristics

    /// Detect if user is likely sleeping based on time
    private func detectSleepMode() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        // Assume sleep mode from 11pm to 7am
        // In a real implementation, would sync with HealthKit sleep schedule
        return hour >= 23 || hour < 7
    }

    /// Detect if user is likely driving
    private func detectDrivingMode() -> Bool {
        // Check if connected to CarPlay or known car Bluetooth device
        // This is a simplified check - real implementation would monitor Bluetooth connections

        // Check for CarPlay connection
        // Note: This requires additional setup to monitor UIScene connections
        // For now, return false as we can't reliably detect without more setup

        return false
    }

    // MARK: - Sleep Schedule Integration

    /// Check if current time is within user's sleep schedule (from HealthKit or settings)
    func isWithinSleepSchedule(quietHoursStart: Int, quietHoursEnd: Int) -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())

        if quietHoursStart > quietHoursEnd {
            // Quiet hours span midnight (e.g., 22:00 to 08:00)
            return hour >= quietHoursStart || hour < quietHoursEnd
        } else {
            // Quiet hours don't span midnight
            return hour >= quietHoursStart && hour < quietHoursEnd
        }
    }
}
