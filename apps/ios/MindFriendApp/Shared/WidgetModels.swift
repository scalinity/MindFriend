import Foundation

// MARK: - Widget Data Models

/// Daily mood entry for widget display
public struct WidgetDailyMood: Codable, Sendable {
    public let date: Date
    public let mood: String?
    public let score: Int?

    public init(date: Date, mood: String?, score: Int?) {
        self.date = date
        self.mood = mood
        self.score = score
    }

    public var dayOfWeek: String {
        WidgetMoodHelper.makeDayOfWeekFormatter().string(from: date)
    }

    public var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
}

/// Daily quote for widget display
public struct WidgetDailyQuote: Codable, Sendable {
    public let text: String
    public let author: String?
    public let date: Date

    public init(text: String, author: String?, date: Date = Date()) {
        self.text = text
        self.author = author
        self.date = date
    }
}

/// Daily affirmation for widget display
public struct WidgetAffirmation: Codable, Sendable {
    public let text: String
    public let category: String
    public let date: Date
    
    public init(text: String, category: String, date: Date = Date()) {
        self.text = text
        self.category = category
        self.date = date
    }
    
    public var categoryIcon: String {
        switch category.lowercased() {
        case "strength": return "bolt.fill"
        case "calm": return "leaf.fill"
        case "gratitude": return "heart.fill"
        case "growth": return "arrow.up.circle.fill"
        case "confidence": return "star.fill"
        case "self-love": return "heart.circle.fill"
        default: return "sparkles"
        }
    }
    
    /// Default affirmations for when no affirmation is stored
    public static let defaults: [WidgetAffirmation] = [
        WidgetAffirmation(text: "I am worthy of love and happiness.", category: "self-love"),
        WidgetAffirmation(text: "Today I choose peace over worry.", category: "calm"),
        WidgetAffirmation(text: "I am stronger than my challenges.", category: "strength"),
        WidgetAffirmation(text: "I am grateful for this moment.", category: "gratitude"),
        WidgetAffirmation(text: "I am growing every day.", category: "growth"),
        WidgetAffirmation(text: "I believe in my abilities.", category: "confidence"),
        WidgetAffirmation(text: "I release what no longer serves me.", category: "calm"),
        WidgetAffirmation(text: "I am enough, just as I am.", category: "self-love")
    ]
}

/// Daily quest for widget display
public struct WidgetDailyQuest: Codable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let category: String
    public let xpReward: Int
    public let isCompleted: Bool
    public let assignedDate: Date

    public init(
        id: String,
        title: String,
        description: String,
        category: String,
        xpReward: Int,
        isCompleted: Bool,
        assignedDate: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.xpReward = xpReward
        self.isCompleted = isCompleted
        self.assignedDate = assignedDate
    }

    public var categoryIcon: String {
        switch category.lowercased() {
        case "mindfulness": return "brain.head.profile"
        case "gratitude": return "heart.fill"
        case "connection": return "person.2.fill"
        case "movement": return "figure.walk"
        case "creativity": return "paintbrush.fill"
        case "reflection": return "text.book.closed.fill"
        case "self-care": return "sparkles"
        default: return "star.fill"
        }
    }

    public var isToday: Bool {
        Calendar.current.isDateInToday(assignedDate)
    }
}

/// Quick action for widget buttons
public struct WidgetQuickAction: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let icon: String
    public let deepLink: String
    public let category: String

    public init(id: String, title: String, icon: String, deepLink: String, category: String) {
        self.id = id
        self.title = title
        self.icon = icon
        self.deepLink = deepLink
        self.category = category
    }

    public static let defaults: [WidgetQuickAction] = [
        WidgetQuickAction(
            id: "breathing",
            title: "Breathe",
            icon: "wind",
            deepLink: "mindfriend://breathing",
            category: "micro"
        ),
        WidgetQuickAction(
            id: "mood",
            title: "Log Mood",
            icon: "face.smiling",
            deepLink: "mindfriend://mood",
            category: "mood"
        ),
        WidgetQuickAction(
            id: "meditate",
            title: "Meditate",
            icon: "brain.head.profile",
            deepLink: "mindfriend://exercise/meditation",
            category: "exercise"
        ),
        WidgetQuickAction(
            id: "journal",
            title: "Journal",
            icon: "book",
            deepLink: "mindfriend://journal",
            category: "journal"
        )
    ]
}

// MARK: - Mood Helpers

/// Helper functions for mood display in widgets
public enum WidgetMoodHelper {
    /// Creates a thread-safe day-of-week formatter
    /// DateFormatter is not thread-safe, so we create a new instance per use
    /// to avoid crashes when accessed from widget timeline providers (background threads)
    public static func makeDayOfWeekFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter
    }

    public static func emoji(for mood: String) -> String {
        // Delegate to MoodEmojiMapper for canonical mood names
        let mapped = MoodEmojiMapper.emoji(for: mood)
        // MoodEmojiMapper returns "🙂" for unknown moods; handle extra synonyms here
        if mapped != "🙂" || mood.lowercased() == "good" || mood.lowercased() == "happy" {
            return mapped
        }
        // Handle synonyms not in MoodEmojiMapper
        switch mood.lowercased() {
        case "amazing", "excellent":
            return "😁"
        case "happy":
            return "🙂"
        case "neutral", "fine":
            return "😐"
        case "sad", "down":
            return "😕"
        case "anxious", "worried":
            return "😔"
        case "angry", "frustrated":
            return "😔"
        default:
            return "🙂"
        }
    }

    public static func score(for mood: String) -> Int {
        switch mood.lowercased() {
        case "great", "amazing", "excellent":
            return 5
        case "good", "happy":
            return 4
        case "okay", "neutral", "fine":
            return 3
        case "low", "sad", "down":
            return 2
        case "stressed", "anxious", "worried", "angry", "frustrated":
            return 1
        default:
            return 3
        }
    }

    public static func mood(for score: Int) -> String {
        switch score {
        case 5: return "great"
        case 4: return "good"
        case 3: return "okay"
        case 2: return "low"
        case 1: return "stressed"
        default: return "okay"
        }
    }

    /// Extracts the last 7 days from weekMoods array
    public static func last7Days(from weekMoods: [WidgetDailyMood]) -> [WidgetDailyMood] {
        let calendar = Calendar.current
        var days: [WidgetDailyMood] = []

        for dayOffset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let startOfDay = calendar.startOfDay(for: date)

            let moodForDay = weekMoods.first { mood in
                calendar.isDate(mood.date, inSameDayAs: startOfDay)
            }

            days.append(moodForDay ?? WidgetDailyMood(date: startOfDay, mood: nil, score: nil))
        }

        return days
    }
}

// MARK: - Widget Deep Links

/// URL scheme constants for widget deep links
public enum WidgetDeepLink {
    public static let scheme = "mindfriend"
    public static let home = "mindfriend://home"
    public static let mood = "mindfriend://mood"
    public static let streak = "mindfriend://streak"
    public static let breathing = "mindfriend://breathing"
    public static let meditation = "mindfriend://exercise/meditation"
    public static let journal = "mindfriend://journal"
    public static let chat = "mindfriend://chat"
    public static let progress = "mindfriend://progress"

    public static let quest = "mindfriend://quest"
    public static let quote = "mindfriend://quote"
    
    // Ambient Wellness Presence deep links
    public static let quickBreath = "mindfriend://breathing/quick"
    public static let affirmation = "mindfriend://affirmation"
    public static let wellnessScore = "mindfriend://wellness"
    public static let ambientSettings = "mindfriend://settings/ambient"

    public static func exercise(id: String) -> String {
        return "mindfriend://exercise/\(id)"
    }

    public static func quest(id: String) -> String {
        return "mindfriend://quest/\(id)"
    }
}
