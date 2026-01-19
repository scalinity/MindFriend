import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Quest Widget

struct QuestWidget: Widget {
    let kind: String = "QuestWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuestWidgetProvider()) { entry in
            QuestWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daily Quest")
        .description("See today's quest and track completion.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Provider

struct QuestWidgetProvider: TimelineProvider {
    typealias Entry = QuestEntry

    func placeholder(in context: Context) -> QuestEntry {
        QuestEntry(
            date: Date(),
            quest: WidgetDailyQuest(
                id: "placeholder",
                title: "Daily Quest",
                description: "Complete your daily wellness activity",
                category: "mindfulness",
                xpReward: 50,
                isCompleted: false
            ),
            streak: 7,
            isPlaceholder: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (QuestEntry) -> Void) {
        let entry = QuestEntry(
            date: Date(),
            quest: SharedDataStore.shared.dailyQuest,
            streak: SharedDataStore.shared.currentStreak,
            isPlaceholder: false
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuestEntry>) -> Void) {
        let entry = QuestEntry(
            date: Date(),
            quest: SharedDataStore.shared.dailyQuest,
            streak: SharedDataStore.shared.currentStreak,
            isPlaceholder: false
        )

        // Refresh at midnight for new quest or every hour
        let calendar = Calendar.current
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        let nextUpdate = min(nextHour, midnight)

        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Entry

struct QuestEntry: TimelineEntry {
    let date: Date
    let quest: WidgetDailyQuest?
    let streak: Int
    let isPlaceholder: Bool
}

// MARK: - Views

struct QuestWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: QuestEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallQuestView
        case .systemMedium:
            mediumQuestView
        case .accessoryRectangular:
            rectangularQuestView
        default:
            smallQuestView
        }
    }

    // MARK: - Small Widget View

    private var smallQuestView: some View {
        VStack(spacing: 8) {
            if let quest = entry.quest {
                if quest.isCompleted {
                    // Completed state
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)

                    Text("Quest Complete!")
                        .font(.caption)
                        .fontWeight(.medium)

                    Text("+\(quest.xpReward) XP")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    // Active quest
                    Image(systemName: quest.categoryIcon)
                        .font(.system(size: 28))
                        .foregroundStyle(.blue)

                    Text(quest.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Text("+\(quest.xpReward) XP")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                // No quest available
                Image(systemName: "star.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)

                Text("No quest today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: WidgetDeepLink.quest))
    }

    // MARK: - Medium Widget View

    private var mediumQuestView: some View {
        HStack(spacing: 16) {
            // Quest info
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("Daily Quest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let quest = entry.quest {
                    HStack(spacing: 8) {
                        Image(systemName: quest.categoryIcon)
                            .font(.title2)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(quest.title)
                                .font(.headline)
                                .lineLimit(1)

                            Text(quest.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                } else {
                    Text("Check back tomorrow!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Status and streak
            VStack(spacing: 8) {
                if let quest = entry.quest {
                    if quest.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.green)
                        Text("Done!")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Button(intent: CompleteQuestIntent(questId: quest.id)) {
                            VStack(spacing: 4) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.blue)
                                Text("Start")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if entry.streak > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("\(entry.streak)")
                            .fontWeight(.bold)
                    }
                    .font(.caption)
                }
            }
            .frame(width: 80)
        }
        .padding()
        .widgetURL(URL(string: WidgetDeepLink.quest))
    }

    // MARK: - Rectangular Widget View (Lock Screen)

    private var rectangularQuestView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quest")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let quest = entry.quest {
                    HStack(spacing: 4) {
                        Image(systemName: quest.categoryIcon)
                            .font(.caption)
                        Text(quest.title)
                            .font(.headline)
                            .lineLimit(1)
                    }

                    if quest.isCompleted {
                        Text("Completed!")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else {
                        Text("+\(quest.xpReward) XP")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No quest")
                        .font(.headline)
                }
            }

            Spacer()

            if let quest = entry.quest, quest.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if entry.streak > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(entry.streak)")
                        .fontWeight(.bold)
                }
                .font(.caption)
            }
        }
        .widgetURL(URL(string: WidgetDeepLink.quest))
    }
}

// MARK: - App Intents

struct CompleteQuestIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Quest"
    static var description: LocalizedStringResource = "Mark today's quest as completed"

    @Parameter(title: "Quest ID") var questId: String

    func perform() async throws -> some IntentResult {
        SharedDataStore.shared.markQuestCompleted(questId: questId)
        return .result()
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    QuestWidget()
} timeline: {
    QuestEntry(
        date: .now,
        quest: WidgetDailyQuest(
            id: "1",
            title: "5-Minute Meditation",
            description: "Take a moment to breathe and center yourself",
            category: "mindfulness",
            xpReward: 50,
            isCompleted: false
        ),
        streak: 7,
        isPlaceholder: false
    )
    QuestEntry(
        date: .now,
        quest: WidgetDailyQuest(
            id: "1",
            title: "5-Minute Meditation",
            description: "Take a moment to breathe",
            category: "mindfulness",
            xpReward: 50,
            isCompleted: true
        ),
        streak: 8,
        isPlaceholder: false
    )
}

#Preview(as: .systemMedium) {
    QuestWidget()
} timeline: {
    QuestEntry(
        date: .now,
        quest: WidgetDailyQuest(
            id: "1",
            title: "Practice Gratitude",
            description: "Write down three things you're grateful for today",
            category: "gratitude",
            xpReward: 50,
            isCompleted: false
        ),
        streak: 14,
        isPlaceholder: false
    )
}

#Preview(as: .accessoryRectangular) {
    QuestWidget()
} timeline: {
    QuestEntry(
        date: .now,
        quest: WidgetDailyQuest(
            id: "1",
            title: "Morning Walk",
            description: "Get outside for a refreshing walk",
            category: "movement",
            xpReward: 50,
            isCompleted: false
        ),
        streak: 3,
        isPlaceholder: false
    )
}
