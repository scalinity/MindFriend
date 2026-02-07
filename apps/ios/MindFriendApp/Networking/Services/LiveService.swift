// LiveService.swift
// MindFriend - Live Experiences Service
// Handles live sessions, circle rooms, and presence with Supabase Realtime

import Foundation
import Supabase
import Realtime
import OSLog

// MARK: - Live Service Errors

enum LiveServiceError: LocalizedError {
    case notAuthenticated
    case sessionNotFound
    case sessionNotActive
    case alreadyInSession
    case invalidResponse
    case realtimeError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to join live sessions."
        case .sessionNotFound:
            return "This session is no longer available."
        case .sessionNotActive:
            return "This session hasn't started yet or has already ended."
        case .alreadyInSession:
            return "You're already in a session. Leave the current session first."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .realtimeError(let message):
            return "Connection error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - Live Service

/// Service for managing live sessions, circle rooms, and user presence
/// Uses Supabase Realtime for live updates
@MainActor
final class LiveService: ObservableObject {

    // MARK: - Published Properties

    /// Currently available live sessions
    @Published private(set) var liveSessions: [LiveSession] = []

    /// Active session the user has joined
    @Published private(set) var currentSession: LiveSession?

    /// Current participant count in active session
    @Published private(set) var participantCount: Int = 0

    /// Recent reactions in active session (last 5)
    @Published private(set) var recentReactions: [String] = []

    /// Active circle live rooms for user's circles
    @Published private(set) var activeCircleRooms: [CircleLiveRoom] = []

    /// Current circle room the user has joined
    @Published private(set) var currentCircleRoom: CircleLiveRoom?

    /// Friends' presence status
    @Published private(set) var friendsPresence: [UserPresence] = []

    /// Connection status
    @Published private(set) var isConnected: Bool = false

    /// Loading state
    @Published private(set) var isLoading: Bool = false

    /// Error message for display
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let logger = Logger(subsystem: "app.mindfriend", category: "LiveService")

    /// Active Realtime channel for live session
    private var sessionChannel: RealtimeChannelV2?

    /// Active Realtime channel for circle room
    private var roomChannel: RealtimeChannelV2?

    /// Presence channel for friends
    private var presenceChannel: RealtimeChannelV2?

    /// Heartbeat timer for keeping presence alive
    private var heartbeatTimer: Timer?

    /// Maximum reactions to keep in memory
    private let maxRecentReactions = 5

    // MARK: - Initialization

    init() {
        // Uses global supabase client
    }

    deinit {
        heartbeatTimer?.invalidate()
    }

    // MARK: - Authentication Helper

    private var userId: UUID {
        get throws {
            guard let id = supabase.auth.currentUser?.id else {
                throw LiveServiceError.notAuthenticated
            }
            return id
        }
    }

    // MARK: - Live Sessions

    /// Fetch all active and upcoming live sessions
    func fetchLiveSessions() async throws {
        isLoading = true
        defer { isLoading = false }

        _ = try userId  // Validate auth

        let sessions: [DBLiveSession] = try await supabase
            .from(Tables.liveSessions)
            .select()
            .eq("is_active", value: true)
            .gte("scheduled_end", value: Date().ISO8601Format())
            .order("scheduled_start", ascending: true)
            .execute()
            .value

        liveSessions = sessions.map { $0.toLiveSession() }
        logger.info("Fetched \(sessions.count) live sessions")
    }

    /// Fetch live sessions using the RPC (includes participant counts)
    func fetchLiveSessionsWithCounts() async throws {
        isLoading = true
        defer { isLoading = false }

        _ = try userId

        struct SessionWithCount: Codable {
            let id: String
            let title: String
            let description: String?
            let sessionType: String
            let scheduledStart: Date
            let scheduledEnd: Date
            let audioUrl: String?
            let isActive: Bool
            let participantCount: Int

            enum CodingKeys: String, CodingKey {
                case id, title, description
                case sessionType = "session_type"
                case scheduledStart = "scheduled_start"
                case scheduledEnd = "scheduled_end"
                case audioUrl = "audio_url"
                case isActive = "is_active"
                case participantCount = "participant_count"
            }
        }

        let sessions: [SessionWithCount] = try await supabase
            .rpc("get_live_sessions")
            .execute()
            .value

        liveSessions = sessions.map { session in
            LiveSession(
                id: session.id,
                title: session.title,
                description: session.description,
                sessionType: SessionType(rawValue: session.sessionType) ?? .breathing,
                scheduledStart: session.scheduledStart,
                scheduledEnd: session.scheduledEnd,
                audioUrl: session.audioUrl,
                participantCount: session.participantCount
            )
        }

        logger.info("Fetched \(sessions.count) live sessions with counts")
    }

    /// Join a live session
    func joinSession(sessionId: String) async throws -> JoinSessionResult {
        guard currentSession == nil else {
            throw LiveServiceError.alreadyInSession
        }

        isLoading = true
        defer { isLoading = false }

        _ = try userId

        // Call edge function to join
        let result: JoinSessionResult = try await supabase.functions.invoke(
            "live-session-manager",
            options: .init(body: [
                "action": "join",
                "session_id": sessionId
            ])
        )

        currentSession = result.session
        participantCount = result.participantCount

        // Subscribe to realtime updates
        await subscribeToSession(sessionId: sessionId)

        // Start heartbeat
        startHeartbeat(sessionId: sessionId)

        logger.info("Joined session \(sessionId) with \(result.participantCount) participants")

        Analytics.shared.track(.liveSessionJoined, properties: [
            "session_id": sessionId,
            "session_type": result.session.sessionType.rawValue,
            "participant_count": result.participantCount
        ])

        return result
    }

    /// Leave the current session
    func leaveSession() async throws {
        guard let session = currentSession else { return }

        // Unsubscribe from realtime
        await unsubscribeFromSession()

        // Stop heartbeat
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil

        // Call edge function to leave
        _ = try await supabase.functions.invoke(
            "live-session-manager",
            options: .init(body: [
                "action": "leave",
                "session_id": session.id
            ])
        )

        logger.info("Left session \(session.id)")

        Analytics.shared.track(.liveSessionLeft, properties: [
            "session_id": session.id,
            "duration_seconds": Int(Date().timeIntervalSince(session.scheduledStart))
        ])

        currentSession = nil
        participantCount = 0
        recentReactions = []
    }

    /// Send a reaction in the current session
    func sendReaction(emoji: String) async throws {
        guard let session = currentSession else { return }

        _ = try await supabase.functions.invoke(
            "live-session-manager",
            options: .init(body: [
                "action": "react",
                "session_id": session.id,
                "emoji": emoji
            ])
        )

        // Optimistically add to local reactions
        addReaction(emoji)
    }

    /// Complete the current session (marks as completed, awards XP)
    func completeSession() async throws -> CompleteSessionResult {
        guard let session = currentSession else {
            throw LiveServiceError.sessionNotFound
        }

        // Unsubscribe first
        await unsubscribeFromSession()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil

        let result: CompleteSessionResult = try await supabase.functions.invoke(
            "live-session-manager",
            options: .init(body: [
                "action": "complete",
                "session_id": session.id
            ])
        )

        logger.info("Completed session \(session.id), XP awarded: \(result.xpAwarded)")

        Analytics.shared.track(.liveSessionCompleted, properties: [
            "session_id": session.id,
            "xp_awarded": result.xpAwarded
        ])

        currentSession = nil
        participantCount = 0
        recentReactions = []

        return result
    }

    // MARK: - Realtime Subscriptions

    private func subscribeToSession(sessionId: String) async {
        // Create channel for this session
        let channel = supabase.realtimeV2.channel("live:session:\(sessionId)")

        // Listen for broadcast events
        let broadcastStream = channel.broadcastStream(event: "participant_update")
        Task {
            for await message in broadcastStream {
                await handleSessionBroadcast(message)
            }
        }

        let reactionStream = channel.broadcastStream(event: "reaction")
        Task {
            for await message in reactionStream {
                await handleReactionBroadcast(message)
            }
        }

        // Subscribe
        try? await channel.subscribeWithError()

        sessionChannel = channel
        isConnected = true

        logger.info("Subscribed to session channel: live:session:\(sessionId)")
    }

    private func unsubscribeFromSession() async {
        if let channel = sessionChannel {
            await channel.unsubscribe()
            sessionChannel = nil
        }
        isConnected = false
        logger.info("Unsubscribed from session channel")
    }

    private func handleSessionBroadcast(_ message: JSONObject) async {
        guard let payloadJSON = message["payload"],
              case .object(let payload) = payloadJSON,
              let typeJSON = payload["type"],
              case .string(let type) = typeJSON else { return }

        switch type {
        case "participant_joined", "participant_left":
            if let countJSON = payload["count"], case .integer(let count) = countJSON {
                await MainActor.run {
                    self.participantCount = count
                }
            }
        default:
            break
        }
    }

    private func handleReactionBroadcast(_ message: JSONObject) async {
        guard let payloadJSON = message["payload"],
              case .object(let payload) = payloadJSON,
              let emojiJSON = payload["emoji"],
              case .string(let emoji) = emojiJSON else { return }

        await MainActor.run {
            addReaction(emoji)
        }
    }

    private func addReaction(_ emoji: String) {
        recentReactions.append(emoji)
        if recentReactions.count > maxRecentReactions {
            recentReactions.removeFirst()
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat(sessionId: String) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.sendHeartbeat(sessionId: sessionId)
            }
        }
    }

    private func sendHeartbeat(sessionId: String) async {
        do {
            _ = try await supabase.functions.invoke(
                "live-session-manager",
                options: .init(body: [
                    "action": "heartbeat",
                    "session_id": sessionId
                ])
            )
        } catch {
            logger.warning("Heartbeat failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Circle Live Rooms

    /// Fetch active circle rooms for user's circles
    func fetchActiveCircleRooms() async throws {
        _ = try userId

        let rooms: [DBCircleLiveRoom] = try await supabase
            .rpc("get_active_circle_rooms")
            .execute()
            .value

        activeCircleRooms = rooms.map { $0.toCircleLiveRoom() }
        logger.info("Fetched \(rooms.count) active circle rooms")
    }

    /// Create a new live room in a circle
    func createCircleRoom(
        circleId: String,
        activityType: String,
        exerciseId: String? = nil,
        title: String? = nil,
        durationMinutes: Int = 10
    ) async throws -> CircleLiveRoom {
        let currentUserId = try userId

        let now = Date()
        let endsAt = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: now) ?? now.addingTimeInterval(TimeInterval(durationMinutes * 60))

        struct InsertRoom: Codable {
            let circleId: String
            let createdBy: String
            let activityType: String
            let exerciseId: String?
            let title: String?
            let durationMinutes: Int
            let startedAt: Date
            let endsAt: Date
            let status: String

            enum CodingKeys: String, CodingKey {
                case circleId = "circle_id"
                case createdBy = "created_by"
                case activityType = "activity_type"
                case exerciseId = "exercise_id"
                case title
                case durationMinutes = "duration_minutes"
                case startedAt = "started_at"
                case endsAt = "ends_at"
                case status
            }
        }

        let insert = InsertRoom(
            circleId: circleId,
            createdBy: currentUserId.uuidString,
            activityType: activityType,
            exerciseId: exerciseId,
            title: title,
            durationMinutes: durationMinutes,
            startedAt: now,
            endsAt: endsAt,
            status: "active"
        )

        let result: [DBCircleLiveRoom] = try await supabase
            .from(Tables.circleLiveRooms)
            .insert(insert)
            .select()
            .execute()
            .value

        guard let room = result.first else {
            throw LiveServiceError.invalidResponse
        }

        let circleRoom = room.toCircleLiveRoom()

        // Auto-join the room
        try await joinCircleRoom(roomId: circleRoom.id)

        logger.info("Created circle room \(circleRoom.id) in circle \(circleId)")

        return circleRoom
    }

    /// Join a circle live room
    func joinCircleRoom(roomId: String) async throws {
        let currentUserId = try userId

        struct InsertParticipant: Codable {
            let roomId: String
            let userId: String
            let joinedAt: Date
            let completed: Bool

            enum CodingKeys: String, CodingKey {
                case roomId = "room_id"
                case userId = "user_id"
                case joinedAt = "joined_at"
                case completed
            }
        }

        try await supabase
            .from(Tables.circleRoomParticipants)
            .upsert(InsertParticipant(
                roomId: roomId,
                userId: currentUserId.uuidString,
                joinedAt: Date(),
                completed: false
            ), onConflict: "room_id,user_id")
            .execute()

        // Fetch the room with participants
        let rooms: [DBCircleLiveRoom] = try await supabase
            .from(Tables.circleLiveRooms)
            .select()
            .eq("id", value: roomId)
            .execute()
            .value

        guard let room = rooms.first else {
            throw LiveServiceError.sessionNotFound
        }

        currentCircleRoom = room.toCircleLiveRoom()

        // Subscribe to room updates
        await subscribeToCircleRoom(roomId: roomId)

        // Update presence
        try await updatePresence(activity: "circle_room")

        logger.info("Joined circle room \(roomId)")
    }

    /// Leave the current circle room
    func leaveCircleRoom() async throws {
        guard let room = currentCircleRoom else { return }

        let currentUserId = try userId

        await unsubscribeFromCircleRoom()

        try await supabase
            .from(Tables.circleRoomParticipants)
            .update(["left_at": Date().ISO8601Format()])
            .eq("room_id", value: room.id)
            .eq("user_id", value: currentUserId.uuidString)
            .execute()

        currentCircleRoom = nil
        logger.info("Left circle room \(room.id)")
    }

    private func subscribeToCircleRoom(roomId: String) async {
        let channel = supabase.realtimeV2.channel("circle:room:\(roomId)")

        // Listen for participant changes
        let participantStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: Tables.circleRoomParticipants,
            filter: "room_id=eq.\(roomId)"
        )

        Task {
            for await change in participantStream {
                await handleCircleRoomChange(change)
            }
        }

        try? await channel.subscribeWithError()
        roomChannel = channel

        logger.info("Subscribed to circle room channel: circle:room:\(roomId)")
    }

    private func unsubscribeFromCircleRoom() async {
        if let channel = roomChannel {
            await channel.unsubscribe()
            roomChannel = nil
        }
    }

    private func handleCircleRoomChange(_ change: AnyAction) async {
        // Refresh participants when changes occur
        guard let room = currentCircleRoom else { return }

        do {
            let participants: [RoomParticipant] = try await supabase
                .from(Tables.circleRoomParticipants)
                .select("*, profiles(display_name)")
                .eq("room_id", value: room.id)
                .is("left_at", value: nil)
                .execute()
                .value

            await MainActor.run {
                var updatedRoom = room
                updatedRoom.participants = participants
                self.currentCircleRoom = updatedRoom
            }
        } catch {
            logger.warning("Failed to refresh room participants: \(error.localizedDescription)")
        }
    }

    // MARK: - Presence

    /// Update current user's presence
    func updatePresence(activity: String? = nil) async throws {
        _ = try userId

        struct PresenceParams: Encodable {
            let p_activity: String?
        }

        try await supabase
            .rpc("update_presence", params: PresenceParams(p_activity: activity))
            .execute()
    }

    /// Fetch presence for circle members
    func fetchCirclePresence(circleId: String) async throws -> [UserPresence] {
        _ = try userId

        let presences: [DBUserPresence] = try await supabase
            .rpc("get_circle_presence", params: ["p_circle_id": circleId])
            .execute()
            .value

        return presences.map { $0.toPresence() }
    }

    /// Subscribe to presence updates for a circle
    func subscribeToCirclePresence(circleId: String) async {
        let channel = supabase.realtimeV2.channel("presence:circle:\(circleId)")

        // Use Postgres changes on user_presence table filtered by circle membership
        let presenceStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: Tables.userPresence
        )

        Task {
            for await _ in presenceStream {
                // Refresh presence when any change occurs
                do {
                    let presences = try await fetchCirclePresence(circleId: circleId)
                    await MainActor.run {
                        self.friendsPresence = presences
                    }
                } catch {
                    logger.warning("Failed to refresh presence: \(error.localizedDescription)")
                }
            }
        }

        try? await channel.subscribeWithError()
        presenceChannel = channel

        // Initial fetch
        do {
            friendsPresence = try await fetchCirclePresence(circleId: circleId)
        } catch {
            logger.warning("Failed to fetch initial presence: \(error.localizedDescription)")
        }
    }

    func unsubscribeFromCirclePresence() async {
        if let channel = presenceChannel {
            await channel.unsubscribe()
            presenceChannel = nil
        }
    }

    // MARK: - Cleanup

    /// Clean up all subscriptions and timers
    func cleanup() async {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil

        await unsubscribeFromSession()
        await unsubscribeFromCircleRoom()
        await unsubscribeFromCirclePresence()

        currentSession = nil
        currentCircleRoom = nil
        participantCount = 0
        recentReactions = []

        logger.info("LiveService cleanup complete")
    }
}

// MARK: - Analytics Events Extension
// Note: Live session events should be added to AnalyticsEvent enum in Analytics.swift
// Live session events: liveSessionJoined, liveSessionLeft, liveSessionCompleted

// MARK: - JSON Decoder Extension

extension JSONDecoder {
    static var supabaseDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }

            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }
        return decoder
    }
}
