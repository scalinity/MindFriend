import SwiftUI
import UserNotifications

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showEditProfile = false
    @State private var showSubscription = false

    var body: some View {
        NavigationStack {
            List {
                // Profile header
                Section {
                    Button {
                        showEditProfile = true
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(Color.accentColor)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(appState.currentUser?.displayName ?? "User")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)

                                Text("@\(appState.currentUser?.handle ?? "")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if appState.entitlements.tier == .premium {
                                    Label("Premium", systemImage: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                }
                            }

                            Spacer()

                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Stats
                Section("Stats") {
                    HStack {
                        ProfileStatItem(value: "\(appState.currentUser?.stats?.currentStreakDays ?? 0)", label: "Streak")
                        Divider()
                        ProfileStatItem(value: "\(appState.currentUser?.stats?.totalQuestsCompleted ?? 0)", label: "Quests")
                        Divider()
                        ProfileStatItem(value: "\(appState.currentUser?.badges?.count ?? 0)", label: "Badges")
                    }
                    .padding(.vertical, 8)
                }

                // Progress
                Section("Progress") {
                    NavigationLink {
                        AchievementsView()
                            .environmentObject(container.achievementService)
                    } label: {
                        Label("Achievements", systemImage: "trophy.fill")
                    }

                    NavigationLink {
                        CertificatesListView()
                    } label: {
                        Label("Certificates", systemImage: "checkmark.seal.fill")
                    }

                    NavigationLink {
                        NarrativeListView(dataService: container.supabaseDataService)
                    } label: {
                        Label("My Stories", systemImage: "book.closed")
                    }
                }

                // Features
                Section("Features") {
                    NavigationLink {
                        CirclesListView()
                    } label: {
                        Label {
                            Text("Circles")
                        } icon: {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 14))
                        }
                    }

                    NavigationLink {
                        SleepTabView(contentIdToPlay: .constant(nil))
                    } label: {
                        Label("Sleep", systemImage: "moon.fill")
                    }

                    NavigationLink {
                        ForYouView()
                    } label: {
                        Label("For You", systemImage: "sparkles")
                    }
                }

                // Social
                Section("Social") {
                    NavigationLink {
                        PartnerModeView()
                    } label: {
                        Label("Partner Mode", systemImage: "person.2.fill")
                    }

                    NavigationLink {
                        FamilyHubView()
                    } label: {
                        Label("Family", systemImage: "figure.2.and.child.holdinghands")
                    }
                }

                // Professional / Therapist
                Section("Professional") {
                    NavigationLink {
                        TherapistApplicationView()
                    } label: {
                        Label("Become a Therapist/Coach", systemImage: "person.badge.plus")
                    }
                }

                // Creator Studio
                // TODO: Uncomment when CreatorService is integrated (Spec 13)
                // if container.creatorService.creatorProfile != nil {
                //     Section("Creator Studio") {
                //         NavigationLink {
                //             CreatorDashboardView()
                //                 .environmentObject(container.creatorService)
                //         } label: {
                //             Label("Creator Studio", systemImage: "sparkles")
                //         }
                //     }
                // }

                // Settings
                Section("Settings") {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell.fill")
                    }

                    NavigationLink {
                        AIPreferencesView()
                    } label: {
                        Label("AI Preferences", systemImage: "brain")
                    }

                    NavigationLink {
                        PrivacySettingsView()
                    } label: {
                        Label("Privacy", systemImage: "lock.fill")
                    }

                    NavigationLink {
                        PrivacyLockSettingsView()
                    } label: {
                        Label("App Lock", systemImage: "faceid")
                    }

                    NavigationLink {
                        VaultListView()
                            .environmentObject(container.vaultViewModel)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Private Vault")
                                Text("Encrypted, device-only journal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "lock.shield.fill")
                        }
                    }

                    NavigationLink {
                        MemorySettingsView()
                    } label: {
                        Label("AI Memory", systemImage: "brain.head.profile")
                    }

                    NavigationLink {
                        CompanionMemoryView()
                    } label: {
                        Label("Memory Vault", systemImage: "archivebox.fill")
                    }

                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }

                    NavigationLink {
                        LanguageSettingsView()
                            .environmentObject(container.localizationService)
                    } label: {
                        Label("Language", systemImage: "globe")
                    }

                    NavigationLink {
                        ProactiveSettingsView()
                    } label: {
                        Label("Proactive Check-ins", systemImage: "sparkles")
                    }

                    NavigationLink {
                        SOSSettingsView()
                    } label: {
                        Label("SOS Panic Button", systemImage: "heart.fill")
                            .foregroundStyle(.red)
                    }

                    NavigationLink {
                        RecoveryModeSettingsView()
                    } label: {
                        Label("Recovery Mode", systemImage: "heart.circle.fill")
                            .foregroundStyle(.pink)
                    }

                    NavigationLink {
                        OurApproachView()
                    } label: {
                        Label("Our Approach", systemImage: "checkmark.seal.fill")
                    }
                }

                // Premium / Subscription
                Section {
                    if appState.entitlements.tier == .free {
                        Button {
                            showSubscription = true
                        } label: {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                Text("Upgrade to Premium")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Button {
                            showSubscription = true
                        } label: {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Premium")
                                        .fontWeight(.semibold)
                                    Text("Manage subscription")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Data
                Section("Data") {
                    NavigationLink {
                        DataExportView()
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Account", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }

                // Support
                Section("Support") {
                    Button {
                        appState.showCrisisResources = true
                    } label: {
                        Label("Crisis Resources", systemImage: "heart.text.square.fill")
                            .foregroundStyle(.red)
                    }

                    Link(destination: URL(string: "mailto:support@mindfriend.app")!) {
                        Label("Contact Support", systemImage: "envelope")
                    }

                    Link(destination: URL(string: "https://getmindfriend.app/privacy")!) {
                        Label("Privacy Policy", systemImage: "doc.text")
                    }

                    Link(destination: URL(string: "https://getmindfriend.app/terms")!) {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
                }

                // Logout
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                // Version
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.appVersion)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Profile")
            .alert("Sign Out", isPresented: $showLogoutConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    logout()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Delete Account", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Account", role: .destructive) {
                    deleteAccount()
                }
            } message: {
                Text("This will permanently delete your account and all data. This action cannot be undone.")
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView()
            }
            .sheet(isPresented: $showSubscription) {
                SubscriptionView()
            }
        }
    }

    private func logout() {
        Task {
            do {
                try await container.supabaseAuthService.signOut()
            } catch {
                Log.auth.error("Logout error", error: error)
            }
            await MainActor.run {
                appState.setUnauthenticated()
            }
        }
    }

    private func deleteAccount() {
        Task {
            do {
                try await container.supabaseAuthService.deleteAccount()
                await MainActor.run {
                    appState.setUnauthenticated()
                }
            } catch {
                appState.showError(.apiError(error.localizedDescription))
            }
        }
    }
}

private struct ProfileStatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

struct NotificationSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    // Social notifications
    @State private var notifyCircleActivity = true
    @State private var notifyHugs = true
    @State private var notifyChallenges = true

    // Motivation notifications
    @State private var notifyStreakRisk = true
    @State private var notifyWeeklySummary = true

    // Timing
    @State private var remindersEnabled = true
    @State private var questTime = Date()
    @State private var preferredNotifyHour = 9
    @State private var quietHoursEnabled = false
    @State private var quietStart = Date()
    @State private var quietEnd = Date()

    // State
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var systemNotificationsEnabled = true
    @State private var saveTask: Task<Void, Never>?

    /// Debounce interval in seconds for batching rapid setting changes
    private let debounceInterval: TimeInterval = 0.5

    var body: some View {
        Form {
            // System notification status
            if !systemNotificationsEnabled {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading) {
                            Text("Notifications Disabled")
                                .font(.headline)
                            Text("Enable notifications in Settings to receive alerts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            // Social notifications
            Section {
                Toggle("Circle activity", isOn: $notifyCircleActivity)
                    .onChange(of: notifyCircleActivity) { _, _ in saveSettings() }
                Toggle("Hugs received", isOn: $notifyHugs)
                    .onChange(of: notifyHugs) { _, _ in saveSettings() }
                Toggle("Challenge updates", isOn: $notifyChallenges)
                    .onChange(of: notifyChallenges) { _, _ in saveSettings() }
            } header: {
                Text("Social")
            } footer: {
                Text("Get notified when friends share, send hugs, or complete challenges")
            }

            // Motivation notifications
            Section {
                Toggle("Streak at risk", isOn: $notifyStreakRisk)
                    .onChange(of: notifyStreakRisk) { _, _ in saveSettings() }
                Toggle("Weekly summary", isOn: $notifyWeeklySummary)
                    .onChange(of: notifyWeeklySummary) { _, _ in saveSettings() }
            } header: {
                Text("Motivation")
            } footer: {
                Text("Reminders to keep your streak and weekly progress summaries")
            }

            // Timing
            Section {
                Toggle("Daily Reminders", isOn: $remindersEnabled)
                    .onChange(of: remindersEnabled) { _, _ in saveSettings() }

                if remindersEnabled {
                    DatePicker("Quest Time", selection: $questTime, displayedComponents: .hourAndMinute)
                        .onChange(of: questTime) { _, _ in saveSettings() }
                }

                Picker("Preferred Notification Time", selection: $preferredNotifyHour) {
                    ForEach(6..<22) { hour in
                        Text(formatHour(hour)).tag(hour)
                    }
                }
                .onChange(of: preferredNotifyHour) { _, _ in saveSettings() }

                NavigationLink {
                    QuietHoursView(
                        isEnabled: $quietHoursEnabled,
                        startTime: $quietStart,
                        endTime: $quietEnd,
                        onSave: saveSettings
                    )
                } label: {
                    HStack {
                        Text("Quiet Hours")
                        Spacer()
                        Text(quietHoursEnabled ? quietHoursSummary : "Off")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Timing")
            }
        }
        .navigationTitle("Notifications")
        .disabled(isLoading || isSaving)
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
        .task {
            await loadSettings()
            await checkSystemNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await checkSystemNotifications() }
        }
    }

    private var quietHoursSummary: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return "\(formatter.string(from: quietStart)) - \(formatter.string(from: quietEnd))"
    }

    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
        return formatter.string(from: date)
    }

    private func checkSystemNotifications() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        await MainActor.run {
            systemNotificationsEnabled = settings.authorizationStatus == .authorized
        }
    }

    private func loadSettings() async {
        isLoading = true
        defer { isLoading = false }

        guard let settings = appState.currentUser?.settings else { return }

        await MainActor.run {
            remindersEnabled = settings.remindersEnabled

            // Parse quest time
            if let time = parseTime(settings.dailyQuestTimeLocal) {
                questTime = time
            }

            // Parse quiet hours
            if let start = settings.quietHoursStartLocal,
               let end = settings.quietHoursEndLocal {
                quietHoursEnabled = true
                if let startTime = parseTime(start) { quietStart = startTime }
                if let endTime = parseTime(end) { quietEnd = endTime }
            }

            // Smart notification settings (with defaults for new columns)
            notifyCircleActivity = settings.notifyCircleActivity ?? true
            notifyHugs = settings.notifyHugs ?? true
            notifyChallenges = settings.notifyChallenges ?? true
            notifyStreakRisk = settings.notifyStreakRisk ?? true
            notifyWeeklySummary = settings.notifyWeeklySummary ?? true
            preferredNotifyHour = settings.preferredNotifyHour ?? 9
        }
    }

    private func parseTime(_ timeString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.date(from: timeString)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// Schedules a debounced save operation.
    /// Cancels any pending save and waits for the debounce interval before executing.
    /// This prevents rapid API calls when users toggle multiple settings quickly.
    private func saveSettings() {
        guard !isLoading else { return }

        // Cancel any pending save task
        saveTask?.cancel()

        // Schedule a new debounced save
        saveTask = Task {
            // Wait for debounce interval
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))

            // Check if cancelled during sleep
            guard !Task.isCancelled else { return }

            await performSave()
        }
    }

    /// Performs the actual save operation to the database.
    @MainActor
    private func performSave() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await container.supabaseDataService.updateUserSettings(
                dailyQuestTimeLocal: formatTime(questTime),
                quietHoursStartLocal: quietHoursEnabled ? formatTime(quietStart) : nil,
                quietHoursEndLocal: quietHoursEnabled ? formatTime(quietEnd) : nil,
                remindersEnabled: remindersEnabled,
                notifyCircleActivity: notifyCircleActivity,
                notifyHugs: notifyHugs,
                notifyChallenges: notifyChallenges,
                notifyStreakRisk: notifyStreakRisk,
                notifyWeeklySummary: notifyWeeklySummary,
                preferredNotifyHour: preferredNotifyHour
            )

            // Note: Settings are saved to database. AppState will be refreshed on next fetch.
            // We could fetch the updated profile here if needed for immediate UI updates.
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }
}

struct QuietHoursView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isEnabled: Bool
    @Binding var startTime: Date
    @Binding var endTime: Date
    var onSave: () -> Void

    var body: some View {
        Form {
            Section {
                Toggle("Enable Quiet Hours", isOn: $isEnabled)
            } footer: {
                Text("Notifications will be held until quiet hours end")
            }

            if isEnabled {
                Section {
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                } footer: {
                    Text("Recommended: 10 PM to 8 AM")
                }
            }
        }
        .navigationTitle("Quiet Hours")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isEnabled) { _, _ in onSave() }
        .onChange(of: startTime) { _, _ in onSave() }
        .onChange(of: endTime) { _, _ in onSave() }
    }
}

struct AIPreferencesView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var selectedTone: AITone = .friendly
    @State private var isSaving = false

    var body: some View {
        Form {
            Section("AI Tone") {
                ForEach(AITone.allCases, id: \.self) { tone in
                    Button {
                        selectTone(tone)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(tone.displayName)
                                    .foregroundStyle(.primary)
                                Text(tone.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedTone == tone {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .navigationTitle("AI Preferences")
        .onAppear {
            selectedTone = appState.currentUser?.settings?.aiTone ?? .friendly
        }
    }

    private func selectTone(_ tone: AITone) {
        guard tone != selectedTone else { return }
        selectedTone = tone
        isSaving = true

        Task {
            defer { isSaving = false }

            do {
                try await container.supabaseDataService.updateUserSettings(aiTone: tone)

                // Settings updated in database - will be refreshed on next profile fetch
            } catch {
                await MainActor.run {
                    // Revert on error
                    selectedTone = appState.currentUser?.settings?.aiTone ?? .friendly
                    appState.showError(.apiError(error.localizedDescription))
                }
            }
        }
    }
}

struct PrivacySettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var shareMoodInCircles = true
    @State private var privacyMode: PrivacyMode = .standard
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                PrivacyBanner()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Toggle("Share Mood in Circles", isOn: $shareMoodInCircles)
                    .disabled(isSaving)
                    .onChange(of: shareMoodInCircles) { _, newValue in
                        saveShareMoodSetting(newValue)
                    }
            } footer: {
                Text("When enabled, your daily mood will be visible to your circle members")
            }

            Section("Privacy Mode") {
                ForEach(PrivacyMode.allCases, id: \.self) { mode in
                    Button {
                        selectPrivacyMode(mode)
                    } label: {
                        HStack {
                            Text(mode.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if privacyMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .navigationTitle("Privacy")
        .onAppear {
            loadSettings()
        }
    }

    private func loadSettings() {
        guard let settings = appState.currentUser?.settings else { return }
        shareMoodInCircles = settings.shareMoodInCircles
        privacyMode = settings.privacyMode
    }

    private func saveShareMoodSetting(_ newValue: Bool) {
        isSaving = true

        Task {
            defer { isSaving = false }

            do {
                try await container.supabaseDataService.updateUserSettings(shareMoodInCircles: newValue)
                // Settings updated in database - will be refreshed on next profile fetch
            } catch {
                await MainActor.run {
                    // Revert on error
                    shareMoodInCircles = appState.currentUser?.settings?.shareMoodInCircles ?? true
                    appState.showError(.apiError(error.localizedDescription))
                }
            }
        }
    }

    private func selectPrivacyMode(_ mode: PrivacyMode) {
        guard mode != privacyMode else { return }
        let previousMode = privacyMode
        privacyMode = mode
        isSaving = true

        Task {
            defer { isSaving = false }

            do {
                try await container.supabaseDataService.updateUserSettings(privacyMode: mode)
                // Settings updated in database - will be refreshed on next profile fetch
            } catch {
                await MainActor.run {
                    // Revert on error
                    privacyMode = previousMode
                    appState.showError(.apiError(error.localizedDescription))
                }
            }
        }
    }
}

struct DataExportView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var isExporting = false
    @State private var exportData: UserDataExport?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)

            Text("Export Your Data")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Download all your MindFriend data including moods, quests, conversations, and more.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                performExport()
            } label: {
                if isExporting {
                    ProgressView()
                } else {
                    Text("Export Data")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExporting)

            Spacer()
        }
        .padding()
        .navigationTitle("Export Data")
    }

    private func performExport() {
        isExporting = true
        Task {
            do {
                let data = try await container.supabaseDataService.exportUserData()
                // In real app, would share the data file
                Log.data.info("Exported: \(String(describing: data), privacy: .private)")
            } catch {
                await MainActor.run {
                    appState.showError(.apiError(error.localizedDescription))
                }
            }
            isExporting = false
        }
    }
}

// NOTE: BadgesView and BadgeCard are defined in Features/Badges/BadgesView.swift

extension Bundle {
    var appVersion: String {
        "\(infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(infoDictionary?["CFBundleVersion"] as? String ?? "1"))"
    }
}

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var displayName: String = ""
    @State private var handle: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var handleValidation: HandleValidation = .empty

    enum HandleValidation {
        case empty
        case checking
        case valid
        case tooShort
        case invalidFormat
        case taken

        var message: String? {
            switch self {
            case .empty: return nil
            case .checking: return "Checking availability..."
            case .valid: return "Handle is available"
            case .tooShort: return "Handle must be at least 3 characters"
            case .invalidFormat: return "Only letters, numbers, and underscores allowed"
            case .taken: return "This handle is already taken"
            }
        }

        var color: Color {
            switch self {
            case .valid: return .green
            case .tooShort, .invalidFormat, .taken: return .red
            default: return .secondary
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display Name", text: $displayName)
                        .textContentType(.name)

                    HStack {
                        Text("@")
                            .foregroundStyle(.secondary)
                        TextField("handle", text: $handle)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: handle) { _, newValue in
                                validateHandle(newValue)
                            }

                        if handleValidation == .checking {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else if handleValidation == .valid {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if handleValidation == .taken || handleValidation == .invalidFormat {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let message = handleValidation.message {
                            Text(message)
                                .foregroundStyle(handleValidation.color)
                        }
                        Text("Your handle is how others find you in circles")
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProfile()
                    }
                    .disabled(isSaving || displayName.isEmpty || !canSave)
                }
            }
            .onAppear {
                displayName = appState.currentUser?.displayName ?? ""
                let currentHandle = appState.currentUser?.handle ?? ""
                handle = currentHandle
                
                // If there's an existing handle, mark it as valid initially
                if !currentHandle.isEmpty {
                    handleValidation = .valid
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var canSave: Bool {
        if handle.isEmpty {
            return true // Handle is optional
        }
        return handleValidation == .valid
    }

    private func validateHandle(_ newHandle: String) {
        let trimmed = newHandle.lowercased().trimmingCharacters(in: .whitespaces)

        // Empty is OK (handle is optional)
        guard !trimmed.isEmpty else {
            handleValidation = .empty
            return
        }

        // Check length
        guard trimmed.count >= 3 else {
            handleValidation = .tooShort
            return
        }

        // Check format
        let handleRegex = /^[a-z0-9_]{3,30}$/
        guard trimmed.wholeMatch(of: handleRegex) != nil else {
            handleValidation = .invalidFormat
            return
        }

        // If it's the same as current handle, it's valid
        if trimmed == appState.currentUser?.handle?.lowercased() {
            handleValidation = .valid
            return
        }

        // Check availability
        handleValidation = .checking
        Task {
            do {
                let isAvailable = try await container.supabaseAuthService.isHandleAvailable(trimmed)
                await MainActor.run {
                    // Only update if still the same handle
                    if handle.lowercased().trimmingCharacters(in: .whitespaces) == trimmed {
                        handleValidation = isAvailable ? .valid : .taken
                    }
                }
            } catch {
                await MainActor.run {
                    handleValidation = .invalidFormat
                }
            }
        }
    }

    private func saveProfile() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await container.supabaseAuthService.updateProfile(
                    displayName: displayName,
                    handle: handle.isEmpty ? nil : handle
                )

                // Refresh the profile
                let updatedProfile = try await container.supabaseAuthService.fetchProfile()
                await MainActor.run {
                    appState.currentUser = updatedProfile
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            isSaving = false
        }
    }
}

// MARK: - Premium Badge Label

struct PremiumBadgeLabel: View {
    let badge: Badge

    private var displayName: String {
        switch badge.code {
        case "premium_supporter": return "Premium"
        case "annual_achiever": return "Annual"
        case "family_champion": return "Family Champion"
        default: return "Premium"
        }
    }

    private var badgeColor: Color {
        switch badge.code {
        case "annual_achiever": return .purple
        case "family_champion": return .blue
        default: return .yellow
        }
    }

    var body: some View {
        Label(displayName, systemImage: badge.icon)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor.opacity(0.15))
            .cornerRadius(6)
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
