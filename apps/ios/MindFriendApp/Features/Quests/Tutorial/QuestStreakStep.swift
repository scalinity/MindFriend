//
//  QuestStreakStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: Explain streaks and momentum
//

import SwiftUI

/// Step 3: Show how streaks build momentum
struct QuestStreakStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var dayStates: [Bool] = Array(repeating: false, count: 7)
    @State private var showExplanation = false

    var body: some View {
        TutorialStepView(
            icon: "flame.fill",
            iconColor: .orange,
            headline: "Build Momentum",
            subheadline: "Complete your quest each day to build a streak. Consistency leads to lasting change.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 24) {
                // Week visualization
                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { day in
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(dayStates[day] ? Color.orange : Color(.systemGray5))
                                    .frame(width: 36, height: 36)

                                if dayStates[day] {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }

                            Text(dayLabels[day])
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .scaleEffect(dayStates[day] ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: dayStates[day])
                    }
                }

                // Streak benefits
                VStack(alignment: .leading, spacing: 12) {
                    Text("As your streak grows:")
                        .font(.subheadline.weight(.medium))

                    ForEach(Array(benefits.enumerated()), id: \.element.text) { index, benefit in
                        HStack(spacing: 8) {
                            Image(systemName: benefit.icon)
                                .font(.caption)
                                .foregroundStyle(benefit.color)
                            Text(benefit.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .opacity(showExplanation ? 1 : 0)
                        .offset(x: showExplanation ? 0 : -10)
                        .animation(
                            .easeOut(duration: 0.3).delay(1.5 + Double(index) * 0.1),
                            value: showExplanation
                        )
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
            }
            .onAppear {
                animateWeek()
            }
        }
    }

    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    private var benefits: [(icon: String, color: Color, text: String)] {
        [
            ("arrow.up.circle.fill", .green, "Earn more XP per quest"),
            ("brain.head.profile", .purple, "Build stronger habits"),
            ("trophy.fill", .yellow, "Unlock streak badges")
        ]
    }

    private func animateWeek() {
        for day in 0..<7 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(day) * 0.15) {
                withAnimation {
                    dayStates[day] = true
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showExplanation = true
        }
    }
}

#Preview {
    QuestStreakStep(onNext: {}, onSkip: {})
}
