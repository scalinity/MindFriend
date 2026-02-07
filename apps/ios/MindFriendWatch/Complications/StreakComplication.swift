import WidgetKit
import SwiftUI

// MARK: - Shared Defaults (App Group for cross-process access)

private let sharedDefaults = UserDefaults(suiteName: "group.com.mindfriend.app") ?? .standard

// MARK: - Streak Complication

struct StreakComplication: Widget {
    let kind: String = "StreakComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakComplicationProvider()) { entry in
            StreakComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Streak")
        .description("See your current wellness streak.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Provider

struct StreakComplicationProvider: TimelineProvider {
    typealias Entry = StreakEntry

    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), streak: 7, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        let streak = sharedDefaults.integer(forKey: "watch_streak")
        let entry = StreakEntry(date: Date(), streak: max(streak, 0), isPlaceholder: false)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let streak = sharedDefaults.integer(forKey: "watch_streak")
        let entry = StreakEntry(date: Date(), streak: max(streak, 0), isPlaceholder: false)

        // Refresh at midnight (streak only changes daily; data-driven updates use reloadTimelines)
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())

        let timeline = Timeline(entries: [entry], policy: .after(midnight))
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

struct StreakComplicationEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: StreakEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryCorner:
            cornerView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        default:
            circularView
        }
    }

    // MARK: - Circular View

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: 0) {
                Image(systemName: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(streakColor)

                Text("\(entry.streak)")
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)
            }
        }
        .widgetURL(URL(string: "mindfriend://streak"))
    }

    // MARK: - Corner View

    private var cornerView: some View {
        ZStack {
            Image(systemName: "flame.fill")
                .font(.title3)
                .foregroundStyle(streakColor)
        }
        .widgetLabel {
            Text("\(entry.streak) days")
        }
        .widgetURL(URL(string: "mindfriend://streak"))
    }

    // MARK: - Rectangular View

    private var rectangularView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Streak")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(streakColor)
                    Text("\(entry.streak)")
                        .font(.headline)
                    Text(entry.streak == 1 ? "day" : "days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Mini progress indicator
            if entry.streak > 0 {
                streakRing
            }
        }
        .widgetURL(URL(string: "mindfriend://streak"))
    }

    // MARK: - Inline View

    private var inlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
            Text("\(entry.streak) day streak")
        }
        .widgetURL(URL(string: "mindfriend://streak"))
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

    private var streakRing: some View {
        let progress = min(Double(entry.streak) / 30.0, 1.0) // Progress toward 30-day milestone

        return ZStack {
            Circle()
                .stroke(streakColor.opacity(0.3), lineWidth: 3)
                .frame(width: 24, height: 24)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(streakColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 24, height: 24)
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Preview

#Preview(as: .accessoryCircular) {
    StreakComplication()
} timeline: {
    StreakEntry(date: .now, streak: 14, isPlaceholder: false)
}

#Preview(as: .accessoryRectangular) {
    StreakComplication()
} timeline: {
    StreakEntry(date: .now, streak: 7, isPlaceholder: false)
}

#Preview(as: .accessoryInline) {
    StreakComplication()
} timeline: {
    StreakEntry(date: .now, streak: 14, isPlaceholder: false)
}
