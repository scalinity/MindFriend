import Foundation

// MARK: - Mentorship Profile

/// User's mentorship profile (mentor availability, expertise, etc.)
public struct MentorshipProfile: Codable, Identifiable, Equatable {
    public let id: UUID
    public let userId: UUID
    public var isMentorAvailable: Bool
    public var expertiseAreas: [String]
    public var seekingAreas: [String]
    public var bio: String?
    public var availabilityHoursWeek: Int
    public var languages: [String]
    public var timezone: String
    public var isVerified: Bool
    public var mentorAlias: String?
    public let createdAt: Date
    public var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case isMentorAvailable = "is_mentor_available"
        case expertiseAreas = "expertise_areas"
        case seekingAreas = "seeking_areas"
        case bio
        case availabilityHoursWeek = "availability_hours_week"
        case languages
        case timezone
        case isVerified = "is_verified"
        case mentorAlias = "mentor_alias"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: UUID = UUID(),
        userId: UUID,
        isMentorAvailable: Bool = false,
        expertiseAreas: [String] = [],
        seekingAreas: [String] = [],
        bio: String? = nil,
        availabilityHoursWeek: Int = 0,
        languages: [String] = ["en"],
        timezone: String = "UTC",
        isVerified: Bool = false,
        mentorAlias: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.isMentorAvailable = isMentorAvailable
        self.expertiseAreas = expertiseAreas
        self.seekingAreas = seekingAreas
        self.bio = bio
        self.availabilityHoursWeek = availabilityHoursWeek
        self.languages = languages
        self.timezone = timezone
        self.isVerified = isVerified
        self.mentorAlias = mentorAlias
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Mentorship Match

/// A mentorship relationship between mentor and mentee
public struct MentorshipMatch: Codable, Identifiable, Equatable {
    public let id: UUID
    public let mentorId: UUID
    public let menteeId: UUID
    public var status: MentorshipStatus
    public var introductionMessage: String?
    public var compatibilityScore: Double?
    public var matchReason: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var expiresAt: Date?
    public var endedAt: Date?
    public var endReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case mentorId = "mentor_id"
        case menteeId = "mentee_id"
        case status
        case introductionMessage = "introduction_message"
        case compatibilityScore = "compatibility_score"
        case matchReason = "match_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case expiresAt = "expires_at"
        case endedAt = "ended_at"
        case endReason = "end_reason"
    }

    public init(
        id: UUID = UUID(),
        mentorId: UUID,
        menteeId: UUID,
        status: MentorshipStatus = .pending,
        introductionMessage: String? = nil,
        compatibilityScore: Double? = nil,
        matchReason: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        expiresAt: Date? = nil,
        endedAt: Date? = nil,
        endReason: String? = nil
    ) {
        self.id = id
        self.mentorId = mentorId
        self.menteeId = menteeId
        self.status = status
        self.introductionMessage = introductionMessage
        self.compatibilityScore = compatibilityScore
        self.matchReason = matchReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
        self.endedAt = endedAt
        self.endReason = endReason
    }

    public var isActive: Bool {
        status == .active
    }

    public var isPending: Bool {
        status == .pending
    }

    public var isEnded: Bool {
        status == .ended
    }
}

// MARK: - Mentorship Role

/// Enum for mentorship participant role
public enum MentorshipRole: String, Codable, Equatable {
    case mentor = "mentor"
    case mentee = "mentee"
    case both = "both"
}

// MARK: - Mentorship Status

/// Enum for mentorship match status
public enum MentorshipStatus: String, Codable, Equatable {
    case pending = "pending"
    case active = "active"
    case completed = "completed"
    case cancelled = "cancelled"
    case ended = "ended"
    case expired = "expired"
}

// MARK: - Mentorship Message

/// A message within a mentorship match
public struct MentorshipMessage: Codable, Identifiable, Equatable {
    public let id: UUID
    public let matchId: UUID
    public let senderId: UUID
    public let content: String
    public var isRead: Bool?
    public let createdAt: Date
    public var readAt: Date?
    public var isFlagged: Bool?
    public var flaggedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case matchId = "match_id"
        case senderId = "sender_id"
        case content
        case isRead = "is_read"
        case createdAt = "created_at"
        case readAt = "read_at"
        case isFlagged = "is_flagged"
        case flaggedAt = "flagged_at"
    }

    public init(
        id: UUID = UUID(),
        matchId: UUID,
        senderId: UUID,
        content: String,
        isRead: Bool? = false,
        createdAt: Date = Date(),
        readAt: Date? = nil,
        isFlagged: Bool? = false,
        flaggedAt: Date? = nil
    ) {
        self.id = id
        self.matchId = matchId
        self.senderId = senderId
        self.content = content
        self.isRead = isRead
        self.createdAt = createdAt
        self.readAt = readAt
        self.isFlagged = isFlagged
        self.flaggedAt = flaggedAt
    }

    public var isSafetyFlagged: Bool {
        isFlagged == true
    }
}

// MARK: - Mentorship Report

/// Report of safety concern in mentorship
public struct MentorshipReport: Codable, Identifiable, Equatable {
    public let id: UUID
    public let matchId: UUID
    public let reporterId: UUID
    public let reportedUserId: UUID
    public let reason: String
    public var status: ReportStatus
    public let description: String?
    public let messageIds: [UUID]?
    public let createdAt: Date
    public var reviewedAt: Date?
    public var reviewedBy: UUID?
    public var resolution: String?

    enum CodingKeys: String, CodingKey {
        case id
        case matchId = "match_id"
        case reporterId = "reporter_id"
        case reportedUserId = "reported_user_id"
        case reason
        case status
        case description
        case messageIds = "message_ids"
        case createdAt = "created_at"
        case reviewedAt = "reviewed_at"
        case reviewedBy = "reviewed_by"
        case resolution
    }

    public init(
        id: UUID = UUID(),
        matchId: UUID,
        reporterId: UUID,
        reportedUserId: UUID,
        reason: String,
        status: ReportStatus = .pending,
        description: String? = nil,
        messageIds: [UUID]? = nil,
        createdAt: Date = Date(),
        reviewedAt: Date? = nil,
        reviewedBy: UUID? = nil,
        resolution: String? = nil
    ) {
        self.id = id
        self.matchId = matchId
        self.reporterId = reporterId
        self.reportedUserId = reportedUserId
        self.reason = reason
        self.status = status
        self.description = description
        self.messageIds = messageIds
        self.createdAt = createdAt
        self.reviewedAt = reviewedAt
        self.reviewedBy = reviewedBy
        self.resolution = resolution
    }

    public var isPending: Bool {
        status == .pending
    }

    public var isResolved: Bool {
        status == .resolved
    }
}

/// Status of a report
public enum ReportStatus: String, Codable {
    case pending       // Awaiting moderator review
    case resolved      // Reviewed and action taken
    case dismissed     // No violation found
    case escalated     // Referred to crisis team
}

// MARK: - Mentorship Escalation

/// Critical safety escalation (crisis keywords, severe violations)
public struct MentorshipEscalation: Codable, Identifiable, Equatable {
    public let id: UUID
    public let messageId: UUID
    public let matchId: UUID
    public let senderId: UUID
    public let severity: EscalationSeverity
    public let reasons: [String]
    public var status: EscalationStatus
    public let createdAt: Date
    public var reviewedAt: Date?
    public var action: String?

    enum CodingKeys: String, CodingKey {
        case id
        case messageId = "message_id"
        case matchId = "match_id"
        case senderId = "sender_id"
        case severity
        case reasons
        case status
        case createdAt = "created_at"
        case reviewedAt = "reviewed_at"
        case action
    }

    public init(
        id: UUID = UUID(),
        messageId: UUID,
        matchId: UUID,
        senderId: UUID,
        severity: EscalationSeverity,
        reasons: [String],
        status: EscalationStatus = .pending,
        createdAt: Date = Date(),
        reviewedAt: Date? = nil,
        action: String? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.matchId = matchId
        self.senderId = senderId
        self.severity = severity
        self.reasons = reasons
        self.status = status
        self.createdAt = createdAt
        self.reviewedAt = reviewedAt
        self.action = action
    }

    public var isCritical: Bool {
        severity == .critical
    }
}

/// Severity level of an escalation
public enum EscalationSeverity: String, Codable {
    case low           // Minor boundary violation
    case medium        // Moderate concern (e.g., PII exposure)
    case high          // Significant violation (e.g., inappropriate request)
    case critical      // Crisis keywords (e.g., suicide-related)
}

/// Status of an escalation
public enum EscalationStatus: String, Codable {
    case pending       // Awaiting crisis team review
    case reviewed      // Reviewed by team
    case escalated     // Referred to emergency services
    case resolved      // Action taken and resolved
    case closed        // Monitoring completed
}

// MARK: - Request/Response DTOs

/// Request to find mentor matches
public struct FindMentorMatchesRequest: Codable {
    let limit: Int?
    let offset: Int?

    public init(limit: Int? = 5, offset: Int? = 0) {
        self.limit = limit
        self.offset = offset
    }
}

/// Response from find-mentor-matches function
public struct FindMentorMatchesResponse: Codable {
    let success: Bool
    let matches: [MentorMatch]
    let count: Int
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case success
        case matches
        case count
        case timestamp
    }

    public struct MentorMatch: Codable, Identifiable {
        public let id: UUID
        public let mentorId: UUID
        public let mentorName: String
        public let mentorAlias: String
        public let expertiseAreas: [String]
        public let availabilityHoursWeek: Int
        public let languages: [String]
        public let timezone: String
        public let compatibilityScore: Double
        public let matchReasons: [String]
        public let isVerified: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case mentorId = "mentor_id"
            case mentorName = "mentor_name"
            case mentorAlias = "mentor_alias"
            case expertiseAreas = "expertise_areas"
            case availabilityHoursWeek = "availability_hours_week"
            case languages
            case timezone
            case compatibilityScore = "compatibility_score"
            case matchReasons = "match_reasons"
            case isVerified = "is_verified"
        }
    }
}

/// Request to send mentorship request
public struct RequestMentorshipBody: Codable {
    let mentorId: UUID
    let introductionMessage: String

    enum CodingKeys: String, CodingKey {
        case mentorId = "mentor_id"
        case introductionMessage = "introduction_message"
    }

    public init(mentorId: UUID, introductionMessage: String) {
        self.mentorId = mentorId
        self.introductionMessage = introductionMessage
    }
}

/// Response from request-mentorship function
public struct RequestMentorshipResponse: Codable {
    let success: Bool
    let matchId: UUID?
    let status: String?
    let message: String
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case success
        case matchId = "match_id"
        case status
        case message
        case timestamp
    }
}

/// Request to send message in mentorship
public struct SendMentorshipMessageRequest: Codable {
    let matchId: UUID
    let content: String

    enum CodingKeys: String, CodingKey {
        case matchId = "match_id"
        case content
    }

    public init(matchId: UUID, content: String) {
        self.matchId = matchId
        self.content = content
    }
}

/// Response from safety check function
public struct SafetyCheckResponse: Codable {
    let success: Bool
    let messagesChecked: Int
    let messagesFlagged: Int
    let criticalEscalations: Int
    let flaggedDetails: [FlaggedMessageDetail]
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case success
        case messagesChecked = "messages_checked"
        case messagesFlagged = "messages_flagged"
        case criticalEscalations = "critical_escalations"
        case flaggedDetails = "flagged_details"
        case timestamp
    }

    public struct FlaggedMessageDetail: Codable {
        let messageId: UUID
        let severity: String
        let reasons: [String]

        enum CodingKeys: String, CodingKey {
            case messageId = "message_id"
            case severity
            case reasons
        }
    }
}
