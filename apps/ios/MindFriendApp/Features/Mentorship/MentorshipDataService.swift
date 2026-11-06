import Foundation
import Supabase

// MARK: - Request/Update DTOs for Supabase Operations

private struct ProfileInsert: Encodable {
    let userId: UUID
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case timezone
    }
}

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

private struct MessageInsert: Encodable {
    let matchId: UUID
    let senderId: UUID
    let content: String
    enum CodingKeys: String, CodingKey {
        case matchId = "match_id"
        case senderId = "sender_id"
        case content
    }
}

private struct FindMentorMatchesBody: Encodable {
    let limit: Int
    let offset: Int
}

// Note: RequestMentorshipBody is already defined in MentorshipModels.swift

private struct EmptyBody: Encodable {}

/// Data access layer for mentorship operations
@MainActor
final class MentorshipDataService {
    private let supabase: SupabaseClient
    private let userIdProvider: @MainActor () -> UUID?
    private(set) var accountGeneration = 0
    var currentUserId: UUID? { userIdProvider() }

    init(supabase: SupabaseClient, userIdProvider: @escaping @MainActor () -> UUID?) {
        self.supabase = supabase
        self.userIdProvider = userIdProvider
    }

    func resetForAccountChange() { accountGeneration += 1 }

    private func perform<Value>(_ operation: (UUID) async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        guard let owner = userIdProvider() else { throw MentorshipError.notAuthenticated }
        let generation = accountGeneration
        do {
            let value = try await operation(owner)
            try Task.checkCancellation()
            guard generation == accountGeneration, userIdProvider() == owner else { throw CancellationError() }
            return value
        } catch {
            guard generation == accountGeneration, userIdProvider() == owner else { throw CancellationError() }
            throw error
        }
    }

    // MARK: - Profile Management

    func fetchOrCreateProfile() async throws -> MentorshipProfile {
        return try await perform { userId in
            if let profile = try await self.fetchProfile() {
                return profile
            }
            return try await self.createDefaultProfile()

        }
    }

    func fetchProfile() async throws -> MentorshipProfile? {
        return try await perform { userId in
            let profiles: [MentorshipProfile] = try await self.supabase
                .from("mentorship_profiles")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            return profiles.first

        }
    }

    func createDefaultProfile() async throws -> MentorshipProfile {
        return try await perform { userId in
            // Server defaults own verification, qualifications, aliases and timestamps.
            let profiles: [MentorshipProfile] = try await self.supabase
                .from("mentorship_profiles")
                .insert(ProfileInsert(userId: userId, timezone: TimeZone.current.identifier))
                .select()
                .execute()
                .value
            guard let profile = profiles.first, profile.userId == userId else {
                throw MentorshipError.notFound("The mentorship profile was not saved.")
            }
            return profile

        }
    }

    func updateProfile(
        isMentorAvailable: Bool? = nil,
        expertiseAreas: [String]? = nil,
        seekingAreas: [String]? = nil,
        bio: String? = nil,
        availabilityHoursWeek: Int? = nil,
        languages: [String]? = nil
    ) async throws -> MentorshipProfile {
        return try await perform { userId in
            let updates = ProfileUpdate(
                isMentorAvailable: isMentorAvailable,
                expertiseAreas: expertiseAreas,
                seekingAreas: seekingAreas,
                bio: bio,
                availabilityHoursWeek: availabilityHoursWeek,
                languages: languages
            )

            let updated: [MentorshipProfile] = try await self.supabase
                .from("mentorship_profiles")
                .update(updates)
                .eq("user_id", value: userId.uuidString)
                .select()
                .execute()
                .value
            guard let profile = updated.first, profile.userId == userId else {
                throw MentorshipError.notFound("The mentorship profile was not saved.")
            }
            return profile

        }
    }

    // MARK: - Mentor Matching

    func findMentorMatches(limit: Int = 5, offset: Int = 0) async throws -> FindMentorMatchesResponse {
        return try await perform { userId in
            let body = FindMentorMatchesBody(limit: limit, offset: offset)
            let response: FindMentorMatchesResponse = try await self.supabase.functions.invoke(
                "find-mentor-matches",
                options: .init(body: body)
            )
            return response

        }
    }

    func requestMentorship(mentorId: UUID, introductionMessage: String) async throws -> RequestMentorshipResponse {
        return try await perform { userId in
            let body = RequestMentorshipBody(mentorId: mentorId, introductionMessage: introductionMessage)
            let response: RequestMentorshipResponse = try await self.supabase.functions.invoke(
                "request-mentorship",
                options: .init(body: body)
            )
            return response

        }
    }

    // MARK: - Match Management

    func fetchMatches(role: MentorshipRole) async throws -> [MentorshipMatch] {
        return try await perform { userId in
            // Fetch all matches for the user (as mentor or mentee)
            let matches: [MentorshipMatch] = try await self.supabase
                .from("mentorship_matches")
                .select()
                .or("mentor_id.eq.\(userId.uuidString),mentee_id.eq.\(userId.uuidString)")
                .execute()
                .value
            return matches

        }
    }

    func fetchMatch(matchId: UUID) async throws -> MentorshipMatch {
        return try await perform { userId in
            let rows: [MentorshipMatch] = try await self.supabase.from("mentorship_matches")
                .select().eq("id", value: matchId.uuidString).execute().value
            guard let match = rows.first, match.mentorId == userId || match.menteeId == userId else {
                throw MentorshipError.notFound("The mentorship could not be loaded.")
            }
            return match

        }
    }

    func acceptMentorshipRequest(matchId: UUID) async throws -> MentorshipMatch {
        return try await perform { userId in
            let update = MatchStatusUpdate(status: "active")
            let updated: [MentorshipMatch] = try await self.supabase
                .from("mentorship_matches")
                .update(update)
                .eq("id", value: matchId.uuidString)
                .select()
                .execute()
                .value
            return updated.first ?? MentorshipMatch(id: matchId, mentorId: UUID(), menteeId: UUID(), status: .active, introductionMessage: "")

        }
    }

    func rejectMentorshipRequest(matchId: UUID) async throws {
        return try await perform { userId in
            _ = try await self.supabase
                .from("mentorship_matches")
                .delete()
                .eq("id", value: matchId.uuidString)
                .execute()

        }
    }

    func endMentorship(matchId: UUID, reason: String? = nil) async throws {
        return try await perform { userId in
            let update = MatchEndUpdate(
                status: "completed",
                endedAt: ISO8601DateFormatter().string(from: Date()),
                endReason: reason
            )
            _ = try await self.supabase
                .from("mentorship_matches")
                .update(update)
                .eq("id", value: matchId.uuidString)
                .execute()

        }
    }

    // MARK: - Messaging

    func sendMessage(matchId: UUID, content: String) async throws -> MentorshipMessage {
        try await perform { userId in
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, content.count <= 2000 else {
                throw MentorshipError.validationError("Enter a message of up to 2,000 characters.")
            }
            let rows: [MentorshipMessage] = try await self.supabase.from("mentorship_messages")
                .insert(MessageInsert(matchId: matchId, senderId: userId, content: content))
                .select().execute().value
            guard let saved = rows.first, saved.matchId == matchId, saved.senderId == userId else {
                throw MentorshipError.networkError("Your message was not confirmed. Please try again.")
            }
            return saved
        }
    }

    func fetchMessages(matchId: UUID, limit: Int = 50, offset: Int = 0) async throws -> [MentorshipMessage] {
        return try await perform { userId in
            let messages: [MentorshipMessage] = try await self.supabase
                .from("mentorship_messages")
                .select()
                .eq("match_id", value: matchId.uuidString)
                .order("created_at", ascending: true)
                .range(from: offset, to: offset + limit - 1)
                .execute()
                .value
            return messages

        }
    }

    func markMessagesAsRead(matchId: UUID) async throws {
        try await perform { _ in
            let confirmed: Bool = try await self.supabase.rpc("mark_messages_read", params: ["p_match_id": matchId.uuidString]).execute().value
            guard confirmed else { throw MentorshipError.networkError("Read receipts were not saved.") }
        }
    }

    func flagMessage(messageId: UUID, reason: String) async throws {
        try await perform { _ in
            let confirmed: Bool = try await self.supabase.rpc("flag_mentorship_message", params: ["p_message_id": messageId.uuidString, "p_reason": reason]).execute().value
            guard confirmed else { throw MentorshipError.networkError("The message flag was not saved.") }
        }
    }

    func deleteMessage(messageId: UUID) async throws {
        try await perform { _ in
            let confirmed: Bool = try await self.supabase.rpc("delete_mentorship_message", params: ["p_message_id": messageId.uuidString]).execute().value
            guard confirmed else { throw MentorshipError.networkError("The message was not deleted.") }
        }
    }

    // MARK: - Safety & Reporting

    func createReport(
        matchId: UUID,
        reportedUserId: UUID,
        reason: String,
        description: String? = nil,
        messageIds: [UUID]? = nil
    ) async throws -> MentorshipReport {
        return try await perform { userId in
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
            _ = try await self.supabase
                .from("mentorship_reports")
                .insert(report)
                .execute()
            return report

        }
    }

    func fetchReports(matchId: UUID) async throws -> [MentorshipReport] {
        return try await perform { userId in
            let reports: [MentorshipReport] = try await self.supabase
                .from("mentorship_reports")
                .select()
                .eq("match_id", value: matchId.uuidString)
                .execute()
                .value
            return reports

        }
    }

    func runSafetyCheck() async throws -> SafetyCheckResponse {
        return try await perform { userId in
            let body = EmptyBody()
            let response: SafetyCheckResponse = try await self.supabase.functions.invoke(
                "mentorship-safety-check",
                options: .init(body: body)
            )
            return response

        }
    }
}
