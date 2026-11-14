import Charts
import SwiftUI

/// Main Weekly Insights screen showing mood analysis, patterns, and AI recommendations
struct WeeklyInsightsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var currentInsight: WeeklySummary?
    @State private var pastInsights: [WeeklySummary] = []
    @State private var isLoading = true
    @State private var isGenerating = false
    @State private var error: String?

    // Insights tutorial state
    @AppStorage("insights_tutorial_completed") private var insightsTutorialCompleted = false
    @State private var showInsightsTutorial = false

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                if isLoading || isGenerating {
                    VStack(spacing: SupportTheme.Spacing.s) {
                        ProgressView()
                        if isGenerating {
                            Text("Generating your insights...")
                                .font(.subheadline)
                                .foregroundColor(SupportTheme.textSecondary)
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

                    // Show error if present (for debugging)
                    if let error = error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(SupportTheme.controlRadius)
                    }
                }
            }
            .padding()
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("Weekly Insights")
        .background(SupportTheme.canvas)
        .task { await loadInsights(forceRegenerate: false) }
        .refreshable { await loadInsights(forceRegenerate: true) }
        .onChange(of: container.supabaseAuthService.userId) { _, newValue in
            guard newValue != nil else { return }
            Task {
                await loadInsights(forceRegenerate: false)
            }
        }
        .onAppear {
            if !insightsTutorialCompleted {
                showInsightsTutorial = true
            }
        }
        .fullScreenCover(isPresented: $showInsightsTutorial) {
            InsightsTutorialFlow(onComplete: {
                insightsTutorialCompleted = true
                showInsightsTutorial = false
            })
            .environmentObject(container)
        }
    }

    private func loadInsights(forceRegenerate: Bool) async {
        // Wait for authentication to be ready
        guard container.supabaseAuthService.userId != nil else {
            print("[WeeklyInsightsView] Not authenticated yet, skipping data load")
            isLoading = false
            error = "Please sign in to view your insights"
            return
        }

        isLoading = true
        error = nil

        do {
            // First, try to fetch existing insights
            currentInsight = try await container.supabaseDataService.getWeeklySummary()

            // Regenerate if:
            // - Force regenerate requested (pull-to-refresh)
            // - No insight exists
            // - Existing one has no meaningful data (user may have logged mood since)
            let hasNoMeaningfulData = currentInsight?.avgMood == nil && currentInsight?.checkinCount == 0
            let shouldRegenerate = forceRegenerate || currentInsight == nil || hasNoMeaningfulData

            if shouldRegenerate {
                isLoading = false
                isGenerating = true

                do {
                    currentInsight = try await container.supabaseDataService.generateWeeklyInsight()
                } catch {
                    // If generation fails, show the error to the user for debugging
                    self.error = "Generation failed: \(error.localizedDescription)"
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
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            HStack {
                Text("This Week")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(insight.weekLabel)
                    .font(.subheadline)
                    .foregroundColor(SupportTheme.textSecondary)
            }

            if let avg = insight.avgMood {
                HStack(spacing: SupportTheme.Spacing.l) {
                    VStack {
                        Text(String(format: "%.1f", avg))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                        Text("avg mood")
                            .font(.caption)
                            .foregroundColor(SupportTheme.textSecondary)
                    }

                    Spacer()

                    // Only show trend for meaningful values (not baseline/insufficientData)
                    if let trend = insight.moodTrend,
                        trend != .baseline && trend != .insufficientData
                    {
                        VStack(alignment: .trailing, spacing: SupportTheme.Spacing.xxs) {
                            Text(trend.emoji)
                                .font(.title)
                                .accessibilityAddTraits(.isHeader)
                            Text(insight.moodTrendMessage)
                                .font(.subheadline)
                                .foregroundColor(trend.insightColor)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            } else {
                Text("Not enough mood data yet")
                    .foregroundColor(SupportTheme.textSecondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)
    }
}

// MARK: - Trend color

private extension MoodTrend {
    /// Improving is green, declining is warm orange, steady is blue and unknown is neutral.
    var insightColor: Color {
        switch self {
        case .improving: return SupportTheme.Status.positive
        case .stable: return SupportTheme.Area.voice.palette.ink
        case .declining: return SupportTheme.Status.caution
        case .baseline, .insufficientData: return SupportTheme.textSecondary
        }
    }
}

// MARK: - Mood Chart Card

struct MoodChartCard: View {
    let insight: WeeklySummary

    private let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let dayKeys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Mood by Day")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

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
                            .cornerRadius(SupportTheme.controlRadius)
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
                HStack(alignment: .bottom, spacing: SupportTheme.Spacing.xs) {
                    ForEach(Array(zip(days, dayKeys)), id: \.0) { day, key in
                        VStack {
                            if let moods = insight.moodByDay, let value = moods[key] {
                                RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                                    .fill(moodColor(value))
                                    .frame(width: 30, height: CGFloat(value) * 25)
                            } else {
                                RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                                    .fill(SupportTheme.textSecondary.opacity(0.3))
                                    .frame(width: 30, height: 20)
                            }
                            Text(day)
                                .font(.caption2)
                                .foregroundColor(SupportTheme.textSecondary)
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
                        .foregroundColor(SupportTheme.Status.caution)
                    Spacer()
                    Label("High: \(max)", systemImage: "arrow.up")
                        .font(.caption)
                        .foregroundColor(SupportTheme.Status.positive)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)
    }

    private func moodColor(_ value: Double) -> Color {
        switch value {
        case 4...: return SupportTheme.Status.positive
        case 3..<4: return SupportTheme.Area.voice.palette.ink
        default: return SupportTheme.Status.caution
        }
    }
}

// MARK: - Patterns Card

struct PatternsCard: View {
    let patterns: [DetectedPattern]

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Label("Patterns Detected", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            ForEach(patterns, id: \.description) { pattern in
                HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                    Image(systemName: pattern.icon)
                        .foregroundColor(SupportTheme.Celebration.gold)
                        .frame(minWidth: 24)

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text(pattern.description)
                            .font(.subheadline)

                        // Confidence indicator
                        HStack(spacing: SupportTheme.Spacing.xxs) {
                            ForEach(0..<5) { i in
                                Circle()
                                    .fill(
                                        Double(i) / 5.0 < pattern.confidence
                                            ? SupportTheme.Celebration.gold : SupportTheme.textSecondary.opacity(0.3)
                                    )
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)
    }
}

// MARK: - AI Insight Card

struct AIInsightCard: View {
    let insight: String
    let recommendations: [InsightRecommendation]

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Label("AI Insight", systemImage: "sparkles")
                .font(.headline)

            Text(insight)
                .font(.body)

            if !recommendations.isEmpty {
                Divider()

                Text("Recommendations")
                    .font(.subheadline)
                    .foregroundColor(SupportTheme.textSecondary)

                ForEach(recommendations, id: \.title) { rec in
                    HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(SupportTheme.accent)

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text(rec.title)
                                .fontWeight(.medium)
                            Text(rec.reason)
                                .font(.caption)
                                .foregroundColor(SupportTheme.textSecondary)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)
    }
}

// MARK: - Activity Summary Card

struct ActivitySummaryCard: View {
    let insight: WeeklySummary

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Activity Summary")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: SupportTheme.Spacing.s) {
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
                        .foregroundColor(SupportTheme.Area.people.palette.ink)
                    Text("\(circleCount) circle check-ins")
                        .font(.subheadline)
                        .foregroundColor(SupportTheme.textSecondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)
    }
}

struct InsightStatBox: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xxs) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(SupportTheme.accent)
            Text(value)
                .font(.title3)
                .accessibilityAddTraits(.isHeader)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SupportTheme.Spacing.xs)
    }
}

// MARK: - Past Weeks Section

struct PastWeeksSection: View {
    let insights: [WeeklySummary]

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Past Weeks")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SupportTheme.Spacing.s) {
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
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text(insight.weekLabel)
                .font(.caption)
                .foregroundColor(SupportTheme.textSecondary)

            if let avg = insight.avgMood {
                HStack(spacing: SupportTheme.Spacing.xxs) {
                    Text(String(format: "%.1f", avg))
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)
                        .fontWeight(.bold)

                    // Only show trend icon for meaningful values
                    if let trend = insight.moodTrend,
                        trend != .insufficientData && trend != .baseline
                    {
                        Image(systemName: trend.icon)
                            .foregroundColor(trend.insightColor)
                            .font(.caption)
                    }
                }
            } else {
                Text("--")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                    .foregroundColor(SupportTheme.textSecondary)
            }

            HStack(spacing: SupportTheme.Spacing.xs) {
                Label("\(insight.questCount)", systemImage: "checkmark")
                Label("\(insight.exerciseCount)", systemImage: "figure.walk")
            }
            .font(.caption2)
            .foregroundColor(SupportTheme.textSecondary)
        }
        .padding()
        .frame(width: 140)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)
    }
}

// MARK: - Empty State

struct EmptyInsightCard: View {
    var body: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundColor(SupportTheme.textSecondary)

            Text("No Insights Yet")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text(
                "Log your moods, complete quests, and do exercises throughout the week. Your personalized insights will appear here every Sunday."
            )
            .font(.subheadline)
            .foregroundColor(SupportTheme.textSecondary)
            .multilineTextAlignment(.center)
        }
        .padding(SupportTheme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)
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
