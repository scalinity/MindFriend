import Foundation

// MARK: - Habit Category Enum

enum HabitCategory: String, Codable, CaseIterable {
    case breathing = "breathing"
    case meditation = "meditation"
    case journaling = "journaling"
    case movement = "movement"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .breathing:
            return "Breathing"
        case .meditation:
            return "Meditation"
        case .journaling:
            return "Journaling"
        case .movement:
            return "Movement"
        case .custom:
            return "Custom"
        }
    }
}

// MARK: - Habit Difficulty Enum

enum HabitDifficulty: String, Codable, CaseIterable {
    case easy = "easy"
    case medium = "medium"
    case hard = "hard"
    
    var displayName: String {
        switch self {
        case .easy:
            return "Easy"
        case .medium:
            return "Medium"
        case .hard:
            return "Hard"
        }
    }
    
    /// Duration in seconds for each difficulty level
    var defaultDuration: Int {
        switch self {
        case .easy:
            return 120  // 2 minutes
        case .medium:
            return 300  // 5 minutes
        case .hard:
            return 600  // 10 minutes
        }
    }
    
    /// Max duration in seconds (cap for graduation)
    static let maxDuration: Int = 600
}

// MARK: - Habit Model

struct Habit: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let name: String
    let anchor: String  // "After I [anchor], I will [behavior]"
    let behavior: String
    let category: HabitCategory
    let difficulty: HabitDifficulty
    let durationSeconds: Int
    let reminderTime: Date?  // Optional time for reminder
    let reminderMinutesBefore: Int?  // Minutes before reminder_time to notify
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case anchor
        case behavior
        case category
        case difficulty
        case durationSeconds = "duration_seconds"
        case reminderTime = "reminder_time"
        case reminderMinutesBefore = "reminder_minutes_before"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    /// Format: "After I [anchor], I will [behavior]"
    var fullHabitStatement: String {
        "After I \(anchor), I will \(behavior)"
    }
    
    /// Display name with emoji
    var displayName: String {
        "\(categoryEmoji) \(name)"
    }
    
    private var categoryEmoji: String {
        switch category {
        case .breathing:
            return "🫁"
        case .meditation:
            return "🧘"
        case .journaling:
            return "📝"
        case .movement:
            return "🏃"
        case .custom:
            return "✨"
        }
    }
}

// MARK: - Habit Completion Model

/// YYYY-MM-DD formatter used for PostgreSQL DATE columns. Fixed to UTC and
/// POSIX locale so the serialized day doesn't shift under device timezone/locale.
enum HabitDateFormatter {
    static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

struct HabitCompletion: Identifiable, Codable {
    let id: UUID
    let habitId: UUID
    let userId: UUID
    let completedDate: Date  // DATE type in database (no time component)
    let currentStreak: Int
    let skipped: Bool
    let skipReason: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case habitId = "habit_id"
        case userId = "user_id"
        case completedDate = "completed_date"
        case currentStreak = "current_streak"
        case skipped
        case skipReason = "skip_reason"
        case createdAt = "created_at"
    }

    init(id: UUID, habitId: UUID, userId: UUID, completedDate: Date, currentStreak: Int, skipped: Bool, skipReason: String?, createdAt: Date) {
        self.id = id
        self.habitId = habitId
        self.userId = userId
        self.completedDate = completedDate
        self.currentStreak = currentStreak
        self.skipped = skipped
        self.skipReason = skipReason
        self.createdAt = createdAt
    }

    // Encode completedDate as YYYY-MM-DD so PostgREST accepts it for the DATE
    // column. The default Supabase encoder emits a full ISO8601 timestamp,
    // which PostgREST rejects when inserting into `completed_date`.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(habitId, forKey: .habitId)
        try container.encode(userId, forKey: .userId)
        try container.encode(HabitDateFormatter.dayOnly.string(from: completedDate), forKey: .completedDate)
        try container.encode(currentStreak, forKey: .currentStreak)
        try container.encode(skipped, forKey: .skipped)
        try container.encodeIfPresent(skipReason, forKey: .skipReason)
        try container.encode(createdAt, forKey: .createdAt)
    }

    // Decode completedDate from YYYY-MM-DD (PostgREST returns DATE columns as
    // a string). Falls back to the outer decoder's date strategy so any
    // future schema change that uses a timestamp still parses.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.habitId = try container.decode(UUID.self, forKey: .habitId)
        self.userId = try container.decode(UUID.self, forKey: .userId)
        if let dateString = try? container.decode(String.self, forKey: .completedDate),
           let parsed = HabitDateFormatter.dayOnly.date(from: dateString) {
            self.completedDate = parsed
        } else {
            self.completedDate = try container.decode(Date.self, forKey: .completedDate)
        }
        self.currentStreak = try container.decode(Int.self, forKey: .currentStreak)
        self.skipped = try container.decode(Bool.self, forKey: .skipped)
        self.skipReason = try container.decodeIfPresent(String.self, forKey: .skipReason)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

// MARK: - Habit Template Model

struct HabitTemplate: Identifiable, Codable {
    let id: UUID
    let name: String
    let category: HabitCategory
    let difficulty: HabitDifficulty
    let defaultDurationSeconds: Int
    let behaviorTemplate: String  // "After I [anchor], I will..." template
    let description: String?
    let anchorExample: String?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case difficulty
        case defaultDurationSeconds = "default_duration_seconds"
        case behaviorTemplate = "behavior_template"
        case description
        case anchorExample = "anchor_example"
        case createdAt = "created_at"
    }
}

// MARK: - Habit Streak Information Model

struct HabitStreakInfo: Equatable {
    let currentStreak: Int
    let longestStreak: Int
    let lastCompletionDate: Date?
    let isCompletedToday: Bool
    let willResetNextDay: Bool  // True if user has skipped or missed
}
