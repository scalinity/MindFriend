import Foundation

// MARK: - Listener

/// A certified peer support listener who can provide support to seekers
struct DBListener: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var status: ListenerStatus
    var trainingStartedAt: Date?
    var trainingCompletedAt: Date?
    var certificationScore: Int?
    var certificationPassed: Bool?
    var specializations: [String]
    var languages: [String]
    var isAvailable: Bool
    var availableHours: [String: [TimeSlot]]?
    var maxSessionsPerWeek: Int
    var totalSessions: Int
    var totalHours: Double
    var averageRating: Double?
    var ratingCount: Int
    var acceptsVoiceCalls: Bool
    var acceptsCrisisBridge: Bool
    var bio: String?
    var displayName: String?
    let createdAt: Date
    var updatedAt: Date

    enum ListenerStatus: String, Codable, CaseIterable {
        case applicant
        case training
        case active
        case inactive
        case suspended

        var displayName: String {
            switch self {
            case .applicant: return "Applicant"
            case .training: return "In Training"
            case .active: return "Active"
            case .inactive: return "Inactive"
            case .suspended: return "Suspended"
            }
        }

        var isEligibleForSessions: Bool {
            self == .active
        }
    }

    struct TimeSlot: Codable, Equatable {
        let start: String
        let end: String
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case status
        case trainingStartedAt = "training_started_at"
        case trainingCompletedAt = "training_completed_at"
        case certificationScore = "certification_score"
        case certificationPassed = "certification_passed"
        case specializations
        case languages
        case isAvailable = "is_available"
        case availableHours = "available_hours"
        case maxSessionsPerWeek = "max_sessions_per_week"
        case totalSessions = "total_sessions"
        case totalHours = "total_hours"
        case averageRating = "average_rating"
        case ratingCount = "rating_count"
        case acceptsVoiceCalls = "accepts_voice_calls"
        case acceptsCrisisBridge = "accepts_crisis_bridge"
        case bio
        case displayName = "display_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Training Progress

struct DBListenerTrainingProgress: Codable, Identifiable {
    let id: UUID
    let listenerId: UUID
    let moduleId: String
    let startedAt: Date
    var completedAt: Date?
    var score: Int?
    var attempts: Int

    enum CodingKeys: String, CodingKey {
        case id
        case listenerId = "listener_id"
        case moduleId = "module_id"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case score
        case attempts
    }
}

// MARK: - Support Session

/// A peer support session between a seeker and listener
struct DBSupportSession: Codable, Identifiable {
    let id: UUID
    let seekerId: UUID
    var listenerId: UUID?
    let sessionType: SessionType
    var status: SessionStatus
    let requestedAt: Date
    var matchedAt: Date?
    var startedAt: Date?
    var endedAt: Date?
    var topicTags: [String]?
    var seekerMoodBefore: Int?
    var seekerNotes: String?
    var seekerMoodAfter: Int?
    var durationMinutes: Int?
    var wasEscalated: Bool
    var escalationReason: String?
    var escalatedAt: Date?
    var isAnonymous: Bool
    let createdAt: Date

    enum SessionType: String, Codable, CaseIterable {
        case quick
        case deep
        case crisisBridge = "crisis_bridge"
        case group

        var displayName: String {
            switch self {
            case .quick: return "Quick Support"
            case .deep: return "Deep Conversation"
            case .crisisBridge: return "Crisis Support"
            case .group: return "Group Session"
            }
        }

        var estimatedMinutes: Int {
            switch self {
            case .quick: return 15
            case .deep: return 45
            case .crisisBridge: return 30
            case .group: return 60
            }
        }

        var icon: String {
            switch self {
            case .quick: return "clock"
            case .deep: return "bubble.left.and.bubble.right"
            case .crisisBridge: return "heart.circle"
            case .group: return "person.3"
            }
        }
    }

    enum SessionStatus: String, Codable, CaseIterable {
        case pending
        case matched
        case active
        case completed
        case cancelled
        case escalated

        var displayName: String {
            switch self {
            case .pending: return "Waiting"
            case .matched: return "Matched"
            case .active: return "In Progress"
            case .completed: return "Completed"
            case .cancelled: return "Cancelled"
            case .escalated: return "Escalated"
            }
        }

        var isActive: Bool {
            switch self {
            case .pending, .matched, .active:
                return true
            case .completed, .cancelled, .escalated:
                return false
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case seekerId = "seeker_id"
        case listenerId = "listener_id"
        case sessionType = "session_type"
        case status
        case requestedAt = "requested_at"
        case matchedAt = "matched_at"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case topicTags = "topic_tags"
        case seekerMoodBefore = "seeker_mood_before"
        case seekerNotes = "seeker_notes"
        case seekerMoodAfter = "seeker_mood_after"
        case durationMinutes = "duration_minutes"
        case wasEscalated = "was_escalated"
        case escalationReason = "escalation_reason"
        case escalatedAt = "escalated_at"
        case isAnonymous = "is_anonymous"
        case createdAt = "created_at"
    }
}

// MARK: - Support Message

struct DBSupportMessage: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let senderType: SenderType
    let content: String
    var isFlagged: Bool
    var flagReason: String?
    let sentAt: Date

    enum SenderType: String, Codable {
        case seeker
        case listener
        case system
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case senderType = "sender_type"
        case content
        case isFlagged = "is_flagged"
        case flagReason = "flag_reason"
        case sentAt = "sent_at"
    }
}

// MARK: - Session Feedback

struct DBSessionFeedback: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let fromUserId: UUID
    let rating: Int
    var feltHeard: Bool?
    var feltSupported: Bool?
    var wouldRecommend: Bool?
    var feedbackText: String?
    var seekerEngagement: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case fromUserId = "from_user_id"
        case rating
        case feltHeard = "felt_heard"
        case feltSupported = "felt_supported"
        case wouldRecommend = "would_recommend"
        case feedbackText = "feedback_text"
        case seekerEngagement = "seeker_engagement"
        case createdAt = "created_at"
    }
}

// MARK: - Mentorship

/// A long-term mentor-mentee relationship
struct DBMentorship: Codable, Identifiable {
    let id: UUID
    let mentorId: UUID
    let menteeId: UUID
    var status: MentorshipStatus
    var matchedOnChallenges: [String]?
    var compatibilityScore: Double?
    var startedAt: Date?
    var lastInteractionAt: Date?
    var nextCheckinDue: Date?
    var endsAt: Date?
    var checkinFrequency: CheckinFrequency
    var mentorCanSeeProgress: Bool
    let createdAt: Date
    var updatedAt: Date

    enum MentorshipStatus: String, Codable, CaseIterable {
        case pending
        case active
        case paused
        case completed
        case cancelled

        var displayName: String {
            switch self {
            case .pending: return "Pending"
            case .active: return "Active"
            case .paused: return "Paused"
            case .completed: return "Completed"
            case .cancelled: return "Cancelled"
            }
        }
    }

    enum CheckinFrequency: String, Codable, CaseIterable {
        case daily
        case weekly
        case biweekly

        var displayName: String {
            switch self {
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .biweekly: return "Every 2 Weeks"
            }
        }

        var days: Int {
            switch self {
            case .daily: return 1
            case .weekly: return 7
            case .biweekly: return 14
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case mentorId = "mentor_id"
        case menteeId = "mentee_id"
        case status
        case matchedOnChallenges = "matched_on_challenges"
        case compatibilityScore = "compatibility_score"
        case startedAt = "started_at"
        case lastInteractionAt = "last_interaction_at"
        case nextCheckinDue = "next_checkin_due"
        case endsAt = "ends_at"
        case checkinFrequency = "checkin_frequency"
        case mentorCanSeeProgress = "mentor_can_see_progress"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Mentorship Check-in

struct DBMentorshipCheckin: Codable, Identifiable {
    let id: UUID
    let mentorshipId: UUID
    let initiatedBy: UUID
    let checkinType: CheckinType
    var message: String?
    var moodShared: Int?
    var winsShared: [String]?
    var challengesShared: [String]?
    var goalsDiscussed: [String]?
    var respondedAt: Date?
    var responseMessage: String?
    let createdAt: Date

    enum CheckinType: String, Codable {
        case scheduled
        case spontaneous
        case celebration
        case supportRequest = "support_request"

        var displayName: String {
            switch self {
            case .scheduled: return "Scheduled"
            case .spontaneous: return "Spontaneous"
            case .celebration: return "Celebration"
            case .supportRequest: return "Support Request"
            }
        }

        var icon: String {
            switch self {
            case .scheduled: return "calendar"
            case .spontaneous: return "bubble.left"
            case .celebration: return "party.popper"
            case .supportRequest: return "hand.raised"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case mentorshipId = "mentorship_id"
        case initiatedBy = "initiated_by"
        case checkinType = "checkin_type"
        case message
        case moodShared = "mood_shared"
        case winsShared = "wins_shared"
        case challengesShared = "challenges_shared"
        case goalsDiscussed = "goals_discussed"
        case respondedAt = "responded_at"
        case responseMessage = "response_message"
        case createdAt = "created_at"
    }
}

// MARK: - Gratitude Action

struct DBGratitudeAction: Codable, Identifiable {
    let id: UUID
    let fromUserId: UUID
    var toUserId: UUID?
    let actionType: ActionType
    var message: String?
    var isPublic: Bool
    var sessionId: UUID?
    var mentorshipId: UUID?
    let createdAt: Date

    enum ActionType: String, Codable, CaseIterable {
        case thankListener = "thank_listener"
        case communityHug = "community_hug"
        case wisdomShare = "wisdom_share"
        case storySpotlight = "story_spotlight"
        case donation

        var displayName: String {
            switch self {
            case .thankListener: return "Thank You"
            case .communityHug: return "Community Hug"
            case .wisdomShare: return "Shared Wisdom"
            case .storySpotlight: return "Story Shared"
            case .donation: return "Donation"
            }
        }

        var icon: String {
            switch self {
            case .thankListener: return "heart.fill"
            case .communityHug: return "hands.sparkles.fill"
            case .wisdomShare: return "lightbulb.fill"
            case .storySpotlight: return "star.fill"
            case .donation: return "gift.fill"
            }
        }

        var color: String {
            switch self {
            case .thankListener: return "red"
            case .communityHug: return "pink"
            case .wisdomShare: return "yellow"
            case .storySpotlight: return "orange"
            case .donation: return "green"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case fromUserId = "from_user_id"
        case toUserId = "to_user_id"
        case actionType = "action_type"
        case message
        case isPublic = "is_public"
        case sessionId = "session_id"
        case mentorshipId = "mentorship_id"
        case createdAt = "created_at"
    }
}

// MARK: - Community Wisdom

struct DBCommunityWisdom: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let title: String
    let content: String
    let category: WisdomCategory
    var tags: [String]?
    var status: WisdomStatus
    var moderatedAt: Date?
    var moderationNotes: String?
    var helpfulCount: Int
    var saveCount: Int
    let createdAt: Date

    enum WisdomCategory: String, Codable, CaseIterable {
        case coping
        case motivation
        case technique
        case perspective

        var displayName: String {
            switch self {
            case .coping: return "Coping Strategies"
            case .motivation: return "Motivation"
            case .technique: return "Techniques"
            case .perspective: return "Perspectives"
            }
        }

        var icon: String {
            switch self {
            case .coping: return "shield"
            case .motivation: return "flame"
            case .technique: return "wrench.and.screwdriver"
            case .perspective: return "eye"
            }
        }
    }

    enum WisdomStatus: String, Codable {
        case pending
        case approved
        case rejected
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case content
        case category
        case tags
        case status
        case moderatedAt = "moderated_at"
        case moderationNotes = "moderation_notes"
        case helpfulCount = "helpful_count"
        case saveCount = "save_count"
        case createdAt = "created_at"
    }
}

// MARK: - Anonymous Room

struct DBAnonymousRoom: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String
    let topic: String
    var maxParticipants: Int
    var isModerated: Bool
    var requiresListener: Bool
    var isAlwaysOpen: Bool
    var schedule: [String: Any]?
    var isActive: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case topic
        case maxParticipants = "max_participants"
        case isModerated = "is_moderated"
        case requiresListener = "requires_listener"
        case isAlwaysOpen = "is_always_open"
        case schedule
        case isActive = "is_active"
        case createdAt = "created_at"
    }

    // Custom decoding to handle JSONB schedule field
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        topic = try container.decode(String.self, forKey: .topic)
        maxParticipants = try container.decode(Int.self, forKey: .maxParticipants)
        isModerated = try container.decode(Bool.self, forKey: .isModerated)
        requiresListener = try container.decode(Bool.self, forKey: .requiresListener)
        isAlwaysOpen = try container.decode(Bool.self, forKey: .isAlwaysOpen)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        // Skip schedule decoding for simplicity
        schedule = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(topic, forKey: .topic)
        try container.encode(maxParticipants, forKey: .maxParticipants)
        try container.encode(isModerated, forKey: .isModerated)
        try container.encode(requiresListener, forKey: .requiresListener)
        try container.encode(isAlwaysOpen, forKey: .isAlwaysOpen)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - Anonymous Room Participant

struct DBAnonymousRoomParticipant: Codable, Identifiable {
    let id: UUID
    let roomId: UUID
    let userId: UUID
    let anonymousName: String
    var anonymousAvatar: String?
    let joinedAt: Date
    var leftAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case userId = "user_id"
        case anonymousName = "anonymous_name"
        case anonymousAvatar = "anonymous_avatar"
        case joinedAt = "joined_at"
        case leftAt = "left_at"
    }
}

// MARK: - Support Topic

/// Topics for peer support matching
enum SupportTopic: String, CaseIterable, Identifiable, Codable {
    case anxiety
    case depression
    case stress
    case grief
    case relationships
    case loneliness
    case selfEsteem = "self_esteem"
    case workLife = "work_life"
    case family
    case general

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anxiety: return "Anxiety"
        case .depression: return "Depression"
        case .stress: return "Stress"
        case .grief: return "Grief & Loss"
        case .relationships: return "Relationships"
        case .loneliness: return "Loneliness"
        case .selfEsteem: return "Self-Esteem"
        case .workLife: return "Work-Life Balance"
        case .family: return "Family"
        case .general: return "General Support"
        }
    }

    var icon: String {
        switch self {
        case .anxiety: return "wind"
        case .depression: return "cloud.rain"
        case .stress: return "bolt.fill"
        case .grief: return "heart.slash"
        case .relationships: return "person.2"
        case .loneliness: return "person.crop.circle.badge.minus"
        case .selfEsteem: return "person.crop.circle.badge.checkmark"
        case .workLife: return "briefcase"
        case .family: return "house"
        case .general: return "bubble.left.and.bubble.right"
        }
    }
}

// MARK: - API Request/Response Types

struct SupportMatchRequest: Codable {
    let sessionType: String
    var topicTags: [String]?
    var isAnonymous: Bool?
    var preferredLanguage: String?
    var preferredGender: String?
    var seekerMood: Int?
    var seekerNotes: String?
}

struct SupportMatchResponse: Codable {
    let success: Bool
    let sessionId: UUID?
    let status: String?
    let listener: ListenerInfo?
    let estimatedWait: Int?
    let error: String?

    struct ListenerInfo: Codable {
        let displayName: String?
        let rating: Double?
        let sessionCount: Int?
    }
}

// MARK: - Training Module (Local Definition)

struct TrainingModule: Identifiable {
    let id: String
    let title: String
    let description: String
    let durationMinutes: Int
    let content: [TrainingContent]
    let quiz: [QuizQuestion]
    let requiredScore: Int

    struct TrainingContent: Identifiable {
        let id: String
        let type: ContentType
        let content: String

        enum ContentType {
            case text
            case video
            case interactive
            case scenario
        }
    }

    struct QuizQuestion: Identifiable {
        let id: String
        let question: String
        let options: [String]
        let correctIndex: Int
        let explanation: String
    }
}

// MARK: - Listener Stats

struct ListenerStats {
    let listenerId: UUID
    let totalSessions: Int
    let totalHours: Double
    let averageRating: Double?
    let ratingCount: Int
    let isAvailable: Bool
    let specializations: [String]
}

// MARK: - Listener Availability

struct DBListenerAvailability: Codable, Identifiable {
    let id: UUID
    let listenerId: UUID
    let dayOfWeek: Int
    let startTime: String
    let endTime: String
    let timezone: String
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case listenerId = "listener_id"
        case dayOfWeek = "day_of_week"
        case startTime = "start_time"
        case endTime = "end_time"
        case timezone
        case isActive = "is_active"
    }

    var dayName: String {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard dayOfWeek >= 0, dayOfWeek < days.count else { return "Unknown" }
        return days[dayOfWeek]
    }
}
