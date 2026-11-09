//
//  AchievementsBadgesStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: Badge collection
//

import SwiftUI

/// Step 2: Show badge system
struct AchievementsBadgesStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var unlockedBadges: Set<Int> = []

    private let badges: [(icon: String, color: Color, name: String)] = [
        ("leaf.fill", SupportTheme.accent, "First steps"),
        ("star.fill", SupportTheme.Celebration.gold, "Quest Master"),
        ("moon.fill", SupportTheme.accent, "Night Owl"),
        ("sun.max.fill", SupportTheme.accent, "Early Bird"),
        ("heart.fill", SupportTheme.accent, "Self-Care Pro"),
        ("brain.head.profile", SupportTheme.accent, "Mindful One"),
    ]

    var body: some View {
        TutorialStepView(
            icon: "medal.fill",
            iconColor: SupportTheme.accent,
            headline: "Collect Badges",
            subheadline: "Recognize milestones, new practices and moments of care.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Badge grid
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: SupportTheme.Spacing.m
                ) {
                    ForEach(Array(badges.enumerated()), id: \.element.name) { index, badge in
                        VStack(spacing: SupportTheme.Spacing.xs) {
                            ZStack {
                                Circle()
                                    .fill(
                                        unlockedBadges.contains(index)
                                            ? badge.color.opacity(0.15)
                                            : SupportTheme.field
                                    )
                                    .frame(width: 48, height: 48)

                                Image(systemName: badge.icon)
                                    .font(.title2)
                                    .foregroundStyle(
                                        unlockedBadges.contains(index)
                                            ? badge.color
                                            : SupportTheme.textSecondary.opacity(0.5))
                            }
                            .scaleEffect(reduceMotion ? 1 : (unlockedBadges.contains(index) ? 1.1 : 1.0))

                            Text(badge.name)
                                .font(.caption2)
                                .foregroundStyle(
                                    unlockedBadges.contains(index)
                                        ? SupportTheme.textPrimary : SupportTheme.textSecondary
                                )
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.l)

                // Stats
                HStack(spacing: SupportTheme.Spacing.m) {
                    VStack {
                        Text("50+")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("Total Badges")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    VStack {
                        Text("\(unlockedBadges.count)")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                            .foregroundStyle(SupportTheme.accent)
                            .contentTransition(reduceMotion ? .opacity : .numericText())
                        Text("Unlocked")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                .padding(.horizontal, SupportTheme.Spacing.l)
            }
            .onAppear {
                animateBadges()
            }
        }
    }

    private func animateBadges() {
        for index in 0..<badges.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(index) * 0.2) {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : (.spring(response: 0.4, dampingFraction: 0.6)))
                {
                    _ = unlockedBadges.insert(index)
                }
            }
        }
    }
}

#Preview {
    AchievementsBadgesStep(onNext: {}, onSkip: {})
}
