//
//  OutcomesAssessmentsStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: Explain assessments
//

import SwiftUI

/// Step 2: Show how standardized assessments work
struct OutcomesAssessmentsStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showAssessments = false
    @State private var animatedIndex = -1

    private let assessments: [(code: String, name: String, description: String, color: Color)] = [
        ("PHQ-9", "Depression", "9 questions about mood and energy", .blue),
        ("GAD-7", "Anxiety", "7 questions about worry and tension", .purple),
        ("PSS", "Stress", "10 questions about stress levels", .orange)
    ]

    var body: some View {
        TutorialStepView(
            icon: "list.clipboard.fill",
            iconColor: .blue,
            headline: "Standardized Assessments",
            subheadline: "Complete brief, validated questionnaires to track specific aspects of your mental health.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 8) {
                // Assessment cards
                ForEach(Array(assessments.enumerated()), id: \.element.code) { index, assessment in
                    HStack(spacing: 12) {
                        // Code badge
                        Text(assessment.code)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(assessment.color)
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(assessment.name)
                                .font(.subheadline.weight(.medium))
                            Text(assessment.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(animatedIndex >= index ? 1 : 0)
                    .offset(x: animatedIndex >= index ? 0 : 30)
                }
                .padding(.horizontal, 20)

                // Frequency note
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(.cyan)
                    Text("We'll remind you when assessments are due")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
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
                withAnimation(.easeOut(duration: 0.3)) {
                    animatedIndex = index
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { showAssessments = true }
        }
    }
}

#Preview {
    OutcomesAssessmentsStep(onNext: {}, onSkip: {})
}
