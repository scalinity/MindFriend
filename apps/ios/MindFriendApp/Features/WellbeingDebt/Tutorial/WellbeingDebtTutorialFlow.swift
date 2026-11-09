//
//  WellbeingDebtTutorialFlow.swift
//  MindFriendApp
//
//  N006: Wellbeing Debt Calculator - First-time Tutorial
//  Shows a 4-step walkthrough explaining the feature to new users
//

import SwiftUI

/// Main container for the Wellbeing Debt tutorial walkthrough
struct WellbeingDebtTutorialFlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var container: DependencyContainer

    let onComplete: () -> Void

    @State private var currentStep: TutorialStep = .concept

    enum TutorialStep: Int, CaseIterable {
        case concept = 0
        case transactions = 1
        case trend = 2
        case recovery = 3

        var progress: Double {
            Double(self.rawValue + 1) / Double(TutorialStep.allCases.count)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            ProgressView(value: currentStep.progress)
                .progressViewStyle(.linear)
                .tint(SupportTheme.accent)
                .padding(.horizontal)
                .padding(.top, SupportTheme.Spacing.xl)

            // Step content
            Group {
                switch currentStep {
                case .concept:
                    DebtConceptStep(onNext: advanceStep, onSkip: skipTutorial)
                case .transactions:
                    DebtTransactionsStep(onNext: advanceStep, onSkip: skipTutorial)
                case .trend:
                    DebtTrendStep(onNext: advanceStep, onSkip: skipTutorial)
                case .recovery:
                    DebtRecoveryStep(onComplete: completeTutorial)
                }
            }
            .transition(.opacity)
        }
        .background(SupportTheme.canvas)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : (.easeInOut(duration: 0.3)), value: currentStep)
    }

    private func advanceStep() {
        if let nextStep = TutorialStep(rawValue: currentStep.rawValue + 1) {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .default) {
                currentStep = nextStep
            }
        }
    }

    private func skipTutorial() {
        onComplete()
    }

    private func completeTutorial() {
        onComplete()
    }
}

// MARK: - Reusable Tutorial Components

/// Standard layout for tutorial steps
struct TutorialStepLayout<Content: View>: View {
    let icon: String
    let iconColor: Color
    let headline: String
    let subheadline: String
    let content: Content
    let primaryAction: () -> Void
    let primaryLabel: String
    let skipAction: (() -> Void)?

    init(
        icon: String,
        iconColor: Color = SupportTheme.accent,
        headline: String,
        subheadline: String,
        primaryLabel: String = "Next",
        primaryAction: @escaping () -> Void,
        skipAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.headline = headline
        self.subheadline = subheadline
        self.primaryLabel = primaryLabel
        self.primaryAction = primaryAction
        self.skipAction = skipAction
        self.content = content()
    }

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Spacer()

            // Icon
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(iconColor)
                .symbolRenderingMode(.hierarchical)

            // Headlines
            VStack(spacing: SupportTheme.Spacing.xs) {
                Text(headline)
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                    .multilineTextAlignment(.center)

                Text(subheadline)
                    .font(.body)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Custom content
            content
                .padding(.vertical)

            Spacer()

            // Actions
            VStack(spacing: SupportTheme.Spacing.s) {
                Button(action: primaryAction) {
                    Text(primaryLabel)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(SupportTheme.accent)
                        .foregroundStyle(SupportTheme.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                }

                if let skipAction = skipAction {
                    Button(action: skipAction) {
                        Text("Skip tutorial")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, SupportTheme.Spacing.l)
            .padding(.bottom, SupportTheme.Spacing.xl)
        }
        .padding(.horizontal)
    }
}

#Preview {
    WellbeingDebtTutorialFlow(onComplete: {})
        .environmentObject(DependencyContainer())
}
