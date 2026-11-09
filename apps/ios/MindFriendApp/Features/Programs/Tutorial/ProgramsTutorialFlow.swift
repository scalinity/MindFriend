//
//  ProgramsTutorialFlow.swift
//  MindFriendApp
//
//  First-time tutorial for the Programs feature
//  Explains multi-day wellness journeys, enrollment, progress, and certificates
//

import SwiftUI

/// Main container for the Programs tutorial walkthrough
struct ProgramsTutorialFlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var container: DependencyContainer

    let onComplete: () -> Void

    @State private var currentStep: TutorialStep = .concept

    enum TutorialStep: Int, CaseIterable, TutorialStepProtocol {
        case concept = 0
        case enroll = 1
        case progress = 2
        case certificate = 3
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
                case .concept:
                    ProgramsConceptStep(onNext: advanceStep, onSkip: skipTutorial)
                case .enroll:
                    ProgramsEnrollStep(onNext: advanceStep, onSkip: skipTutorial)
                case .progress:
                    ProgramsProgressStep(onNext: advanceStep, onSkip: skipTutorial)
                case .certificate:
                    ProgramsCertificateStep(onComplete: completeTutorial)
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
            withAnimation(.easeInOut(duration: 0.2)) {
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
    ProgramsTutorialFlow(onComplete: {})
        .environmentObject(DependencyContainer())
}
