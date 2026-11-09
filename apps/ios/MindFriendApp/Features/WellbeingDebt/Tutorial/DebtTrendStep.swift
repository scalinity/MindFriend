//
//  DebtTrendStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: Explains the metrics - rolling windows, trend, threshold
//

import SwiftUI

/// Step 3: Explain the dashboard metrics
struct DebtTrendStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        TutorialStepLayout(
            icon: "chart.line.uptrend.xyaxis",
            iconColor: SupportTheme.accent,
            headline: "Tracking Your Trajectory",
            subheadline: "We monitor your wellbeing patterns over time.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                // Metric cards
                metricCard(
                    icon: "calendar",
                    title: "Rolling Windows",
                    description: "7, 14, and 30-day scores show patterns over time",
                    color: SupportTheme.accent
                )

                metricCard(
                    icon: "arrow.up.right",
                    title: "Trend & Velocity",
                    description: "See if you're improving or worsening, and by how much",
                    color: SupportTheme.accent
                )

                metricCard(
                    icon: "gauge.with.needle",
                    title: "Your Threshold",
                    description: "We learn YOUR personal breaking point from past patterns",
                    color: SupportTheme.accent
                )

                // Severity legend
                HStack(spacing: SupportTheme.Spacing.s) {
                    severityBadge(color: SupportTheme.accent, label: "Safe")
                    severityBadge(color: SupportTheme.accent, label: "Warning")
                    severityBadge(color: .red, label: "Danger")
                }
                .padding(.top, SupportTheme.Spacing.xs)
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func metricCard(icon: String, title: String, description: String, color: Color) -> some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(title)
                    .font(.caption.bold())

                Text(description)
                    .font(.caption2)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(SupportTheme.Spacing.s)
        .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }

    @ViewBuilder
    private func severityBadge(color: Color, label: String) -> some View {
        HStack(spacing: SupportTheme.Spacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(label)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }
}

#Preview {
    DebtTrendStep(onNext: {}, onSkip: {})
}
