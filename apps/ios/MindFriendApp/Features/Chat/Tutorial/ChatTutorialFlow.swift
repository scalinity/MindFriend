//
//  ChatTutorialFlow.swift
//  MindFriendApp
//
//  First-time tutorial for the AI Chat feature
//  Explains the companion, voice mode, coaching, and quotas
//

import SwiftUI

/// Main container for the Chat tutorial walkthrough
struct ChatTutorialFlow: View {
    @EnvironmentObject var container: DependencyContainer

    let onComplete: () -> Void

    @State private var currentStep: TutorialStep = .intro

    enum TutorialStep: Int, CaseIterable, TutorialStepProtocol {
        case intro = 0
        case voice = 1
        case coaching = 2
        case quota = 3
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
                case .intro:
                    ChatIntroStep(onNext: advanceStep, onSkip: skipTutorial)
                case .voice:
                    ChatVoiceStep(onNext: advanceStep, onSkip: skipTutorial)
                case .coaching:
                    ChatCoachingStep(onNext: advanceStep, onSkip: skipTutorial)
                case .quota:
                    ChatQuotaStep(onComplete: completeTutorial)
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

#Preview {
    ChatTutorialFlow(onComplete: {})
        .environmentObject(DependencyContainer())
}
