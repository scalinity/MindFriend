//
//  OutcomesAssessmentsStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: Explain assessments
//

import SwiftUI

/// Step 2: Show how standardized assessments work
struct OutcomesAssessmentsStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showAssessments = false
    @State private var animatedIndex = -1

    private let assessments: [(code: String, name: String, description: String, color: Color)] = [
        ("PHQ-9", "Depression", "9 questions about mood and energy", SupportTheme.accent),
        ("GAD-7", "Anxiety", "7 questions about worry and tension", SupportTheme.accent),
        ("PSS", "Stress", "10 questions about stress levels", SupportTheme.accent)
    ]

    var body: some View {
        TutorialStepView(
            icon: "list.clipboard.fill",
            iconColor: SupportTheme.accent,
            headline: "Standardized Assessments",
            subheadline: "Complete brief, validated questionnaires to track specific aspects of your mental health.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                // Assessment cards
                ForEach(Array(assessments.enumerated()), id: \.element.code) { index, assessment in
                    HStack(spacing: SupportTheme.Spacing.s) {
                        // Code badge
                        Text(assessment.code)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SupportTheme.textPrimary)
                            .padding(.horizontal, SupportTheme.Spacing.xs)
                            .padding(.vertical, SupportTheme.Spacing.xxs)
                            .background(assessment.color)
                            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text(assessment.name)
                                .font(.subheadline.weight(.medium))
                            Text(assessment.description)
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .padding(SupportTheme.Spacing.s)
                    .background(SupportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    .opacity(animatedIndex >= index ? 1 : 0)
                    .offset(x: animatedIndex >= index ? 0 : 30)
                }
                .padding(.horizontal, SupportTheme.Spacing.m)

                // Frequency note
                HStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(SupportTheme.accent)
                    Text("We'll remind you when assessments are due")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, SupportTheme.Spacing.xxs)
                .opacity(showAssessments ? 1 : 0)
            }
            .onAppear {
                animateAssessments()
            }
        }
    }

    private func animateAssessments() {
        for index in 0..<assessments.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(index) * 0.15) {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.3)) {
                    animatedIndex = index
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.2)) { showAssessments = true }
        }
    }
}

#Preview {
    OutcomesAssessmentsStep(onNext: {}, onSkip: {})
}
