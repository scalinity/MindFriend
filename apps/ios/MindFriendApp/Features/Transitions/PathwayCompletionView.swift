//
//  PathwayCompletionView.swift
//  MindFriendApp
//
//  Created by Claude on 2026-01-25.
//

import SwiftUI

struct PathwayCompletionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let userPathway: UserPathway
    @Environment(\.dismiss) var dismiss
    @State private var showConfetti = false

    var body: some View {
        ZStack {
            // Background
            SupportTheme.canvas
                .ignoresSafeArea()

            // Confetti overlay
            if showConfetti {
                CelebrationParticles()
                    .ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: SupportTheme.Spacing.xl) {
                    Spacer(minLength: SupportTheme.Spacing.xl)

                    // Success icon
                    CelebrationEmblem(.symbol("checkmark.seal.fill"))
                        .celebrationReveal()

                    // Title
                    VStack(spacing: SupportTheme.Spacing.s) {
                        Text("Journey complete")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text("You completed the \(userPathway.pathway?.name ?? "pathway")")
                            .font(.title3)
                            .foregroundColor(SupportTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    // Summary stats
                    VStack(spacing: SupportTheme.Spacing.m) {
                        StatRow(label: "Total Days", value: "\(userPathway.currentDay)")
                        StatRow(label: "Phases Completed", value: "4")
                        StatRow(label: "Started", value: userPathway.startedAt.formatted(date: .abbreviated, time: .omitted))
                        if let completedAt = userPathway.completedAt {
                            StatRow(label: "Completed", value: completedAt.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    .supportCard()
                    .padding(.horizontal, SupportTheme.Spacing.m)

                    // Motivational message
                    VStack(spacing: SupportTheme.Spacing.s) {
                        Text("You've Grown")
                            .font(.headline)

                        Text("Your pathway is complete. You can revisit what helped and choose what to carry forward.")
                            .font(.body)
                            .foregroundColor(SupportTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .supportCard()
                    .padding(.horizontal, SupportTheme.Spacing.m)

                    // Actions
                    VStack(spacing: SupportTheme.Spacing.s) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.supportPrimary)
                        .accessibilityLabel("Done")
                        .accessibilityHint("Return to home screen")

                        Button {
                            // Navigate to PathwaySelectionView
                            // This will be implemented when integrating with navigation
                        } label: {
                            Text("Start Another Pathway")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(SupportTheme.Spacing.m)
                                .background(SupportTheme.surface)
                                .foregroundColor(SupportTheme.accent)
                                .cornerRadius(SupportTheme.controlRadius)
                        }
                        .accessibilityLabel("Start another pathway")
                        .accessibilityHint("Begin a new transition journey")
                    }
                    .padding(.horizontal, SupportTheme.Spacing.m)

                    Spacer(minLength: SupportTheme.Spacing.xl)
                }
            }
        }
        .onAppear {
            // Trigger confetti animation
            withAnimation(.easeInOut(duration: 0.2)) {
                showConfetti = true
            }

            // Hide confetti after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showConfetti = false
                }
            }
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(SupportTheme.textSecondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(SupportTheme.textPrimary)
        }
    }
}

// ConfettiView and ConfettiParticle are defined in Celebration/CelebrationView.swift

#Preview {
    PathwayCompletionView(
        userPathway: UserPathway(
            id: UUID(),
            userId: UUID(),
            pathwayId: UUID(),
            startedAt: Date().addingTimeInterval(-56 * 24 * 60 * 60),
            currentPhase: 4,
            currentDay: 56,
            currentPhaseDay: 14,
            status: .completed,
            pausedAt: nil,
            completedAt: Date(),
            personalization: PathwayPersonalization(),
            createdAt: Date(),
            updatedAt: Date(),
            pathway: TransitionPathway(
                id: UUID(),
                key: "job_loss",
                name: "Career Transition",
                description: "Navigate job loss or career change",
                category: .career,
                durationWeeks: 8,
                phases: [],
                isPremium: true,
                iconName: "briefcase.fill",
                color: "#5C6BC0",
                crisisResources: nil,
                createdAt: Date()
            ),
            progress: nil
        )
    )
}
