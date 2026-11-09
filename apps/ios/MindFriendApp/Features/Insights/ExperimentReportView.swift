// ExperimentReportView.swift
// Displays experiment outcome report with metrics and recommendations

import SwiftUI

struct ExperimentReportView: View {
    @EnvironmentObject private var insightLabService: InsightLabService
    let experimentId: UUID

    @State private var report: ExperimentReport?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingShareSheet = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Generating Report...")
            } else if let report = report {
                reportContent(report)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            }
        }
        .supportScreen()
        .navigationTitle("Experiment Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .task {
            await loadReport()
        }
    }

    // MARK: - Report Content

    private func reportContent(_ report: ExperimentReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                // Header
                reportHeader(report)

                // Adherence card
                adherenceCard(report)

                // Mood change card
                if report.moodChange.hasBaseline {
                    moodChangeCard(report)
                } else {
                    absoluteMoodCard(report)
                }

                // Energy change card
                if report.energyChange.hasBaseline, report.energyChange.experiment != nil {
                    energyChangeCard(report)
                }

                // Recommendation
                recommendationCard(report)

                // Insights
                insightsCard(report)

                // Action buttons
                actionButtons(report)
            }
            .padding(SupportTheme.Spacing.m)
        }
    }

    // MARK: - Report Header

    private func reportHeader(_ report: ExperimentReport) -> some View {
        VStack(alignment: .center, spacing: SupportTheme.Spacing.s) {
            if let actionType = report.actionTypeEnum {
                Image(systemName: actionType.icon)
                    .font(.system(.largeTitle))
                    .foregroundStyle(SupportTheme.textPrimary)
                    .frame(width: 100, height: 100)
                    .background(
                        report.moodImproved ? SupportTheme.accent :
                        report.moodDeclined ? SupportTheme.accent :
                        SupportTheme.accent
                    )
                    .clipShape(Circle())
            }

            Text(report.title)
                .font(.title2)
                .fontWeight(.bold)

            Text("\(report.dateRange.start) - \(report.dateRange.end)")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)

            // Status badge
            if report.moodImproved {
                Label("Positive Results", systemImage: "arrow.up.circle.fill")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .padding(.horizontal, SupportTheme.Spacing.s)
                    .padding(.vertical, SupportTheme.Spacing.xxs)
                    .background(SupportTheme.accent)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(SupportTheme.Spacing.m)
    }

    // MARK: - Adherence Card

    private func adherenceCard(_ report: ExperimentReport) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            Label("Adherence", systemImage: "checkmark.circle")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text("\(report.adherencePercentage)%")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(adherenceColor(report.adherence.rate))

                    Text("\(report.adherence.completedDays) of \(report.adherence.totalDays) days completed")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                Spacer()

                // Visual progress ring
                ZStack {
                    Circle()
                        .stroke(SupportTheme.separator, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: report.adherence.rate)
                        .stroke(adherenceColor(report.adherence.rate), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 60, height: 60)
            }
        }
        .supportCard()
    }

    // MARK: - Mood Change Card

    private func moodChangeCard(_ report: ExperimentReport) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            Label("Mood Change", systemImage: "face.smiling")
                .font(.headline)

            HStack(alignment: .bottom, spacing: SupportTheme.Spacing.l) {
                // Baseline
                VStack(spacing: SupportTheme.Spacing.xxs) {
                    Text("Baseline")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                    Text(String(format: "%.1f", report.moodChange.baseline ?? 0))
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                // Arrow
                Image(systemName: "arrow.right")
                    .foregroundStyle(SupportTheme.textSecondary)

                // Experiment
                VStack(spacing: SupportTheme.Spacing.xxs) {
                    Text("Experiment")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                    Text(String(format: "%.1f", report.moodChange.experiment ?? 0))
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                Spacer()

                // Delta
                if let delta = report.moodChange.delta {
                    VStack(spacing: SupportTheme.Spacing.xxs) {
                        Text("Change")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                        HStack(spacing: SupportTheme.Spacing.xxs) {
                            Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                            Text(String(format: "%.1f", abs(delta)))
                        }
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(delta >= 0.5 ? .green : delta <= -0.5 ? .red : SupportTheme.textPrimary)
                    }
                }
            }
        }
        .supportCard()
    }

    // MARK: - Absolute Mood Card (No Baseline)

    private func absoluteMoodCard(_ report: ExperimentReport) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            Label("Mood During Experiment", systemImage: "face.smiling")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    if let avgMood = report.moodChange.experiment {
                        Text(String(format: "%.1f", avgMood))
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        Text("out of 5")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                    } else {
                        Text("No mood data")
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }

                Spacer()

                Label("Limited baseline data", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .supportCard()
    }

    // MARK: - Energy Change Card

    private func energyChangeCard(_ report: ExperimentReport) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            Label("Energy Change", systemImage: "bolt.fill")
                .font(.headline)

            HStack(alignment: .bottom, spacing: SupportTheme.Spacing.l) {
                // Baseline
                VStack(spacing: SupportTheme.Spacing.xxs) {
                    Text("Baseline")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                    Text(String(format: "%.1f", report.energyChange.baseline ?? 0))
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(SupportTheme.textSecondary)

                // Experiment
                VStack(spacing: SupportTheme.Spacing.xxs) {
                    Text("Experiment")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                    Text(String(format: "%.1f", report.energyChange.experiment ?? 0))
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                Spacer()

                // Delta
                if let delta = report.energyChange.delta {
                    VStack(spacing: SupportTheme.Spacing.xxs) {
                        Text("Change")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                        HStack(spacing: SupportTheme.Spacing.xxs) {
                            Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                            Text(String(format: "%.1f", abs(delta)))
                        }
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(delta >= 0.5 ? .green : delta <= -0.5 ? .red : SupportTheme.textPrimary)
                    }
                }
            }
        }
        .supportCard()
    }

    // MARK: - Recommendation Card

    private func recommendationCard(_ report: ExperimentReport) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            Label("Recommendation", systemImage: "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(SupportTheme.accent)

            Text(report.recommendation.text)
                .font(.body)

            if !report.recommendation.nextSteps.isEmpty {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Next Steps:")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(report.recommendation.nextSteps, id: \.self) { step in
                        HStack(alignment: .top, spacing: SupportTheme.Spacing.xs) {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(SupportTheme.accent)
                                .font(.caption)
                            Text(step)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .supportCard()
    }

    // MARK: - Insights Card

    private func insightsCard(_ report: ExperimentReport) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Label("Key Insights", systemImage: "sparkles")
                .font(.headline)

            ForEach(report.insights, id: \.self) { insight in
                HStack(alignment: .top, spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SupportTheme.accent)
                        .font(.caption)
                    Text(insight)
                        .font(.subheadline)
                }
            }
        }
        .supportCard()
    }

    // MARK: - Action Buttons

    private func actionButtons(_ report: ExperimentReport) -> some View {
        HStack(spacing: SupportTheme.Spacing.m) {
            // Share button
            ShareLink(item: report.shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .supportCard()
            }

            // Start new experiment button
            Button {
                dismiss()
            } label: {
                Label("New Experiment", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.supportPrimary)
        }
        .padding(.top, SupportTheme.Spacing.m)
    }

    // MARK: - Helpers

    private func adherenceColor(_ rate: Double) -> Color {
        if rate >= 0.8 {
            return SupportTheme.accent
        } else if rate >= 0.5 {
            return SupportTheme.accent
        } else {
            return .red
        }
    }

    // MARK: - Load Report

    private func loadReport() async {
        isLoading = true
        errorMessage = nil

        do {
            report = try await insightLabService.generateReport(experimentId: experimentId)
        } catch {
            errorMessage = "Failed to generate report: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

#Preview {
    NavigationStack {
        ExperimentReportView(experimentId: UUID())
    }
}
