//
//  MoodTutorialFlow.swift
//  MindFriendApp
//
//  First-time tutorial for Mood Logging
//  Explains why tracking mood matters and how to do it
//

import SwiftUI

/// Main container for the Mood tutorial walkthrough
struct MoodTutorialFlow: View {
    @EnvironmentObject var container: DependencyContainer

    let onComplete: () -> Void

    @State private var currentStep: TutorialStep = .why

    enum TutorialStep: Int, CaseIterable, TutorialStepProtocol {
        case why = 0
        case how = 1
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: currentStep.progress)
                .progressViewStyle(.linear)
                .tint(.pink)
                .padding(.horizontal)
                .padding(.top, 60)

            Group {
                switch currentStep {
                case .why:
                    MoodWhyStep(onNext: advanceStep, onSkip: skipTutorial)
                case .how:
                    MoodHowStep(onComplete: completeTutorial)
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
    MoodTutorialFlow(onComplete: {})
        .environmentObject(DependencyContainer())
}
