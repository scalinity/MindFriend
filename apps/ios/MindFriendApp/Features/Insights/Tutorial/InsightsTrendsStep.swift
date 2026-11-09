//
//  InsightsTrendsStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: Understanding trend indicators
//

import SwiftUI

/// Step 2: Explain trend arrows and metrics
struct InsightsTrendsStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showTrends = false

    var body: some View {
        TutorialStepView(
            icon: "chart.line.uptrend.xyaxis",
            iconColor: SupportTheme.accent,
            headline: "Understanding Trends",
            subheadline: "Trend indicators show how your metrics are changing over time.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                // Trend explanations
                ForEach(Array(trendTypes.enumerated()), id: \.element.label) { index, trend in
                    HStack(spacing: SupportTheme.Spacing.s) {
                        // Trend arrow
                        Image(systemName: trend.icon)
                            .font(.title3)
                            .foregroundStyle(trend.color)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text(trend.label)
                                .font(.subheadline.weight(.medium))
                            Text(trend.description)
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(SupportTheme.Spacing.s)
                    .background(SupportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    .opacity(showTrends ? 1 : 0)
                    .offset(x: reduceMotion ? 0 : (showTrends ? 0 : 20))
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) :
                        .easeOut(duration: 0.3).delay(0.3 + Double(index) * 0.15),
                        value: showTrends
                    )
                }
            }
            .padding(.horizontal, SupportTheme.Spacing.m)
            .onAppear { showTrends = true }
        }
    }

    private var trendTypes: [(icon: String, color: Color, label: String, description: String)] {
        [
            ("arrow.up.circle.fill", SupportTheme.accent, "Improving", "Your metric is trending upward"),
            ("arrow.right.circle.fill", SupportTheme.accent, "Stable", "Holding steady - keep it up!"),
            ("arrow.down.circle.fill", SupportTheme.accent, "Declining", "Might need attention"),
            ("minus.circle.fill", SupportTheme.textSecondary, "Not enough data", "Check back after a few days")
        ]
    }
}

#Preview {
    InsightsTrendsStep(onNext: {}, onSkip: {})
}
