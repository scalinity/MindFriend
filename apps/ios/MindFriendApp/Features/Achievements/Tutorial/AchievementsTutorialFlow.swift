//
//  AchievementsTutorialFlow.swift
//  MindFriendApp
//
//  First-time tutorial for Achievements
//  Explains XP, badges, and skill trees
//

import SwiftUI

/// Main container for the Achievements tutorial walkthrough
struct AchievementsTutorialFlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var container: DependencyContainer

    let onComplete: () -> Void

    @State private var currentStep: TutorialStep = .xp

    enum TutorialStep: Int, CaseIterable, TutorialStepProtocol {
        case xp = 0
        case badges = 1
        case skills = 2
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: currentStep.progress)
                .progressViewStyle(.linear)
                .tint(SupportTheme.Celebration.gold)
                .padding(.horizontal)
                .padding(.top, SupportTheme.Spacing.xl)

            Group {
                switch currentStep {
                case .xp:
                    AchievementsXPStep(onNext: advanceStep, onSkip: skipTutorial)
                case .badges:
                    AchievementsBadgesStep(onNext: advanceStep, onSkip: skipTutorial)
                case .skills:
                    AchievementsSkillsStep(onComplete: completeTutorial)
                }
            }
            .transition(.opacity)
        }
        .background(SupportTheme.canvas)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : (.easeInOut(duration: 0.3)), value: currentStep)
    }

    private func advanceStep() {
        if let nextStep = TutorialStep(rawValue: currentStep.rawValue + 1) {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .default) { currentStep = nextStep }
        }
    }

    private func skipTutorial() { onComplete() }
    private func completeTutorial() { onComplete() }
}

#Preview {
    AchievementsTutorialFlow(onComplete: {})
        .environmentObject(DependencyContainer())
}
