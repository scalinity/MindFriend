import SwiftUI
import UserNotifications

struct ProfileView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showEditProfile = false
    @State private var showSubscription = false
    @State private var showVacationMode = false
    @State private var showShieldHistory = false
    @State private var badgeCount = 0

    var body: some View {
        NavigationStack {
            List {
                // Profile header
                Section {
                    Button {
                        showEditProfile = true
                    } label: {
                        HStack(spacing: 16) {
                            // Display avatar or placeholder
                            if let avatarUrl = appState.currentUser?.avatarUrl, !avatarUrl.isEmpty {
                                AsyncImage(url: URL(string: avatarUrl)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 60, height: 60)
                                            .clipShape(Circle())
                                    case .failure:
                                        Image(systemName: "person.circle.fill")
                                            .font(.system(size: 60))
                                            .foregroundStyle(Color.accentColor)
                                    case .empty:
                                        ProgressView()
                                            .frame(width: 60, height: 60)
                                    @unknown default:
                                        Image(systemName: "person.circle.fill")
                                            .font(.system(size: 60))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .accessibilityLabel("Profile picture")
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityLabel("Profile picture placeholder")
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(appState.currentUser?.displayName ?? "User")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)

                                Text("@\(appState.currentUser?.handle ?? "")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if appState.entitlements.tier == .premium {
                                    HStack(spacing: 4) {
                                        Image(systemName: "crown.fill")
                                        Text("Premium")
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.medium)
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
                        ProfileStatItem(value: "\(badgeCount)", label: "Badges")
                    }
                    .padding(.vertical, 8)
                }

                // Premium / Subscription (placed between Stats and Progress)
                if appState.entitlements.tier == .free {
                    Section {
                        Button {
                            showSubscription = true
                        } label: {
                            HStack {
                                Image(systemName: "crown.fill")
                                    .foregroundStyle(.yellow)
                                Text("Upgrade to Premium")
                                    .fontWeight(.semibold)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
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

                    NavigationLink {
                        LongitudinalDashboardView()
                    } label: {
                        Label("Your Journey", systemImage: "chart.line.uptrend.xyaxis")
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
                        MentorshipTabView()
                    } label: {
                        Label("Mentorship", systemImage: "star.fill")
                    }

                    NavigationLink {
                        PeerSupportHubView(supabase: container.supabase)
                    } label: {
                        Label("Peer Support", systemImage: "person.3.fill")
                    }

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
                        BiometricsSettingsView(healthKit: container.healthKitService)
                    } label: {
                        Label("Apple Health (HealthKit)", systemImage: "heart.fill")
                            .foregroundStyle(.pink)
                    }

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
                        InterventionSettingsView()
                    } label: {
                        Label("Smart Interventions", systemImage: "waveform.path.ecg")
                    }

                    // Vacation Mode & Shield History
                    Button {
                        showVacationMode = true
                    } label: {
                        Label("Vacation Mode", systemImage: "airplane")
                    }
                    
                    Button {
                        showShieldHistory = true
                    } label: {
                        Label("Shield History", systemImage: "shield.lefthalf.filled")
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
                            .environmentObject(container.companionMemoryService)
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
                        AgentDashboardView()
                    } label: {
                        Label("Wellness Agent", systemImage: "brain.head.profile")
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

                    Link(destination: AppURLs.privacyPolicy) {
                        Label("Privacy Policy", systemImage: "doc.text")
                    }

                    Link(destination: AppURLs.termsOfUse) {
                        Label("Terms of Use", systemImage: "doc.text")
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
            .sheet(isPresented: $showVacationMode) {
                VacationModeSheet()
                    .environmentObject(container)
            }
            .sheet(isPresented: $showShieldHistory) {
                NavigationStack {
                    ShieldHistoryView()
                        .environmentObject(container)
                }
            }
            .task {
                await loadBadgeCount()
            }
        }
    }

    private func loadBadgeCount() async {
        do {
            // Check badge progress first to ensure badges are up-to-date
            _ = try? await container.achievementService.checkBadgeProgress()
            // Then load the updated badge progress
            try await container.achievementService.loadUserBadgeProgress()
            let earned = container.achievementService.earnedBadges
            await MainActor.run {
                badgeCount = earned.count
            }
            Log.profile.debug("ProfileView loaded \(earned.count) earned badges")
        } catch {
            Log.profile.error("Failed to load badge count: \(error.localizedDescription)")
        }
    }

    private func logout() {
        Task {
            // Stop ambient theme monitoring
            container.ambientThemeService.stop()
            
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
        guard let owner = appState.currentUser?.id else { return }
        Task {
            do {
                try await container.supabaseAuthService.deleteAccount(expectedOwner: owner)
                await MainActor.run {
                    if container.supabaseAuthService.userId == nil { appState.setUnauthenticated() }
                }
            } catch {
                guard appState.currentUser?.id == owner else { return }
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
    @State private var badgeCount = 0
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
            await loadBadgeCount()
        }
        .onAppear {
            // Refresh badge count each time the view appears (for TabView navigation)
            Task { await loadBadgeCount() }
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

    private func loadBadgeCount() async {
        do {
            // Check badge progress first to ensure badges are up-to-date
            _ = try? await container.achievementService.checkBadgeProgress()
            // Then load the updated badge progress
            try await container.achievementService.loadUserBadgeProgress()
            let earned = container.achievementService.earnedBadges
            badgeCount = earned.count
            Log.profile.debug("Loaded \(earned.count) earned badges out of \(container.achievementService.userBadgeProgress.count) total user badges")
        } catch {
            Log.profile.error("Failed to load badge count: \(error.localizedDescription)")
            badgeCount = 0
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

            // Schedule/cancel local quest reminder notification
            let components = Calendar.current.dateComponents([.hour, .minute], from: questTime)
            try await container.questNotificationService.updateSchedule(
                enabled: remindersEnabled,
                hour: components.hour ?? 9,
                minute: components.minute ?? 0
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

/// Owner data export (AC-20 / E01). A deliberate tap builds ONE protected JSON file (never logged), shows visible
/// loading/failure, offers the native share/save sheet, and discards the file after sharing, on dismissal, or when the
/// account changes. See Core/SupportSession/SupportDataExport.swift for the owner/epoch, paging and file contract.
struct DataExportView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    /// Owns the run/share state. Each run and each share sheet is bound to a generation, so a cancelled run or a delayed
    /// share-sheet completion from an older generation can never change (or delete) the current export.
    @StateObject private var export = SupportExportController()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text("Export Your Data")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Create a file with a copy of the records listed below that MindFriend keeps for your account, plus support data saved only on this device. Nothing is created until you tap Export Data.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                scopeSection
                actionSection
            }
            .padding()
        }
        .navigationTitle("Export Data")
        .sheet(isPresented: $export.showShareSheet) {
            // The ticket pins this sheet to the exact file and generation it was created for.
            if let ticket = export.shareTicket {
                SupportExportShareSheet(url: ticket.result.fileURL) { export.finishSharing(ticket) }
                    .ignoresSafeArea()
            }
        }
        // A different account or a restarted account scope never keeps (or shares) the previous person's file.
        .onChange(of: appState.accountEpoch) { _, _ in export.reset() }
        .onChange(of: appState.currentUser?.id) { _, _ in export.reset() }
        .onAppear { SupportDataExporter.purgeLeftoverFiles() }
        // A sheet over this screen doesn't dismiss it; only leaving the screen discards the file.
        .onDisappear { if !export.showShareSheet { export.reset() } }
    }

    // MARK: Sections

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup("What this export includes") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SupportExportDataset.allCases, id: \.rawValue) { dataset in
                        Text("• \(dataset.title)")
                    }
                    Text("• Protected support data saved on this device: drafts, transcript lines and changes still waiting to sync, each marked as local or pending.")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            }
            DisclosureGroup("What it does not include") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SupportExportScope.notIncluded, id: \.self) { item in
                        Text("• \(item)")
                    }
                    Text(SupportExportScope.statement)
                    Text(SupportExportScope.consistencyNote)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            }
            Text("The file contains private details such as conversations and notes. Share it only with people and apps you trust, and delete saved copies you no longer need.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        switch export.phase {
        case .idle:
            exportButton(title: "Export Data")
        case .running(let status):
            VStack(spacing: 12) {
                ProgressView()
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Cancel Export", role: .cancel) { export.cancel() }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Exporting your data. \(status)")
        case .ready(let result):
            VStack(alignment: .leading, spacing: 12) {
                Label(result.summary.isComplete ? "Your export is ready" : "Your export is ready, but not everything is in it",
                      systemImage: result.summary.isComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(result.summary.isComplete ? Color.green : Color.orange)
                Text("\(result.summary.totalRows) account records from \(result.summary.datasets.filter { $0.status == .included }.count) of \(result.summary.datasets.count) cloud groups\(deviceSummary(result.summary.local)).")
                    .font(.subheadline)
                if !result.summary.isComplete {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.summary.omissions, id: \.self) { Text("• \($0)").font(.footnote) }
                        Text("The file itself marks these as unavailable. They are not empty.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    Task { await export.presentShare() }
                } label: {
                    Label("Share or Save File", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button("Discard Export", role: .destructive) { export.reset() }
                    .frame(maxWidth: .infinity)
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Label("Export didn't finish", systemImage: "exclamationmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(Color.red)
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                exportButton(title: "Try Again")
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    private func exportButton(title: String) -> some View {
        Button {
            export.start { makeExporter() }
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(export.isRunning)
    }

    private func deviceSummary(_ local: SupportExportLocalSummary) -> String {
        switch local.status {
        case .included:
            let pending = local.unsentMutations + local.pendingTranscriptEvents + local.rejectedTranscriptEvents + local.pendingChatRequests + local.unacknowledgedPrivacyChanges
            return " and your on-device support data (\(local.drafts) draft\(local.drafts == 1 ? "" : "s"), \(pending) item\(pending == 1 ? "" : "s") awaiting sync or attention)"
        case .unavailable:
            return " (on-device support data not included)"
        }
    }

    // MARK: Wiring (captured owner + epoch; raw token; no ambient SDK session on the wire)

    @MainActor
    private func makeExporter() -> SupportDataExporter? {
        guard let ownerID = appState.currentUser?.id else { return nil }
        let binding = SupportExportBinding(ownerID: ownerID, accountEpoch: appState.accountEpoch)
        let appState = self.appState
        let container = self.container

        let proof: SupportExportOwnerProof = { [weak appState, weak container] in
            guard let appState, let container else { return nil }
            return await MainActor.run {
                guard appState.currentUser?.id == binding.ownerID, appState.accountEpoch == binding.accountEpoch,
                      container.supabaseAuthService.userId == binding.ownerID,
                      container.supabaseClient.auth.currentSession?.user.id == binding.ownerID else { return nil }
                return binding
            }
        }
        let tokens: SupportExportTokenSource = { [weak container] in
            guard let container, await proof() == binding else { throw SupportExportError.ownerChanged }
            try await container.supabaseAuthService.ensureValidSession()
            guard await proof() == binding else { throw SupportExportError.ownerChanged }
            let token: String? = await MainActor.run {
                guard let session = container.supabaseAuthService.session, session.user.id == binding.ownerID else { return nil }
                return session.accessToken
            }
            guard let token else { throw SupportExportError.ownerChanged }
            return SupportExportCredential(binding: binding, accessToken: token)
        }
        let local: SupportExportLocalSource = { [weak container] requested in
            guard let container else { return .unavailable(.noSupportScope) }
            return await DataExportView.readLocalJournal(container: container, binding: requested)
        }
        return SupportDataExporter(
            binding: binding, ownerProof: proof, tokenSource: tokens, local: local,
            transport: URLSessionSupportExportTransport(session: URLSessionSupportExportTransport.makeSession()),
            projectURL: SupabaseConfig.projectURL, apiKey: SupabaseConfig.anonKey, appVersion: Bundle.main.appVersion)
    }

    /// Requires the loaded coordinator's owner AND account epoch to match, then only READS the journal: nothing is
    /// replayed, sent or changed.
    @MainActor
    private static func readLocalJournal(container: DependencyContainer, binding: SupportExportBinding) async -> SupportExportLocalOutcome {
        if container.supportSessionRecovery != nil { return .unavailable(.journalNeedsRecovery) }
        guard let coordinator = container.supportSessionCoordinator else { return .unavailable(.noSupportScope) }
        guard coordinator.identity.ownerID == binding.ownerID else { return .unavailable(.ownerMismatch) }
        guard container.supportSessionAccountEpoch == binding.accountEpoch else { return .unavailable(.accountEpochMismatch) }
        do {
            return .journal(try await coordinator.repository.currentJournal(epoch: coordinator.identity.epochID))
        } catch {
            return .unavailable(.journalUnreadable)
        }
    }
}

/// `UIActivityViewController` with a completion callback, so the temporary export file is deleted as soon as the sheet ends.
private struct SupportExportShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
    @State private var showProfilePictureEditor = false

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
                // Profile picture section
                Section {
                    Button {
                        showProfilePictureEditor = true
                    } label: {
                        HStack(spacing: 16) {
                            if let avatarUrl = appState.currentUser?.avatarUrl, !avatarUrl.isEmpty {
                                AsyncImage(url: URL(string: avatarUrl)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 80, height: 80)
                                            .clipShape(Circle())
                                    case .failure, .empty:
                                        Image(systemName: "person.circle.fill")
                                            .font(.system(size: 80))
                                            .foregroundStyle(.gray)
                                    @unknown default:
                                        Image(systemName: "person.circle.fill")
                                            .font(.system(size: 80))
                                            .foregroundStyle(.gray)
                                    }
                                }
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 80))
                                    .foregroundStyle(.gray)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Profile Picture")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("Tap to edit")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

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
            .keyboardDoneButton()
            .sheet(isPresented: $showProfilePictureEditor) {
                ProfilePictureEditorView()
                    .environmentObject(appState)
                    .environmentObject(container)
            }
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
    let badge: EarnedBadge

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
