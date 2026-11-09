//
//  InsightsSummaryStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: Weekly summary overview
//

import SwiftUI

/// Step 1: Introduce weekly insights concept
struct InsightsSummaryStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showMetrics = false

    var body: some View {
        TutorialStepView(
            icon: "chart.bar.fill",
            iconColor: SupportTheme.accent,
            headline: "Your Weekly Summary",
            subheadline: "Every Sunday, you'll receive a personalized summary of your wellbeing patterns.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                // Example metrics
                HStack(spacing: SupportTheme.Spacing.s) {
                    InsightMetricCard(
                        icon: "face.smiling",
                        value: "3.8",
                        label: "Avg Mood",
                        color: SupportTheme.accent,
                        isVisible: showMetrics
                    )
                    InsightMetricCard(
                        icon: "leaf",
                        value: "5",
                        label: "Practices",
                        color: SupportTheme.accent,
                        isVisible: showMetrics
                    )
                    InsightMetricCard(
                        icon: "star",
                        value: "6",
                        label: "Quests",
                        color: SupportTheme.accent,
                        isVisible: showMetrics
                    )
                }
                .padding(.horizontal, SupportTheme.Spacing.m)

                // What's included
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Your summary includes:")
                        .font(.subheadline.weight(.medium))
                .accessibilityAddTraits(.isHeader)

                    ForEach(summaryItems, id: \.self) { item in
                        HStack(spacing: SupportTheme.Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.accent)
                            Text(item)
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                .padding(.horizontal, SupportTheme.Spacing.m)
                .opacity(showMetrics ? 1 : 0)
            }
            .onAppear {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.5).delay(0.3)) {
                    showMetrics = true
                }
            }
        }
    }

    private let summaryItems = [
        "Mood patterns and changes",
        "Quest completion stats",
        "Exercise engagement",
        "AI-generated observations"
    ]
}

private struct InsightMetricCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let icon: String
    let value: String
    let label: String
    let color: Color
    let isVisible: Bool

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.title2.bold())

            Text(label)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SupportTheme.Spacing.s)
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
        .scaleEffect(reduceMotion ? 1 : (isVisible ? 1 : 0.8))
        .opacity(isVisible ? 1 : 0)
    }
}

#Preview {
    InsightsSummaryStep(onNext: {}, onSkip: {})
}
