/// Couples/Partner Mode Data Models
/// Structures for partner linking, couples exercises, and shared features
///
/// Defined per specification: `/opus-specs/11-couples-mode-v2.1.md`

import Foundation

// MARK: - Partner Link Model

/// Represents a partnership between two users with asymmetric sharing settings
struct PartnerLink: Codable, Identifiable {
    let id: UUID
    let userId1: UUID
    let userId2: UUID?
    let inviteCode: String?
    let createdBy: UUID
    let expiresAt: Date
    let status: PartnerLinkStatus
    let activatedAt: Date?
    let endedAt: Date?
    let user1ShareMood: Bool
    let user1ShareExercises: Bool
    let user2ShareMood: Bool
    let user2ShareExercises: Bool
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"

        case userId1 = "user_id_1"
        case userId2 = "user_id_2"
        case inviteCode = "invite_code"
        case createdBy = "created_by"
        case expiresAt = "expires_at"
        case activatedAt = "activated_at"
        case endedAt = "ended_at"
        case user1ShareMood = "user_1_share_mood"
        case user1ShareExercises = "user_1_share_exercises"
        case user2ShareMood = "user_2_share_mood"
        case user2ShareExercises = "user_2_share_exercises"
    }
}

/// Status of a partnership
enum PartnerLinkStatus: String, Codable {
    case pending = "pending"
    case active = "active"
    case ended = "ended"
    case expired = "expired"
}

// MARK: - Couples Exercise Models

/// A couples exercise from the library
struct CouplesExercise: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String
    let type: CouplesExerciseType
    let difficulty: CouplesExerciseDifficulty
    let durationMinutes: Int
    let instructions: CouplesExerciseInstructions
    let requiresPremium: Bool
    let requiresBothPartners: Bool
    let canDoSolo: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, description, type, difficulty, instructions, createdAt, updatedAt
        case durationMinutes = "duration_minutes"
        case requiresPremium = "requires_premium"
        case requiresBothPartners = "requires_both_partners"
        case canDoSolo = "can_do_solo"
    }
}

/// Type of couples exercise (COUPLES-SPECIFIC)
enum CouplesExerciseType: String, Codable {
    case communication = "communication"
    case intimacy = "intimacy"
    case goalSetting = "goal-setting"
    case mindfulness = "mindfulness"
}

/// Difficulty level of an exercise (couples-specific to avoid ambiguity with Models.ExerciseDifficulty)
enum CouplesExerciseDifficulty: String, Codable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"
}

/// Role-specific instructions for partners
struct RoleSpecificInstructions: Codable {
    let partner1: String?
    let partner2: String?

    enum CodingKeys: String, CodingKey {
        case partner1 = "partner_1"
        case partner2 = "partner_2"
    }
}

/// Step-by-step instructions for a couples exercise
struct CouplesExerciseInstructions: Codable {
    let steps: [CouplesExerciseStep]
    let materialsNeeded: [String]?
    let tips: String?
    let canDoSolo: Bool
    let requiresBothPartners: Bool

    enum CodingKeys: String, CodingKey {
        case steps
        case tips
        case canDoSolo = "can_do_solo"
        case requiresBothPartners = "requires_both_partners"
        case materialsNeeded = "materials_needed"
    }
}

/// Individual step in a couples exercise
struct CouplesExerciseStep: Codable {
    let order: Int
    let title: String
    let description: String
    let durationSeconds: Int
    let roleSpecific: RoleSpecificInstructions?

    enum CodingKeys: String, CodingKey {
        case order, title, description
        case durationSeconds = "duration_seconds"
        case roleSpecific = "role_specific"
    }
}

// MARK: - Couples Exercise Session Models

/// A session where partners complete an exercise together
struct CouplesExerciseSession: Codable, Identifiable {
    let id: UUID
    let partnerLinkId: UUID
    let exerciseId: UUID
    let userId1: UUID
    let userId2: UUID?
    let status: SessionStatus
    let user1Rating: Int?
    let user2Rating: Int?
    let user1Notes: String?
    let user2Notes: String?
    let user1ProgressPercent: Int
    let user2ProgressPercent: Int
    let startedAt: Date
    let completedAt: Date?
    let lastActivityAt: Date
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, createdAt, updatedAt
        case partnerLinkId = "partner_link_id"
        case exerciseId = "exercise_id"
        case userId1 = "user_id_1"
        case userId2 = "user_id_2"
        case user1Rating = "user_1_rating"
        case user2Rating = "user_2_rating"
        case user1Notes = "user_1_notes"
        case user2Notes = "user_2_notes"
        case user1ProgressPercent = "user_1_progress_percent"
        case user2ProgressPercent = "user_2_progress_percent"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case lastActivityAt = "last_activity_at"
    }
}

/// Status of an exercise session
enum SessionStatus: String, Codable {
    case pending = "pending"
    case inProgress = "in_progress"
    case paused = "paused"
    case completed = "completed"
    case abandoned = "abandoned"
}

// MARK: - Appreciation Message Models

/// A message sent from one partner to another
struct AppreciationMessage: Codable, Identifiable {
    let id: UUID
    let partnerLinkId: UUID
    let fromUserId: UUID
    let toUserId: UUID
    let message: String
    let readAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, message, createdAt
        case partnerLinkId = "partner_link_id"
        case fromUserId = "from_user_id"
        case toUserId = "to_user_id"
        case readAt = "read_at"
    }
}

// MARK: - API Response Models

/// Response from POST /partner-links/invite
struct InviteCodeResponse: Codable {
    let inviteCode: String
    let expiresAt: Date
    let deepLink: String
    let webLink: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case inviteCode = "inviteCode"
        case expiresAt = "expiresAt"
        case deepLink = "deepLink"
        case webLink = "webLink"
        case message
    }
}

/// Response from POST /partner-links/accept
struct AcceptPartnerInviteResponse: Codable {
    let partnerLinkId: UUID
    let partnerId: UUID
    let partnerName: String
    let status: PartnerLinkStatus
    let activatedAt: Date
    let message: String

    enum CodingKeys: String, CodingKey {
        case partnerLinkId = "partnerLinkId"
        case partnerId = "partnerId"
        case partnerName = "partnerName"
        case status
        case activatedAt = "activatedAt"
        case message
    }
}

/// Response from GET /partners/mood-summary
struct PartnerMoodSummary: Codable {
    struct MoodEntry: Codable {
        let date: String
        let mood: String
        let timestamp: Date
    }

    let partnerId: UUID
    let partnerName: String
    let moods: [MoodEntry]
    let lastUpdate: String
    let sharingEnabled: Bool
}

/// Response from GET /couples-exercises
struct ExercisesListResponse: Codable {
    let exercises: [CouplesExercise]
    let totalAvailable: Int
    let free: Int
    let premium: Int
    let hasPartnerPremium: Bool
}

/// Response from POST /couples-exercise-sessions
struct StartSessionResponse: Codable {
    let sessionId: UUID
    let exerciseId: UUID
    let exerciseName: String
    let status: SessionStatus
    let invitedPartnerId: UUID?
    let invitedPartnerName: String?
    let expiresAt: Date
    let message: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "sessionId"
        case exerciseId = "exerciseId"
        case exerciseName = "exerciseName"
        case status
        case invitedPartnerId = "invitedPartnerId"
        case invitedPartnerName = "invitedPartnerName"
        case expiresAt = "expiresAt"
        case message
    }
}

/// Response from PATCH /couples-exercise-sessions/{id}
struct UpdateSessionResponse: Codable {
    let sessionId: UUID
    let status: SessionStatus
    let user1Rating: Int?
    let user2Rating: Int?
    let completedAt: Date?
    let message: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "sessionId"
        case status
        case user1Rating = "user1Rating"
        case user2Rating = "user2Rating"
        case completedAt = "completedAt"
        case message
    }
}

// MARK: - Error Types

/// Errors specific to couples mode
enum CouplesModeError: LocalizedError, Identifiable {
    case alreadyPartnered
    case selfInvite
    case inviteExpired
    case inviteInvalid
    case inviteAlreadyUsed
    case quotaExceeded(retryAfterSeconds: Int)
    case notPartnered
    case partnerNotSharing
    case exercisePremiumOnly
    case invalidStateTransition
    case sessionExpired
    case alreadyCompleted
    case textTooShort
    case textTooLong(currentLength: Int, maxLength: Int)
    case permissionDenied
    case notFound
    case alreadyEnded
    case rateLimited(retryAfterSeconds: Int)
    case internalError

    var id: String {
        String(describing: self)
    }

    var errorDescription: String? {
        switch self {
        case .alreadyPartnered:
            return "You already have an active partner. Unlink first."
        case .selfInvite:
            return "You cannot partner with yourself."
        case .inviteExpired:
            return "This invite code has expired. Ask your partner for a new one."
        case .inviteInvalid:
            return "Invalid invite code. Please check and try again."
        case .inviteAlreadyUsed:
            return "This invite has already been accepted."
        case .quotaExceeded(let seconds):
            let hours = seconds / 3600
            return "You've reached your invite limit. Try again in \(hours) hour(s)."
        case .notPartnered:
            return "You must have an active partner to access this feature."
        case .partnerNotSharing:
            return "Your partner has not shared this data with you."
        case .exercisePremiumOnly:
            return "Upgrade to Premium to unlock this exercise."
        case .invalidStateTransition:
            return "Cannot perform this action in the current state."
        case .sessionExpired:
            return "This session expired. Start a new exercise together."
        case .alreadyCompleted:
            return "You already rated this session."
        case .textTooShort:
            return "Message must be at least 10 characters."
        case .textTooLong(let current, let max):
            return "Message must be under \(max) characters. Current: \(current)."
        case .permissionDenied:
            return "You don't have permission to perform this action."
        case .notFound:
            return "Resource not found."
        case .alreadyEnded:
            return "This partnership has already ended."
        case .rateLimited(let seconds):
            return "Too many attempts. Please try again in \(seconds) seconds."
        case .internalError:
            return "An error occurred. Please try again."
        }
    }

    var failureReason: String? {
        errorDescription
    }

    var recoverySuggestion: String? {
        switch self {
        case .alreadyPartnered:
            return "End your current partnership first."
        case .selfInvite:
            return "Enter your partner's user ID or invite code."
        case .inviteExpired:
            return "Ask your partner to generate a new invite code."
        case .inviteInvalid, .inviteAlreadyUsed:
            return "Double-check the invite code and try again."
        case .quotaExceeded:
            return "You can generate new invites after the wait time."
        case .notPartnered:
            return "Create a partnership first by sharing an invite code."
        case .partnerNotSharing:
            return "Ask your partner to enable sharing for this data type."
        case .exercisePremiumOnly:
            return "Consider upgrading to Premium or ask your partner if they have Premium."
        case .invalidStateTransition, .sessionExpired:
            return "Start a new exercise session."
        case .alreadyCompleted:
            return "You've already rated this exercise."
        case .textTooShort, .textTooLong:
            return "Adjust your message length and try again."
        case .permissionDenied:
            return "Check your partnerships and permissions."
        case .notFound:
            return "Refresh and try again."
        case .alreadyEnded:
            return "Create a new partnership."
        case .rateLimited:
            return "Wait a moment and try again."
        case .internalError:
            return "Please try again later."
        }
    }
}

// MARK: - View Models (Request/Update Models)

/// Request to update an exercise session
struct UpdateSessionRequest: Codable {
    enum SessionAction: String, Codable {
        case join = "join"
        case rate = "rate"
        case notes = "notes"
        case abandon = "abandon"
    }

    let action: SessionAction
    let rating: Int?
    let notes: String?
}

/// Request to send an appreciation message
struct SendAppreciationRequest: Codable {
    let message: String
}

// MARK: - Partner Mode View Models

/// Sharing settings for Partner Mode
struct SharingSettings: Equatable, Codable {
    var shareMood: Bool
    var shareExercises: Bool
}

/// Partner info for dashboard display
struct PartnerInfo: Equatable {
    let partnerId: UUID
    let partnerName: String
    let partnerStreak: Int
    let hasCompletedToday: Bool
    let lastActive: Date
    let isSharingMood: Bool
    let isSharingExercises: Bool
}

/// State of partner mode view
enum PartnerState: Equatable {
    case loading
    case noPartner
    case pendingInvite(code: String, expiresAt: Date)
    case hasPartner(PartnerInfo)
}

// MARK: - PartnerLink Extensions

extension PartnerLink {
    /// Returns current user's sharing settings
    func mySharingSettings(for userId: UUID) -> SharingSettings {
        if userId == userId1 {
            return SharingSettings(shareMood: user1ShareMood, shareExercises: user1ShareExercises)
        } else {
            return SharingSettings(shareMood: user2ShareMood, shareExercises: user2ShareExercises)
        }
    }

    /// Returns partner's sharing settings (what they share with me)
    func partnerSharingSettings(for userId: UUID) -> SharingSettings {
        if userId == userId1 {
            return SharingSettings(shareMood: user2ShareMood, shareExercises: user2ShareExercises)
        } else {
            return SharingSettings(shareMood: user1ShareMood, shareExercises: user1ShareExercises)
        }
    }

    /// Returns partner's user ID
    func partnerId(for userId: UUID) -> UUID? {
        if userId == userId1 { return userId2 }
        if userId == userId2 { return userId1 }
        return nil
    }
}
