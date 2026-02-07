import WidgetKit
import SwiftUI

// MARK: - Shared Defaults (App Group for cross-process access)

private let sharedDefaults = UserDefaults(suiteName: "group.com.mindfriend.app") ?? .standard

// MARK: - Mood Complication

struct MoodComplication: Widget {
    let kind: String = "MoodComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MoodComplicationProvider()) { entry in
            MoodComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Mood")
        .description("Log your mood quickly.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular
        ])
    }
}

// MARK: - Provider

struct MoodComplicationProvider: TimelineProvider {
    typealias Entry = MoodComplicationEntry

    func placeholder(in context: Context) -> MoodComplicationEntry {
        let mood = sharedDefaults.string(forKey: "watch_today_mood_display")
        let moodDate = sharedDefaults.object(forKey: "watch_mood_date_display") as? Date
        let hasLoggedToday = moodDate.map { Calendar.current.isDateInToday($0) } ?? false

        let entry = MoodComplicationEntry(
            date: Date(),
            mood: mood,
            emoji: emojiForMood(mood),
            hasLoggedToday: hasLoggedToday,
            isPlaceholder: true
        )
        return entry
    }

    func getSnapshot(in context: Context, completion: @escaping (MoodComplicationEntry) -> Void) {
        let mood = sharedDefaults.string(forKey: "watch_today_mood_display")
        let moodDate = sharedDefaults.object(forKey: "watch_mood_date_display") as? Date
        let hasLoggedToday = moodDate.map { Calendar.current.isDateInToday($0) } ?? false

        let entry = MoodComplicationEntry(
            date: Date(),
            mood: mood,
            emoji: emojiForMood(mood),
            hasLoggedToday: hasLoggedToday,
            isPlaceholder: false
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MoodComplicationEntry>) -> Void) {
        let mood = sharedDefaults.string(forKey: "watch_today_mood_display")
        let moodDate = sharedDefaults.object(forKey: "watch_mood_date_display") as? Date
        let hasLoggedToday = moodDate.map { Calendar.current.isDateInToday($0) } ?? false

        let entry = MoodComplicationEntry(
            date: Date(),
            mood: mood,
            emoji: emojiForMood(mood),
            hasLoggedToday: hasLoggedToday,
            isPlaceholder: false
        )

        // Refresh every hour or at midnight
        let calendar = Calendar.current
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        let nextUpdate = min(nextHour, midnight)

        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func emojiForMood(_ mood: String?) -> String {
        guard let mood = mood else { return "😊" }
        switch mood.lowercased() {
        case "great", "amazing", "excellent": return "😊"
        case "good", "happy": return "🙂"
        case "okay", "neutral", "fine": return "😐"
        case "low", "sad", "down": return "😔"
        case "stressed", "anxious", "worried": return "😰"
        default: return "🙂"
        }
    }
}

// MARK: - Entry

struct MoodComplicationEntry: TimelineEntry {
    let date: Date
    let mood: String?
    let emoji: String
    let hasLoggedToday: Bool
    let isPlaceholder: Bool
}

// MARK: - Views

struct MoodComplicationEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: MoodComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryCorner:
            cornerView
        case .accessoryRectangular:
            rectangularView
        default:
            circularView
        }
    }

    // MARK: - Circular View

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()

            if entry.hasLoggedToday {
                VStack(spacing: 0) {
                    Text(entry.emoji)
                        .font(.title2)

                    Text("Today")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "plus.circle")
                        .font(.title3)

                    Text("Mood")
                        .font(.system(size: 8))
                }
            }
        }
        .widgetURL(URL(string: "mindfriend://mood"))
    }

    // MARK: - Corner View

    private var cornerView: some View {
        ZStack {
            if entry.hasLoggedToday {
                Text(entry.emoji)
                    .font(.title2)
            } else {
                Image(systemName: "face.smiling")
                    .font(.title3)
            }
        }
        .widgetLabel {
            if entry.hasLoggedToday {
                Text(entry.mood?.capitalized ?? "Mood")
            } else {
                Text("Log mood")
            }
        }
        .widgetURL(URL(string: "mindfriend://mood"))
    }

    // MARK: - Rectangular View

    private var rectangularView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mood")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if entry.hasLoggedToday {
                    HStack(spacing: 4) {
                        Text(entry.emoji)
                            .font(.title3)
                        Text(entry.mood?.capitalized ?? "")
                            .font(.headline)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                        Text("Log mood")
                            .font(.headline)
                    }
                }
            }

            Spacer()

            // Quick mood buttons (if not logged)
            if !entry.hasLoggedToday {
                HStack(spacing: 4) {
                    ForEach(["😊", "😐", "😔"], id: \.self) { emoji in
                        Text(emoji)
                            .font(.caption)
                    }
                }
            }
        }
        .widgetURL(URL(string: "mindfriend://mood"))
    }
}

// MARK: - Preview

#Preview(as: .accessoryCircular) {
    MoodComplication()
} timeline: {
    MoodComplicationEntry(date: .now, mood: nil, emoji: "🙂", hasLoggedToday: false, isPlaceholder: false)
    MoodComplicationEntry(date: .now, mood: "good", emoji: "🙂", hasLoggedToday: true, isPlaceholder: false)
}

#Preview(as: .accessoryRectangular) {
    MoodComplication()
} timeline: {
    MoodComplicationEntry(date: .now, mood: nil, emoji: "🙂", hasLoggedToday: false, isPlaceholder: false)
    MoodComplicationEntry(date: .now, mood: "great", emoji: "😊", hasLoggedToday: true, isPlaceholder: false)
}
