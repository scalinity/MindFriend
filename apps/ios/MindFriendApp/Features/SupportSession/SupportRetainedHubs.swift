import SwiftUI

// Small hubs that give retained Home-only capabilities a named home in Explore / You (SR-03…SR-07).
// Each hub reuses the existing card / view, loads only its own data through the existing service, and
// requires an explicit tap for any action. None of them reproduces the old Home fan-out.
// Loads are scoped to the signed-in account: a late result for a different account is dropped.

private enum HubLoad: Equatable {
    case loading, loaded, failed
}

/// Shared "couldn't load" treatment with a retry; local content stays usable.
private struct HubFailedView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        SupportUnavailableState(
            title: String(localized: "Couldn't load this"),
            message: message,
            actionTitle: String(localized: "Try again"),
            action: retry
        )
    }
}

// MARK: - Plans (You → Progress)

/// The user's current action plan. Existing plans only: this app has no initial-generation UI, so nothing here
/// offers to create one.
struct SupportPlansHub: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @State private var plan: ActionPlan?
    @State private var items: [ActionPlanItem] = []
    @State private var state = HubLoad.loading
    @State private var retry = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                switch state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .failed:
                    HubFailedView(message: String(localized: "Check your connection and try again.")) { retry = UUID() }
                case .loaded:
                    if let plan, plan.isActive, !items.isEmpty {
                        ActionPlanHomeCard(plan: plan, items: items)
                    } else {
                        Text("You don't have an active plan right now.")
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
            }
            .padding(SupportTheme.Spacing.m)
        }
        .background(SupportTheme.canvas.ignoresSafeArea())
        .navigationTitle(SupportDestination.plans.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: retry) { await load() }
    }

    private func load() async {
        guard let userID = appState.currentUser?.id else { return }
        state = .loading
        do {
            let result = try await container.actionPlanService.fetchLatestPlan(
                timezone: appState.currentUser?.timezone ?? TimeZone.current.identifier
            )
            guard !Task.isCancelled, appState.currentUser?.id == userID else { return }
            plan = result?.0
            items = result?.1 ?? []
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, appState.currentUser?.id == userID else { return }
            state = .failed
        }
    }
}

// MARK: - Daily briefing (You → Progress)

struct SupportDailyBriefingHub: View {
    @EnvironmentObject private var container: DependencyContainer

    var body: some View {
        ScrollView {
            DailyBriefingCard(viewModel: container.dailyBriefingViewModel)
                .padding(SupportTheme.Spacing.m)
        }
        .background(SupportTheme.canvas.ignoresSafeArea())
        .navigationTitle(SupportDestination.dailyBriefing.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await container.dailyBriefingViewModel.loadTodaysBriefing() }
    }
}

// MARK: - Weekly recap / progress story (You → Progress)

/// The weekly progress-story recap. This is different from "My stories" (narratives); both stay reachable.
struct SupportWeeklyRecapHub: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                ProgressStoryPreviewCard()
                NavigationLink {
                    ProgressStoryViewer(weekStart: nil)
                } label: {
                    SupportRowLabel(
                        title: String(localized: "Open this week's recap"),
                        icon: "rectangle.stack"
                    )
                }
            }
            .padding(SupportTheme.Spacing.m)
        }
        .background(SupportTheme.canvas.ignoresSafeArea())
        .navigationTitle(SupportDestination.weeklyRecap.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Streaks and shields (You → Progress)

/// Status, history, vacation mode and recovery in one calm place. Nothing here counts down or warns;
/// the recovery check is something you ask for.
struct SupportStreaksHub: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @State private var showVacation = false
    @State private var recoveryItem: RecoveryQuestItem?
    @State private var isChecking = false
    @State private var recoveryMessage: String?
    @State private var pendingStreakToRecover = 0
    @State private var isStartingRecovery = false

    private var stats: UserStats? { appState.currentUser?.stats }

    var body: some View {
        List {
            Section(String(localized: "Current status")) {
                statusRow(String(localized: "Current streak"), value: appState.currentStreak > 0
                          ? appState.currentStreak : (stats?.currentStreakDays ?? 0))
                statusRow(String(localized: "Longest streak"), value: stats?.longestStreakDays ?? 0)
                if let remaining = stats?.streakShieldsRemaining, let max = stats?.streakShieldsMax {
                    statusRow(String(localized: "Shields available"), text: "\(remaining) / \(max)")
                }
            }
            Section {
                NavigationLink {
                    ShieldHistoryView().environmentObject(container)
                } label: {
                    SupportRowLabel(title: String(localized: "Shield history"), icon: "shield.lefthalf.filled")
                }
                Button {
                    showVacation = true
                } label: {
                    SupportRowLabel(title: String(localized: "Vacation mode"), icon: "airplane")
                }
                .buttonStyle(.plain)
            }
            Section {
                Button {
                    Task { await checkForRecovery() }
                } label: {
                    SupportRowLabel(
                        title: String(localized: "Check for a recovery quest"),
                        subtitle: String(localized: "Only if your streak was interrupted"),
                        icon: "arrow.counterclockwise"
                    )
                }
                .buttonStyle(.plain)
                .disabled(isChecking)
                if let recoveryMessage {
                    Text(recoveryMessage).foregroundStyle(SupportTheme.textSecondary)
                }
                if pendingStreakToRecover > 0 {
                    Button {
                        Task { await startRecovery() }
                    } label: {
                        SupportRowLabel(
                            title: String(localized: "Start recovery quest"),
                            subtitle: String(localized: "Restore a streak of \(pendingStreakToRecover)"),
                            icon: "figure.walk"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isStartingRecovery)
                }
            } header: {
                Text("Recovery")
            }
        }
        .supportCanvas()
        .navigationTitle(SupportDestination.streaks.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showVacation) {
            VacationModeSheet().environmentObject(container)
        }
        .sheet(item: $recoveryItem) { item in
            RecoveryQuestView(streakToRecover: pendingStreakToRecover, attemptId: item.attemptId, quest: item.quest)
                .environmentObject(appState)
                .environmentObject(container)
        }
    }

    private func statusRow(_ title: String, value: Int) -> some View {
        statusRow(title, text: "\(value)")
    }

    private func statusRow(_ title: String, text: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(text).foregroundStyle(SupportTheme.textSecondary)
        }
        .frame(minHeight: SupportTheme.minimumTarget)
        .accessibilityElement(children: .combine)
    }

    private func checkForRecovery() async {
        guard let userID = appState.currentUser?.id, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let protection = try await container.supabaseDataService.checkStreakProtection()
            guard appState.currentUser?.id == userID else { return }
            let expiry = protection.recoveryExpiresAt.flatMap { $0 > Date() ? $0 : nil }
            if protection.recoveryAvailable, expiry != nil {
                pendingStreakToRecover = max(0, protection.streakBeforeBreak ?? 0)
                recoveryMessage = String(localized: "A recovery quest is available.")
            } else {
                pendingStreakToRecover = 0
                recoveryMessage = String(localized: "No recovery quest is needed right now.")
            }
        } catch {
            recoveryMessage = String(localized: "Couldn't check right now. Try again later.")
        }
    }

    private func startRecovery() async {
        guard let userID = appState.currentUser?.id, !isStartingRecovery else { return }
        isStartingRecovery = true
        defer { isStartingRecovery = false }
        do {
            let result = try await container.supabaseDataService.startRecoveryQuest()
            guard appState.currentUser?.id == userID else { return }
            if result.success, let quest = result.quest {
                recoveryItem = RecoveryQuestItem(attemptId: result.attemptId ?? "", quest: quest)
            } else {
                recoveryMessage = result.error ?? String(localized: "Couldn't start the recovery quest.")
            }
        } catch {
            recoveryMessage = String(localized: "Couldn't start the recovery quest.")
        }
    }
}

// MARK: - Journal chooser (Explore → Practices)

/// Text and voice journals are separate existing tools; this chooser names both instead of hiding one.
struct SupportJournalHub: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    JournalListView()
                } label: {
                    SupportRowLabel(
                        title: String(localized: "Text journal"),
                        subtitle: String(localized: "Write and revisit entries"),
                        icon: "book.closed"
                    )
                }
                NavigationLink {
                    VoiceJournalRecorderView()
                } label: {
                    SupportRowLabel(
                        title: String(localized: "Voice journal"),
                        subtitle: String(localized: "Record an entry. The microphone starts only when you ask."),
                        icon: "mic.fill"
                    )
                }
                NavigationLink {
                    CreativeGalleryView()
                } label: {
                    SupportRowLabel(
                        title: String(localized: "Voice journal history"),
                        subtitle: String(localized: "Saved recordings and other creative work"),
                        icon: "waveform"
                    )
                }
            } footer: {
                Text("Text and voice entries are kept separately, and each list is searched on its own. Art and drawing tools are in Create.")
            }
        }
        .supportCanvas()
        .navigationTitle(SupportDestination.journal.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Pathways (Explore → Programs and Pathways)

/// Your active pathways open their exact dashboards first; the catalog only starts a new one.
struct SupportPathwaysHub: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @State private var pathways: [UserPathway] = []
    @State private var state = HubLoad.loading
    @State private var selected: UserPathway?
    @State private var retry = UUID()

    var body: some View {
        List {
            Section(String(localized: "Your pathways")) {
                switch state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .failed:
                    HubFailedView(message: String(localized: "Your active pathways couldn't be loaded.")) { retry = UUID() }
                case .loaded:
                    if pathways.isEmpty {
                        Text("You don't have an active pathway.")
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    ForEach(pathways) { pathway in
                        ActivePathwayCard(userPathway: pathway) { selected = pathway }
                            .listRowInsets(EdgeInsets())
                    }
                }
            }
            Section {
                NavigationLink {
                    PathwaySelectionView().environmentObject(container)
                } label: {
                    SupportRowLabel(
                        title: String(localized: "Start a new pathway"),
                        subtitle: String(localized: "Browse life transitions"),
                        icon: "signpost.right.fill"
                    )
                }
            }
        }
        .supportCanvas()
        .navigationTitle(SupportDestination.pathways.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(
            get: { selected != nil },
            set: { if !$0 { selected = nil } }
        )) {
            if let selected {
                PathwayDashboardView(userPathway: selected).environmentObject(container)
            }
        }
        .task(id: retry) { await load() }
    }

    private func load() async {
        guard let userID = appState.currentUser?.id else { return }
        state = .loading
        do {
            let result = try await container.transitionService.fetchActivePathways()
            guard !Task.isCancelled, appState.currentUser?.id == userID else { return }
            pathways = result
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, appState.currentUser?.id == userID else { return }
            state = .failed
        }
    }
}

// MARK: - Seasonal events (Explore → People and Circles)

struct SupportSeasonalHub: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @State private var event: SeasonalEvent?
    @State private var participation: EventParticipation?
    @State private var state = HubLoad.loading
    @State private var retry = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                switch state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .failed:
                    HubFailedView(message: String(localized: "Events couldn't be loaded.")) { retry = UUID() }
                case .loaded:
                    if let event {
                        SeasonalEventCard(event: event, participation: participation) { join(event) }
                    } else {
                        Text("There's no event running right now.")
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
            }
            .padding(SupportTheme.Spacing.m)
        }
        .background(SupportTheme.canvas.ignoresSafeArea())
        .navigationTitle(SupportDestination.seasonalEvents.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: retry) { await load() }
    }

    private func load() async {
        guard let userID = appState.currentUser?.id else { return }
        state = .loading
        do {
            let events = try await container.supabaseDataService.getActiveEvents()
            let all = try await container.supabaseDataService.getEventParticipation()
            guard !Task.isCancelled, appState.currentUser?.id == userID else { return }
            event = events.first
            participation = event.flatMap { current in all.first { $0.eventId == current.id } }
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, appState.currentUser?.id == userID else { return }
            state = .failed
        }
    }

    /// Joining is an explicit tap on the card's own Join button.
    private func join(_ event: SeasonalEvent) {
        guard let userID = appState.currentUser?.id else { return }
        Task {
            do {
                try await container.supabaseDataService.joinEvent(id: event.id)
                let all = try await container.supabaseDataService.getEventParticipation()
                guard appState.currentUser?.id == userID else { return }
                participation = all.first { $0.eventId == event.id }
            } catch {
                appState.showError(.apiError(error.localizedDescription))
            }
        }
    }
}

// MARK: - Buddy (Explore → People and Circles)

struct SupportBuddyHub: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @State private var buddy: BuddyWidgetData?
    @State private var state = HubLoad.loading
    @State private var showInvite = false
    @State private var retry = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                switch state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case .failed:
                    HubFailedView(message: String(localized: "Your buddy status couldn't be loaded.")) { retry = UUID() }
                case .loaded:
                    if let buddy {
                        // Encouragement is only sent when the person taps the widget's own button.
                        BuddyWidget(buddyData: buddy, onSendEncouragement: { sendEncouragement(buddy) })
                    } else {
                        InviteBuddyPrompt(onTap: { showInvite = true })
                    }
                }
            }
            .padding(SupportTheme.Spacing.m)
        }
        .background(SupportTheme.canvas.ignoresSafeArea())
        .navigationTitle(SupportDestination.buddy.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showInvite) {
            InviteBuddySheet().environmentObject(container)
        }
        .task(id: retry) { await load() }
    }

    private func load() async {
        guard let userID = appState.currentUser?.id else { return }
        state = .loading
        do {
            let data = try await container.supabaseDataService.getBuddyWidgetData()
            guard !Task.isCancelled, appState.currentUser?.id == userID else { return }
            buddy = data
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, appState.currentUser?.id == userID else { return }
            state = .failed
        }
    }

    private func sendEncouragement(_ data: BuddyWidgetData) {
        guard let userID = appState.currentUser?.id else { return }
        Task {
            do {
                try await container.supabaseDataService.sendEncouragement(
                    to: data.buddyId, relationshipId: data.relationshipId, type: .encouragement
                )
                let refreshed = try await container.supabaseDataService.getBuddyWidgetData()
                guard appState.currentUser?.id == userID else { return }
                buddy = refreshed
            } catch {
                appState.showError(.apiError("Could not send encouragement"))
            }
        }
    }
}

// MARK: - Capacity (You → Measurements)

struct SupportCapacityHub: View {
    @EnvironmentObject private var container: DependencyContainer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                CapacityIndicator().environmentObject(container.difficultyService)
                Text("Capacity is an estimate used to adjust how demanding suggestions are. It isn't a measure of you, and what you say about how you feel comes first.")
                    .font(.footnote)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
            .padding(SupportTheme.Spacing.m)
        }
        .background(SupportTheme.canvas.ignoresSafeArea())
        .navigationTitle(SupportDestination.capacity.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Mood outlook (You → Measurements)

/// The model's mood outlook, labeled as an interpretation. A suggested intervention opens only when asked for.
struct SupportMoodOutlookHub: View {
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SupportMoodOutlookContent(auth: container.supabaseAuthService)
            .id(appState.accountEpoch)
    }
}

private struct SupportMoodOutlookContent: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var predictive: PredictiveService
    @State private var showIntervention = false

    init(auth: SupabaseAuthService) {
        _predictive = StateObject(wrappedValue: PredictiveService(authService: auth))
    }

    private var ownedIntervention: PreemptiveIntervention? {
        predictive.pendingMoodIntervention.flatMap { $0.userId == appState.currentUser?.id ? $0 : nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                Text("An interpretation of recent patterns. It is not a diagnosis and may be wrong. How you say you feel always comes first.")
                    .font(.footnote)
                    .foregroundStyle(SupportTheme.textSecondary)
                if let prediction = predictive.todayPrediction, prediction.userId == appState.currentUser?.id {
                    MoodPredictionCard(prediction: prediction)
                } else {
                    Text("No outlook is available right now.")
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                if ownedIntervention != nil {
                    Button {
                        showIntervention = true
                    } label: {
                        SupportRowLabel(
                            title: String(localized: "See a suggestion"),
                            subtitle: String(localized: "Optional. Nothing starts unless you choose it."),
                            icon: "lightbulb"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(SupportTheme.Spacing.m)
        }
        .background(SupportTheme.canvas.ignoresSafeArea())
        .navigationTitle(SupportDestination.moodPrediction.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showIntervention) {
            if let intervention = ownedIntervention {
                PreemptiveInterventionView(
                    intervention: intervention,
                    prediction: predictive.todayPrediction,
                    onAccept: { showIntervention = false },
                    onDismiss: { _ in showIntervention = false }
                )
            }
        }
        .task(id: appState.currentUser?.id) {
            // Existing service reads; failures just leave "No outlook is available".
            try? await predictive.fetchTodayPrediction()
            try? await predictive.fetchPendingMoodIntervention()
        }
    }
}
