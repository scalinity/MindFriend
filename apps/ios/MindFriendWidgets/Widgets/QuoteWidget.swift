import WidgetKit
import SwiftUI

// MARK: - Quote Widget

struct QuoteWidget: Widget {
    let kind: String = "QuoteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuoteWidgetProvider()) { entry in
            QuoteWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daily Inspiration")
        .description("Start your day with an inspiring quote.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

// MARK: - Provider

struct QuoteWidgetProvider: TimelineProvider {
    typealias Entry = QuoteEntry

    // Default quotes for when no quote is stored
    private static let defaultQuotes: [WidgetDailyQuote] = [
        WidgetDailyQuote(text: "The only way to do great work is to love what you do.", author: "Steve Jobs"),
        WidgetDailyQuote(text: "In the middle of difficulty lies opportunity.", author: "Albert Einstein"),
        WidgetDailyQuote(text: "Be yourself; everyone else is already taken.", author: "Oscar Wilde"),
        WidgetDailyQuote(text: "The mind is everything. What you think you become.", author: "Buddha"),
        WidgetDailyQuote(text: "Happiness is not something ready made. It comes from your own actions.", author: "Dalai Lama"),
        WidgetDailyQuote(text: "Every moment is a fresh beginning.", author: "T.S. Eliot"),
        WidgetDailyQuote(text: "You are never too old to set another goal or to dream a new dream.", author: "C.S. Lewis")
    ]

    func placeholder(in context: Context) -> QuoteEntry {
        QuoteEntry(
            date: Date(),
            quote: WidgetDailyQuote(
                text: "Believe you can and you're halfway there.",
                author: "Theodore Roosevelt"
            ),
            isPlaceholder: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (QuoteEntry) -> Void) {
        let quote = SharedDataStore.shared.dailyQuote ?? randomDefaultQuote()
        let entry = QuoteEntry(date: Date(), quote: quote, isPlaceholder: false)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuoteEntry>) -> Void) {
        let quote = SharedDataStore.shared.dailyQuote ?? randomDefaultQuote()
        let entry = QuoteEntry(date: Date(), quote: quote, isPlaceholder: false)

        // Refresh at midnight for new quote
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        let timeline = Timeline(entries: [entry], policy: .after(midnight))
        completion(timeline)
    }

    private func randomDefaultQuote() -> WidgetDailyQuote {
        // Use day of year to get consistent quote per day
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let index = (dayOfYear - 1) % Self.defaultQuotes.count
        return Self.defaultQuotes[index]
    }
}

// MARK: - Entry

struct QuoteEntry: TimelineEntry {
    let date: Date
    let quote: WidgetDailyQuote
    let isPlaceholder: Bool
}

// MARK: - Views

struct QuoteWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: QuoteEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallQuoteView
        case .systemMedium:
            mediumQuoteView
        case .systemLarge:
            largeQuoteView
        case .accessoryRectangular:
            rectangularQuoteView
        default:
            smallQuoteView
        }
    }

    // MARK: - Small Widget View

    private var smallQuoteView: some View {
        VStack(spacing: 8) {
            Image(systemName: "quote.opening")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(entry.quote.text)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.8)

            if let author = entry.quote.author {
                Text("— \(author)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: WidgetDeepLink.quote))
    }

    // MARK: - Medium Widget View

    private var mediumQuoteView: some View {
        HStack(spacing: 16) {
            // Quote mark
            VStack {
                Image(systemName: "quote.opening")
                    .font(.title)
                    .foregroundStyle(.blue.opacity(0.7))
                Spacer()
            }
            .frame(width: 30)

            // Quote content
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.quote.text)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.9)

                if let author = entry.quote.author {
                    Text("— \(author)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Decorative element
            VStack {
                Spacer()
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.yellow.opacity(0.6))
            }
            .frame(width: 30)
        }
        .padding()
        .widgetURL(URL(string: WidgetDeepLink.quote))
    }

    // MARK: - Large Widget View

    private var largeQuoteView: some View {
        VStack(spacing: 20) {
            Spacer()

            // Quote marks
            HStack {
                Image(systemName: "quote.opening")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue.opacity(0.5))
                Spacer()
            }

            // Quote text
            Text(entry.quote.text)
                .font(.title3)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(6)
                .padding(.horizontal)

            // Author
            if let author = entry.quote.author {
                Text("— \(author)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Daily inspiration label
            HStack {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.yellow)
                Text("Daily Inspiration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
        }
        .padding()
        .widgetURL(URL(string: WidgetDeepLink.quote))
    }

    // MARK: - Rectangular Widget View (Lock Screen)

    private var rectangularQuoteView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "quote.opening")
                    .font(.caption2)
                Text("Daily Quote")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            Text(entry.quote.text)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)

            if let author = entry.quote.author {
                Text("— \(author)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .widgetURL(URL(string: WidgetDeepLink.quote))
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    QuoteWidget()
} timeline: {
    QuoteEntry(
        date: .now,
        quote: WidgetDailyQuote(
            text: "The only way to do great work is to love what you do.",
            author: "Steve Jobs"
        ),
        isPlaceholder: false
    )
}

#Preview(as: .systemMedium) {
    QuoteWidget()
} timeline: {
    QuoteEntry(
        date: .now,
        quote: WidgetDailyQuote(
            text: "Happiness is not something ready made. It comes from your own actions.",
            author: "Dalai Lama"
        ),
        isPlaceholder: false
    )
}

#Preview(as: .systemLarge) {
    QuoteWidget()
} timeline: {
    QuoteEntry(
        date: .now,
        quote: WidgetDailyQuote(
            text: "In the middle of difficulty lies opportunity. Every challenge is a chance to grow and become stronger.",
            author: "Albert Einstein"
        ),
        isPlaceholder: false
    )
}

#Preview(as: .accessoryRectangular) {
    QuoteWidget()
} timeline: {
    QuoteEntry(
        date: .now,
        quote: WidgetDailyQuote(
            text: "Every moment is a fresh beginning.",
            author: "T.S. Eliot"
        ),
        isPlaceholder: false
    )
}
