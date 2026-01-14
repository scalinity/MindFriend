import Foundation
import Supabase

// MARK: - API Errors

enum APIError: LocalizedError {
    case quotaExceeded
    case badRequest(String)
    case serverError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .quotaExceeded:
            return "Daily AI quota exceeded. Upgrade to premium for unlimited access."
        case .badRequest(let message):
            return message
        case .serverError(let message):
            return message
        case .networkError(let message):
            return message
        }
    }
}

/// Handles all data operations with Supabase
@MainActor
final class SupabaseDataService: ObservableObject {
    private let authService: SupabaseAuthService

    init(authService: SupabaseAuthService) {
        self.authService = authService
    }

    private var userId: UUID {
        get throws {
            guard let id = authService.userId else {
                throw DataError.notAuthenticated
            }
            return id
        }
    }

    // MARK: - Moods

    func createMood(_ mood: MoodEntry) async throws {
        let dbMood = DBMood(
            id: nil,
            userId: try userId,
            localDate: mood.localDate,
            moodScore: mood.moodScore,
            anxietyScore: mood.anxietyScore,
            energyScore: mood.energyScore,
            note: mood.note,
            createdAt: nil
        )

        try await supabase
            .from(Tables.moods)
            .upsert(dbMood, onConflict: "user_id,local_date")
            .execute()

        Analytics.shared.track(.moodLogged, properties: [
            "mood_score": mood.moodScore,
            "has_note": mood.note != nil
        ])
    }

    func getMoods(from startDate: String, to endDate: String) async throws -> [MoodEntry] {
        let moods: [DBMood] = try await supabase
            .from(Tables.moods)
            .select()
            .eq("user_id", value: try userId)
            .gte("local_date", value: startDate)
            .lte("local_date", value: endDate)
            .order("local_date", ascending: false)
            .execute()
            .value

        return moods.map { $0.toMoodEntry() }
    }

    func getMoodsForPast(days: Int) async throws -> [MoodEntry] {
        let formatter = ISO8601DateFormatter.dateOnly
        let to = formatter.string(from: Date())
        guard let pastDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return []
        }
        let from = formatter.string(from: pastDate)
        return try await getMoods(from: from, to: to)
    }

    // MARK: - Quests

    func getTodayQuest() async throws -> Quest? {
        let today = ISO8601DateFormatter.dateOnly.string(from: Date())

        // First try to get existing quest for today
        let existingQuests: [DBUserQuestWithTemplate] = try await supabase
            .from(Tables.userQuests)
            .select("*, quest_templates(*)")
            .eq("user_id", value: try userId)
            .eq("assigned_date", value: today)
            .execute()
            .value

        if let existing = existingQuests.first {
            return existing.toQuest()
        }

        // Assign a new quest using the database function
        let result: UUID = try await supabase
            .rpc("assign_daily_quest", params: ["p_user_id": try userId])
            .execute()
            .value

        // Fetch the newly assigned quest
        let quests: [DBUserQuestWithTemplate] = try await supabase
            .from(Tables.userQuests)
            .select("*, quest_templates(*)")
            .eq("id", value: result)
            .execute()
            .value

        return quests.first?.toQuest()
    }

    func completeQuest(id: String, reflectionNote: String?, rating: Int?) async throws {
        guard let questId = UUID(uuidString: id) else { return }

        let updates: [String: AnyEncodable] = [
            "status": AnyEncodable("completed"),
            "reflection_note": AnyEncodable(reflectionNote),
            "rating": AnyEncodable(rating),
            "completed_at": AnyEncodable(ISO8601DateFormatter().string(from: Date()))
        ]

        try await supabase
            .from(Tables.userQuests)
            .update(updates)
            .eq("id", value: questId)
            .eq("user_id", value: try userId)
            .execute()

        // Update streak and stats
        try await updateQuestStats()

        Analytics.shared.track(.questCompleted, properties: [
            "quest_id": id,
            "has_reflection": reflectionNote != nil,
            "rating": rating ?? 0
        ])
    }

    func skipQuest(id: String) async throws {
        guard let questId = UUID(uuidString: id) else { return }

        try await supabase
            .from(Tables.userQuests)
            .update(["status": "skipped"])
            .eq("id", value: questId)
            .eq("user_id", value: try userId)
            .execute()

        Analytics.shared.track(.questSkipped, properties: ["quest_id": id])
    }

    private func updateQuestStats() async throws {
        // Increment total quests completed
        try await supabase
            .from(Tables.profiles)
            .update([
                "total_quests_completed": AnyEncodable("total_quests_completed + 1")
            ])
            .eq("id", value: try userId)
            .execute()
    }

    // MARK: - Exercises

    func getExercises(type: ExerciseType? = nil) async throws -> [Exercise] {
        var query = supabase
            .from(Tables.exercises)
            .select()

        if let type = type {
            query = query.eq("type", value: type.rawValue)
        }

        let exercises: [DBExercise] = try await query
            .order("title")
            .execute()
            .value

        return exercises.map { exercise in
            Exercise(
                id: exercise.id.uuidString,
                type: ExerciseType(rawValue: exercise.type) ?? .breathing,
                title: exercise.title,
                description: exercise.description,
                durationSeconds: exercise.durationMinutes * 60,
                contentKind: .text,
                contentText: nil,
                audioUrl: nil
            )
        }
    }

    func startExerciseSession(exerciseId: String) async throws -> String {
        guard let exerciseUUID = UUID(uuidString: exerciseId) else {
            throw DataError.invalidId
        }

        let session = DBExerciseSession(
            id: nil,
            userId: try userId,
            exerciseId: exerciseUUID,
            startedAt: Date(),
            completedAt: nil,
            rating: nil,
            note: nil
        )

        let result: DBExerciseSession = try await supabase
            .from(Tables.exerciseSessions)
            .insert(session)
            .select()
            .single()
            .execute()
            .value

        Analytics.shared.track(.exerciseStarted, properties: ["exercise_id": exerciseId])

        return result.id?.uuidString ?? ""
    }

    func completeExerciseSession(sessionId: String, rating: Int?, note: String?) async throws {
        guard let sessionUUID = UUID(uuidString: sessionId) else { return }

        let updates: [String: AnyEncodable] = [
            "completed_at": AnyEncodable(ISO8601DateFormatter().string(from: Date())),
            "rating": AnyEncodable(rating),
            "note": AnyEncodable(note)
        ]

        try await supabase
            .from(Tables.exerciseSessions)
            .update(updates)
            .eq("id", value: sessionUUID)
            .execute()

        // Update stats
        try await supabase
            .from(Tables.profiles)
            .update(["total_exercises_completed": AnyEncodable("total_exercises_completed + 1")])
            .eq("id", value: try userId)
            .execute()

        Analytics.shared.track(.exerciseCompleted, properties: [
            "session_id": sessionId,
            "rating": rating ?? 0
        ])
    }

    // MARK: - Conversations

    func getConversations() async throws -> [Conversation] {
        let conversations: [DBConversation] = try await supabase
            .from(Tables.conversations)
            .select()
            .eq("user_id", value: try userId)
            .order("updated_at", ascending: false)
            .execute()
            .value

        return conversations.map { conv in
            Conversation(
                id: conv.id?.uuidString ?? "",
                title: conv.title,
                status: .active,
                createdAt: conv.createdAt ?? Date(),
                updatedAt: conv.updatedAt ?? Date(),
                lastMessage: nil
            )
        }
    }

    func createConversation(title: String?) async throws -> Conversation {
        print("[SupabaseDataService] Creating conversation for user: \(try userId)")

        let conversation = DBConversation(
            id: nil,
            userId: try userId,
            title: title,
            createdAt: nil,
            updatedAt: nil
        )

        let result: DBConversation = try await supabase
            .from(Tables.conversations)
            .insert(conversation)
            .select()
            .single()
            .execute()
            .value

        guard let conversationId = result.id else {
            print("[SupabaseDataService] ERROR: Conversation created but no ID returned")
            throw DataError.operationFailed("Failed to create conversation - no ID returned")
        }

        print("[SupabaseDataService] Conversation created with ID: \(conversationId)")
        Analytics.shared.track(.chatConversationCreated)

        return Conversation(
            id: conversationId.uuidString,
            title: result.title,
            status: .active,
            createdAt: result.createdAt ?? Date(),
            updatedAt: result.updatedAt ?? Date(),
            lastMessage: nil
        )
    }

    func deleteConversation(id: String) async throws {
        guard let convId = UUID(uuidString: id) else {
            throw DataError.invalidId
        }

        // Delete the conversation (messages will cascade delete via FK)
        try await supabase
            .from(Tables.conversations)
            .delete()
            .eq("id", value: convId)
            .eq("user_id", value: try userId)
            .execute()

        Analytics.shared.track(.chatConversationDeleted)
    }

    func getMessages(conversationId: String, limit: Int = 50) async throws -> [Message] {
        guard let convId = UUID(uuidString: conversationId) else { return [] }

        let messages: [DBMessage] = try await supabase
            .from(Tables.messages)
            .select()
            .eq("conversation_id", value: convId)
            .order("created_at", ascending: true)
            .limit(limit)
            .execute()
            .value

        return messages.map { msg in
            Message(
                id: msg.id?.uuidString ?? "",
                role: MessageRole(rawValue: msg.role) ?? .user,
                content: msg.content,
                createdAt: msg.createdAt ?? Date(),
                blocked: false
            )
        }
    }

    /// Send a message and get AI response via Edge Function
    /// Returns the assistant's response message
    func sendMessage(conversationId: String, content: String) async throws -> ChatResponse {
        print("[SupabaseDataService] Invoking chat function for conversation: \(conversationId)")

        // Validate conversation ID
        guard UUID(uuidString: conversationId) != nil else {
            print("[SupabaseDataService] ERROR: Invalid conversation ID: \(conversationId)")
            throw DataError.invalidId
        }

        // Ensure we have a valid session before calling Edge Function
        guard let accessToken = authService.session?.accessToken else {
            print("[SupabaseDataService] No access token available")
            throw APIError.badRequest("Not signed in. Please sign in again.")
        }

        // Refresh token to ensure it's valid
        do {
            try await authService.ensureValidSession()
        } catch {
            print("[SupabaseDataService] Session validation failed: \(error)")
            throw APIError.badRequest("Session expired. Please sign in again.")
        }

        // Get the refreshed access token
        guard let refreshedToken = authService.session?.accessToken else {
            print("[SupabaseDataService] No access token after refresh")
            throw APIError.badRequest("Session expired. Please sign in again.")
        }

        print("[SupabaseDataService] Using access token: \(refreshedToken.prefix(20))...")

        // Call the chat Edge Function with explicit auth header
        let chatResponse: ChatFunctionResponse
        do {
            chatResponse = try await supabase.functions.invoke(
                "chat",
                options: .init(
                    headers: ["Authorization": "Bearer \(refreshedToken)"],
                    body: [
                        "conversationId": conversationId,
                        "content": content
                    ]
                )
            )
            print("[SupabaseDataService] Chat function returned successfully")
            print("[SupabaseDataService] Response: quotaUsed=\(chatResponse.quotaUsed ?? -1), quotaLimit=\(chatResponse.quotaLimit ?? -1)")
        } catch let error as FunctionsError {
            // Extract detailed error info from FunctionsError
            switch error {
            case .httpError(let code, let data):
                let responseBody = String(data: data, encoding: .utf8) ?? "unknown"
                print("[SupabaseDataService] Chat function HTTP error \(code): \(responseBody)")

                if code == 429 || responseBody.lowercased().contains("quota") {
                    throw APIError.quotaExceeded
                } else if code == 401 {
                    throw APIError.badRequest("Authentication failed: \(responseBody)")
                } else if code == 404 {
                    throw APIError.badRequest("User profile not found. Please try signing out and back in.")
                } else {
                    throw APIError.serverError("Server error (\(code)): \(responseBody)")
                }
            case .relayError:
                print("[SupabaseDataService] Chat function relay error")
                throw APIError.networkError("Unable to reach server")
            }
        } catch {
            print("[SupabaseDataService] Chat function error: \(error)")
            throw error
        }

        Analytics.shared.track(.chatMessageSent)

        if chatResponse.isCrisisResponse == true {
            Analytics.shared.track(.crisisDetected)
        }

        return ChatResponse(
            message: Message(
                id: chatResponse.message.id ?? UUID().uuidString,
                role: .assistant,
                content: chatResponse.message.content,
                createdAt: ISO8601DateFormatter().date(from: chatResponse.message.createdAt ?? "") ?? Date(),
                blocked: chatResponse.message.blocked ?? false
            ),
            isCrisisResponse: chatResponse.isCrisisResponse ?? false,
            quotaUsed: chatResponse.quotaUsed,
            quotaLimit: chatResponse.quotaLimit,
            conversationTitle: chatResponse.conversationTitle
        )
    }

    /// Legacy method for direct message insertion (without AI response)
    func insertUserMessage(conversationId: String, content: String) async throws -> Message {
        guard let convId = UUID(uuidString: conversationId) else {
            throw DataError.invalidId
        }

        let message = DBMessage(
            id: nil,
            conversationId: convId,
            role: "user",
            content: content,
            createdAt: nil
        )

        let result: DBMessage = try await supabase
            .from(Tables.messages)
            .insert(message)
            .select()
            .single()
            .execute()
            .value

        return Message(
            id: result.id?.uuidString ?? "",
            role: .user,
            content: result.content,
            createdAt: result.createdAt ?? Date(),
            blocked: false
        )
    }

    // MARK: - Circles

    func getCircles() async throws -> [FriendCircle] {
        let circles: [DBCircleWithMembers] = try await supabase
            .from(Tables.circles)
            .select("*, circle_members(user_id, profiles(display_name, avatar_url))")
            .execute()
            .value

        return circles.map { $0.toCircle(currentUserId: try? userId) }
    }

    func createCircle(name: String, description: String?) async throws -> FriendCircle {
        let inviteCode = generateInviteCode()

        let circle = DBCircle(
            id: nil,
            name: name,
            description: description,
            inviteCode: inviteCode,
            ownerId: try userId,
            createdAt: nil
        )

        let result: DBCircle = try await supabase
            .from(Tables.circles)
            .insert(circle)
            .select()
            .single()
            .execute()
            .value

        // Add creator as member
        let membership = DBCircleMember(
            id: nil,
            circleId: result.id!,
            userId: try userId,
            joinedAt: nil
        )

        try await supabase
            .from(Tables.circleMembers)
            .insert(membership)
            .execute()

        Analytics.shared.track(.circleCreated)

        return FriendCircle(
            id: result.id?.uuidString ?? "",
            name: result.name,
            description: result.description,
            inviteCode: result.inviteCode ?? "",
            maxMembers: 10,
            memberCount: 1,
            role: .owner,
            joinedAt: Date()
        )
    }

    func joinCircle(inviteCode: String) async throws -> FriendCircle {
        // Find circle by invite code
        let circles: [DBCircle] = try await supabase
            .from(Tables.circles)
            .select()
            .eq("invite_code", value: inviteCode.uppercased())
            .execute()
            .value

        guard let circle = circles.first, let circleId = circle.id else {
            throw DataError.circleNotFound
        }

        // Add membership
        let membership = DBCircleMember(
            id: nil,
            circleId: circleId,
            userId: try userId,
            joinedAt: nil
        )

        try await supabase
            .from(Tables.circleMembers)
            .insert(membership)
            .execute()

        Analytics.shared.track(.circleJoined)

        return FriendCircle(
            id: circleId.uuidString,
            name: circle.name,
            description: circle.description,
            inviteCode: circle.inviteCode ?? "",
            maxMembers: 10,
            memberCount: 1,
            role: .member,
            joinedAt: Date()
        )
    }

    func leaveCircle(id: String) async throws {
        guard let circleId = UUID(uuidString: id) else { return }

        try await supabase
            .from(Tables.circleMembers)
            .delete()
            .eq("circle_id", value: circleId)
            .eq("user_id", value: try userId)
            .execute()

        Analytics.shared.track(.circleLeft)
    }

    func getCircle(id: String) async throws -> CircleDetail {
        guard let circleId = UUID(uuidString: id) else {
            throw DataError.invalidId
        }

        // Fetch circle with members
        let circle: DBCircleWithMembers = try await supabase
            .from(Tables.circles)
            .select("*, circle_members(user_id, joined_at, profiles(display_name, avatar_url))")
            .eq("id", value: circleId)
            .single()
            .execute()
            .value

        let members = circle.circleMembers.compactMap { member -> CircleMember? in
            guard let profile = member.profiles else { return nil }
            return CircleMember(
                id: member.userId.uuidString,
                userId: member.userId.uuidString,
                displayName: profile.displayName ?? "User",
                role: circle.ownerId == member.userId ? .owner : .member,
                joinedAt: Date()
            )
        }

        return CircleDetail(
            circle: circle.toCircle(currentUserId: try? userId),
            members: members
        )
    }

    func getCircleFeed(circleId: String, from: String, to: String) async throws -> [CirclePost] {
        guard let circleUUID = UUID(uuidString: circleId) else {
            throw DataError.invalidId
        }

        let checkins: [DBCircleCheckinWithProfile] = try await supabase
            .from(Tables.circleCheckins)
            .select("*, profiles(display_name)")
            .eq("circle_id", value: circleUUID)
            .gte("created_at", value: from)
            .lte("created_at", value: to)
            .order("created_at", ascending: false)
            .execute()
            .value

        return checkins.map { checkin in
            CirclePost(
                id: checkin.id?.uuidString ?? UUID().uuidString,
                userId: checkin.userId.uuidString,
                userDisplayName: checkin.profiles?.displayName ?? "User",
                kind: .checkin,
                moodEmoji: checkin.moodEmoji,
                bodyText: checkin.bodyText,
                localDate: ISO8601DateFormatter.dateOnly.string(from: checkin.createdAt ?? Date()),
                createdAt: checkin.createdAt ?? Date()
            )
        }
    }

    func postCheckin(circleId: String, moodEmoji: String, bodyText: String?) async throws -> CirclePost {
        guard let circleUUID = UUID(uuidString: circleId) else {
            throw DataError.invalidId
        }

        let checkin = DBCircleCheckin(
            id: nil,
            circleId: circleUUID,
            userId: try userId,
            moodEmoji: moodEmoji,
            bodyText: bodyText,
            createdAt: nil
        )

        let result: DBCircleCheckin = try await supabase
            .from(Tables.circleCheckins)
            .insert(checkin)
            .select()
            .single()
            .execute()
            .value

        // Fetch user's display name
        let profile: DBMemberProfile = try await supabase
            .from(Tables.profiles)
            .select("display_name, avatar_url")
            .eq("id", value: try userId)
            .single()
            .execute()
            .value

        Analytics.shared.track(.circleCheckinPosted)

        return CirclePost(
            id: result.id?.uuidString ?? UUID().uuidString,
            userId: (try userId).uuidString,
            userDisplayName: profile.displayName ?? "User",
            kind: .checkin,
            moodEmoji: moodEmoji,
            bodyText: bodyText,
            localDate: ISO8601DateFormatter.dateOnly.string(from: Date()),
            createdAt: result.createdAt ?? Date()
        )
    }

    // MARK: - Crisis Resources

    func getCrisisResources(country: String? = nil) async throws -> [CrisisResource] {
        var query = supabase
            .from(Tables.crisisResources)
            .select()

        if let country = country {
            query = query.eq("country_code", value: country)
        }

        let resources: [DBCrisisResource] = try await query
            .order("is_default", ascending: false)
            .execute()
            .value

        return resources.map { resource in
            CrisisResource(
                id: resource.id.uuidString,
                country: resource.countryCode,
                countryCode: resource.countryCode,
                name: resource.name,
                phone: resource.phone,
                sms: resource.textLine,
                chat: resource.website,
                available: resource.isDefault ? "24/7" : "Available"
            )
        }
    }

    // MARK: - Device Registration

    func registerDevice(apnsToken: String, deviceModel: String, osVersion: String) async throws {
        let device = DBDevice(
            id: nil,
            userId: try userId,
            apnsToken: apnsToken,
            deviceModel: deviceModel,
            osVersion: osVersion,
            createdAt: nil,
            updatedAt: nil
        )

        try await supabase
            .from(Tables.devices)
            .upsert(device, onConflict: "user_id,apns_token")
            .execute()
    }

    // MARK: - Data Export

    func exportUserData() async throws -> UserDataExport {
        let userId = try userId

        // Fetch all user data
        let profile: DBProfile = try await supabase
            .from(Tables.profiles)
            .select()
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        let moods: [DBMood] = try await supabase
            .from(Tables.moods)
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value

        let conversations: [DBConversation] = try await supabase
            .from(Tables.conversations)
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        return UserDataExport(
            exportedAt: formatter.string(from: Date()),
            user: UserDataExport.UserExportData(
                id: userId.uuidString,
                handle: profile.handle ?? "",
                displayName: profile.displayName ?? "User",
                email: profile.email
            )
        )
    }

    // MARK: - Memory Management

    func getMemories() async throws -> [MemoryFragment] {
        let now = ISO8601DateFormatter().string(from: Date())

        // Filter expired memories at database level for efficiency
        // Order by confidence (highest first) per spec
        let memories: [DBMemoryFragment] = try await supabase
            .from(Tables.memoryFragments)
            .select()
            .eq("user_id", value: try userId)
            .or("expires_at.is.null,expires_at.gt.\(now)")
            .order("confidence", ascending: false)
            .execute()
            .value

        return memories.map { $0.toMemoryFragment() }
    }

    func getMemories(type: MemoryType) async throws -> [MemoryFragment] {
        let now = ISO8601DateFormatter().string(from: Date())

        // Filter expired memories at database level for efficiency
        let memories: [DBMemoryFragment] = try await supabase
            .from(Tables.memoryFragments)
            .select()
            .eq("user_id", value: try userId)
            .eq("fragment_type", value: type.rawValue)
            .or("expires_at.is.null,expires_at.gt.\(now)")
            .order("confidence", ascending: false)
            .execute()
            .value

        return memories.map { $0.toMemoryFragment() }
    }

    func deleteMemory(id: String) async throws {
        guard let memoryId = UUID(uuidString: id) else {
            throw DataError.invalidId
        }

        try await supabase
            .from(Tables.memoryFragments)
            .delete()
            .eq("id", value: memoryId)
            .eq("user_id", value: try userId)
            .execute()

        Analytics.shared.track(.memoryDeleted)
    }

    func deleteAllMemories() async throws {
        try await supabase
            .from(Tables.memoryFragments)
            .delete()
            .eq("user_id", value: try userId)
            .execute()

        Analytics.shared.track(.allMemoriesDeleted)
    }

    func deleteMemories(type: MemoryType) async throws {
        try await supabase
            .from(Tables.memoryFragments)
            .delete()
            .eq("user_id", value: try userId)
            .eq("fragment_type", value: type.rawValue)
            .execute()

        Analytics.shared.track(.memoriesDeletedByType, properties: ["type": type.rawValue])
    }

    // MARK: - Onboarding

    /// Update the user's wellness focus selection from onboarding quiz
    func updateWellnessFocus(_ focus: WellnessFocus) async throws {
        let currentUserId = try userId
        print("[SupabaseDataService] Updating wellness focus to '\(focus.rawValue)' for user: \(currentUserId)")

        try await supabase
            .from(Tables.profiles)
            .update(["wellness_focus": focus.rawValue])
            .eq("id", value: currentUserId)
            .execute()

        print("[SupabaseDataService] Wellness focus updated successfully")
        Analytics.shared.track(.onboardingStepCompleted, properties: [
            "step": "quiz",
            "wellness_focus": focus.rawValue
        ])
    }

    /// Mark onboarding as complete for the current user
    func markOnboardingComplete() async throws {
        let currentUserId = try userId
        let now = ISO8601DateFormatter().string(from: Date())
        print("[SupabaseDataService] Marking onboarding complete for user: \(currentUserId)")

        try await supabase
            .from(Tables.profiles)
            .update(["onboarding_completed_at": now])
            .eq("id", value: currentUserId)
            .execute()

        print("[SupabaseDataService] Onboarding marked complete at: \(now)")
        Analytics.shared.track(.onboardingCompleted)
    }

    /// Complete onboarding in a single atomic operation
    func completeOnboarding(focus: WellnessFocus) async throws {
        let currentUserId = try userId
        let now = ISO8601DateFormatter().string(from: Date())
        print("[SupabaseDataService] Completing onboarding with focus '\(focus.rawValue)' for user: \(currentUserId)")

        // Single atomic update
        try await supabase
            .from(Tables.profiles)
            .update([
                "wellness_focus": focus.rawValue,
                "onboarding_completed_at": now
            ])
            .eq("id", value: currentUserId)
            .execute()

        print("[SupabaseDataService] Onboarding completed successfully")
        Analytics.shared.track(.onboardingStepCompleted, properties: [
            "step": "quiz",
            "wellness_focus": focus.rawValue
        ])
        Analytics.shared.track(.onboardingCompleted)
    }

    // MARK: - Helpers

    private func generateInviteCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}

// MARK: - Supporting Types

struct DBExerciseSession: Codable {
    let id: UUID?
    let userId: UUID
    let exerciseId: UUID
    let startedAt: Date?
    let completedAt: Date?
    let rating: Int?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case exerciseId = "exercise_id"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case rating, note
    }
}

struct DBDevice: Codable {
    let id: UUID?
    let userId: UUID
    let apnsToken: String
    let deviceModel: String?
    let osVersion: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case apnsToken = "apns_token"
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DBUserQuestWithTemplate: Codable {
    let id: UUID
    let userId: UUID
    let questTemplateId: UUID
    let assignedDate: String
    let status: String
    let reflectionNote: String?
    let rating: Int?
    let completedAt: Date?
    let questTemplates: DBQuestTemplate

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case questTemplateId = "quest_template_id"
        case assignedDate = "assigned_date"
        case status
        case reflectionNote = "reflection_note"
        case rating
        case completedAt = "completed_at"
        case questTemplates = "quest_templates"
    }

    func toQuest() -> Quest {
        Quest(
            id: id.uuidString,
            localDate: assignedDate,
            status: QuestStatus(rawValue: status) ?? .assigned,
            assignedAt: Date(),
            completedAt: completedAt,
            template: QuestTemplate(
                id: questTemplates.id.uuidString,
                type: QuestType(rawValue: questTemplates.category) ?? .focus,
                title: questTemplates.title,
                description: questTemplates.description,
                estimatedMinutes: questTemplates.estimatedMinutes,
                difficulty: "medium",
                tags: [],
                instructions: questTemplates.defaultInstructions()
            )
        )
    }
}

struct DBCircleWithMembers: Codable {
    let id: UUID
    let name: String
    let description: String?
    let inviteCode: String
    let ownerId: UUID
    let createdAt: Date
    let circleMembers: [DBCircleMemberWithProfile]

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case inviteCode = "invite_code"
        case ownerId = "owner_id"
        case createdAt = "created_at"
        case circleMembers = "circle_members"
    }

    func toCircle(currentUserId: UUID?) -> FriendCircle {
        FriendCircle(
            id: id.uuidString,
            name: name,
            description: description,
            inviteCode: inviteCode,
            maxMembers: 10,
            memberCount: circleMembers.count,
            role: currentUserId == ownerId ? .owner : .member,
            joinedAt: createdAt
        )
    }
}

struct DBCircleMemberWithProfile: Codable {
    let userId: UUID
    let profiles: DBMemberProfile?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case profiles
    }

    func toMember() -> CircleMember? {
        guard let profile = profiles else { return nil }
        return CircleMember(
            id: userId.uuidString,
            userId: userId.uuidString,
            displayName: profile.displayName ?? "User",
            role: .member,
            joinedAt: Date()
        )
    }
}

struct DBMemberProfile: Codable {
    let displayName: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }
}

// MARK: - Chat Edge Function Response Types

struct ChatFunctionResponse: Codable {
    let message: ChatFunctionMessage
    let isCrisisResponse: Bool?
    let quotaUsed: Int?
    let quotaLimit: Int?
    let conversationTitle: String?
}

struct ChatFunctionMessage: Codable {
    let id: String?
    let role: String
    let content: String
    let createdAt: String?
    let blocked: Bool?
}

/// Response from sendMessage containing the AI response and quota info
struct ChatResponse {
    let message: Message
    let isCrisisResponse: Bool
    let quotaUsed: Int?
    let quotaLimit: Int?
    let conversationTitle: String?

    var isQuotaExceeded: Bool {
        guard let used = quotaUsed, let limit = quotaLimit, limit > 0 else { return false }
        return used >= limit
    }
}

// MARK: - Errors

enum DataError: Error, LocalizedError {
    case notAuthenticated
    case invalidId
    case circleNotFound
    case quotaExceeded(used: Int, limit: Int)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to perform this action"
        case .invalidId:
            return "Invalid identifier"
        case .circleNotFound:
            return "Circle not found. Check the invite code and try again."
        case .quotaExceeded:
            return "You've reached your daily AI chat limit. Upgrade to Premium for unlimited chats!"
        case .operationFailed(let message):
            return message
        }
    }
}

// MARK: - Date Formatter Extension

extension ISO8601DateFormatter {
    static let dateOnly: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
