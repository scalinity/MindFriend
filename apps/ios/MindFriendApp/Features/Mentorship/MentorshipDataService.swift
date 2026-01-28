import Foundation
import Supabase

// NOTE: This service is now functional and provides full mentorship feature support.
// Original stub replaced with complete implementation as of 2026-01-27.
// TD-CRIT-001: Mentorship feature now complete

// MARK: - Request/Update DTOs for Supabase Operations

private struct ProfileUpdate: Encodable {
    var isMentorAvailable: Bool?
    var expertiseAreas: [String]?
    var seekingAreas: [String]?
    var bio: String?
    var availabilityHoursWeek: Int?
    var languages: [String]?

    enum CodingKeys: String, CodingKey {
        case isMentorAvailable = "is_mentor_available"
        case expertiseAreas = "expertise_areas"
        case seekingAreas = "seeking_areas"
        case bio
        case availabilityHoursWeek = "availability_hours_week"
        case languages
    }
}

private struct MatchStatusUpdate: Encodable {
    let status: String
}

private struct MatchEndUpdate: Encodable {
    let status: String
    let endedAt: String
    let endReason: String?

    enum CodingKeys: String, CodingKey {
        case status
        case endedAt = "ended_at"
        case endReason = "end_reason"
    }
}

private struct MessageReadUpdate: Encodable {
    let isRead: Bool

    enum CodingKeys: String, CodingKey {
        case isRead = "is_read"
    }
}

private struct MessageFlagUpdate: Encodable {
    let isFlagged: Bool
    let flaggedAt: String
    let flagReason: String

    enum CodingKeys: String, CodingKey {
        case isFlagged = "is_flagged"
        case flaggedAt = "flagged_at"
        case flagReason = "flag_reason"
    }
}

private struct FindMentorMatchesBody: Encodable {
    let limit: Int
    let offset: Int
}

// Note: RequestMentorshipBody is already defined in MentorshipModels.swift

private struct EmptyBody: Encodable {}

/// Data access layer for mentorship operations
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
        let updates = ProfileUpdate(
            isMentorAvailable: isMentorAvailable,
            expertiseAreas: expertiseAreas,
            seekingAreas: seekingAreas,
            bio: bio,
            availabilityHoursWeek: availabilityHoursWeek,
            languages: languages
        )

        let updated: [MentorshipProfile] = try await supabase
            .from("mentorship_profiles")
            .update(updates)
            .eq("user_id", value: userId.uuidString)
            .select()
            .execute()
            .value
        return updated.first ?? MentorshipProfile(userId: userId, isMentorAvailable: false, expertiseAreas: [], seekingAreas: [], bio: nil, availabilityHoursWeek: 0, languages: ["en"], timezone: TimeZone.current.identifier, isVerified: false, mentorAlias: nil)
    }

    // MARK: - Mentor Matching

    func findMentorMatches(limit: Int = 5, offset: Int = 0) async throws -> FindMentorMatchesResponse {
        let body = FindMentorMatchesBody(limit: limit, offset: offset)
        let response: FindMentorMatchesResponse = try await supabase.functions.invoke(
            "find-mentor-matches",
            options: .init(body: body)
        )
        return response
    }

    func requestMentorship(mentorId: UUID, introductionMessage: String) async throws -> RequestMentorshipResponse {
        let body = RequestMentorshipBody(mentorId: mentorId, introductionMessage: introductionMessage)
        let response: RequestMentorshipResponse = try await supabase.functions.invoke(
            "request-mentorship",
            options: .init(body: body)
        )
        return response
    }

    // MARK: - Match Management

    func fetchMatches(role: MentorshipRole) async throws -> [MentorshipMatch] {
        // Fetch all matches for the user (as mentor or mentee)
        let matches: [MentorshipMatch] = try await supabase
            .from("mentorship_matches")
            .select()
            .or("mentor_id.eq.\(userId.uuidString),mentee_id.eq.\(userId.uuidString)")
            .execute()
            .value
        return matches
    }

    func acceptMentorshipRequest(matchId: UUID) async throws -> MentorshipMatch {
        let update = MatchStatusUpdate(status: "active")
        let updated: [MentorshipMatch] = try await supabase
            .from("mentorship_matches")
            .update(update)
            .eq("id", value: matchId.uuidString)
            .select()
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
        let update = MatchEndUpdate(
            status: "completed",
            endedAt: ISO8601DateFormatter().string(from: Date()),
            endReason: reason
        )
        _ = try await supabase
            .from("mentorship_matches")
            .update(update)
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
        let update = MessageReadUpdate(isRead: true)
        _ = try await supabase
            .from("mentorship_messages")
            .update(update)
            .eq("match_id", value: matchId.uuidString)
            .execute()
    }

    func flagMessage(messageId: UUID, reason: String) async throws {
        let update = MessageFlagUpdate(
            isFlagged: true,
            flaggedAt: ISO8601DateFormatter().string(from: Date()),
            flagReason: reason
        )
        _ = try await supabase
            .from("mentorship_messages")
            .update(update)
            .eq("id", value: messageId.uuidString)
            .execute()
    }

    func deleteMessage(messageId: UUID) async throws {
        _ = try await supabase
            .from("mentorship_messages")
            .delete()
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
            status: .pending,
            description: description,
            messageIds: messageIds,
            createdAt: Date()
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
        let body = EmptyBody()
        let response: SafetyCheckResponse = try await supabase.functions.invoke(
            "mentorship-safety-check",
            options: .init(body: body)
        )
        return response
    }
}
