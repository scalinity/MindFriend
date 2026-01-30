import SwiftUI

// MARK: - Quest Loading State
enum QuestLoadingState {
    case loading
    case loaded(Quest)
    case noQuest
    case error(String)
}

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.scenePhase) private var scenePhase
    @State private var questState: QuestLoadingState = .loading
    @State private var isRefreshing = false
    @State private var userLevel: UserLevel?
    @State private var activeEvent: SeasonalEvent?
    @State private var eventParticipation: EventParticipation?
    @State private var weeklyInsight: WeeklySummary?
    // Streak shield state
    @State private var shieldStatus: StreakShieldStatus?
    @State private var showRecoveryQuest = false
    @State private var recoveryQuestData: (attemptId: String, quest: StartRecoveryResult.RecoveryQuestInfo)?
    @State private var lastLoadTime: Date?
    @State private var hasCheckedReengagement = false
    // Mood-adaptive home context
    @State private var homeContext: HomeContext?
    // Buddy widget data
    @State private var buddyWidgetData: BuddyWidgetData?
    @State private var showInviteBuddySheet = false
    // SOS intervention state
    @State private var showSOSIntervention = false
    // Recovery mode state
    @State private var recoveryModeState: RecoveryModeState = .inactive
    @State private var showExitRecoveryModeConfirmation = false
    // Quest Arc state
    @State private var activeQuestArc: UserQuestArc?
    @State private var showQuestArcCatalog = false
    // Mood prediction state
    @State private var todayPrediction: MoodPrediction?
    @State private var pendingMoodIntervention: PreemptiveIntervention?
    @State private var showInterventionSheet = false
    // Life Transition Pathways state
    @State private var activePathways: [UserPathway] = []
    @State private var showPathwaySelection = false
    @State private var selectedPathwayId: String?
    // Home tutorial state
    @AppStorage("home_tutorial_completed") private var homeTutorialCompleted = false
    @State private var showHomeTutorial = false

    /// Background color adapts to mood context
    private var adaptiveBackgroundColor: Color {
        homeContext?.moodContext.backgroundColor ?? Color(uiColor: .systemBackground)
    }

    /// Level to display - prefers AchievementService (real-time updates), falls back to loaded userLevel
    private var displayLevel: UserLevel {
        // Prefer AchievementService data (updates in real-time when XP is earned)
        if let exp = container.achievementService.userExperience {
            // Calculate threshold for next level (not remaining XP)
            let nextLevelThreshold = UserLevel.xpThresholds[min(exp.currentLevel, 49)]
            return UserLevel(
                level: exp.currentLevel,
                title: levelTitle(for: exp.currentLevel),
                currentXP: exp.totalXp,
                nextLevelXP: nextLevelThreshold,
                xpThisWeek: exp.weeklyXp
            )
        }
        // Fallback to loaded userLevel if AchievementService hasn't loaded yet
        if let level = userLevel {
            return level
        }
        // Default level while loading
        return UserLevel(
            level: 1,
            title: "Beginner",
            currentXP: 0,
            nextLevelXP: 100,
            xpThisWeek: 0
        )
    }

    /// Get level title for a given level number
    private func levelTitle(for level: Int) -> String {
        switch level {
        case 1...5: return String(localized: "Beginner")
        case 6...10: return String(localized: "Learner")
        case 11...15: return String(localized: "Explorer")
        case 16...20: return String(localized: "Practitioner")
        case 21...25: return String(localized: "Achiever")
        case 26...30: return String(localized: "Expert")
        case 31...35: return String(localized: "Master")
        case 36...40: return String(localized: "Champion")
        case 41...45: return String(localized: "Legend")
        case 46...50: return String(localized: "Transcendent")
        default: return String(localized: "Beginner")
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if recoveryModeState.isActive {
                RecoveryModeHomeView(
                    recoveryState: recoveryModeState,
                    onExitRecoveryMode: {
                        if recoveryModeState.canManuallyExit {
                            showExitRecoveryModeConfirmation = true
                        }
                    }
                )
                .navigationTitle("Home")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            appState.showCrisisResources = true
                        } label: {
                            Image(systemName: "heart.text.square.fill")
                                .foregroundStyle(.red)
                        }
                        .accessibilityLabel("Crisis Resources")
                    }
                }
                .refreshable {
                    await loadData()
                }
                .confirmationDialog(
                    "Exit Recovery Mode?",
                    isPresented: $showExitRecoveryModeConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Exit Recovery Mode") {
                        Task { await exitRecoveryMode() }
                    }
                    Button("Stay in Recovery Mode", role: .cancel) {}
                } message: {
                    Text("You'll return to the full home screen with all features.")
                }
            } else {
            ScrollView {
                VStack(spacing: 24) {
                    // Adaptive greeting with time-of-day context
                    AdaptiveGreetingHeader(
                        userName: appState.currentUser?.displayName ?? "Friend",
                        timeOfDay: homeContext?.timeOfDay ?? .current
                    )

                    // Level progress (top for visibility)
                    LevelProgressView(userLevel: displayLevel)

                    // Mood check-in prompt (adapted based on time)
                    if let mood = appState.todayMood {
                        TodayMoodCard(mood: mood)
                    } else {
                        AdaptiveMoodPromptCard(timeOfDay: homeContext?.timeOfDay ?? .current)
                    }

                    // Today's quest - with proper state handling
                    questCard

                    // Capacity indicator (difficulty adjustment)
                    CapacityIndicator()
                        .environmentObject(container.difficultyService)

                    // Streak with shields (moved above briefing for visibility)
                    StreakCardWithShields(
                        currentStreak: appState.currentStreak,
                        longestStreak: appState.currentUser?.stats?.longestStreakDays ?? 0,
                        shieldsRemaining: shieldStatus?.shieldsRemaining ?? appState.currentUser?.stats?.streakShieldsRemaining ?? 1,
                        shieldsMax: shieldStatus?.shieldsMax ?? appState.currentUser?.stats?.streakShieldsMax ?? 1,
                        recoveryAvailable: shieldStatus?.recoveryQuestAvailable ?? false,
                        streakBeforeBreak: shieldStatus?.streakBeforeBreak,
                        recoveryExpiresAt: shieldStatus?.recoveryQuestExpiresAt,
                        onStartRecovery: startRecoveryQuest
                    )

                    // Grace period banner (48-hour window to complete missed quest)
                    if let shieldStatus = shieldStatus,
                       shieldStatus.recoveryQuestAvailable,
                       let expiresAt = shieldStatus.recoveryQuestExpiresAt {
                        GracePeriodBanner(expiresAt: expiresAt) {
                            startRecoveryQuest()
                        }
                    }

                    // Daily Briefing Card (F009)
                    DailyBriefingCard(viewModel: container.dailyBriefingViewModel)
                        .task {
                            await container.dailyBriefingViewModel.loadTodaysBriefing()
                        }

                    // Wellbeing Debt Card (N006 - real data)
                    WellbeingDebtCard()
                        .environmentObject(container)

                    // Sleep Dashboard Card (F012)
                    NavigationLink {
                        SleepDashboardView()
                            .environmentObject(container)
                    } label: {
                        SleepHomeCard()
                    }

                    // Mood Prediction Card (shows today's AI prediction)
                    if let prediction = todayPrediction {
                        MoodPredictionCard(prediction: prediction) {
                            // If there's a pending intervention, show it
                            if pendingMoodIntervention != nil {
                                showInterventionSheet = true
                            }
                        }
                    }

                    // Supportive message (mood-adaptive)
                    if let message = homeContext?.supportiveMessage {
                        SupportiveMessageCard(
                            message: message,
                            moodContext: homeContext?.moodContext ?? .neutral,
                            showCrisisSupport: homeContext?.shouldShowCrisisSupport ?? false,
                            onCrisisTap: { appState.showCrisisResources = true }
                        )
                    }

                    // Active event (if participating)
                    if let event = activeEvent {
                        SeasonalEventCard(
                            event: event,
                            participation: eventParticipation,
                            onJoin: { joinEvent(event) }
                        )
                    }

                    // Contextual quick actions (mood-adaptive)
                    if let actions = homeContext?.recommendedActions, !actions.isEmpty {
                        ContextualActionsRow(actions: actions)
                    }

                    if let plan = appState.todayActionPlan,
                       !appState.todayActionPlanItems.isEmpty,
                       plan.isActive {
                        ActionPlanHomeCard(plan: plan, items: appState.todayActionPlanItems)
                    }

                    // Quest Arc progress card
                    if let arc = activeQuestArc {
                        QuestArcProgressCard(userArc: arc) {
                            showQuestArcCatalog = true
                        }
                    } else {
                        NoActiveArcCard {
                            showQuestArcCatalog = true
                        }
                    }

                    // Buddy widget or invite prompt
                    if let buddyData = buddyWidgetData {
                        BuddyWidget(
                            buddyData: buddyData,
                            onSendEncouragement: sendBuddyEncouragement
                        )
                    } else {
                        InviteBuddyPrompt(onTap: { showInviteBuddySheet = true })
                    }

                    // Weekly Insights
                    InsightsPreviewCard(insight: weeklyInsight)

                    // Sensory Regulation Toolkit
                    SensoryToolkitCard()

                    // Progress Stories - Weekly Recap
                    ProgressStoryPreviewCard()

                    // Insight Lab - 7-day experiments
                    InsightLabHomeCard()
                        .environmentObject(container.insightLabService)

                    // Life Transition Pathways (F015)
                    if !activePathways.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Your Journeys")
                                    .font(.headline)
                                Spacer()
                                Button("View All") {
                                    showPathwaySelection = true
                                }
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            }

                            ForEach(activePathways) { pathway in
                                ActivePathwayCard(userPathway: pathway) {
                                    selectedPathwayId = pathway.id.uuidString
                                }
                            }
                        }
                    } else {
                        Button {
                            showPathwaySelection = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "map.fill")
                                            .font(.title2)
                                        Text("Explore Life Transitions")
                                            .font(.headline)
                                    }
                                    Text("Get structured support through major life changes")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Standard quick actions (fallback)
                    QuickActionsSection(onSOSTapped: { showSOSIntervention = true })

                    Spacer(minLength: 32)
                }
                .padding()
            }
            .background(adaptiveBackgroundColor)
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Crisis button becomes more prominent when needed
                    Button {
                        appState.showCrisisResources = true
                    } label: {
                        if homeContext?.shouldShowCrisisSupport == true {
                            // Pulsing indicator when crisis support is recommended
                            Image(systemName: "heart.text.square.fill")
                                .foregroundStyle(.red)
                                .symbolEffect(.pulse, options: .repeating)
                        } else {
                            Image(systemName: "heart.text.square.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .accessibilityLabel("Crisis Resources")
                }
            }
            .refreshable {
                await loadData()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Refresh data when app returns to foreground to prevent stale state
                if newPhase == .active {
                    // Only refresh if it's been more than 30 seconds since last load
                    let shouldRefresh = lastLoadTime == nil ||
                        Date().timeIntervalSince(lastLoadTime!) > 30
                    if shouldRefresh {
                        Task { await loadData() }
                    }
                }
            }
            .sheet(isPresented: $showRecoveryQuest) {
                if let data = recoveryQuestData {
                    RecoveryQuestView(
                        streakToRecover: shieldStatus?.streakBeforeBreak ?? 0,
                        attemptId: data.attemptId,
                        quest: data.quest
                    )
                }
            }
            .sheet(isPresented: $showInviteBuddySheet) {
                InviteBuddySheet()
            }
            .fullScreenCover(isPresented: $showSOSIntervention) {
                SOSInterventionView()
                    .environmentObject(container)
            }
            .fullScreenCover(isPresented: $showHomeTutorial) {
                HomeTutorialFlow(onComplete: {
                    homeTutorialCompleted = true
                    showHomeTutorial = false
                })
                .environmentObject(container)
                .environmentObject(appState)
            }
            .sheet(isPresented: $showQuestArcCatalog) {
                QuestArcCatalogView()
                    .environmentObject(container)
            }
            .sheet(isPresented: $showInterventionSheet) {
                if let intervention = pendingMoodIntervention {
                    PreemptiveInterventionView(
                        intervention: intervention,
                        prediction: todayPrediction,
                        onAccept: {
                            showInterventionSheet = false
                            pendingMoodIntervention = nil
                        },
                        onDismiss: { reason in
                            showInterventionSheet = false
                            pendingMoodIntervention = nil
                        }
                    )
                }
            }
            .sheet(isPresented: $showPathwaySelection) {
                NavigationStack {
                    PathwaySelectionView()
                        .environmentObject(container)
                }
            }
            .sheet(item: Binding(
                get: { selectedPathwayId.flatMap { id in activePathways.first { $0.id.uuidString == id } } },
                set: { selectedPathwayId = $0?.id.uuidString }
            )) { pathway in
                NavigationStack {
                    PathwayDashboardView(userPathway: pathway)
                        .environmentObject(container)
                }
            }
            } // End of else block for standard home
            } // End of Group
        } // End of NavigationStack
        // Load data on initial appear
        .task {
            await loadData()
        }
        // Refresh data every time view appears (e.g., returning from mood log, exiting journey)
        .onAppear {
            // Show tutorial on first visit
            if !homeTutorialCompleted {
                showHomeTutorial = true
            }

            Task {
                // Refresh when returning to HomeView after initial load
                // Debounce: only refresh if >0.5s since last load to prevent rapid-fire requests
                if let lastLoad = lastLoadTime {
                    let timeSinceLastLoad = Date().timeIntervalSince(lastLoad)
                    if timeSinceLastLoad > 0.5 {
                        await loadData()
                    }
                }
            }
        }
        // Refresh when quest arc changes (started, paused, resumed, or exited)
        .onReceive(NotificationCenter.default.publisher(for: .questArcDidChange)) { _ in
            Task {
                await loadData()
            }
        }
        // Sync questState when todayQuest changes (e.g., after quest completion in QuestDetailView)
        .onChange(of: appState.todayQuest) { _, newQuest in
            if let quest = newQuest {
                questState = .loaded(quest)
            }
        }
        // XP gain toast overlay
        .xpGainToast()
    } // End of body

    // MARK: - Recovery Mode Exit

    private func exitRecoveryMode() async {
        do {
            let result = try await container.supabaseDataService.toggleRecoveryMode(enable: false)
            if result.success {
                await MainActor.run {
                    recoveryModeState = result.newState
                }
                Analytics.shared.track(.recoveryModeExited, properties: [
                    "method": "manual"
                ])
            } else if let error = result.errorMessage {
                appState.showError(.apiError(error))
            }
        } catch {
            appState.showError(.apiError("Failed to exit recovery mode"))
        }
    }

    // MARK: - Buddy Encouragement

    private func sendBuddyEncouragement() {
        guard let buddyData = buddyWidgetData else { return }

        Task {
            do {
                try await container.supabaseDataService.sendEncouragement(
                    to: buddyData.buddyId,
                    relationshipId: buddyData.relationshipId,
                    type: .encouragement
                )

                // Refresh buddy data to show updated status
                let newBuddyData = try await container.supabaseDataService.getBuddyWidgetData()
                await MainActor.run {
                    buddyWidgetData = newBuddyData
                }

                Analytics.shared.track(.buddyEncouragementSent, properties: [
                    "relationship_id": buddyData.relationshipId
                ])
            } catch {
                appState.showError(.apiError("Could not send encouragement"))
            }
        }
    }

    // MARK: - Recovery Quest

    private func startRecoveryQuest() {
        Task {
            do {
                let result = try await container.supabaseDataService.startRecoveryQuest()

                if result.success, let quest = result.quest {
                    await MainActor.run {
                        recoveryQuestData = (attemptId: result.attemptId ?? "", quest: quest)
                        showRecoveryQuest = true
                    }

                    // Track analytics
                    Analytics.shared.track(.recoveryQuestStarted, properties: [
                        "streak_to_recover": shieldStatus?.streakBeforeBreak ?? 0,
                        "quest_id": quest.id
                    ])
                } else {
                    appState.showError(.apiError(result.error ?? "Failed to start recovery quest"))
                }
            } catch {
                appState.showError(.apiError("Failed to start recovery: \(error.localizedDescription)"))
            }
        }
    }

    // MARK: - Quest Card View
    @ViewBuilder
    private var questCard: some View {
        switch questState {
        case .loading:
            QuestLoadingCard()
        case .loaded(let quest):
            QuestCard(quest: quest)
        case .noQuest:
            QuestEmptyCard(onRetry: { Task { await loadData() } })
        case .error(let message):
            QuestErrorCard(message: message, onRetry: { Task { await loadData() } })
        }
    }

    private func loadData() async {
        // Only show loading state if we don't have a loaded quest
        // This preserves existing data during refresh and prevents flickering if cancelled
        switch questState {
        case .loading, .noQuest, .error:
            questState = .loading
        case .loaded:
            // Keep showing existing quest during refresh
            break
        }

        // Check if we're in dev mode (no real Supabase session)
        let isDevMode = container.supabaseAuthService.userId == nil

        if isDevMode {
            // In dev mode, show a mock quest
            #if DEBUG
            await loadMockData()
            #else
            questState = .error("Please sign in to view your quest")
            #endif
            return
        }

        do {
            // Check and reset weekly XP if needed (fire-and-forget, don't block)
            Task { _ = try? await container.supabaseDataService.resetWeeklyXPIfNeeded() }

            // Check for re-engagement (only once per session)
            if !hasCheckedReengagement {
                hasCheckedReengagement = true
                await checkReengagement()
            }

            // Check streak protection status first (handles shield usage/recovery availability)
            let protectionResult = try? await container.supabaseDataService.checkStreakProtection()

            // Handle streak protection events
            if let protection = protectionResult {
                if protection.streakProtected {
                    // Shield was just used - track analytics
                    // Note: shieldsRemaining and newStreak are non-optional Int
                    Analytics.shared.track(.streakShieldUsed, properties: [
                        "shields_remaining": protection.shieldsRemaining,
                        "streak_protected": protection.newStreak
                    ])
                }
                if protection.recoveryAvailable {
                    // Recovery became available - track analytics
                    Analytics.shared.track(.recoveryQuestOffered, properties: [
                        "streak_to_recover": protection.streakBeforeBreak ?? 0
                    ])
                }

                // Use protection result to build shield status, avoiding duplicate API call
                // Use defaults for fields not returned by protection check
                shieldStatus = StreakShieldStatus(
                    shieldsRemaining: protection.shieldsRemaining,
                    shieldsMax: protection.shieldsMax,
                    shieldsResetAt: nil,  // Not returned from protection check
                    lastShieldUsedAt: nil,  // Not returned from protection check
                    recoveryQuestAvailable: protection.recoveryAvailable,
                    recoveryQuestExpiresAt: protection.recoveryExpiresAt,
                    streakBeforeBreak: protection.streakBeforeBreak,
                    recoveryAttemptsRemaining: protection.recoveryAvailable ? 1 : 0,  // Assume 1 if available
                    recoveryAttemptsMax: 1,  // Default to 1, premium upgrade handled elsewhere
                    currentStreak: protection.newStreak
                )
            }

            // Parallelize independent API calls for better performance
            // Note: Shield status is populated from protection check above to avoid duplicate call
            async let questTask = container.supabaseDataService.getTodayQuest()
            async let profileTask = container.supabaseAuthService.fetchProfile()

            // Optional data (fail gracefully)
            async let eventsTask = try? await container.supabaseDataService.getActiveEvents()
            async let participationTask = try? await container.supabaseDataService.getEventParticipation()
            async let insightTask = try? await container.supabaseDataService.getWeeklySummary()
            async let homeContextTask = try? await container.supabaseDataService.getHomeContext()
            async let todayMoodTask = try? await container.supabaseDataService.getTodayMood()
            async let buddyTask = try? await container.supabaseDataService.getBuddyWidgetData()
            async let celebrationsTask = try? await container.supabaseDataService.getPendingCelebrations()
            async let recoveryModeTask = try? await container.supabaseDataService.fetchRecoveryModeState()
            async let questArcTask = try? await container.questArcsService.getActiveArc()
            // Mood prediction data (fail gracefully)
            async let predictionTask: Void? = try? await container.predictiveService.fetchTodayPrediction()
            async let interventionTask: Void? = try? await container.predictiveService.fetchPendingMoodIntervention()
            // Load user experience (XP/level from user_experience table)
            async let experienceTask: Void? = try? await container.achievementService.loadUserExperience()
            // Load active pathways
            async let pathwaysTask = try? await container.transitionService.fetchActivePathways()

            // Await all results concurrently
            let questResult = try await questTask
            let profileResult = try await profileTask
            let actionPlanResult = try? await container.actionPlanService.fetchLatestPlan(
                timezone: profileResult.timezone ?? "America/New_York"
            )
            let events = await eventsTask ?? []
            let participation = await participationTask ?? []
            let insightResult = (await insightTask) ?? nil
            let contextResult = await homeContextTask
            let todayMoodResult = await todayMoodTask
            let buddyResult = (await buddyTask) ?? nil
            let pendingCelebrations = await celebrationsTask ?? []
            let recoveryModeResult = await recoveryModeTask ?? .inactive
            let questArcResult = await questArcTask ?? nil
            // Await prediction tasks (they update the service's published state)
            _ = await predictionTask
            _ = await interventionTask
            // Await experience load (updates achievementService.userExperience)
            _ = await experienceTask
            let pathwaysResult = await pathwaysTask ?? []

            // Compute level info from user_stats (via achievementService)
            let levelResult: UserLevel
            if let exp = await MainActor.run(body: { container.achievementService.userExperience }) {
                // Calculate threshold for next level (not remaining XP)
                let nextLevelThreshold = UserLevel.xpThresholds[min(exp.currentLevel, 49)]
                levelResult = UserLevel(
                    level: exp.currentLevel,
                    title: levelTitle(for: exp.currentLevel),
                    currentXP: exp.totalXp,
                    nextLevelXP: nextLevelThreshold,
                    xpThisWeek: exp.weeklyXp
                )
            } else {
                // Fallback to default if experience not loaded
                levelResult = UserLevel(
                    level: 1,
                    title: "Beginner",
                    currentXP: 0,
                    nextLevelXP: 100,
                    xpThisWeek: 0
                )
            }

            await MainActor.run {
                // Track load time for stale state prevention
                lastLoadTime = Date()

                // Update quest state
                if let quest = questResult {
                    questState = .loaded(quest)
                    appState.todayQuest = quest
                } else {
                    questState = .noQuest
                }

                if let actionPlanResult {
                    appState.todayActionPlan = actionPlanResult.0
                    appState.todayActionPlanItems = actionPlanResult.1
                } else {
                    appState.todayActionPlan = nil
                    appState.todayActionPlanItems = []
                }

                // Update user profile
                appState.currentUser = profileResult
                appState.currentStreak = profileResult.stats?.currentStreakDays ?? 0

                // Convert UserEntitlements to Entitlements
                if let userEntitlements = profileResult.entitlements {
                    let tier: Tier = userEntitlements.subscriptionTier == "premium" ? .premium : .free
                    appState.entitlements = Entitlements(tier: tier, dailyAiQuota: tier == .premium ? 9999 : 20, dailyAiUsed: 0)
                } else {
                    appState.entitlements = .free
                }

                // Set level info
                userLevel = levelResult

                // Set first active event and participation
                activeEvent = events.first
                if let event = activeEvent {
                    eventParticipation = participation.first { $0.eventId == event.id }
                }

                // Set weekly insight
                weeklyInsight = insightResult

                // Set mood-adaptive home context
                homeContext = contextResult

                // Set today's mood (for check-in prompt logic)
                appState.todayMood = todayMoodResult

                // Set buddy widget data
                buddyWidgetData = buddyResult

                // Set recovery mode state
                recoveryModeState = recoveryModeResult

                // Set active quest arc
                activeQuestArc = questArcResult

                // Set active pathways
                activePathways = pathwaysResult

                // Queue any pending celebrations
                if !pendingCelebrations.isEmpty {
                    appState.addCelebrations(pendingCelebrations)
                }

                // Set mood prediction data from service's published state
                todayPrediction = container.predictiveService.todayPrediction
                pendingMoodIntervention = container.predictiveService.pendingMoodIntervention

                // Shield status is set from protection check above
            }
        } catch is CancellationError {
            // Task was cancelled (e.g., user navigated away or pulled to refresh again)
            // Don't show error state - just return and keep previous state
            Log.ui.debug("HomeView loadData cancelled")
            return
        } catch {
            Log.ui.error("HomeView loadData error", error: error)
            questState = .error(error.localizedDescription)
        }
    }

    // MARK: - Re-engagement Check

    private func checkReengagement() async {
        do {
            // Record session start and get absence info
            let sessionResult = try await container.supabaseDataService.recordSessionStart()

            // If user is returning after 3+ days, fetch detailed absence summary
            if sessionResult.isReturning {
                if let absenceSummary = try await container.supabaseDataService.checkUserAbsence() {
                    await MainActor.run {
                        appState.showWelcomeBackModal(summary: absenceSummary)
                    }
                }
            }
        } catch is CancellationError {
            // Task cancelled - ignore silently
        } catch {
            // Don't fail the whole load if re-engagement check fails
            Log.data.error("Re-engagement check error", error: error)
        }
    }

    private func joinEvent(_ event: SeasonalEvent) {
        Task {
            do {
                try await container.supabaseDataService.joinEvent(id: event.id)

                // Reload participation
                let participation = try await container.supabaseDataService.getEventParticipation()

                await MainActor.run {
                    eventParticipation = participation.first { $0.eventId == event.id }
                }
            } catch {
                appState.showError(.apiError(error.localizedDescription))
            }
        }
    }

    #if DEBUG
    private func loadMockData() async {
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 500_000_000)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let mockQuest = Quest(
            id: "mock-quest-1",
            localDate: dateFormatter.string(from: Date()),
            status: .assigned,
            assignedAt: Date(),
            completedAt: nil,
            template: QuestTemplate(
                id: "mock-template-1",
                type: .gratitude,
                title: "Morning Gratitude",
                description: "Write down 3 things you are grateful for this morning. Take a moment to reflect on the positive aspects of your life.",
                estimatedMinutes: 5,
                difficulty: "easy",
                tags: ["gratitude", "morning"],
                instructions: [
                    QuestInstruction(step: 1, text: "Find a quiet space", durationSeconds: nil),
                    QuestInstruction(step: 2, text: "Think of 3 things you're grateful for", durationSeconds: nil),
                    QuestInstruction(step: 3, text: "Write them down", durationSeconds: nil)
                ]
            )
        )

        await MainActor.run {
            questState = .loaded(mockQuest)
            appState.todayQuest = mockQuest
        }
    }
    #endif
}

// MARK: - Components

struct GreetingHeader: View {
    let userName: String

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return String(localized: "Good morning,")
        case 12..<17: return String(localized: "Good afternoon,")
        case 17..<21: return String(localized: "Good evening,")
        default: return String(localized: "Goodnight,")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(userName)
                .font(.largeTitle)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MoodPromptCard: View {
    var body: some View {
        NavigationLink {
            MoodCheckInView()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How are you feeling?")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Log your mood to track your wellness journey")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct TodayMoodCard: View {
    let mood: MoodEntry

    var moodEmoji: String {
        switch mood.moodScore {
        case 1: return "😔"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😄"
        default: return "😐"
        }
    }

    var body: some View {
        HStack {
            Text(moodEmoji)
                .font(.system(size: 40))

            VStack(alignment: .leading, spacing: 4) {
                Text("Today's mood")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)

                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { index in
                        Image(systemName: index <= mood.moodScore ? "circle.fill" : "circle")
                            .font(.caption)
                            .foregroundStyle(index <= mood.moodScore ? Color.accentColor : Color.secondary)
                    }
                }
            }

            Spacer()

            NavigationLink {
                MoodCheckInView(existingMood: mood)
            } label: {
                Text("Update")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct QuestCard: View {
    let quest: Quest
    @State private var showQuestChoice = false
    @State private var showQuestDetail = false

    /// Color for the journey category
    private var journeyColor: Color {
        guard let arc = quest.arcContext else { return .orange }
        switch arc.arcCategory.lowercased() {
        case "stress": return .blue
        case "sleep": return .indigo
        case "confidence": return .purple
        case "focus": return .teal
        case "resilience": return .green
        default: return .orange
        }
    }

    private var questCardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Journey context header (if part of a journey)
            if let arc = quest.arcContext {
                VStack(alignment: .leading, spacing: 8) {
                    // Journey title and day
                    HStack {
                        Image(systemName: "map.fill")
                            .foregroundStyle(journeyColor)
                        Text(arc.arcTitle)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(journeyColor)
                        Spacer()
                        Text("Day \(arc.currentDay + 1) of \(arc.durationDays)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(.systemGray5))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(journeyColor)
                                .frame(width: geometry.size.width * arc.progressPercentage, height: 6)
                        }
                    }
                    .frame(height: 6)

                    // Milestone indicator
                    if arc.isMilestoneDay {
                        HStack(spacing: 4) {
                            Image(systemName: "flag.fill")
                                .foregroundStyle(.yellow)
                            Text("Milestone day!")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.yellow)
                        }
                    }
                }
                .padding(.bottom, 4)

                Divider()
            }

            // Quest header
            HStack {
                Label(quest.isPartOfJourney ? "Journey Quest" : "Today's Quest", systemImage: "star.fill")
                    .font(.subheadline)
                    .foregroundStyle(quest.isPartOfJourney ? journeyColor : .orange)

                Spacer()

                if quest.status == .completed {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    // Show "Choose" hint for quest choice
                    Label("Choose", systemImage: "arrow.right.circle")
                        .font(.caption)
                        .foregroundStyle(quest.isPartOfJourney ? journeyColor : .orange)
                }
            }

            Text(quest.template.title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(quest.template.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Coaching message for journey quests
            if let arc = quest.arcContext, let coaching = arc.coachingMessage {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundStyle(journeyColor)
                    Text(coaching)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(journeyColor.opacity(0.1))
                .cornerRadius(8)
            }

            HStack {
                Label("\(quest.template.estimatedMinutes) min", systemImage: "clock")
                Spacer()
                Image(systemName: quest.template.type.icon)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            LinearGradient(
                colors: quest.isPartOfJourney
                    ? [journeyColor.opacity(0.1), journeyColor.opacity(0.05)]
                    : [.orange.opacity(0.1), .yellow.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke((quest.isPartOfJourney ? journeyColor : .orange).opacity(0.3), lineWidth: 1)
        )
    }

    var body: some View {
        Group {
            if quest.status == .completed {
                // Completed quests go directly to detail view
                NavigationLink {
                    QuestDetailView(quest: quest)
                } label: {
                    questCardContent
                }
            } else {
                // Assigned quests show the choice sheet first
                Button {
                    showQuestChoice = true
                } label: {
                    questCardContent
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showQuestChoice) {
            QuestChoiceView(assignedQuest: quest)
        }
    }
}

struct QuestLoadingCard: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading today's quest...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct QuestEmptyCard: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("No Quest Available")
                    .font(.headline)

                Text("Check back tomorrow for a new quest!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                onRetry()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct QuestErrorCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            VStack(spacing: 4) {
                Text("Unable to Load Quest")
                    .font(.headline)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            Button {
                onRetry()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.subheadline)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct StreakCard: View {
    let currentStreak: Int
    let longestStreak: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(currentStreak) day streak")
                        .fontWeight(.semibold)
                }

                Text("Longest: \(longestStreak) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if currentStreak >= 7 {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct QuickActionsSection: View {
    @EnvironmentObject var container: DependencyContainer
    @AppStorage("safety_plan.pinned_quick_actions") private var pinnedSafetyPlan = false
    var onSOSTapped: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 12) {
                NavigationLink {
                    LiveSessionsView()
                } label: {
                    HomeQuickActionCard(
                        title: "Live",
                        icon: "person.3.sequence.fill",
                        color: .red
                    )
                }

                NavigationLink {
                    CreativeHubView()
                } label: {
                    HomeQuickActionCard(
                        title: "Create",
                        icon: "paintpalette.fill",
                        color: .pink
                    )
                }

                NavigationLink {
                    ExerciseLibraryView()
                } label: {
                    HomeQuickActionCard(
                        title: "Exercises",
                        icon: "figure.mind.and.body",
                        color: .purple
                    )
                }

                NavigationLink {
                    MoodHistoryView()
                } label: {
                    HomeQuickActionCard(
                        title: "Mood",
                        icon: "chart.line.uptrend.xyaxis",
                        color: .blue
                    )
                }

                NavigationLink {
                    GenerativeHomeView()
                } label: {
                    HomeQuickActionCard(
                        title: "For You",
                        icon: "wand.and.stars",
                        color: .indigo
                    )
                }

                NavigationLink {
                    BadgesView()
                } label: {
                    HomeQuickActionCard(
                        title: "Badges",
                        icon: "medal.fill",
                        color: .yellow
                    )
                }

                NavigationLink {
                    TherapistDiscoveryView()
                } label: {
                    HomeQuickActionCard(
                        title: "Therapists",
                        icon: "person.2.wave.2.fill",
                        color: .teal
                    )
                }

                // Warning Signs - Early detection (F026)
                NavigationLink {
                    WarningSignsDashboardView(engine: container.stressSignatureEngine)
                } label: {
                    HomeQuickActionCard(
                        title: "Alerts",
                        icon: "shield.checkered",
                        color: .purple
                    )
                }

                // SOS Button - accessible but not prominent
                if container.sosCoordinator.settings?.sosEnabled != false {
                    HomeQuickActionCard(
                        title: "SOS",
                        icon: "heart.fill",
                        color: .red,
                        action: onSOSTapped
                    )
                }

                if pinnedSafetyPlan {
                    NavigationLink {
                        SafetyPlanView()
                    } label: {
                        HomeQuickActionCard(
                            title: "Safety",
                            icon: "heart.shield.fill",
                            color: .orange
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Insights Preview Card

struct InsightsPreviewCard: View {
    let insight: WeeklySummary?

    var body: some View {
        NavigationLink {
            WeeklyInsightsView()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Weekly Insights", systemImage: "chart.bar.xaxis")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let insight = insight {
                    HStack(spacing: 16) {
                        // Average mood
                        if let avg = insight.avgMood {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "%.1f", avg))
                                    .font(.title)
                                    .fontWeight(.bold)
                                Text("avg mood")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        // Trend indicator (hide if insufficient data)
                        if let trend = insight.moodTrend,
                           trend != .insufficientData && trend != .baseline {
                            HStack(spacing: 4) {
                                Image(systemName: trend.icon)
                                    .foregroundStyle(trend.color)
                                Text(trend.displayName)
                                    .font(.subheadline)
                                    .foregroundStyle(trend.color)
                            }
                        }
                    }

                    // AI insight preview
                    if let aiInsight = insight.aiInsight {
                        Text(aiInsight)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else {
                    Text("Your personalized insights will appear here on Sunday")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct HomeQuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    var action: (() -> Void)? = nil

    var body: some View {
        if let action = action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 50, height: 50)

                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(color)
            }

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
    }
}

/// Uniform square card for Quick Actions grid
struct HomeQuickActionCard: View {
    let title: String
    let icon: String
    let color: Color
    var action: (() -> Void)? = nil

    var body: some View {
        if let action = action {
            Button(action: action) {
                cardContent
            }
            .buttonStyle(.plain)
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color)

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Mood-Adaptive Components

/// Enhanced greeting header with time-of-day context and icon
struct AdaptiveGreetingHeader: View {
    let userName: String
    let timeOfDay: TimeOfDay

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeOfDay.greeting + ",")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text(userName)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(timeOfDay.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Time-appropriate icon
            Image(systemName: timeOfDay.icon)
                .font(.title)
                .foregroundStyle(iconColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iconColor: Color {
        switch timeOfDay {
        case .morning: return .yellow
        case .afternoon: return .orange
        case .evening: return .purple
        case .night: return .indigo
        }
    }
}

/// Supportive message card shown based on mood context
struct SupportiveMessageCard: View {
    let message: String
    let moodContext: MoodContext
    let showCrisisSupport: Bool
    let onCrisisTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: moodContext == .high ? "sparkles" : "heart.fill")
                    .foregroundStyle(moodContext.accentColor)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }

            if showCrisisSupport {
                Button(action: onCrisisTap) {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.raised.fill")
                        Text("Need extra support?")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(moodContext.accentColor.opacity(0.1))
        .cornerRadius(12)
    }
}

/// Adaptive mood prompt that changes based on time of day
struct AdaptiveMoodPromptCard: View {
    let timeOfDay: TimeOfDay

    private var promptText: String {
        switch timeOfDay {
        case .morning: return "How are you feeling this morning?"
        case .afternoon: return "How's your afternoon going?"
        case .evening: return "How was your day?"
        case .night: return "How are you feeling tonight?"
        }
    }

    private var subtitleText: String {
        switch timeOfDay {
        case .morning: return "Start your day with a check-in"
        case .afternoon: return "A quick check-in helps track your journey"
        case .evening: return "Reflect on how you've been feeling"
        case .night: return "Log your mood before winding down"
        }
    }

    var body: some View {
        NavigationLink {
            MoodCheckInView()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(promptText)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(subtitleText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

/// Contextual quick actions row based on mood and activity
struct ContextualActionsRow: View {
    let actions: [RecommendedAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested for you")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(Array(actions.prefix(3))) { action in
                    ContextualActionButton(action: action)
                }
            }
        }
    }
}

/// Individual contextual action button
struct ContextualActionButton: View {
    let action: RecommendedAction

    var body: some View {
        NavigationLink {
            destinationView
        } label: {
            VStack(spacing: 8) {
                Image(systemName: action.icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)

                Text(action.title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var destinationView: some View {
        switch action.type {
        case .exercise, .breathing:
            ExerciseLibraryView()
        case .chat:
            ChatListView()
        case .circle:
            CirclesListView()
        case .quest:
            QuestChoiceView()
        case .journal:
            ExerciseLibraryView() // Filtered to journaling exercises
        case .celebrate, .share:
            CirclesListView() // Go to circles to share
        }
    }
}

// MARK: - Buddy Widget

struct BuddyWidget: View {
    let buddyData: BuddyWidgetData
    let onSendEncouragement: () -> Void

    @State private var showEncouragementSent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(.tint)
                Text("Your Buddy")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
            }

            // Buddy info
            HStack(spacing: 12) {
                // Avatar placeholder
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(String(buddyData.buddyName.prefix(1)))
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.accentColor)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(buddyData.buddyName)
                        .font(.headline)

                    // Status
                    HStack(spacing: 4) {
                        Image(systemName: buddyData.statusIcon)
                            .font(.caption)
                            .foregroundStyle(buddyData.statusColor)

                        Text(buddyData.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Buddy streak
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(buddyData.buddyStreak)")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
            }

            // Action button
            Button {
                showEncouragementSent = true
                onSendEncouragement()
            } label: {
                HStack {
                    Image(systemName: "hand.wave.fill")
                    Text(buddyData.needsCheckIn ? "Check in on them" : "Send encouragement")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.1))
                .foregroundStyle(Color.accentColor)
                .cornerRadius(8)
            }
            .disabled(showEncouragementSent)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
        .overlay(
            Group {
                if showEncouragementSent {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.green, lineWidth: 2)
                }
            }
        )
        .task(id: showEncouragementSent) {
            if showEncouragementSent {
                try? await Task.sleep(for: .seconds(2))
                showEncouragementSent = false
            }
        }
    }
}

// MARK: - Invite Buddy Prompt

struct InviteBuddyPrompt: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite a Wellness Buddy")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text("3x more likely to reach goals together!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Level Progress Loading View

struct LevelProgressLoadingView: View {
    var body: some View {
        HStack(spacing: 12) {
            // Level badge placeholder
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                // Level text placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 80, height: 14)

                // Progress bar placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: 8)

                // XP text placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 100, height: 12)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
        .redacted(reason: .placeholder)
    }
}

#Preview {
    let container = DependencyContainer()
    return HomeView()
        .environmentObject(AppState())
        .environmentObject(container)
        .environmentObject(container.achievementService)
}
