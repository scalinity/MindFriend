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
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Label("Insight Lab", systemImage: "flask.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .task {
            await insightLabService.fetchActiveExperiment()
        }
    }

    // MARK: - Active Experiment Content

    private func activeExperimentContent(_ experiment: InsightExperiment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Icon
                if let actionType = experiment.actionTypeEnum {
                    Image(systemName: actionType.icon)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Progress info
                VStack(alignment: .leading, spacing: 4) {
                    Text(experiment.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text("Day \(experiment.currentDay) of 7")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Progress indicator
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray4), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: Double(experiment.completedDays) / 7)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
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
                .foregroundStyle(.accentColor)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - No Experiment Content

    private var noExperimentContent: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("Run a 7-day experiment")
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Text("See how habits affect your mood")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Start indicator
            HStack(spacing: 4) {
                Text("Start")
                    .font(.caption)
                    .fontWeight(.medium)
                Image(systemName: "arrow.right")
                    .font(.caption2)
            }
            .foregroundStyle(.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

#Preview("No Experiment") {
    InsightLabHomeCard()
        .padding()
}
