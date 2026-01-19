import SwiftUI
import Charts

/// Main Weekly Insights screen showing mood analysis, patterns, and AI recommendations
struct WeeklyInsightsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var currentInsight: WeeklySummary?
    @State private var pastInsights: [WeeklySummary] = []
    @State private var isLoading = true
    @State private var isGenerating = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isLoading || isGenerating {
                    VStack(spacing: 12) {
                        ProgressView()
                        if isGenerating {
                            Text("Generating your insights...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 200)
                } else if let insight = currentInsight {
                    CurrentWeekCard(insight: insight)
                    MoodChartCard(insight: insight)

                    if let patterns = insight.patternsDetected, !patterns.isEmpty {
                        PatternsCard(patterns: patterns)
                    }

                    if let aiInsight = insight.aiInsight {
                        AIInsightCard(
                            insight: aiInsight,
                            recommendations: insight.aiRecommendations ?? []
                        )
                    }

                    ActivitySummaryCard(insight: insight)

                    if !pastInsights.isEmpty {
                        PastWeeksSection(insights: pastInsights)
                    }
                } else {
                    EmptyInsightCard()
                }
            }
            .padding()
        }
        .navigationTitle("Weekly Insights")
        .background(Color(.systemGroupedBackground))
        .task { await loadInsights() }
        .refreshable { await loadInsights() }
    }

    private func loadInsights() async {
        isLoading = true
        error = nil

        do {
            // First, try to fetch existing insights
            currentInsight = try await container.supabaseDataService.getWeeklySummary()

            // If no current insight exists, auto-generate one
            if currentInsight == nil {
                isLoading = false
                isGenerating = true

                do {
                    currentInsight = try await container.supabaseDataService.generateWeeklyInsight()
                } catch {
                    // If generation fails, continue with empty state
                    Log.data.error("Failed to generate weekly insight", error: error)
                }

                isGenerating = false
            }

            let history = try await container.supabaseDataService.getInsightsHistory(limit: 12)

            // Remove current week from history if present
            if let current = currentInsight {
                pastInsights = history.filter { $0.id != current.id }
            } else {
                pastInsights = history
            }

            Analytics.shared.track(.screenViewed, properties: ["screen": "weekly_insights"])
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Current Week Card

struct CurrentWeekCard: View {
    let insight: WeeklySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("This Week")
                    .font(.headline)
                Spacer()
                Text(insight.weekLabel)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let avg = insight.avgMood {
                HStack(spacing: 20) {
                    VStack {
                        Text(String(format: "%.1f", avg))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                        Text("avg mood")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if let trend = insight.moodTrend {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(trend.emoji)
                                .font(.title)
                            Text(insight.moodTrendMessage)
                                .font(.subheadline)
                                .foregroundColor(Color(trend.color))
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            } else {
                Text("Not enough mood data yet")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

// MARK: - Mood Chart Card

struct MoodChartCard: View {
    let insight: WeeklySummary

    private let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let dayKeys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mood by Day")
                .font(.headline)

            if let moodByDay = insight.moodByDay, !moodByDay.isEmpty {
                // Use Charts framework for visualization
                Chart {
                    ForEach(Array(zip(days, dayKeys)), id: \.0) { day, key in
                        if let value = moodByDay[key] {
                            BarMark(
                                x: .value("Day", day),
                                y: .value("Mood", value)
                            )
                            .foregroundStyle(moodColor(value))
                            .cornerRadius(4)
                        }
                    }
                }
                .chartYScale(domain: 0...5)
                .chartYAxis {
                    AxisMarks(values: [1, 2, 3, 4, 5])
                }
                .frame(height: 150)
            } else {
                // Fallback bar chart
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(zip(days, dayKeys)), id: \.0) { day, key in
                        VStack {
                            if let moods = insight.moodByDay, let value = moods[key] {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(moodColor(value))
                                    .frame(width: 30, height: CGFloat(value) * 25)
                            } else {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 30, height: 20)
                            }
                            Text(day)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Min/Max indicators
            if let min = insight.moodMin, let max = insight.moodMax {
                HStack {
                    Label("Low: \(min)", systemImage: "arrow.down")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                    Label("High: \(max)", systemImage: "arrow.up")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private func moodColor(_ value: Double) -> Color {
        switch value {
        case 4...: return .green
        case 3..<4: return .blue
        case 2..<3: return .orange
        default: return .red
        }
    }
}

// MARK: - Patterns Card

struct PatternsCard: View {
    let patterns: [DetectedPattern]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Patterns Detected", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            ForEach(patterns, id: \.description) { pattern in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: pattern.icon)
                        .foregroundColor(.yellow)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pattern.description)
                            .font(.subheadline)

                        // Confidence indicator
                        HStack(spacing: 4) {
                            ForEach(0..<5) { i in
                                Circle()
                                    .fill(Double(i) / 5.0 < pattern.confidence ? Color.yellow : Color.gray.opacity(0.3))
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

// MARK: - AI Insight Card

struct AIInsightCard: View {
    let insight: String
    let recommendations: [InsightRecommendation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI Insight", systemImage: "sparkles")
                .font(.headline)

            Text(insight)
                .font(.body)

            if !recommendations.isEmpty {
                Divider()

                Text("Recommendations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(recommendations, id: \.title) { rec in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(rec.title)
                                .fontWeight(.medium)
                            Text(rec.reason)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(16)
    }
}

// MARK: - Activity Summary Card

struct ActivitySummaryCard: View {
    let insight: WeeklySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity Summary")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                InsightStatBox(icon: "checkmark.circle", label: "Quests", value: "\(insight.questCount)")
                InsightStatBox(icon: "figure.mind.and.body", label: "Exercises", value: "\(insight.exerciseCount)")
                InsightStatBox(icon: "face.smiling", label: "Moods", value: "\(insight.checkinCount)")
                InsightStatBox(
                    icon: "clock",
                    label: "Minutes",
                    value: "\(insight.exerciseMinutes ?? 0)"
                )
            }

            if let circleCount = insight.circleCheckinCount, circleCount > 0 {
                HStack {
                    Image(systemName: "person.2")
                        .foregroundColor(.accentColor)
                    Text("\(circleCount) circle check-ins")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

struct InsightStatBox: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - Past Weeks Section

struct PastWeeksSection: View {
    let insights: [WeeklySummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Past Weeks")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(insights) { insight in
                        PastWeekCard(insight: insight)
                    }
                }
            }
        }
    }
}

struct PastWeekCard: View {
    let insight: WeeklySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(insight.weekLabel)
                .font(.caption)
                .foregroundColor(.secondary)

            if let avg = insight.avgMood {
                HStack(spacing: 4) {
                    Text(String(format: "%.1f", avg))
                        .font(.title2)
                        .fontWeight(.bold)

                    if let trend = insight.moodTrend {
                        Image(systemName: trend.icon)
                            .foregroundColor(Color(trend.color))
                            .font(.caption)
                    }
                }
            } else {
                Text("--")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Label("\(insight.questCount)", systemImage: "checkmark")
                Label("\(insight.exerciseCount)", systemImage: "figure.walk")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 140)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Empty State

struct EmptyInsightCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Insights Yet")
                .font(.headline)

            Text("Log your moods, complete quests, and do exercises throughout the week. Your personalized insights will appear here every Sunday.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WeeklyInsightsView()
            .environmentObject(AppState())
            .environmentObject(DependencyContainer())
    }
}
