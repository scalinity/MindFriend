//
//  DebtRecoveryStep.swift
//  MindFriendApp
//
//  Tutorial Step 4: Explains recovery support and final CTA
//

import SwiftUI

/// Step 4: Explain recovery program and encourage getting started
struct DebtRecoveryStep: View {
    let onComplete: () -> Void

    @State private var showSparkle = false

    var body: some View {
        TutorialStepLayout(
            icon: "heart.circle.fill",
            iconColor: .pink,
            headline: "We've Got Your Back",
            subheadline: "When your debt approaches danger levels, we'll help you recover.",
            primaryLabel: "Get Started",
            primaryAction: onComplete,
            skipAction: nil
        ) {
            VStack(spacing: 20) {
                // Recovery program preview card
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.yellow)
                            .scaleEffect(showSparkle ? 1.2 : 1.0)

                        Text("Recovery Program")
                            .font(.headline)

                        Spacer()
                    }

                    Text("A personalized 7-day action plan with specific activities to rebuild your reserves.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)

                    // Sample recovery items
                    VStack(alignment: .leading, spacing: 8) {
                        recoveryItem(day: "Day 1", activity: "Sleep recovery focus")
                        recoveryItem(day: "Day 2", activity: "Light exercise")
                        recoveryItem(day: "Day 3", activity: "Social connection")
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

                // Reassurance text
                Text("We'll alert you before things get critical and guide you back to balance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.horizontal)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    showSparkle = true
                }
            }
        }
    }

    @ViewBuilder
    private func recoveryItem(day: String, activity: String) -> some View {
        HStack(spacing: 8) {
            Text(day)
                .font(.caption.bold())
                .foregroundStyle(.blue)
                .frame(width: 44, alignment: .leading)

            Text(activity)
                .font(.caption)
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DebtRecoveryStep(onComplete: {})
}
