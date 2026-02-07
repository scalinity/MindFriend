import Foundation
import Supabase

/// Service for peer support features: listeners, sessions, mentorships, and gratitude
@MainActor
final class PeerSupportService: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var listenerProfile: DBListener?
    @Published private(set) var trainingProgress: [DBListenerTrainingProgress] = []
    @Published private(set) var activeSessions: [DBSupportSession] = []
    @Published private(set) var sessionHistory: [DBSupportSession] = []
    @Published private(set) var mentorships: [DBMentorship] = []
    @Published private(set) var receivedGratitude: [DBGratitudeAction] = []
    @Published private(set) var communityWisdom: [DBCommunityWisdom] = []
    @Published private(set) var anonymousRooms: [DBAnonymousRoom] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    // Realtime channels
    @Published private(set) var currentSessionMessages: [DBSupportMessage] = []

    // MARK: - Private Properties

    private let supabase: SupabaseClient
    private var sessionChannel: RealtimeChannelV2?
    private var subscriptionTask: Task<Void, Never>?

    // MARK: - Initialization

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    deinit {
        subscriptionTask?.cancel()
        Task { [sessionChannel] in
            await sessionChannel?.unsubscribe()
        }
    }

    // MARK: - Load All Data

    /// Load all peer support data for the hub view
    func loadData() async {
        isLoading = true
        error = nil

        async let listenerTask = fetchListenerProfile()
        async let sessionsTask = fetchActiveSessions()
        async let mentorshipsTask = fetchMentorships()
        async let gratitudeTask = fetchReceivedGratitude()
        async let wisdomTask = fetchCommunityWisdom()
        async let roomsTask = fetchAnonymousRooms()

        do {
            listenerProfile = try await listenerTask
        } catch {
            Log.social.error("Failed to fetch listener profile", error: error)
        }

        do {
            activeSessions = try await sessionsTask
        } catch {
            Log.social.error("Failed to fetch active sessions", error: error)
        }

        do {
            mentorships = try await mentorshipsTask
        } catch {
            Log.social.error("Failed to fetch mentorships", error: error)
        }

        do {
            receivedGratitude = try await gratitudeTask
        } catch {
            Log.social.error("Failed to fetch gratitude", error: error)
        }

        do {
            communityWisdom = try await wisdomTask
        } catch {
            Log.social.error("Failed to fetch community wisdom", error: error)
        }

        do {
            anonymousRooms = try await roomsTask
        } catch {
            Log.social.error("Failed to fetch anonymous rooms", error: error)
        }

        isLoading = false
    }

    // MARK: - Listener Profile

    /// Fetch the current user's listener profile if they are a registered listener
    func fetchListenerProfile() async throws -> DBListener? {
        guard let userId = supabase.auth.currentUser?.id else { return nil }

        let response: [DBListener] = try await supabase
            .from("listeners")
            .select()
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value

        return response.first
    }

    /// Apply to become a peer listener
    func applyToBecomeListener(
        displayName: String?,
        bio: String?,
        specializations: [SupportTopic],
        languages: [String]
    ) async throws -> UUID {
        let response: UUID = try await supabase
            .rpc("apply_to_become_listener", params: [
                "p_display_name": PeerSupportAnyEncodable(displayName),
                "p_bio": PeerSupportAnyEncodable(bio),
                "p_specializations": PeerSupportAnyEncodable(specializations.map { $0.rawValue }),
                "p_languages": PeerSupportAnyEncodable(languages)
            ])
            .execute()
            .value

        // Refresh listener profile
        listenerProfile = try await fetchListenerProfile()
        return response
    }

    /// Start listener training
    func startListenerTraining() async throws {
        let _: Bool = try await supabase
            .rpc("start_listener_training")
            .execute()
            .value

        listenerProfile = try await fetchListenerProfile()
    }

    /// Complete a training module
    func completeTrainingModule(moduleId: String, score: Int) async throws {
        let _: Bool = try await supabase
            .rpc("complete_training_module", params: [
                "p_module_id": PeerSupportAnyEncodable(moduleId),
                "p_score": PeerSupportAnyEncodable(score)
            ])
            .execute()
            .value

        // Refresh training progress
        trainingProgress = try await fetchTrainingProgress()
    }

    /// Complete listener certification
    func completeListenerCertification(finalScore: Int) async throws -> Bool {
        let passed: Bool = try await supabase
            .rpc("complete_listener_certification", params: [
                "p_final_score": finalScore
            ])
            .execute()
            .value

        listenerProfile = try await fetchListenerProfile()
        return passed
    }

    /// Toggle listener availability
    func toggleListenerAvailability(isAvailable: Bool) async throws {
        let _: Bool = try await supabase
            .rpc("toggle_listener_availability", params: [
                "p_is_available": isAvailable
            ])
            .execute()
            .value

        listenerProfile = try await fetchListenerProfile()
    }

    /// Fetch training progress for current listener
    func fetchTrainingProgress() async throws -> [DBListenerTrainingProgress] {
        guard let listenerId = listenerProfile?.id else { return [] }

        let response: [DBListenerTrainingProgress] = try await supabase
            .from("listener_training_progress")
            .select()
            .eq("listener_id", value: listenerId)
            .order("started_at", ascending: true)
            .execute()
            .value

        return response
    }

    // MARK: - Support Sessions

    /// Fetch active support sessions (as seeker or listener)
    func fetchActiveSessions() async throws -> [DBSupportSession] {
        let response: [DBSupportSession] = try await supabase
            .rpc("get_my_active_sessions")
            .execute()
            .value

        return response
    }

    /// Fetch session history
    func fetchSessionHistory(limit: Int = 20) async throws -> [DBSupportSession] {
        guard let userId = supabase.auth.currentUser?.id else { return [] }

        let response: [DBSupportSession] = try await supabase
            .from("support_sessions")
            .select()
            .or("seeker_id.eq.\(userId),listener_id.eq.\(userId)")
            .in("status", values: ["completed", "cancelled", "escalated"])
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return response
    }

    /// Request a peer support session
    func requestSupport(
        sessionType: DBSupportSession.SessionType,
        topics: [SupportTopic],
        mood: Int?,
        notes: String?,
        isAnonymous: Bool
    ) async throws -> SupportMatchResponse {
        let request = SupportMatchRequest(
            sessionType: sessionType.rawValue,
            topicTags: topics.map { $0.rawValue },
            isAnonymous: isAnonymous,
            preferredLanguage: "en",
            preferredGender: nil,
            seekerMood: mood,
            seekerNotes: notes
        )

        let response: SupportMatchResponse = try await supabase.functions.invoke(
            "match-support-session",
            options: .init(body: request)
        )

        // Refresh active sessions
        activeSessions = try await fetchActiveSessions()

        return response
    }

    /// Start an active session (for listeners accepting a match)
    func startSession(sessionId: UUID) async throws {
        try await supabase
            .from("support_sessions")
            .update(["status": "active", "started_at": Date().ISO8601Format()])
            .eq("id", value: sessionId)
            .execute()

        activeSessions = try await fetchActiveSessions()
    }

    /// End a session
    func endSession(sessionId: UUID, moodAfter: Int?) async throws {
        var updates: [String: PeerSupportAnyEncodable] = [
            "status": PeerSupportAnyEncodable("completed"),
            "ended_at": PeerSupportAnyEncodable(Date().ISO8601Format())
        ]

        if let moodAfter = moodAfter {
            updates["seeker_mood_after"] = PeerSupportAnyEncodable(moodAfter)
        }

        try await supabase
            .from("support_sessions")
            .update(updates)
            .eq("id", value: sessionId)
            .execute()

        activeSessions = try await fetchActiveSessions()
    }

    /// Cancel a pending session
    func cancelSession(sessionId: UUID) async throws {
        try await supabase
            .from("support_sessions")
            .update(["status": "cancelled"])
            .eq("id", value: sessionId)
            .execute()

        activeSessions = try await fetchActiveSessions()
    }

    // MARK: - Session Messages

    /// Fetch messages for a session
    func fetchSessionMessages(sessionId: UUID) async throws -> [DBSupportMessage] {
        let response: [DBSupportMessage] = try await supabase
            .from("support_messages")
            .select()
            .eq("session_id", value: sessionId)
            .order("sent_at", ascending: true)
            .execute()
            .value

        return response
    }

    /// Send a message in a session
    func sendMessage(sessionId: UUID, content: String, senderType: DBSupportMessage.SenderType) async throws {
        let message: [String: PeerSupportAnyEncodable] = [
            "session_id": PeerSupportAnyEncodable(sessionId),
            "sender_type": PeerSupportAnyEncodable(senderType.rawValue),
            "content": PeerSupportAnyEncodable(content)
        ]

        try await supabase
            .from("support_messages")
            .insert(message)
            .execute()
    }

    /// Subscribe to realtime messages for a session
    func subscribeToSessionMessages(sessionId: UUID) async {
        // Cancel any existing subscription
        subscriptionTask?.cancel()
        await sessionChannel?.unsubscribe()

        let channel = supabase.realtimeV2.channel("session:\(sessionId)")

        let insertions = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "support_messages",
            filter: "session_id=eq.\(sessionId)"
        )

        try? await channel.subscribeWithError()

        // Store task so it can be cancelled
        subscriptionTask = Task {
            for await insertion in insertions {
                // Check for cancellation before processing
                if Task.isCancelled { break }

                if let message = try? insertion.decodeRecord(as: DBSupportMessage.self, decoder: JSONDecoder()) {
                    await MainActor.run {
                        // Check cancellation again before UI update
                        if !Task.isCancelled {
                            self.currentSessionMessages.append(message)
                        }
                    }
                }
            }
        }

        sessionChannel = channel
    }

    /// Unsubscribe from session messages
    func unsubscribeFromSessionMessages() async {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        await sessionChannel?.unsubscribe()
        sessionChannel = nil
        currentSessionMessages = []
    }

    // MARK: - Session Feedback

    /// Submit feedback for a session
    func submitSessionFeedback(
        sessionId: UUID,
        rating: Int,
        feltHeard: Bool?,
        feltSupported: Bool?,
        wouldRecommend: Bool?,
        feedbackText: String?
    ) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw PeerSupportError.notAuthenticated
        }

        // Validate rating is within acceptable range
        guard (1...5).contains(rating) else {
            throw PeerSupportError.invalidRating
        }

        let feedback: [String: PeerSupportAnyEncodable] = [
            "session_id": PeerSupportAnyEncodable(sessionId),
            "from_user_id": PeerSupportAnyEncodable(userId),
            "rating": PeerSupportAnyEncodable(rating),
            "felt_heard": PeerSupportAnyEncodable(feltHeard),
            "felt_supported": PeerSupportAnyEncodable(feltSupported),
            "would_recommend": PeerSupportAnyEncodable(wouldRecommend),
            "feedback_text": PeerSupportAnyEncodable(feedbackText)
        ]

        try await supabase
            .from("session_feedback")
            .insert(feedback)
            .execute()
    }

    // MARK: - Mentorships

    /// Fetch user's mentorships (as mentor or mentee)
    func fetchMentorships() async throws -> [DBMentorship] {
        let response: [DBMentorship] = try await supabase
            .rpc("get_my_mentorships")
            .execute()
            .value

        return response
    }

    /// Request a mentor
    func requestMentorship(mentorId: UUID, challenges: [SupportTopic]) async throws -> UUID {
        let response: UUID = try await supabase
            .rpc("request_mentorship", params: [
                "p_mentor_id": PeerSupportAnyEncodable(mentorId.uuidString),
                "p_challenges": PeerSupportAnyEncodable(challenges.map { $0.rawValue })
            ])
            .execute()
            .value

        mentorships = try await fetchMentorships()
        return response
    }

    /// Accept a mentorship request (for mentors)
    func acceptMentorship(mentorshipId: UUID) async throws {
        let _: Bool = try await supabase
            .rpc("accept_mentorship", params: [
                "p_mentorship_id": PeerSupportAnyEncodable(mentorshipId.uuidString)
            ])
            .execute()
            .value

        mentorships = try await fetchMentorships()
    }

    /// Update mentorship status
    func updateMentorshipStatus(mentorshipId: UUID, status: DBMentorship.MentorshipStatus) async throws {
        try await supabase
            .from("mentorships")
            .update(["status": status.rawValue])
            .eq("id", value: mentorshipId)
            .execute()

        mentorships = try await fetchMentorships()
    }

    /// Create a mentorship check-in
    func createMentorshipCheckin(
        mentorshipId: UUID,
        type: DBMentorshipCheckin.CheckinType,
        message: String?,
        mood: Int?,
        wins: [String]?,
        challenges: [String]?,
        goals: [String]?
    ) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw PeerSupportError.notAuthenticated
        }

        let checkin: [String: PeerSupportAnyEncodable] = [
            "mentorship_id": PeerSupportAnyEncodable(mentorshipId),
            "initiated_by": PeerSupportAnyEncodable(userId),
            "checkin_type": PeerSupportAnyEncodable(type.rawValue),
            "message": PeerSupportAnyEncodable(message),
            "mood_shared": PeerSupportAnyEncodable(mood),
            "wins_shared": PeerSupportAnyEncodable(wins),
            "challenges_shared": PeerSupportAnyEncodable(challenges),
            "goals_discussed": PeerSupportAnyEncodable(goals)
        ]

        try await supabase
            .from("mentorship_checkins")
            .insert(checkin)
            .execute()
    }

    /// Fetch check-ins for a mentorship
    func fetchMentorshipCheckins(mentorshipId: UUID) async throws -> [DBMentorshipCheckin] {
        let response: [DBMentorshipCheckin] = try await supabase
            .from("mentorship_checkins")
            .select()
            .eq("mentorship_id", value: mentorshipId)
            .order("created_at", ascending: false)
            .execute()
            .value

        return response
    }

    // MARK: - Gratitude

    /// Send a gratitude action
    func sendGratitude(
        toUserId: UUID?,
        actionType: DBGratitudeAction.ActionType,
        message: String,
        isPublic: Bool,
        sessionId: UUID?,
        mentorshipId: UUID?
    ) async throws -> UUID {
        let response: UUID = try await supabase
            .rpc("send_gratitude", params: [
                "p_to_user_id": PeerSupportAnyEncodable(toUserId?.uuidString ?? ""),
                "p_action_type": PeerSupportAnyEncodable(actionType.rawValue),
                "p_message": PeerSupportAnyEncodable(message),
                "p_is_public": PeerSupportAnyEncodable(isPublic),
                "p_session_id": PeerSupportAnyEncodable(sessionId?.uuidString ?? ""),
                "p_mentorship_id": PeerSupportAnyEncodable(mentorshipId?.uuidString ?? "")
            ])
            .execute()
            .value

        return response
    }

    /// Fetch received gratitude
    func fetchReceivedGratitude(limit: Int = 20) async throws -> [DBGratitudeAction] {
        guard let userId = supabase.auth.currentUser?.id else { return [] }

        let response: [DBGratitudeAction] = try await supabase
            .from("gratitude_actions")
            .select()
            .eq("to_user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return response
    }

    /// Fetch public gratitude feed
    func fetchPublicGratitude(limit: Int = 50) async throws -> [DBGratitudeAction] {
        let response: [DBGratitudeAction] = try await supabase
            .from("gratitude_actions")
            .select()
            .eq("is_public", value: true)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return response
    }

    // MARK: - Community Wisdom

    /// Fetch approved community wisdom
    func fetchCommunityWisdom(category: DBCommunityWisdom.WisdomCategory? = nil, limit: Int = 30) async throws -> [DBCommunityWisdom] {
        var query = supabase
            .from("community_wisdom")
            .select()
            .eq("status", value: "approved")

        if let category = category {
            query = query.eq("category", value: category.rawValue)
        }

        let response: [DBCommunityWisdom] = try await query
            .order("helpful_count", ascending: false)
            .limit(limit)
            .execute()
            .value

        return response
    }

    /// Submit community wisdom
    func submitWisdom(
        title: String,
        content: String,
        category: DBCommunityWisdom.WisdomCategory,
        tags: [String]?
    ) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw PeerSupportError.notAuthenticated
        }

        let wisdom: [String: PeerSupportAnyEncodable] = [
            "user_id": PeerSupportAnyEncodable(userId),
            "title": PeerSupportAnyEncodable(title),
            "content": PeerSupportAnyEncodable(content),
            "category": PeerSupportAnyEncodable(category.rawValue),
            "tags": PeerSupportAnyEncodable(tags)
        ]

        try await supabase
            .from("community_wisdom")
            .insert(wisdom)
            .execute()
    }

    /// Mark wisdom as helpful
    func markWisdomAsHelpful(wisdomId: UUID) async throws {
        // Increment the helpful count
        try await supabase.rpc("increment_wisdom_helpful", params: [
            "wisdom_id": wisdomId.uuidString
        ]).execute()
    }

    // MARK: - Anonymous Rooms

    /// Fetch available anonymous rooms
    func fetchAnonymousRooms() async throws -> [DBAnonymousRoom] {
        let response: [DBAnonymousRoom] = try await supabase
            .from("anonymous_rooms")
            .select()
            .eq("is_active", value: true)
            .execute()
            .value

        return response
    }

    /// Join an anonymous room
    func joinAnonymousRoom(roomId: UUID) async throws -> (participantId: UUID, anonymousName: String) {
        struct JoinResult: Decodable {
            let participantId: UUID
            let anonymousName: String

            enum CodingKeys: String, CodingKey {
                case participantId = "participant_id"
                case anonymousName = "anonymous_name"
            }
        }

        let response: [JoinResult] = try await supabase
            .rpc("join_anonymous_room", params: [
                "p_room_id": roomId.uuidString
            ])
            .execute()
            .value

        guard let result = response.first else {
            throw PeerSupportError.joinRoomFailed
        }

        return (result.participantId, result.anonymousName)
    }

    /// Leave an anonymous room
    func leaveAnonymousRoom(participantId: UUID) async throws {
        try await supabase
            .from("anonymous_room_participants")
            .update(["left_at": Date().ISO8601Format()])
            .eq("id", value: participantId)
            .execute()
    }

    // MARK: - Listener Stats

    /// Get listener statistics
    func getListenerStats() async throws -> ListenerStats? {
        struct StatsResult: Decodable {
            let listenerId: UUID
            let totalSessions: Int
            let totalHours: Double
            let averageRating: Double?
            let ratingCount: Int
            let isAvailable: Bool
            let specializations: [String]

            enum CodingKeys: String, CodingKey {
                case listenerId = "listener_id"
                case totalSessions = "total_sessions"
                case totalHours = "total_hours"
                case averageRating = "average_rating"
                case ratingCount = "rating_count"
                case isAvailable = "is_available"
                case specializations
            }
        }

        let response: [StatsResult] = try await supabase
            .rpc("get_listener_stats")
            .execute()
            .value

        guard let stats = response.first else { return nil }

        return ListenerStats(
            listenerId: stats.listenerId,
            totalSessions: stats.totalSessions,
            totalHours: stats.totalHours,
            averageRating: stats.averageRating,
            ratingCount: stats.ratingCount,
            isAvailable: stats.isAvailable,
            specializations: stats.specializations
        )
    }

    // MARK: - Find Potential Mentors

    /// Find users who could be mentors (90+ days, demonstrated progress)
    func findPotentialMentors(challenges: [SupportTopic], limit: Int = 10) async throws -> [MentorCandidate] {
        // This would be a more complex query in production
        // For now, return an empty array - implement RPC function if needed
        return []
    }
}

// MARK: - Supporting Types

struct MentorCandidate: Identifiable {
    let id: UUID
    let displayName: String?
    let daysOnPlatform: Int
    let sharedChallenges: [SupportTopic]
    let compatibilityScore: Double
}

enum PeerSupportError: LocalizedError {
    case notAuthenticated
    case sessionNotFound
    case joinRoomFailed
    case matchFailed(String)
    case invalidRating
    case invalidTopicSelection
    case rateLimit
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to use peer support features."
        case .sessionNotFound:
            return "The support session could not be found."
        case .joinRoomFailed:
            return "Failed to join the anonymous room."
        case .matchFailed(let reason):
            return "Failed to find a match: \(reason)"
        case .invalidRating:
            return "Rating must be between 1 and 5."
        case .invalidTopicSelection:
            return "Please select at least one topic."
        case .rateLimit:
            return "You're sending requests too quickly. Please wait and try again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - PeerSupportAnyEncodable Helper

private struct PeerSupportAnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ wrapped: T) {
        _encode = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
