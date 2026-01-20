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
    
    var currentScore: Double {
        responses.sorted { $0.completedAt > $1.completedAt }.first.map { Double($0.totalScore) } ?? 0
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Chart header
            VStack(alignment: .leading, spacing: 8) {
                Text("\(assessmentType.rawValue) Progress")
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                
                Text("\(responses.count) assessments tracked")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Stats pills
            HStack(spacing: 12) {
                StatPill(
                    label: "Current",
                    value: "\(Int(currentScore))",
                    color: Color(red: 0.1, green: 0.3, blue: 0.5)
                )
                
                StatPill(
                    label: "Average",
                    value: "\(Int(averageScore))",
                    color: Color(red: 0.2, green: 0.6, blue: 0.4)
                )
                
                if let goal = goal {
                    StatPill(
                        label: "Target",
                        value: "\(goal.targetScore)",
                        color: Color(red: 0.95, green: 0.7, blue: 0.0)
                    )
                }
            }
            .padding(.horizontal, 16)
            
            // Line chart
            if !chartData.isEmpty {
                Chart {
                    // Trend line
                    ForEach(chartData, id: \.date) { point in
                        LineMark(
                            x: .value("Assessment", point.sequenceNumber),
                            y: .value("Score", point.score)
                        )
                        .foregroundStyle(Color(red: 0.2, green: 0.6, blue: 0.4))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        
                        PointMark(
                            x: .value("Assessment", point.sequenceNumber),
                            y: .value("Score", point.score)
                        )
                        .foregroundStyle(Color(red: 0.2, green: 0.6, blue: 0.4))
                        .symbolSize(80)
                    }
                    
                    // Goal line (if set)
                    if let goal = goal {
                        RuleMark(y: .value("Goal", Double(goal.targetScore)))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))
                            .foregroundStyle(Color(red: 0.95, green: 0.7, blue: 0.0).opacity(0.5))
                    }
                    
                    // Average line
                    RuleMark(y: .value("Average", averageScore))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                        .foregroundStyle(Color.gray.opacity(0.3))
                }
                .chartYScale(domain: 0...(Int(maxScore) + 10))
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisValueLabel()
                            .font(.system(size: 11, weight: .regular, design: .default))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel()
                            .font(.system(size: 11, weight: .regular, design: .default))
                    }
                }
                .frame(height: 240)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                )
                .padding(.horizontal, 16)
                
                // Legend
                VStack(alignment: .leading, spacing: 8) {
                    ChartLegendItem(
                        color: Color(red: 0.2, green: 0.6, blue: 0.4),
                        label: "Your Score"
                    )
                    
                    ChartLegendItem(
                        color: Color.gray.opacity(0.3),
                        label: "Average"
                    )
                    
                    if goal != nil {
                        ChartLegendItem(
                            color: Color(red: 0.95, green: 0.7, blue: 0.0).opacity(0.5),
                            label: "Your Goal"
                        )
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(red: 0.98, green: 0.99, blue: 1.0))
                )
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 40))
                        .foregroundColor(Color.gray.opacity(0.3))
                    
                    Text("No data yet")
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                    
                    Text("Complete more assessments to see your progress")
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundColor(.gray)
                }
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 0.98, green: 0.99, blue: 1.0))
                )
                .padding(.horizontal, 16)
            }
            
            // Insights section
            VStack(alignment: .leading, spacing: 12) {
                Text("Insights")
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.5))
                
                InsightCard(
                    icon: "arrow.trend.down",
                    title: "Trend Direction",
                    description: getTrendDescription(),
                    color: getTrendColor()
                )
                
                if let goal = goal {
                    let daysToGoal = Int(goal.targetDate?.timeIntervalSince(Date()) ?? 0) / 86400
                    let scoreGap = goal.targetScore - Int(currentScore)
                    
                    InsightCard(
                        icon: "target",
                        title: "Goal Progress",
                        description: scoreGap > 0 ?
                            "Need to reduce score by \(scoreGap) points in \(daysToGoal) days" :
                            "Goal achieved! \(-scoreGap) points below target",
                        color: scoreGap > 0 ? Color(red: 0.95, green: 0.7, blue: 0.0) : Color(red: 0.2, green: 0.6, blue: 0.4)
                    )
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }
    
    private func getTrendDescription() -> String {
        guard chartData.count >= 2 else { return "Insufficient data" }
        
        let recent = chartData.suffix(2)
        let previousScore = recent.first?.score ?? 0
        let currentScore = recent.last?.score ?? 0
        let delta = currentScore - previousScore
        
        if delta < 0 {
            return "Improving by \(Int(-delta)) points"
        } else if delta > 0 {
            return "Increasing by \(Int(delta)) points"
        } else {
            return "Score stable"
        }
    }
    
    private func getTrendColor() -> Color {
        guard chartData.count >= 2 else { return Color.gray }
        
        let recent = chartData.suffix(2)
        let previousScore = recent.first?.score ?? 0
        let currentScore = recent.last?.score ?? 0
        let delta = currentScore - previousScore
        
        if delta < 0 {
            return Color(red: 0.2, green: 0.6, blue: 0.4)
        } else if delta > 0 {
            return Color(red: 1.0, green: 0.2, blue: 0.2)
        } else {
            return Color.gray
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
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .default))
                .foregroundColor(color)
            
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.05))
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

struct ChartLegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(color)
                .frame(width: 8, height: 8)
                .cornerRadius(2)
            
            Text(label)
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(.gray)
            
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
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundColor(color)
                
                Text(description)
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
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
                completedAt: Date().addingTimeInterval(-86400 * 7)
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
                completedAt: Date()
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
            achievedAt: nil
        )
    )
}
