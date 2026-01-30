//
//  LongitudinalTutorialFlow.swift
//  MindFriendApp
//
//  First-time tutorial for Longitudinal Dashboard
//  Explains long-term tracking, patterns, and yearly overview
//

import SwiftUI

/// Main container for the Longitudinal tutorial walkthrough
struct LongitudinalTutorialFlow: View {
    @EnvironmentObject var container: DependencyContainer

    let onComplete: () -> Void

    @State private var currentStep: TutorialStep = .journey

    enum TutorialStep: Int, CaseIterable, TutorialStepProtocol {
        case journey = 0
        case patterns = 1
        case year = 2
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: currentStep.progress)
                .progressViewStyle(.linear)
                .tint(.teal)
                .padding(.horizontal)
                .padding(.top, 60)

            Group {
                switch currentStep {
                case .journey:
                    LongitudinalJourneyStep(onNext: advanceStep, onSkip: skipTutorial)
                case .patterns:
                    LongitudinalPatternsStep(onNext: advanceStep, onSkip: skipTutorial)
                case .year:
                    LongitudinalYearStep(onComplete: completeTutorial)
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
    LongitudinalTutorialFlow(onComplete: {})
        .environmentObject(DependencyContainer())
}
