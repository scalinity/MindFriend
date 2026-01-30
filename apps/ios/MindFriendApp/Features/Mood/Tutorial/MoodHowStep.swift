//
//  MoodHowStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: How to log mood
//

import SwiftUI

/// Step 2: Show the quick mood logging process
struct MoodHowStep: View {
    let onComplete: () -> Void

    @State private var selectedMood: Int? = nil
    @State private var showDetails = false

    private let moods: [(emoji: String, label: String, color: Color)] = [
        ("😔", "Awful", .red),
        ("😕", "Bad", .orange),
        ("😐", "Okay", .yellow),
        ("🙂", "Good", .green),
        ("😁", "Great", .blue)
    ]

    var body: some View {
        TutorialStepView(
            icon: "clock.badge.checkmark.fill",
            iconColor: .green,
            headline: "Quick & Easy",
            subheadline: "Just tap how you're feeling. Takes 5 seconds!",
            primaryLabel: "Start Logging",
            primaryAction: onComplete
        ) {
            VStack(spacing: 16) {
                // Mood selector preview
                VStack(spacing: 8) {
                    Text("How are you feeling?")
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 12) {
                        ForEach(Array(moods.enumerated()), id: \.element.label) { index, mood in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    selectedMood = index
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    withAnimation { showDetails = true }
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Text(mood.emoji)
                                        .font(.title)
                                        .grayscale(selectedMood == index ? 0 : 0.8)
                                        .opacity(selectedMood == index ? 1 : 0.6)

                                    Text(mood.label)
                                        .font(.caption2)
                                        .foregroundStyle(selectedMood == index ? .primary : .secondary)
                                }
                            }
                            .scaleEffect(selectedMood == index ? 1.15 : 1.0)
                        }
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)

                // Optional details
                if showDetails {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add context (optional)")
                            .font(.caption.weight(.medium))

                        HStack(spacing: 8) {
                            TagPill(text: "Work")
                            TagPill(text: "Sleep")
                            TagPill(text: "Exercise")
                            TagPill(text: "Social")
                        }
                    }
                    .padding(12)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Tip
                Text("Tap a mood above to try it out!")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .opacity(selectedMood == nil ? 1 : 0)
            }
        }
    }
}

private struct TagPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray5))
            .clipShape(Capsule())
    }
}

#Preview {
    MoodHowStep(onComplete: {})
}
