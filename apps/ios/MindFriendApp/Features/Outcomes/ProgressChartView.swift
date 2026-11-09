import SwiftUI
import Charts

/// Progress visualization showing assessment trends over time with goal targets
@MainActor
struct ProgressChartView: View {
    let assessmentType: AssessmentType
    let responses: [AssessmentResponse]
    let goal: OutcomeGoal?

    var chartData: [ChartDataPoint] {
        responses
            .filter { $0.availableScore != nil }
            .sorted { $0.completedAt < $1.completedAt }
            .enumerated()
            .map { index, response in
                ChartDataPoint(
                    date: response.completedAt,
                    score: Double(response.totalScore),
                    sequenceNumber: Double(index)
                )
            }
    }

    var minScore: Double {
        let responses = chartData.map { $0.score }
        return responses.min() ?? 0
    }

    var maxScore: Double {
        let responses = chartData.map { $0.score }
        let goalMax = goal.map { Double($0.targetScore) } ?? 100
        return max(responses.max() ?? 100, goalMax)
    }

    var averageScore: Double {
        guard !chartData.isEmpty else { return 0 }
        return chartData.map { $0.score }.reduce(0, +) / Double(chartData.count)
    }

    var currentScore: Int? {
        responses.sorted { $0.completedAt > $1.completedAt }.first?.availableScore
    }

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            // Chart header
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                Text("\(assessmentType.rawValue) Progress")
                    .font(.system(.body, design: .default).weight(.semibold))
                    .foregroundColor(SupportTheme.accent)

                Text("\(responses.count) assessments tracked")
                    .font(.system(.caption, design: .default).weight(.regular))
                    .foregroundColor(SupportTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SupportTheme.Spacing.m)
            .padding(.top, SupportTheme.Spacing.m)

            // Stats pills
            HStack(spacing: SupportTheme.Spacing.s) {
                StatPill(
                    label: "Current",
                    value: currentScore.map(String.init) ?? "—",
                    color: SupportTheme.accent
                )

                StatPill(
                    label: "Average",
                    value: chartData.isEmpty ? "—" : "\(Int(averageScore))",
                    color: SupportTheme.accent
                )

                if let goal = goal {
                    StatPill(
                        label: "Target",
                        value: "\(goal.targetScore)",
                        color: SupportTheme.accent
                    )
                }
            }
            .padding(.horizontal, SupportTheme.Spacing.m)

            // Line chart
            if !chartData.isEmpty {
                Chart {
                    // Trend line
                    ForEach(chartData, id: \.date) { point in
                        LineMark(
                            x: .value("Assessment", point.sequenceNumber),
                            y: .value("Score", point.score)
                        )
                        .foregroundStyle(SupportTheme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        PointMark(
                            x: .value("Assessment", point.sequenceNumber),
                            y: .value("Score", point.score)
                        )
                        .foregroundStyle(SupportTheme.accent)
                        .symbolSize(80)
                    }

                    // Goal line (if set)
                    if let goal = goal {
                        RuleMark(y: .value("Goal", Double(goal.targetScore)))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                            .foregroundStyle(SupportTheme.accent.opacity(0.5))
                    }

                    // Average line
                    RuleMark(y: .value("Average", averageScore))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                        .foregroundStyle(SupportTheme.textSecondary.opacity(0.3))
                }
                .chartYScale(domain: 0...(Int(maxScore) + 10))
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisValueLabel()
                            .font(.system(.caption2, design: .default).weight(.regular))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel()
                            .font(.system(.caption2, design: .default).weight(.regular))
                    }
                }
                .frame(height: 240)
                .padding(SupportTheme.Spacing.m)
                .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                .padding(.horizontal, SupportTheme.Spacing.m)

                // Legend
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    ChartLegendItem(
                        color: SupportTheme.accent,
                        label: "Your Score"
                    )

                    ChartLegendItem(
                        color: SupportTheme.textSecondary.opacity(0.3),
                        label: "Average"
                    )

                    if goal != nil {
                        ChartLegendItem(
                            color: SupportTheme.accent.opacity(0.5),
                            label: "Your Goal"
                        )
                    }
                }
                .padding(SupportTheme.Spacing.s)
                .background(
                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .fill(SupportTheme.accent)
                )
                .padding(.horizontal, SupportTheme.Spacing.m)
            } else {
                VStack(spacing: SupportTheme.Spacing.s) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(.largeTitle))
                        .foregroundColor(SupportTheme.textSecondary.opacity(0.3))

                    Text("No data yet")
                        .font(.system(.subheadline, design: .default).weight(.semibold))
                        .foregroundColor(SupportTheme.accent)

                    Text("Complete more assessments to see your progress")
                        .font(.system(.caption, design: .default).weight(.regular))
                        .foregroundColor(SupportTheme.textSecondary)
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .fill(SupportTheme.accent)
                )
                .padding(.horizontal, SupportTheme.Spacing.m)
            }

            // Insights section
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                Text("Insights")
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .foregroundColor(SupportTheme.accent)

                InsightCard(
                    icon: assessmentType.higherScoresAreBetter ? "arrow.trend.up" : "arrow.trend.down",
                    title: "Trend Direction",
                    description: getTrendDescription(),
                    color: getTrendColor()
                )

                if let goal = goal {
                    let remaining = goal.remainingPoints(currentScore: currentScore, type: assessmentType)

                    InsightCard(
                        icon: "target",
                        title: "Goal Progress",
                        description: goalProgressDescription(goal),
                        color: remaining == 0 ? SupportTheme.accent : .gray
                    )
                }
            }
            .padding(SupportTheme.Spacing.s)
            .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
            .padding(.horizontal, SupportTheme.Spacing.m)
            .padding(.bottom, SupportTheme.Spacing.m)
        }
    }

    private func goalProgressDescription(_ goal: OutcomeGoal) -> String {
        if goal.requiresScoreReview(for: assessmentType) {
            return "This target needs review after scoring corrections. Set a new goal from a current assessment."
        }
        guard let remaining = goal.remainingPoints(currentScore: currentScore, type: assessmentType) else {
            return "A current assessment is needed to show progress."
        }
        if remaining == 0 { return "Goal achieved!" }
        return "\(assessmentType.higherScoresAreBetter ? "Increase" : "Reduce") score by \(remaining) points to reach your target"
    }

    private func getTrendDescription() -> String {
        guard chartData.count >= 2 else { return "Insufficient data" }

        let recent = chartData.suffix(2)
        let previousScore = recent.first?.score ?? 0
        let currentScore = recent.last?.score ?? 0
        let delta = assessmentType.improvement(from: Int(previousScore), to: Int(currentScore))

        if delta > 0 {
            return "Improving by \(delta) points"
        } else if delta < 0 {
            return "Worsening by \(-delta) points"
        } else {
            return "Score stable"
        }
    }

    private func getTrendColor() -> Color {
        guard chartData.count >= 2 else { return SupportTheme.textSecondary }

        let recent = chartData.suffix(2)
        let previousScore = recent.first?.score ?? 0
        let currentScore = recent.last?.score ?? 0
        let delta = assessmentType.improvement(from: Int(previousScore), to: Int(currentScore))

        if delta > 0 {
            return SupportTheme.accent
        } else if delta < 0 {
            return SupportTheme.accent
        } else {
            return SupportTheme.textSecondary
        }
    }
}

// MARK: - Supporting Views

struct ChartDataPoint {
    let date: Date
    let score: Double
    let sequenceNumber: Double
}

struct StatPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xxs) {
            Text(value)
                .font(.system(.body, design: .default).weight(.bold))
                .foregroundColor(color)

            Text(label)
                .font(.system(.caption2, design: .default).weight(.semibold))
                .foregroundColor(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(SupportTheme.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                .fill(color.opacity(0.05))
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

struct ChartLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xs) {
            Rectangle()
                .fill(color)
                .frame(width: 8, height: 8)
                .cornerRadius(SupportTheme.controlRadius)

            Text(label)
                .font(.system(.caption, design: .default).weight(.regular))
                .foregroundColor(SupportTheme.textSecondary)

            Spacer()
        }
    }
}

struct InsightCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: icon)
                .font(.system(.subheadline).weight(.semibold))
                .foregroundColor(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(title)
                    .font(.system(.caption, design: .default).weight(.semibold))
                    .foregroundColor(color)

                Text(description)
                    .font(.system(.caption2, design: .default).weight(.regular))
                    .foregroundColor(SupportTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(SupportTheme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                .fill(color.opacity(0.05))
        )
    }
}

#Preview {
    ProgressChartView(
        assessmentType: .phq9,
        responses: [
            AssessmentResponse(
                id: UUID(),
                userId: UUID(),
                assessmentTemplateId: UUID(),
                answers: [:],
                totalScore: 18,
                severityLevel: "moderate",
                isBaseline: true,
                notes: nil,
                completedAt: Date().addingTimeInterval(-86400 * 7),
                createdAt: Date()
            ),
            AssessmentResponse(
                id: UUID(),
                userId: UUID(),
                assessmentTemplateId: UUID(),
                answers: [:],
                totalScore: 15,
                severityLevel: "moderate",
                isBaseline: false,
                notes: nil,
                completedAt: Date(),
                createdAt: Date()
            )
        ],
        goal: OutcomeGoal(
            id: UUID(),
            userId: UUID(),
            assessmentTemplateId: UUID(),
            targetScore: 10,
            targetDate: Date().addingTimeInterval(86400 * 84),
            baselineScore: 18,
            baselineDate: Date().addingTimeInterval(-86400 * 7),
            achieved: false,
            achievedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    )
}
