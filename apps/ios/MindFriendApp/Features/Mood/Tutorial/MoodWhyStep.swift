//
//  MoodWhyStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: Why track mood?
//

import SwiftUI

/// Step 1: Explain the benefits of mood tracking
struct MoodWhyStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    private let benefits: [(icon: String, color: Color, title: String, description: String)] = [
        ("chart.line.uptrend.xyaxis", SupportTheme.accent, "Spot patterns", "See what affects your mood over time"),
        ("lightbulb.fill", SupportTheme.Celebration.gold, "Get insights", "AI analyzes your data for personalized tips"),
        ("bell.fill", SupportTheme.Celebration.gold, "Early warnings", "Know when you might need extra support"),
        ("sparkles", SupportTheme.accent, "Better recommendations", "More accurate quest and exercise suggestions")
    ]

    var body: some View {
        TutorialStepView(
            icon: "face.smiling.fill",
            iconColor: SupportTheme.accent,
            headline: "Why track mood?",
            subheadline: "Your mood data powers personalized insights and predictions.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                ForEach(Array(benefits.enumerated()), id: \.element.title) { index, benefit in
                    HStack(spacing: SupportTheme.Spacing.s) {
                        Image(systemName: benefit.icon)
                            .font(.title3)
                            .foregroundStyle(benefit.color)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text(benefit.title)
                                .font(.subheadline.weight(.medium))
                            Text(benefit.description)
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(SupportTheme.Spacing.s)
                    .background(SupportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    .celebrationReveal(delay: Double(index) * 0.1)
                }
            }
            .padding(.horizontal, SupportTheme.Spacing.l)
        }
    }
}

#Preview {
    MoodWhyStep(onNext: {}, onSkip: {})
}
