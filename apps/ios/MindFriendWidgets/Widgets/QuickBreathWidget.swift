import WidgetKit
import SwiftUI

// MARK: - Quick Breath Widget

/// A minimalist widget that provides instant access to breathing exercises
/// with visual feedback on last session time.
struct QuickBreathWidget: Widget {
    let kind: String = "QuickBreathWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickBreathWidgetProvider()) { entry in
            QuickBreathWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Breath")
        .description("Instant access to a calming breathing exercise.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Provider

struct QuickBreathWidgetProvider: TimelineProvider {
    typealias Entry = QuickBreathEntry

    func placeholder(in context: Context) -> QuickBreathEntry {
        QuickBreathEntry(date: Date(), lastSessionTime: nil, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickBreathEntry) -> Void) {
        let lastSession = SharedDataStore.shared.lastBreathingSessionTime
        let entry = QuickBreathEntry(date: Date(), lastSessionTime: lastSession, isPlaceholder: false)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickBreathEntry>) -> Void) {
        let lastSession = SharedDataStore.shared.lastBreathingSessionTime
        let entry = QuickBreathEntry(date: Date(), lastSessionTime: lastSession, isPlaceholder: false)

        // Refresh every hour to update "time since last session"
        // Use safe date calculation with fallback
        let now = Date()
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: now)
            ?? now.addingTimeInterval(3600)
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }
}

// MARK: - Entry

struct QuickBreathEntry: TimelineEntry {
    let date: Date
    let lastSessionTime: Date?
    let isPlaceholder: Bool

    /// Human-readable time since last session
    var timeSinceLastSession: String? {
        guard let lastTime = lastSessionTime else { return nil }

        let interval = Date().timeIntervalSince(lastTime)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return days == 1 ? "Yesterday" : "\(days)d ago"
        }
    }

    /// Whether user has done a breathing session today
    var doneToday: Bool {
        guard let lastTime = lastSessionTime else { return false }
        return Calendar.current.isDateInToday(lastTime)
    }
}

// MARK: - Views

struct QuickBreathWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: QuickBreathEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            smallView
        }
    }

    // MARK: - Small Widget View

    private var smallView: some View {
        VStack(spacing: 12) {
            // Breathing circle animation hint
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.3), lineWidth: 4)
                    .frame(width: 60, height: 60)

                Circle()
                    .fill(entry.doneToday ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                    .frame(width: 52, height: 52)

                Image(systemName: "wind")
                    .font(.title2)
                    .foregroundStyle(entry.doneToday ? .green : .blue)
            }

            VStack(spacing: 4) {
                Text("Breathe")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if let lastSession = entry.timeSinceLastSession {
                    Text(lastSession)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tap to start")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: WidgetDeepLink.quickBreath))
    }

    // MARK: - Circular Widget View (Lock Screen)

    private var circularView: some View {
        ZStack {
            Circle()
                .stroke(Color.blue.opacity(0.5), lineWidth: 2)

            VStack(spacing: 2) {
                Image(systemName: "wind")
                    .font(.title3)

                if entry.doneToday {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
        }
        .widgetURL(URL(string: WidgetDeepLink.quickBreath))
    }

    // MARK: - Rectangular Widget View (Lock Screen)

    private var rectangularView: some View {
        HStack(spacing: 8) {
            Image(systemName: "wind")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Quick Breath")
                    .font(.caption)
                    .fontWeight(.semibold)

                if let lastSession = entry.timeSinceLastSession {
                    Text("Last: \(lastSession)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tap to start")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if entry.doneToday {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .widgetURL(URL(string: WidgetDeepLink.quickBreath))
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    QuickBreathWidget()
} timeline: {
    QuickBreathEntry(date: .now, lastSessionTime: nil, isPlaceholder: false)
    QuickBreathEntry(date: .now, lastSessionTime: Date().addingTimeInterval(-3600), isPlaceholder: false)
    QuickBreathEntry(date: .now, lastSessionTime: Date().addingTimeInterval(-300), isPlaceholder: false)
}

#Preview(as: .accessoryCircular) {
    QuickBreathWidget()
} timeline: {
    QuickBreathEntry(date: .now, lastSessionTime: Date(), isPlaceholder: false)
}

#Preview(as: .accessoryRectangular) {
    QuickBreathWidget()
} timeline: {
    QuickBreathEntry(date: .now, lastSessionTime: Date().addingTimeInterval(-1800), isPlaceholder: false)
}
