import Foundation

// MARK: - Routine Type Enum

enum RoutineType: String, Codable, CaseIterable {
    case morning = "morning"
    case evening = "evening"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .morning:
            return "Morning"
        case .evening:
            return "Evening"
        case .custom:
            return "Custom"
        }
    }
    
    var emoji: String {
        switch self {
        case .morning:
            return "🌅"
        case .evening:
            return "🌙"
        case .custom:
            return "⭐"
        }
    }
}

// MARK: - Routine Model

struct Routine: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let name: String
    let type: RoutineType
    let targetTime: Date?  // When routine should be started (TIME type in DB)
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case type
        case targetTime = "target_time"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    /// Display name with emoji
    var displayName: String {
        "\(type.emoji) \(type.displayName)"
    }
}

// MARK: - Routine Habit Junction Model

struct RoutineHabit: Codable {
    let routineId: UUID
    let habitId: UUID
    let orderIndex: Int
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case routineId = "routine_id"
        case habitId = "habit_id"
        case orderIndex = "order_index"
        case createdAt = "created_at"
    }
}

// MARK: - Routine Completion Model

struct RoutineCompletion: Identifiable, Codable {
    let id: UUID
    let routineId: UUID
    let userId: UUID
    let completedDate: Date  // DATE type in database
    let completedHabitIds: [UUID]
    let skippedHabitIds: [UUID]
    let completionPercentage: Int  // 0-100%
    let totalDurationSeconds: Int
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case routineId = "routine_id"
        case userId = "user_id"
        case completedDate = "completed_date"
        case completedHabitIds = "completed_habit_ids"
        case skippedHabitIds = "skipped_habit_ids"
        case completionPercentage = "completion_percentage"
        case totalDurationSeconds = "total_duration_seconds"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    /// Formatted time display
    var totalDurationFormatted: String {
        let minutes = totalDurationSeconds / 60
        let seconds = totalDurationSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    /// Completion status
    var completionStatus: RoutineCompletionStatus {
        if completionPercentage == 100 {
            return .completed
        } else if completionPercentage >= 50 {
            return .partiallyCompleted
        } else {
            return .notCompleted
        }
    }
}

// MARK: - Routine Completion Status Enum

enum RoutineCompletionStatus {
    case completed
    case partiallyCompleted
    case notCompleted
    
    var displayName: String {
        switch self {
        case .completed:
            return "Completed"
        case .partiallyCompleted:
            return "Partially Completed"
        case .notCompleted:
            return "Not Completed"
        }
    }
    
    var emoji: String {
        switch self {
        case .completed:
            return "✅"
        case .partiallyCompleted:
            return "⚡"
        case .notCompleted:
            return "⭕"
        }
    }
}

// MARK: - Routine Template Model

struct RoutineTemplate: Identifiable, Codable {
    let id: UUID
    let name: String
    let type: RoutineType
    let description: String?
    let targetTime: Date?
    let habitTemplateIds: [UUID]
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case description
        case targetTime = "target_time"
        case habitTemplateIds = "habit_template_ids"
        case createdAt = "created_at"
    }
}

// MARK: - Routine With Habits Model (For UI Display)

struct RoutineWithHabits: Identifiable {
    let routine: Routine
    let habits: [Habit]
    
    var id: UUID {
        routine.id
    }
    
    var totalDuration: Int {
        habits.reduce(0) { $0 + $1.durationSeconds }
    }
    
    var totalDurationFormatted: String {
        let minutes = totalDuration / 60
        let seconds = totalDuration % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}
