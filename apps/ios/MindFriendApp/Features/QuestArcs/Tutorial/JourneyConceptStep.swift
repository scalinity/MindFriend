//
//  JourneyConceptStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: Introduces what Quest Journeys are
//

import SwiftUI

/// Step 1: Explain the core journey concept
struct JourneyConceptStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showCategories = false

    private let categories = [
        ("brain.head.profile", "Stress", SupportTheme.accent),
        ("moon.zzz.fill", "Sleep", SupportTheme.accent),
        ("figure.stand", "Confidence", SupportTheme.accent),
        ("target", "Focus", SupportTheme.accent),
        ("heart.fill", "Resilience", SupportTheme.accent)
    ]

    var body: some View {
        JourneyTutorialStepLayout(
            icon: "map.fill",
            iconColor: SupportTheme.accent,
            headline: "Your Personal Growth Journey",
            subheadline: "Multi-day guided programs designed to build lasting habits and skills.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Journey categories
                HStack(spacing: SupportTheme.Spacing.s) {
                    ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                        VStack(spacing: SupportTheme.Spacing.xs) {
                            Image(systemName: category.0)
                                .font(.title2)
                                .foregroundStyle(category.2)
                                .frame(width: 38, height: 38)
                                .background(category.2.opacity(0.15))
                                .clipShape(Circle())
                                .scaleEffect(reduceMotion ? 1 : (showCategories ? 1.0 : 0.5))
                                .opacity(showCategories ? 1.0 : 0.0)

                            Text(category.1)
                                .font(.caption2)
                                .foregroundStyle(SupportTheme.textSecondary)
                                .opacity(showCategories ? 1.0 : 0.0)
                        }
                        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.4).delay(Double(index) * 0.1), value: showCategories)
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)

                // Explanation
                Text("Each journey focuses on a specific area, guiding you through **daily activities** that compound into real transformation.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .padding(.horizontal, SupportTheme.Spacing.m)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCategories = true
                }
            }
        }
    }
}

#Preview {
    JourneyConceptStep(onNext: {}, onSkip: {})
}
