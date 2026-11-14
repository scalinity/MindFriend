// InsightLabHomeCard.swift
// Home screen card for accessing Insight Lab experiments

import SwiftUI

struct InsightLabHomeCard: View {
    @EnvironmentObject private var insightLabService: InsightLabService

    var body: some View {
        NavigationLink {
            InsightLabView()
                .environmentObject(insightLabService)
        } label: {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                // Header
                HStack {
                    Label("Insight Lab", systemImage: "flask.fill")
                        .font(.headline)
                        .foregroundStyle(SupportTheme.textPrimary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                // Content based on active experiment status
                if let experiment = insightLabService.activeExperiment {
                    // Active experiment view
                    activeExperimentContent(experiment)
                } else {
                    // No experiment - invitation to start
                    noExperimentContent
                }
            }
            .supportCard()
        }
        .buttonStyle(.plain)
        .task {
            await insightLabService.fetchActiveExperiment()
        }
    }

    // MARK: - Active Experiment Content

    private func activeExperimentContent(_ experiment: InsightExperiment) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack(spacing: SupportTheme.Spacing.s) {
                // Icon
                if let actionType = experiment.actionTypeEnum {
                    Image(systemName: actionType.icon)
                        .font(.title2)
                        .foregroundStyle(SupportTheme.onHero)
                        .frame(width: 44, height: 44)
                        .background(SupportTheme.Area.insights.palette.heroGradient)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                }

                // Progress info
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(experiment.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(SupportTheme.textPrimary)

                    Text("Day \(experiment.currentDay) of 7")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                Spacer()

                // Progress indicator
                ZStack {
                    Circle()
                        .stroke(SupportTheme.separator, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: Double(experiment.completedDays) / 7)
                        .stroke(SupportTheme.Status.positive, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Text("\(experiment.completedDays)/7")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .frame(width: 44, height: 44)
            }

            // Quick check-in button if day not completed
            let todayCompleted = experiment.days.first(where: { $0.dayIndex == experiment.currentDay })?.completed ?? false
            if !todayCompleted && experiment.status == .active {
                HStack {
                    Image(systemName: "checkmark.circle")
                    Text("Check in today")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(SupportTheme.accent)
                .padding(.vertical, SupportTheme.Spacing.xs)
                .frame(maxWidth: .infinity)
                .background(SupportTheme.surface)
                .cornerRadius(SupportTheme.controlRadius)
            }
        }
    }

    // MARK: - No Experiment Content

    private var noExperimentContent: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            // Icon
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(SupportTheme.Area.insights.palette.ink)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text("Run a 7-day experiment")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textPrimary)

                Text("See how habits affect your mood")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            Spacer()

            // Start indicator
            HStack(spacing: SupportTheme.Spacing.xxs) {
                Text("Start")
                    .font(.caption)
                    .fontWeight(.medium)
                Image(systemName: "arrow.right")
                    .font(.caption2)
            }
            .foregroundStyle(SupportTheme.accent)
            .padding(.horizontal, SupportTheme.Spacing.s)
            .padding(.vertical, SupportTheme.Spacing.xxs)
            .background(SupportTheme.surface)
            .cornerRadius(SupportTheme.controlRadius)
        }
    }
}

#Preview("No Experiment") {
    InsightLabHomeCard()
        .padding(SupportTheme.Spacing.m)
}
