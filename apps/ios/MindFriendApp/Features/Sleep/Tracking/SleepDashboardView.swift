import SwiftUI
#if DEBUG
import HealthKit
import Supabase
#endif

/// Main sleep tracking dashboard showing recent sleep, trends, and quick actions
struct SleepDashboardView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: SleepDashboardViewModel
    @State private var showManualEntry = false
    @State private var isVisible = false
    @State private var morningCheckInEntryID: UUID?
    private let trackingReader: (any SleepTrackingReading)?
    private let syncSleep: (() async throws -> Void)?
    private let automaticSync: (() async throws -> Void)?

    init(trackingReader: (any SleepTrackingReading)? = nil, syncSleep: (() async throws -> Void)? = nil,
         automaticSync: (() async throws -> Void)? = nil, preferences: UserDefaults = .standard) {
        self.trackingReader = trackingReader
        self.syncSleep = syncSleep
        self.automaticSync = automaticSync
        _viewModel = StateObject(wrappedValue: SleepDashboardViewModel(preferences: preferences))
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
                    if viewModel.isImportingHistory {
                        ProgressView("Importing sleep history…")
                            .accessibilityIdentifier("sleep.importingHistory")
                    }
                    // Last Night's Sleep Summary
                    if let lastEntry = viewModel.lastSleepEntry {
                        lastNightSection(lastEntry)
                    } else if viewModel.isLoading {
                        ProgressView("Loading sleep…")
                            .frame(maxWidth: .infinity, minHeight: 160)
                            .accessibilityIdentifier("sleep.loading")
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
            .sheet(isPresented: $viewModel.showMorningCheckIn, onDismiss: {
                if let entry = viewModel.lastSleepEntry, entry.id == morningCheckInEntryID {
                    viewModel.skipMorningCheckIn(for: entry)
                }
                morningCheckInEntryID = nil
                if isVisible, scenePhase == .active { Task { await syncConnectedSleep() } }
            }) {
                if let entry = viewModel.lastSleepEntry {
                    MorningCheckInView(entry: entry) { viewModel.skipMorningCheckIn(for: entry) }
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
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false; viewModel.cancelRefresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, isVisible, !viewModel.showMorningCheckIn,
                   !showManualEntry, !viewModel.showSettings, !viewModel.showWindDown {
                    Task { await syncConnectedSleep() }
                }
            }
            .onChange(of: viewModel.showMorningCheckIn) { _, isPresented in
                if isPresented { morningCheckInEntryID = viewModel.lastSleepEntry?.id }
            }
            .task(id: appState.currentUser?.id) {
                if trackingReader == nil { viewModel.prepareForOwner(appState.currentUser?.id) }
                else { viewModel.cancelRefresh() }
                if trackingReader == nil || automaticSync != nil {
                    await syncConnectedSleep()
                } else {
                    await viewModel.loadData(trackingService: trackingReader ?? dependencies.sleepTrackingService)
                }
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

    private func syncConnectedSleep() async {
        if let automaticSync {
            await viewModel.refresh(trackingService: trackingReader ?? dependencies.sleepTrackingService, sync: automaticSync)
        } else if trackingReader == nil {
            let manager = dependencies.sleepHealthKitManager
            await viewModel.refresh(trackingService: dependencies.sleepTrackingService, sync: {
                await manager.updateAuthorizationStatus()
                try Task.checkCancellation()
                if manager.isAuthorized { _ = try await manager.syncRecentSleep() }
            }, history: { started in
                if manager.isAuthorized { try await manager.syncAvailableHistory(retryConflicts: false, onBatchStart: started) }
            })
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
    @Published var isLoading = true
    @Published var isImportingHistory = false
    @Published var errorMessage: String?
    @Published var syncErrorMessage: String?
    private var loadedOwnerID: UUID?
    private var loadID = UUID()
    private var refreshTask: (id: UUID, task: Task<Void, Never>)?
    private var historyTask: (id: UUID, task: Task<Void, Never>)?
    private let preferences: UserDefaults
    init(preferences: UserDefaults = .standard) { self.preferences = preferences }

    func skipMorningCheckIn(for entry: SleepEntry) {
        preferences.set(entry.id.uuidString, forKey: "sleep.checkin.skipped." + entry.userId.uuidString.lowercased())
        if lastSleepEntry?.id == entry.id, lastSleepEntry?.userId == entry.userId { showMorningCheckIn = false }
    }
    @Published var showMorningCheckIn = false
    @Published var showSettings = false
    @Published var showWindDown = false

    var weeklyAverageScore: Int? {
        let scores = weekEntries.compactMap { $0.displayableScore }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / scores.count
    }

    func loadData(trackingService: any SleepTrackingReading, healthKitManager: SleepHealthKitManager? = nil,
                  preservingContent: Bool = false) async {
        guard !Task.isCancelled else { return }
        let requestID = UUID()
        loadID = requestID
        if !preservingContent {
            lastSleepEntry = nil
            weekEntries = []
            insights = []
            showMorningCheckIn = false
        }
        errorMessage = nil
        isLoading = true
        defer { if loadID == requestID { isLoading = false } }

        do {
            let userID = try await trackingService.currentUserID()
            guard loadID == requestID, !Task.isCancelled else { return }
            if loadedOwnerID != userID {
                lastSleepEntry = nil
                weekEntries = []
                insights = []
                showMorningCheckIn = false
            }
            loadedOwnerID = userID
            // Fetch last 7 days
            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: endDate))!
            let entries = try await trackingService.fetchEntries(from: startDate, to: endDate)

            let loadedInsights = try await trackingService.fetchInsights()
            let activeUserID = try await trackingService.currentUserID()
            guard loadID == requestID, !Task.isCancelled, activeUserID == userID else { return }
            // A form can open while the source read is suspended. Leave its draft intact;
            // dismissing it triggers a fresh read through the existing screen refresh.
            if preservingContent, showMorningCheckIn { return }
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
            if preservingContent, showMorningCheckIn {
                errorMessage = "Sleep records couldn't be loaded. Pull to refresh or try again."
                return
            }
            lastSleepEntry = nil
            weekEntries = []
            insights = []
            errorMessage = "Sleep records couldn't be loaded. Pull to refresh or try again."
        }
    }

    func refresh(trackingService: SleepTrackingService, healthKitManager: SleepHealthKitManager) async {
        await refresh(trackingService: trackingService, sync: { _ = try await healthKitManager.syncRecentSleep() },
            history: { try await healthKitManager.syncAvailableHistory(onBatchStart: $0) })
    }

    func refresh(trackingService: any SleepTrackingReading, sync: @escaping @MainActor () async throws -> Void,
                 history: (@MainActor (@escaping @MainActor () -> Void) async throws -> Void)? = nil) async {
        guard !Task.isCancelled else { return }
        if let refreshTask { await refreshTask.task.value; return }
        let id = UUID()
        isLoading = true
        // SwiftUI may cancel the pull action during a view update. Keep one screen-owned
        // operation alive until it finishes, the screen disappears, or the account changes.
        let task = Task { @MainActor in
            defer {
                if self.refreshTask?.id == id { self.isLoading = false }
            }
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
            await self.loadData(trackingService: trackingService, preservingContent: true)
            let finalOwner = try? await trackingService.currentUserID()
            guard !Task.isCancelled, finalOwner == owner else { return }
            if let failure {
                if case SleepTrackingError.importDateConflict = failure {
                    self.syncErrorMessage = failure.localizedDescription
                } else {
                    self.syncErrorMessage = "Health sleep couldn't be synced. Saved records may be out of date. Try syncing again."
                }
            }
            var historyAllowed = failure == nil
            if let failure, case SleepTrackingError.importDateConflict = failure { historyAllowed = true }
            if let history, self.historyTask == nil, historyAllowed {
                let historyID = UUID()
                let task = Task { @MainActor in
                    defer {
                        if self.historyTask?.id == historyID {
                            self.isImportingHistory = false
                            self.historyTask = nil
                        }
                    }
                    do { try await history {
                        guard self.historyTask?.id == historyID, !Task.isCancelled else { return }
                        self.isImportingHistory = true
                    } } catch {
                        let activeOwner = try? await trackingService.currentUserID()
                        guard !Task.isCancelled, activeOwner == owner else { return }
                        if case SleepTrackingError.importDateConflict = error {
                            self.syncErrorMessage = error.localizedDescription
                        } else {
                            self.syncErrorMessage = "Some older sleep records couldn't be imported. Try syncing again."
                        }
                    }
                }
                self.historyTask = (historyID, task)
            }
        }
        refreshTask = (id, task)
        await task.value
        if refreshTask?.id == id { refreshTask = nil }
    }

    func prepareForOwner(_ owner: UUID?) {
        cancelRefresh()
        guard loadedOwnerID != owner else { return }
        loadedOwnerID = owner
        lastSleepEntry = nil
        weekEntries = []
        insights = []
        showMorningCheckIn = false
        errorMessage = nil
        syncErrorMessage = nil
        isLoading = true
    }

    func cancelRefresh() {
        refreshTask?.task.cancel()
        refreshTask = nil
        historyTask?.task.cancel()
        historyTask = nil
        loadID = UUID()
        isLoading = lastSleepEntry == nil
        isImportingHistory = false
    }

    func requestHealthKitAuth(healthKitManager: SleepHealthKitManager, trackingService: SleepTrackingService) async {
        await refresh(trackingService: trackingService, sync: {
            try await healthKitManager.requestAuthorization()
            _ = try await healthKitManager.syncRecentSleep()
        }, history: { try await healthKitManager.syncAvailableHistory(onBatchStart: $0) })
    }

    private func shouldShowMorningCheckIn(for entry: SleepEntry) -> Bool {
        let now = Date()
        let hoursSinceWake = now.timeIntervalSince(entry.wakeTime) / 3600
        let skipped = preferences.string(forKey: "sleep.checkin.skipped." + entry.userId.uuidString.lowercased())
        return skipped != entry.id.uuidString && hoursSinceWake >= 0 && hoursSinceWake <= 2
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
    private var syncCount = 0
    func syncSleep() async throws {
        let automatic = ProcessInfo.processInfo.arguments.contains("--sleep-auto-sync")
        try await Task.sleep(for: .seconds(automatic ? 5 : 2))
        syncCount += 1
    }
    func currentUserID() async throws -> UUID { owner }
    func fetchLatestEntry() async throws -> SleepEntry? { nil }
    func fetchInsights() async throws -> [SleepInsight] { [] }
    func fetchEntries(from startDate: Date, to endDate: Date) async throws -> [SleepEntry] {
        let automatic = ProcessInfo.processInfo.arguments.contains("--sleep-auto-sync")
        let checkIn = ProcessInfo.processInfo.arguments.contains("--sleep-checkin-skip")
        let pullFixture = ProcessInfo.processInfo.arguments.contains("--sleep-pull-sync") || automatic
        if pullFixture { try await Task.sleep(for: .milliseconds(200)) }
        if !failedOnce && !pullFixture && !checkIn { failedOnce = true; throw URLError(.notConnectedToInternet) }
        if ProcessInfo.processInfo.arguments.contains("--sleep-session-accuracy") || (pullFixture && syncCount > 0 && !checkIn) {
            let wake = endDate
            let start = wake.addingTimeInterval(-Double(automatic && syncCount > 1 ? 1140 : 1080) * 60)
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
        var record: [String: Any] = ["id": checkIn ? "22222222-2222-4222-8222-222222222222" : UUID().uuidString, "user_id": owner.uuidString,
            "date": String(wake.ISO8601Format().prefix(10)), "source": "healthkit",
            "bedtime": wake.addingTimeInterval(-8 * 3600).ISO8601Format(), "wake_time": wake.ISO8601Format(),
            "time_in_bed_minutes": 480, "time_asleep_minutes": 450, "deep_sleep_minutes": 90,
            "rem_sleep_minutes": 100, "light_sleep_minutes": 260, "awake_minutes": 30, "user_rating": 4,
            "created_at": wake.ISO8601Format(), "updated_at": wake.ISO8601Format()]
        if checkIn { record["user_rating"] = NSNull() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return [try decoder.decode(SleepEntry.self, from: JSONSerialization.data(withJSONObject: record))]
    }
}

struct SleepDashboardUITestView: View {
    @State private var reader = SleepDashboardUITestReader()
    private var automaticSync: (() async throws -> Void)? {
        guard ProcessInfo.processInfo.arguments.contains("--sleep-auto-sync") else { return nil }
        return { try await reader.syncSleep() }
    }
    private var preferences: UserDefaults {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--sleep-test-suite"), index + 1 < args.count else { return .standard }
        return UserDefaults(suiteName: args[index + 1])!
    }
    var body: some View {
        SleepDashboardView(trackingReader: reader, syncSleep: { try await reader.syncSleep() },
            automaticSync: automaticSync, preferences: preferences)
    }
}

#endif
