import Foundation
import Supabase

/// Service for mentorship matching features
@MainActor
final class MentorshipService: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var profile: DBMentorshipProfile?
    @Published private(set) var matches: [DBMentorshipMatch] = []
    @Published private(set) var currentMessages: [DBMentorshipMessage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    // MARK: - Private Properties

    private let supabase: SupabaseClient
    private var messageChannel: RealtimeChannelV2?
    private var subscriptionTask: Task<Void, Never>?

    // MARK: - Initialization

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    deinit {
        // Cancel subscription task first
        subscriptionTask?.cancel()
        subscriptionTask = nil

        // Capture channel reference before deinit completes
        let channel = messageChannel
        messageChannel = nil

        // Unsubscribe in detached task to avoid actor isolation issues
        if let channel = channel {
            Task.detached {
                await channel.unsubscribe()
            }
        }
    }

    /// Cleanup method for explicit teardown (preferred over relying on deinit)
    func cleanup() async {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        await messageChannel?.unsubscribe()
        messageChannel = nil
        currentMessages = []
    }

    // MARK: - Timeout Helper

    /// Wrap an async operation with a timeout using structured concurrency
    private func withTimeout<T>(
        seconds: UInt64,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            // Main operation task
            group.addTask {
                try await operation()
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw MentorshipError.networkError(NSError(
                    domain: "Timeout",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Operation timed out"]
                ))
            }

            // Wait for first result (whichever completes first)
            guard let result = try await group.next() else {
                throw MentorshipError.networkError(NSError(domain: "Unknown", code: -1))
            }

            // Cancel remaining tasks
            group.cancelAll()

            return result
        }
    }

    // MARK: - Profile Management

    /// Fetch the current user's mentorship profile
    func fetchProfile() async throws -> DBMentorshipProfile? {
        guard let userId = supabase.auth.currentUser?.id else { return nil }

        let response: [DBMentorshipProfile] = try await withTimeout(seconds: 5) { [self] in
            try await self.supabase
                .from("mentorship_profiles")
                .select()
                .eq("user_id", value: userId)
                .limit(1)
                .execute()
                .value
        }

        profile = response.first
        return profile
    }

    /// Update or create mentorship profile
    func upsertProfile(
        isMentorAvailable: Bool? = nil,
        expertiseAreas: [String]? = nil,
        seekingAreas: [String]? = nil,
        bio: String? = nil,
        availabilityHoursWeek: Int? = nil,
        languages: [String]? = nil,
        timezone: String? = nil,
        mentorshipStyle: DBMentorshipProfile.MentorshipStyle? = nil
    ) async throws -> UUID {
        let response: UUID = try await withTimeout(seconds: 8) { [self] in
            try await self.supabase.rpc(
                "upsert_mentorship_profile",
                params: [
                    "p_is_mentor_available": AnyEncodable(isMentorAvailable),
                    "p_expertise_areas": AnyEncodable(expertiseAreas),
                    "p_seeking_areas": AnyEncodable(seekingAreas),
                    "p_bio": AnyEncodable(bio),
                    "p_availability_hours_week": AnyEncodable(availabilityHoursWeek),
                    "p_languages": AnyEncodable(languages),
                    "p_timezone": AnyEncodable(timezone),
                    "p_mentorship_style": AnyEncodable(mentorshipStyle?.rawValue),
                ]
            )
            .execute()
            .value
        }

        // Refresh profile
        _ = try await fetchProfile()
        return response
    }

    /// Toggle mentor availability
    func toggleMentorAvailability(_ isAvailable: Bool) async throws {
        _ = try await upsertProfile(isMentorAvailable: isAvailable)
    }

    // MARK: - Mentor Matching

    /// Find compatible mentors based on seeking areas
    func findMentorMatches(seekingAreas: [String], limit: Int = 5) async throws -> [MentorMatchResult] {
        isLoading = true
        defer { isLoading = false }

        let request = FindMentorMatchesRequest(
            seekingAreas: seekingAreas,
            limit: limit
        )

        let response: FindMentorMatchesResponse = try await withTimeout(seconds: 10) { [self] in
            try await self.supabase.functions.invoke(
                "find-mentor-matches",
                options: .init(body: request)
            )
        }

        return response.matches
    }

    /// Request mentorship from a specific mentor
    func requestMentorship(mentorId: UUID, introductionMessage: String) async throws -> RequestMentorshipResponse {
        isLoading = true
        defer { isLoading = false }

        let request = RequestMentorshipRequest(
            mentorId: mentorId.uuidString,
            introductionMessage: introductionMessage
        )

        let response: RequestMentorshipResponse = try await withTimeout(seconds: 12) { [self] in
            try await self.supabase.functions.invoke(
                "request-mentorship",
                options: .init(body: request)
            )
        }

        // Refresh matches
        _ = try await fetchMatches()

        return response
    }

    // MARK: - Match Management

    /// Fetch user's mentorship matches
    func fetchMatches() async throws -> [DBMentorshipMatch] {
        let response: [DBMentorshipMatch] = try await withTimeout(seconds: 5) { [self] in
            try await self.supabase
                .rpc("get_my_mentorship_matches")
                .execute()
                .value
        }

        matches = response
        return response
    }

    /// Accept a mentorship request (for mentors)
    func acceptMatch(_ matchId: UUID, responseMessage: String? = nil) async throws {
        let _: Bool = try await withTimeout(seconds: 8) { [self] in
            try await self.supabase
                .rpc("respond_to_mentorship_request", params: [
                    "p_match_id": AnyEncodable(matchId.uuidString),
                    "p_accept": AnyEncodable(true),
                    "p_response_message": AnyEncodable(responseMessage),
                ])
                .execute()
                .value
        }

        _ = try await fetchMatches()
    }

    /// Decline a mentorship request (for mentors)
    func declineMatch(_ matchId: UUID, responseMessage: String? = nil) async throws {
        let _: Bool = try await withTimeout(seconds: 8) { [self] in
            try await self.supabase
                .rpc("respond_to_mentorship_request", params: [
                    "p_match_id": AnyEncodable(matchId.uuidString),
                    "p_accept": AnyEncodable(false),
                    "p_response_message": AnyEncodable(responseMessage),
                ])
                .execute()
                .value
        }

        _ = try await fetchMatches()
    }

    /// End a mentorship
    func endMentorship(_ matchId: UUID, reason: String = "completed") async throws {
        let _: Bool = try await withTimeout(seconds: 8) { [self] in
            try await self.supabase
                .rpc("end_mentorship", params: [
                    "p_match_id": AnyEncodable(matchId.uuidString),
                    "p_reason": AnyEncodable(reason),
                ])
                .execute()
                .value
        }

        _ = try await fetchMatches()
    }

    // MARK: - Messaging

    /// Fetch messages for a match
    func fetchMessages(matchId: UUID) async throws -> [DBMentorshipMessage] {
        let response: [DBMentorshipMessage] = try await withTimeout(seconds: 5) { [self] in
            try await self.supabase
                .from("mentorship_messages")
                .select()
                .eq("match_id", value: matchId)
                .order("sent_at", ascending: true)
                .execute()
                .value
        }

        currentMessages = response
        return response
    }

    /// Send a message in a mentorship (uses secure RPC with rate limiting)
    func sendMessage(matchId: UUID, content: String) async throws {
        guard supabase.auth.currentUser != nil else {
            throw MentorshipError.notAuthenticated
        }

        // Validate content client-side
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw MentorshipError.invalidMessage("Message cannot be empty")
        }

        guard trimmedContent.count <= 2000 else {
            throw MentorshipError.invalidMessage("Message too long (max 2000 characters)")
        }

        // Use secure RPC function with rate limiting and timeout
        do {
            let result: UUID = try await withTimeout(seconds: 8) { [self] in
                try await self.supabase.rpc(
                    "send_mentorship_message",
                    params: [
                        "p_match_id": AnyEncodable(matchId.uuidString),
                        "p_content": AnyEncodable(trimmedContent)
                    ]
                )
                .execute()
                .value as UUID
            }
            
            _ = result
        } catch {
            // Handle specific errors
            if let errorMessage = (error as NSError).userInfo["message"] as? String {
                if errorMessage.contains("Rate limit") {
                    throw MentorshipError.rateLimited
                } else if errorMessage.contains("not active") {
                    throw MentorshipError.matchNotFound
                }
            }
            throw MentorshipError.networkError(error)
        }
    }

    /// Subscribe to realtime messages for a match
    func subscribeToMessages(matchId: UUID) async {
        subscriptionTask?.cancel()
        
        // Wait for old subscription to fully unsubscribe before starting new one
        if let oldChannel = messageChannel {
            await oldChannel.unsubscribe()
        }

        let channel = supabase.realtimeV2.channel("mentorship:\(matchId)")

        let insertions = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "mentorship_messages",
            filter: "match_id=eq.\(matchId)"
        )

        await channel.subscribe()

        subscriptionTask = Task {
            for await insertion in insertions {
                if Task.isCancelled { break }

                if let message = try? insertion.decodeRecord(as: DBMentorshipMessage.self, decoder: JSONDecoder()) {
                    await MainActor.run {
                        if !Task.isCancelled {
                            self.currentMessages.append(message)
                        }
                    }
                }
            }
        }

        messageChannel = channel
    }

    /// Unsubscribe from messages
    func unsubscribeFromMessages() async {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        
        // Ensure subscription is fully unsubscribed before clearing
        if let channel = messageChannel {
            await channel.unsubscribe()
        }
        messageChannel = nil
        currentMessages = []
    }

    /// Mark messages as read
    func markMessagesAsRead(matchId: UUID) async throws {
        guard let userId = supabase.auth.currentUser?.id else { return }

        try await withTimeout(seconds: 5) { [self] in
            try await self.supabase
                .from("mentorship_messages")
                .update(["read_at": Date().ISO8601Format()])
                .eq("match_id", value: matchId)
                .neq("sender_id", value: userId)
                .is("read_at", value: nil)
                .execute()
        }
    }

    // MARK: - Reporting

    /// Report an issue with a mentorship
    func reportIssue(
        matchId: UUID,
        reportedUserId: UUID,
        reason: DBMentorshipReport.ReportReason,
        description: String?,
        messageIds: [UUID] = []
    ) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw MentorshipError.notAuthenticated
        }

        let report = MentorshipReportInsert(
            reporterId: userId,
            reportedId: reportedUserId,
            matchId: matchId,
            reason: reason.rawValue,
            description: description,
            messageIds: messageIds.map { $0.uuidString }
        )

        try await withTimeout(seconds: 8) { [self] in
            try await self.supabase
                .from("mentorship_reports")
                .insert(report)
                .execute()
        }
    }
}

// MARK: - Insert Models

private struct MentorshipReportInsert: Encodable {
    let reporterId: UUID
    let reportedId: UUID
    let matchId: UUID
    let reason: String
    let description: String?
    let messageIds: [String]

    enum CodingKeys: String, CodingKey {
        case reporterId = "reporter_id"
        case reportedId = "reported_id"
        case matchId = "match_id"
        case reason
        case description
        case messageIds = "message_ids"
    }
}

// MARK: - Request Types

private struct FindMentorMatchesRequest: Encodable {
    let seekingAreas: [String]
    let limit: Int
}

private struct RequestMentorshipRequest: Encodable {
    let mentorId: String
    let introductionMessage: String
}

// MARK: - Errors

enum MentorshipError: LocalizedError {
    case notAuthenticated
    case matchNotFound
    case alreadyMatched
    case mentorUnavailable
    case rateLimited
    case invalidMessage(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to use mentorship features."
        case .matchNotFound:
            return "The mentorship match could not be found."
        case .alreadyMatched:
            return "You already have an active match with this mentor."
        case .mentorUnavailable:
            return "This mentor is not currently available."
        case .rateLimited:
            return "Too many messages. Please wait a moment before sending more."
        case .invalidMessage(let reason):
            return reason
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
