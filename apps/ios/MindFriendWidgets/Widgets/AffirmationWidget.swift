import WidgetKit
import SwiftUI

// MARK: - Affirmation Widget

/// A widget that displays daily affirmations to inspire and motivate users.
struct AffirmationWidget: Widget {
    let kind: String = "AffirmationWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AffirmationWidgetProvider()) { entry in
            AffirmationWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daily Affirmation")
        .description("Start your day with a positive affirmation.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Provider

struct AffirmationWidgetProvider: TimelineProvider {
    typealias Entry = AffirmationEntry

    func placeholder(in context: Context) -> AffirmationEntry {
        AffirmationEntry(
            date: Date(),
            affirmation: WidgetAffirmation(text: "I am worthy of love and happiness.", category: "self-love"),
            isPlaceholder: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (AffirmationEntry) -> Void) {
        let affirmation = SharedDataStore.shared.dailyAffirmation ?? randomDefaultAffirmation()
        let entry = AffirmationEntry(date: Date(), affirmation: affirmation, isPlaceholder: false)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AffirmationEntry>) -> Void) {
        let affirmation = SharedDataStore.shared.dailyAffirmation ?? randomDefaultAffirmation()
        let entry = AffirmationEntry(date: Date(), affirmation: affirmation, isPlaceholder: false)

        // Refresh at midnight for new affirmation
        // Use safe date calculation with fallback
        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400)
        let midnight = calendar.startOfDay(for: tomorrow)
        let timeline = Timeline(entries: [entry], policy: .after(midnight))
        completion(timeline)
    }

    private func randomDefaultAffirmation() -> WidgetAffirmation {
        // Use day of year to get consistent affirmation per day
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let index = (dayOfYear - 1) % WidgetAffirmation.defaults.count
        return WidgetAffirmation.defaults[index]
    }
}

// MARK: - Entry

struct AffirmationEntry: TimelineEntry {
    let date: Date
    let affirmation: WidgetAffirmation
    let isPlaceholder: Bool
}

// MARK: - Views

struct AffirmationWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: AffirmationEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .accessoryRectangular:
            rectangularView
        default:
            smallView
        }
    }

    // MARK: - Small Widget View

    private var smallView: some View {
        VStack(spacing: 8) {
            // Category icon
            Image(systemName: entry.affirmation.categoryIcon)
                .font(.title2)
                .foregroundStyle(.purple)

            // Affirmation text
            Text(entry.affirmation.text)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: WidgetDeepLink.affirmation))
    }

    // MARK: - Medium Widget View

    private var mediumView: some View {
        HStack(spacing: 16) {
            // Decorative left element
            VStack {
                Image(systemName: entry.affirmation.categoryIcon)
                    .font(.title)
                    .foregroundStyle(.purple.opacity(0.7))
                Spacer()
            }
            .frame(width: 30)

            // Affirmation content
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.affirmation.text)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.9)

                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                    Text("Daily Affirmation")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Decorative right element
            VStack {
                Spacer()
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(.pink.opacity(0.5))
            }
            .frame(width: 30)
        }
        .padding()
        .widgetURL(URL(string: WidgetDeepLink.affirmation))
    }

    // MARK: - Rectangular Widget View (Lock Screen)

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: entry.affirmation.categoryIcon)
                    .font(.caption2)
                Text("Affirmation")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            Text(entry.affirmation.text)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
        }
        .widgetURL(URL(string: WidgetDeepLink.affirmation))
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    AffirmationWidget()
} timeline: {
    AffirmationEntry(
        date: .now,
        affirmation: WidgetAffirmation(text: "I am worthy of love and happiness.", category: "self-love"),
        isPlaceholder: false
    )
}

#Preview(as: .systemMedium) {
    AffirmationWidget()
} timeline: {
    AffirmationEntry(
        date: .now,
        affirmation: WidgetAffirmation(text: "Today I choose peace over worry. I am calm and centered.", category: "calm"),
        isPlaceholder: false
    )
}

#Preview(as: .accessoryRectangular) {
    AffirmationWidget()
} timeline: {
    AffirmationEntry(
        date: .now,
        affirmation: WidgetAffirmation(text: "I am stronger than my challenges.", category: "strength"),
        isPlaceholder: false
    )
}
