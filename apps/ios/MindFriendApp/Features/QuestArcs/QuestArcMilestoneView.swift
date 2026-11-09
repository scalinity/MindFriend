//
//  QuestArcMilestoneView.swift
//  MindFriendApp
//
//  Celebration view shown when user reaches an arc milestone
//

import SwiftUI

struct QuestArcMilestoneView: View {
    let arcTitle: String
    let milestoneNumber: Int
    let totalMilestones: Int
    let dayNumber: Int
    let onDismiss: () -> Void
    let onShare: () -> Void

    @State private var showConfetti = false

    var body: some View {
        ZStack {
            // Background gradient
            SupportTheme.canvas
            .ignoresSafeArea()

            // Content
            VStack(spacing: SupportTheme.Spacing.xl) {
                Spacer()

                CelebrationEmblem(.text("\(milestoneNumber)"), tint: SupportTheme.Celebration.gold)
                    .celebrationReveal()

                VStack(spacing: SupportTheme.Spacing.s) {
                    Text("Milestone reached")
                        .font(.largeTitle.weight(.bold))

                    Text("Day \(dayNumber) of \(arcTitle)")
                        .font(.title3)
                        .foregroundStyle(SupportTheme.textSecondary)

                    Text("Milestone \(milestoneNumber) of \(totalMilestones)")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .multilineTextAlignment(.center)

                // Encouragement message
                Text(encouragementMessage)
                    .font(.body)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SupportTheme.Spacing.xl)

                Spacer()

                // Actions
                VStack(spacing: SupportTheme.Spacing.s) {
                    Button {
                        onShare()
                    } label: {
                        Label("Share with Circles", systemImage: "person.2.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.supportPrimary)

                    Button {
                        onDismiss()
                    } label: {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                            .padding(SupportTheme.Spacing.m)
                            .background(SupportTheme.surface)
                            .foregroundStyle(SupportTheme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)
                .padding(.bottom, SupportTheme.Spacing.xl)
            }

            // Confetti overlay
            if showConfetti {
                CelebrationParticles()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showConfetti = true
            }
        }
    }

    private var encouragementMessage: String {
        switch milestoneNumber {
        case 1:
            return "You've reached your first milestone. Take a moment to notice what helped."
        case 2:
            return "You're halfway through your journey. Your completed practices are here to revisit."
        case 3:
            return "You've reached another milestone. Continue at a pace that works for you."
        default:
            if milestoneNumber == totalMilestones {
                return "You've completed this journey. Take a moment to reflect on what you want to carry forward."
            }
            return "Another part of your journey is complete."
        }
    }
}


// MARK: - Arc Completion View

struct QuestArcCompletionView: View {
    let arcTitle: String
    let totalDays: Int
    let totalMilestones: Int
    let onDismiss: () -> Void
    let onBrowseMore: () -> Void

    @State private var showConfetti = false

    var body: some View {
        ZStack {
            // Background gradient
            SupportTheme.canvas
            .ignoresSafeArea()

            VStack(spacing: SupportTheme.Spacing.xl) {
                Spacer()

                CelebrationEmblem(.symbol("trophy.fill"), tint: SupportTheme.Celebration.gold)
                    .celebrationReveal()

                VStack(spacing: SupportTheme.Spacing.s) {
                    Text("Journey complete")
                        .font(.largeTitle.weight(.bold))

                    Text(arcTitle)
                        .font(.title3)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                // Stats
                HStack(spacing: SupportTheme.Spacing.xl) {
                    VStack {
                        Text("\(totalDays)")
                            .font(.title.weight(.bold))
                        Text("Days")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    VStack {
                        Text("\(totalMilestones)")
                            .font(.title.weight(.bold))
                        Text("Milestones")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
                .supportCard()

                Text("Congratulations on completing your wellness journey! You've built lasting habits and shown incredible dedication.")
                    .font(.body)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SupportTheme.Spacing.xl)

                Spacer()

                VStack(spacing: SupportTheme.Spacing.s) {
                    Button {
                        onBrowseMore()
                    } label: {
                        Label("Start Another Journey", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.supportPrimary)

                    Button {
                        onDismiss()
                    } label: {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                            .padding(SupportTheme.Spacing.m)
                            .background(SupportTheme.surface)
                            .foregroundStyle(SupportTheme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)
                .padding(.bottom, SupportTheme.Spacing.xl)
            }

            if showConfetti {
                CelebrationParticles()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showConfetti = true
            }
        }
    }
}

#Preview("Milestone") {
    QuestArcMilestoneView(
        arcTitle: "Stress Relief Journey",
        milestoneNumber: 1,
        totalMilestones: 3,
        dayNumber: 3,
        onDismiss: {},
        onShare: {}
    )
}

#Preview("Completion") {
    QuestArcCompletionView(
        arcTitle: "Stress Relief Journey",
        totalDays: 14,
        totalMilestones: 3,
        onDismiss: {},
        onBrowseMore: {}
    )
}
