//
//  ExerciseLibraryStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: Introduce the exercise library
//

import SwiftUI

/// Step 1: Show the variety of exercises available
struct ExerciseLibraryStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showCategories = false

    private let categories: [(icon: String, color: Color, name: String, count: Int)] = [
        ("wind", .cyan, "Breathing", 10),
        ("sparkles", .purple, "Meditation", 12),
        ("hand.raised.fill", .green, "Grounding", 8),
        ("pencil.and.outline", .orange, "Journaling", 8),
        ("figure.walk", .pink, "Movement", 7)
    ]

    var body: some View {
        TutorialStepView(
            icon: "figure.mind.and.body",
            iconColor: .green,
            headline: "Exercise Library",
            subheadline: "Access 45+ exercises across 5 categories, designed to help you feel better fast.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 12) {
                ForEach(Array(categories.enumerated()), id: \.element.name) { index, category in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(category.color.opacity(0.15))
                                .frame(width: 40, height: 40)
                            Image(systemName: category.icon)
                                .foregroundStyle(category.color)
                        }

                        Text(category.name)
                            .font(.subheadline.weight(.medium))

                        Spacer()

                        Text("\(category.count) exercises")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .opacity(showCategories ? 1 : 0)
                    .offset(x: showCategories ? 0 : 20)
                    .animation(
                        .easeOut(duration: 0.3).delay(0.2 + Double(index) * 0.1),
                        value: showCategories
                    )
                }
            }
            .padding(.horizontal, 24)
            .onAppear { showCategories = true }
        }
    }
}

#Preview {
    ExerciseLibraryStep(onNext: {}, onSkip: {})
}
