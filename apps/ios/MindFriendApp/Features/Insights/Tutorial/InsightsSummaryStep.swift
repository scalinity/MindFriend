//
//  InsightsSummaryStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: Weekly summary overview
//

import SwiftUI

/// Step 1: Introduce weekly insights concept
struct InsightsSummaryStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showMetrics = false

    var body: some View {
        TutorialStepView(
            icon: "chart.bar.fill",
            iconColor: .purple,
            headline: "Your Weekly Summary",
            subheadline: "Every Sunday, you'll receive a personalized summary of your wellbeing patterns.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 8) {
                // Example metrics
                HStack(spacing: 12) {
                    InsightMetricCard(
                        icon: "face.smiling",
                        value: "3.8",
                        label: "Avg Mood",
                        color: .green,
                        isVisible: showMetrics
                    )
                    InsightMetricCard(
                        icon: "flame",
                        value: "5",
                        label: "Day Streak",
                        color: .orange,
                        isVisible: showMetrics
                    )
                    InsightMetricCard(
                        icon: "star",
                        value: "6",
                        label: "Quests",
                        color: .yellow,
                        isVisible: showMetrics
                    )
                }
                .padding(.horizontal, 20)

                // What's included
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your summary includes:")
                        .font(.subheadline.weight(.medium))

                    ForEach(summaryItems, id: \.self) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.purple)
                            Text(item)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .opacity(showMetrics ? 1 : 0)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
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
    let icon: String
    let value: String
    let label: String
    let color: Color
    let isVisible: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.title2.bold())

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .scaleEffect(isVisible ? 1 : 0.8)
        .opacity(isVisible ? 1 : 0)
    }
}

#Preview {
    InsightsSummaryStep(onNext: {}, onSkip: {})
}
