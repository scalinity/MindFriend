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

    private let categories: [(icon: String, area: SupportTheme.Area, name: String, count: Int)] = [
        ("wind", ExerciseType.breathing.categoryArea, "Breathing", 10),
        ("sparkles", ExerciseType.meditation.categoryArea, "Meditation", 12),
        ("hand.raised.fill", ExerciseType.grounding.categoryArea, "Grounding", 8),
        ("pencil.and.outline", ExerciseType.journaling.categoryArea, "Journaling", 8),
        ("figure.walk", ExerciseType.movement.categoryArea, "Movement", 7)
    ]

    var body: some View {
        TutorialStepView(
            icon: "figure.mind.and.body",
            iconColor: SupportTheme.Area.insights.palette.ink,
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
                                .fill(category.area.palette.tint)
                                .frame(width: 36, height: 36)
                            Image(systemName: category.icon)
                                .foregroundStyle(category.area.palette.ink)
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
