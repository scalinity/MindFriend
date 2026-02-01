import SwiftUI

/// Main sleep tracking dashboard showing recent sleep, trends, and quick actions
struct SleepDashboardView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @StateObject private var viewModel: SleepDashboardViewModel
    @State private var showManualEntry = false

    init() {
        _viewModel = StateObject(wrappedValue: SleepDashboardViewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Last Night's Sleep Summary
                    if let lastEntry = viewModel.lastSleepEntry {
                        lastNightSection(lastEntry)
                    } else {
                        emptyStateSection
                    }

                    // Weekly Trend
                    if !viewModel.weekEntries.isEmpty {
                        weeklyTrendSection
                    }

                    // Quick Actions
                    quickActionsSection

                    // Insights
                    if !viewModel.insights.isEmpty {
                        insightsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Sleep Tracking")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showMorningCheckIn) {
                if let entry = viewModel.lastSleepEntry {
                    MorningCheckInView(entry: entry)
                }
            }
            .sheet(isPresented: $viewModel.showSettings) {
                NavigationStack {
                    SleepGoalsView()
                }
            }
            .sheet(isPresented: $viewModel.showWindDown) {
                WindDownRoutineView()
            }
            .sheet(isPresented: $showManualEntry) {
                ManualSleepEntryView(isPresented: $showManualEntry) {
                    // Refresh data after save
                    Task {
                        await viewModel.loadData(
                            trackingService: dependencies.sleepTrackingService,
                            healthKitManager: dependencies.sleepHealthKitManager
                        )
                    }
                }
            }
            .task {
                await viewModel.loadData(
                    trackingService: dependencies.sleepTrackingService,
                    healthKitManager: dependencies.sleepHealthKitManager
                )
            }
            .refreshable {
                await viewModel.refresh(
                    trackingService: dependencies.sleepTrackingService,
                    healthKitManager: dependencies.sleepHealthKitManager
                )
            }
        }
    }

    // MARK: - Last Night Section

    @ViewBuilder
    private func lastNightSection(_ entry: SleepEntry) -> some View {
        VStack(spacing: 16) {
            Text("Last Night")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 20) {
                // Sleep Score Ring
                SleepScoreRing(score: entry.sleepScore ?? 0, size: 120)

                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.durationFormatted)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(entry.qualityLabel)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let breakdown = entry.scoreBreakdown {
                        Text("Weakest: \(breakdown.primaryFactor)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    if entry.userRating == nil {
                        Button {
                            viewModel.showMorningCheckIn = true
                        } label: {
                            Text("Rate Sleep")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            // Score Breakdown
            if let breakdown = entry.scoreBreakdown {
                scoreBreakdownView(breakdown)
            }
        }
    }

    @ViewBuilder
    private func scoreBreakdownView(_ breakdown: SleepScoreBreakdown) -> some View {
        VStack(spacing: 8) {
            scoreComponent("Duration", score: breakdown.duration, max: 25)
            scoreComponent("Efficiency", score: breakdown.efficiency, max: 25)
            scoreComponent("Timing", score: breakdown.timing, max: 20)
            scoreComponent("Stages", score: breakdown.stages, max: 20)
            scoreComponent("Restfulness", score: breakdown.restfulness, max: 10)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func scoreComponent(_ name: String, score: Int, max: Int) -> some View {
        HStack {
            Text(name)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 6)
                        .cornerRadius(3)

                    Rectangle()
                        .fill(scoreColor(Double(score) / Double(max)))
                        .frame(width: geometry.size.width * (Double(score) / Double(max)), height: 6)
                        .cornerRadius(3)
                }
            }
            .frame(height: 6)

            Text("\(score)/\(max)")
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func scoreColor(_ percentage: Double) -> Color {
        if percentage >= 0.85 { return .green }
        if percentage >= 0.7 { return .yellow }
        return .orange
    }

    // MARK: - Weekly Trend Section

    @ViewBuilder
    private var weeklyTrendSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("7-Day Trend")
                    .font(.headline)

                Spacer()

                if let avgScore = viewModel.weeklyAverageScore {
                    Text("\(avgScore) avg")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            SleepTrendGraph(entries: viewModel.weekEntries)
                .frame(height: 150)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActionsSection: some View {
        VStack(spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                quickActionButton(
                    title: "Wind Down",
                    icon: "moon.stars.fill",
                    color: .purple
                ) {
                    viewModel.showWindDown = true
                }

                quickActionButton(
                    title: "Log Sleep",
                    icon: "bed.double.fill",
                    color: .blue
                ) {
                    showManualEntry = true
                }

                quickActionButton(
                    title: "Goals",
                    icon: "target",
                    color: .green
                ) {
                    viewModel.showSettings = true
                }
            }
        }
    }

    @ViewBuilder
    private func quickActionButton(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 70)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    // MARK: - Insights Section

    @ViewBuilder
    private var insightsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Insights")
                    .font(.headline)

                Spacer()

                NavigationLink {
                    SleepInsightsView()
                } label: {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
            }

            ForEach(viewModel.insights.prefix(2)) { insight in
                insightCard(insight)
            }
        }
    }

    @ViewBuilder
    private func insightCard(_ insight: SleepInsight) -> some View {
        HStack(spacing: 12) {
            Image(systemName: insight.insightType.icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.insightData.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(insight.insightData.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if !insight.viewed {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            if dependencies.sleepHealthKitManager.isAuthorized {
                // HealthKit is connected but no sleep data found
                Text("No Sleep Data Yet")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("We couldn't find any sleep data in HealthKit. Make sure you have sleep data recorded in the Health app, or add a manual entry.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    showManualEntry = true
                } label: {
                    Text("Log Sleep Manually")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                
                Button {
                    Task {
                        await viewModel.refresh(
                            trackingService: dependencies.sleepTrackingService,
                            healthKitManager: dependencies.sleepHealthKitManager
                        )
                    }
                } label: {
                    Text("Sync from HealthKit Again")
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
            } else {
                // HealthKit not connected yet
                Text("Start Tracking Your Sleep")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Connect HealthKit or manually log your sleep to get personalized insights")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    Task {
                        await viewModel.requestHealthKitAuth(
                            healthKitManager: dependencies.sleepHealthKitManager,
                            trackingService: dependencies.sleepTrackingService
                        )
                    }
                } label: {
                    Text("Connect HealthKit")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                
                Button {
                    showManualEntry = true
                } label: {
                    Text("Or Log Manually")
                        .font(.subheadline)
                        .foregroundColor(.accentColor)
                }
            }
        }
        .padding(.vertical, 40)
    }
}

// MARK: - View Model

@MainActor
final class SleepDashboardViewModel: ObservableObject {
    @Published var lastSleepEntry: SleepEntry?
    @Published var weekEntries: [SleepEntry] = []
    @Published var insights: [SleepInsight] = []
    @Published var isLoading = false
    @Published var showMorningCheckIn = false
    @Published var showSettings = false
    @Published var showWindDown = false

    var weeklyAverageScore: Int? {
        let scores = weekEntries.compactMap { $0.sleepScore }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / scores.count
    }

    func loadData(trackingService: SleepTrackingService, healthKitManager: SleepHealthKitManager) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Fetch latest entry
            lastSleepEntry = try await trackingService.fetchLatestEntry()

            // Fetch last 7 days
            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate)!
            weekEntries = try await trackingService.fetchEntries(from: startDate, to: endDate)

            // Fetch insights
            insights = try await trackingService.fetchInsights()

            // Check if should show morning check-in
            if let last = lastSleepEntry,
               last.userRating == nil,
               shouldShowMorningCheckIn(for: last) {
                showMorningCheckIn = true
            }
        } catch {
            print("Failed to load sleep data: \(error)")
        }
    }

    func refresh(trackingService: SleepTrackingService, healthKitManager: SleepHealthKitManager) async {
        // Sync from HealthKit first
        do {
            _ = try await healthKitManager.syncRecentSleep()
        } catch {
            print("HealthKit sync failed: \(error)")
        }

        // Reload data
        await loadData(trackingService: trackingService, healthKitManager: healthKitManager)
    }

    func requestHealthKitAuth(healthKitManager: SleepHealthKitManager, trackingService: SleepTrackingService) async {
        print("[SleepDashboard] Starting HealthKit authorization...")
        
        do {
            try await healthKitManager.requestAuthorization()
            print("[SleepDashboard] Authorization complete, syncing sleep data...")
            
            // Sync after authorization
            let entry = try await healthKitManager.syncRecentSleep()
            print("[SleepDashboard] Sync complete. Entry: \(entry != nil ? "found" : "none")")
            
            // Reload data to update the UI
            await loadData(trackingService: trackingService, healthKitManager: healthKitManager)
            print("[SleepDashboard] Data reloaded. Entries: \(weekEntries.count)")
        } catch {
            print("[SleepDashboard] HealthKit authorization/sync failed: \(error)")
        }
    }

    private func shouldShowMorningCheckIn(for entry: SleepEntry) -> Bool {
        let now = Date()
        let hoursSinceWake = now.timeIntervalSince(entry.wakeTime) / 3600
        return hoursSinceWake >= 0 && hoursSinceWake <= 2 // Within 2 hours of wake
    }
}

#Preview {
    SleepDashboardView()
        .environmentObject(DependencyContainer.preview)
}
