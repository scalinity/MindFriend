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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                .tint(SupportTheme.accent)
                .padding(.horizontal, SupportTheme.Spacing.m)
                .padding(.top, SupportTheme.Spacing.xl)

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
