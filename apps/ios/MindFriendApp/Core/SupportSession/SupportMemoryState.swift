import Foundation

/// Inspectable account context cached only inside the protected owner journal.
public struct SupportMemoryRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var content: String
    public var category: String
    public var origin: String
    public var state: String
    public var revision: Int
    public var confirmedAt: Date?
    public var reviewDueAt: Date?
    public var expiresAt: Date?
    public var lastUsedAt: Date?
    public var sourceMessageID: UUID?
    public var sourceConversationID: UUID?
    public var isSuggestion: Bool
}

public enum SupportMemoryAction: String, Codable, Sendable {
    case edit, stopUsing, resumeUsing, forgetMemory, forgetCandidate, approveCandidate, dismissCandidate
}

/// An immutable semantic operation. Transport retries retain its ID and values across relaunch.
public struct SupportMemoryChange: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let targetID: UUID
    public let action: SupportMemoryAction
    public let content: String?
    public let category: String?
    public let expectedRevision: Int?
    public let createdAt: Date
    public var sent = false
    public var failureCode: String?
    public var conflictingContent: String?
    public var conflictingRevision: Int?
}
