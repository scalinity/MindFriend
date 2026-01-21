import Foundation

// MARK: - Action Card Models

struct ActionCard: Identifiable, Codable, Equatable {
    let id: String
    let sessionId: String
    let messageId: String
    let cardType: CardType
    let cardData: CardData
    let isDismissed: Bool
    let isCompleted: Bool
    let displayedAt: Date
    let actionTakenAt: Date?
    let expiresAt: Date?

    enum CardType: String, Codable, CaseIterable {
        case exercise
        case journaling
        case quest
        case mood
        case resource
        case chat
    }

    struct CardData: Codable, Equatable {
        let title: String
        let description: String
        let icon: String
        let estimatedMinutes: Int
        let actionDestination: ActionDestination
        let isPremium: Bool
        let priority: Int
        let conditions: [String: String]?
    }

    struct ActionDestination: Codable, Equatable {
        let type: String
        let id: String?
        let params: [String: String]?
    }
}

struct ActionCardTemplate: Identifiable, Codable {
    let id: String
    let triggerType: String
    let cardTitle: String
    let cardDescription: String?
    let actionDestination: String
    let actionDestinationId: String?
    let icon: String?
    let estimatedMinutes: Int
    let priority: Int
    let isPremium: Bool
    let conditions: [String: String]?
    let active: Bool
}

// MARK: - API Request/Response Models

struct GenerateActionCardsRequest: Codable {
    let conversationId: String
    let messageId: String
    let messageContent: String
    let messageIntent: String?
    let userContext: UserContext
}

struct UserContext: Codable {
    let completedExerciseIds: [String]
    let currentStreak: Int
    let lastMoodLog: String?
    let activeQuestId: String?
    let isPremium: Bool
}

struct GenerateActionCardsResponse: Codable {
    let cards: [ActionCardDTO]
    let generatedAt: String
}

struct ActionCardDTO: Codable {
    let id: String
    let cardType: ActionCard.CardType
    let title: String
    let description: String
    let icon: String
    let estimatedMinutes: Int
    let actionDestination: ActionDestinationDTO
    let metadata: CardMetadataDTO
}

struct ActionDestinationDTO: Codable {
    let type: String
    let id: String?
    let params: [String: String]?
}

struct CardMetadataDTO: Codable {
    let isPremium: Bool
    let priority: Int
    let conditions: [String: String]?
}

struct CardActionRequest: Codable {
    let cardId: String
    let actionType: String
    let additionalData: [String: String]?
}

struct DismissCardRequest: Codable {
    let cardId: String
    let reason: String?
    let snoozeMinutes: Int?
    let suppressSimilar: Bool
}

// MARK: - Analytics Events

enum CardAnalyticsEvent {
    case impression(cardId: String)
    case click(cardId: String)
    case dismiss(cardId: String, reason: String?)
    case complete(cardId: String)
    case conversion(cardId: String)
}
