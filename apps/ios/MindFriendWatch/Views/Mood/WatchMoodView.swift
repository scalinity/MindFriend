import SwiftUI
import WidgetKit

struct WatchMoodView: View {
    @State private var selectedMood: String?
    let moods = [
        ("great", "😊"),
        ("good", "🙂"),
        ("okay", "😐"),
        ("low", "😔"),
        ("stressed", "😰")
    ]

    var body: some View {
        VStack(spacing: 12) {
            Text("How are you?")
                .font(.headline)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(moods, id: \.0) { mood, emoji in
                        Button {
                            selectedMood = mood
                            saveMood(mood)
                        } label: {
                            HStack {
                                Text(emoji)
                                    .font(.title)
                                Text(mood.capitalized)
                                    .font(.body)
                                Spacer()
                                if selectedMood == mood {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(selectedMood == mood ? Color.blue.opacity(0.2) : Color.gray.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .padding()
        .navigationTitle("Mood")
    }

    private func saveMood(_ mood: String) {
        // Derive score from mood (great=5 ... stressed=1)
        let moodScoreMap: [String: Int] = ["great": 5, "good": 4, "okay": 3, "low": 2, "stressed": 1]
        let score = moodScoreMap[mood] ?? 3

        // Use Keychain for sensitive mood data
        WatchKeychain.save(mood, forKey: "watch_today_mood")
        WatchKeychain.save(Date().ISO8601Format(), forKey: "watch_mood_date")

        // Also store in shared App Group UserDefaults for complications
        WatchAppConstants.sharedDefaults.set(mood, forKey: "watch_today_mood_display")
        WatchAppConstants.sharedDefaults.set(Date(), forKey: "watch_mood_date_display")

        // Update mood history for stats
        MoodHistoryManager.addMoodEntry(mood)

        // Sync mood to iOS app
        WatchConnectivityManager.shared.sendMoodToPhone(mood, score: score)
    }
}

// MARK: - Mood History Manager

/// Manages 7-day mood history for WatchStatsView
enum MoodHistoryManager {
    private static let historyKey = "watch_mood_history"
    private static let maxDays = 7

    struct MoodEntry: Codable {
        let mood: String
        let date: Date
    }

    /// Add a mood entry to history
    static func addMoodEntry(_ mood: String) {
        var history = loadHistory()

        // Remove any existing entry for today
        let today = Calendar.current.startOfDay(for: Date())
        history.removeAll { Calendar.current.isDate($0.date, inSameDayAs: today) }

        // Add new entry
        history.append(MoodEntry(mood: mood, date: Date()))

        // Keep only last 7 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -maxDays, to: Date()) ?? Date()
        history = history.filter { $0.date > cutoff }

        saveHistory(history)
    }

    /// Load mood history
    static func loadHistory() -> [MoodEntry] {
        guard let data = WatchAppConstants.sharedDefaults.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([MoodEntry].self, from: data) else {
            return []
        }
        return history
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

    private static func saveHistory(_ history: [MoodEntry]) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        WatchAppConstants.sharedDefaults.set(data, forKey: historyKey)
    }

    private static func emojiForMood(_ mood: String) -> String {
        switch mood {
        case "great": return "😊"
        case "good": return "🙂"
        case "okay": return "😐"
        case "low": return "😔"
        case "stressed": return "😰"
        default: return "🙂"
        }
    }
}
