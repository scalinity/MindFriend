//
//  MoodWhyStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: Why track mood?
//

import SwiftUI

/// Step 1: Explain the benefits of mood tracking
struct MoodWhyStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showBenefits = false

    private let benefits: [(icon: String, color: Color, title: String, description: String)] = [
        ("chart.line.uptrend.xyaxis", .green, "Spot Patterns", "See what affects your mood over time"),
        ("lightbulb.fill", .yellow, "Get Insights", "AI analyzes your data for personalized tips"),
        ("bell.fill", .orange, "Early Warnings", "Know when you might need extra support"),
        ("sparkles", .purple, "Better Recommendations", "More accurate quest and exercise suggestions")
    ]

    var body: some View {
        TutorialStepView(
            icon: "face.smiling.fill",
            iconColor: .pink,
            headline: "Why Track Mood?",
            subheadline: "Your mood data powers personalized insights and predictions.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 12) {
                ForEach(Array(benefits.enumerated()), id: \.element.title) { index, benefit in
                    HStack(spacing: 12) {
                        Image(systemName: benefit.icon)
                            .font(.title3)
                            .foregroundStyle(benefit.color)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(benefit.title)
                                .font(.subheadline.weight(.medium))
                            Text(benefit.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(showBenefits ? 1 : 0)
                    .offset(x: showBenefits ? 0 : 20)
                    .animation(
                        .easeOut(duration: 0.3).delay(0.3 + Double(index) * 0.1),
                        value: showBenefits
                    )
                }
            }
            .padding(.horizontal, 24)
            .onAppear { showBenefits = true }
        }
    }
}

#Preview {
    MoodWhyStep(onNext: {}, onSkip: {})
}
