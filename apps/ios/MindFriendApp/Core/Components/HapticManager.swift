// MindFriend Haptic Manager
// Centralized haptic feedback utilities for celebration animations

import UIKit

/// Centralized haptic feedback manager for consistent tactile feedback across celebrations
enum HapticManager {

    // MARK: - Badge Celebration Haptics

    /// Medium impact for badge stamp-down effect
    static func badgeStamp() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Light impact for badge ripple effect
    static func badgeRipple() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    // MARK: - Skill Level Up Haptics

    /// Soft impact for energy convergence
    static func skillConverge() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Medium impact for energy burst
    static func skillBurst() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    // MARK: - Certificate Haptics

    /// Light impact for certificate unfurl
    static func certificateUnfurl() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Heavy impact for gold seal stamp
    static func certificateSeal() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
    }

    // MARK: - General Celebration Haptics

    /// Success notification for celebration completion
    static func celebrationSuccess() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    /// Warning notification (e.g., streak at risk)
    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }

    /// Selection feedback for UI interactions
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    // MARK: - XP Gain Haptics

    /// Light haptic for XP gain notifications
    static func xpGain() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    // MARK: - Custom Patterns

    /// Double tap pattern for level up (two quick impacts)
    static func levelUpPattern() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            generator.impactOccurred()
        }
    }

    /// Triple pulse pattern for milestones
    static func milestonePattern() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()

        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) {
                generator.impactOccurred()
            }
        }
    }
}
