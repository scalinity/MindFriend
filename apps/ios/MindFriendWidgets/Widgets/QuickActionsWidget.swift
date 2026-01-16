import WidgetKit
import SwiftUI

// MARK: - Quick Actions Widget

struct QuickActionsWidget: Widget {
    let kind: String = "QuickActionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickActionsWidgetProvider()) { entry in
            QuickActionsWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Actions")
        .description("Access your favorite wellness activities quickly.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Provider

struct QuickActionsWidgetProvider: TimelineProvider {
    typealias Entry = QuickActionsEntry

    func placeholder(in context: Context) -> QuickActionsEntry {
        QuickActionsEntry(
            date: Date(),
            actions: WidgetQuickAction.defaults,
            isPlaceholder: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickActionsEntry) -> Void) {
        let entry = QuickActionsEntry(
            date: Date(),
            actions: SharedDataStore.shared.quickActions,
            isPlaceholder: false
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickActionsEntry>) -> Void) {
        let entry = QuickActionsEntry(
            date: Date(),
            actions: SharedDataStore.shared.quickActions,
            isPlaceholder: false
        )

        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 4, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Entry

struct QuickActionsEntry: TimelineEntry {
    let date: Date
    let actions: [WidgetQuickAction]
    let isPlaceholder: Bool
}

// MARK: - Views

struct QuickActionsWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: QuickActionsEntry

    var body: some View {
        HStack(spacing: 12) {
            ForEach(entry.actions.prefix(3), id: \.id) { action in
                Link(destination: URL(string: action.deepLink) ?? URL(string: "mindfriend://")!) {
                    VStack(spacing: 6) {
                        Image(systemName: action.icon)
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .frame(height: 28)

                        Text(action.title)
                            .font(.caption2)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding()
        .widgetURL(URL(string: WidgetDeepLink.home))
    }
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    QuickActionsWidget()
} timeline: {
    QuickActionsEntry(
        date: .now,
        actions: WidgetQuickAction.defaults,
        isPlaceholder: false
    )
}
