import Foundation
import Combine

@MainActor
final class WatchHomeViewModel: ObservableObject {
    @Published var streak = 0
    @Published var completedToday = 0
    @Published var dailyGoal = 3
    @Published var showBreathing = false
    @Published var showFocus = false

    private var observation: AnyCancellable?

    init() {
        loadData()
        observation = WatchConnectivityManager.shared.$lastSyncDate.sink { [weak self] _ in
            self?.loadData()
        }
    }

    private func loadData() {
        let snapshot = SharedDataStore.shared.snapshot()
        streak = snapshot?.currentStreak ?? 0
        completedToday = snapshot?.completedActivities ?? 0
        dailyGoal = snapshot?.goalActivities ?? 3
    }
}
