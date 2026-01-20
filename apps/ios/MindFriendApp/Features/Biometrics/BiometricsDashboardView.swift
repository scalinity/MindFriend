import SwiftUI
import Charts

struct BiometricsDashboardView: View {
    @StateObject private var healthKit = HealthKitService()
    @State private var todaySummary: BiometricDailySummary?
    @State private var recentSummaries: [BiometricDailySummary] = []
    @State private var insights: [BiometricInsight] = []
    @State private var alerts: [BiometricAlert] = []
    @State private var correlations: [MoodBiometricCorrelation] = []
    @State private var isLoading = true
    @State private var showSettings = false
    @State private var showConnectionSheet = false
    @State private var selectedInsight: BiometricInsight?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if !healthKit.isAuthorized {
                        connectHealthKitCard
                    } else {
                        if healthKit.isSyncing {
                            syncingIndicator
                        }

                        todayMetricsSection

                        if !alerts.isEmpty {
                            alertsSection
                        }

                        if !insights.isEmpty {
                            insightsSection
                        }

                        if !correlations.isEmpty {
                            correlationsSection
                        }

                        if recentSummaries.count > 1 {
                            trendsSection
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Body & Mind")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if healthKit.isAuthorized {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .refreshable {
                await refresh()
            }
            .task {
                await loadData()
            }
            .sheet(isPresented: $showConnectionSheet) {
                HealthKitConnectionSheet(healthKit: healthKit) {
                    Task {
                        await loadData()
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                BiometricsSettingsView(healthKit: healthKit)
            }
            .sheet(item: $selectedInsight) { insight in
                InsightDetailView(insight: insight, healthKit: healthKit)
            }
        }
    }

    // MARK: - Connect Card

    private var connectHealthKitCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 60))
                .foregroundStyle(.pink.gradient)

            Text("Connect Apple Health")
                .font(.title2.bold())

            Text("Understand how your sleep, activity, and stress levels affect your mood.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showConnectionSheet = true
            } label: {
                Label("Connect Health Data", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Syncing

    private var syncingIndicator: some View {
        HStack {
            ProgressView()
            Text("Syncing health data...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Today's Metrics

    private var todayMetricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.headline)

            if let summary = todaySummary {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    if let sleepHours = summary.sleepHours {
                        MetricCard(
                            icon: "moon.zzz.fill",
                            title: "Sleep",
                            value: String(format: "%.1fh", sleepHours),
                            subtitle: summary.sleepQualityScore.map { "\(Int($0 * 100))% efficiency" },
                            color: .indigo
                        )
                    }

                    if let hrv = summary.hrvAverageMs {
                        MetricCard(
                            icon: "heart.fill",
                            title: "HRV",
                            value: "\(Int(hrv))ms",
                            subtitle: summary.restingHeartRate.map { "Resting HR: \($0)" },
                            color: .red
                        )
                    }

                    if let steps = summary.stepsCount {
                        MetricCard(
                            icon: "figure.walk",
                            title: "Steps",
                            value: summary.stepsFormatted ?? "\(steps)",
                            subtitle: summary.distanceFormatted,
                            color: .green
                        )
                    }

                    if let activeKcal = summary.activeEnergyKcal {
                        MetricCard(
                            icon: "flame.fill",
                            title: "Active Energy",
                            value: "\(activeKcal) cal",
                            subtitle: summary.exerciseMinutes.map { "\($0) min exercise" },
                            color: .orange
                        )
                    }
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Text("No data for today yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }

    // MARK: - Alerts

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Alerts")
                .font(.headline)

            ForEach(alerts.prefix(3)) { alert in
                BiometricAlertCard(alert: alert) {
                    Task {
                        try? await healthKit.markAlertRead(alert.id)
                        await loadAlerts()
                    }
                }
            }
        }
    }

    // MARK: - Insights

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Insights")
                    .font(.headline)
                Spacer()
                NavigationLink("See All") {
                    InsightsListView(insights: insights, healthKit: healthKit)
                }
                .font(.subheadline)
            }

            ForEach(insights.prefix(2)) { insight in
                InsightCard(insight: insight)
                    .onTapGesture {
                        selectedInsight = insight
                    }
            }
        }
    }

    // MARK: - Correlations

    private var correlationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Patterns")
                .font(.headline)

            ForEach(correlations) { correlation in
                CorrelationCard(correlation: correlation)
            }
        }
    }

    // MARK: - Trends

    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("7-Day Trends")
                .font(.headline)

            // Sleep trend chart
            if recentSummaries.contains(where: { $0.sleepDurationMinutes != nil }) {
                sleepTrendChart
            }

            // Steps trend chart
            if recentSummaries.contains(where: { $0.stepsCount != nil }) {
                stepsTrendChart
            }
        }
    }

    private var sleepTrendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Chart(recentSummaries.reversed()) { summary in
                if let hours = summary.sleepHours {
                    BarMark(
                        x: .value("Date", summary.date),
                        y: .value("Hours", hours)
                    )
                    .foregroundStyle(.indigo.gradient)
                }
            }
            .frame(height: 120)
            .chartYAxis {
                AxisMarks(values: [0, 4, 8]) { value in
                    AxisValueLabel {
                        if let hours = value.as(Int.self) {
                            Text("\(hours)h")
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisValueLabel()
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var stepsTrendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Steps")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Chart(recentSummaries.reversed()) { summary in
                if let steps = summary.stepsCount {
                    LineMark(
                        x: .value("Date", summary.date),
                        y: .value("Steps", steps)
                    )
                    .foregroundStyle(.green.gradient)

                    AreaMark(
                        x: .value("Date", summary.date),
                        y: .value("Steps", steps)
                    )
                    .foregroundStyle(.green.opacity(0.1).gradient)
                }
            }
            .frame(height: 120)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        guard healthKit.isAuthorized else { return }

        // Sync if needed (hourly)
        if healthKit.lastSyncDate == nil ||
           Date().timeIntervalSince(healthKit.lastSyncDate!) > 3600 {
            try? await healthKit.syncBiometrics(days: 7)
        }

        // Load from database in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadTodaySummary() }
            group.addTask { await self.loadRecentSummaries() }
            group.addTask { await self.loadInsights() }
            group.addTask { await self.loadAlerts() }
            group.addTask { await self.loadCorrelations() }
        }
    }

    private func refresh() async {
        try? await healthKit.syncBiometrics(days: 7)
        await loadData()
    }

    private func loadTodaySummary() async {
        do {
            todaySummary = try await healthKit.getTodaySummary()
        } catch {
            Log.biometrics.error("Failed to load today summary", error: error)
        }
    }

    private func loadRecentSummaries() async {
        do {
            recentSummaries = try await healthKit.getRecentSummaries(days: 7)
        } catch {
            Log.biometrics.error("Failed to load recent summaries", error: error)
        }
    }

    private func loadInsights() async {
        do {
            insights = try await healthKit.getInsights()
        } catch {
            Log.biometrics.error("Failed to load insights", error: error)
        }
    }

    private func loadAlerts() async {
        do {
            alerts = try await healthKit.getAlerts()
        } catch {
            Log.biometrics.error("Failed to load alerts", error: error)
        }
    }

    private func loadCorrelations() async {
        do {
            correlations = try await healthKit.getCorrelations()
        } catch {
            Log.biometrics.error("Failed to load correlations", error: error)
        }
    }
}

// MARK: - Metric Card

struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.title2.bold())

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

// MARK: - Alert Card

struct BiometricAlertCard: View {
    let alert: BiometricAlert
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: alert.alertType.icon)
                .font(.title2)
                .foregroundStyle(alertColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title)
                    .font(.subheadline.bold())
                Text(alert.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if alert.suggestedActionType != nil {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDismiss()
            } label: {
                Label("Dismiss", systemImage: "xmark")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(alert.severity.rawValue.capitalized) alert: \(alert.title). \(alert.message)")
    }

    private var alertColor: Color {
        switch alert.severity {
        case .info: return .blue
        case .warning: return .orange
        case .urgent: return .red
        }
    }
}

// MARK: - Insight Card

struct InsightCard: View {
    let insight: BiometricInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: insight.insightCategory.icon)
                    .foregroundStyle(categoryColor)
                Text(insight.title)
                    .font(.subheadline.bold())
                Spacer()
                if let label = insight.correlationLabel {
                    Text(label)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(categoryColor.opacity(0.2))
                        .clipShape(Capsule())
                }
            }

            Text(insight.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(insight.insightCategory.displayName) insight: \(insight.title). \(insight.description)")
    }

    private var categoryColor: Color {
        switch insight.insightCategory {
        case .sleep: return .indigo
        case .activity: return .green
        case .stress: return .orange
        case .general: return .blue
        }
    }
}

// MARK: - Correlation Card

struct CorrelationCard: View {
    let correlation: MoodBiometricCorrelation

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(correlation.biometricTypeDisplay)
                    .font(.subheadline)
                Text(correlation.directionLabel ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Visual correlation indicator
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(correlationBarColor(at: i))
                        .frame(width: 8, height: 20)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(correlation.biometricTypeDisplay): \(correlation.strengthLabel ?? "no") \(correlation.directionLabel ?? "") correlation with mood")
    }

    private func correlationBarColor(at index: Int) -> Color {
        let strength = abs(correlation.correlationCoefficient)
        let threshold = Double(index + 1) / 5.0

        if strength >= threshold {
            return correlation.correlationCoefficient > 0 ? .green : .red
        }
        return Color.gray.opacity(0.3)
    }
}

#Preview {
    BiometricsDashboardView()
}
