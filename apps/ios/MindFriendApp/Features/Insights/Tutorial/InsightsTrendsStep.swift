//
//  InsightsTrendsStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: Understanding trend indicators
//

import SwiftUI

/// Step 2: Explain trend arrows and metrics
struct InsightsTrendsStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showTrends = false

    var body: some View {
        TutorialStepView(
            icon: "chart.line.uptrend.xyaxis",
            iconColor: .green,
            headline: "Understanding Trends",
            subheadline: "Trend indicators show how your metrics are changing over time.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 8) {
                // Trend explanations
                ForEach(Array(trendTypes.enumerated()), id: \.element.label) { index, trend in
                    HStack(spacing: 12) {
                        // Trend arrow
                        Image(systemName: trend.icon)
                            .font(.title3)
                            .foregroundStyle(trend.color)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(trend.label)
                                .font(.subheadline.weight(.medium))
                            Text(trend.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(showTrends ? 1 : 0)
                    .offset(x: showTrends ? 0 : 20)
                    .animation(
                        .easeOut(duration: 0.3).delay(0.3 + Double(index) * 0.15),
                        value: showTrends
                    )
                }
            }
            .padding(.horizontal, 20)
            .onAppear { showTrends = true }
        }
    }

    private var trendTypes: [(icon: String, color: Color, label: String, description: String)] {
        [
            ("arrow.up.circle.fill", .green, "Improving", "Your metric is trending upward"),
            ("arrow.right.circle.fill", .yellow, "Stable", "Holding steady - keep it up!"),
            ("arrow.down.circle.fill", .orange, "Declining", "Might need attention"),
            ("minus.circle.fill", .secondary, "Not enough data", "Check back after a few days")
        ]
    }
}

#Preview {
    InsightsTrendsStep(onNext: {}, onSkip: {})
}
