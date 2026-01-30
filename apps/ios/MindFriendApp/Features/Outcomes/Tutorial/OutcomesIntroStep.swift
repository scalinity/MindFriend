//
//  OutcomesIntroStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: Introduction to Wellness Tracking
//

import SwiftUI

/// Step 1: Introduce evidence-based wellness tracking
struct OutcomesIntroStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showContent = false

    var body: some View {
        TutorialStepView(
            icon: "heart.text.square.fill",
            iconColor: .cyan,
            headline: "Wellness Tracking",
            subheadline: "Monitor your mental health journey with clinically-validated assessments.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 16) {
                // Feature highlights
                VStack(spacing: 8) {
                    WellnessFeatureRow(
                        icon: "checkmark.seal.fill",
                        color: .green,
                        title: "Evidence-Based",
                        description: "Uses validated tools like PHQ-9 and GAD-7"
                    )

                    WellnessFeatureRow(
                        icon: "chart.line.uptrend.xyaxis",
                        color: .blue,
                        title: "Track Progress",
                        description: "See your mental health trends over time"
                    )

                    WellnessFeatureRow(
                        icon: "target",
                        color: .orange,
                        title: "Set Goals",
                        description: "Work toward meaningful outcomes"
                    )
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)

                // Reassurance
                Text("Your assessment data is private and helps personalize your experience.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
                    .opacity(showContent ? 1 : 0)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                    showContent = true
                }
            }
        }
    }
}

// MARK: - Feature Row

private struct WellnessFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}

#Preview {
    OutcomesIntroStep(onNext: {}, onSkip: {})
}
