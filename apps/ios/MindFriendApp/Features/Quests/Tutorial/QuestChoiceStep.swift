//
//  QuestChoiceStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: Explain quest selection
//

import SwiftUI

/// Step 2: Show how quest selection works
struct QuestChoiceStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var selectedQuest: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TutorialStepView(
            icon: "hand.tap.fill",
            iconColor: SupportTheme.accent,
            headline: "Choose your quest",
            subheadline: "Each day, you can pick from three options. Choose what feels right for your energy level.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                ForEach(Array(questOptions.enumerated()), id: \.element.title) { index, quest in
                    Button {
                        withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.3)) {
                            selectedQuest = index
                        }
                    } label: {
                        HStack(spacing: SupportTheme.Spacing.s) {
                            Image(systemName: quest.icon)
                                .font(.title3)
                                .foregroundStyle(quest.color)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                                Text(quest.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(SupportTheme.textPrimary)

                                HStack(spacing: SupportTheme.Spacing.xs) {
                                    Label(quest.duration, systemImage: "clock")
                                    Label(quest.difficulty, systemImage: "leaf")
                                }
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                            }

                            Spacer()

                            if selectedQuest == index {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(SupportTheme.accent)
                                    .transition(.opacity)
                            }
                        }
                        .padding(SupportTheme.Spacing.s)
                        .background(
                            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                .fill(SupportTheme.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                        .strokeBorder(
                                            selectedQuest == index ? SupportTheme.accent : SupportTheme.border,
                                            lineWidth: 2
                                        )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .celebrationReveal(delay: Double(index) * 0.1)
                }

                // Tip text
                Text("Tap a quest above to see how selection works")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, SupportTheme.Spacing.xs)
                    .opacity(selectedQuest == nil ? 1 : 0)
            }
            .padding(.horizontal, SupportTheme.Spacing.l)
        }
    }

    private var questOptions: [(icon: String, color: Color, title: String, duration: String, difficulty: String)] {
        [
            ("figure.walk", SupportTheme.accent, "Take a mindful walk", "10 min", "Easy"),
            ("drop.fill", SupportTheme.accent, "Practice deep breathing", "5 min", "Easy"),
            ("pencil.and.outline", SupportTheme.accent, "Journal 3 gratitudes", "5 min", "Medium")
        ]
    }
}

#Preview {
    QuestChoiceStep(onNext: {}, onSkip: {})
}
