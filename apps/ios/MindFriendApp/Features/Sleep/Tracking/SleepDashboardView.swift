import SwiftUI
#if DEBUG
import HealthKit
import Supabase
#endif

/// Main sleep tracking dashboard showing recent sleep, trends, and quick actions
struct SleepDashboardView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: SleepDashboardViewModel
    @State private var showManualEntry = false
    private let trackingReader: (any SleepTrackingReading)?
    private let syncSleep: (() async throws -> Void)?

    init(trackingReader: (any SleepTrackingReading)? = nil, syncSleep: (() async throws -> Void)? = nil) {
        self.trackingReader = trackingReader
        self.syncSleep = syncSleep
        _viewModel = StateObject(wrappedValue: SleepDashboardViewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let message = viewModel.syncErrorMessage {
                        VStack(spacing: 8) {
                            Text(message).foregroundStyle(.secondary)
                            Button("Try Sync Again") {
                                Task { await viewModel.refresh(trackingService: dependencies.sleepTrackingService,
                                    healthKitManager: dependencies.sleepHealthKitManager) }
                            }
                        }
                        .accessibilityIdentifier("sleep.syncError")
                    }
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
                            trackingService: trackingReader ?? dependencies.sleepTrackingService,
                            healthKitManager: dependencies.sleepHealthKitManager
                        )
                    }
                }
            }
            .onDisappear { viewModel.cancelRefresh() }
            .task(id: appState.currentUser?.id) {
                viewModel.cancelRefresh()
                await viewModel.loadData(
                    trackingService: trackingReader ?? dependencies.sleepTrackingService,
                    healthKitManager: dependencies.sleepHealthKitManager
                )
            }
            .refreshable {
                if let syncSleep {
                    await viewModel.refresh(trackingService: trackingReader ?? dependencies.sleepTrackingService, sync: syncSleep)
                } else {
                    await viewModel.refresh(trackingService: dependencies.sleepTrackingService,
                        healthKitManager: dependencies.sleepHealthKitManager)
                }
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

            Text("\(entry.wakeTime.formatted(date: .abbreviated, time: .omitted)) · \(entry.source.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("sleep.source")

            HStack(spacing: 20) {
                // Sleep Score Ring
                if let score = entry.displayableScore {
                    SleepScoreRing(score: score, size: 120)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.durationFormatted)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(entry.displayableScore == nil ? "Score unavailable — missing measurements" : entry.qualityLabel)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if entry.displayableScore != nil, let breakdown = entry.scoreBreakdown {
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

            if !entry.previousImportFeedback.isEmpty {
                DisclosureGroup("Saved feedback from earlier imports") {
                    ForEach(entry.previousImportFeedback) { fragment in
                        VStack(alignment: .leading, spacing: 4) {
                            if let rating = fragment.userRating { Text("Rating: \(rating)/5") }
                            if let dreamNotes = fragment.dreamNotes { Text(dreamNotes) }
                            if let notes = fragment.notes { Text(notes) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            // Score Breakdown
            if entry.displayableScore != nil, let breakdown = entry.scoreBreakdown {
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

            if let error = viewModel.errorMessage {
                Text("Sleep Records Unavailable")
                    .font(.title3).fontWeight(.semibold)
                Text(error)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task {
                        await viewModel.loadData(trackingService: trackingReader ?? dependencies.sleepTrackingService)
                    }
                }
                .accessibilityIdentifier("sleep.retry")
            } else if dependencies.sleepHealthKitManager.isAuthorized {
                // HealthKit is connected but no sleep data found
                Text("No Sleep Data Yet")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("No sleep record is available for last night. Health may have no samples or read access may be off. Check access in Health, or log sleep manually.")
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
    @Published var errorMessage: String?
    @Published var syncErrorMessage: String?
    private var loadID = UUID()
    private var refreshTask: (id: UUID, task: Task<Void, Never>)?
    @Published var showMorningCheckIn = false
    @Published var showSettings = false
    @Published var showWindDown = false

    var weeklyAverageScore: Int? {
        let scores = weekEntries.compactMap { $0.displayableScore }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / scores.count
    }

    func loadData(trackingService: any SleepTrackingReading, healthKitManager: SleepHealthKitManager? = nil) async {
        guard !Task.isCancelled else { return }
        let requestID = UUID()
        loadID = requestID
        lastSleepEntry = nil
        weekEntries = []
        insights = []
        showMorningCheckIn = false
        errorMessage = nil
        isLoading = true
        defer { if loadID == requestID { isLoading = false } }

        do {
            let userID = try await trackingService.currentUserID()
            // Fetch last 7 days
            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate)!
            let entries = try await trackingService.fetchEntries(from: startDate, to: endDate)

            let loadedInsights = try await trackingService.fetchInsights()
            let activeUserID = try await trackingService.currentUserID()
            guard loadID == requestID, !Task.isCancelled, activeUserID == userID else { return }
            let calculator = SleepScoreCalculator()
            weekEntries = entries.filter {
                $0.userId == userID && calculator.isValidForScoring(entry: $0) &&
                $0.wakeTime >= startDate && $0.wakeTime <= endDate
            }.sorted { $0.wakeTime > $1.wakeTime }
            lastSleepEntry = weekEntries.first {
                Calendar.current.isDate($0.wakeTime, inSameDayAs: endDate)
            }

            // Fetch insights
            insights = weekEntries.isEmpty ? [] : loadedInsights

            // Check if should show morning check-in
            if let last = lastSleepEntry,
               last.userRating == nil,
               shouldShowMorningCheckIn(for: last) {
                showMorningCheckIn = true
            }
        } catch {
            guard loadID == requestID, !Task.isCancelled else { return }
            lastSleepEntry = nil
            weekEntries = []
            insights = []
            errorMessage = "Sleep records couldn't be loaded. Pull to refresh or try again."
        }
    }

    func refresh(trackingService: SleepTrackingService, healthKitManager: SleepHealthKitManager) async {
        await refresh(trackingService: trackingService) { _ = try await healthKitManager.syncRecentSleep() }
    }

    func refresh(trackingService: any SleepTrackingReading, sync: @escaping @MainActor () async throws -> Void) async {
        if let refreshTask { await refreshTask.task.value; return }
        let id = UUID()
        // SwiftUI may cancel the pull action during a view update. Keep one screen-owned
        // operation alive until it finishes, the screen disappears, or the account changes.
        let task = Task { @MainActor in
            self.syncErrorMessage = nil
            let owner = try? await trackingService.currentUserID()
            guard !Task.isCancelled else { return }
            guard let owner else {
                await self.loadData(trackingService: trackingService)
                return
            }
            var failure: Error?
            do { try await sync() } catch { failure = error }
            let activeOwner = try? await trackingService.currentUserID()
            guard !Task.isCancelled, activeOwner == owner else { return }
            await self.loadData(trackingService: trackingService)
            let finalOwner = try? await trackingService.currentUserID()
            guard !Task.isCancelled, finalOwner == owner else { return }
            if let failure {
                if case SleepTrackingError.importDateConflict = failure {
                    self.syncErrorMessage = failure.localizedDescription
                } else {
                    self.syncErrorMessage = "Health sleep couldn't be synced. Saved records may be out of date. Try syncing again."
                }
            }
        }
        refreshTask = (id, task)
        await task.value
        if refreshTask?.id == id { refreshTask = nil }
    }

    func cancelRefresh() {
        refreshTask?.task.cancel()
        refreshTask = nil
        loadID = UUID()
        isLoading = false
    }

    func requestHealthKitAuth(healthKitManager: SleepHealthKitManager, trackingService: SleepTrackingService) async {
        await refresh(trackingService: trackingService) {
            try await healthKitManager.requestAuthorization()
            _ = try await healthKitManager.syncRecentSleep()
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

#if DEBUG
/// Synthetic data only; no HealthKit queries, authentication or wellness writes.
@MainActor
final class SleepDashboardUITestReader: SleepTrackingReading {
    private let owner = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private var failedOnce = false
    private var synced = false
    func syncSleep() async throws {
        try await Task.sleep(for: .seconds(2))
        synced = true
    }
    func currentUserID() async throws -> UUID { owner }
    func fetchLatestEntry() async throws -> SleepEntry? { nil }
    func fetchInsights() async throws -> [SleepInsight] { [] }
    func fetchEntries(from startDate: Date, to endDate: Date) async throws -> [SleepEntry] {
        let pullFixture = ProcessInfo.processInfo.arguments.contains("--sleep-pull-sync")
        if pullFixture { try await Task.sleep(for: .milliseconds(200)) }
        if !failedOnce && !pullFixture { failedOnce = true; throw URLError(.notConnectedToInternet) }
        if ProcessInfo.processInfo.arguments.contains("--sleep-session-accuracy") || (pullFixture && synced) {
            let wake = endDate
            let start = wake.addingTimeInterval(-1080 * 60)
            let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
            let samples = [HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                            start: start, end: wake)]
            var full = SleepHealthKitManager.sleepEntry(from: samples, for: Calendar.current.startOfDay(for: wake), owner: owner)!
            full.userRating = 4
            var fragment = SleepHealthKitManager.sleepEntry(from: [HKCategorySample(type: type,
                value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                start: wake.addingTimeInterval(-240*60), end: wake)], for: wake, owner: owner)!
            fragment.notes = "Synthetic earlier feedback"
            // Exercise the same import construction, database coding and reconciliation used by a resync.
            let encoder = PostgrestClient.Configuration.jsonEncoder
            let records = try PostgrestClient.Configuration.jsonDecoder.decode([SleepEntry].self, from: encoder.encode([fragment, full]))
            return SleepEntry.withoutContainedHealthImports(records)
        }
        let wake = endDate
        let record: [String: Any] = ["id": UUID().uuidString, "user_id": owner.uuidString,
            "date": String(wake.ISO8601Format().prefix(10)), "source": "healthkit",
            "bedtime": wake.addingTimeInterval(-8 * 3600).ISO8601Format(), "wake_time": wake.ISO8601Format(),
            "time_in_bed_minutes": 480, "time_asleep_minutes": 450, "deep_sleep_minutes": 90,
            "rem_sleep_minutes": 100, "light_sleep_minutes": 260, "awake_minutes": 30, "user_rating": 4,
            "created_at": wake.ISO8601Format(), "updated_at": wake.ISO8601Format()]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return [try decoder.decode(SleepEntry.self, from: JSONSerialization.data(withJSONObject: record))]
    }
}

struct SleepDashboardUITestView: View {
    @State private var reader = SleepDashboardUITestReader()
    var body: some View { SleepDashboardView(trackingReader: reader, syncSleep: { try await reader.syncSleep() }) }
}

#endif
