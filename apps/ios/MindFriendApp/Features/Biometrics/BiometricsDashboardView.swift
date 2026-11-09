import Charts
import SwiftUI

struct BiometricsDashboardView: View {
    @ObservedObject private var healthKit = HealthKitService.shared
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
                VStack(spacing: SupportTheme.Spacing.l) {
                    if !healthKit.hasCompletedPermissionRequest {
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
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("Body & Mind")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if healthKit.hasCompletedPermissionRequest {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        .accessibilityLabel("Settings")
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
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 60))
                .foregroundStyle(SupportTheme.accent.gradient)

            Text("Connect Apple Health")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text("Understand how your sleep, activity, and stress levels affect your mood.")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                showConnectionSheet = true
            } label: {
                Label("Connect Health Data", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.supportPrimary)
            .controlSize(.large)
        }
        .padding()
        .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }

    // MARK: - Syncing

    private var syncingIndicator: some View {
        HStack {
            ProgressView()
            Text("Syncing health data...")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .padding(.vertical, SupportTheme.Spacing.xs)
    }

    // MARK: - Today's Metrics

    private var todayMetricsSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Today")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if let summary = todaySummary {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: SupportTheme.Spacing.s) {
                    if let sleepHours = summary.sleepHours {
                        MetricCard(
                            icon: "moon.zzz.fill",
                            title: "Sleep",
                            value: String(format: "%.1fh", sleepHours),
                            subtitle: summary.sleepQualityScore.map { "\(Int($0 * 100))% efficiency" },
                            color: SupportTheme.accent
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
                            color: SupportTheme.accent
                        )
                    }

                    if let activeKcal = summary.activeEnergyKcal {
                        MetricCard(
                            icon: "flame.fill",
                            title: "Active Energy",
                            value: "\(activeKcal) cal",
                            subtitle: summary.exerciseMinutes.map { "\($0) min exercise" },
                            color: SupportTheme.accent
                        )
                    }
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Text("No data for today yet")
                    .foregroundStyle(SupportTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }

    // MARK: - Alerts

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Alerts")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

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
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Text("Insights")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink("See All") {
                    InsightsListView(insights: insights, healthKit: healthKit)
                }
                .font(.subheadline)
            }

            ForEach(insights.prefix(2)) { insight in
                InsightCard(
                    icon: "lightbulb.fill",
                    title: insight.title,
                    description: insight.description,
                    color: SupportTheme.accent
                )
                .onTapGesture {
                    selectedInsight = insight
                }
            }
        }
    }

    // MARK: - Correlations

    private var correlationsSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Your Patterns")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(correlations) { correlation in
                CorrelationCard(correlation: correlation)
            }
        }
    }

    // MARK: - Trends

    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("7-Day Trends")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

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
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text("Sleep")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)

            Chart(recentSummaries.reversed()) { summary in
                if let hours = summary.sleepHours {
                    BarMark(
                        x: .value("Date", summary.date),
                        y: .value("Hours", hours)
                    )
                    .foregroundStyle(SupportTheme.accent.gradient)
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
        .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }

    private var stepsTrendChart: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text("Steps")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)

            Chart(recentSummaries.reversed()) { summary in
                if let steps = summary.stepsCount {
                    LineMark(
                        x: .value("Date", summary.date),
                        y: .value("Steps", steps)
                    )
                    .foregroundStyle(SupportTheme.accent.gradient)

                    AreaMark(
                        x: .value("Date", summary.date),
                        y: .value("Steps", steps)
                    )
                    .foregroundStyle(SupportTheme.accent.opacity(0.1).gradient)
                }
            }
            .frame(height: 120)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
        }
        .padding()
        .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        guard healthKit.hasCompletedPermissionRequest else { return }

        // Sync if needed (hourly)
        if healthKit.lastSyncDate == nil || Date().timeIntervalSince(healthKit.lastSyncDate!) > 3600 {
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
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            Text(value)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

// MARK: - Alert Card

struct BiometricAlertCard: View {
    let alert: BiometricAlert
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: alert.alertType.icon)
                .font(.title2)
                .foregroundStyle(alertColor)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(alert.title)
                    .font(.subheadline.bold())
                Text(alert.message)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            Spacer()

            if alert.suggestedActionType != nil {
                Image(systemName: "chevron.right")
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .padding()
        .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
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
        case .info: return SupportTheme.accent
        case .warning: return SupportTheme.accent
        case .urgent: return .red
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
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            Spacer()

            // Visual correlation indicator
            HStack(spacing: SupportTheme.Spacing.xxs) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                        .fill(correlationBarColor(at: i))
                        .frame(width: 8, height: 20)
                }
            }
        }
        .padding()
        .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(correlation.biometricTypeDisplay): \(correlation.strengthLabel ?? "no") \(correlation.directionLabel ?? "") correlation with mood"
        )
    }

    private func correlationBarColor(at index: Int) -> Color {
        let strength = abs(correlation.correlationCoefficient)
        let threshold = Double(index + 1) / 5.0

        if strength >= threshold {
            return correlation.correlationCoefficient > 0 ? SupportTheme.accent : .red
        }
        return SupportTheme.textSecondary.opacity(0.3)
    }
}

#Preview {
    BiometricsDashboardView()
}
