//
//  InsightsRecommendStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: AI recommendations
//

import SwiftUI

/// Step 3: Show AI-powered recommendations
struct InsightsRecommendStep: View {
    let onComplete: () -> Void

    @State private var showRecommendations = false

    var body: some View {
        TutorialStepView(
            icon: "sparkles",
            iconColor: .orange,
            headline: "AI Recommendations",
            subheadline: "Get personalized suggestions based on your patterns and progress.",
            primaryLabel: "View Your Insights",
            primaryAction: onComplete
        ) {
            VStack(spacing: 8) {
                // Example recommendations
                ForEach(Array(recommendations.enumerated()), id: \.element.title) { index, rec in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: rec.icon)
                            .font(.title3)
                            .foregroundStyle(rec.color)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(rec.title)
                                .font(.subheadline.weight(.medium))
                            Text(rec.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(rec.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(showRecommendations ? 1 : 0)
                    .offset(y: showRecommendations ? 0 : 15)
                    .animation(
                        .easeOut(duration: 0.4).delay(0.3 + Double(index) * 0.15),
                        value: showRecommendations
                    )
                }

                // Note
                Text("Recommendations update weekly based on your activity")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .opacity(showRecommendations ? 1 : 0)
            }
            .padding(.horizontal, 20)
            .onAppear { showRecommendations = true }
        }
    }

    private var recommendations: [(icon: String, color: Color, title: String, description: String)] {
        [
            ("moon.stars", .purple, "Try evening exercises", "Your mood dips in the evening - calming exercises might help."),
            ("figure.walk", .green, "Movement boost", "Physical activity correlates with your best mood days."),
            ("person.2", .blue, "Social connection", "Consider reaching out to your circle more often.")
        ]
    }
}

#Preview {
    InsightsRecommendStep(onComplete: {})
}
