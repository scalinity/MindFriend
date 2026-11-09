//
//  ProgramsConceptStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: What are programs?
//

import SwiftUI

/// Step 1: Introduce the concept of multi-day programs
struct ProgramsConceptStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showElements = false

    var body: some View {
        TutorialStepView(
            icon: "book.fill",
            iconColor: SupportTheme.accent,
            headline: "What Are Programs?",
            subheadline: "Programs are structured multi-day journeys designed to help you build lasting skills and habits.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                // Comparison: Quest vs Program
                HStack(spacing: SupportTheme.Spacing.s) {
                    // Quest card
                    VStack(spacing: SupportTheme.Spacing.xs) {
                        Image(systemName: "star.fill")
                            .font(.title2)
                            .foregroundStyle(SupportTheme.accent)

                        Text("Quest")
                            .font(.subheadline.weight(.medium))

                        Text("Single day challenge")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(SupportTheme.Spacing.s)
                    .frame(maxWidth: .infinity)
                    .background(SupportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    .opacity(showElements ? 1 : 0)
                    .offset(y: reduceMotion ? 0 : (showElements ? 0 : 10))

                    // Arrow
                    Image(systemName: "arrow.right")
                        .foregroundStyle(SupportTheme.textSecondary)
                        .opacity(showElements ? 1 : 0)

                    // Program card
                    VStack(spacing: SupportTheme.Spacing.xs) {
                        Image(systemName: "book.fill")
                            .font(.title2)
                            .foregroundStyle(SupportTheme.accent)

                        Text("Program")
                            .font(.subheadline.weight(.medium))

                        Text("Multi-week journey")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(SupportTheme.Spacing.s)
                    .frame(maxWidth: .infinity)
                    .background(SupportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    .opacity(showElements ? 1 : 0.3)
                    .offset(y: reduceMotion ? 0 : (showElements ? 0 : 10))
                }
                .padding(.horizontal, SupportTheme.Spacing.m)

                // Program features
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    ForEach(Array(features.enumerated()), id: \.element.text) { index, feature in
                        HStack(spacing: SupportTheme.Spacing.xs) {
                            Image(systemName: feature.icon)
                                .font(.caption)
                                .foregroundStyle(feature.color)
                                .frame(width: 20)

                            Text(feature.text)
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .opacity(showElements ? 1 : 0)
                        .animation(reduceMotion ? .easeInOut(duration: 0.2) :
                            .easeOut(duration: 0.3).delay(0.5 + Double(index) * 0.1),
                            value: showElements
                        )
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.l)
            }
            .onAppear {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.5).delay(0.3)) {
                    showElements = true
                }
            }
        }
    }

    private var features: [(icon: String, color: Color, text: String)] {
        [
            ("calendar", SupportTheme.accent, "7-30 day structured curriculum"),
            ("brain.head.profile", SupportTheme.accent, "Science-backed methodologies"),
            ("chart.line.uptrend.xyaxis", SupportTheme.accent, "Progressive skill building"),
            ("rosette", SupportTheme.accent, "Earn completion certificates")
        ]
    }
}

#Preview {
    ProgramsConceptStep(onNext: {}, onSkip: {})
}
