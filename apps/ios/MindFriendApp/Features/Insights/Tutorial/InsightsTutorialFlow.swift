//
//  InsightsTutorialFlow.swift
//  MindFriendApp
//
//  First-time tutorial for Weekly Insights
//  Explains summaries, trends, and AI recommendations
//

import SwiftUI

/// Main container for the Insights tutorial walkthrough
struct InsightsTutorialFlow: View {
    @EnvironmentObject var container: DependencyContainer

    let onComplete: () -> Void

    @State private var currentStep: TutorialStep = .summary

    enum TutorialStep: Int, CaseIterable, TutorialStepProtocol {
        case summary = 0
        case trends = 1
        case recommend = 2
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: currentStep.progress)
                .progressViewStyle(.linear)
                .tint(.purple)
                .padding(.horizontal)
                .padding(.top, 16)

            Group {
                switch currentStep {
                case .summary:
                    InsightsSummaryStep(onNext: advanceStep, onSkip: skipTutorial)
                case .trends:
                    InsightsTrendsStep(onNext: advanceStep, onSkip: skipTutorial)
                case .recommend:
                    InsightsRecommendStep(onComplete: completeTutorial)
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
    InsightsTutorialFlow(onComplete: {})
        .environmentObject(DependencyContainer())
}
