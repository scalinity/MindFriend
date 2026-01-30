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
                .tint(.blue)
                .padding(.horizontal)
                .padding(.top, 60)

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
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .background(Color(.systemBackground))
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }

    private func advanceStep() {
        if let nextStep = TutorialStep(rawValue: currentStep.rawValue + 1) {
            withAnimation {
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
        iconColor: Color = .blue,
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
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(iconColor)
                .symbolRenderingMode(.hierarchical)

            // Headlines
            VStack(spacing: 8) {
                Text(headline)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(subheadline)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Custom content
            content
                .padding(.vertical)

            Spacer()

            // Actions
            VStack(spacing: 12) {
                Button(action: primaryAction) {
                    Text(primaryLabel)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if let skipAction = skipAction {
                    Button(action: skipAction) {
                        Text("Skip tutorial")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .padding(.horizontal)
    }
}

#Preview {
    QuestJourneysTutorialFlow(onComplete: {})
}
