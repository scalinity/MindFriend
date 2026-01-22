//
//  RehearsalModels.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-20.
//  Conversation Rehearsal Studio models
//

import Foundation

// MARK: - Conversation Scenario

struct ConversationScenario: Identifiable, Codable, Hashable {
    let id: UUID
    let category: ScenarioCategory
    let title: String
    let description: String
    let situationContext: String
    let otherPartyRole: String
    let otherPartyPersonality: String?
    let keyPointsToConvey: [String]
    let desiredOutcome: String
    let difficultyLevel: DifficultyLevel
    let estimatedMinutes: Int
    let tipsForUser: [String]?
    let tags: [String]?
    let isPremium: Bool
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case title
        case description
        case situationContext = "situation_context"
        case otherPartyRole = "other_party_role"
        case otherPartyPersonality = "other_party_personality"
        case keyPointsToConvey = "key_points_to_convey"
        case desiredOutcome = "desired_outcome"
        case difficultyLevel = "difficulty_level"
        case estimatedMinutes = "estimated_minutes"
        case tipsForUser = "tips_for_user"
        case tags
        case isPremium = "is_premium"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum ScenarioCategory: String, Codable, CaseIterable {
    case work
    case relationships
    case social
    case family
    case health
    case financial

    var displayName: String {
        switch self {
        case .work: return "Work"
        case .relationships: return "Relationships"
        case .social: return "Social"
        case .family: return "Family"
        case .health: return "Health"
        case .financial: return "Financial"
        }
    }

    var icon: String {
        switch self {
        case .work: return "briefcase.fill"
        case .relationships: return "heart.fill"
        case .social: return "person.2.fill"
        case .family: return "house.fill"
        case .health: return "cross.fill"
        case .financial: return "dollarsign.circle.fill"
        }
    }
}

enum DifficultyLevel: String, Codable {
    case easy
    case medium
    case advanced

    var displayName: String {
        switch self {
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .advanced: return "Advanced"
        }
    }

    var color: String {
        switch self {
        case .easy: return "green"
        case .medium: return "orange"
        case .advanced: return "red"
        }
    }
}

// MARK: - Custom Scenario

struct CustomScenario: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    let title: String
    let otherPartyRole: String
    let situationSummary: String
    let keyPoints: [String]
    let desiredOutcome: String
    let situationType: SituationType
    let contextDetails: [String: String]?
    let isPublic: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let archivedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case otherPartyRole = "other_party_role"
        case situationSummary = "situation_summary"
        case keyPoints = "key_points"
        case desiredOutcome = "desired_outcome"
        case situationType = "situation_type"
        case contextDetails = "context_details"
        case isPublic = "is_public"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case archivedAt = "archived_at"
    }
}

enum SituationType: String, Codable {
    case conflict
    case feedback
    case boundary
    case request
    case other

    var displayName: String {
        switch self {
        case .conflict: return "Conflict Resolution"
        case .feedback: return "Giving Feedback"
        case .boundary: return "Setting Boundaries"
        case .request: return "Making Requests"
        case .other: return "Other"
        }
    }
}

// MARK: - Rehearsal Session

struct RehearsalSession: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    let scenarioId: UUID?
    let customScenarioId: UUID?
    let status: RehearsalSessionStatus
    let startedAt: Date
    let completedAt: Date?
    let confidenceRating: Int?
    let notes: String?
    let transcript: String
    let feedbackSummary: String?
    let communicationStyle: CommunicationStyle?
    let keyPointsCovered: Int
    let totalExchanges: Int
    let totalDurationSeconds: Int?
    let isBookmarked: Bool
    let isSaved: Bool
    let autoSaveKey: String?
    let crisisDetected: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case scenarioId = "scenario_id"
        case customScenarioId = "custom_scenario_id"
        case status
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case confidenceRating = "confidence_rating"
        case notes
        case transcript
        case feedbackSummary = "feedback_summary"
        case communicationStyle = "communication_style"
        case keyPointsCovered = "key_points_covered"
        case totalExchanges = "total_exchanges"
        case totalDurationSeconds = "total_duration_seconds"
        case isBookmarked = "is_bookmarked"
        case isSaved = "is_saved"
        case autoSaveKey = "auto_save_key"
        case crisisDetected = "crisis_detected"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var parsedTranscript: [TranscriptMessage]? {
        guard !transcript.isEmpty,
              let data = transcript.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode([TranscriptMessage].self, from: data)
    }
}

enum RehearsalSessionStatus: String, Codable {
    case active
    case completed
    case abandoned
    case crisisEnded = "crisis_ended"

    var displayName: String {
        switch self {
        case .active: return "In Progress"
        case .completed: return "Completed"
        case .abandoned: return "Abandoned"
        case .crisisEnded: return "Ended (Safety)"
        }
    }
}

// Note: Use RehearsalSessionStatus for rehearsal sessions, CouplesSessionStatus for couples exercises

enum CommunicationStyle: String, Codable {
    case defensive
    case aggressive
    case passive
    case assertive
    case empathetic
    case collaborative

    var displayName: String {
        switch self {
        case .defensive: return "Defensive"
        case .aggressive: return "Aggressive"
        case .passive: return "Passive"
        case .assertive: return "Assertive"
        case .empathetic: return "Empathetic"
        case .collaborative: return "Collaborative"
        }
    }

    var color: String {
        switch self {
        case .assertive, .collaborative, .empathetic: return "green"
        case .passive: return "blue"
        case .defensive: return "orange"
        case .aggressive: return "red"
        }
    }

    var icon: String {
        switch self {
        case .assertive: return "hand.raised.fill"
        case .collaborative: return "person.2.fill"
        case .empathetic: return "heart.fill"
        case .passive: return "hand.point.down.fill"
        case .defensive: return "shield.fill"
        case .aggressive: return "exclamationmark.triangle.fill"
        }
    }
}

struct TranscriptMessage: Codable, Hashable, Identifiable {
    let id = UUID()
    let role: String
    let content: String
    let timestamp: Date

    var isUser: Bool {
        role == "user"
    }

    enum CodingKeys: String, CodingKey {
        case role, content, timestamp
    }
}

// MARK: - Rehearsal Feedback

struct RehearsalFeedback: Identifiable, Codable, Hashable {
    let id: UUID
    let sessionId: UUID
    let messageId: UUID?
    let feedbackType: FeedbackType
    let overallScore: Double?
    let tone: CommunicationStyle?
    let clarityScore: Double?
    let empathyScore: Double?
    let assertivenessScore: Double?
    let strengths: [String]?
    let improvements: [String]?
    let suggestedRephrase: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case messageId = "message_id"
        case feedbackType = "feedback_type"
        case overallScore = "overall_score"
        case tone
        case clarityScore = "clarity_score"
        case empathyScore = "empathy_score"
        case assertivenessScore = "assertiveness_score"
        case strengths
        case improvements
        case suggestedRephrase = "suggested_rephrase"
        case createdAt = "created_at"
    }
}

enum FeedbackType: String, Codable {
    case perMessage = "per_message"
    case sessionSummary = "session_summary"
}

// MARK: - Rehearsal Bookmark

struct RehearsalBookmark: Identifiable, Codable, Hashable {
    let id: UUID
    let userId: UUID
    let sessionId: UUID
    let originalMessage: String
    let rewrittenMessage: String?
    let toneType: ToneType?
    let scenarioContext: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case sessionId = "session_id"
        case originalMessage = "original_message"
        case rewrittenMessage = "rewritten_message"
        case toneType = "tone_type"
        case scenarioContext = "scenario_context"
        case createdAt = "created_at"
    }
}

enum ToneType: String, Codable {
    case moreDirect = "more_direct"
    case moreGentle = "more_gentle"
    case moreAssertive = "more_assertive"
    case moreCollaborative = "more_collaborative"

    var displayName: String {
        switch self {
        case .moreDirect: return "More Direct"
        case .moreGentle: return "More Gentle"
        case .moreAssertive: return "More Assertive"
        case .moreCollaborative: return "More Collaborative"
        }
    }
}

// MARK: - API Request/Response Models

struct CreateScenarioRequest: Codable {
    let title: String
    let description: String
    let personRole: String
    let situationType: String
    let keyPoints: [String]
    let desiredOutcome: String
    
    var action: String { "create-scenario" }
    
    enum CodingKeys: String, CodingKey {
        case title, description, personRole, situationType, keyPoints, desiredOutcome
    }
}

struct StartSessionRequest: Codable {
    let scenarioId: UUID?
    let customScenarioId: UUID?
    
    var action: String { "start-session" }
    
    enum CodingKeys: String, CodingKey {
        case scenarioId, customScenarioId
    }
}

struct SendMessageRequest: Codable {
    let sessionId: UUID
    let message: String
    
    var action: String { "send-message" }
    
    enum CodingKeys: String, CodingKey {
        case sessionId, message
    }
}

struct EndSessionRequest: Codable {
    let sessionId: UUID
    let confidenceRating: Int?
    let notes: String?
    
    var action: String { "end-session" }
    
    enum CodingKeys: String, CodingKey {
        case sessionId, confidenceRating, notes
    }
}

struct GetScenariosRequest: Codable {
    let category: String?
    let includeCustom: Bool
    
    var action: String { "get-scenarios" }
    
    enum CodingKeys: String, CodingKey {
        case category, includeCustom
    }
}

struct GetSessionHistoryRequest: Codable {
    let limit: Int
    
    var action: String { "get-session-history" }
    
    enum CodingKeys: String, CodingKey {
        case limit
    }
}

struct StartSessionResponse: Codable {
    let session: SessionInfo
    let openingMessage: String
    let systemContext: String

    struct SessionInfo: Codable {
        let id: UUID
        let scenarioTitle: String
        let keyPoints: [String]
        let goal: String
    }
}

struct RehearsalSendMessageResponse: Codable {
    let aiResponse: String
    let feedback: MessageFeedback?
    let exchangeCount: Int
    let crisis: Bool?
    let message: String?
    let resources: [RehearsalCrisisResource]?
    let sessionEnded: Bool?
    let error: String?
    let upgradePrompt: Bool?

    struct MessageFeedback: Codable {
        let style: String
        let suggestions: [String]
        let encouragement: String
    }
}

struct RehearsalCrisisResource: Codable {
    let name: String
    let phone: String?
    let sms: String?
    let available: String
}

struct EndSessionResponse: Codable {
    let summary: SessionSummary
    let success: Bool

    struct SessionSummary: Codable {
        let duration: Int
        let exchangesCount: Int
        let avgScores: AvgScores
        let strengths: [String]
        let growthAreas: [String]

        struct AvgScores: Codable {
            let clarity: String
            let empathy: String
            let assertiveness: String
        }
    }
}

struct GetScenariosResponse: Codable {
    let prebuilt: [ConversationScenario]
    let custom: [CustomScenario]
}

struct GetSessionHistoryResponse: Codable {
    let sessions: [RehearsalSession]
}
