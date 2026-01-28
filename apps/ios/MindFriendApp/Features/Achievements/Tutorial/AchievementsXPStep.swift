//
//  AchievementsXPStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: XP and leveling system
//

import SwiftUI

/// Step 1: Explain XP earning and levels
struct AchievementsXPStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var xpAmount = 0
    @State private var level = 1
    @State private var showActivities = false

    var body: some View {
        TutorialStepView(
            icon: "star.fill",
            iconColor: .yellow,
            headline: "Earn XP & Level Up",
            subheadline: "Every wellness activity earns you experience points. Level up to unlock more features!",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 20) {
                // Level display
                VStack(spacing: 8) {
                    HStack {
                        Text("Level \(level)")
                            .font(.headline)
                            .contentTransition(.numericText())

                        Spacer()

                        Text("\(xpAmount) XP")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.systemGray5))

                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.yellow.gradient)
                                .frame(width: geo.size.width * min(Double(xpAmount) / 500.0, 1.0))
                        }
                    }
                    .frame(height: 10)

                    Text("500 XP to next level")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)

                // XP sources
                VStack(alignment: .leading, spacing: 10) {
                    Text("Earn XP from:")
                        .font(.subheadline.weight(.medium))

                    ForEach(Array(xpSources.enumerated()), id: \.element.activity) { index, source in
                        HStack {
                            Image(systemName: source.icon)
                                .foregroundStyle(source.color)
                                .frame(width: 24)
                            Text(source.activity)
                                .font(.caption)
                            Spacer()
                            Text("+\(source.xp) XP")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.yellow)
                        }
                        .opacity(showActivities ? 1 : 0)
                        .animation(
                            .easeOut(duration: 0.3).delay(0.8 + Double(index) * 0.1),
                            value: showActivities
                        )
                    }
                }
                .padding()
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
            }
            .onAppear {
                animateXP()
            }
        }
    }

    private var xpSources: [(icon: String, color: Color, activity: String, xp: Int)] {
        [
            ("star.fill", .orange, "Complete quest", 50),
            ("face.smiling", .pink, "Log mood", 10),
            ("figure.mind.and.body", .green, "Do exercise", 25),
            ("bubble.left.fill", .blue, "Chat session", 15)
        ]
    }

    private func animateXP() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            withAnimation(.easeOut(duration: 0.1)) {
                xpAmount += 10
            }
            if xpAmount >= 350 {
                timer.invalidate()
                showActivities = true
            }
        }
    }
}

#Preview {
    AchievementsXPStep(onNext: {}, onSkip: {})
}
