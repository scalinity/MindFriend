//
//  TrajectoryVisualizationView.swift
//  MindFriendApp
//
//  Real-time Emotional Trajectory Visualization
//

import SwiftUI
import Charts

struct TrajectoryVisualizationView: View {
    let trajectory: [TrajectoryPoint]
    let isLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            // Header
            HStack {
                Text("Emotional Trajectory")
                    .font(.headline)

                Spacer()

                if isLive {
                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("LIVE")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(.horizontal, SupportTheme.Spacing.m)

            if trajectory.isEmpty {
                emptyStateView
            } else {
                chartView
                legendView
            }
        }
        .padding(.vertical, SupportTheme.Spacing.m)
        .background(SupportTheme.canvas)
        .cornerRadius(SupportTheme.cardRadius)
        .shadow(color: SupportTheme.canvas.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(.largeTitle))
                .foregroundColor(SupportTheme.textSecondary)

            Text("No trajectory data yet")
                .font(.subheadline)
                .foregroundColor(SupportTheme.textSecondary)

            Text("Data will appear as you progress through the exercise")
                .font(.caption)
                .foregroundColor(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Chart

    private var chartView: some View {
        Chart {
            ForEach(Array(trajectory.enumerated()), id: \.offset) { index, point in
                LineMark(
                    x: .value("Time", point.secondsFromStart),
                    y: .value("Score", point.compositeScore)
                )
                .foregroundStyle(lineGradient)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                AreaMark(
                    x: .value("Time", point.secondsFromStart),
                    y: .value("Score", point.compositeScore)
                )
                .foregroundStyle(areaGradient)
                .opacity(0.3)

                // Highlight breakthrough points
                if let _ = detectBreakthrough(at: index) {
                    PointMark(
                        x: .value("Time", point.secondsFromStart),
                        y: .value("Score", point.compositeScore)
                    )
                    .symbol {
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .foregroundColor(SupportTheme.accent)
                    }
                    .annotation(position: .top) {
                        Text("Breakthrough!")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(SupportTheme.accent)
                            .padding(SupportTheme.Spacing.xxs)
                            .background(SupportTheme.surface)
                            .cornerRadius(SupportTheme.controlRadius)
                    }
                }
            }
        }
        .chartYScale(domain: -1...1)
        .chartXAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let seconds = value.as(Int.self) {
                        Text(formatDuration(seconds))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let score = value.as(Double.self) {
                        Text(String(format: "%.1f", score))
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 200)
        .padding(SupportTheme.Spacing.m)
    }

    private var lineGradient: Color {
        SupportTheme.accent
    }

    private var areaGradient: Color {
        SupportTheme.accent.opacity(0.15)
    }

    // MARK: - Legend

    private var legendView: some View {
        HStack(spacing: SupportTheme.Spacing.l) {
            legendItem(color: SupportTheme.accent, label: "Positive (+1.0)")
            legendItem(color: SupportTheme.textSecondary, label: "Neutral (0.0)")
            legendItem(color: .red, label: "Negative (-1.0)")
        }
        .font(.caption)
        .padding(.horizontal, SupportTheme.Spacing.m)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .foregroundColor(SupportTheme.textSecondary)
        }
    }

    // MARK: - Helpers

    private func detectBreakthrough(at index: Int) -> Bool? {
        guard index > 0, index < trajectory.count else { return nil }

        let current = trajectory[index]
        let previous = trajectory[index - 1]

        let change = current.compositeScore - previous.compositeScore
        let duration = current.secondsFromStart - previous.secondsFromStart

        return change > 0.4 && duration <= 60
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60

        if minutes > 0 {
            return "\(minutes)m\(remainingSeconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        // Live trajectory
        TrajectoryVisualizationView(
            trajectory: [
                TrajectoryPoint(
                    id: UUID(),
                    timestamp: Date(),
                    secondsFromStart: 0,
                    nervousSystemState: "fight_flight",
                    emotionClassification: EmotionClassification(primary: "anxious", valence: -0.4, arousal: 0.8),
                    hrvReading: 40,
                    compositeScore: -0.3
                ),
                TrajectoryPoint(
                    id: UUID(),
                    timestamp: Date().addingTimeInterval(30),
                    secondsFromStart: 30,
                    nervousSystemState: "transition",
                    emotionClassification: EmotionClassification(primary: "neutral", valence: 0.0, arousal: 0.5),
                    hrvReading: 55,
                    compositeScore: 0.1
                ),
                TrajectoryPoint(
                    id: UUID(),
                    timestamp: Date().addingTimeInterval(60),
                    secondsFromStart: 60,
                    nervousSystemState: "rest",
                    emotionClassification: EmotionClassification(primary: "calm", valence: 0.6, arousal: 0.3),
                    hrvReading: 70,
                    compositeScore: 0.6
                )
            ],
            isLive: true
        )

        // Empty state
        TrajectoryVisualizationView(
            trajectory: [],
            isLive: false
        )
    }
    .padding(SupportTheme.Spacing.m)
}
