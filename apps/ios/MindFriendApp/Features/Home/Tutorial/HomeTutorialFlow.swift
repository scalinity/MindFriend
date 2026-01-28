//
//  HomeTutorialFlow.swift
//  MindFriendApp
//
//  First-time tutorial for the Home screen
//  Explains quests, streaks, and how to navigate the app
//

import SwiftUI

/// Main container for the Home screen tutorial walkthrough
struct HomeTutorialFlow: View {
    @EnvironmentObject var container: DependencyContainer
    @EnvironmentObject var appState: AppState

    let onComplete: () -> Void

    @State private var currentStep: TutorialStep = .welcome

    enum TutorialStep: Int, CaseIterable, TutorialStepProtocol {
        case welcome = 0
        case quest = 1
        case streak = 2
        case explore = 3
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            ProgressView(value: currentStep.progress)
                .progressViewStyle(.linear)
                .tint(.indigo)
                .padding(.horizontal)
                .padding(.top, 16)

            // Step content
            Group {
                switch currentStep {
                case .welcome:
                    HomeWelcomeStep(onNext: advanceStep, onSkip: skipTutorial)
                case .quest:
                    HomeQuestStep(onNext: advanceStep, onSkip: skipTutorial)
                case .streak:
                    HomeStreakStep(onNext: advanceStep, onSkip: skipTutorial)
                case .explore:
                    HomeExploreStep(
                        onComplete: completeTutorial,
                        onNavigate: { destination in
                            navigateToFeature(destination)
                        }
                    )
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

    private func navigateToFeature(_ destination: ExploreFeatureDestination) {
        appState.selectedTab = destination.targetTab
    }
}

#Preview {
    HomeTutorialFlow(onComplete: {})
        .environmentObject(DependencyContainer())
        .environmentObject(AppState())
}
