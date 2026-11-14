//
//  DebtRecoveryStep.swift
//  MindFriendApp
//
//  Tutorial Step 4: Explains recovery support and final CTA
//

import SwiftUI

/// Step 4: Explain recovery program and encourage getting started
struct DebtRecoveryStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onComplete: () -> Void

    @State private var showSparkle = false

    var body: some View {
        TutorialStepLayout(
            icon: "heart.circle.fill",
            iconColor: SupportTheme.Area.copingKits.palette.ink,
            headline: "We've Got Your Back",
            subheadline: "When your debt approaches danger levels, we'll help you recover.",
            primaryLabel: "Get Started",
            primaryAction: onComplete,
            skipAction: nil
        ) {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Recovery program preview card
                VStack(spacing: SupportTheme.Spacing.xs) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(SupportTheme.Celebration.gold)
                            .scaleEffect(reduceMotion ? 1 : (showSparkle ? 1.2 : 1.0))

                        Text("Recovery Program")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        Spacer()
                    }

                    Text("A personalized 7-day action plan with specific activities to rebuild your reserves.")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    // Sample recovery items
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        recoveryItem(day: "Day 1", activity: "Sleep recovery focus")
                        recoveryItem(day: "Day 2", activity: "Light exercise")
                        recoveryItem(day: "Day 3", activity: "Social connection")
                    }
                }
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))

                // Reassurance text
                Text("We'll alert you before things get critical and guide you back to balance.")
                    .font(.caption2)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
            }
            .padding(.horizontal)
            .onAppear {
                withAnimation(
                    reduceMotion
                        ? .easeInOut(duration: 0.2) : (.easeInOut(duration: 0.6).repeatForever(autoreverses: true))
                ) {
                    showSparkle = true
                }
            }
        }
    }

    @ViewBuilder
    private func recoveryItem(day: String, activity: String) -> some View {
        HStack(spacing: SupportTheme.Spacing.xs) {
            Text(day)
                .font(.caption2.bold())
                .foregroundStyle(SupportTheme.Area.voice.palette.ink)
                .fixedSize(horizontal: true, vertical: false)

            Text(activity)
                .font(.caption2)
                .foregroundStyle(SupportTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 8))
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .padding(.vertical, SupportTheme.Spacing.xxs)
    }
}

#Preview {
    DebtRecoveryStep(onComplete: {})
}
