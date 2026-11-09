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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private let moods: [(emoji: String, label: String, color: Color)] = [
        ("😔", "Awful", SupportTheme.accent),
        ("😕", "Bad", SupportTheme.Celebration.gold),
        ("😐", "Okay", SupportTheme.Celebration.gold),
        ("🙂", "Good", SupportTheme.accent),
        ("😁", "Great", SupportTheme.accent)
    ]

    var body: some View {
        TutorialStepView(
            icon: "clock.badge.checkmark.fill",
            iconColor: SupportTheme.accent,
            headline: "A moment to check in",
            subheadline: "Choose how you're feeling. Add details if you'd like.",
            primaryLabel: "Start Logging",
            primaryAction: onComplete
        ) {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Mood selector preview
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Text("How are you feeling?")
                        .font(.subheadline.weight(.medium))

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : (typeSize >= .xxLarge ? 2 : 5)), spacing: SupportTheme.Spacing.xs) {
                        ForEach(Array(moods.enumerated()), id: \.element.label) { index, mood in
                            Button {
                                withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.3)) {
                                    selectedMood = index
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    withAnimation(.easeInOut(duration: 0.2)) { showDetails = true }
                                }
                            } label: {
                                VStack(spacing: SupportTheme.Spacing.xs) {
                                    Text(mood.emoji)
                                        .font(.title)
                                        .grayscale(selectedMood == index ? 0 : 0.8)
                                        .opacity(selectedMood == index ? 1 : 0.6)

                                    Text(mood.label)
                                        .font(.caption2)
                                        .foregroundStyle(selectedMood == index ? SupportTheme.textPrimary : SupportTheme.textSecondary)
                                }
                            }
                            .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                            .accessibilityLabel(mood.label)
                            .accessibilityAddTraits(selectedMood == index ? .isSelected : [])
                        }
                    }
                }
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                .padding(.horizontal, SupportTheme.Spacing.l)

                // Optional details
                if showDetails {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        Text("Add context (optional)")
                            .font(.caption.weight(.medium))

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: SupportTheme.Spacing.xs) {
                            TagPill(text: "Work")
                            TagPill(text: "Sleep")
                            TagPill(text: "Exercise")
                            TagPill(text: "Social")
                        }
                    }
                    .padding(SupportTheme.Spacing.s)
                    .background(SupportTheme.elevated)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    .padding(.horizontal, SupportTheme.Spacing.l)
                    .transition(.opacity)
                }

                // Tip
                Text("Tap a mood above to try it out.")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
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
            .padding(.horizontal, SupportTheme.Spacing.xs)
            .padding(.vertical, SupportTheme.Spacing.xs)
            .background(SupportTheme.separator)
            .clipShape(Capsule())
    }
}

#Preview {
    MoodHowStep(onComplete: {})
}
