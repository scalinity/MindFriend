import Foundation
import SwiftUI

// MARK: - Celebration Types

/// Types of milestone celebrations the app can trigger
enum CelebrationType: String, Codable, CaseIterable {
    case streakMilestone = "streak_milestone"
    case levelUp = "level_up"
    case badgeUnlock = "badge_unlock"
    case questMilestone = "quest_milestone"
    case exerciseMilestone = "exercise_milestone"

    /// Colors used for confetti animation based on celebration type
    var confettiColors: [Color] {
        switch self {
        case .streakMilestone: return [.orange, .red, .yellow]
        case .levelUp: return [.purple, .blue, .pink]
        case .badgeUnlock: return [.green, .yellow, .blue]
        case .questMilestone: return [.blue, .cyan, .white]
        case .exerciseMilestone: return [.green, .mint, .cyan]
        }
    }

    /// SF Symbol name for this celebration type
    var iconName: String {
        switch self {
        case .streakMilestone: return "flame.fill"
        case .levelUp: return "star.fill"
        case .badgeUnlock: return "trophy.fill"
        case .questMilestone: return "checkmark.seal.fill"
        case .exerciseMilestone: return "figure.mind.and.body"
        }
    }

    /// Display name for the celebration type
    var displayName: String {
        switch self {
        case .streakMilestone: return "Streak Milestone"
        case .levelUp: return "Level Up"
        case .badgeUnlock: return "Badge Unlocked"
        case .questMilestone: return "Quest Milestone"
        case .exerciseMilestone: return "Exercise Milestone"
        }
    }
}

// MARK: - Celebration Event

/// Represents a celebration event that should be shown to the user
struct CelebrationEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let celebrationType: CelebrationType
    let value: Int
    let badgeId: UUID?
    let shownAt: Date?
    var sharedToCircle: Bool
    var sharedExternally: Bool
    var circlePostId: UUID?
    let createdAt: Date

    // Joined data (optional, populated when fetching with relations)
    var badgeTitle: String?
    var badgeDescription: String?
    var badgeIconName: String?

    /// Number of reactions (populated when fetching reaction summary)
    var reactionCount: Int {
        reactions?.count ?? 0
    }

    /// Reactions from circle members (optional, populated separately)
    var reactions: [CelebrationReaction]?

    /// Title text for the celebration modal
    var title: String {
        switch celebrationType {
        case .streakMilestone:
            return "\(value)-Day Streak!"
        case .levelUp:
            return "Level \(value)!"
        case .badgeUnlock:
            return badgeTitle ?? "New Badge!"
        case .questMilestone:
            return "\(value) Quests!"
        case .exerciseMilestone:
            return "\(value) Exercises!"
        }
    }

    /// Subtitle text for the celebration modal
    var subtitle: String {
        switch celebrationType {
        case .streakMilestone:
            return "You've been consistent for \(value) days. Amazing!"
        case .levelUp:
            return "You've reached a new level in your journey!"
        case .badgeUnlock:
            return badgeDescription ?? "You unlocked a new achievement!"
        case .questMilestone:
            return "You've completed \(value) quests. Keep going!"
        case .exerciseMilestone:
            return "\(value) exercises completed. Your dedication shows!"
        }
    }

    /// Message for sharing externally
    var shareMessage: String {
        switch celebrationType {
        case .streakMilestone:
            return "I just hit a \(value)-day streak on MindFriend! 🔥"
        case .levelUp:
            return "Just reached Level \(value) on my wellness journey! ⭐"
        case .badgeUnlock:
            return "Unlocked the '\(badgeTitle ?? "new")' badge on MindFriend! 🏆"
        case .questMilestone:
            return "Completed \(value) wellness quests! 💪"
        case .exerciseMilestone:
            return "Finished \(value) exercises on MindFriend! 🧘"
        }
    }

    /// Icon name for display (uses badge icon if available)
    var displayIconName: String {
        if celebrationType == .badgeUnlock, let icon = badgeIconName {
            return icon
        }
        return celebrationType.iconName
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case celebrationType = "celebration_type"
        case value
        case badgeId = "badge_id"
        case shownAt = "shown_at"
        case sharedToCircle = "shared_to_circle"
        case sharedExternally = "shared_externally"
        case circlePostId = "circle_post_id"
        case createdAt = "created_at"
        case badgeTitle = "badge_title"
        case badgeDescription = "badge_description"
        case badgeIconName = "badge_icon_name"
        case reactions
    }
}

// MARK: - Celebration Reaction

/// Represents a reaction from a circle member on a shared celebration
struct CelebrationReaction: Identifiable, Codable, Equatable {
    let id: UUID
    let celebrationEventId: UUID
    let reactorUserId: UUID
    let emoji: String
    let createdAt: Date

    /// Reactor's display name (populated when fetching with profile join)
    var reactorName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case celebrationEventId = "celebration_event_id"
        case reactorUserId = "reactor_user_id"
        case emoji
        case createdAt = "created_at"
        case reactorName = "reactor_name"
    }
}

// MARK: - Reaction Summary

/// Summary of reactions for a celebration (emoji counts)
struct CelebrationReactionSummary: Codable, Equatable {
    let emoji: String
    let count: Int
    let userReacted: Bool

    enum CodingKeys: String, CodingKey {
        case emoji
        case count
        case userReacted = "user_reacted"
    }
}

// MARK: - Share Card Template

/// Template for generating shareable celebration cards
struct ShareCardTemplate: Codable, Identifiable {
    let id: UUID
    let templateType: String
    let backgroundColor: String
    let accentColor: String
    let iconName: String
    let messageTemplate: String

    /// Parses hex color string to SwiftUI Color
    var backgroundSwiftUIColor: Color {
        Color(hex: backgroundColor)
    }

    var accentSwiftUIColor: Color {
        Color(hex: accentColor)
    }

    /// Generates the message with value substitution
    func generateMessage(value: Int, badgeName: String? = nil) -> String {
        var message = messageTemplate
            .replacingOccurrences(of: "{value}", with: "\(value)")
        if let name = badgeName {
            message = message.replacingOccurrences(of: "{badge_name}", with: name)
        }
        return message
    }

    enum CodingKeys: String, CodingKey {
        case id
        case templateType = "template_type"
        case backgroundColor = "background_color"
        case accentColor = "accent_color"
        case iconName = "icon_name"
        case messageTemplate = "message_template"
    }
}

// MARK: - Pending Celebration (RPC Result)

/// Result from get_pending_celebrations RPC call
struct PendingCelebration: Codable, Identifiable {
    let id: UUID
    let celebrationType: String
    let value: Int
    let badgeId: UUID?
    let badgeTitle: String?
    let badgeDescription: String?
    let badgeIconName: String?
    let createdAt: Date

    /// Converts to a full CelebrationEvent
    func toCelebrationEvent(userId: UUID) -> CelebrationEvent {
        CelebrationEvent(
            id: id,
            userId: userId,
            celebrationType: CelebrationType(rawValue: celebrationType) ?? .questMilestone,
            value: value,
            badgeId: badgeId,
            shownAt: nil,
            sharedToCircle: false,
            sharedExternally: false,
            circlePostId: nil,
            createdAt: createdAt,
            badgeTitle: badgeTitle,
            badgeDescription: badgeDescription,
            badgeIconName: badgeIconName
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case celebrationType = "celebration_type"
        case value
        case badgeId = "badge_id"
        case badgeTitle = "badge_title"
        case badgeDescription = "badge_description"
        case badgeIconName = "badge_icon_name"
        case createdAt = "created_at"
    }
}

// MARK: - Milestone Trigger Result

/// Result from check_milestone_triggers RPC call
struct MilestoneTriggerResult: Codable {
    let celebrationId: UUID
    let celebrationType: String
    let value: Int
    let badgeId: UUID?

    enum CodingKeys: String, CodingKey {
        case celebrationId = "celebration_id"
        case celebrationType = "celebration_type"
        case value
        case badgeId = "badge_id"
    }

    /// Converts to a CelebrationEvent for display
    func toCelebrationEvent(userId: UUID) -> CelebrationEvent {
        CelebrationEvent(
            id: celebrationId,
            userId: userId,
            celebrationType: CelebrationType(rawValue: celebrationType) ?? .questMilestone,
            value: value,
            badgeId: badgeId,
            shownAt: nil,
            sharedToCircle: false,
            sharedExternally: false,
            circlePostId: nil,
            createdAt: Date()
        )
    }
}

// MARK: - Available Celebration Reactions

/// Standard emojis available for celebrating with friends
enum CelebrationEmoji: String, CaseIterable {
    case party = "🎉"
    case clap = "👏"
    case fire = "🔥"
    case muscle = "💪"
    case heart = "❤️"
    case star = "⭐"

    var displayName: String {
        switch self {
        case .party: return "Party"
        case .clap: return "Clap"
        case .fire: return "Fire"
        case .muscle: return "Strong"
        case .heart: return "Love"
        case .star: return "Star"
        }
    }
}

// MARK: - Color Extension for Hex Parsing

extension Color {
    /// Initialize Color from hex string (e.g., "#FF6B35" or "FF6B35")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
