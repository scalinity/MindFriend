//
//  HomeQuestStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: Explain daily quests
//

import SwiftUI

/// Step 2: Explain what quests are and why they matter
struct HomeQuestStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showQuest = false
    @State private var showCheckmark = false

    var body: some View {
        TutorialStepView(
            icon: "star.fill",
            iconColor: .orange,
            headline: "Your Daily Quest",
            subheadline: "Each day, you'll receive a personalized micro-challenge designed to boost your wellbeing.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 16) {
                // Example quest card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.orange)
                        Text("Today's Quest")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if showCheckmark {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }

                    Text("Take a 5-minute mindful walk")
                        .font(.headline)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Label("5 min", systemImage: "clock")
                        Label("Easy", systemImage: "leaf")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .scaleEffect(showQuest ? 1 : 0.9)
                .opacity(showQuest ? 1 : 0)
                .padding(.horizontal, 20)

                // Explanation
                Text("Quests are matched to your current energy level and take just a few minutes to complete.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .opacity(showQuest ? 1 : 0)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                    showQuest = true
                }
                withAnimation(.easeOut(duration: 0.3).delay(1.2)) {
                    showCheckmark = true
                }
            }
        }
    }
}

#Preview {
    HomeQuestStep(onNext: {}, onSkip: {})
}
