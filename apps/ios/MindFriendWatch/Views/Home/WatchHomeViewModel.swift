import Foundation

@MainActor
final class WatchHomeViewModel: ObservableObject {
    @Published var streak = 0
    @Published var completedToday = 0
    @Published var dailyGoal = 3
    @Published var showBreathing = false
    @Published var showFocus = false

    init() {
        loadData()
    }

    private func loadData() {
        let savedStreak = WatchAppConstants.sharedDefaults.integer(forKey: "watch_streak")
        streak = savedStreak

        let savedCompleted = WatchAppConstants.sharedDefaults.integer(forKey: "watch_completed_today")
        completedToday = savedCompleted

        let savedGoal = WatchAppConstants.sharedDefaults.integer(forKey: "watch_daily_goal")
        dailyGoal = savedGoal > 0 ? savedGoal : 3 // Default to 3 if not set
    }
}
