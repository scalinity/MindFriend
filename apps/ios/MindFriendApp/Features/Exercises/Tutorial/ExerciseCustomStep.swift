//
//  ExerciseCustomStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: AI-generated custom exercises
//

import SwiftUI

/// Step 3: Show custom exercise generation
struct ExerciseCustomStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onComplete: () -> Void

    @State private var showGeneration = false
    @State private var showExercise = false

    var body: some View {
        TutorialStepView(
            icon: "wand.and.stars",
            iconColor: SupportTheme.accent,
            headline: "Custom Exercises",
            subheadline: "Need something specific? AI can generate personalized exercises just for you.",
            primaryLabel: "Start Exploring",
            primaryAction: onComplete
        ) {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Generation animation
                VStack(spacing: SupportTheme.Spacing.xs) {
                    if !showExercise {
                        // Generating state
                        HStack(spacing: SupportTheme.Spacing.s) {
                            Image(systemName: "wand.and.stars")
                                .font(.title2)
                                .foregroundStyle(SupportTheme.accent)
                                .symbolEffect(.pulse.wholeSymbol, isActive: !reduceMotion && (showGeneration))

                            VStack(alignment: .leading) {
                                Text("Generating custom exercise...")
                                    .font(.subheadline.weight(.medium))
                                Text("Based on: \"Help me calm down before sleep\"")
                                    .font(.caption)
                                    .foregroundStyle(SupportTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()
                        }
                        .padding(SupportTheme.Spacing.s)
                        .background(SupportTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                        .transition(reduceMotion ? .opacity : .opacity)
                    }

                    if showExercise {
                        // Generated exercise
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            HStack {
                                Image(systemName: "moon.stars.fill")
                                    .foregroundStyle(SupportTheme.accent)
                                Text("Evening Wind-Down")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("AI Generated")
                                    .font(.caption2)
                                    .foregroundStyle(SupportTheme.accent)
                                    .padding(.horizontal, SupportTheme.Spacing.xs)
                                    .padding(.vertical, SupportTheme.Spacing.xxs)
                                    .background(SupportTheme.surface)
                                    .clipShape(Capsule())
                            }

                            Text("A gentle 5-minute breathing exercise designed to help you transition to restful sleep.")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: SupportTheme.Spacing.s) {
                                Label("5 min", systemImage: "clock")
                                Label("Calming", systemImage: "leaf")
                            }
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                        }
                        .padding(SupportTheme.Spacing.s)
                        .background(SupportTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)

                // Premium note
                HStack(spacing: SupportTheme.Spacing.xxs) {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.accent)
                    Text("Premium feature")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .opacity(showExercise ? 1 : 0)
            }
            .onAppear {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.3).delay(0.3)) {
                    showGeneration = true
                }
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.4).delay(1.5)) {
                    showExercise = true
                }
            }
        }
    }
}

#Preview {
    ExerciseCustomStep(onComplete: {})
}
