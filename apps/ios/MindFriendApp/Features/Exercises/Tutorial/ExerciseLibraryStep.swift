//
//  ExerciseLibraryStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: Introduce the exercise library
//

import SwiftUI

/// Step 1: Show the variety of exercises available
struct ExerciseLibraryStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showCategories = false

    private let categories: [(icon: String, color: Color, name: String, count: Int)] = [
        ("wind", SupportTheme.accent, "Breathing", 10),
        ("sparkles", SupportTheme.accent, "Meditation", 12),
        ("hand.raised.fill", SupportTheme.accent, "Grounding", 8),
        ("pencil.and.outline", SupportTheme.accent, "Journaling", 8),
        ("figure.walk", SupportTheme.accent, "Movement", 7)
    ]

    var body: some View {
        TutorialStepView(
            icon: "figure.mind.and.body",
            iconColor: SupportTheme.accent,
            headline: "Exercise Library",
            subheadline: "Access 45+ exercises across 5 categories, designed to help you feel better fast.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                ForEach(Array(categories.enumerated()), id: \.element.name) { index, category in
                    HStack(spacing: SupportTheme.Spacing.s) {
                        ZStack {
                            Circle()
                                .fill(SupportTheme.accent.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: category.icon)
                                .foregroundStyle(SupportTheme.accent)
                        }

                        Text(category.name)
                            .font(.subheadline.weight(.medium))

                        Spacer()

                        Text("\(category.count) exercises")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                            .fixedSize()
                    }
                    .padding(.horizontal, SupportTheme.Spacing.s)
                    .padding(.vertical, SupportTheme.Spacing.xs)
                    .background(SupportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    .opacity(showCategories ? 1 : 0)
                    .offset(x: reduceMotion ? 0 : (showCategories ? 0 : 20))
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) :
                        .easeOut(duration: 0.3).delay(0.2 + Double(index) * 0.1),
                        value: showCategories
                    )
                }
            }
            .padding(.horizontal, SupportTheme.Spacing.m)
            .onAppear { showCategories = true }
        }
    }
}

#Preview {
    ExerciseLibraryStep(onNext: {}, onSkip: {})
}
