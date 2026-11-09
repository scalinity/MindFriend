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
        case .quest: return "Quest Complete"
        case .exercise: return "Exercise"
        case .mood: return "Mood Check-in"
        case .badge: return "Badge Earned"
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
    @State private var showSparkles = false
    @State private var showLabel = false
    @State private var animationWorkItems: [DispatchWorkItem] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: "sparkles")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SupportTheme.Celebration.gold)
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? false : showSparkles)
            VStack(alignment: .leading, spacing: 2) {
                Text("+\(xpAmount) XP")
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
        .background(SupportTheme.elevated, in: Capsule())
        .overlay(Capsule().strokeBorder(SupportTheme.Celebration.gold.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
        .scaleEffect(isVisible || reduceMotion ? 1 : 0.9)
        .offset(y: isVisible || reduceMotion ? 0 : -16)
        .opacity(isVisible ? 1 : 0)
        .padding(.top, SupportTheme.Spacing.s)
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            cancelAllAnimations()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Earned \(xpAmount) XP for \(activityLabel)")
        .accessibilityAddTraits(.isStaticText)
    }

    private func cancelAllAnimations() {
        animationWorkItems.forEach { $0.cancel() }
        animationWorkItems.removeAll()
    }

    private func startAnimation() {
        if haptic { HapticManager.xpGain() }

        if reduceMotion {
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

        // Show sparkles
        let sparklesWorkItem = DispatchWorkItem {
            showSparkles = true
        }
        animationWorkItems.append(sparklesWorkItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: sparklesWorkItem)

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
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .zIndex(1000)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: achievementService.pendingXPGain != nil)
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
        Color.blue.opacity(0.3).ignoresSafeArea()
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
        Color.green.opacity(0.3).ignoresSafeArea()
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
        Color.purple.opacity(0.3).ignoresSafeArea()
    }
    .overlay(alignment: .top) {
        XPGainToast(
            xpAmount: 10,
            activityLabel: "Mood Check-in",
            onDismiss: {}
        )
    }
}
