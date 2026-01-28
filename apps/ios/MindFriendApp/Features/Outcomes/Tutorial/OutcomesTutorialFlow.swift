//
//  OutcomesTutorialFlow.swift
//  MindFriendApp
//
//  First-time tutorial for Wellness Tracking / Outcomes
//  Explains evidence-based assessments, progress tracking, and goals
//

import SwiftUI

/// Main container for the Wellness Tracking tutorial walkthrough
struct OutcomesTutorialFlow: View {
    @EnvironmentObject var container: DependencyContainer

    let onComplete: () -> Void

    @State private var currentStep: TutorialStep = .intro

    enum TutorialStep: Int, CaseIterable, TutorialStepProtocol {
        case intro = 0
        case assessments = 1
        case progress = 2
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: currentStep.progress)
                .progressViewStyle(.linear)
                .tint(.cyan)
                .padding(.horizontal)
                .padding(.top, 16)

            Group {
                switch currentStep {
                case .intro:
                    OutcomesIntroStep(onNext: advanceStep, onSkip: skipTutorial)
                case .assessments:
                    OutcomesAssessmentsStep(onNext: advanceStep, onSkip: skipTutorial)
                case .progress:
                    OutcomesProgressStep(onComplete: completeTutorial)
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
            withAnimation { currentStep = nextStep }
        }
    }

    private func skipTutorial() { onComplete() }
    private func completeTutorial() { onComplete() }
}

#Preview {
    OutcomesTutorialFlow(onComplete: {})
        .environmentObject(DependencyContainer())
}
