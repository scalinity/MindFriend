//
//  ExerciseTutorialFlow.swift
//  MindFriendApp
//
//  First-time tutorial for the Exercise Library
//  Explains the library, recommendations, and custom exercises
//

import SwiftUI

/// Main container for the Exercise tutorial walkthrough
struct ExerciseTutorialFlow: View {
    @EnvironmentObject var container: DependencyContainer

    let onComplete: () -> Void

    @State private var currentStep: TutorialStep = .library

    enum TutorialStep: Int, CaseIterable, TutorialStepProtocol {
        case library = 0
        case recommend = 1
        case custom = 2
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: currentStep.progress)
                .progressViewStyle(.linear)
                .tint(.green)
                .padding(.horizontal)
                .padding(.top, 16)

            Group {
                switch currentStep {
                case .library:
                    ExerciseLibraryStep(onNext: advanceStep, onSkip: skipTutorial)
                case .recommend:
                    ExerciseRecommendStep(onNext: advanceStep, onSkip: skipTutorial)
                case .custom:
                    ExerciseCustomStep(onComplete: completeTutorial)
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
    ExerciseTutorialFlow(onComplete: {})
        .environmentObject(DependencyContainer())
}
