import Foundation
import Supabase

/// Service for managing therapy integration features
/// Handles connections, sharing settings, assignments, and audit logs
@MainActor
final class TherapyIntegrationService: ObservableObject {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Connection Management

    /// Invite a therapist by email
    func inviteTherapist(email: String) async throws -> UUID {
        let request = InviteTherapistRequest(therapistEmail: email)

        let response: InviteTherapistResponse = try await supabase.functions
            .invoke("therapist-invite", options: FunctionInvokeOptions(body: request))

        if let error = response.error {
            throw TherapyError.invitationFailed(error)
        }

        guard let invitationId = response.invitationId else {
            throw TherapyError.invitationFailed("No invitation ID returned")
        }

        return invitationId
    }

    /// Get all therapy connections for the current user
    func getConnections() async throws -> [TherapyConnection] {
        let connections: [TherapyConnection] = try await supabase
            .from("therapy_connections")
            .select("""
                *,
                therapist_accounts!inner(*)
            """)
            .order("created_at", ascending: false)
            .execute()
            .value

        return connections
    }

    /// Get a specific connection by ID
    func getConnection(id: UUID) async throws -> TherapyConnection {
        let connection: TherapyConnection = try await supabase
            .from("therapy_connections")
            .select("""
                *,
                therapist_accounts!inner(*)
            """)
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value

        return connection
    }

    /// Revoke (disconnect) a therapy connection
    func revokeConnection(connectionId: UUID) async throws {
        try await supabase
            .from("therapy_connections")
            .update([
                "status": "revoked",
                "ended_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: connectionId.uuidString)
            .execute()
    }

    // MARK: - Sharing Settings

    /// Update sharing permissions for a connection
    func updateSharingSettings(
        connectionId: UUID,
        shareMood: Bool? = nil,
        shareJournal: Bool? = nil,
        shareAssessments: Bool? = nil,
        shareExercises: Bool? = nil,
        crisisAlerts: Bool? = nil
    ) async throws {
        var updates: [String: Any] = [:]

        if let shareMood = shareMood {
            updates["share_mood"] = shareMood
        }
        if let shareJournal = shareJournal {
            updates["share_journal"] = shareJournal
        }
        if let shareAssessments = shareAssessments {
            updates["share_assessments"] = shareAssessments
        }
        if let shareExercises = shareExercises {
            updates["share_exercises"] = shareExercises
        }
        if let crisisAlerts = crisisAlerts {
            updates["crisis_alerts_enabled"] = crisisAlerts
        }

        try await supabase
            .from("therapy_connections")
            .update(updates)
            .eq("id", value: connectionId.uuidString)
            .execute()
    }

    // MARK: - Assignments

    /// Get all assignments for a connection
    func getAssignments(connectionId: UUID? = nil) async throws -> [TherapistAssignment] {
        var query = supabase
            .from("therapist_assignments")
            .select("*")
            .order("created_at", ascending: false)

        if let connectionId = connectionId {
            query = query.eq("connection_id", value: connectionId.uuidString)
        }

        let assignments: [TherapistAssignment] = try await query
            .execute()
            .value

        return assignments
    }

    /// Complete an assignment
    func completeAssignment(id: UUID, notes: String?) async throws {
        try await supabase
            .from("therapist_assignments")
            .update([
                "status": "completed",
                "completed_at": ISO8601DateFormatter().string(from: Date()),
                "client_notes": notes ?? NSNull()
            ])
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Skip an assignment
    func skipAssignment(id: UUID) async throws {
        try await supabase
            .from("therapist_assignments")
            .update([
                "status": "skipped"
            ])
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Audit Log

    /// Get access log for a connection
    func getAccessLog(connectionId: UUID, limit: Int = 100) async throws -> [TherapyAccessLog] {
        let logs: [TherapyAccessLog] = try await supabase
            .from("therapy_access_log")
            .select("*")
            .eq("connection_id", value: connectionId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return logs
    }
}

// MARK: - Error Types

enum TherapyError: LocalizedError {
    case invitationFailed(String)
    case connectionNotFound
    case unauthorized
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invitationFailed(let message):
            return "Failed to send invitation: \(message)"
        case .connectionNotFound:
            return "Therapy connection not found"
        case .unauthorized:
            return "You don't have permission to access this resource"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
