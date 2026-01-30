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
            iconColor: .indigo,
            headline: "Tracking Your Trajectory",
            subheadline: "We monitor your wellbeing patterns over time.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 8) {
                // Metric cards
                metricCard(
                    icon: "calendar",
                    title: "Rolling Windows",
                    description: "7, 14, and 30-day scores show patterns over time",
                    color: .blue
                )

                metricCard(
                    icon: "arrow.up.right",
                    title: "Trend & Velocity",
                    description: "See if you're improving or worsening, and by how much",
                    color: .green
                )

                metricCard(
                    icon: "gauge.with.needle",
                    title: "Your Threshold",
                    description: "We learn YOUR personal breaking point from past patterns",
                    color: .orange
                )

                // Severity legend
                HStack(spacing: 12) {
                    severityBadge(color: .green, label: "Safe")
                    severityBadge(color: .orange, label: "Warning")
                    severityBadge(color: .red, label: "Danger")
                }
                .padding(.top, 6)
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func metricCard(icon: String, title: String, description: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())

                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func severityBadge(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    DebtTrendStep(onNext: {}, onSkip: {})
}
