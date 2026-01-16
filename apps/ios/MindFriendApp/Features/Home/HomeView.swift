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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Greeting
                    GreetingHeader(userName: appState.currentUser?.displayName ?? "Friend")

                    // Level progress
                    if let level = userLevel {
                        LevelProgressView(userLevel: level)
                    }

                    // Active event (if participating)
                    if let event = activeEvent {
                        SeasonalEventCard(
                            event: event,
                            participation: eventParticipation,
                            onJoin: { joinEvent(event) }
                        )
                    }

                    // Mood check-in prompt
                    if let mood = appState.todayMood {
                        TodayMoodCard(mood: mood)
                    } else {
                        MoodPromptCard()
                    }

                    // Today's quest - with proper state handling
                    questCard

                    // Streak with shields
                    StreakCardWithShields(
                        currentStreak: appState.currentStreak,
                        longestStreak: appState.currentUser?.stats.longestStreakDays ?? 0,
                        shieldsRemaining: shieldStatus?.shieldsRemaining ?? appState.currentUser?.stats.streakShieldsRemaining ?? 1,
                        shieldsMax: shieldStatus?.shieldsMax ?? appState.currentUser?.stats.streakShieldsMax ?? 1,
                        recoveryAvailable: shieldStatus?.recoveryQuestAvailable ?? false,
                        streakBeforeBreak: shieldStatus?.streakBeforeBreak,
                        recoveryExpiresAt: shieldStatus?.recoveryQuestExpiresAt,
                        onStartRecovery: startRecoveryQuest
                    )

                    // Weekly Insights
                    InsightsPreviewCard(insight: weeklyInsight)

                    // Quick actions
                    QuickActionsSection()

                    Spacer(minLength: 32)
                }
                .padding()
            }
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
            .task {
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
        questState = .loading

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
            async let eventsTask = container.supabaseDataService.getActiveEvents()
            async let participationTask = container.supabaseDataService.getEventParticipation()
            async let insightTask = container.supabaseDataService.getWeeklySummary()

            // Await all results concurrently
            let (questResult, profileResult, events, participation, insightResult) = try await (
                questTask, profileTask, eventsTask, participationTask, insightTask
            )

            // Compute level info from profile
            let levelResult = UserLevel.from(stats: profileResult.stats)

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

                // Update user profile
                appState.currentUser = profileResult
                appState.currentStreak = profileResult.stats.currentStreakDays
                appState.entitlements = profileResult.entitlements

                // Set level info
                userLevel = levelResult

                // Set first active event and participation
                activeEvent = events.first
                if let event = activeEvent {
                    eventParticipation = participation.first { $0.eventId == event.id }
                }

                // Set weekly insight
                weeklyInsight = insightResult

                // Shield status is set from protection check above
            }
        } catch {
            print("HomeView loadData error: \(error)")
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
        } catch {
            // Don't fail the whole load if re-engagement check fails
            print("Re-engagement check error: \(error)")
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

        let mockQuest = Quest(
            id: "mock-quest-1",
            localDate: ISO8601DateFormatter.dateOnly.string(from: Date()),
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
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Goodnight"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting + ",")
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
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct TodayMoodCard: View {
    let mood: MoodEntry

    var moodEmoji: String {
        switch mood.moodScore {
        case 1: return "😢"
        case 2: return "😔"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😊"
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
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct QuestCard: View {
    let quest: Quest
    @State private var showQuestChoice = false
    @State private var showQuestDetail = false

    private var questCardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Today's Quest", systemImage: "star.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)

                Spacer()

                if quest.status == .completed {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    // Show "Choose" hint for quest choice
                    Label("Choose", systemImage: "arrow.right.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Text(quest.template.title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(quest.template.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

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
                colors: [.orange.opacity(0.1), .yellow.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
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
            QuestChoiceView()
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
        .background(Color(.secondarySystemBackground))
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
        .background(Color(.secondarySystemBackground))
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
        .background(Color(.secondarySystemBackground))
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
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct QuickActionsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            HStack(spacing: 12) {
                NavigationLink {
                    ExerciseLibraryView()
                } label: {
                    QuickActionButton(
                        icon: "figure.mind.and.body",
                        title: "Exercises",
                        color: .purple
                    )
                }

                NavigationLink {
                    MoodHistoryView()
                } label: {
                    QuickActionButton(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Mood History",
                        color: .blue
                    )
                }

                NavigationLink {
                    BadgesView()
                } label: {
                    QuickActionButton(
                        icon: "medal.fill",
                        title: "Badges",
                        color: .yellow
                    )
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

                        // Trend indicator
                        if let trend = insight.moodTrend {
                            HStack(spacing: 4) {
                                Text(trend.emoji)
                                Text(trend.rawValue.capitalized)
                                    .font(.subheadline)
                                    .foregroundStyle(Color(trend.color))
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
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(title)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
