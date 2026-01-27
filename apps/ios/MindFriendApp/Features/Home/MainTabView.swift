import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    // Progressive disclosure state
    @State private var showFeatureUnlock = false

    // Cache unlocked features state for proper SwiftUI reactivity
    @State private var programsUnlocked = false
    @State private var outcomesUnlocked = false

    var body: some View {
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
                OutcomeHomeView(outcomeService: container.outcomeService)
                    .tabItem {
                        Label(MainTab.outcomes.title, systemImage: MainTab.outcomes.icon)
                    }
                    .tag(MainTab.outcomes)
            }

            // Mentorship tab
            MentorshipTabView()
                .tabItem {
                    Label(MainTab.mentorship.title, systemImage: MainTab.mentorship.icon)
                }
                .tag(MainTab.mentorship)

            // Profile - always visible
            ProfileView()
                .tabItem {
                    Label("More", systemImage: "ellipsis")
                }
                .tag(MainTab.profile)
        }
        .onReceive(container.activationService.$justActivated) { justActivated in
            if justActivated {
                showFeatureUnlock = true
            }
        }
        .onReceive(container.activationService.$unlockedFeatures) { features in
            // Update local state when features change - triggers view refresh
            programsUnlocked = features.contains(.programs)
            outcomesUnlocked = features.contains(.outcomes)
        }
        .task {
            // Load activation state on appear
            await container.activationService.loadActivationState()
            // Initialize local state
            programsUnlocked = container.activationService.isUnlocked(.programs)
            outcomesUnlocked = container.activationService.isUnlocked(.outcomes)
            // Check if justActivated was set before view appeared (timing edge case)
            if container.activationService.justActivated {
                showFeatureUnlock = true
            }
        }
        .sheet(isPresented: $appState.showCrisisResources) {
            CrisisResourcesView()
        }
        .sheet(isPresented: $appState.showPaywall) {
            SubscriptionView()
        }
        .sheet(isPresented: $appState.showWelcomeBack) {
            if let summary = appState.absenceSummary {
                WelcomeBackView(absenceSummary: summary)
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
        // TODO: Add Celebration folder files to Xcode project to enable
        // .celebrationOverlay(pending: $appState.pendingCelebrations)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
