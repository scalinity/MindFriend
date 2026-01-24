import Foundation

// MARK: - Mentorship Profile

/// User profile for mentor/mentee preferences and availability
struct DBMentorshipProfile: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var isMentorAvailable: Bool
    var expertiseAreas: [String]
    var seekingAreas: [String]
    var bio: String?
    var availabilityHoursWeek: Int
    var languages: [String]
    var timezone: String?
    var verified: Bool
    var verifiedAt: Date?
    var trainingCompleted: Bool
    var trainingCompletedAt: Date?
    var totalMentorships: Int
    var avgRating: Double?
    var maxActiveMentees: Int
    var mentorshipStyle: MentorshipStyle
    let createdAt: Date
    var updatedAt: Date

    enum MentorshipStyle: String, Codable, CaseIterable {
        case supportive
        case advisory
        case accountability

        var displayName: String {
            switch self {
            case .supportive: return "Supportive Listener"
            case .advisory: return "Advice & Guidance"
            case .accountability: return "Accountability Partner"
            }
        }

        var description: String {
            switch self {
            case .supportive: return "Focuses on empathetic listening and emotional support"
            case .advisory: return "Shares experiences and offers practical suggestions"
            case .accountability: return "Helps set and track goals with check-ins"
            }
        }

        var icon: String {
            switch self {
            case .supportive: return "ear"
            case .advisory: return "lightbulb"
            case .accountability: return "checkmark.circle"
            }
        }
    }

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
        case verified
        case verifiedAt = "verified_at"
        case trainingCompleted = "training_completed"
        case trainingCompletedAt = "training_completed_at"
        case totalMentorships = "total_mentorships"
        case avgRating = "avg_rating"
        case maxActiveMentees = "max_active_mentees"
        case mentorshipStyle = "mentorship_style"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Mentorship Match

/// A match between mentor and mentee with compatibility scores
struct DBMentorshipMatch: Codable, Identifiable {
    let id: UUID
    let mentorId: UUID
    let menteeId: UUID
    let matchedAt: Date
    var status: MatchStatus
    var compatibilityScore: Double?
    var matchReason: String?
    var expertiseMatchScore: Double?
    var languageMatchScore: Double?
    var timezoneMatchScore: Double?
    var availabilityMatchScore: Double?
    var introductionMessage: String?
    var mentorResponse: String?
    var startedAt: Date?
    var endedAt: Date?
    var endReason: String?
    var durationWeeks: Int
    let mentorAlias: String
    let menteeAlias: String
    let createdAt: Date
    var updatedAt: Date

    enum MatchStatus: String, Codable, CaseIterable {
        case pending
        case accepted
        case active
        case completed
        case declined
        case ended
        case suspended

        var displayName: String {
            switch self {
            case .pending: return "Pending"
            case .accepted: return "Accepted"
            case .active: return "Active"
            case .completed: return "Completed"
            case .declined: return "Declined"
            case .ended: return "Ended"
            case .suspended: return "Suspended"
            }
        }

        var isActive: Bool {
            switch self {
            case .pending, .accepted, .active:
                return true
            case .completed, .declined, .ended, .suspended:
                return false
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case mentorId = "mentor_id"
        case menteeId = "mentee_id"
        case matchedAt = "matched_at"
        case status
        case compatibilityScore = "compatibility_score"
        case matchReason = "match_reason"
        case expertiseMatchScore = "expertise_match_score"
        case languageMatchScore = "language_match_score"
        case timezoneMatchScore = "timezone_match_score"
        case availabilityMatchScore = "availability_match_score"
        case introductionMessage = "introduction_message"
        case mentorResponse = "mentor_response"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case endReason = "end_reason"
        case durationWeeks = "duration_weeks"
        case mentorAlias = "mentor_alias"
        case menteeAlias = "mentee_alias"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Mentorship Message

/// A message between matched mentor and mentee
struct DBMentorshipMessage: Codable, Identifiable {
    let id: UUID
    let matchId: UUID
    let senderId: UUID
    let content: String
    let sentAt: Date
    var readAt: Date?
    var flagged: Bool
    var flagReason: String?
    var reviewed: Bool
    var reviewedAt: Date?
    var reviewedBy: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case matchId = "match_id"
        case senderId = "sender_id"
        case content
        case sentAt = "sent_at"
        case readAt = "read_at"
        case flagged
        case flagReason = "flag_reason"
        case reviewed
        case reviewedAt = "reviewed_at"
        case reviewedBy = "reviewed_by"
        case createdAt = "created_at"
    }
}

// MARK: - Mentorship Report

/// A safety report for mentorship interactions
struct DBMentorshipReport: Codable, Identifiable {
    let id: UUID
    let reporterId: UUID
    let reportedId: UUID
    var matchId: UUID?
    let reason: ReportReason
    var description: String?
    var messageIds: [UUID]
    var status: ReportStatus
    var resolution: String?
    var resolvedAt: Date?
    var resolvedBy: UUID?
    var actionTaken: ReportAction?
    let createdAt: Date

    enum ReportReason: String, Codable, CaseIterable {
        case inappropriateContent = "inappropriate_content"
        case harassment
        case boundaryViolation = "boundary_violation"
        case unprofessional
        case crisisMishandling = "crisis_mishandling"
        case personalInfoRequest = "personal_info_request"
        case other

        var displayName: String {
            switch self {
            case .inappropriateContent: return "Inappropriate Content"
            case .harassment: return "Harassment"
            case .boundaryViolation: return "Boundary Violation"
            case .unprofessional: return "Unprofessional Behavior"
            case .crisisMishandling: return "Crisis Mishandling"
            case .personalInfoRequest: return "Personal Info Request"
            case .other: return "Other"
            }
        }
    }

    enum ReportStatus: String, Codable {
        case pending
        case investigating
        case resolved
        case dismissed

        var displayName: String {
            switch self {
            case .pending: return "Pending Review"
            case .investigating: return "Under Investigation"
            case .resolved: return "Resolved"
            case .dismissed: return "Dismissed"
            }
        }
    }

    enum ReportAction: String, Codable {
        case warning
        case suspension
        case permanentBan = "permanent_ban"
        case noAction = "no_action"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case reporterId = "reporter_id"
        case reportedId = "reported_id"
        case matchId = "match_id"
        case reason
        case description
        case messageIds = "message_ids"
        case status
        case resolution
        case resolvedAt = "resolved_at"
        case resolvedBy = "resolved_by"
        case actionTaken = "action_taken"
        case createdAt = "created_at"
    }
}

// MARK: - Mentor Match Result

/// Result from the find-mentor-matches API
struct MentorMatchResult: Codable, Identifiable {
    let mentorUserId: UUID
    let profileId: UUID
    let bio: String?
    let expertiseAreas: [String]
    let languages: [String]
    let mentorshipStyle: String
    let availabilityHoursWeek: Int
    let avgRating: Double?
    let totalMentorships: Int
    let compatibilityScore: Double
    let expertiseMatchScore: Double
    let languageMatchScore: Double
    let timezoneMatchScore: Double
    let availabilityMatchScore: Double
    let matchReason: String

    var id: UUID { mentorUserId }

    var styleEnum: DBMentorshipProfile.MentorshipStyle {
        DBMentorshipProfile.MentorshipStyle(rawValue: mentorshipStyle) ?? .supportive
    }

    var formattedRating: String {
        if let rating = avgRating {
            return String(format: "%.1f", rating)
        }
        return "New"
    }

    var compatibilityPercentage: Int {
        Int(compatibilityScore)
    }
}

// MARK: - Find Matches Response

struct FindMentorMatchesResponse: Codable {
    let success: Bool
    let matches: [MentorMatchResult]
    let count: Int
}

// MARK: - Request Mentorship Response

struct RequestMentorshipResponse: Codable {
    let success: Bool
    let matchId: UUID?
    let match: MatchInfo?
    let message: String?
    let error: String?
    let code: String?

    struct MatchInfo: Codable {
        let id: UUID
        let mentorId: UUID
        let menteeId: UUID
        let status: String
        let compatibilityScore: Double?
        let matchReason: String?
        let mentorAlias: String
        let menteeAlias: String
        let createdAt: Date?
    }
}

// MARK: - Expertise Areas

/// Common expertise areas for mentorship matching
enum MentorshipExpertiseArea: String, CaseIterable, Identifiable {
    case anxiety
    case depression
    case stress
    case grief
    case relationships
    case loneliness
    case selfEsteem = "self_esteem"
    case workLife = "work_life"
    case family
    case addiction
    case trauma
    case lifeTransitions = "life_transitions"
    case caregiving
    case chronicIllness = "chronic_illness"
    case general

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anxiety: return "Anxiety"
        case .depression: return "Depression"
        case .stress: return "Stress Management"
        case .grief: return "Grief & Loss"
        case .relationships: return "Relationships"
        case .loneliness: return "Loneliness"
        case .selfEsteem: return "Self-Esteem"
        case .workLife: return "Work-Life Balance"
        case .family: return "Family Issues"
        case .addiction: return "Addiction Recovery"
        case .trauma: return "Trauma Healing"
        case .lifeTransitions: return "Life Transitions"
        case .caregiving: return "Caregiving"
        case .chronicIllness: return "Chronic Illness"
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
        case .addiction: return "arrow.triangle.2.circlepath"
        case .trauma: return "bandage"
        case .lifeTransitions: return "arrow.right.arrow.left"
        case .caregiving: return "heart.text.square"
        case .chronicIllness: return "heart.circle"
        case .general: return "bubble.left.and.bubble.right"
        }
    }
}
