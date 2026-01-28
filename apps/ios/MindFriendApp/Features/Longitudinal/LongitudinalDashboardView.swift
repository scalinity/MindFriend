import SwiftUI
import Charts

// MARK: - Longitudinal Dashboard View

struct LongitudinalDashboardView: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel: LongitudinalDashboardViewModel

    // Longitudinal tutorial state
    @AppStorage("longitudinal_tutorial_completed") private var longitudinalTutorialCompleted = false
    @State private var showLongitudinalTutorial = false

    init(container: DependencyContainer? = nil) {
        _viewModel = StateObject(wrappedValue: LongitudinalDashboardViewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Show report generation error as a dismissible banner if we have data
                    if let reportError = viewModel.reportError {
                        reportErrorBanner(reportError)
                    }
                    
                    if viewModel.isLoading {
                        loadingView
                    } else if let error = viewModel.loadError {
                        errorView(error)
                    } else if !viewModel.hasData {
                        emptyStateView
                    } else {
                        contentView
                    }
                }
                .padding()
            }
            .navigationTitle("Your Journey")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        NavigationLink(destination: ReportsView()) {
                            Label("View Reports", systemImage: "doc.text")
                        }
                        Button {
                            viewModel.generateQuarterlyReport()
                        } label: {
                            Label("Generate Report", systemImage: "doc.badge.plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                viewModel.setService(container.longitudinalService)
                viewModel.setDataService(container.supabaseDataService)
                await viewModel.loadData()
            }
            .onAppear {
                if !longitudinalTutorialCompleted {
                    showLongitudinalTutorial = true
                }
            }
            .fullScreenCover(isPresented: $showLongitudinalTutorial) {
                LongitudinalTutorialFlow(onComplete: {
                    longitudinalTutorialCompleted = true
                    showLongitudinalTutorial = false
                })
                .environmentObject(container)
            }
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        VStack(spacing: 24) {
            // Yearly Heat Map
            yearlyHeatMapSection

            // Year at a Glance Card
            yearAtGlanceCard

            // Mood Trend Chart
            moodTrendSection

            // Key Patterns
            if !viewModel.patterns.isEmpty {
                patternsSection
            }

            // Recent Life Events
            if !viewModel.recentLifeEvents.isEmpty {
                lifeEventsSection
            }

            // Quick Actions
            quickActionsSection
        }
    }

    // MARK: - Yearly Heat Map

    private var yearlyHeatMapSection: some View {
        YearlyHeatMapCard(
            moodsByDate: viewModel.moodsByDate,
            year: Calendar.current.component(.year, from: Date())
        )
    }

    // MARK: - Year at a Glance

    private var yearAtGlanceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Year at a Glance")
                    .font(.headline)
                Spacer()
                if let year = viewModel.currentYearStat?.year {
                    Text(String(year))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let yearStat = viewModel.currentYearStat {
                HStack(spacing: 20) {
                    // Quarterly mood summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quarterly Mood")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
                            ForEach(0..<4, id: \.self) { quarter in
                                QuarterMoodIndicator(
                                    quarter: quarter + 1,
                                    mood: yearStat.quarterlyMoods.indices.contains(quarter)
                                        ? yearStat.quarterlyMoods[quarter]
                                        : nil
                                )
                            }
                        }
                    }

                    Divider()

                    // Year comparison
                    if let comparison = yearStat.yearlyComparison {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("vs Last Year")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                Image(systemName: comparison.isImprovement ? "arrow.up.right" : "arrow.down.right")
                                    .foregroundStyle(comparison.isImprovement ? .green : .red)
                                Text(comparison.moodDeltaFormatted)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }

                // Seasonal patterns
                if let patterns = yearStat.seasonalPatterns {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Seasonal Patterns")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        SeasonalPatternBar(patterns: patterns)
                    }
                }

                // Milestones
                if !yearStat.milestonesAchieved.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Milestones")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(yearStat.milestonesAchieved, id: \.name) { milestone in
                                    MilestoneBadge(milestone: milestone)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Not enough data for yearly summary yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    // MARK: - Mood Trend Section

    private var moodTrendSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("12-Month Mood Trend")
                    .font(.headline)
                Spacer()
                NavigationLink(destination: YearlyOverviewView()) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }

            if viewModel.monthlyStats.isEmpty {
                Text("Start tracking to see your mood trends")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                MoodTrendChart(data: viewModel.monthlyStats)
                    .frame(height: 200)
            }

            // Trend indicator
            if let trend = viewModel.dashboardData?.mostRecentMoodTrend {
                HStack {
                    Image(systemName: trendIcon(for: trend))
                        .foregroundStyle(trendColor(for: trend))
                    Text(trendDescription(for: trend))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    // MARK: - Patterns Section

    private var patternsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Detected Patterns")
                    .font(.headline)
                Spacer()
                NavigationLink(destination: PatternsView()) {
                    Text("View All")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }

            ForEach(viewModel.patterns.prefix(3)) { pattern in
                LongitudinalPatternCard(pattern: pattern)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    // MARK: - Life Events Section

    private var lifeEventsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Life Events")
                    .font(.headline)
                Spacer()
                NavigationLink(destination: LifeEventsView()) {
                    Text("View All")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }

            ForEach(viewModel.recentLifeEvents.prefix(3)) { event in
                LifeEventRow(event: event)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(spacing: 12) {
            NavigationLink(destination: LifeEventsView()) {
                HStack {
                    Image(systemName: "calendar.badge.plus")
                        .frame(width: 24)
                    Text("Log Life Event")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            Button {
                viewModel.exportFHIR()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 24)
                    Text("Export Health Data (FHIR)")
                    Spacer()
                    if viewModel.isExporting {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isExporting)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading your journey...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Unable to load data")
                .font(.headline)
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task {
                    await viewModel.refresh()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            // Show heat map even when no other data
            yearlyHeatMapSection

            VStack(spacing: 16) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Your Journey Starts Here")
                    .font(.headline)
                Text("Track your mood regularly to see long-term patterns and insights about your wellness journey.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
        }
    }

    // MARK: - Helpers

    private func reportErrorBanner(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Report generation failed")
                .font(.subheadline)
            Spacer()
            Button {
                viewModel.reportError = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func trendIcon(for trend: MoodTrend) -> String {
        switch trend {
        case .improving: return "arrow.up.right.circle.fill"
        case .declining: return "arrow.down.right.circle.fill"
        case .stable: return "arrow.right.circle.fill"
        case .baseline, .insufficientData: return "minus.circle.fill"
        }
    }

    private func trendColor(for trend: MoodTrend) -> Color {
        switch trend {
        case .improving: return .green
        case .declining: return .red
        case .stable, .baseline, .insufficientData: return .secondary
        }
    }

    private func trendDescription(for trend: MoodTrend) -> String {
        switch trend {
        case .improving: return "Your mood has been improving recently"
        case .declining: return "Your mood has been declining - consider reaching out for support"
        case .stable: return "Your mood has been stable"
        case .baseline, .insufficientData: return "Building your baseline data"
        }
    }
}

// MARK: - View Model

@MainActor
final class LongitudinalDashboardViewModel: ObservableObject {
    @Published var dashboardData: LongitudinalDashboardData?
    @Published var isLoading = false
    @Published var isExporting = false
    @Published var loadError: String?
    @Published var reportError: String?
    @Published var moodsByDate: [String: Int] = [:]

    private var service: LongitudinalService?
    private var dataService: SupabaseDataService?

    var hasData: Bool {
        dashboardData?.hasData ?? false
    }

    var monthlyStats: [MonthlyStat] {
        dashboardData?.monthlyStats ?? []
    }

    var patterns: [LongitudinalPattern] {
        dashboardData?.highConfidencePatterns ?? []
    }

    var recentLifeEvents: [LifeEvent] {
        dashboardData?.recentLifeEvents ?? []
    }

    var currentYearStat: YearlyStat? {
        dashboardData?.currentYearStat
    }

    func setService(_ service: LongitudinalService) {
        self.service = service
    }

    func setDataService(_ dataService: SupabaseDataService) {
        self.dataService = dataService
    }

    func loadData() async {
        guard let service else { return }

        isLoading = true
        loadError = nil

        do {
            dashboardData = try await service.fetchDashboardData()

            // Load mood data for heat map (past 365 days)
            await loadMoodDataForHeatMap()
        } catch {
            self.loadError = error.localizedDescription
        }

        isLoading = false
    }

    private func loadMoodDataForHeatMap() async {
        guard let dataService else { return }

        do {
            let moods = try await dataService.getMoodsForPast(days: 365, limit: 1000)
            var moodDict: [String: Int] = [:]

            for mood in moods {
                // localDate is already in yyyy-MM-dd format
                moodDict[mood.localDate] = mood.moodScore
            }

            self.moodsByDate = moodDict
        } catch {
            // Silent failure - heat map will show no data
            print("[LongitudinalDashboard] Failed to load moods for heat map: \(error)")
        }
    }

    func refresh() async {
        await loadData()
    }

    func generateQuarterlyReport() {
        guard let service else { return }

        Task {
            do {
                _ = try await service.generateReport(type: .quarterly)
                // Could show success notification
            } catch {
                self.reportError = error.localizedDescription
            }
        }
    }

    func exportFHIR() {
        guard let service else { return }

        isExporting = true

        Task {
            do {
                let data = try await service.exportFHIRAsJSON()
                // Share the data
                await shareExportData(data)
            } catch {
                self.reportError = error.localizedDescription
            }
            isExporting = false
        }
    }

    private func shareExportData(_ data: Data) async {
        // Create a temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "mindfriend-wellness-export-\(Date().ISO8601Format()).json"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)

            // Present share sheet
            let activityVC = UIActivityViewController(
                activityItems: [fileURL],
                applicationActivities: nil
            )

            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            self.reportError = "Failed to export: \(error.localizedDescription)"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct LongitudinalDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        LongitudinalDashboardView()
            .environmentObject(DependencyContainer.preview)
    }
}
#endif
