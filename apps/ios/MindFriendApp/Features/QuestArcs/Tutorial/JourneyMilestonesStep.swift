//
//  JourneyMilestonesStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: Explains milestones and achievements
//

import SwiftUI

/// Step 3: Explain milestone system and rewards
struct JourneyMilestonesStep: View {
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
            iconColor: .orange,
            headline: "Celebrate Your Progress",
            subheadline: "Reach milestones along the way and see your transformation unfold.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 8) {
                // Milestone timeline
                HStack(spacing: 0) {
                    ForEach(Array(milestones.enumerated()), id: \.offset) { index, milestone in
                        HStack(spacing: 0) {
                            milestoneMarker(milestone: milestone, index: index)

                            if index < milestones.count - 1 {
                                // Connection line
                                Rectangle()
                                    .fill(milestone.achieved ? Color.orange : Color(.systemGray4))
                                    .frame(height: 2)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)

                // Rewards preview
                VStack(spacing: 10) {
                    Text("When you hit a milestone:")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    HStack(spacing: 20) {
                        rewardItem(icon: "trophy.fill", color: .yellow, label: "Badges")
                        rewardItem(icon: "star.fill", color: .orange, label: "XP Bonus")
                        rewardItem(icon: "square.and.arrow.up", color: .blue, label: "Share")
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .opacity(showMilestones ? 1 : 0)
                .offset(y: showMilestones ? 0 : 20)

                // Motivation text
                Text("Each milestone proves your commitment and reinforces your new habits.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                    showMilestones = true
                }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(0.5)) {
                    celebrateMilestone = true
                }
            }
        }
    }

    @ViewBuilder
    private func milestoneMarker(milestone: (day: Int, title: String, achieved: Bool), index: Int) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(milestone.achieved ? Color.orange : Color(.systemGray5))
                    .frame(width: 36, height: 36)
                    .scaleEffect(milestone.achieved && celebrateMilestone ? 1.1 : 1.0)

                if milestone.achieved {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "flag.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(showMilestones ? 1 : 0)
            .scaleEffect(showMilestones ? 1 : 0.5)
            .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.15), value: showMilestones)

            Text("Day \(milestone.day)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(milestone.title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(milestone.achieved ? .orange : .secondary)
        }
    }

    @ViewBuilder
    private func rewardItem(icon: String, color: Color, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    JourneyMilestonesStep(onNext: {}, onSkip: {})
}
