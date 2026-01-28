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

    @State private var showElements = false

    var body: some View {
        TutorialStepView(
            icon: "star.fill",
            iconColor: .orange,
            headline: "What Are Quests?",
            subheadline: "Quests are small, achievable daily challenges designed to improve your wellbeing.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 16) {
                // Quest characteristics
                ForEach(Array(characteristics.enumerated()), id: \.element.title) { index, item in
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.title3)
                            .foregroundStyle(item.color)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                            Text(item.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .opacity(showElements ? 1 : 0)
                    .offset(y: showElements ? 0 : 10)
                    .animation(
                        .easeOut(duration: 0.4).delay(0.2 + Double(index) * 0.15),
                        value: showElements
                    )
                }
            }
            .padding(.horizontal, 24)
            .onAppear {
                showElements = true
            }
        }
    }

    private var characteristics: [(icon: String, color: Color, title: String, description: String)] {
        [
            ("clock", .blue, "Quick & Easy", "Most quests take just 5-15 minutes"),
            ("brain.head.profile", .purple, "Science-Backed", "Based on proven wellbeing practices"),
            ("person.fill.checkmark", .green, "Personalized", "Matched to your current energy level"),
            ("sparkles", .orange, "Rewarding", "Earn XP and maintain your streak")
        ]
    }
}

#Preview {
    QuestConceptStep(onNext: {}, onSkip: {})
}
