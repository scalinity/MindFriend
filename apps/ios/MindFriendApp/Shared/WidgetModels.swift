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
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
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

/// Daily quest for widget display
public struct WidgetDailyQuest: Codable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let category: String
    public let xpReward: Int
    public let isCompleted: Bool
    public let assignedDate: Date

    public init(id: String, title: String, description: String, category: String, xpReward: Int, isCompleted: Bool, assignedDate: Date = Date()) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.xpReward = xpReward
        self.isCompleted = isCompleted
        self.assignedDate = assignedDate
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
    public static func emoji(for mood: String) -> String {
        switch mood.lowercased() {
        case "great", "amazing", "excellent":
            return "😊"
        case "good", "happy":
            return "🙂"
        case "okay", "neutral", "fine":
            return "😐"
        case "low", "sad", "down":
            return "😔"
        case "stressed", "anxious", "worried":
            return "😰"
        case "angry", "frustrated":
            return "😤"
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

    public static func exercise(id: String) -> String {
        return "mindfriend://exercise/\(id)"
    }
}
