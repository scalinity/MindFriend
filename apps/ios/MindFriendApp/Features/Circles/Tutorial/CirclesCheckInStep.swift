//
//  CirclesCheckInStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: Daily check-ins
//

import SwiftUI

/// Step 2: Explain daily check-in flow
struct CirclesCheckInStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showCheckIn = false
    @State private var showReactions = false

    var body: some View {
        TutorialStepView(
            icon: "hand.wave.fill",
            iconColor: SupportTheme.accent,
            headline: "Daily Check-ins",
            subheadline: "Share how you're doing with your circle. Quick, simple, and supportive.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                // Example check-in
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    // Header
                    HStack(spacing: SupportTheme.Spacing.s) {
                        Circle()
                            .fill(SupportTheme.accent)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.caption)
                                    .foregroundStyle(SupportTheme.onAccent)
                            )

                        VStack(alignment: .leading) {
                            Text("Sarah")
                                .font(.subheadline.weight(.medium))
                            Text("Today at 9:30 AM")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                    }

                    // Check-in content
                    Text("Feeling good today! Started with a morning walk and ready to tackle the day.")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Reactions
                    if showReactions {
                        HStack(spacing: SupportTheme.Spacing.xs) {
                            ReactionPill(emoji: "heart.fill", count: 3, color: SupportTheme.accent)
                            ReactionPill(emoji: "hand.thumbsup.fill", count: 2, color: SupportTheme.accent)
                            ReactionPill(emoji: "sparkles", count: 1, color: SupportTheme.accent)
                        }
                        .transition(reduceMotion ? .opacity.animation(.easeInOut(duration: 0.2)) : .scale.combined(with: .opacity))
                    }
                }
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                .scaleEffect(reduceMotion ? 1 : (showCheckIn ? 1 : 0.95))
                .opacity(showCheckIn ? 1 : 0)
                .padding(.horizontal, SupportTheme.Spacing.l)

                // Info
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Text("React to show support")
                        .font(.caption.weight(.medium))
                    Text("Hugs, high-fives, and encouragement make a difference")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, SupportTheme.Spacing.l)
                .opacity(showReactions ? 1 : 0)
            }
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(0.3)) {
                    showCheckIn = true
                }
                withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.7).delay(1.0)) {
                    showReactions = true
                }
            }
        }
    }
}

private struct ReactionPill: View {
    let emoji: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            Image(systemName: emoji)
                .font(.caption)
                .foregroundStyle(color)
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .padding(.horizontal, SupportTheme.Spacing.s)
        .padding(.vertical, SupportTheme.Spacing.xs)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}

#Preview {
    CirclesCheckInStep(onNext: {}, onSkip: {})
}
