//
//  AchievementsBadgesStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: Badge collection
//

import SwiftUI

/// Step 2: Show badge system
struct AchievementsBadgesStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var unlockedBadges: Set<Int> = []

    private let badges: [(icon: String, color: Color, name: String)] = [
        ("flame.fill", .orange, "First Streak"),
        ("star.fill", .yellow, "Quest Master"),
        ("moon.fill", .purple, "Night Owl"),
        ("sun.max.fill", .orange, "Early Bird"),
        ("heart.fill", .pink, "Self-Care Pro"),
        ("brain.head.profile", .teal, "Mindful One")
    ]

    var body: some View {
        TutorialStepView(
            icon: "medal.fill",
            iconColor: .orange,
            headline: "Collect Badges",
            subheadline: "Unlock achievements for milestones, streaks, and special accomplishments.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 16) {
                // Badge grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(Array(badges.enumerated()), id: \.element.name) { index, badge in
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(unlockedBadges.contains(index)
                                          ? badge.color.opacity(0.15)
                                          : Color(.systemGray5))
                                    .frame(width: 48, height: 48)

                                Image(systemName: badge.icon)
                                    .font(.title2)
                                    .foregroundStyle(unlockedBadges.contains(index)
                                                     ? badge.color
                                                     : .secondary.opacity(0.5))
                            }
                            .scaleEffect(unlockedBadges.contains(index) ? 1.1 : 1.0)

                            Text(badge.name)
                                .font(.caption2)
                                .foregroundStyle(unlockedBadges.contains(index) ? .primary : .secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 20)

                // Stats
                HStack(spacing: 16) {
                    VStack {
                        Text("50+")
                            .font(.title2.bold())
                        Text("Total Badges")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack {
                        Text("\(unlockedBadges.count)")
                            .font(.title2.bold())
                            .foregroundStyle(.orange)
                            .contentTransition(.numericText())
                        Text("Unlocked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
            }
            .onAppear {
                animateBadges()
            }
        }
    }

    private func animateBadges() {
        for index in 0..<badges.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(index) * 0.2) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    _ = unlockedBadges.insert(index)
                }
            }
        }
    }
}

#Preview {
    AchievementsBadgesStep(onNext: {}, onSkip: {})
}
