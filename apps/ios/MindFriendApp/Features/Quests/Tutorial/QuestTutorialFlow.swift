//
//  QuestTutorialFlow.swift
//  MindFriendApp
//
//  First-time tutorial for the Quest feature
//  Explains quest selection, completion, progress, and room for pauses
//

import SwiftUI

/// Main container for the Quest tutorial walkthrough
struct QuestTutorialFlow: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onComplete: () -> Void

    @State private var currentStep: TutorialStep = .concept

    enum TutorialStep: Int, CaseIterable, TutorialStepProtocol {
        case concept = 0
        case choice = 1
        case streak = 2
        case shield = 3
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            ProgressView(value: currentStep.progress)
                .progressViewStyle(.linear)
                .tint(SupportTheme.Celebration.gold)
                .padding(.horizontal, SupportTheme.Spacing.m)
                .padding(.top, SupportTheme.Spacing.xl)

            // Step content
            Group {
                switch currentStep {
                case .concept:
                    QuestConceptStep(onNext: advanceStep, onSkip: skipTutorial)
                case .choice:
                    QuestChoiceStep(onNext: advanceStep, onSkip: skipTutorial)
                case .streak:
                    QuestStreakStep(onNext: advanceStep, onSkip: skipTutorial)
                case .shield:
                    QuestShieldStep(onComplete: completeTutorial)
                }
            }
            .id(currentStep)
            .transition(.opacity)
        }
        .background(SupportTheme.canvas)
        .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.3), value: currentStep)
    }

    private func advanceStep() {
        if let nextStep = TutorialStep(rawValue: currentStep.rawValue + 1) {
            withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.3)) {
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

#Preview {
    QuestTutorialFlow(onComplete: {})
        .environmentObject(DependencyContainer())
}
