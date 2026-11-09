//
//  DebtConceptStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: Introduces the "bank account" metaphor for wellbeing debt
//

import SwiftUI

/// Step 1: Explain the core debt concept using a relatable metaphor
struct DebtConceptStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showDeposit = false
    @State private var showWithdrawal = false

    var body: some View {
        TutorialStepLayout(
            icon: "scalemass.fill",
            iconColor: SupportTheme.accent,
            headline: "Your Wellbeing Bank Account",
            subheadline: "Think of your energy like a bank account with deposits and withdrawals.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            // Animated balance illustration
            VStack(spacing: SupportTheme.Spacing.m) {
                HStack(spacing: SupportTheme.Spacing.xl) {
                    // Deposit indicator
                    VStack(spacing: SupportTheme.Spacing.xs) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(SupportTheme.accent)
                            .scaleEffect(reduceMotion ? 1 : (showDeposit ? 1.0 : 0.5))
                            .opacity(showDeposit ? 1.0 : 0.3)

                        Text("Deposits")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    // Withdrawal indicator
                    VStack(spacing: SupportTheme.Spacing.xs) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(SupportTheme.accent)
                            .scaleEffect(reduceMotion ? 1 : (showWithdrawal ? 1.0 : 0.5))
                            .opacity(showWithdrawal ? 1.0 : 0.3)

                        Text("Withdrawals")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }

                // Explanation text
                Text("When withdrawals exceed deposits, you accumulate **debt** that can lead to burnout.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SupportTheme.Spacing.m)
            }
            .onAppear {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : (.easeOut(duration: 0.5).delay(0.3))) {
                    showDeposit = true
                }
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : (.easeOut(duration: 0.5).delay(0.6))) {
                    showWithdrawal = true
                }
            }
        }
    }
}

#Preview {
    DebtConceptStep(onNext: {}, onSkip: {})
}
