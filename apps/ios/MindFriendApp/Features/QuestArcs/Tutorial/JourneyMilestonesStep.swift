//
//  JourneyMilestonesStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: Explains milestones and achievements
//

import SwiftUI

/// Step 3: Explain milestone system and rewards
struct JourneyMilestonesStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showMilestones = false
    @State private var celebrateMilestone = false

    private let milestones = [
        (day: 7, title: "First Week", achieved: true),
        (day: 14, title: "Halfway", achieved: false),
        (day: 21, title: "Complete", achieved: false)
    ]

    var body: some View {
        JourneyTutorialStepLayout(
            icon: "flag.fill",
            iconColor: SupportTheme.accent,
            headline: "Celebrate Your Progress",
            subheadline: "Reach milestones along the way and see your transformation unfold.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                // Milestone timeline
                HStack(spacing: 0) {
                    ForEach(Array(milestones.enumerated()), id: \.offset) { index, milestone in
                        HStack(spacing: 0) {
                            milestoneMarker(milestone: milestone, index: index)

                            if index < milestones.count - 1 {
                                // Connection line
                                Rectangle()
                                    .fill(milestone.achieved ? SupportTheme.accent : SupportTheme.separator)
                                    .frame(height: 2)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.l)

                // Rewards preview
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Text("When you hit a milestone:")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SupportTheme.textPrimary)

                    HStack(spacing: SupportTheme.Spacing.m) {
                        rewardItem(icon: "trophy.fill", color: SupportTheme.accent, label: "Badges")
                        rewardItem(icon: "star.fill", color: SupportTheme.accent, label: "XP Bonus")
                        rewardItem(icon: "square.and.arrow.up", color: SupportTheme.accent, label: "Share")
                    }
                }
                .padding(.vertical, SupportTheme.Spacing.s)
                .padding(.horizontal, SupportTheme.Spacing.m)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                .padding(.horizontal, SupportTheme.Spacing.m)
                .opacity(showMilestones ? 1 : 0)
                .offset(y: reduceMotion ? 0 : (showMilestones ? 0 : 20))

                // Motivation text
                Text("Each milestone proves your commitment and reinforces your new habits.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SupportTheme.Spacing.m)
            }
            .onAppear {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.5).delay(0.3)) {
                    showMilestones = true
                }
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(0.5)) {
                    celebrateMilestone = true
                }
            }
        }
    }

    @ViewBuilder
    private func milestoneMarker(milestone: (day: Int, title: String, achieved: Bool), index: Int) -> some View {
        VStack(spacing: SupportTheme.Spacing.xxs) {
            ZStack {
                Circle()
                    .fill(milestone.achieved ? SupportTheme.accent : SupportTheme.separator)
                    .frame(width: 36, height: 36)
                    .scaleEffect(reduceMotion ? 1 : (milestone.achieved && celebrateMilestone ? 1.1 : 1.0))

                if milestone.achieved {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textPrimary)
                } else {
                    Image(systemName: "flag.fill")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
            .opacity(showMilestones ? 1 : 0)
            .scaleEffect(reduceMotion ? 1 : (showMilestones ? 1 : 0.5))
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.4).delay(Double(index) * 0.15), value: showMilestones)

            Text("Day \(milestone.day)")
                .font(.caption2)
                .foregroundStyle(SupportTheme.textSecondary)

            Text(milestone.title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(milestone.achieved ? SupportTheme.Celebration.gold : SupportTheme.textSecondary)
        }
    }

    @ViewBuilder
    private func rewardItem(icon: String, color: Color, label: String) -> some View {
        VStack(spacing: SupportTheme.Spacing.xxs) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(label)
                .font(.caption2)
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }
}

#Preview {
    JourneyMilestonesStep(onNext: {}, onSkip: {})
}
