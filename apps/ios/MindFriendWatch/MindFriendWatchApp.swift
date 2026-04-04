import SwiftUI

@main
struct MindFriendWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchNavigationView()
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
