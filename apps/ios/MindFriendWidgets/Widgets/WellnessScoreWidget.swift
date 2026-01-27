import WidgetKit
import SwiftUI

// MARK: - Wellness Score Widget

/// A widget that displays the user's current wellness score with trend indicator.
struct WellnessScoreWidget: Widget {
    let kind: String = "WellnessScoreWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WellnessScoreWidgetProvider()) { entry in
            WellnessScoreWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Wellness Score")
        .description("Track your overall wellness at a glance.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Provider

struct WellnessScoreWidgetProvider: TimelineProvider {
    typealias Entry = WellnessScoreEntry

    func placeholder(in context: Context) -> WellnessScoreEntry {
        WellnessScoreEntry(date: Date(), score: 75, trend: 5, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WellnessScoreEntry) -> Void) {
        let score = SharedDataStore.shared.wellnessScore ?? 0
        let trend = SharedDataStore.shared.wellnessScoreTrend
        let entry = WellnessScoreEntry(date: Date(), score: score, trend: trend, isPlaceholder: false)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WellnessScoreEntry>) -> Void) {
        let score = SharedDataStore.shared.wellnessScore ?? 0
        let trend = SharedDataStore.shared.wellnessScoreTrend
        let entry = WellnessScoreEntry(date: Date(), score: score, trend: trend, isPlaceholder: false)

        // Refresh every 4 hours
        // Use safe date calculation with fallback
        let now = Date()
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 4, to: now)
            ?? now.addingTimeInterval(14400) // 4 hours in seconds
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }
}

// MARK: - Entry

struct WellnessScoreEntry: TimelineEntry {
    let date: Date
    let score: Int
    let trend: Int
    let isPlaceholder: Bool

    /// Score color based on value
    var scoreColor: Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }

    /// Trend direction icon
    var trendIcon: String {
        if trend > 0 {
            return "arrow.up.right"
        } else if trend < 0 {
            return "arrow.down.right"
        } else {
            return "arrow.right"
        }
    }

    /// Trend color
    var trendColor: Color {
        if trend > 0 {
            return .green
        } else if trend < 0 {
            return .red
        } else {
            return .secondary
        }
    }

    /// Human-readable score level
    var scoreLevel: String {
        switch score {
        case 80...100: return "Excellent"
        case 60..<80: return "Good"
        case 40..<60: return "Fair"
        case 1..<40: return "Needs Care"
        default: return "No Data"
        }
    }

    /// Whether we have actual data
    var hasData: Bool {
        score > 0
    }
}

// MARK: - Views

struct WellnessScoreWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: WellnessScoreEntry

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
        VStack(spacing: 8) {
            if entry.hasData {
                // Score ring
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                        .frame(width: 70, height: 70)

                    Circle()
                        .trim(from: 0, to: CGFloat(entry.score) / 100)
                        .stroke(entry.scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 70, height: 70)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text("\(entry.score)")
                            .font(.title2)
                            .fontWeight(.bold)

                        HStack(spacing: 2) {
                            Image(systemName: entry.trendIcon)
                                .font(.caption2)
                            if entry.trend != 0 {
                                Text("\(abs(entry.trend))")
                                    .font(.caption2)
                            }
                        }
                        .foregroundStyle(entry.trendColor)
                    }
                }

                Text(entry.scoreLevel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // No data state
                VStack(spacing: 8) {
                    Image(systemName: "heart.text.square")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)

                    Text("No Data Yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Log your mood")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: WidgetDeepLink.wellnessScore))
    }

    // MARK: - Circular Widget View (Lock Screen)

    private var circularView: some View {
        ZStack {
            if entry.hasData {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 4)

                Circle()
                    .trim(from: 0, to: CGFloat(entry.score) / 100)
                    .stroke(entry.scoreColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(entry.score)")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.bold)

                    Image(systemName: entry.trendIcon)
                        .font(.caption2)
                        .foregroundStyle(entry.trendColor)
                }
            } else {
                Image(systemName: "heart.text.square")
                    .font(.title2)
            }
        }
        .widgetURL(URL(string: WidgetDeepLink.wellnessScore))
    }

    // MARK: - Rectangular Widget View (Lock Screen)

    private var rectangularView: some View {
        HStack(spacing: 8) {
            if entry.hasData {
                // Score
                ZStack {
                    Circle()
                        .stroke(entry.scoreColor.opacity(0.3), lineWidth: 3)
                        .frame(width: 36, height: 36)

                    Circle()
                        .trim(from: 0, to: CGFloat(entry.score) / 100)
                        .stroke(entry.scoreColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 36, height: 36)
                        .rotationEffect(.degrees(-90))

                    Text("\(entry.score)")
                        .font(.caption)
                        .fontWeight(.bold)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Wellness")
                        .font(.caption)
                        .fontWeight(.semibold)

                    HStack(spacing: 4) {
                        Text(entry.scoreLevel)
                            .font(.caption2)

                        Image(systemName: entry.trendIcon)
                            .font(.caption2)
                            .foregroundStyle(entry.trendColor)
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()
            } else {
                Image(systemName: "heart.text.square")
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Wellness")
                        .font(.caption)
                        .fontWeight(.semibold)

                    Text("No data yet")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .widgetURL(URL(string: WidgetDeepLink.wellnessScore))
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    WellnessScoreWidget()
} timeline: {
    WellnessScoreEntry(date: .now, score: 85, trend: 5, isPlaceholder: false)
    WellnessScoreEntry(date: .now, score: 65, trend: -3, isPlaceholder: false)
    WellnessScoreEntry(date: .now, score: 0, trend: 0, isPlaceholder: false)
}

#Preview(as: .accessoryCircular) {
    WellnessScoreWidget()
} timeline: {
    WellnessScoreEntry(date: .now, score: 78, trend: 2, isPlaceholder: false)
}

#Preview(as: .accessoryRectangular) {
    WellnessScoreWidget()
} timeline: {
    WellnessScoreEntry(date: .now, score: 72, trend: -1, isPlaceholder: false)
}
