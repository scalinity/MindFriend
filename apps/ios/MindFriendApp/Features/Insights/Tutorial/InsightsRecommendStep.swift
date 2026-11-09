//
//  InsightsRecommendStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: AI recommendations
//

import SwiftUI

/// Step 3: Show AI-powered recommendations
struct InsightsRecommendStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onComplete: () -> Void

    @State private var showRecommendations = false

    var body: some View {
        TutorialStepView(
            icon: "sparkles",
            iconColor: SupportTheme.accent,
            headline: "AI Recommendations",
            subheadline: "Get personalized suggestions based on your patterns and progress.",
            primaryLabel: "View Your Insights",
            primaryAction: onComplete
        ) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                // Example recommendations
                ForEach(Array(recommendations.enumerated()), id: \.element.title) { index, rec in
                    HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                        Image(systemName: rec.icon)
                            .font(.title3)
                            .foregroundStyle(rec.color)
                            .frame(minWidth: 28)

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text(rec.title)
                                .font(.subheadline.weight(.medium))
                            Text(rec.description)
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(SupportTheme.Spacing.s)
                    .background(rec.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    .opacity(showRecommendations ? 1 : 0)
                    .offset(y: reduceMotion ? 0 : (showRecommendations ? 0 : 15))
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) :
                        .easeOut(duration: 0.4).delay(0.3 + Double(index) * 0.15),
                        value: showRecommendations
                    )
                }

                // Note
                Text("Recommendations update weekly based on your activity")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SupportTheme.Spacing.m)
                    .opacity(showRecommendations ? 1 : 0)
            }
            .padding(.horizontal, SupportTheme.Spacing.m)
            .onAppear { showRecommendations = true }
        }
    }

    private var recommendations: [(icon: String, color: Color, title: String, description: String)] {
        [
            ("moon.stars", SupportTheme.accent, "Try evening exercises", "Your mood dips in the evening - calming exercises might help."),
            ("figure.walk", SupportTheme.accent, "Movement boost", "Physical activity correlates with your best mood days."),
            ("person.2", SupportTheme.accent, "Social connection", "Consider reaching out to your circle more often.")
        ]
    }
}

#Preview {
    InsightsRecommendStep(onComplete: {})
}
