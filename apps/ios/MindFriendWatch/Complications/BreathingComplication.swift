import WidgetKit
import SwiftUI

// MARK: - Breathing Complication

struct BreathingComplication: Widget {
    let kind: String = "BreathingComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BreathingComplicationProvider()) { entry in
            BreathingComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Breathe")
        .description("Quick breathing exercise.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner
        ])
    }
}

// MARK: - Provider

struct BreathingComplicationProvider: TimelineProvider {
    typealias Entry = BreathingComplicationEntry

    func placeholder(in context: Context) -> BreathingComplicationEntry {
        BreathingComplicationEntry(date: Date(), isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (BreathingComplicationEntry) -> Void) {
        let entry = BreathingComplicationEntry(date: Date(), isPlaceholder: false)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BreathingComplicationEntry>) -> Void) {
        let entry = BreathingComplicationEntry(date: Date(), isPlaceholder: false)

        // Static complication - just refresh daily
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        let timeline = Timeline(entries: [entry], policy: .after(tomorrow))
        completion(timeline)
    }
}

// MARK: - Entry

struct BreathingComplicationEntry: TimelineEntry {
    let date: Date
    let isPlaceholder: Bool
}

// MARK: - Views

struct BreathingComplicationEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: BreathingComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryCorner:
            cornerView
        default:
            circularView
        }
    }

    // MARK: - Circular View

    private var circularView: some View {
        ZStack {
            // Breathing ring animation effect (static for complication)
            Circle()
                .stroke(Color.blue.opacity(0.3), lineWidth: 3)

            Circle()
                .fill(Color.blue.opacity(0.2))
                .padding(6)

            VStack(spacing: 0) {
                Image(systemName: "wind")
                    .font(.title3)
                    .foregroundStyle(.blue)

                Text("4-7-8")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .widgetURL(URL(string: "mindfriend://breathing"))
    }

    // MARK: - Corner View

    private var cornerView: some View {
        ZStack {
            Image(systemName: "wind")
                .font(.title3)
                .foregroundStyle(.blue)
        }
        .widgetLabel {
            Text("Breathe")
        }
        .widgetURL(URL(string: "mindfriend://breathing"))
    }
}

// MARK: - Preview

#Preview(as: .accessoryCircular) {
    BreathingComplication()
} timeline: {
    BreathingComplicationEntry(date: .now, isPlaceholder: false)
}

#Preview(as: .accessoryCorner) {
    BreathingComplication()
} timeline: {
    BreathingComplicationEntry(date: .now, isPlaceholder: false)
}
