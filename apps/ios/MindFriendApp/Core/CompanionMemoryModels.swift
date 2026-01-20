import Foundation
import SwiftUI

// MARK: - Memory Category

/// Categories for organizing companion memories
enum MemoryCategory: String, Codable, CaseIterable, Identifiable {
    case boundaries
    case preferences
    case triggers
    case avoidTopics = "avoid_topics"
    case positiveReinforcement = "positive_reinforcement"
    case lifeContext = "life_context"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .boundaries: return "Boundaries"
        case .preferences: return "Preferences"
        case .triggers: return "Triggers"
        case .avoidTopics: return "Topics to Avoid"
        case .positiveReinforcement: return "Positive Reinforcement"
        case .lifeContext: return "Life Context"
        }
    }

    var icon: String {
        switch self {
        case .boundaries: return "hand.raised.fill"
        case .preferences: return "heart.fill"
        case .triggers: return "exclamationmark.triangle.fill"
        case .avoidTopics: return "xmark.circle.fill"
        case .positiveReinforcement: return "star.fill"
        case .lifeContext: return "person.fill"
        }
    }

    var color: Color {
        switch self {
        case .boundaries: return .red
        case .preferences: return .blue
        case .triggers: return .orange
        case .avoidTopics: return .purple
        case .positiveReinforcement: return .green
        case .lifeContext: return .teal
        }
    }

    var description: String {
        switch self {
        case .boundaries:
            return "Things you don't want to discuss or boundaries to respect"
        case .preferences:
            return "How you prefer to be supported or communicated with"
        case .triggers:
            return "Topics or situations that are difficult for you"
        case .avoidTopics:
            return "Subjects to avoid in conversation"
        case .positiveReinforcement:
            return "Encouragement styles or approaches that work for you"
        case .lifeContext:
            return "Important life details, relationships, or situations"
        }
    }
}

// MARK: - Companion Memory

/// A user-managed memory item that the AI companion remembers
struct CompanionMemory: Codable, Identifiable, Equatable {
    let id: String
    let category: MemoryCategory
    var content: String
    let lastUsedAt: Date?
    let usageCount: Int
    let createdAt: Date
    let updatedAt: Date

    /// Whether this memory has never been used in a conversation
    var isUnused: Bool {
        lastUsedAt == nil
    }

    /// Usage frequency level based on usage count
    var usageLevel: UsageLevel {
        switch usageCount {
        case 0: return .never
        case 1...5: return .low
        case 6...15: return .medium
        default: return .high
        }
    }

    enum UsageLevel: String {
        case never, low, medium, high

        var displayName: String {
            switch self {
            case .never: return "Never used"
            case .low: return "Rarely used"
            case .medium: return "Sometimes used"
            case .high: return "Frequently used"
            }
        }

        var color: Color {
            switch self {
            case .never: return .gray
            case .low: return .blue
            case .medium: return .orange
            case .high: return .green
            }
        }
    }
}

// MARK: - Daily Intent

/// A short-term daily focus or intention that expires after 24 hours
struct DailyIntent: Codable, Identifiable, Equatable {
    let id: String
    var intent: String
    let createdAt: Date
    let expiresAt: Date

    /// Whether the intent has expired
    var isExpired: Bool {
        Date() >= expiresAt
    }

    /// Time remaining until expiration
    var timeRemaining: TimeInterval {
        max(0, expiresAt.timeIntervalSinceNow)
    }

    /// Formatted time remaining (e.g., "5h 30m")
    var formattedTimeRemaining: String {
        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "Expiring soon"
        }
    }
}

// MARK: - API Response Types

/// Response from get-companion-memory endpoint
struct GetMemoryResponse: Codable {
    let memories: [CompanionMemory]
    let dailyIntent: DailyIntent?
    let totalCount: Int
    let maxLimit: Int

    /// Whether the memory limit has been reached
    var isLimitReached: Bool {
        totalCount >= maxLimit
    }

    /// Number of remaining memory slots
    var remainingSlots: Int {
        max(0, maxLimit - totalCount)
    }
}

/// Response from update-companion-memory endpoint
struct UpdateMemoryResponse: Codable {
    let success: Bool
    let memory: CompanionMemory?
    let dailyIntent: DailyIntent?
    let error: String?
}

/// Response from delete-companion-memory endpoint
struct DeleteMemoryResponse: Codable {
    let success: Bool
    let error: String?
}

// MARK: - Request Types

/// Request body for creating/updating a memory
struct UpdateMemoryRequest: Codable {
    let action: String // "memory" or "intent"
    let id: String?
    let category: MemoryCategory?
    let content: String?
    let intent: String?

    /// Create a request for adding/editing a memory
    static func memory(id: String? = nil, category: MemoryCategory, content: String) -> UpdateMemoryRequest {
        UpdateMemoryRequest(action: "memory", id: id, category: category, content: content, intent: nil)
    }

    /// Create a request for setting a daily intent
    static func intent(_ text: String) -> UpdateMemoryRequest {
        UpdateMemoryRequest(action: "intent", id: nil, category: nil, content: nil, intent: text)
    }
}

/// Request body for deleting a memory or clearing intent
struct DeleteMemoryRequest: Codable {
    let action: String // "memory" or "intent"
    let id: String?

    /// Create a request for deleting a memory
    static func memory(id: String) -> DeleteMemoryRequest {
        DeleteMemoryRequest(action: "memory", id: id)
    }

    /// Create a request for clearing the daily intent
    static func intent() -> DeleteMemoryRequest {
        DeleteMemoryRequest(action: "intent", id: nil)
    }
}
