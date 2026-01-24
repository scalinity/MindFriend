import Foundation
import Supabase

/// Service for mentorship matching features
@MainActor
final class MentorshipService: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var profile: DBMentorshipProfile?
    @Published private(set) var matches: [DBMentorshipMatch] = []
    @Published var currentMessages: [DBMentorshipMessage] = []
    @Published var isLoading = false
    @Published var error: String?

    // MARK: - Private Properties

    private let supabase: SupabaseClient
    private var messageChannel: RealtimeChannelV2?
    private var subscriptionTask: Task<Void, Never>?

    // MARK: - Constants

    private static let MAX_MESSAGES_PER_LOAD = 100
    private static let INITIAL_MESSAGE_LIMIT = 50
    
    // Timeout constants (in seconds)
    private static let TIMEOUT_FETCH_PROFILE: UInt64 = 5
    private static let TIMEOUT_UPSERT_PROFILE: UInt64 = 8
    private static let TIMEOUT_FIND_MATCHES: UInt64 = 10
    private static let TIMEOUT_REQUEST_MENTORSHIP: UInt64 = 12
    private static let TIMEOUT_FETCH_MATCHES: UInt64 = 5
    private static let TIMEOUT_ACCEPT_DECLINE_MATCH: UInt64 = 8
    private static let TIMEOUT_END_MENTORSHIP: UInt64 = 8
    private static let TIMEOUT_FETCH_MESSAGES: UInt64 = 5
    private static let TIMEOUT_SEND_MESSAGE: UInt64 = 8
    private static let TIMEOUT_MARK_AS_READ: UInt64 = 5
    private static let TIMEOUT_REPORT_ISSUE: UInt64 = 8
    private static let TIMEOUT_DELETE_MESSAGE: UInt64 = 5
    
    // Message constraints
    private static let MAX_MESSAGE_LENGTH = 2000

    // MARK: - Pagination State

    private var messagePaginationOffsets: [UUID: Int] = [:]
    private var hasMoreMessagesMap: [UUID: Bool] = [:]
    private var backfilledMessageIds: Set<UUID> = []

    // Add these properties for subscription management
    private var currentMatchId: UUID?
    private var subscriptionReconnectAttempts = 0

    // MARK: - Initialization

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    /// Cleanup method for explicit teardown (preferred over relying on deinit)
    func cleanup() async {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        await messageChannel?.unsubscribe()
        messageChannel = nil
        currentMessages = []
        backfilledMessageIds.removeAll()
        messagePaginationOffsets.removeAll()
        hasMoreMessagesMap.removeAll()
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

        let response: [DBMentorshipProfile] = try await withTimeout(seconds: Self.TIMEOUT_FETCH_PROFILE) { [self] in
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
        let response: UUID = try await withTimeout(seconds: Self.TIMEOUT_UPSERT_PROFILE) { [self] in
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

        let response: FindMentorMatchesResponse = try await withTimeout(seconds: Self.TIMEOUT_FIND_MATCHES) { [self] in
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

        let response: RequestMentorshipResponse = try await withTimeout(seconds: Self.TIMEOUT_REQUEST_MENTORSHIP) { [self] in
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
        let response: [DBMentorshipMatch] = try await withTimeout(seconds: Self.TIMEOUT_FETCH_MATCHES) { [self] in
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
        let _: Bool = try await withTimeout(seconds: Self.TIMEOUT_ACCEPT_DECLINE_MATCH) { [self] in
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
        let _: Bool = try await withTimeout(seconds: Self.TIMEOUT_ACCEPT_DECLINE_MATCH) { [self] in
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
        let _: Bool = try await withTimeout(seconds: Self.TIMEOUT_END_MENTORSHIP) { [self] in
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

    /// Fetch messages for a match (with pagination and batch decryption)
    func fetchMessages(matchId: UUID, offset: Int = 0) async throws -> [DBMentorshipMessage] {
        let limit = offset == 0 ? Self.INITIAL_MESSAGE_LIMIT : Self.MAX_MESSAGES_PER_LOAD
        
        let response: [DBMentorshipMessage] = try await withTimeout(seconds: Self.TIMEOUT_FETCH_MESSAGES) { [self] in
            // Fetch raw encrypted messages with pagination
            let rawMessages: [EncryptedMessageRow] = try await self.supabase
                .from("mentorship_messages")
                .select()
                .eq("match_id", value: matchId)
                .order("sent_at", ascending: true)
                .range(offset, offset + limit)
                .execute()
                .value

            // Batch decrypt all messages in single RPC call (fixes N+1 queries)
            let messageIds = rawMessages.compactMap { $0.id }
            guard !messageIds.isEmpty else { return [] }
            
            let decryptResults: [DecryptResult] = try await self.supabase
                .rpc(
                    "decrypt_messages_batch",
                    params: ["p_message_ids": AnyEncodable(messageIds)]
                )
                .execute()
                .value
            
            // Map decrypted results back to messages
            let decryptMap = Dictionary(uniqueKeysWithValues: 
                decryptResults.map { ($0.message_id, $0) }
            )
            
            let decryptedMessages: [DBMentorshipMessage] = rawMessages.compactMap { rawMsg in
                guard let decryptResult = decryptMap[rawMsg.id] else {
                    // Skip messages that failed to decrypt
                    return nil
                }

                if !decryptResult.decryption_success {
                    print("Warning: Message \(rawMsg.id) failed decryption: \(decryptResult.error_message ?? "Unknown error")")
                }

                return DBMentorshipMessage(
                    id: rawMsg.id,
                    matchId: rawMsg.match_id,
                    senderId: rawMsg.sender_id,
                    content: decryptResult.decrypted_content ?? "[Decryption failed]",
                    sentAt: rawMsg.sent_at,
                    readAt: rawMsg.read_at,
                    flagged: rawMsg.flagged,
                    flagReason: rawMsg.flag_reason,
                    reviewed: rawMsg.reviewed,
                    reviewedAt: rawMsg.reviewed_at,
                    reviewedBy: rawMsg.reviewed_by,
                    createdAt: rawMsg.created_at
                )
            }

            // Track pagination state per match
            messagePaginationOffsets[matchId] = offset + limit
            hasMoreMessagesMap[matchId] = rawMessages.count == limit

            return decryptedMessages
        }

        if offset == 0 {
            currentMessages = response
        } else {
            currentMessages.append(contentsOf: response)
        }
        return response
    }

    /// Load more messages (pagination)
    func loadMoreMessages(matchId: UUID) async throws -> [DBMentorshipMessage] {
        guard let offset = messagePaginationOffsets[matchId],
              let hasMore = hasMoreMessagesMap[matchId],
              hasMore else { return [] }
        return try await fetchMessages(matchId: matchId, offset: offset)
    }

    /// Delete user's own message (GDPR right to be forgotten)
    func deleteMessage(messageId: UUID) async throws {
        guard supabase.auth.currentUser != nil else {
            throw MentorshipError.notAuthenticated
        }

        let _: Bool = try await withTimeout(seconds: Self.TIMEOUT_DELETE_MESSAGE) { [self] in
            try await self.supabase.rpc(
                "delete_mentorship_message",
                params: ["p_message_id": AnyEncodable(messageId.uuidString)]
            )
            .execute()
            .value
        }

        // Remove from local state
        currentMessages.removeAll { $0.id == messageId }
    }

    /// Send a message with comprehensive error handling
    func sendMessage(matchId: UUID, content: String) async throws {
        // Validate inputs
        guard !content.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw MentorshipError.validationError("Message cannot be empty")
        }
        
        guard content.count <= Self.MAX_MESSAGE_LENGTH else {
            throw MentorshipError.validationError("Message exceeds \(Self.MAX_MESSAGE_LENGTH) character limit")
        }
        
        // Verify match exists and user is participant
        let matchCheck = try await supabase
            .from("mentorship_matches")
            .select("id, status, mentor_id, mentee_id")
            .eq("id", value: matchId)
            .single()
            .execute()
        
        guard let match = try? matchCheck.json() as? [String: Any],
              let mentorId = match["mentor_id"] as? String,
              let menteeId = match["mentee_id"] as? String,
              let currentUserId = supabase.auth.currentUser?.id,
              (mentorId == currentUserId || menteeId == currentUserId) else {
            throw MentorshipError.notFound("Mentorship match not found or access denied")
        }
        
        // Encrypt content before sending
        let keyId = try await getActiveEncryptionKeyId()
        let encryptionResult = try await supabase.rpc(
            "encrypt_message_content_aes_gcm",
            params: [
                "p_content": content,
                "p_key_id": keyId
            ]
        )
        
        // Parse encryption RPC result - comes as RECORD with three fields
        struct EncryptionResult: Codable {
            let v_encrypted: String  // bytea encoded as base64 string in JSON
            let v_iv: String?        // NULL with pgp_sym_encrypt (HMAC included in encrypted blob)
            let v_key_id_out: String
            
            enum CodingKeys: String, CodingKey {
                case v_encrypted
                case v_iv
                case v_key_id_out
            }
        }
        
        let encryptionResultDecoded = try encryptionResult.json(as: EncryptionResult.self)
        let encryptedContent = encryptionResultDecoded.v_encrypted
        // Note: v_iv is NULL since pgp_sym_encrypt includes HMAC in encrypted blob
        
        // Send with retry on conflict
        var retryCount = 0
        let maxRetries = 3
        
        while retryCount < maxRetries {
            do {
                _ = try await supabase
                    .from("mentorship_messages")
                    .insert([
                        "match_id": matchId,
                        "sender_id": supabase.auth.currentUser?.id ?? "",
                        "encrypted_content": encryptedContent,
                        "iv": nil,
                        "encryption_key_id": keyId,
                        "sent_at": Date().ISO8601Format()
                    ])
                    .execute()
                
                error = nil
                return
            } catch let error as PostgrestError where error.code == "23505" {
                // Unique constraint violation - retry with slight delay
                retryCount += 1
                if retryCount < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(Double(retryCount) * 100_000_000))
                    continue
                }
                throw MentorshipError.networkError("Failed to send message after retries")
            } catch {
                self.error = "Failed to send message: \(error.localizedDescription)"
                throw error
            }
        }
    }
    
    // MARK: - Encryption Key Management
    
    private func getActiveEncryptionKeyId() async throws -> String {
        let keyId = try await supabase.rpc("get_active_encryption_key").json() as? String
        guard let keyId = keyId, !keyId.isEmpty else {
            throw MentorshipError.encryptionError("No active encryption key found")
        }
        return keyId
    }

    // MARK: - Subscription with Reconnection + Backfill
    
    func subscribeToMessages(matchId: UUID) async {
        // Unsubscribe from previous subscription
        await unsubscribeFromMessages()
        
        // Clear backfilled message tracking when switching matches
        backfilledMessageIds.removeAll()
        
        self.currentMatchId = matchId
        let channelName = "mentorship_messages:\(matchId)"
        
        let channel = supabase.realtimeV2.channel(channelName)
        
        // Track last received message timestamp for backfill
        var lastReceivedTimestamp = Date()
        
        // Listen for new messages
        channel.onPostgresChange(
            event: .insert,
            schema: "public",
            table: "mentorship_messages"
        ) { [weak self] payload in
            Task { @MainActor [weak self] in
                // Verify message belongs to this match
                guard let message = try? JSONDecoder().decode(
                    DBMentorshipMessage.self,
                    from: JSONEncoder().encode(payload.newRecord)
                ) else { return }
                
                guard message.matchId == matchId else { return }
                
                // Update timestamp for potential backfill
                lastReceivedTimestamp = max(lastReceivedTimestamp, message.sentAt)
                
                // Batch decrypt and append
                do {
                    let decryptResult = try await self?.supabase.rpc(
                        "decrypt_messages_batch",
                        params: ["p_message_ids": [message.id]]
                    )
                    
                    let results: [DecryptResult] = try decryptResult?.json(as: [DecryptResult].self) ?? []
                    
                    if let result = results.first, result.decryption_success,
                       let decryptedContent = result.decrypted_content {
                        // Create message with decrypted content
                        var decryptedMessage = message
                        decryptedMessage.content = decryptedContent
                        
                        // Check if this was a backfilled message to prevent duplicates
                        if !self?.backfilledMessageIds.contains(message.id) ?? true {
                            self?.currentMessages.insert(decryptedMessage, at: 0)
                        }
                    } else if let result = results.first {
                        // Decryption failed - log error but don't crash
                        print("Message decryption failed: \(result.error_message ?? "Unknown error")")
                    }
                } catch {
                    print("Failed to decrypt realtime message: \(error.localizedDescription)")
                }
            }
        }
        
        // Listen for DELETE events (restored messages support)
        channel.onPostgresChange(
            event: .delete,
            schema: "public",
            table: "mentorship_messages"
        ) { [weak self] payload in
            Task { @MainActor [weak self] in
                guard let deletedId = payload.oldRecord["id"] as? String,
                      let uuid = UUID(uuidString: deletedId) else { return }
                self?.currentMessages.removeAll { $0.id == uuid }
            }
        }
        
        // Subscribe with reconnection handler
        do {
            try await channel.subscribe()
            self.messageChannel = channel
            self.subscriptionReconnectAttempts = 0
        } catch {
            self.error = "Failed to subscribe to messages"
            // Pass current attempt count to prevent infinite loop
            scheduleSubscriptionReconnect(matchId: matchId, attempt: subscriptionReconnectAttempts)
        }
    }
    
    // MARK: - Subscription Reconnection with Exponential Backoff
    
    private func scheduleSubscriptionReconnect(matchId: UUID, attempt: Int) {
        let maxAttempts = 5
        let backoffSeconds = pow(2.0, Double(attempt)) * 5.0  // 5s, 10s, 20s, 40s, 80s
        
        guard attempt < maxAttempts else {
            error = "Connection lost. Please refresh."
            return
        }
        
        Task {
            try await Task.sleep(nanoseconds: UInt64(backoffSeconds * 1_000_000_000))
            
            // Fetch messages since last known timestamp to backfill
            guard let lastMessage = currentMessages.first else {
                await subscribeToMessages(matchId: matchId)
                return
            }
            
            // Backfill missing messages during offline period
            do {
                let backfillMessages = try await supabase
                    .from("mentorship_messages")
                    .select()
                    .eq("match_id", matchId)
                    .gt("sent_at", lastMessage.sentAt.ISO8601Format())
                    .execute()
                
                // Batch decrypt backfilled messages
                if let backfilled = try? backfillMessages.json() as? [[String: Any]] {
                    let backfillIds = backfilled.compactMap { $0["id"] as? String }.compactMap(UUID.init)
                    
                    // Track backfilled messages to prevent duplicates (limit to 500 most recent)
                    backfilledMessageIds.formUnion(backfillIds)
                    if backfilledMessageIds.count > 500 {
                        // Keep only the most recent messages
                        let toRemove = backfilledMessageIds.count - 500
                        let sortedIds = backfilledMessageIds.sorted { $0.uuidString < $1.uuidString }
                        backfilledMessageIds.subtract(sortedIds.prefix(toRemove))
                    }
                    
                    _ = try await supabase.rpc(
                        "decrypt_messages_batch",
                        params: ["p_message_ids": backfillIds]
                    )
                }
            } catch {
                // Retry on backfill failure
                scheduleSubscriptionReconnect(matchId: matchId, attempt: attempt + 1)
                return
            }
            
            // Attempt reconnection
            await subscribeToMessages(matchId: matchId)
            subscriptionReconnectAttempts = attempt + 1
        }
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

        try await withTimeout(seconds: Self.TIMEOUT_MARK_AS_READ) { [self] in
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

        try await withTimeout(seconds: Self.TIMEOUT_REPORT_ISSUE) { [self] in
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
    case notFound(String)
    case invalidMessage(String)
    case rateLimited
    case matchNotFound
    case networkError(Error)
    case validationError(String)
    case encryptionError(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .notFound(let message):
            return message
        case .invalidMessage(let message):
            return message
        case .rateLimited:
            return "Too many requests. Please wait before trying again."
        case .matchNotFound:
            return "Mentorship match not found"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .validationError(let message):
            return message
        case .encryptionError(let message):
            return message
        }
    }
}
