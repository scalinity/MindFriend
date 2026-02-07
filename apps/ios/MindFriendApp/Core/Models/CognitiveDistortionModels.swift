//
//  CognitiveDistortionModels.swift
//  MindFriendApp
//
//  Created by dev-pipeline
//  Cognitive Distortion Detector models
//

import Foundation

// MARK: - Distortion Type Enum

enum DistortionType: String, Codable, CaseIterable {
    case allOrNothing = "all_or_nothing"
    case overgeneralization = "overgeneralization"
    case mentalFilter = "mental_filter"
    case disqualifyingPositive = "disqualifying_positive"
    case jumpingToConclusions = "jumping_to_conclusions"
    case magnificationMinimization = "magnification_minimization"
    case emotionalReasoning = "emotional_reasoning"
    case shouldStatements = "should_statements"
    case labeling = "labeling"
    case personalization = "personalization"

    var displayName: String {
        switch self {
        case .allOrNothing:
            return "All-or-Nothing Thinking"
        case .overgeneralization:
            return "Overgeneralization"
        case .mentalFilter:
            return "Mental Filter"
        case .disqualifyingPositive:
            return "Disqualifying the Positive"
        case .jumpingToConclusions:
            return "Jumping to Conclusions"
        case .magnificationMinimization:
            return "Magnification/Minimization"
        case .emotionalReasoning:
            return "Emotional Reasoning"
        case .shouldStatements:
            return "Should Statements"
        case .labeling:
            return "Labeling"
        case .personalization:
            return "Personalization"
        }
    }

    var explanation: String {
        switch self {
        case .allOrNothing:
            return "Seeing things in black and white, with no middle ground. One mistake means total failure."
        case .overgeneralization:
            return "Taking one event and believing it will always happen. 'This always happens to me.'"
        case .mentalFilter:
            return "Focusing only on negatives while ignoring positives."
        case .disqualifyingPositive:
            return "Dismissing good things that happen. 'That doesn't count.'"
        case .jumpingToConclusions:
            return "Assuming you know what others think or predicting the future negatively."
        case .magnificationMinimization:
            return "Exaggerating negatives or minimizing positives out of proportion."
        case .emotionalReasoning:
            return "Believing that feelings equal facts. 'I feel stupid, so I must be stupid.'"
        case .shouldStatements:
            return "Rigid rules for yourself or others using 'should,' 'must,' or 'have to.'"
        case .labeling:
            return "Attaching fixed negative labels to yourself or others based on one event."
        case .personalization:
            return "Blaming yourself for things outside your control."
        }
    }

    var reframingPrompt: String {
        switch self {
        case .allOrNothing:
            return "Is there a middle ground here? Can something be partially successful?"
        case .overgeneralization:
            return "Can you think of a time when this didn't happen?"
        case .mentalFilter:
            return "What positives might you be overlooking right now?"
        case .disqualifyingPositive:
            return "Why might this positive thing actually count?"
        case .jumpingToConclusions:
            return "What evidence do you have for this assumption?"
        case .magnificationMinimization:
            return "What would a balanced perspective look like?"
        case .emotionalReasoning:
            return "What facts support or contradict this feeling?"
        case .shouldStatements:
            return "What if you replaced 'should' with 'I'd like to'?"
        case .labeling:
            return "Can you describe the behavior without labeling yourself?"
        case .personalization:
            return "What other factors might have contributed to this?"
        }
    }
}

// MARK: - Detection Method Enum

enum DetectionMethod: String, Codable {
    case llm = "llm"
    case pattern = "pattern"
}

// MARK: - Distortion Event Model

struct DistortionEvent: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let sessionId: String
    let distortionType: DistortionType
    let transcriptText: String  // Decrypted in-memory representation
    let confidence: Double?
    let detectionMethod: DetectionMethod
    var userAcknowledged: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case sessionId = "session_id"
        case distortionType = "distortion_type"
        case transcriptTextEncrypted = "transcript_text_encrypted"  // SECURITY: Database stores encrypted
        case confidence
        case detectionMethod = "detection_method"
        case userAcknowledged = "user_acknowledged"
        case createdAt = "created_at"
    }

    // Custom decoding to handle encrypted transcript
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        distortionType = try container.decode(DistortionType.self, forKey: .distortionType)

        // SECURITY NOTE: Decryption happens server-side via Edge Function
        // The encrypted field is never exposed to the client directly
        // For now, we expect the server to return decrypted text in a different field
        // or handle decryption before sending to client
        if let _ = try? container.decode(Data.self, forKey: .transcriptTextEncrypted) {
            // Edge Function should decrypt before sending to client
            // This is a safeguard - in practice, the server sends decrypted text
            transcriptText = "[Encrypted - decrypt server-side]"
        } else {
            transcriptText = ""
        }

        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        detectionMethod = try container.decode(DetectionMethod.self, forKey: .detectionMethod)
        userAcknowledged = try container.decode(Bool.self, forKey: .userAcknowledged)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    // Custom encoding to handle encrypted transcript
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(distortionType, forKey: .distortionType)

        // SECURITY: Send plaintext to server, encryption happens server-side
        // The Edge Function will encrypt before storing in database
        // Client never handles encryption keys
        try container.encode(transcriptText.data(using: .utf8), forKey: .transcriptTextEncrypted)

        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encode(detectionMethod, forKey: .detectionMethod)
        try container.encode(userAcknowledged, forKey: .userAcknowledged)
        try container.encode(createdAt, forKey: .createdAt)
    }

    init(
        id: UUID = UUID(),
        userId: UUID,
        sessionId: String,
        distortionType: DistortionType,
        transcriptText: String,
        confidence: Double? = nil,
        detectionMethod: DetectionMethod,
        userAcknowledged: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.sessionId = sessionId
        self.distortionType = distortionType
        self.transcriptText = transcriptText
        self.confidence = confidence
        self.detectionMethod = detectionMethod
        self.userAcknowledged = userAcknowledged
        self.createdAt = createdAt
    }
}

// MARK: - Distortion Prompt Model

struct DistortionPrompt: Identifiable {
    let id: UUID
    let distortionEvent: DistortionEvent
    let shownAt: Date
    var dismissed: Bool
    var acknowledged: Bool
    var dismissedAt: Date?

    init(
        id: UUID = UUID(),
        distortionEvent: DistortionEvent,
        shownAt: Date = Date(),
        dismissed: Bool = false,
        acknowledged: Bool = false,
        dismissedAt: Date? = nil
    ) {
        self.id = id
        self.distortionEvent = distortionEvent
        self.shownAt = shownAt
        self.dismissed = dismissed
        self.acknowledged = acknowledged
        self.dismissedAt = dismissedAt
    }

    var displayTitle: String {
        distortionEvent.distortionType.displayName
    }

    var displayMessage: String {
        distortionEvent.distortionType.reframingPrompt
    }

    var triggerPhrase: String {
        // Extract first 100 chars or first sentence from transcript
        let text = distortionEvent.transcriptText
        let maxLength = min(100, text.count)
        let truncated = String(text.prefix(maxLength))

        // Try to end at sentence boundary
        if let lastPeriod = truncated.lastIndex(of: ".") {
            return String(truncated[..<lastPeriod]) + "."
        }

        return truncated + (text.count > maxLength ? "..." : "")
    }
}

// MARK: - Distortion Prompt Record (for DB storage)

struct DistortionPromptRecord: Codable {
    let id: UUID
    let userId: UUID
    let sessionId: String
    let distortionEventId: UUID
    let shownAt: Date
    var dismissed: Bool
    var acknowledged: Bool
    var dismissedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case sessionId = "session_id"
        case distortionEventId = "distortion_event_id"
        case shownAt = "shown_at"
        case dismissed
        case acknowledged
        case dismissedAt = "dismissed_at"
    }

    init(
        id: UUID = UUID(),
        userId: UUID,
        sessionId: String,
        distortionEventId: UUID,
        shownAt: Date = Date(),
        dismissed: Bool = false,
        acknowledged: Bool = false,
        dismissedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.sessionId = sessionId
        self.distortionEventId = distortionEventId
        self.shownAt = shownAt
        self.dismissed = dismissed
        self.acknowledged = acknowledged
        self.dismissedAt = dismissedAt
    }
}
