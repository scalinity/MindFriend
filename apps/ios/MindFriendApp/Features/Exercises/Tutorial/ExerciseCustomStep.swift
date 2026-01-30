//
//  ExerciseCustomStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: AI-generated custom exercises
//

import SwiftUI

/// Step 3: Show custom exercise generation
struct ExerciseCustomStep: View {
    let onComplete: () -> Void

    @State private var showGeneration = false
    @State private var showExercise = false

    var body: some View {
        TutorialStepView(
            icon: "wand.and.stars",
            iconColor: .orange,
            headline: "Custom Exercises",
            subheadline: "Need something specific? AI can generate personalized exercises just for you.",
            primaryLabel: "Start Exploring",
            primaryAction: onComplete
        ) {
            VStack(spacing: 16) {
                // Generation animation
                VStack(spacing: 8) {
                    if !showExercise {
                        // Generating state
                        HStack(spacing: 12) {
                            Image(systemName: "wand.and.stars")
                                .font(.title2)
                                .foregroundStyle(.orange)
                                .symbolEffect(.pulse.wholeSymbol, isActive: showGeneration)

                            VStack(alignment: .leading) {
                                Text("Generating custom exercise...")
                                    .font(.subheadline.weight(.medium))
                                Text("Based on: \"Help me calm down before sleep\"")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .transition(.opacity)
                    }

                    if showExercise {
                        // Generated exercise
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "moon.stars.fill")
                                    .foregroundStyle(.purple)
                                Text("Evening Wind-Down")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("AI Generated")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.1))
                                    .clipShape(Capsule())
                            }

                            Text("A gentle 5-minute breathing exercise designed to help you transition to restful sleep.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 12) {
                                Label("5 min", systemImage: "clock")
                                Label("Calming", systemImage: "leaf")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)

                // Premium note
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Premium feature")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .opacity(showExercise ? 1 : 0)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.3).delay(0.3)) {
                    showGeneration = true
                }
                withAnimation(.easeOut(duration: 0.4).delay(1.5)) {
                    showExercise = true
                }
            }
        }
    }
}

#Preview {
    ExerciseCustomStep(onComplete: {})
}
