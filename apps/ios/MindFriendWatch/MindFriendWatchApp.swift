import SwiftUI

@main
struct MindFriendWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() { WatchConnectivityManager.shared.activate() }

    var body: some Scene {
        WindowGroup {
            WatchNavigationView()
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { WatchConnectivityManager.shared.requestSyncFromPhone() }
                }
        }
    }
}

// MARK: - Root Navigation View

struct WatchNavigationView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            WatchHomeView()
                .tag(0)

            WatchMoodView()
                .tag(1)

            WatchStatsView()
                .tag(2)
        }
        .tabViewStyle(.page)
    }
}
