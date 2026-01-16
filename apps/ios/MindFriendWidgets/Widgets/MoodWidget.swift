import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Mood Widget

struct MoodWidget: Widget {
    let kind: String = "MoodWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MoodWidgetProvider()) { entry in
            MoodWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mood")
        .description("Track your mood quickly.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Provider

struct MoodWidgetProvider: TimelineProvider {
    typealias Entry = MoodEntry

    func placeholder(in context: Context) -> MoodEntry {
        MoodEntry(date: Date(), currentMood: nil, weekMoods: [], isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (MoodEntry) -> Void) {
        let entry = MoodEntry(
            date: Date(),
            currentMood: SharedDataStore.shared.todayMood,
            weekMoods: SharedDataStore.shared.weekMoods,
            isPlaceholder: false
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MoodEntry>) -> Void) {
        let entry = MoodEntry(
            date: Date(),
            currentMood: SharedDataStore.shared.todayMood,
            weekMoods: SharedDataStore.shared.weekMoods,
            isPlaceholder: false
        )

        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Entry

struct MoodEntry: TimelineEntry {
    let date: Date
    let currentMood: String?
    let weekMoods: [WidgetDailyMood]
    let isPlaceholder: Bool
}

// MARK: - Views

struct MoodWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: MoodEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallMoodView
        case .systemMedium:
            mediumMoodView
        case .accessoryRectangular:
            rectangularMoodView
        default:
            smallMoodView
        }
    }

    // MARK: - Small Widget View

    private var smallMoodView: some View {
        VStack(spacing: 12) {
            if let mood = entry.currentMood {
                Text(WidgetMoodHelper.emoji(for: mood))
                    .font(.system(size: 40))

                Text("Today's mood")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("How are you?")
                    .font(.headline)

                // Interactive mood buttons (iOS 17+)
                HStack(spacing: 8) {
                    ForEach(["great", "good", "okay", "low"], id: \.self) { mood in
                        Button(intent: LogMoodIntent(mood: mood)) {
                            Text(WidgetMoodHelper.emoji(for: mood))
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: WidgetDeepLink.mood))
    }

    // MARK: - Medium Widget View

    private var mediumMoodView: some View {
        HStack(spacing: 16) {
            // Current mood
            VStack(spacing: 8) {
                if let mood = entry.currentMood {
                    Text(WidgetMoodHelper.emoji(for: mood))
                        .font(.system(size: 48))
                    Text("Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [4]))
                        .frame(width: 50, height: 50)
                        .overlay {
                            Image(systemName: "plus")
                                .foregroundStyle(.secondary)
                        }
                    Text("Log mood")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Week view
            VStack(alignment: .leading, spacing: 8) {
                Text("This Week")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    ForEach(last7Days, id: \.date) { dailyMood in
                        VStack(spacing: 4) {
                            if let mood = dailyMood.mood {
                                Text(WidgetMoodHelper.emoji(for: mood))
                                    .font(.caption)
                            } else {
                                Text("·")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(String(dailyMood.dayOfWeek.prefix(1)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .widgetURL(URL(string: WidgetDeepLink.mood))
    }

    // MARK: - Rectangular Widget View (Lock Screen)

    private var rectangularMoodView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Mood")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let mood = entry.currentMood {
                    HStack {
                        Text(WidgetMoodHelper.emoji(for: mood))
                        Text(mood.capitalized)
                            .font(.headline)
                    }
                } else {
                    Text("Not logged")
                        .font(.headline)
                }
            }

            Spacer()

            // Quick log buttons
            HStack(spacing: 4) {
                ForEach(["great", "okay", "low"], id: \.self) { mood in
                    Button(intent: LogMoodIntent(mood: mood)) {
                        Text(WidgetMoodHelper.emoji(for: mood))
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .widgetURL(URL(string: WidgetDeepLink.mood))
    }

    // MARK: - Helpers

    private var last7Days: [WidgetDailyMood] {
        WidgetMoodHelper.last7Days(from: entry.weekMoods)
    }
}

// MARK: - App Intents

struct LogMoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Mood"
    static var description: LocalizedStringResource = "Log your current mood"

    @Parameter(title: "Mood") var mood: String

    func perform() async throws -> some IntentResult {
        // Update mood in SharedDataStore
        let score = WidgetMoodHelper.score(for: mood)
        SharedDataStore.shared.updateTodayMood(mood, score: score)
        return .result()
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    MoodWidget()
} timeline: {
    MoodEntry(date: .now, currentMood: nil, weekMoods: [], isPlaceholder: false)
    MoodEntry(date: .now, currentMood: "good", weekMoods: [], isPlaceholder: false)
}

#Preview(as: .systemMedium) {
    MoodWidget()
} timeline: {
    MoodEntry(
        date: .now,
        currentMood: "good",
        weekMoods: [
            WidgetDailyMood(date: Date(), mood: "good", score: 4),
            WidgetDailyMood(date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!, mood: "great", score: 5)
        ],
        isPlaceholder: false
    )
}

#Preview(as: .accessoryRectangular) {
    MoodWidget()
} timeline: {
    MoodEntry(date: .now, currentMood: "okay", weekMoods: [], isPlaceholder: false)
}
