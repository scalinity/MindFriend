//
//  PathwayCompletionView.swift
//  MindFriendApp
//
//  Created by Claude on 2026-01-25.
//

import SwiftUI

struct PathwayCompletionView: View {
    let userPathway: UserPathway
    @Environment(\.dismiss) var dismiss
    @State private var showConfetti = false

    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            // Confetti overlay
            if showConfetti {
                ConfettiView(colors: [.blue, .green, .yellow, .orange, .red])
                    .ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 60)

                    // Success icon
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 100))
                        .foregroundColor(.green)
                        .shadow(color: Color.green.opacity(0.3), radius: 20, x: 0, y: 10)

                    // Title
                    VStack(spacing: 12) {
                        Text("Journey Complete!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text("You completed the \(userPathway.pathway?.name ?? "pathway")")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    // Summary stats
                    VStack(spacing: 16) {
                        StatRow(label: "Total Days", value: "\(userPathway.currentDay)")
                        StatRow(label: "Phases Completed", value: "4")
                        StatRow(label: "Started", value: userPathway.startedAt.formatted(date: .abbreviated, time: .omitted))
                        if let completedAt = userPathway.completedAt {
                            StatRow(label: "Completed", value: completedAt.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal)

                    // Motivational message
                    VStack(spacing: 12) {
                        Text("You've Grown")
                            .font(.headline)

                        Text("This transition has shaped you into someone stronger and wiser. The courage you've shown throughout this journey is remarkable.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal)

                    // Actions
                    VStack(spacing: 12) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .accessibilityLabel("Done")
                        .accessibilityHint("Return to home screen")

                        Button {
                            // Navigate to PathwaySelectionView
                            // This will be implemented when integrating with navigation
                        } label: {
                            Text("Start Another Pathway")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.secondarySystemGroupedBackground))
                                .foregroundColor(.blue)
                                .cornerRadius(12)
                        }
                        .accessibilityLabel("Start another pathway")
                        .accessibilityHint("Begin a new transition journey")
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 60)
                }
            }
        }
        .onAppear {
            // Trigger confetti animation
            withAnimation {
                showConfetti = true
            }

            // Hide confetti after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
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
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
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
