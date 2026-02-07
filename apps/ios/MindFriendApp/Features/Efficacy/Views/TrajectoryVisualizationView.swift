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
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Emotional Trajectory")
                    .font(.headline)

                Spacer()

                if isLive {
                    HStack(spacing: 4) {
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
            .padding(.horizontal)

            if trajectory.isEmpty {
                emptyStateView
            } else {
                chartView
                legendView
            }
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No trajectory data yet")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Data will appear as you progress through the exercise")
                .font(.caption)
                .foregroundColor(.secondary)
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
                            .foregroundColor(.purple)
                    }
                    .annotation(position: .top) {
                        Text("Breakthrough!")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.purple)
                            .padding(4)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(4)
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
        .padding()
    }

    private var lineGradient: LinearGradient {
        LinearGradient(
            colors: [.blue, .purple],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [.blue.opacity(0.5), .purple.opacity(0.5)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Legend

    private var legendView: some View {
        HStack(spacing: 24) {
            legendItem(color: .green, label: "Positive (+1.0)")
            legendItem(color: .gray, label: "Neutral (0.0)")
            legendItem(color: .red, label: "Negative (-1.0)")
        }
        .font(.caption)
        .padding(.horizontal)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .foregroundColor(.secondary)
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
    .padding()
}
