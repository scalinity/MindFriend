import Foundation
import Combine

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

    private var observation: AnyCancellable?

    init() {
        loadData()
        observation = WatchConnectivityManager.shared.$lastSyncDate.sink { [weak self] _ in self?.loadData() }
    }

    func loadData() {
        let snapshot = SharedDataStore.shared.snapshot()
        let days = WidgetMoodHelper.last7Days(from: snapshot?.weekMoods ?? [])
        weekMoods = days.map { $0.mood.map(WidgetMoodHelper.emoji(for:)) ?? "·" }
        moodsLogged = days.filter { $0.mood != nil }.count
        exercisesDone = snapshot?.weeklyExercisesCompleted ?? 0
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
