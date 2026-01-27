import Foundation
import Supabase

// FIXME: This is a stub implementation to allow the project to build
// The original MentorshipDataService.swift has compilation errors and was never functional
// See MentorshipDataService.swift.broken for the incomplete implementation

/// Stub data access layer for mentorship operations
actor MentorshipDataService {
    private let supabase: SupabaseClient
    private let userId: UUID

    init(supabase: SupabaseClient, userId: UUID) {
        self.supabase = supabase
        self.userId = userId
    }

    // MARK: - Profile Management

    func fetchOrCreateProfile() async throws -> MentorshipProfile {
        do {
            if let profile = try await fetchProfile() {
                return profile
            }
            return try await createDefaultProfile()
        } catch {
            return try await createDefaultProfile()
        }
    }

    func fetchProfile() async throws -> MentorshipProfile? {
        let profiles: [MentorshipProfile] = try await supabase
            .from("mentorship_profiles")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        return profiles.first
    }

    func createDefaultProfile() async throws -> MentorshipProfile {
        let profile = MentorshipProfile(
            userId: userId,
            isMentorAvailable: false,
            expertiseAreas: [],
            seekingAreas: [],
            bio: nil,
            availabilityHoursWeek: 0,
            languages: ["en"],
            timezone: TimeZone.current.identifier,
            isVerified: false,
            mentorAlias: nil
        )
        _ = try await supabase
            .from("mentorship_profiles")
            .insert(profile)
            .execute()
        return profile
    }

    func updateProfile(
        isMentorAvailable: Bool? = nil,
        expertiseAreas: [String]? = nil,
        seekingAreas: [String]? = nil,
        bio: String? = nil,
        availabilityHoursWeek: Int? = nil,
        languages: [String]? = nil
    ) async throws -> MentorshipProfile {
        var updates: [String: String] = [:]
        if let value = isMentorAvailable { updates["is_mentor_available"] = String(value) }
        if let value = expertiseAreas { updates["expertise_areas"] = value.joined(separator: ",") }
        if let value = seekingAreas { updates["seeking_areas"] = value.joined(separator: ",") }
        if let value = bio { updates["bio"] = value }
        if let value = availabilityHoursWeek { updates["availability_hours_week"] = String(value) }
        if let value = languages { updates["languages"] = value.joined(separator: ",") }

        let updated: [MentorshipProfile] = try await supabase
            .from("mentorship_profiles")
            .update(updates)
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        return updated.first ?? MentorshipProfile(userId: userId, isMentorAvailable: false, expertiseAreas: [], seekingAreas: [], bio: nil, availabilityHoursWeek: 0, languages: ["en"], timezone: TimeZone.current.identifier, isVerified: false, mentorAlias: nil)
    }

    // MARK: - Mentor Matching

    func findMentorMatches(limit: Int = 5, offset: Int = 0) async throws -> FindMentorMatchesResponse {
        struct RequestBody: Encodable {
            let limit: Int
            let offset: Int
        }
        let response = try await supabase.functions.invoke(
            "find-mentor-matches",
            options: FunctionInvokeOptions(body: RequestBody(limit: limit, offset: offset))
        )
        let decoded = try JSONDecoder().decode(FindMentorMatchesResponse.self, from: response.data)
        return decoded
    }

    func requestMentorship(mentorId: UUID, introductionMessage: String) async throws -> RequestMentorshipResponse {
        struct RequestBody: Encodable {
            let mentorId: String
            let message: String
        }
        let response = try await supabase.functions.invoke(
            "request-mentorship",
            options: FunctionInvokeOptions(body: RequestBody(mentorId: mentorId.uuidString, message: introductionMessage))
        )
        let decoded = try JSONDecoder().decode(RequestMentorshipResponse.self, from: response.data)
        return decoded
    }

    // MARK: - Match Management

    func fetchMatches(role: MentorshipRole) async throws -> [MentorshipMatch] {
        let roleStr = role == .mentor ? "mentor" : (role == .mentee ? "mentee" : "both")
        let matches: [MentorshipMatch] = try await supabase
            .from("mentorship_matches")
            .select()
            .in("role", values: [roleStr])
            .execute()
            .value
        return matches
    }

    func acceptMentorshipRequest(matchId: UUID) async throws -> MentorshipMatch {
        let updated: [MentorshipMatch] = try await supabase
            .from("mentorship_matches")
            .update(["status": "active"])
            .eq("id", value: matchId.uuidString)
            .execute()
            .value
        return updated.first ?? MentorshipMatch(id: matchId, mentorId: UUID(), menteeId: UUID(), status: .active, introductionMessage: "")
    }

    func rejectMentorshipRequest(matchId: UUID) async throws {
        _ = try await supabase
            .from("mentorship_matches")
            .delete()
            .eq("id", value: matchId.uuidString)
            .execute()
    }

    func endMentorship(matchId: UUID, reason: String? = nil) async throws {
        var updates: [String: String] = ["status": "completed", "ended_at": ISO8601DateFormatter().string(from: Date())]
        if let reason = reason { updates["end_reason"] = reason }
        _ = try await supabase
            .from("mentorship_matches")
            .update(updates)
            .eq("id", value: matchId.uuidString)
            .execute()
    }

    // MARK: - Messaging

    func sendMessage(matchId: UUID, content: String) async throws -> MentorshipMessage {
        let message = MentorshipMessage(
            id: UUID(),
            matchId: matchId,
            senderId: userId,
            content: content,
            isFlagged: false,
            flaggedAt: nil
        )
        _ = try await supabase
            .from("mentorship_messages")
            .insert(message)
            .execute()
        return message
    }

    func fetchMessages(matchId: UUID, limit: Int = 50, offset: Int = 0) async throws -> [MentorshipMessage] {
        let messages: [MentorshipMessage] = try await supabase
            .from("mentorship_messages")
            .select()
            .eq("match_id", value: matchId.uuidString)
            .order("created_at", ascending: true)
            .range(from: offset, to: offset + limit - 1)
            .execute()
            .value
        return messages
    }

    func markMessagesAsRead(matchId: UUID) async throws {
        _ = try await supabase
            .from("mentorship_messages")
            .update(["is_read": "true"])
            .eq("match_id", value: matchId.uuidString)
            .execute()
    }

    func flagMessage(messageId: UUID, reason: String) async throws {
        _ = try await supabase
            .from("mentorship_messages")
            .update(["is_flagged": "true", "flagged_at": ISO8601DateFormatter().string(from: Date()), "flag_reason": reason])
            .eq("id", value: messageId.uuidString)
            .execute()
    }

    // MARK: - Safety & Reporting

    func createReport(
        matchId: UUID,
        reportedUserId: UUID,
        reason: String,
        description: String? = nil,
        messageIds: [UUID]? = nil
    ) async throws -> MentorshipReport {
        let report = MentorshipReport(
            id: UUID(),
            matchId: matchId,
            reporterId: userId,
            reportedUserId: reportedUserId,
            reason: reason,
            description: description,
            messageIds: messageIds,
            createdAt: Date(),
            status: .pending
        )
        _ = try await supabase
            .from("mentorship_reports")
            .insert(report)
            .execute()
        return report
    }

    func fetchReports(matchId: UUID) async throws -> [MentorshipReport] {
        let reports: [MentorshipReport] = try await supabase
            .from("mentorship_reports")
            .select()
            .eq("match_id", value: matchId.uuidString)
            .execute()
            .value
        return reports
    }

    func runSafetyCheck() async throws -> SafetyCheckResponse {
        struct EmptyBody: Encodable {}
        let response = try await supabase.functions.invoke(
            "mentorship-safety-check",
            options: FunctionInvokeOptions(body: EmptyBody())
        )
        let decoded = try JSONDecoder().decode(SafetyCheckResponse.self, from: response.data)
        return decoded
    }
}
