// MindFriend XP Gain Toast
// Lightweight toast notification for XP gains

import SwiftUI

// MARK: - XP Gain Event

/// Event triggered when XP is earned
struct XPGainEvent: Identifiable, Equatable {
    let id = UUID()
    let amount: Int
    let source: XPSource
    let timestamp: Date = Date()

    var activityLabel: String {
        switch source {
        case .quest: return "Quest complete"
        case .exercise: return "Exercise"
        case .mood: return "Mood check-in"
        case .badge: return "Badge earned"
        case .streak: return "Bonus"
        case .bonus: return "Bonus"
        case .meditation: return "Meditation"
        case .checkin: return "Check-in"
        }
    }

    static func == (lhs: XPGainEvent, rhs: XPGainEvent) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - XP Gain Toast View

/// Toast notification that appears when XP is earned
struct XPGainToast: View {
    let xpAmount: Int
    let activityLabel: String
    /// Mood check-ins earn XP quietly: the spec allows no haptic reward for a disclosure.
    var haptic = true
    let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var showLabel = false
    @State private var animationWorkItems: [DispatchWorkItem] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: haptic ? "sparkles" : "checkmark.circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SupportTheme.Celebration.gold)
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(haptic ? "+\(xpAmount) XP" : "Check-in saved")
                    .font(.headline)
                    .foregroundStyle(SupportTheme.textPrimary)
                Text(activityLabel)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .opacity(showLabel ? 1 : 0)
            }
        }
        .padding(.horizontal, SupportTheme.Spacing.m)
        .padding(.vertical, SupportTheme.Spacing.s)
        .background(SupportTheme.elevated, in: RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: SupportTheme.controlRadius).strokeBorder(SupportTheme.border, lineWidth: 1))

        .scaleEffect(isVisible || reduceMotion || !haptic ? 1 : 0.9)
        .offset(y: isVisible || reduceMotion || !haptic ? 0 : -16)
        .opacity(isVisible ? 1 : 0)
        .padding(.top, SupportTheme.Spacing.s)
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            cancelAllAnimations()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(haptic ? "Earned \(xpAmount) XP for \(activityLabel)" : "Check-in saved")
        .accessibilityAddTraits(.isStaticText)
    }

    private func cancelAllAnimations() {
        animationWorkItems.forEach { $0.cancel() }
        animationWorkItems.removeAll()
    }

    private func startAnimation() {
        if haptic { HapticManager.xpGain() }

        if reduceMotion || !haptic {
            // Simple fade for reduced motion
            withAnimation(.easeOut(duration: 0.2)) {
                isVisible = true
                showLabel = true
            }
            // Auto-dismiss after 2.5s
            let dismissWorkItem = DispatchWorkItem {
                withAnimation(.easeIn(duration: 0.2)) {
                    isVisible = false
                }
            }
            let callbackWorkItem = DispatchWorkItem {
                onDismiss()
            }
            animationWorkItems.append(contentsOf: [dismissWorkItem, callbackWorkItem])
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: dismissWorkItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.7, execute: callbackWorkItem)
            return
        }

        // Animate in with spring
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            isVisible = true
        }

        // Show activity label
        let labelWorkItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.2)) {
                showLabel = true
            }
        }
        animationWorkItems.append(labelWorkItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: labelWorkItem)

        // Auto-dismiss after 2.2s
        let dismissWorkItem = DispatchWorkItem {
            withAnimation(.easeIn(duration: 0.3)) {
                isVisible = false
            }
        }
        let callbackWorkItem = DispatchWorkItem {
            onDismiss()
        }
        animationWorkItems.append(contentsOf: [dismissWorkItem, callbackWorkItem])
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: dismissWorkItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: callbackWorkItem)
    }
}

// MARK: - XP Gain View Modifier

/// View modifier to show XP gain toast overlay
struct XPGainModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var achievementService: AchievementService

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let event = achievementService.pendingXPGain {
                    XPGainToast(
                        xpAmount: event.amount,
                        activityLabel: event.activityLabel,
                        haptic: event.source != .mood,
                        onDismiss: { achievementService.clearXPGain() }
                    )
                    .transition(reduceMotion || event.source == .mood ? .opacity : .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                    .zIndex(1000)
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.7), value: achievementService.pendingXPGain != nil)
                }
            }
    }
}

extension View {
    /// Add XP gain toast overlay to view
    func xpGainToast() -> some View {
        modifier(XPGainModifier())
    }
}

// MARK: - Preview

#Preview("XP Toast - Quest") {
    ZStack {
        SupportTheme.accent.opacity(0.3).ignoresSafeArea()
        VStack {
            Text("Main Content")
            Spacer()
        }
    }
    .overlay(alignment: .top) {
        XPGainToast(
            xpAmount: 50,
            activityLabel: "Quest Complete",
            onDismiss: {}
        )
    }
}

#Preview("XP Toast - Exercise") {
    ZStack {
        SupportTheme.accent.opacity(0.3).ignoresSafeArea()
    }
    .overlay(alignment: .top) {
        XPGainToast(
            xpAmount: 30,
            activityLabel: "Exercise",
            onDismiss: {}
        )
    }
}

#Preview("XP Toast - Mood") {
    ZStack {
        SupportTheme.accent.opacity(0.3).ignoresSafeArea()
    }
    .overlay(alignment: .top) {
        XPGainToast(
            xpAmount: 10,
            activityLabel: "Mood Check-in",
            onDismiss: {}
        )
    }
}
