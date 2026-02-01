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
            VStack(spacing: 16) {
                // Recovery program preview card
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.yellow)
                            .scaleEffect(showSparkle ? 1.2 : 1.0)

                        Text("Recovery Program")
                            .font(.headline)

                        Spacer()
                    }

                    Text("A personalized 7-day action plan with specific activities to rebuild your reserves.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    // Sample recovery items
                    VStack(alignment: .leading, spacing: 8) {
                        recoveryItem(day: "Day 1", activity: "Sleep recovery focus")
                        recoveryItem(day: "Day 2", activity: "Light exercise")
                        recoveryItem(day: "Day 3", activity: "Social connection")
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

                // Reassurance text
                Text("We'll alert you before things get critical and guide you back to balance.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
        HStack(spacing: 6) {
            Text(day)
                .font(.caption2.bold())
                .foregroundStyle(.blue)
                .fixedSize(horizontal: true, vertical: false)

            Text(activity)
                .font(.caption2)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    DebtRecoveryStep(onComplete: {})
}
