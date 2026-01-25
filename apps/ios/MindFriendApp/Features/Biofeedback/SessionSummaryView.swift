// SessionSummaryView.swift
// MindFriendApp
// Post-exercise biofeedback session summary

import SwiftUI

struct SessionSummaryView: View {
    let summary: BiofeedbackSummary
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Heart Rate Card
                    heartRateCard

                    // HRV Card (if available)
                    if summary.startingHRV != nil || summary.endingHRV != nil {
                        hrvCard
                    }

                    // Session Stats
                    sessionStatsCard

                    // Effectiveness Score
                    if let score = summary.effectivenessScore {
                        effectivenessCard(score: score)
                    }

                    Spacer(minLength: 20)

                    // Done Button
                    Button {
                        onDismiss()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .navigationTitle("Session Summary")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Great Session!")
                .font(.title2)
                .fontWeight(.semibold)

            if let change = summary.heartRateChange, change < 0 {
                Text("Your heart rate decreased by \(Int(abs(change))) BPM")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Heart Rate Card

    private var heartRateCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("Heart Rate")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 40) {
                // Starting HR
                VStack(spacing: 4) {
                    Text("Start")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let start = summary.startingHeartRate {
                        Text("\(Int(start))")
                            .font(.title)
                            .fontWeight(.semibold)
                    } else {
                        Text("--")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                    Text("BPM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Arrow indicator
                Image(systemName: summary.heartRateChange ?? 0 < 0 ? "arrow.down" : "arrow.right")
                    .font(.title2)
                    .foregroundStyle(summary.heartRateChange ?? 0 < 0 ? .green : .secondary)

                // Ending HR
                VStack(spacing: 4) {
                    Text("End")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let end = summary.endingHeartRate {
                        Text("\(Int(end))")
                            .font(.title)
                            .fontWeight(.semibold)
                    } else {
                        Text("--")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                    Text("BPM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Min/Max/Avg Row
            if let lowest = summary.lowestHeartRate,
               let highest = summary.highestHeartRate,
               let average = summary.averageHeartRate {
                Divider()

                HStack {
                    statItem(label: "Lowest", value: "\(Int(lowest))", unit: "BPM")
                    Spacer()
                    statItem(label: "Average", value: "\(Int(average))", unit: "BPM")
                    Spacer()
                    statItem(label: "Highest", value: "\(Int(highest))", unit: "BPM")
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - HRV Card

    private var hrvCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.purple)
                Text("Heart Rate Variability")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 40) {
                // Starting HRV
                VStack(spacing: 4) {
                    Text("Start")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let start = summary.startingHRV {
                        Text("\(Int(start))")
                            .font(.title)
                            .fontWeight(.semibold)
                    } else {
                        Text("--")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                    Text("ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Arrow indicator
                let improvement = summary.hrvImprovementPercent ?? 0
                Image(systemName: improvement > 0 ? "arrow.up" : "arrow.right")
                    .font(.title2)
                    .foregroundStyle(improvement > 0 ? .green : .secondary)

                // Ending HRV
                VStack(spacing: 4) {
                    Text("End")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let end = summary.endingHRV {
                        Text("\(Int(end))")
                            .font(.title)
                            .fontWeight(.semibold)
                    } else {
                        Text("--")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                    Text("ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let improvement = summary.hrvImprovementPercent, improvement != 0 {
                HStack {
                    Image(systemName: improvement > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(improvement > 0 ? .green : .orange)
                    Text("\(improvement > 0 ? "+" : "")\(Int(improvement))% HRV change")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Session Stats Card

    private var sessionStatsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.blue)
                Text("Session Stats")
                    .font(.headline)
                Spacer()
            }

            HStack {
                statItem(
                    label: "Adaptations",
                    value: "\(summary.totalAdaptations)",
                    unit: "changes"
                )

                Spacer()

                if let timeToRelax = summary.timeToRelaxationSeconds {
                    statItem(
                        label: "Time to Relax",
                        value: formatSeconds(timeToRelax),
                        unit: ""
                    )
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Effectiveness Card

    private func effectivenessCard(score: Double) -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                Text("Effectiveness")
                    .font(.headline)
                Spacer()
            }

            VStack(spacing: 8) {
                // Score gauge
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 12)
                        .frame(width: 100, height: 100)

                    Circle()
                        .trim(from: 0, to: score)
                        .stroke(
                            scoreColor(score),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(score * 100))%")
                        .font(.title2)
                        .fontWeight(.bold)
                }

                Text(effectivenessMessage(score))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func statItem(label: String, value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 0.8 { return .green }
        if score >= 0.5 { return .yellow }
        return .orange
    }

    private func effectivenessMessage(_ score: Double) -> String {
        if score >= 0.8 {
            return "Excellent! Your body responded very well to this session."
        }
        if score >= 0.5 {
            return "Good progress! Regular practice will improve effectiveness."
        }
        return "Keep practicing! Consistency is key to better results."
    }
}

// MARK: - Preview

#Preview {
    SessionSummaryView(
        summary: BiofeedbackSummary(
            id: UUID(),
            sessionId: UUID(),
            startingHeartRate: 85,
            endingHeartRate: 68,
            lowestHeartRate: 65,
            highestHeartRate: 88,
            averageHeartRate: 72,
            startingHRV: 45,
            endingHRV: 58,
            hrvImprovementPercent: 28.9,
            timeToRelaxationSeconds: 180,
            totalAdaptations: 3,
            effectivenessScore: 0.75,
            createdAt: Date()
        )
    ) {
        print("Dismissed")
    }
}
