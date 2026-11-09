//
//  QuestConceptStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: Explain what quests are
//

import SwiftUI

/// Step 1: Introduce the concept of daily quests
struct QuestConceptStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        TutorialStepView(
            icon: "star.fill",
            iconColor: SupportTheme.Celebration.gold,
            headline: "What are quests?",
            subheadline: "Quests are small, achievable daily challenges designed to improve your wellbeing.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                // Quest characteristics
                ForEach(Array(characteristics.enumerated()), id: \.element.title) { index, item in
                    HStack(spacing: SupportTheme.Spacing.s) {
                        Image(systemName: item.icon)
                            .font(.title3)
                            .foregroundStyle(item.color)
                            .frame(minWidth: 28)

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                            Text(item.description)
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .celebrationReveal(delay: Double(index) * 0.1)
                }
            }
            .padding(.horizontal, SupportTheme.Spacing.l)
        }
    }

    private var characteristics: [(icon: String, color: Color, title: String, description: String)] {
        [
            ("clock", SupportTheme.accent, "Quick and simple", "Most quests take just 5-15 minutes"),
            ("brain.head.profile", SupportTheme.accent, "Science-backed", "Based on proven wellbeing practices"),
            ("person.fill.checkmark", SupportTheme.accent, "Personalized", "Matched to your current energy level"),
            ("sparkles", SupportTheme.Celebration.gold, "Rewarding", "Earn XP and see your progress")
        ]
    }
}

#Preview {
    QuestConceptStep(onNext: {}, onSkip: {})
}
