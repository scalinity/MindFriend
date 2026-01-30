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
        case .streak: return "Streak Bonus"
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
    let onDismiss: () -> Void

    @State private var isVisible = false
    @State private var showSparkles = false
    @State private var showLabel = false
    @State private var animationWorkItems: [DispatchWorkItem] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let goldColor = Color(red: 1.0, green: 0.84, blue: 0.0) // #FFD700
    private let orangeGold = Color(red: 1.0, green: 0.65, blue: 0.0) // #FFA500

    var body: some View {
        VStack(spacing: 4) {
            // XP Amount with sparkles
            ZStack {
                // Sparkle particles behind
                if showSparkles {
                    XPSparkleParticles(particleCount: 12)
                        .frame(width: 160, height: 60)
                }

                // XP text
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.headline)
                    Text("+\(xpAmount) XP")
                        .font(.title2.bold())
                    Image(systemName: "sparkles")
                        .font(.headline)
                }
                .foregroundStyle(
                    LinearGradient(
                        colors: [goldColor, orangeGold],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }

            // Activity label
            Text(activityLabel)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .opacity(showLabel ? 1 : 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.black.opacity(0.6))
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: goldColor.opacity(0.3), radius: 10)
        .scaleEffect(isVisible ? 1 : 0.8)
        .offset(y: isVisible ? 0 : -20)
        .opacity(isVisible ? 1 : 0)
        .padding(.top, 60) // Below safe area
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
        // Haptic feedback
        HapticManager.xpGain()

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
