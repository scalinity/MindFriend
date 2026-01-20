import SwiftUI

/// Settings view for smart notification configuration
struct SmartNotificationSettingsView: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel = SmartNotificationSettingsViewModel()

    var body: some View {
        List {
            // MARK: - Main Toggle
            Section {
                Toggle("Smart Notifications", isOn: $viewModel.isEnabled)
                    .tint(.accentColor)
            } header: {
                Text("Enable")
            } footer: {
                Text("Smart notifications learn when you're most likely to engage and deliver messages at optimal times.")
            }

            if viewModel.isEnabled {
                // MARK: - Frequency Settings
                Section {
                    Picker("Frequency", selection: $viewModel.frequency) {
                        Text("Minimal").tag(NotificationFrequency.minimal)
                        Text("Moderate").tag(NotificationFrequency.moderate)
                        Text("Frequent").tag(NotificationFrequency.frequent)
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Max per day")
                            Spacer()
                            Text("\(viewModel.maxPerDay)")
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(viewModel.maxPerDay) },
                                set: { viewModel.maxPerDay = Int($0) }
                            ),
                            in: 1...10,
                            step: 1
                        )
                        .tint(.accentColor)
                    }
                } header: {
                    Text("Delivery Preferences")
                } footer: {
                    frequencyDescription
                }

                // MARK: - Notification Types
                Section {
                    ForEach(SmartNotificationType.allCases, id: \.self) { type in
                        Toggle(type.displayName, isOn: viewModel.bindingForType(type))
                            .tint(.accentColor)
                    }
                } header: {
                    Text("Notification Types")
                } footer: {
                    Text("Choose which types of notifications you want to receive.")
                }

                // MARK: - Focus & Quiet Hours
                Section {
                    Toggle("Sync with Sleep Focus", isOn: $viewModel.syncQuietHoursWithSleep)
                        .tint(.accentColor)

                    if !viewModel.focusModeAvailable {
                        Toggle("Manual Do Not Disturb", isOn: $viewModel.manualDndEnabled)
                            .tint(.accentColor)
                    }
                } header: {
                    Text("Focus & Quiet Hours")
                } footer: {
                    if viewModel.focusModeAvailable {
                        Text("Notifications are automatically suppressed during Sleep Focus mode.")
                    } else {
                        Text("Your device doesn't support automatic Focus detection. Use manual DND to suppress notifications.")
                    }
                }

                // MARK: - Weekly Stats
                if let stats = viewModel.weeklyStats {
                    Section {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Engagement Rate")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("\(Int(stats.rate * 100))%")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                            }

                            Spacer()

                            VStack(alignment: .trailing) {
                                Text("This Week")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 4) {
                                    Text("\(stats.opened)")
                                        .foregroundStyle(.green)
                                    Text("/")
                                        .foregroundStyle(.secondary)
                                    Text("\(stats.delivered)")
                                }
                                .font(.title2)
                                .fontWeight(.semibold)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Statistics")
                    } footer: {
                        Text("Shows how many notifications you opened out of those delivered this week.")
                    }
                }

                // MARK: - Beta Features
                Section {
                    Toggle("Enable Beta Features", isOn: $viewModel.betaOptIn)
                        .tint(.accentColor)
                } header: {
                    Text("Beta")
                } footer: {
                    Text("Get early access to new notification features. These may be experimental and subject to change.")
                }

                // MARK: - Actions
                Section {
                    Button {
                        viewModel.sendTestNotification()
                    } label: {
                        HStack {
                            Image(systemName: "bell.badge")
                            Text("Send Test Notification")
                        }
                    }
                    .disabled(viewModel.isSendingTest)

                    Button(role: .destructive) {
                        viewModel.resetToDefaults()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to Defaults")
                        }
                    }
                } header: {
                    Text("Actions")
                }
            }
        }
        .navigationTitle("Smart Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.configure(
                smartNotificationService: container.smartNotificationService,
                dataService: container.supabaseDataService
            )
        }
        .onChange(of: viewModel.isEnabled) { _, _ in viewModel.saveSettings() }
        .onChange(of: viewModel.frequency) { _, _ in viewModel.saveSettings() }
        .onChange(of: viewModel.maxPerDay) { _, _ in viewModel.saveSettings() }
        .onChange(of: viewModel.syncQuietHoursWithSleep) { _, _ in viewModel.saveSettings() }
        .onChange(of: viewModel.manualDndEnabled) { _, _ in viewModel.saveSettings() }
        .onChange(of: viewModel.betaOptIn) { _, _ in viewModel.saveSettings() }
        .alert("Test Sent", isPresented: $viewModel.showTestSentAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("A test notification has been scheduled. It should arrive within a few seconds.")
        }
    }

    @ViewBuilder
    private var frequencyDescription: some View {
        switch viewModel.frequency {
        case .minimal:
            Text("Only the most important notifications. Higher engagement threshold (70%).")
        case .moderate:
            Text("Balanced notifications. Standard engagement threshold (60%).")
        case .frequent:
            Text("More notifications allowed. Lower engagement threshold (50%).")
        }
    }
}

// MARK: - View Model

@MainActor
final class SmartNotificationSettingsViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isEnabled: Bool = true
    @Published var frequency: NotificationFrequency = .moderate
    @Published var maxPerDay: Int = SmartNotificationDefaults.maxPerDay
    @Published var enabledTypes: Set<SmartNotificationType> = Set(SmartNotificationType.allCases)
    @Published var syncQuietHoursWithSleep: Bool = true
    @Published var manualDndEnabled: Bool = false
    @Published var betaOptIn: Bool = false

    @Published var weeklyStats: EngagementStats?
    @Published var isSendingTest: Bool = false
    @Published var showTestSentAlert: Bool = false
    @Published var focusModeAvailable: Bool = true

    // MARK: - Private Properties

    private var smartNotificationService: SmartNotificationService?
    private var dataService: SupabaseDataService?
    private var saveTask: Task<Void, Never>?

    // MARK: - Configuration

    func configure(smartNotificationService: SmartNotificationService, dataService: SupabaseDataService) {
        self.smartNotificationService = smartNotificationService
        self.dataService = dataService

        // Check Focus Mode availability
        if #available(iOS 18.0, *) {
            focusModeAvailable = true
        } else {
            focusModeAvailable = false
        }

        loadSettings()
        loadStats()
    }

    // MARK: - Settings Management

    func loadSettings() {
        Task {
            guard let dataService = dataService else { return }

            do {
                let settings = try await dataService.getUserSettings()

                isEnabled = settings.smartNotificationsEnabled ?? true
                maxPerDay = settings.notificationMaxPerDay ?? SmartNotificationDefaults.maxPerDay
                syncQuietHoursWithSleep = settings.syncQuietHoursWithSleep ?? true
                betaOptIn = settings.betaNotificationsOptIn ?? false
                manualDndEnabled = settings.manualDndEnabled ?? false

                if let frequencyStr = settings.notificationFrequency,
                   let freq = NotificationFrequency(rawValue: frequencyStr) {
                    frequency = freq
                }

                if let types = settings.enabledNotificationTypes {
                    enabledTypes = Set(types.compactMap { SmartNotificationType(rawValue: $0) })
                }
            } catch {
                // Use defaults on error
            }
        }
    }

    func saveSettings() {
        // Debounce saves
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            await performSave()
        }
    }

    private func performSave() async {
        guard let dataService = dataService else { return }

        do {
            var settings = try await dataService.getUserSettings()

            settings.smartNotificationsEnabled = isEnabled
            settings.notificationMaxPerDay = maxPerDay
            settings.notificationFrequency = frequency.rawValue
            settings.enabledNotificationTypes = enabledTypes.map { $0.rawValue }
            settings.syncQuietHoursWithSleep = syncQuietHoursWithSleep
            settings.betaNotificationsOptIn = betaOptIn
            settings.manualDndEnabled = manualDndEnabled

            try await dataService.updateUserSettings(settings)

            // Update service configuration
            smartNotificationService?.configure(settings: settings)
        } catch {
            // Silent fail - settings will be saved on next attempt
        }
    }

    // MARK: - Stats

    func loadStats() {
        Task {
            await smartNotificationService?.updateWeeklyStats()

            if let stats = try? await dataService?.fetchNotificationEngagementStats() {
                weeklyStats = stats
            }
        }
    }

    // MARK: - Type Binding Helper

    func bindingForType(_ type: SmartNotificationType) -> Binding<Bool> {
        Binding(
            get: { self.enabledTypes.contains(type) },
            set: { enabled in
                if enabled {
                    self.enabledTypes.insert(type)
                } else {
                    self.enabledTypes.remove(type)
                }
                self.saveSettings()
            }
        )
    }

    // MARK: - Actions

    func sendTestNotification() {
        guard let service = smartNotificationService else { return }

        isSendingTest = true

        Task {
            do {
                try await service.scheduleNotification(
                    type: .reminder,
                    title: "Test Notification",
                    body: "This is a test of your smart notification settings.",
                    priority: .normal
                )
                showTestSentAlert = true
            } catch {
                // Silent fail
            }

            isSendingTest = false
        }
    }

    func resetToDefaults() {
        isEnabled = true
        frequency = .moderate
        maxPerDay = SmartNotificationDefaults.maxPerDay
        enabledTypes = Set(SmartNotificationType.allCases)
        syncQuietHoursWithSleep = true
        manualDndEnabled = false
        betaOptIn = false

        saveSettings()
    }

    deinit {
        saveTask?.cancel()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SmartNotificationSettingsView()
            .environmentObject(DependencyContainer.preview)
    }
}
