import WidgetKit
import SwiftUI

// MARK: - Streak Widget

struct StreakWidget: Widget {
    let kind: String = "StreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakWidgetProvider()) { entry in
            StreakWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Streak")
        .description("See your current wellness streak.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Provider

struct StreakWidgetProvider: TimelineProvider {
    typealias Entry = StreakEntry

    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), streak: 7, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        let entry = StreakEntry(
            date: Date(),
            streak: SharedDataStore.shared.currentStreak,
            isPlaceholder: false
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let entry = StreakEntry(
            date: Date(),
            streak: SharedDataStore.shared.currentStreak,
            isPlaceholder: false
        )

        // Refresh at midnight or every hour
        let calendar = Calendar.current
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        let nextUpdate = min(nextHour, midnight)

        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Entry

struct StreakEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let isPlaceholder: Bool
}

// MARK: - Views

struct StreakWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: StreakEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .accessoryCircular:
            circularView
        case .accessoryInline:
            inlineView
        default:
            smallView
        }
    }

    // MARK: - Small Widget View

    private var smallView: some View {
        VStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 32))
                .foregroundStyle(streakColor)

            Text("\(entry.streak)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(entry.streak == 1 ? "day" : "days")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: WidgetDeepLink.streak))
    }

    // MARK: - Circular Widget View (Lock Screen)

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: 2) {
                Image(systemName: "flame.fill")
                    .font(.caption)

                Text("\(entry.streak)")
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)
            }
        }
        .widgetURL(URL(string: WidgetDeepLink.streak))
    }

    // MARK: - Inline Widget View (Lock Screen)

    private var inlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
            Text("\(entry.streak) day streak")
        }
        .widgetURL(URL(string: WidgetDeepLink.streak))
    }

    // MARK: - Helpers

    private var streakColor: Color {
        if entry.streak >= 30 {
            return .red
        } else if entry.streak >= 7 {
            return .orange
        } else if entry.streak > 0 {
            return .yellow
        } else {
            return .gray
        }
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    StreakWidget()
} timeline: {
    StreakEntry(date: .now, streak: 0, isPlaceholder: false)
    StreakEntry(date: .now, streak: 7, isPlaceholder: false)
    StreakEntry(date: .now, streak: 30, isPlaceholder: false)
}

#Preview(as: .accessoryCircular) {
    StreakWidget()
} timeline: {
    StreakEntry(date: .now, streak: 14, isPlaceholder: false)
}

#Preview(as: .accessoryInline) {
    StreakWidget()
} timeline: {
    StreakEntry(date: .now, streak: 14, isPlaceholder: false)
}
