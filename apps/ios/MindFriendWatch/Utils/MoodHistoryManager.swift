import Foundation

/// Thread-safe manager for 7-day mood history storage
/// Used by WatchStatsView and synced from both Watch and iOS mood logging
enum MoodHistoryManager {
    private static let historyKey = "watch_mood_history"
    private static let maxDays = 7
    private static let queue = DispatchQueue(label: "com.mindfriend.moodhistory", qos: .utility)

    struct MoodEntry: Codable {
        let mood: String
        let date: Date
    }

    /// Add a mood entry to history (thread-safe)
    static func addMoodEntry(_ mood: String) {
        queue.sync {
            var history = loadHistoryUnsafe()

            // Remove any existing entry for today
            let today = Calendar.current.startOfDay(for: Date())
            history.removeAll { Calendar.current.isDate($0.date, inSameDayAs: today) }

            // Add new entry
            history.append(MoodEntry(mood: mood, date: Date()))

            // Keep only last 7 days
            let cutoff = Calendar.current.date(byAdding: .day, value: -maxDays, to: Date()) ?? Date()
            history = history.filter { $0.date > cutoff }

            saveHistoryUnsafe(history)
        }
    }

    /// Load mood history (thread-safe)
    static func loadHistory() -> [MoodEntry] {
        queue.sync {
            loadHistoryUnsafe()
        }
    }

    /// Get mood emoji for a specific day offset (0 = today, 1 = yesterday, etc.)
    static func moodEmoji(forDayOffset offset: Int) -> String {
        let calendar = Calendar.current
        guard let targetDate = calendar.date(byAdding: .day, value: -offset, to: Date()) else {
            return "·"
        }

        let history = loadHistory()
        if let entry = history.first(where: { calendar.isDate($0.date, inSameDayAs: targetDate) }) {
            return emojiForMood(entry.mood)
        }
        return "·"
    }

    // MARK: - Private (Unsafe - must be called within queue.sync)

    private static func loadHistoryUnsafe() -> [MoodEntry] {
        guard let data = WatchAppConstants.sharedDefaults.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([MoodEntry].self, from: data) else {
            return []
        }
        return history
    }

    private static func saveHistoryUnsafe(_ history: [MoodEntry]) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        WatchAppConstants.sharedDefaults.set(data, forKey: historyKey)
    }

    private static func emojiForMood(_ mood: String) -> String {
        MoodEmojiMapper.emoji(for: mood)
    }
}
