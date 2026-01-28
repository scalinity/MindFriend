//
//  CirclesTutorialFlow.swift
//  MindFriendApp
//
//  First-time tutorial for Circles
//  Explains accountability groups, check-ins, and rituals
//

import SwiftUI

/// Main container for the Circles tutorial walkthrough
struct CirclesTutorialFlow: View {
    @EnvironmentObject var container: DependencyContainer

    let onComplete: () -> Void

    @State private var currentStep: TutorialStep = .concept

    enum TutorialStep: Int, CaseIterable, TutorialStepProtocol {
        case concept = 0
        case checkin = 1
        case rituals = 2
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: currentStep.progress)
                .progressViewStyle(.linear)
                .tint(.pink)
                .padding(.horizontal)
                .padding(.top, 16)

            Group {
                switch currentStep {
                case .concept:
                    CirclesConceptStep(onNext: advanceStep, onSkip: skipTutorial)
                case .checkin:
                    CirclesCheckInStep(onNext: advanceStep, onSkip: skipTutorial)
                case .rituals:
                    CirclesRitualsStep(onComplete: completeTutorial)
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
    CirclesTutorialFlow(onComplete: {})
        .environmentObject(DependencyContainer())
}
