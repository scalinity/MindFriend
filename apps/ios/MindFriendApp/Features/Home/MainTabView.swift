import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter

    // Progressive disclosure state
    @State private var showFeatureUnlock = false

    // Cache unlocked features state for proper SwiftUI reactivity
    @State private var programsUnlocked = false
    @State private var outcomesUnlocked = false
    @State private var activationLoaded = false
    @State private var deepLinkPresentation: DeepLinkRouter.Request?
    @State private var blockedRequestID: UUID?
    @State private var deepLinkDismissing = false

    /// Development switch for the stable Today/Chat/Explore/You shell. Evaluated once per view lifetime; the
    /// legacy shell below is preserved unchanged as the rollback. See `SupportShellFeature`.
    @State private var useSupportShell = SupportShellFeature.isEnabled()
    @StateObject private var supportNavigator = SupportShellNavigator()

    /// The stable shell has no activation-gated navigation, so deep links never wait for activation state.
    private var canPresentDeepLink: Bool {
        appState.authState == .authenticated && appState.sessionRestored && (useSupportShell || activationLoaded) &&
        !showFeatureUnlock && !appState.showCrisisResources && !appState.showPaywall &&
        !appState.showWelcomeBack && !appState.showError && !deepLinkDismissing
    }

    var body: some View {
        shellTabs
        .onReceive(container.activationService.$justActivated) { justActivated in
            if justActivated {
                acknowledgeActivation()
            }
        }
        .onReceive(container.activationService.$unlockedFeatures) { features in
            // Update local state when features change - triggers view refresh
            programsUnlocked = features.contains(.programs)
            outcomesUnlocked = features.contains(.outcomes)
            presentPendingDeepLink()
        }
        .task {
            #if DEBUG
            if SupportSessionUIFixture.isEnabled { return }
            #endif
            // Load activation state on appear
            await container.activationService.loadActivationState()
            // Initialize local state
            programsUnlocked = container.activationService.isUnlocked(.programs)
            outcomesUnlocked = container.activationService.isUnlocked(.outcomes)
            activationLoaded = true
            // Check if justActivated was set before view appeared (timing edge case)
            if container.activationService.justActivated {
                acknowledgeActivation()
            }
        }
        .onChange(of: deepLinkRouter.pendingRequest) { _, _ in presentPendingDeepLink() }
        .onChange(of: deepLinkRouter.requestID) { _, _ in
            if deepLinkRouter.pendingRequest == nil { deepLinkPresentation = nil }
        }
        .onChange(of: canPresentDeepLink) { _, ready in
            if ready { presentPendingDeepLink() }
        }
        .sheet(item: $deepLinkPresentation, onDismiss: {
            deepLinkDismissing = false
            // A link received while a sheet is open waits for its dismissal, without a timer.
            presentPendingDeepLink()
        }) { request in
            DeepLinkDestinationView(request: request, stableShell: useSupportShell)
                .onAppear { deepLinkRouter.consume(request) }
                .supportSheet()
        }
        .sheet(isPresented: $appState.showCrisisResources) {
            CrisisResourcesView().supportSheet()
        }
        .sheet(isPresented: $appState.showPaywall) {
            SubscriptionView().supportSheet()
        }
        .sheet(isPresented: $appState.showWelcomeBack) {
            if let summary = appState.absenceSummary {
                WelcomeBackView(absenceSummary: summary).supportSheet()
            }
        }
        .alert(
            appState.globalError?.title ?? "Error",
            isPresented: $appState.showError,
            presenting: appState.globalError
        ) { _ in
            Button("OK", role: .cancel) { }
        } message: { error in
            Text(error.message)
        }
        .levelUpCelebration(
            isPresented: $appState.showLevelUp,
            level: appState.levelUpLevel,
            title: appState.levelUpTitle
        )
        .fullScreenCover(isPresented: $showFeatureUnlock) {
            FeatureUnlockView(
                unlockedFeatures: [.programs, .outcomes],
                onDismiss: {
                    showFeatureUnlock = false
                    container.activationService.clearJustActivated()
                }
            )
        }
        // One celebration layer for both shells: XP, simple celebrations and milestones.
        .xpGainToast()
        .simpleCelebrations()
        .celebrationOverlay(pending: $appState.pendingCelebrations)
        .task {
            #if DEBUG
            if SupportSessionUIFixture.isEnabled { return }
            #endif
            // The shell owns the greeting's name and the reward queue: refresh the profile
            // and collect unshown milestones once per launch.
            if let profile = try? await container.supabaseAuthService.fetchProfile(),
               appState.currentUser?.id == profile.id {
                appState.refreshProfileEntitlements(profile)
                appState.currentUser = profile
            }
            if let pending = try? await container.supabaseDataService.getPendingCelebrations() {
                appState.addCelebrations(pending)
            }
        }
    }

    /// Legacy shell: tabs appear as features unlock. Kept byte-for-byte equivalent for rollback.
    @ViewBuilder
    private var legacyTabs: some View {
        TabView(selection: $appState.selectedTab) {
            // Home - always visible
            HomeView()
                .tabItem {
                    Label(MainTab.home.title, systemImage: MainTab.home.icon)
                }
                .tag(MainTab.home)

            // Programs - requires activation
            if programsUnlocked {
                ProgramsLibraryView()
                    .tabItem {
                        Label(MainTab.programs.title, systemImage: MainTab.programs.icon)
                    }
                    .tag(MainTab.programs)
            }

            // Chat - always visible
            ChatListView()
                .tabItem {
                    Label(MainTab.chat.title, systemImage: MainTab.chat.icon)
                }
                .tag(MainTab.chat)

            // Progress/Outcomes - requires activation
            if outcomesUnlocked {
                OutcomeHomeView(outcomeService: container.outcomeService, authService: container.supabaseAuthService)
                    .tabItem {
                        Label(MainTab.outcomes.title, systemImage: MainTab.outcomes.icon)
                    }
                    .tag(MainTab.outcomes)
            }

            // Profile/More - always visible (includes Mentorship)
            ProfileView()
                .tabItem {
                    Label("More", systemImage: "ellipsis")
                }
                .tag(MainTab.profile)
        }
    }

    @ViewBuilder
    private var shellTabs: some View {
        if useSupportShell {
            // Account/epoch isolation is owned by the parent: AuthenticatedSupportRoot wraps this whole view in
            // `.id(coordinator.identity.epochID)`, which also recreates `supportNavigator` and the pin store.
            // This view deliberately does not add its own reset.
            SupportShellTabs(accountID: appState.currentUser?.id)
                .environmentObject(supportNavigator)
        } else {
            legacyTabs
        }
    }

    /// The unlock celebration describes tabs that appear on activation. The stable shell never hides tabs, so
    /// it only acknowledges the event (activation analytics/state are unchanged).
    private func acknowledgeActivation() {
        if useSupportShell {
            container.activationService.clearJustActivated()
        } else {
            showFeatureUnlock = true
        }
    }

    /// Route a request in the stable shell. Same request-identity and account guards as the legacy path,
    /// with no activation hold. Record ownership, circle membership, and premium checks stay in
    /// `DeepLinkDestinationView`, which every identifier-bearing route still goes through.
    private func presentInStableShell(_ request: DeepLinkRouter.Request) {
        switch request.route.supportPlacement {
        case .tabRoot(let tab):
            appState.selectedTab = tab
            if case .chat(let id) = request.route, id != nil { return } // ChatListView resolves ownership and consumes this request.
        case .destination(let destination):
            appState.selectedTab = destination.tab.mainTab
            supportNavigator.open(destination)
        case .presented(let tab):
            appState.selectedTab = tab
            deepLinkPresentation = request
            return
        case .externalFlow:
            return // Buddy acceptance has its own authenticated app-level path.
        case .unavailable:
            // Native unavailable screen with a way back, instead of a bare alert.
            appState.selectedTab = SupportShellTab.today.mainTab
            deepLinkPresentation = request
            return
        }
        deepLinkRouter.consume(request)
    }

    private func presentPendingDeepLink() {
        guard canPresentDeepLink,
              let request = deepLinkRouter.requestForPresentation(isAuthenticated: true) else { return }

        if let presented = deepLinkPresentation {
            if presented.id != request.id {
                deepLinkDismissing = true
                deepLinkPresentation = nil
            }
            return
        }

        if useSupportShell {
            presentInStableShell(request)
            return
        }

        let lockedFeature: String?
        switch request.route {
        case .programs, .program, .therapeuticPrograms:
            lockedFeature = programsUnlocked && container.activationService.loadError == nil ? nil : "Programs"
        case .progress, .assessment:
            lockedFeature = outcomesUnlocked && container.activationService.loadError == nil ? nil : "Progress"
        default:
            lockedFeature = nil
        }
        if let lockedFeature {
            appState.selectedTab = .home
            if blockedRequestID != request.id {
                blockedRequestID = request.id
                let message = container.activationService.loadError == nil
                    ? "\(lockedFeature) unlocks after logging a mood or completing a quest and sending a chat message. This link will wait until then."
                    : "Couldn't check whether \(lockedFeature) is unlocked. This link will wait until access can be confirmed."
                appState.showError(.apiError(message))
            }
            return
        }

        switch request.route {
        case .home, .quote:
            appState.selectedTab = .home
        case .profile, .settings:
            appState.selectedTab = .profile
        case .programs:
            appState.selectedTab = .programs
        case .progress, .assessment(code: nil):
            appState.selectedTab = .outcomes
        case .chat(let id):
            appState.selectedTab = .chat
            if id != nil { return } // ChatListView resolves ownership and consumes this request.
        case .unknown:
            appState.showError(.apiError("This link isn't supported or contains an invalid identifier."))
        case .buddy:
            return // Buddy acceptance has its own authenticated app-level path.
        default:
            deepLinkPresentation = request
            return
        }
        deepLinkRouter.consume(request)
    }

}

#Preview {
    let container = DependencyContainer()
    return MainTabView()
        .environmentObject(AppState())
        .environmentObject(container)
        .environmentObject(container.achievementService)
        .environmentObject(DeepLinkRouter.shared)
}


/// The stable Today / Chat / Explore / You shell. Compact width: native `TabView`. Regular width (iPad, wide
/// split view): the same four identities in a native `NavigationSplitView` sidebar. Tab tags reuse
/// `MainTab.home/.chat/.circles/.profile`. Explore/You paths live in `SupportShellNavigator`, so they survive
/// switching between layouts; Today/Chat view state is only kept while a layout is on screen.
private struct SupportShellTabs: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var navigator: SupportShellNavigator
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var pins: SupportPinStore
    /// Regular width keeps visited roots alive (like a TabView does) so switching doesn't discard their state.
    @State private var visited: Set<MainTab> = []

    init(accountID: UUID?) {
        _pins = StateObject(wrappedValue: SupportPinStore(accountID: accountID))
    }

    /// Today derives its primary action from acknowledged local session state.
    @ViewBuilder
    private var todayRoot: some View {
        SupportTodayView()
    }

    @ViewBuilder
    private func root(for tab: SupportShellTab) -> some View {
        switch tab {
        case .today: todayRoot
        case .chat: ChatListView().supportScreen()
        case .explore: SupportExploreView()
        case .you: SupportYouView(extensions: [
            SupportYouExtension(id: "support-history", section: .history, title: "History", icon: "clock") { SupportSessionListView() },
            SupportYouExtension(id: "support-steps", section: .progress, title: "Saved steps", icon: "checkmark.circle") { SupportSavedStepsView() },
            SupportYouExtension(id: "support-reminders", section: .settings, title: "Step reminders", subtitle: "On this device", icon: "bell") { SupportStepReminderSettingsView() }
        ])
        }
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                sidebarLayout
            } else {
                tabLayout
            }
        }
        .environmentObject(pins)
        .onAppear { select(appState.selectedTab) }
        .onChange(of: appState.selectedTab) { _, tab in select(tab) }
    }

    private var tabLayout: some View {
        TabView(selection: $appState.selectedTab) {
            ForEach(SupportShellTab.allCases) { tab in
                root(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.icon) }
                    .tag(tab.mainTab)
            }
        }
        .tint(SupportTheme.accent)
    }

    private var sidebarLayout: some View {
        NavigationSplitView {
            List(SupportShellTab.allCases, selection: Binding<SupportShellTab?>(
                get: { SupportShellTab(mainTab: appState.selectedTab) },
                set: { if let tab = $0 { appState.selectedTab = tab.mainTab } }
            )) { tab in
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(tab.title).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Label(tab.title, systemImage: tab.icon)
                    }
                }
                    .frame(minHeight: SupportTheme.minimumTarget)
                    .accessibilityIdentifier("support-root-\(tab.title)")
                    .tag(tab)
            }
            .navigationTitle("MindFriend")
            .supportScreen()
        } detail: {
            ZStack {
                ForEach(SupportShellTab.allCases) { tab in
                    if visited.contains(tab.mainTab) {
                        let isSelected = appState.selectedTab == tab.mainTab
                        root(for: tab)
                            .opacity(isSelected ? 1 : 0)
                            .allowsHitTesting(isSelected)
                            .accessibilityHidden(!isSelected)
                    }
                }
            }
        }
    }

    /// Onboarding, tutorials, and widgets may still select a legacy tab that no longer exists. Land on the
    /// destination that replaced it instead of showing an empty tab.
    private func select(_ tab: MainTab) {
        if SupportShellTab(mainTab: tab) == nil {
            if let destination = SupportDestination.replacingLegacyTab(tab) {
                navigator.open(destination)
            }
            appState.selectedTab = tab.supportShellTag
            return
        }
        visited.insert(tab)
    }
}

/// Resolves linked identifiers through existing services before constructing their real views.
private struct DeepLinkDestinationView: View {
    let request: DeepLinkRouter.Request
    /// In the stable shell an unavailable link offers a route back to its category. The guarded resolver below
    /// is unchanged: a missing/unauthorized record never falls back to a different record.
    var stableShell = false
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var router: DeepLinkRouter
    @Environment(\.dismiss) private var dismiss
    @State private var destination: Destination?
    @State private var errorMessage: String?
    @State private var retryID = UUID()

    private enum Destination {
        case screen(DeepLinkRoute)
        case quest(Quest)
        case circle(FriendCircle)
        case exercise(Exercise)
        case program(Program)
        case micro(MicroMomentTemplate)
        case sleep(SleepContent)
        case assessment(AssessmentTemplate)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't open link", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        if retryable {
                            Button("Try Again") { retryID = UUID() }
                        }
                        if stableShell {
                            Button(returnTitle) {
                                appState.selectedTab = returnTab
                                dismiss()
                            }
                        }
                    }
                } else if let destination {
                    // One stack for the whole sheet: embedded roots must not add another.
                    destinationView(destination)
                        .environment(\.supportRootEmbedded, true)
                } else {
                    ProgressView("Opening link…")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task(id: retryID) { await resolveDestination() }
    }

    /// The tab whose category this link belongs to (Explore for circles/exercises/programs, You for assessments, ...).
    private var returnTab: MainTab {
        guard let tab = DeepLinkRouter.supportShellTab(for: request.route) else { return SupportShellTab.today.mainTab }
        return tab
    }

    private var returnTitle: String {
        let name = SupportShellTab(mainTab: returnTab)?.title ?? SupportShellTab.today.title
        return String(localized: "Back to \(name)")
    }

    /// Retrying cannot fix an item that is gone or not yours, or a link that isn't supported.
    private var retryable: Bool {
        if case .unknown = request.route { return false }
        return !isUnavailableError
    }
    @State private var isUnavailableError = false

    @ViewBuilder
    private func destinationView(_ destination: Destination) -> some View {
        switch destination {
        case .quest(let quest): QuestDetailView(quest: quest)
        case .circle(let circle): CircleDetailView(circle: circle)
        case .exercise(let exercise): LibraryExercisePlayerView(exercise: exercise, container: container)
        case .program(let program): ProgramDetailView(program: program)
        case .micro(let template):
            MicroMomentPlayerView(template: template) { completion in
                Task {
                    do {
                        _ = try await MicroMomentsService(supabase: container.supabase).recordCompletion(completion)
                    } catch {
                        appState.showError(.apiError("Couldn't save this micro-moment. Please try again."))
                    }
                }
            }
        case .sleep(let content):
            DeepLinkedSleepView(content: content, container: container, appState: appState)
        case .assessment(let template):
            AssessmentFlowView(template: template, outcomeService: container.outcomeService,
                               isPresented: Binding(get: { true }, set: { if !$0 { dismiss() } }))
        case .screen(let route):
            switch route {
            case .mood: MoodCheckInView()
            case .moodHistory: MoodHistoryView()
            case .streak: ShieldHistoryView()
            case .breathing: QuickBreathingView()
            case .meditation, .exerciseLibrary: ExerciseLibraryView()
            case .therapeuticPrograms:
                TherapeuticProgramsListView(service: TherapeuticProgramService(supabase: container.supabase))
            case .journal: JournalListView()
            case .microMoments: MicroMomentsHubView(supabase: container.supabase)
            case .sleep: SleepHomeView(container: container, appState: appState)
            case .circles: CirclesListView()
            case .insights: WeeklyInsightsView()
            case .achievements: AchievementsView()
            default: EmptyView()
            }
        }
    }

    private func resolveDestination() async {
        guard let userID = appState.currentUser?.id,
              appState.authState == .authenticated,
              container.supabaseAuthService.userId == userID else { return }
        destination = nil
        errorMessage = nil
        isUnavailableError = false
        if case .unknown = request.route {
            errorMessage = "This link isn't supported or contains an invalid identifier."
            return
        }
        do {
            let resolved: Destination
            switch request.route {
            case .quest(let id):
                let linkedQuest: Quest?
                if let id {
                    linkedQuest = try await container.supabaseDataService.getQuest(id: id)
                } else {
                    linkedQuest = try await container.supabaseDataService.getTodayQuest()
                }
                guard let quest = linkedQuest else {
                    throw DeepLinkRouter.DestinationError.unavailable
                }
                resolved = .quest(quest)
            case .circles(let id?):
                let detail = try await container.supabaseDataService.getCircle(id: id)
                guard detail.members.contains(where: { UUID(uuidString: $0.userId) == userID }) else {
                    throw DeepLinkRouter.DestinationError.unavailable
                }
                resolved = .circle(detail.circle)
            case .exercise(let id):
                let exercises = try await container.supabaseDataService.getExercises()
                resolved = .exercise(try DeepLinkRouter.linkedItem(id: id, in: exercises))
            case .program(let id):
                let programs = try await container.supabaseDataService.getPrograms()
                resolved = .program(try DeepLinkRouter.linkedItem(id: id, in: programs))
            case .microMoments(let id?):
                let templates = try await MicroMomentsService(supabase: container.supabase).fetchTemplates()
                let template = try DeepLinkRouter.linkedItem(id: id, in: templates)
                if template.isPremium { try await verifyPremiumAccess(userID: userID) }
                resolved = .micro(template)
            case .sleep(let id?):
                let content = try await container.sleepService.fetchAllContent()
                let item = try DeepLinkRouter.linkedItem(id: id, in: content)
                if item.isPremium { try await verifyPremiumAccess(userID: userID) }
                resolved = .sleep(item)
            case .assessment(let code?):
                guard AssessmentType(rawValue: code) != nil else { throw DeepLinkRouter.DestinationError.unavailable }
                try await container.outcomeService.loadAssessmentTemplates()
                guard let template = container.outcomeService.assessmentTemplates.first(where: { $0.code == code }) else {
                    throw DeepLinkRouter.DestinationError.unavailable
                }
                resolved = .assessment(template)
            default:
                resolved = .screen(request.route)
            }
            try Task.checkCancellation()
            guard router.requestID == request.id, appState.currentUser?.id == userID,
                  container.supabaseAuthService.userId == userID, appState.authState == .authenticated else { return }
            destination = resolved
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, router.requestID == request.id,
                  appState.currentUser?.id == userID, container.supabaseAuthService.userId == userID,
                  appState.authState == .authenticated else { return }
            let destinationError = DeepLinkRouter.destinationError(for: error)
            isUnavailableError = destinationError != nil
            errorMessage = destinationError?.errorDescription
                ?? "Couldn't load this item. Check your connection and try again."
        }
    }

    private func verifyPremiumAccess(userID: UUID) async throws {
        // A restored session can still display a cached profile. Fetch the verified profile,
        // including the auth service's sponsored-access mapping, before deciding access.
        let profile = try await container.supabaseAuthService.fetchProfile()
        try Task.checkCancellation()
        guard profile.id == userID, appState.currentUser?.id == userID,
              container.supabaseAuthService.userId == userID, appState.authState == .authenticated,
              router.requestID == request.id else { throw CancellationError() }
        let entitlements: Entitlements = profile.entitlements?.subscriptionTier == "premium" ? .premium : .free
        appState.updateEntitlements(entitlements)
        guard entitlements.tier == .premium else { throw DeepLinkRouter.DestinationError.premium }
    }
}

/// Open the requested catalog item without starting audio merely because a notification was opened.
private struct DeepLinkedSleepView: View {
    let content: SleepContent
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: SleepViewModel
    @State private var showPlayer = false

    init(content: SleepContent, container: DependencyContainer, appState: AppState) {
        self.content = content
        _viewModel = StateObject(wrappedValue: SleepViewModel(container: container, appState: appState))
    }

    var body: some View {
        SleepContentCard(content: content, isPremiumUser: appState.entitlements.tier == .premium) {
            showPlayer = true
        }
        .padding()
        .navigationTitle(content.title)
        .sheet(isPresented: $showPlayer) {
            SleepPlayerView(content: content, viewModel: viewModel)
                .task { await viewModel.play(content) }
        }
    }
}
