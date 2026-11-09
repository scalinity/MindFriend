//
//  AchievementsXPStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: XP and leveling system
//

import SwiftUI

/// Step 1: Explain XP earning and levels
struct AchievementsXPStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var xpAmount = 0
    @State private var level = 1
    @State private var showActivities = false

    var body: some View {
        TutorialStepView(
            icon: "star.fill",
            iconColor: SupportTheme.Celebration.gold,
            headline: "Earn XP & Level Up",
            subheadline: "Every wellness activity earns you experience points. Level up to unlock more features!",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Level display
                VStack(spacing: SupportTheme.Spacing.xs) {
                    HStack {
                        Text("Level \(level)")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                            .contentTransition(reduceMotion ? .opacity : .numericText())

                        Spacer()

                        Text("\(xpAmount) XP")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                            .contentTransition(reduceMotion ? .opacity : .numericText())
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                                .fill(SupportTheme.field)

                            RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                                .fill(SupportTheme.Celebration.gold.gradient)
                                .frame(width: geo.size.width * min(Double(xpAmount) / 100.0, 1.0))
                        }
                    }
                    .frame(height: 10)

                    Text("100 XP to next level")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                .padding(.horizontal, SupportTheme.Spacing.l)

                // XP sources
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Text("Earn XP from:")
                        .font(.subheadline.weight(.medium))

                    ForEach(Array(xpSources.enumerated()), id: \.element.activity) { index, source in
                        HStack {
                            Image(systemName: source.icon)
                                .foregroundStyle(source.color)
                                .frame(width: 24)
                            Text(source.activity)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Text("+\(source.xp) XP")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SupportTheme.Celebration.gold)
                        }
                        .opacity(showActivities ? 1 : 0)
                        .animation(
                            reduceMotion
                                ? .easeInOut(duration: 0.2)
                                : (.easeOut(duration: 0.3).delay(0.8 + Double(index) * 0.1)),
                            value: showActivities
                        )
                    }
                }
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                .padding(.horizontal, SupportTheme.Spacing.l)
            }
            .onAppear {
                animateXP()
            }
        }
    }

    private var xpSources: [(icon: String, color: Color, activity: String, xp: Int)] {
        [
            ("star.fill", SupportTheme.accent, "Complete quest", 50),
            ("face.smiling", SupportTheme.accent, "Log mood", 10),
            ("figure.mind.and.body", SupportTheme.accent, "Do exercise", 25),
            ("bubble.left.fill", SupportTheme.accent, "Chat session", 15),
        ]
    }

    private func animateXP() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : (.easeOut(duration: 0.1))) {
                xpAmount += 5
            }
            if xpAmount >= 70 {
                timer.invalidate()
                showActivities = true
            }
        }
    }
}

#Preview {
    AchievementsXPStep(onNext: {}, onSkip: {})
}
