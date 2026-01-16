// Spec 11: Family Wellness - Together Moments Models
// Models for synchronized family wellness activities

import Foundation

// MARK: - Together Session

struct TogetherSession: Codable, Identifiable, Equatable {
    let id: String
    let familyId: String

    let exerciseId: String?
    let togetherTemplateId: String?
    let title: String

    let scheduledFor: Date?
    var startedAt: Date?
    var endedAt: Date?
    var durationSeconds: Int?

    let minimumParticipants: Int

    var status: TogetherSessionStatus
    let syncMode: TogetherSyncMode
    let asyncWindowHours: Int?

    let createdBy: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case exerciseId = "exercise_id"
        case togetherTemplateId = "together_template_id"
        case title
        case scheduledFor = "scheduled_for"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case minimumParticipants = "minimum_participants"
        case status
        case syncMode = "sync_mode"
        case asyncWindowHours = "async_window_hours"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }

    var isActive: Bool {
        status == .inProgress
    }

    var timeRemaining: TimeInterval? {
        guard let startedAt = startedAt, let duration = durationSeconds else { return nil }
        let elapsed = Date().timeIntervalSince(startedAt)
        let remaining = Double(duration) - elapsed
        return max(0, remaining)
    }
}

enum TogetherSessionStatus: String, Codable, Equatable {
    case pending
    case inProgress = "in_progress"
    case completed
    case cancelled
}

enum TogetherSyncMode: String, Codable, Equatable {
    case realtime
    case asyncWindow = "async_window"
}

// MARK: - Together Template

struct TogetherTemplate: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let description: String?
    let category: TogetherCategory

    let contentType: TogetherContentType
    let durationMinutes: Int
    let audioUrl: String?

    let minimumParticipants: Int
    let maximumParticipants: Int
    let minimumAge: Int

    let configuration: TogetherConfiguration?

    let isActive: Bool
    let isPremium: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, description, category
        case contentType = "content_type"
        case durationMinutes = "duration_minutes"
        case audioUrl = "audio_url"
        case minimumParticipants = "minimum_participants"
        case maximumParticipants = "maximum_participants"
        case minimumAge = "minimum_age"
        case configuration
        case isActive = "is_active"
        case isPremium = "is_premium"
    }

    var formattedDuration: String {
        if durationMinutes < 60 {
            return "\(durationMinutes)m"
        } else {
            let hours = durationMinutes / 60
            let minutes = durationMinutes % 60
            if minutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(minutes)m"
            }
        }
    }
}

enum TogetherCategory: String, Codable, CaseIterable, Equatable {
    case meditation
    case gratitude
    case breathing
    case checkin
    case movement

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .meditation: return "brain.head.profile"
        case .gratitude: return "heart.fill"
        case .breathing: return "wind"
        case .checkin: return "bubble.left.and.bubble.right"
        case .movement: return "figure.walk"
        }
    }

    var color: String {
        switch self {
        case .meditation: return "blue"
        case .gratitude: return "red"
        case .breathing: return "green"
        case .checkin: return "purple"
        case .movement: return "orange"
        }
    }
}

enum TogetherContentType: String, Codable, Equatable {
    case guidedAudio = "guided_audio"
    case interactive
    case roundRobin = "round_robin"

    var displayName: String {
        switch self {
        case .guidedAudio: return "Guided Audio"
        case .interactive: return "Interactive"
        case .roundRobin: return "Round Robin"
        }
    }
}

struct TogetherConfiguration: Codable, Equatable {
    var rounds: Int?
    var timePerPersonSeconds: Int?
    var includeAudio: Bool?

    enum CodingKeys: String, CodingKey {
        case rounds
        case timePerPersonSeconds = "time_per_person_seconds"
        case includeAudio = "include_audio"
    }
}

// MARK: - Together Participant

struct TogetherParticipant: Codable, Identifiable, Equatable {
    let id: String
    let sessionId: String
    let memberId: String

    var status: TogetherParticipantStatus
    var joinedAt: Date?
    var completedAt: Date?

    var turnOrder: Int?
    var turnCompleted: Bool
    var contribution: String?

    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case memberId = "member_id"
        case status
        case joinedAt = "joined_at"
        case completedAt = "completed_at"
        case turnOrder = "turn_order"
        case turnCompleted = "turn_completed"
        case contribution
        case createdAt = "created_at"
    }

    var isCompleted: Bool {
        status == .completed
    }

    var isActive: Bool {
        status == .joined
    }
}

enum TogetherParticipantStatus: String, Codable, Equatable {
    case invited
    case joined
    case completed
    case declined

    var displayName: String {
        switch self {
        case .invited: return "Invited"
        case .joined: return "Joined"
        case .completed: return "Completed"
        case .declined: return "Declined"
        }
    }
}

// MARK: - Content Age Ratings

struct ContentAgeRating: Codable, Identifiable, Equatable {
    let id: String
    let contentType: String
    let contentId: String

    let minimumAge: Int
    let maximumAge: Int?
    let ratingCategory: ContentRatingCategory

    let containsHeavyTopics: Bool
    let requiresReading: Bool
    let complexityLevel: ComplexityLevel?

    let reviewedBy: String?
    let reviewedAt: Date?

    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case contentType = "content_type"
        case contentId = "content_id"
        case minimumAge = "minimum_age"
        case maximumAge = "maximum_age"
        case ratingCategory = "rating_category"
        case containsHeavyTopics = "contains_heavy_topics"
        case requiresReading = "requires_reading"
        case complexityLevel = "complexity_level"
        case reviewedBy = "reviewed_by"
        case reviewedAt = "reviewed_at"
        case createdAt = "created_at"
    }

    func isAppropriateForAge(_ age: Int) -> Bool {
        return age >= minimumAge && (maximumAge == nil || age <= maximumAge!)
    }
}

enum ContentRatingCategory: String, Codable, Equatable {
    case allAges = "all_ages"
    case kids
    case teen
    case adult

    var displayName: String {
        switch self {
        case .allAges: return "All Ages"
        case .kids: return "Kids (6+)"
        case .teen: return "Teens (13+)"
        case .adult: return "Adults (18+)"
        }
    }

    var minimumAge: Int {
        switch self {
        case .allAges: return 4
        case .kids: return 6
        case .teen: return 13
        case .adult: return 18
        }
    }
}

enum ComplexityLevel: String, Codable, Equatable {
    case simple
    case moderate
    case complex

    var displayName: String {
        rawValue.capitalized
    }
}
