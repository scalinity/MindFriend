//
//  QuestJourneysTutorialFlow.swift
//  MindFriendApp
//
//  Quest Journeys - First-time Tutorial
//  Shows a 4-step walkthrough explaining the feature to new users
//

import SwiftUI

/// Main container for the Quest Journeys tutorial walkthrough
struct QuestJourneysTutorialFlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onComplete: () -> Void

    @State private var currentStep: TutorialStep = .concept

    enum TutorialStep: Int, CaseIterable {
        case concept = 0
        case progress = 1
        case milestones = 2
        case getStarted = 3

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
                .padding(.horizontal, SupportTheme.Spacing.m)
                .padding(.top, SupportTheme.Spacing.xl)

            // Step content
            Group {
                switch currentStep {
                case .concept:
                    JourneyConceptStep(onNext: advanceStep, onSkip: skipTutorial)
                case .progress:
                    JourneyProgressStep(onNext: advanceStep, onSkip: skipTutorial)
                case .milestones:
                    JourneyMilestonesStep(onNext: advanceStep, onSkip: skipTutorial)
                case .getStarted:
                    JourneyGetStartedStep(onComplete: completeTutorial)
                }
            }
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .background(SupportTheme.canvas)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.3), value: currentStep)
    }

    private func advanceStep() {
        if let nextStep = TutorialStep(rawValue: currentStep.rawValue + 1) {
            withAnimation(.easeInOut(duration: 0.2)) {
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
struct JourneyTutorialStepLayout<Content: View>: View {
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
        ScrollView {
        VStack(spacing: SupportTheme.Spacing.l) {

            // Icon
            Image(systemName: icon)
                .font(.system(.largeTitle))
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
                    .padding(.horizontal, SupportTheme.Spacing.m)
            }

            // Custom content
            content
                .padding(.vertical, SupportTheme.Spacing.m)

            // Actions
            VStack(spacing: SupportTheme.Spacing.s) {
                Button(primaryLabel, action: primaryAction)
                    .buttonStyle(.supportPrimary)

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
        .padding(.horizontal, SupportTheme.Spacing.m)
        }
        .supportScreen()
    }
}

#Preview {
    QuestJourneysTutorialFlow(onComplete: {})
}
