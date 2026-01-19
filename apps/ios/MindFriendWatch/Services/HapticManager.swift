import WatchKit

/// Centralized haptic feedback manager for Apple Watch
/// Provides optimized haptic patterns for breathing exercises and user feedback
@MainActor
final class HapticManager {
    static let shared = HapticManager()

    private let device = WKInterfaceDevice.current()

    private init() {}

    // MARK: - Breathing Exercise Haptics (4-7-8 Pattern)

    /// Strong haptic at start of inhale phase
    func playInhaleStart() {
        device.play(.start)
    }

    /// Subtle pulse during inhale (called each second)
    func playInhaleProgress() {
        device.play(.click)
    }

    /// Medium haptic at start of hold phase
    func playHoldStart() {
        device.play(.directionUp)
    }

    /// Very subtle tick at hold midpoint
    func playHoldProgress() {
        device.play(.click)
    }

    /// Descending haptic at start of exhale phase
    func playExhaleStart() {
        device.play(.directionDown)
    }

    /// Success haptic at end of exhale phase
    func playExhaleComplete() {
        device.play(.success)
    }

    /// Celebration haptic at end of full breathing session
    func playSessionComplete() {
        device.play(.notification)
    }

    // MARK: - General Haptics

    /// Success feedback for completed actions (mood logged, etc.)
    func playSuccess() {
        device.play(.success)
    }

    /// Failure feedback for errors
    func playFailure() {
        device.play(.failure)
    }

    /// Notification haptic for alerts
    func playNotification() {
        device.play(.notification)
    }

    /// Click haptic for button taps
    func playClick() {
        device.play(.click)
    }

    /// Start haptic for beginning an activity
    func playStart() {
        device.play(.start)
    }

    /// Stop haptic for ending an activity
    func playStop() {
        device.play(.stop)
    }

    /// Retry haptic for retry actions
    func playRetry() {
        device.play(.retry)
    }
}
