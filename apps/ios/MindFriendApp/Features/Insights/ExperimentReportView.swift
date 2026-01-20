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
            VStack(alignment: .leading, spacing: 24) {
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
            .padding()
        }
    }

    // MARK: - Report Header

    private func reportHeader(_ report: ExperimentReport) -> some View {
        VStack(alignment: .center, spacing: 12) {
            if let actionType = report.actionTypeEnum {
                Image(systemName: actionType.icon)
                    .font(.system(size: 50))
                    .foregroundStyle(.white)
                    .frame(width: 100, height: 100)
                    .background(
                        report.moodImproved ? Color.green :
                        report.moodDeclined ? Color.orange :
                        Color.accentColor
                    )
                    .clipShape(Circle())
            }

            Text(report.title)
                .font(.title2)
                .fontWeight(.bold)

            Text("\(report.dateRange.start) - \(report.dateRange.end)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Status badge
            if report.moodImproved {
                Label("Positive Results", systemImage: "arrow.up.circle.fill")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Adherence Card

    private func adherenceCard(_ report: ExperimentReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Adherence", systemImage: "checkmark.circle")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(report.adherencePercentage)%")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(adherenceColor(report.adherence.rate))

                    Text("\(report.adherence.completedDays) of \(report.adherence.totalDays) days completed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Visual progress ring
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray4), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: report.adherence.rate)
                        .stroke(adherenceColor(report.adherence.rate), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 60, height: 60)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Mood Change Card

    private func moodChangeCard(_ report: ExperimentReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Mood Change", systemImage: "face.smiling")
                .font(.headline)

            HStack(alignment: .bottom, spacing: 24) {
                // Baseline
                VStack(spacing: 4) {
                    Text("Baseline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f", report.moodChange.baseline ?? 0))
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                // Arrow
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)

                // Experiment
                VStack(spacing: 4) {
                    Text("Experiment")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f", report.moodChange.experiment ?? 0))
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                Spacer()

                // Delta
                if let delta = report.moodChange.delta {
                    VStack(spacing: 4) {
                        Text("Change")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                            Text(String(format: "%.1f", abs(delta)))
                        }
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(delta >= 0.5 ? .green : delta <= -0.5 ? .red : .primary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Absolute Mood Card (No Baseline)

    private func absoluteMoodCard(_ report: ExperimentReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Mood During Experiment", systemImage: "face.smiling")
                .font(.headline)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let avgMood = report.moodChange.experiment {
                        Text(String(format: "%.1f", avgMood))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                        Text("out of 5")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No mood data")
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Label("Limited baseline data", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Energy Change Card

    private func energyChangeCard(_ report: ExperimentReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Energy Change", systemImage: "bolt.fill")
                .font(.headline)

            HStack(alignment: .bottom, spacing: 24) {
                // Baseline
                VStack(spacing: 4) {
                    Text("Baseline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f", report.energyChange.baseline ?? 0))
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)

                // Experiment
                VStack(spacing: 4) {
                    Text("Experiment")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f", report.energyChange.experiment ?? 0))
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                Spacer()

                // Delta
                if let delta = report.energyChange.delta {
                    VStack(spacing: 4) {
                        Text("Change")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            Image(systemName: delta >= 0 ? "arrow.up" : "arrow.down")
                            Text(String(format: "%.1f", abs(delta)))
                        }
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(delta >= 0.5 ? .green : delta <= -0.5 ? .red : .primary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Recommendation Card

    private func recommendationCard(_ report: ExperimentReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Recommendation", systemImage: "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(report.recommendation.text)
                .font(.body)

            if !report.recommendation.nextSteps.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next Steps:")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(report.recommendation.nextSteps, id: \.self) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(Color.accentColor)
                                .font(.caption)
                            Text(step)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Insights Card

    private func insightsCard(_ report: ExperimentReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Key Insights", systemImage: "sparkles")
                .font(.headline)

            ForEach(report.insights, id: \.self) { insight in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(insight)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Action Buttons

    private func actionButtons(_ report: ExperimentReport) -> some View {
        HStack(spacing: 16) {
            // Share button
            ShareLink(item: report.shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Start new experiment button
            Button {
                dismiss()
            } label: {
                Label("New Experiment", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.top)
    }

    // MARK: - Helpers

    private func adherenceColor(_ rate: Double) -> Color {
        if rate >= 0.8 {
            return .green
        } else if rate >= 0.5 {
            return .orange
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
