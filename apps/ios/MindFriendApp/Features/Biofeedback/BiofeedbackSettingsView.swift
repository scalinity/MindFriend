// BiofeedbackSettingsView.swift
// MindFriendApp
// Settings for biofeedback adaptation

import SwiftUI
import WatchConnectivity

struct BiofeedbackSettingsView: View {
    @StateObject private var viewModel: BiofeedbackSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    init(biofeedbackService: BiofeedbackService) {
        _viewModel = StateObject(wrappedValue: BiofeedbackSettingsViewModel(
            biofeedbackService: biofeedbackService
        ))
    }

    var body: some View {
        List {
            // Biofeedback Toggle
            Section {
                Toggle(isOn: $viewModel.isBiofeedbackEnabled) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Biofeedback")
                            Text("Adapt exercises based on heart rate")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Biofeedback")
            } footer: {
                Text("When enabled, breathing exercises will automatically adjust their pace based on your real-time heart rate data from Apple Watch.")
            }

            // Apple Watch Status
            Section {
                HStack {
                    Label("Apple Watch", systemImage: "applewatch")
                    Spacer()
                    connectionStatusBadge
                }

                if viewModel.isWatchConnected {
                    HStack {
                        Label("Last Sync", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        Text(viewModel.lastSyncText)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Watch Connection")
            }

            // Baseline Section
            Section {
                if let baseline = viewModel.baseline {
                    baselineDataRows(baseline)
                } else {
                    HStack {
                        Text("No baseline calculated")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }

                Button {
                    Task {
                        await viewModel.recalculateBaseline()
                    }
                } label: {
                    HStack {
                        Label("Recalculate Baseline", systemImage: "arrow.clockwise")
                        Spacer()
                        if viewModel.isCalculatingBaseline {
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isCalculatingBaseline)
            } header: {
                Text("Your Baseline")
            } footer: {
                Text("Your baseline is calculated from the last 14 days of heart rate data. A reliable baseline needs at least 10 samples.")
            }

            // Adaptation Mode
            Section {
                Picker("Adaptation Mode", selection: $viewModel.adaptationMode) {
                    ForEach(AdaptationMode.allCases, id: \.self) { mode in
                        VStack(alignment: .leading) {
                            Text(mode.displayName)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.menu)

                adaptationModeDescription
            } header: {
                Text("Adaptation Behavior")
            }

            // Data Sync Settings
            Section {
                Toggle(isOn: $viewModel.autoSyncHealthKit) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-sync HealthKit")
                            Text("Sync heart rate data daily")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "heart.text.square")
                    }
                }

                Button {
                    Task {
                        await viewModel.syncNow()
                    }
                } label: {
                    HStack {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if viewModel.isSyncing {
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isSyncing)
            } header: {
                Text("Data Sync")
            }

            // Session History
            Section {
                NavigationLink {
                    BiofeedbackHistoryView(biofeedbackService: viewModel.biofeedbackService)
                } label: {
                    Label("Session History", systemImage: "clock.arrow.circlepath")
                }

                if viewModel.totalSessions > 0 {
                    HStack {
                        Text("Total Sessions")
                        Spacer()
                        Text("\(viewModel.totalSessions)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("History")
            }
        }
        .navigationTitle("Biofeedback Settings")
        .task {
            await viewModel.load()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
    }

    // MARK: - Connection Status Badge

    private var connectionStatusBadge: some View {
        Group {
            if viewModel.isWatchConnected {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Connected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Not Connected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Baseline Data Rows

    @ViewBuilder
    private func baselineDataRows(_ baseline: BiofeedbackBaseline) -> some View {
        HStack {
            Text("Resting Heart Rate")
            Spacer()
            if let hr = baseline.restingHeartRate {
                Text("\(Int(hr)) BPM")
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .foregroundStyle(.secondary)
            }
        }

        HStack {
            Text("Stress Threshold")
            Spacer()
            if let threshold = baseline.stressHRThreshold {
                Text("\(Int(threshold)) BPM")
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .foregroundStyle(.secondary)
            }
        }

        HStack {
            Text("Resting HRV")
            Spacer()
            if let hrv = baseline.restingHRV {
                Text("\(Int(hrv)) ms")
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .foregroundStyle(.secondary)
            }
        }

        HStack {
            Text("Confidence")
            Spacer()
            confidenceBadge(baseline.confidenceScore)
        }

        HStack {
            Text("Samples")
            Spacer()
            Text("\(baseline.sampleCount)")
                .foregroundStyle(.secondary)
        }
    }

    private func confidenceBadge(_ score: Double) -> some View {
        let color: Color
        let label: String

        if score >= 0.8 {
            color = .green
            label = "High"
        } else if score >= 0.5 {
            color = .yellow
            label = "Medium"
        } else {
            color = .orange
            label = "Low"
        }

        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Adaptation Mode Description

    private var adaptationModeDescription: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.adaptationMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - View Model

@MainActor
final class BiofeedbackSettingsViewModel: ObservableObject {
    // MARK: - Published State

    @Published var isBiofeedbackEnabled = true
    @Published var isWatchConnected = false
    @Published var lastSyncText = "Never"
    @Published var baseline: BiofeedbackBaseline?
    @Published var adaptationMode: AdaptationMode = .auto
    @Published var autoSyncHealthKit = true
    @Published var totalSessions = 0
    @Published var isCalculatingBaseline = false
    @Published var isSyncing = false
    @Published var showError = false
    @Published var errorMessage: String?

    // MARK: - Dependencies

    let biofeedbackService: BiofeedbackService
    private let heartRateMonitor = HeartRateMonitor()

    // MARK: - Init

    init(biofeedbackService: BiofeedbackService) {
        self.biofeedbackService = biofeedbackService
    }

    // MARK: - Load

    func load() async {
        // Fetch baseline
        await biofeedbackService.fetchBaseline()
        baseline = biofeedbackService.baseline

        // Check Watch connection via WCSession
        #if os(iOS)
        if WCSession.isSupported() {
            let session = WCSession.default
            isWatchConnected = session.isPaired && session.isWatchAppInstalled
        }
        #endif

        // Fetch session count
        do {
            let sessions = try await biofeedbackService.fetchRecentSessions(limit: 100)
            totalSessions = sessions.count
        } catch {
            // Don't log error details - may contain PHI
            print("Failed to fetch sessions")
        }

        // Load preferences
        loadPreferences()
    }

    private func loadPreferences() {
        isBiofeedbackEnabled = UserDefaults.standard.bool(forKey: "biofeedback_enabled")
        if !UserDefaults.standard.contains(key: "biofeedback_enabled") {
            isBiofeedbackEnabled = true // Default on
        }

        autoSyncHealthKit = UserDefaults.standard.bool(forKey: "biofeedback_auto_sync")
        if !UserDefaults.standard.contains(key: "biofeedback_auto_sync") {
            autoSyncHealthKit = true
        }

        if let modeString = UserDefaults.standard.string(forKey: "biofeedback_adaptation_mode"),
           let mode = AdaptationMode(rawValue: modeString) {
            adaptationMode = mode
        }

        if let lastSync = UserDefaults.standard.object(forKey: "biofeedback_last_sync") as? Date {
            lastSyncText = formatRelativeDate(lastSync)
        }
    }

    // MARK: - Actions

    func recalculateBaseline() async {
        isCalculatingBaseline = true

        do {
            _ = try await biofeedbackService.calculateBaseline()
            baseline = biofeedbackService.baseline
        } catch let error as BiofeedbackError {
            // Use safe error description (no PHI)
            errorMessage = error.errorDescription
            showError = true
        } catch {
            // Generic fallback for unexpected errors
            errorMessage = "Unable to calculate baseline. Please try again."
            showError = true
        }

        isCalculatingBaseline = false
    }

    func syncNow() async {
        isSyncing = true

        do {
            // Fetch HealthKit data in parallel
            async let hrSamplesTask = heartRateMonitor.fetchRecentHeartRateData(hours: 24 * 14)
            async let hrvSamplesTask = heartRateMonitor.fetchHRVData(days: 14)
            let hrSamples = try await hrSamplesTask
            let hrvSamples = try await hrvSamplesTask

            // Convert to storage format
            guard let userId = UUID(uuidString: UserDefaults.standard.string(forKey: "user_id") ?? "") else {
                throw BiofeedbackError.fetchFailed("UID-001")
            }

            let hrStorageSamples = heartRateMonitor.convertToStorageSamples(
                heartRateSamples: hrSamples,
                userId: userId
            )
            let hrvStorageSamples = heartRateMonitor.convertToStorageSamples(
                hrvSamples: hrvSamples,
                userId: userId
            )

            // Sync to server
            try await biofeedbackService.syncHealthKitHeartRate(samples: hrStorageSamples)
            try await biofeedbackService.syncHealthKitHRV(samples: hrvStorageSamples)

            // Update last sync time
            UserDefaults.standard.set(Date(), forKey: "biofeedback_last_sync")
            lastSyncText = "Just now"

            // Recalculate baseline with new data
            await recalculateBaseline()

        } catch let error as BiofeedbackError {
            // Use safe error description (no PHI)
            errorMessage = error.errorDescription
            showError = true
        } catch {
            // Generic fallback for unexpected errors
            errorMessage = "Unable to sync data. Please try again."
            showError = true
        }

        isSyncing = false
    }

    // MARK: - Helpers

    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - UserDefaults Extension

extension UserDefaults {
    func contains(key: String) -> Bool {
        object(forKey: key) != nil
    }
}

// MARK: - Biofeedback History View

struct BiofeedbackHistoryView: View {
    let biofeedbackService: BiofeedbackService
    @State private var sessions: [BiofeedbackSession] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions Yet",
                    systemImage: "heart.text.square",
                    description: Text("Complete a biofeedback exercise to see your history here.")
                )
            } else {
                List(sessions) { session in
                    sessionRow(session)
                }
            }
        }
        .navigationTitle("Session History")
        .task {
            await loadSessions()
        }
    }

    private func sessionRow(_ session: BiofeedbackSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.startedAt, style: .date)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if let duration = session.durationSeconds {
                    Text(formatDuration(duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Label(session.adaptationMode.displayName, systemImage: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if session.wasExtended {
                    Label("Extended", systemImage: "plus.circle")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func loadSessions() async {
        do {
            sessions = try await biofeedbackService.fetchRecentSessions(limit: 50)
        } catch {
            // Don't log error details - may contain PHI
            print("Failed to load sessions")
        }
        isLoading = false
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
