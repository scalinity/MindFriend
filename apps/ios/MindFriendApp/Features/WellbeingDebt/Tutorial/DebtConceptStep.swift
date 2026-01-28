//
//  DebtConceptStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: Introduces the "bank account" metaphor for wellbeing debt
//

import SwiftUI

/// Step 1: Explain the core debt concept using a relatable metaphor
struct DebtConceptStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showDeposit = false
    @State private var showWithdrawal = false

    var body: some View {
        TutorialStepLayout(
            icon: "scalemass.fill",
            iconColor: .blue,
            headline: "Your Wellbeing Bank Account",
            subheadline: "Think of your energy like a bank account with deposits and withdrawals.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            // Animated balance illustration
            VStack(spacing: 20) {
                HStack(spacing: 40) {
                    // Deposit indicator
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.green)
                            .scaleEffect(showDeposit ? 1.0 : 0.5)
                            .opacity(showDeposit ? 1.0 : 0.3)

                        Text("Deposits")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Withdrawal indicator
                    VStack(spacing: 8) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)
                            .scaleEffect(showWithdrawal ? 1.0 : 0.5)
                            .opacity(showWithdrawal ? 1.0 : 0.3)

                        Text("Withdrawals")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Explanation text
                Text("When withdrawals exceed deposits, you accumulate **debt** that can lead to burnout.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                    showDeposit = true
                }
                withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
                    showWithdrawal = true
                }
            }
        }
    }
}

#Preview {
    DebtConceptStep(onNext: {}, onSkip: {})
}
