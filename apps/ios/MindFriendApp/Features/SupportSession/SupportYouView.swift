import SwiftUI

/// A row contributed by another lane (for example the session owner's "Saved steps" or session History)
/// that is shown in a You section without this file knowing the destination's type.
struct SupportYouExtension: Identifiable {
    let id: String
    let section: SupportSection
    let title: String
    var subtitle: String?
    let icon: String
    let destination: AnyView

    init<Destination: View>(id: String, section: SupportSection, title: String, subtitle: String? = nil,
                            icon: String, @ViewBuilder destination: () -> Destination) {
        self.id = id
        self.section = section
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.destination = AnyView(destination())
    }
}

/// You: Progress and History first, then memory, measurements, settings, and help (SUPPORT_SESSION_SPEC §4.1, §5.6).
/// Nothing here is gated by activation. Paid actions remain guarded inside their own destination views.
struct SupportYouView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var navigator: SupportShellNavigator
    @EnvironmentObject private var pins: SupportPinStore

    /// Rows contributed by the session lane (History, Saved steps, What MindFriend remembers).
    var extensions: [SupportYouExtension] = []

    @State private var showEditProfile = false
    @State private var showSubscription = false
    @State private var showSOS = false
    @State private var badgeCount: Int?
    @State private var replaceCandidate: SupportPin?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack(path: $navigator.youPath) {
            List {
                profileSection
                progressSection
                historySection
                memorySections
                measurementsSection
                settingsSection
                helpSection
            }
            .supportCanvas()
            .navigationTitle(SupportShellTab.you.title)
            .navigationDestination(for: SupportDestination.self) { destination in
                SupportDestinationView(destination: destination)
            }
            .sheet(isPresented: $showEditProfile) { EditProfileView() }
            .sheet(isPresented: $showSubscription) { SubscriptionView() }
            .sheet(item: $replaceCandidate) { ReplacePinSheet(candidate: $0).environmentObject(pins) }
            .fullScreenCover(isPresented: $showSOS) {
                SOSInterventionView().environmentObject(container)
            }
            .task(id: appState.currentUser?.id) { await loadBadgeCount() }
        }
    }

    // MARK: Sections

    private var profileSection: some View {
        Section {
            Button {
                showEditProfile = true
            } label: {
                // Stacked at accessibility sizes so the name wraps on word boundaries.
                (dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: SupportTheme.Spacing.s))
                    : AnyLayout(HStackLayout(spacing: SupportTheme.Spacing.m))) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(SupportTheme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text(appState.currentUser?.displayName ?? String(localized: "Your profile"))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(SupportTheme.textPrimary)
                        if appState.entitlements.tier == .premium {
                            Text("Premium")
                                .font(.subheadline)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Text("Edit")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.accent)
                }
                .frame(minHeight: SupportTheme.minimumTarget)
            }
            .accessibilityLabel(Text("Edit profile"))

            if appState.entitlements.tier == .free {
                Button {
                    showSubscription = true
                } label: {
                    SupportRowLabel(
                        title: String(localized: "Plans and Premium"),
                        subtitle: String(localized: "Saved work and Help stay available"),
                        icon: "crown.fill"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var progressSection: some View {
        Section(SupportSection.progress.title) {
            // Summary from real account stats only; nothing is shown as a score or judgment.
            HStack(alignment: .top, spacing: SupportTheme.Spacing.m) {
                summaryItem(value: appState.currentUser?.stats?.currentStreakDays, label: String(localized: "Streak"))
                summaryItem(value: appState.currentUser?.stats?.totalQuestsCompleted, label: String(localized: "Quests"))
                summaryItem(value: badgeCount, label: String(localized: "Badges"))
            }
            .accessibilityElement(children: .contain)
            ForEach(SupportDestination.destinations(in: .progress)) { destination in
                pinnableRow(destination)
            }
            extensionRows(in: .progress)
        }
    }

    private var historySection: some View {
        Section(SupportSection.history.title) {
            extensionRows(in: .history)
            NavigationLink(value: SupportDestination.moodHistory) { SupportRowLabel(.moodHistory) }
            NavigationLink(value: SupportDestination.journal) {
                SupportRowLabel(
                    title: SupportDestination.journal.title,
                    subtitle: String(localized: "Text and voice entries"),
                    icon: SupportDestination.journal.icon
                )
            }
            Button {
                appState.selectedTab = SupportShellTab.chat.mainTab
            } label: {
                SupportRowLabel(
                    title: String(localized: "Conversations"),
                    subtitle: String(localized: "Open Chat to continue or search past conversations"),
                    icon: "bubble.left.and.bubble.right"
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var memorySections: some View {
        Section {
            extensionRows(in: .memory)
            NavigationLink(value: SupportDestination.memoryVault) {
                Label("What MindFriend remembers", systemImage: "brain.head.profile")
            }
        } header: {
            Text(SupportSection.memory.title)
        } footer: {
            Text("Cloud memory the AI may use, if you allow it. Your private journal below is separate.")
        }
        Section {
            NavigationLink(value: SupportDestination.privateVault) { SupportRowLabel(.privateVault) }
        }
    }

    private var measurementsSection: some View {
        Section {
            ForEach(SupportDestination.destinations(in: .measurements)) { destination in
                pinnableRow(destination)
            }
            extensionRows(in: .measurements)
        } header: {
            Text(SupportSection.measurements.title)
        } footer: {
            Text("Optional. Measurements and estimates show what they are based on. They never replace how you say you feel.")
        }
    }

    private var settingsSection: some View {
        Section(SupportSection.settings.title) {
            NavigationLink(value: SupportDestination.settings) {
                SupportRowLabel(
                    title: String(localized: "Settings and account"),
                    subtitle: String(localized: "Notifications, privacy, subscription, data, and sign out"),
                    icon: SupportDestination.settings.icon
                )
            }
            extensionRows(in: .settings)
        }
    }

    private func pinnableRow(_ destination: SupportDestination) -> some View {
        HStack {
            NavigationLink(value: destination) { SupportRowLabel(destination) }
            if destination.isPinnable {
                Menu {
                    if pins.isPinned(destination) {
                        Button("Unpin from Today") { pins.unpin(destination) }
                    } else if pins.isFull {
                        Button("Replace a pin…") { replaceCandidate = SupportPin(destination) }
                    } else {
                        Button("Pin to Today") { pins.pin(destination) }
                    }
                } label: {
                    Image(systemName: pins.isPinned(destination) ? "pin.fill" : "ellipsis.circle")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Pin options for \(destination.title)")
            }
        }
    }

    private var helpSection: some View {
        Section(SupportSection.help.title) {
            Button {
                appState.showCrisisResources = true
            } label: {
                SupportRowLabel(
                    title: String(localized: "Support and crisis resources"),
                    subtitle: String(localized: "Available any time, no sign-in checks or AI needed"),
                    icon: "heart.text.square.fill"
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: SupportDestination.safetyPlan) { SupportRowLabel(.safetyPlan) }

            if container.sosCoordinator.settings?.sosEnabled != false {
                Button {
                    showSOS = true
                } label: {
                    SupportRowLabel(
                        title: String(localized: "SOS support"),
                        subtitle: String(localized: "Guided help for a hard moment"),
                        icon: "heart.fill"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func extensionRows(in section: SupportSection) -> some View {
        ForEach(extensions.filter { $0.section == section }) { row in
            NavigationLink {
                row.destination
            } label: {
                SupportRowLabel(title: row.title, subtitle: row.subtitle, icon: row.icon)
            }
        }
    }

    private func summaryItem(value: Int?, label: String) -> some View {
        VStack(spacing: SupportTheme.Spacing.xxs) {
            if let value {
                Text(String(value))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(SupportTheme.textPrimary)
            } else {
                Text("Not yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SupportTheme.textSecondary)
            }
            Text(label)
                .font(.footnote)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(value.map(String.init) ?? "Unavailable") \(label)"))
    }

    private func loadBadgeCount() async {
        guard let userID = appState.currentUser?.id else { return }
        _ = try? await container.achievementService.checkBadgeProgress()
        do {
            try await container.achievementService.loadUserBadgeProgress()
            guard !Task.isCancelled, appState.currentUser?.id == userID else { return }
            badgeCount = container.achievementService.earnedBadges.filter { $0.userId == userID }.count
        } catch {
            // Leave the badge count unavailable ("–") rather than showing a misleading zero.
        }
    }
}

// MARK: - Settings and account

/// Every account/settings capability formerly in Profile, kept under You → Settings with the same destinations.
struct SupportSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer

    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showSubscription = false
    @State private var showVacationMode = false

    private static let preferenceRows: [SupportDestination] = [
        .notificationSettings, .aiPreferences, .interventionSettings, .privacySettings, .appLock,
        .appearance, .language, .proactiveCheckIns, .wellnessAgent, .sosSettings, .recoveryMode, .ourApproach
    ]

    var body: some View {
        List {
            Section(String(localized: "Plan")) {
                Button {
                    showSubscription = true
                } label: {
                    SupportRowLabel(
                        title: appState.entitlements.tier == .premium
                            ? String(localized: "Manage subscription") : String(localized: "Plans and Premium"),
                        icon: "crown.fill"
                    )
                }
                .buttonStyle(.plain)
            }

            Section(String(localized: "Preferences")) {
                ForEach(Self.preferenceRows) { destination in
                    NavigationLink(value: destination) { SupportRowLabel(destination) }
                }
                Button {
                    showVacationMode = true
                } label: {
                    SupportRowLabel(title: String(localized: "Vacation mode"), icon: "airplane")
                }
                .buttonStyle(.plain)
            }

            Section(String(localized: "Professional")) {
                NavigationLink(value: SupportDestination.becomeTherapist) { SupportRowLabel(.becomeTherapist) }
            }

            Section(String(localized: "Data")) {
                NavigationLink(value: SupportDestination.dataExport) { SupportRowLabel(.dataExport) }
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    SupportRowLabel(title: String(localized: "Delete account"), icon: "trash")
                }
            }

            Section(String(localized: "Support")) {
                Button {
                    appState.showCrisisResources = true
                } label: {
                    SupportRowLabel(title: String(localized: "Crisis resources"), icon: "heart.text.square.fill")
                }
                .buttonStyle(.plain)
                if let mail = URL(string: "mailto:support@mindfriend.app") {
                    Link(destination: mail) {
                        SupportRowLabel(title: String(localized: "Contact support"), icon: "envelope")
                    }
                }
                Link(destination: AppURLs.privacyPolicy) {
                    SupportRowLabel(title: String(localized: "Privacy policy"), icon: "doc.text")
                }
                Link(destination: AppURLs.termsOfUse) {
                    SupportRowLabel(title: String(localized: "Terms of use"), icon: "doc.text")
                }
            }

            Section {
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    SupportRowLabel(title: String(localized: "Sign out"), icon: "rectangle.portrait.and.arrow.right")
                }
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.appVersion).foregroundStyle(SupportTheme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .supportCanvas()
        .navigationTitle(SupportDestination.settings.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "Sign out"), isPresented: $showLogoutConfirm) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Sign out"), role: .destructive) { logout() }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert(String(localized: "Delete account"), isPresented: $showDeleteConfirm) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Delete account"), role: .destructive) { deleteAccount() }
        } message: {
            Text("This will permanently delete your account and all data. This action cannot be undone.")
        }
        .sheet(isPresented: $showSubscription) { SubscriptionView() }
        .sheet(isPresented: $showVacationMode) {
            VacationModeSheet().environmentObject(container)
        }
    }

    // Same behavior as the legacy ProfileView actions.
    private func logout() {
        Task {
            container.ambientThemeService.stop()
            do {
                try await container.supabaseAuthService.signOut()
            } catch {
                Log.auth.error("Logout error", error: error)
            }
            await MainActor.run { appState.setUnauthenticated() }
        }
    }

    private func deleteAccount() {
        Task {
            do {
                try await container.supabaseAuthService.deleteAccount()
                await MainActor.run { appState.setUnauthenticated() }
            } catch {
                appState.showError(.apiError(error.localizedDescription))
            }
        }
    }
}
