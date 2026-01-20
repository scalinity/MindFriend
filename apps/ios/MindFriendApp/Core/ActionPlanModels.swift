import Foundation

enum ActionPlanStatus: String, Codable {
    case draft
    case scheduled
    case inProgress = "in_progress"
    case completed
    case cancelled
}

enum ActionPlanItemStatus: String, Codable {
    case pending
    case completed
    case skipped
}

enum ActionPlanSourceType: String, Codable {
    case moodCheckin = "mood_checkin"
    case weeklySummary = "weekly_summary"
    case manual
}

enum ActionPlanSize: String, Codable {
    case quick
    case standard

    var displayName: String {
        switch self {
        case .quick: return "Quick"
        case .standard: return "Standard"
        }
    }

    var timeRangeLabel: String {
        switch self {
        case .quick: return "5-8 min"
        case .standard: return "10-15 min"
        }
    }
}

struct ActionPlan: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let sourceType: ActionPlanSourceType
    let planSize: ActionPlanSize
    let localDate: String
    let timezone: String
    let status: ActionPlanStatus
    let scheduledFor: Date?
    let createdAt: Date
    let updatedAt: Date

    var isActive: Bool {
        status == .draft || status == .scheduled || status == .inProgress
    }
}

enum ActionPlanItemType: String, Codable {
    case quest
    case exercise
    case chat
}

struct ActionPlanItem: Identifiable, Codable, Equatable {
    let id: String
    let planId: String
    let itemType: ActionPlanItemType
    let referenceId: String?
    let title: String
    let durationMinutes: Int
    let sortOrder: Int
    let status: ActionPlanItemStatus
    let completedAt: Date?
    let skippedAt: Date?
}

struct ActionPlanFeedback: Codable, Equatable {
    let planId: String
    let rating: Int?
    let notes: String?
}
