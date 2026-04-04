import Foundation

/// ViewModel for WatchStatsView - loads real data from UserDefaults
@MainActor
final class WatchStatsViewModel: ObservableObject {
    @Published var weekMoods: [String] = []
    @Published var exercisesDone: Int = 0
    @Published var moodsLogged: Int = 0

    private static let dayOfWeekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // Use localized template for proper internationalization
        formatter.setLocalizedDateFormatFromTemplate("E")
        return formatter
    }()

    init() {
        loadData()
    }

    func loadData() {
        // Load week moods from history (most recent 7 days, oldest first)
        var moods: [String] = []
        for dayOffset in (0..<7).reversed() {
            let emoji = MoodHistoryManager.moodEmoji(forDayOffset: dayOffset)
            moods.append(emoji)
        }
        weekMoods = moods

        // Count moods logged this week
        let history = MoodHistoryManager.loadHistory()
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        moodsLogged = history.filter { $0.date > weekAgo }.count

        // Load exercises done (synced from iOS)
        exercisesDone = WatchAppConstants.sharedDefaults.integer(forKey: "watch_exercises_count")
    }

    /// Returns single-letter day label for the given index (0 = oldest day in week)
    func dayLabel(_ index: Int) -> String {
        let today = Date()
        let calendar = Calendar.current
        let dayOffset = 6 - index  // 0 = 6 days ago, 6 = today
        if let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) {
            return String(Self.dayOfWeekFormatter.string(from: date).prefix(1))
        }
        return "?"
    }
}
