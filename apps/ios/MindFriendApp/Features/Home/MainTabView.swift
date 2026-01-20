import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem {
                    Label(MainTab.home.title, systemImage: MainTab.home.icon)
                }
                .tag(MainTab.home)

            ProgramsLibraryView()
                .tabItem {
                    Label(MainTab.programs.title, systemImage: MainTab.programs.icon)
                }
                .tag(MainTab.programs)

            ChatListView()
                .tabItem {
                    Label(MainTab.chat.title, systemImage: MainTab.chat.icon)
                }
                .tag(MainTab.chat)

            OutcomeHomeView(outcomeService: container.outcomeService)
                .tabItem {
                    Label(MainTab.outcomes.title, systemImage: MainTab.outcomes.icon)
                }
                .tag(MainTab.outcomes)

            ProfileView()
                .tabItem {
                    Label("More", systemImage: "ellipsis")
                }
                .tag(MainTab.profile)
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
        // TODO: Add Celebration folder files to Xcode project to enable
        // .celebrationOverlay(pending: $appState.pendingCelebrations)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
