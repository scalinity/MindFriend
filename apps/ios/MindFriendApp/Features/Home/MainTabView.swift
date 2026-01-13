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
            PaywallView()
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
