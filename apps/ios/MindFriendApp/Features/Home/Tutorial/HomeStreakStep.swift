//
//  HomeStreakStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: Explain streaks and shields
//

import SwiftUI

/// Step 3: Explain how streaks work and the shield protection
struct HomeStreakStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var streakCount = 0
    @State private var showShield = false

    var body: some View {
        TutorialStepView(
            icon: "flame.fill",
            iconColor: .orange,
            headline: "Build Your Streak",
            subheadline: "Complete quests daily to build momentum. Consistency is key to lasting change.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 16) {
                // Animated streak counter
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)

                    Text("\(streakCount)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())

                    Text("day streak")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                // Shield explanation
                HStack(spacing: 12) {
                    Image(systemName: "shield.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .scaleEffect(showShield ? 1.0 : 0.5)
                        .opacity(showShield ? 1 : 0)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Streak Shields")
                            .font(.subheadline.weight(.semibold))
                        Text("Premium users get shields to protect their streak when life gets busy.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(showShield ? 1 : 0)

                    Spacer()
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
            }
            .onAppear {
                // Animate streak count
                animateStreak()
                // Show shield after streak animation
                withAnimation(.easeOut(duration: 0.5).delay(1.5)) {
                    showShield = true
                }
            }
        }
    }

    private func animateStreak() {
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { timer in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                streakCount += 1
            }
            if streakCount >= 7 {
                timer.invalidate()
            }
        }
    }
}

#Preview {
    HomeStreakStep(onNext: {}, onSkip: {})
}
