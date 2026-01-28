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
    @State private var showQuests = false

    var body: some View {
        TutorialStepView(
            icon: "hand.tap.fill",
            iconColor: .blue,
            headline: "Choose Your Quest",
            subheadline: "Each day, you can pick from three options. Choose what feels right for your energy level.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 12) {
                ForEach(Array(questOptions.enumerated()), id: \.element.title) { index, quest in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedQuest = index
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: quest.icon)
                                .font(.title3)
                                .foregroundStyle(quest.color)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(quest.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)

                                HStack(spacing: 8) {
                                    Label(quest.duration, systemImage: "clock")
                                    Label(quest.difficulty, systemImage: "leaf")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if selectedQuest == index {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(
                                            selectedQuest == index ? Color.green : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .opacity(showQuests ? 1 : 0)
                    .offset(y: showQuests ? 0 : 15)
                    .animation(
                        .easeOut(duration: 0.4).delay(0.2 + Double(index) * 0.1),
                        value: showQuests
                    )
                }

                // Tip text
                Text("Tap a quest above to see how selection works")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .opacity(selectedQuest == nil ? 1 : 0)
            }
            .padding(.horizontal, 24)
            .onAppear {
                showQuests = true
            }
        }
    }

    private var questOptions: [(icon: String, color: Color, title: String, duration: String, difficulty: String)] {
        [
            ("figure.walk", .green, "Take a mindful walk", "10 min", "Easy"),
            ("drop.fill", .blue, "Practice deep breathing", "5 min", "Easy"),
            ("pencil.and.outline", .purple, "Journal 3 gratitudes", "5 min", "Medium")
        ]
    }
}

#Preview {
    QuestChoiceStep(onNext: {}, onSkip: {})
}
