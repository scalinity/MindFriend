import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem {
                    Label(MainTab.home.title, systemImage: MainTab.home.icon)
                }
                .tag(MainTab.home)

            ChatListView()
                .tabItem {
                    Label(MainTab.chat.title, systemImage: MainTab.chat.icon)
                }
                .tag(MainTab.chat)

            CirclesListView()
                .tabItem {
                    Label(MainTab.circles.title, systemImage: MainTab.circles.icon)
                }
                .tag(MainTab.circles)

            ProfileView()
                .tabItem {
                    Label(MainTab.profile.title, systemImage: MainTab.profile.icon)
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
