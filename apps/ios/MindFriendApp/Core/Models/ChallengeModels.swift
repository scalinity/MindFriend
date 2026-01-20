import Foundation

// MARK: - Enums

public enum SocialChallengeType: String, Codable, CaseIterable {
    case streak = "streak"
    case minutes = "minutes"
    case mood = "mood"
    case quest = "quest"

    var displayName: String {
        switch self {
        case .streak:
            return "Daily Streak"
        case .minutes:
            return "Exercise Minutes"
        case .mood:
            return "Mood Check-ins"
        case .quest:
            return "Quest Completion"
        }
    }

    var iconName: String {
        switch self {
        case .streak:
            return "flame.fill"
        case .minutes:
            return "clock.fill"
        case .mood:
            return "heart.fill"
        case .quest:
            return "checkmark.circle.fill"
        }
    }

    var unitLabel: String {
        switch self {
        case .streak:
            return "days"
        case .minutes:
            return "minutes"
        case .mood:
            return "logs"
        case .quest:
            return "quests"
        }
    }
}

public enum ChallengeStatus: String {
    case upcoming
    case active
    case ended

    var displayName: String {
        switch self {
        case .upcoming:
            return "Coming Soon"
        case .active:
            return "Active"
        case .ended:
            return "Ended"
        }
    }
}

// MARK: - Models

public struct SocialChallenge: Identifiable, Codable {
    public let id: UUID
    public let title: String
    public let description: String
    public let challengeType: SocialChallengeType
    public let targetValue: Int
    public let durationDays: Int
    public let isPublic: Bool
    public let circleId: UUID?
    public let createdBy: UUID
    public let exerciseType: String?
    public let startsAt: Date
    public let endsAt: Date
    public let finalized: Bool
    public let finalizedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case challengeType = "challenge_type"
        case targetValue = "target_value"
        case durationDays = "duration_days"
        case isPublic = "is_public"
        case circleId = "circle_id"
        case createdBy = "created_by"
        case exerciseType = "exercise_type"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case finalized
        case finalizedAt = "finalized_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public var status: ChallengeStatus {
        let now = Date()
        if now < startsAt {
            return .upcoming
        } else if now < endsAt {
            return .active
        } else {
            return .ended
        }
    }

    public var isActive: Bool {
        status == .active
    }

    public var daysRemaining: Int {
        let remaining = Calendar.current.dateComponents([.day], from: Date(), to: endsAt)
        return max(0, remaining.day ?? 0)
    }

    public var progressLabel: String {
        "\(targetValue) \(challengeType.unitLabel)"
    }
}

public struct ChallengeParticipant: Identifiable, Codable {
    public let id: UUID
    public let challengeId: UUID
    public let userId: UUID
    public let currentProgress: Int
    public let completed: Bool
    public let completedAt: Date?
    public let finalRank: Int?
    public let showOnLeaderboard: Bool
    public let joinedAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case challengeId = "challenge_id"
        case userId = "user_id"
        case currentProgress = "current_progress"
        case completed
        case completedAt = "completed_at"
        case finalRank = "final_rank"
        case showOnLeaderboard = "show_on_leaderboard"
        case joinedAt = "joined_at"
        case updatedAt = "updated_at"
    }

    public func progressPercent(targetValue: Int) -> Double {
        guard targetValue > 0 else { return 0 }
        return Double(currentProgress) / Double(targetValue)
    }
}

public struct ChallengeWithParticipation: Identifiable {
    public let id: UUID
    public let challenge: SocialChallenge
    public let participation: ChallengeParticipant?
    public let participantCount: Int

    public init(
        challenge: SocialChallenge,
        participation: ChallengeParticipant? = nil,
        participantCount: Int = 0
    ) {
        self.id = challenge.id
        self.challenge = challenge
        self.participation = participation
        self.participantCount = participantCount
    }

    public var isJoined: Bool {
        participation != nil
    }

    public var progressPercent: Double {
        guard let participation = participation else { return 0 }
        return participation.progressPercent(targetValue: challenge.targetValue)
    }
}

public struct LeaderboardEntry: Identifiable {
    public let id: UUID
    public let rank: Int
    public let participant: ChallengeParticipant
    public let userProfile: UserProfile
    public let isCurrentUser: Bool
    public let isTied: Bool

    public init(
        participant: ChallengeParticipant,
        userProfile: UserProfile,
        rank: Int,
        isCurrentUser: Bool = false,
        isTied: Bool = false
    ) {
        self.id = participant.id
        self.participant = participant
        self.userProfile = userProfile
        self.rank = rank
        self.isCurrentUser = isCurrentUser
        self.isTied = isTied
    }

    public var displayName: String {
        userProfile.displayName ?? "Anonymous"
    }

    public var avatarUrl: String? {
        userProfile.avatarUrl
    }
}

public struct ChallengeReward: Codable {
    public let placement: Int // 1, 2, 3 for top 3; 0 for completion
    public let xpEarned: Int
    public let badgeCode: String?

    public var placementLabel: String {
        switch placement {
        case 1:
            return "🥇 1st Place"
        case 2:
            return "🥈 2nd Place"
        case 3:
            return "🥉 3rd Place"
        default:
            return "Participant"
        }
    }

    public var badgeColor: String {
        switch placement {
        case 1:
            return "#FFD700" // Gold
        case 2:
            return "#C0C0C0" // Silver
        case 3:
            return "#CD7F32" // Bronze
        default:
            return "#808080" // Gray
        }
    }
}

// MARK: - Request/Response DTOs

public struct CreateChallengeRequest: Codable {
    public let title: String
    public let description: String
    public let challengeType: SocialChallengeType
    public let targetValue: Int
    public let durationDays: Int
    public let circleId: UUID?
    public let exerciseType: String?

    public init(
        title: String,
        description: String,
        challengeType: SocialChallengeType,
        targetValue: Int,
        durationDays: Int = 7,
        circleId: UUID? = nil,
        exerciseType: String? = nil
    ) {
        self.title = title
        self.description = description
        self.challengeType = challengeType
        self.targetValue = targetValue
        self.durationDays = durationDays
        self.circleId = circleId
        self.exerciseType = exerciseType
    }

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case challengeType = "challenge_type"
        case targetValue = "target_value"
        case durationDays = "duration_days"
        case circleId = "circle_id"
        case exerciseType = "exercise_type"
    }
}

public struct JoinChallengeRequest: Codable {
    public let challengeId: UUID
    public let showOnLeaderboard: Bool

    public init(challengeId: UUID, showOnLeaderboard: Bool = true) {
        self.challengeId = challengeId
        self.showOnLeaderboard = showOnLeaderboard
    }

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case showOnLeaderboard = "show_on_leaderboard"
    }
}

public struct UpdateLeaderboardVisibilityRequest: Codable {
    public let showOnLeaderboard: Bool

    public init(showOnLeaderboard: Bool) {
        self.showOnLeaderboard = showOnLeaderboard
    }

    enum CodingKeys: String, CodingKey {
        case showOnLeaderboard = "show_on_leaderboard"
    }
}

// MARK: - Database Models (for Supabase response mapping)

struct DBSocialChallenge: Codable {
    let id: UUID
    let title: String
    let description: String
    let challenge_type: String
    let target_value: Int
    let duration_days: Int
    let is_public: Bool
    let circle_id: UUID?
    let created_by: UUID
    let exercise_type: String?
    let starts_at: String
    let ends_at: String
    let finalized: Bool
    let finalized_at: String?
    let created_at: String
    let updated_at: String

    func toSocialChallenge() throws -> SocialChallenge {
        guard let challengeType = SocialChallengeType(rawValue: challenge_type) else {
            throw ChallengeError.invalidId
        }

        let iso8601Formatter = ISO8601DateFormatter()
        guard let startsAt = iso8601Formatter.date(from: starts_at),
              let endsAt = iso8601Formatter.date(from: ends_at),
              let createdAt = iso8601Formatter.date(from: created_at),
              let updatedAt = iso8601Formatter.date(from: updated_at)
        else {
            throw ChallengeError.loadFailed
        }

        let finalizedAtDate = finalized_at.flatMap { iso8601Formatter.date(from: $0) }

        return SocialChallenge(
            id: id,
            title: title,
            description: description,
            challengeType: challengeType,
            targetValue: target_value,
            durationDays: duration_days,
            isPublic: is_public,
            circleId: circle_id,
            createdBy: created_by,
            exerciseType: exercise_type,
            startsAt: startsAt,
            endsAt: endsAt,
            finalized: finalized,
            finalizedAt: finalizedAtDate,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct DBChallengeParticipant: Codable {
    let id: UUID
    let challenge_id: UUID
    let user_id: UUID
    let current_progress: Int
    let completed: Bool
    let completed_at: String?
    let final_rank: Int?
    let show_on_leaderboard: Bool
    let joined_at: String
    let updated_at: String

    func toChallengeParticipant() throws -> ChallengeParticipant {
        let iso8601Formatter = ISO8601DateFormatter()

        guard let joinedAt = iso8601Formatter.date(from: joined_at),
              let updatedAt = iso8601Formatter.date(from: updated_at)
        else {
            throw ChallengeError.loadFailed
        }

        let completedAtDate = completed_at.flatMap { iso8601Formatter.date(from: $0) }

        return ChallengeParticipant(
            id: id,
            challengeId: challenge_id,
            userId: user_id,
            currentProgress: current_progress,
            completed: completed,
            completedAt: completedAtDate,
            finalRank: final_rank,
            showOnLeaderboard: show_on_leaderboard,
            joinedAt: joinedAt,
            updatedAt: updatedAt
        )
    }
}

struct DBParticipantProfile: Codable {
    let id: UUID
    let challenge_id: UUID
    let user_id: UUID
    let current_progress: Int
    let completed: Bool
    let completed_at: String?
    let final_rank: Int?
    let show_on_leaderboard: Bool
    let joined_at: String
    let updated_at: String
    let display_name: String?
    let avatar_url: String?
}

// MARK: - Errors

public enum ChallengeError: LocalizedError {
    case notAuthenticated
    case invalidId
    case rateLimited
    case exerciseTypeRequired
    case loadFailed
    case alreadyJoined
    case challengeEnded
    case invalidChallenge
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to join challenges."
        case .invalidId:
            return "The challenge ID is invalid."
        case .rateLimited:
            return "You've hit the rate limit. Try again later."
        case .exerciseTypeRequired:
            return "Exercise type is required for this challenge."
        case .loadFailed:
            return "Failed to load challenges. Please try again."
        case .alreadyJoined:
            return "You've already joined this challenge."
        case .challengeEnded:
            return "This challenge has ended."
        case .invalidChallenge:
            return "The challenge is no longer available."
        case let .networkError(error):
            return error.localizedDescription
        }
    }
}
