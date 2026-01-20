import Foundation

// MARK: - Therapy Connection Models

/// Represents a connection between a client and therapist
struct TherapyConnection: Codable, Identifiable, Equatable {
    let id: UUID
    let clientId: UUID
    let therapistId: UUID
    let status: ConnectionStatus
    let invitedBy: String

    // Sharing permissions (no shareChatSummary per decision doc)
    var shareMood: Bool
    var shareJournal: Bool
    var shareAssessments: Bool
    var shareExercises: Bool
    var crisisAlertsEnabled: Bool

    // Invitation flow
    let invitationToken: String?
    let invitationExpiresAt: Date?

    // Lifecycle dates
    let invitedAt: Date
    let connectedAt: Date?
    let endedAt: Date?
    let createdAt: Date

    // Joined data (loaded separately)
    var therapist: TherapistInfo?

    enum CodingKeys: String, CodingKey {
        case id, status
        case clientId = "client_id"
        case therapistId = "therapist_id"
        case invitedBy = "invited_by"
        case shareMood = "share_mood"
        case shareJournal = "share_journal"
        case shareAssessments = "share_assessments"
        case shareExercises = "share_exercises"
        case crisisAlertsEnabled = "crisis_alerts_enabled"
        case invitationToken = "invitation_token"
        case invitationExpiresAt = "invitation_expires_at"
        case invitedAt = "invited_at"
        case connectedAt = "connected_at"
        case endedAt = "ended_at"
        case createdAt = "created_at"
        case therapist = "therapist_accounts"
    }

    // Computed properties
    var isActive: Bool {
        status == .active
    }

    var isPending: Bool {
        status == .pending
    }

    var isRevoked: Bool {
        status == .revoked || status == .ended
    }

    var sharedDataTypes: [String] {
        var types: [String] = []
        if shareMood { types.append("Mood") }
        if shareJournal { types.append("Journal") }
        if shareAssessments { types.append("Assessments") }
        if shareExercises { types.append("Exercises") }
        return types
    }
}

/// Connection status enum
enum ConnectionStatus: String, Codable, CaseIterable {
    case pending
    case active
    case revoked
    case ended

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .active: return "Active"
        case .revoked: return "Revoked"
        case .ended: return "Ended"
        }
    }

    var color: String {
        switch self {
        case .pending: return "orange"
        case .active: return "green"
        case .revoked: return "red"
        case .ended: return "gray"
        }
    }
}

// MARK: - Therapist Models

/// Therapist account information
struct TherapistInfo: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let isVerified: Bool
    let licenseNumber: String?
    let licenseState: String?
    let licenseVerifiedAt: Date?
    let npiNumber: String?
    let practiceName: String?
    let practiceAddress: String?
    let specialties: [String]?
    let acceptsInvites: Bool
    let maxClients: Int
    let createdAt: Date

    // From profiles table (joined)
    var displayName: String?
    var email: String?
    var avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case isVerified = "is_verified"
        case licenseNumber = "license_number"
        case licenseState = "license_state"
        case licenseVerifiedAt = "license_verified_at"
        case npiNumber = "npi_number"
        case practiceName = "practice_name"
        case practiceAddress = "practice_address"
        case specialties
        case acceptsInvites = "accepts_invites"
        case maxClients = "max_clients"
        case createdAt = "created_at"
        case displayName = "display_name"
        case email
        case avatarUrl = "avatar_url"
    }

    var formattedSpecialties: String {
        specialties?.joined(separator: ", ") ?? "General"
    }

    var verificationBadge: String {
        isVerified ? "✓ Verified" : "Pending Verification"
    }
}

// MARK: - Assignment Models

/// Therapist assignment (homework/exercise)
struct TherapistAssignment: Codable, Identifiable, Equatable {
    let id: UUID
    let connectionId: UUID
    let title: String
    let description: String?
    let assignmentType: AssignmentType
    let exerciseId: UUID?
    let journalPrompt: String?
    let dueDate: Date?
    let frequency: AssignmentFrequency
    let status: AssignmentStatus
    let completedAt: Date?
    var clientNotes: String?
    let createdAt: Date

    // Joined data (loaded separately via query)
    var connection: TherapyConnection?

    enum CodingKeys: String, CodingKey {
        case id
        case connectionId = "connection_id"
        case title, description
        case assignmentType = "assignment_type"
        case exerciseId = "exercise_id"
        case journalPrompt = "journal_prompt"
        case dueDate = "due_date"
        case frequency, status
        case completedAt = "completed_at"
        case clientNotes = "client_notes"
        case createdAt = "created_at"
        case connection = "therapy_connections"
    }

    // Computed properties
    var isOverdue: Bool {
        guard let due = dueDate, status == .assigned else { return false }
        return due < Date()
    }

    var isCompleted: Bool {
        status == .completed
    }

    var canComplete: Bool {
        status == .assigned || status == .expired
    }

    var daysUntilDue: Int? {
        guard let due = dueDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: due).day
    }

    var statusColor: String {
        switch status {
        case .assigned: return isOverdue ? "red" : "blue"
        case .completed: return "green"
        case .skipped: return "orange"
        case .expired: return "gray"
        }
    }
}

/// Assignment type enum
enum AssignmentType: String, Codable, CaseIterable {
    case exercise
    case journalPrompt = "journal_prompt"
    case moodTracking = "mood_tracking"
    case custom

    var displayName: String {
        switch self {
        case .exercise: return "Exercise"
        case .journalPrompt: return "Journal Prompt"
        case .moodTracking: return "Mood Tracking"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .exercise: return "figure.mind.and.body"
        case .journalPrompt: return "book.pages"
        case .moodTracking: return "face.smiling"
        case .custom: return "checklist"
        }
    }
}

/// Assignment frequency enum
enum AssignmentFrequency: String, Codable, CaseIterable {
    case once
    case daily
    case weekly
    case biweekly
    case monthly

    var displayName: String {
        switch self {
        case .once: return "Once"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .biweekly: return "Biweekly"
        case .monthly: return "Monthly"
        }
    }
}

/// Assignment status enum
enum AssignmentStatus: String, Codable, CaseIterable {
    case assigned
    case completed
    case skipped
    case expired

    var displayName: String {
        switch self {
        case .assigned: return "Assigned"
        case .completed: return "Completed"
        case .skipped: return "Skipped"
        case .expired: return "Expired"
        }
    }
}

// MARK: - Audit Log Models

/// Audit log entry for therapist data access
struct TherapyAccessLog: Codable, Identifiable, Equatable {
    let id: UUID
    let connectionId: UUID
    let therapistId: UUID
    let action: String
    let resourceType: String?
    let resourceId: UUID?
    let ipAddress: String?
    let userAgent: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case connectionId = "connection_id"
        case therapistId = "therapist_id"
        case action
        case resourceType = "resource_type"
        case resourceId = "resource_id"
        case ipAddress = "ip_address"
        case userAgent = "user_agent"
        case createdAt = "created_at"
    }

    var formattedAction: String {
        switch action {
        case "view_mood": return "Viewed mood data"
        case "view_journal": return "Viewed journal entries"
        case "view_assessments": return "Viewed assessment results"
        case "view_exercises": return "Viewed exercise history"
        case "export_data": return "Exported client data"
        case "create_assignment": return "Created assignment"
        case "update_assignment": return "Updated assignment"
        case "crisis_alert_sent": return "Received crisis alert"
        case "connection_created": return "Connection established"
        case "connection_revoked": return "Connection revoked"
        case "permissions_changed": return "Sharing permissions changed"
        default: return action
        }
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}

// MARK: - Request/Response Models

/// Request body for inviting a therapist
struct InviteTherapistRequest: Codable {
    let therapistEmail: String
}

/// Response after sending therapist invitation
struct InviteTherapistResponse: Codable {
    let success: Bool
    let invitationId: UUID?
    let expiresAt: Date?
    let error: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case success
        case invitationId = "invitationId"
        case expiresAt
        case error, message
    }
}

/// Request body for updating sharing settings
struct UpdateSharingSettingsRequest: Codable {
    let shareMood: Bool?
    let shareJournal: Bool?
    let shareAssessments: Bool?
    let shareExercises: Bool?
    let crisisAlertsEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case shareMood = "share_mood"
        case shareJournal = "share_journal"
        case shareAssessments = "share_assessments"
        case shareExercises = "share_exercises"
        case crisisAlertsEnabled = "crisis_alerts_enabled"
    }
}

/// Request body for completing an assignment
struct CompleteAssignmentRequest: Codable {
    let notes: String?
    let completedAt: Date

    enum CodingKeys: String, CodingKey {
        case notes
        case completedAt = "completed_at"
    }
}

// MARK: - Helper Extensions

extension TherapyConnection {
    /// Create a sample connection for previews
    static var sample: TherapyConnection {
        TherapyConnection(
            id: UUID(),
            clientId: UUID(),
            therapistId: UUID(),
            status: .active,
            invitedBy: "client",
            shareMood: true,
            shareJournal: false,
            shareAssessments: true,
            shareExercises: false,
            crisisAlertsEnabled: true,
            invitationToken: nil,
            invitationExpiresAt: nil,
            invitedAt: Date(),
            connectedAt: Date(),
            endedAt: nil,
            createdAt: Date(),
            therapist: TherapistInfo.sample
        )
    }
}

extension TherapistInfo {
    /// Create a sample therapist for previews
    static var sample: TherapistInfo {
        TherapistInfo(
            id: UUID(),
            userId: UUID(),
            isVerified: true,
            licenseNumber: "PSY12345",
            licenseState: "CA",
            licenseVerifiedAt: Date(),
            npiNumber: "1234567890",
            practiceName: "Mindful Therapy Center",
            practiceAddress: "123 Main St, Suite 200",
            specialties: ["CBT", "Trauma", "Anxiety"],
            acceptsInvites: true,
            maxClients: 100,
            createdAt: Date(),
            displayName: "Dr. Sarah Johnson",
            email: "dr.johnson@mindfultherapy.com",
            avatarUrl: nil
        )
    }
}

extension TherapistAssignment {
    /// Create a sample assignment for previews
    static var sample: TherapistAssignment {
        let dueDate: Date? = Calendar.current.date(byAdding: .day, value: 7, to: Date())
        let exerciseId: UUID? = nil
        let completedAt: Date? = nil
        let clientNotes: String? = nil

        var assignment = TherapistAssignment(
            id: UUID(),
            connectionId: UUID(),
            title: "Daily Gratitude Journal",
            description: "Write 3 things you're grateful for each evening",
            assignmentType: AssignmentType.journalPrompt,
            exerciseId: exerciseId,
            journalPrompt: "What 3 things am I grateful for today?",
            dueDate: dueDate,
            frequency: AssignmentFrequency.daily,
            status: AssignmentStatus.assigned,
            completedAt: completedAt,
            clientNotes: clientNotes,
            createdAt: Date()
        )
        assignment.connection = TherapyConnection.sample
        return assignment
    }
}
