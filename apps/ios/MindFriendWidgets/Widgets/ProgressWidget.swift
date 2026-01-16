import WidgetKit
import SwiftUI

// MARK: - Progress Widget

struct ProgressWidget: Widget {
    let kind: String = "ProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProgressWidgetProvider()) { entry in
            ProgressWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Progress")
        .description("Track your daily wellness progress.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Provider

struct ProgressWidgetProvider: TimelineProvider {
    typealias Entry = ProgressEntry

    func placeholder(in context: Context) -> ProgressEntry {
        ProgressEntry(
            date: Date(),
            streak: 7,
            completedActivities: 2,
            goalActivities: 3,
            currentMood: "good",
            weekMoods: [],
            isPlaceholder: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ProgressEntry) -> Void) {
        let store = SharedDataStore.shared
        let entry = ProgressEntry(
            date: Date(),
            streak: store.currentStreak,
            completedActivities: store.todayCompletedActivities,
            goalActivities: store.todayGoalActivities,
            currentMood: store.todayMood,
            weekMoods: store.weekMoods,
            isPlaceholder: false
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProgressEntry>) -> Void) {
        let store = SharedDataStore.shared
        let entry = ProgressEntry(
            date: Date(),
            streak: store.currentStreak,
            completedActivities: store.todayCompletedActivities,
            goalActivities: store.todayGoalActivities,
            currentMood: store.todayMood,
            weekMoods: store.weekMoods,
            isPlaceholder: false
        )

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Entry

struct ProgressEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let completedActivities: Int
    let goalActivities: Int
    let currentMood: String?
    let weekMoods: [WidgetDailyMood]
    let isPlaceholder: Bool

    var completionPercentage: Double {
        guard goalActivities > 0 else { return 0 }
        return min(1.0, Double(completedActivities) / Double(goalActivities))
    }
}

// MARK: - Views

struct ProgressWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: ProgressEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumProgressView
        case .systemLarge:
            largeProgressView
        default:
            mediumProgressView
        }
    }

    // MARK: - Medium Widget View

    private var mediumProgressView: some View {
        HStack(spacing: 20) {
            // Streak
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(Color.orange.opacity(0.2), lineWidth: 6)
                        .frame(width: 60, height: 60)

                    VStack(spacing: 0) {
                        Image(systemName: "flame.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)

                        Text("\(entry.streak)")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                }

                Text("streak")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Today's Progress
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(Color.green.opacity(0.2), lineWidth: 6)
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: entry.completionPercentage)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))

                    Text("\(entry.completedActivities)/\(entry.goalActivities)")
                        .font(.headline)
                }

                Text("today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Mood
            VStack(spacing: 4) {
                if let mood = entry.currentMood {
                    Text(WidgetMoodHelper.emoji(for: mood))
                        .font(.system(size: 40))
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [4]))
                        .frame(width: 50, height: 50)
                        .overlay {
                            Image(systemName: "plus")
                                .foregroundStyle(.secondary)
                        }
                }

                Text("mood")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: WidgetDeepLink.home))
    }

    // MARK: - Large Widget View

    private var largeProgressView: some View {
        VStack(spacing: 16) {
            // Header with streak
            HStack {
                VStack(alignment: .leading) {
                    Text("Today's Progress")
                        .font(.headline)

                    Text(entry.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(entry.streak)")
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
                .clipShape(Capsule())
            }

            // Main progress circle
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.2), lineWidth: 12)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: entry.completionPercentage)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))

                VStack {
                    Text("\(entry.completedActivities)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))

                    Text("of \(entry.goalActivities)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Week mood heatmap
            VStack(alignment: .leading, spacing: 8) {
                Text("This Week")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(last7Days, id: \.date) { dailyMood in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(moodColor(dailyMood.mood))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if let mood = dailyMood.mood {
                                        Text(WidgetMoodHelper.emoji(for: mood))
                                            .font(.caption)
                                    }
                                }

                            Text(String(dailyMood.dayOfWeek.prefix(1)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .widgetURL(URL(string: WidgetDeepLink.home))
    }

    // MARK: - Helpers

    private var last7Days: [WidgetDailyMood] {
        WidgetMoodHelper.last7Days(from: entry.weekMoods)
    }

    private func moodColor(_ mood: String?) -> Color {
        guard let mood = mood else { return .gray.opacity(0.2) }
        switch mood.lowercased() {
        case "great", "amazing":
            return .green
        case "good":
            return .green.opacity(0.6)
        case "okay", "neutral":
            return .yellow
        case "low", "sad":
            return .orange
        case "stressed", "anxious":
            return .red.opacity(0.6)
        default:
            return .gray.opacity(0.3)
        }
    }
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    ProgressWidget()
} timeline: {
    ProgressEntry(
        date: .now,
        streak: 14,
        completedActivities: 2,
        goalActivities: 3,
        currentMood: "good",
        weekMoods: [],
        isPlaceholder: false
    )
}

#Preview(as: .systemLarge) {
    ProgressWidget()
} timeline: {
    ProgressEntry(
        date: .now,
        streak: 14,
        completedActivities: 2,
        goalActivities: 3,
        currentMood: "good",
        weekMoods: [
            WidgetDailyMood(date: Date(), mood: "good", score: 4),
            WidgetDailyMood(date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!, mood: "great", score: 5),
            WidgetDailyMood(date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!, mood: "okay", score: 3)
        ],
        isPlaceholder: false
    )
}
