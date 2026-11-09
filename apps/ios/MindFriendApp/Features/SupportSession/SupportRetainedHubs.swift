import SwiftUI

// Small hubs that give retained Home-only capabilities a named home in Explore / You (SR-03…SR-07).
// Each hub reuses the existing card / view, loads only its own data through the existing service, and
// requires an explicit tap for any action. None of them reproduces the old Home fan-out.
// Loads are scoped to the signed-in account: a late result for a different account is dropped.

/// Shared with the Explore hubs in SupportExploreView.swift.
enum HubLoad: Equatable {
    case loading, loaded, failed
}

/// Shared "couldn't load" treatment with a retry; local content stays usable.
struct HubFailedView: View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SupportTheme.canvas.ignoresSafeArea())
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SupportTheme.canvas.ignoresSafeArea())
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SupportTheme.canvas.ignoresSafeArea())
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle(SupportDestination.weeklyRecap.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Retained progress route

struct SupportStreaksHub: View {
    var body: some View {
        SupportUnavailableState(
            title: "Your progress is in You",
            message: "Explore your levels, completed quests and badges from the Progress section."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Capacity (You → Measurements)

struct SupportCapacityHub: View {
    @EnvironmentObject private var container: DependencyContainer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                CapacityIndicator().environmentObject(container.difficultyService)
                Text(
                    "Capacity is an estimate used to adjust how demanding suggestions are. It isn't a measure of you, and what you say about how you feel comes first."
                )
                .font(.footnote)
                .foregroundStyle(SupportTheme.textSecondary)
            }
            .padding(SupportTheme.Spacing.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SupportTheme.canvas.ignoresSafeArea())
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
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
                Text(
                    "An interpretation of recent patterns. It is not a diagnosis and may be wrong. How you say you feel always comes first."
                )
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SupportTheme.canvas.ignoresSafeArea())
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
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
