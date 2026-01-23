import Foundation
import Supabase
import OSLog
import UIKit

// NOTE: SupabaseError was removed in newer supabase-swift releases; keep a local alias for compatibility.
typealias SupabaseError = Error

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

// MARK: - Data Service Errors

enum DataError: LocalizedError {
    case notAuthenticated
    case invalidId
    case circleNotFound
    case circleFull
    case hugLimitReached
    case missingInviteContact
    case notImplemented(String)
    case operationFailed(String)
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .invalidId:
            return "Invalid ID"
        case .circleNotFound:
            return "Circle not found"
        case .circleFull:
            return "Circle is full"
        case .hugLimitReached:
            return "Daily hug limit reached"
        case .missingInviteContact:
            return "Contact information required for invite"
        case .notImplemented(let feature):
            return "Feature not yet implemented: \(feature)"
        case .operationFailed(let message):
            return message
        case .custom(let message):
            return message
        }
    }
}

// MARK: - Chat Response Types

struct ChatResponse: Codable {
    let message: Message
    let isCrisisResponse: Bool
    let quotaUsed: Int?
    let quotaLimit: Int?
    let conversationTitle: String?
    let coachData: CoachData?
}

struct ChatFunctionResponse: Codable {
    let message: Message
    let isCrisisResponse: Bool?
    let quotaUsed: Int?
    let quotaLimit: Int?
    let conversationTitle: String?
    let coachData: CoachData?
}

// MARK: - Private DB Types for Credibility

private struct DBMethodologyInfo: Codable {
    let code: String
    let name: String
    let description: String
    let source: String?
}

/// Handles all data operations with Supabase
@MainActor
final class SupabaseDataService: ObservableObject {
    private let authService: SupabaseAuthService

    /// In-memory cache for methodology info (static reference data)
    private var methodologyCache: [String: MethodologyInfo] = [:]

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

    /// Current user ID (nil if not authenticated)
    var currentUserId: UUID? {
        authService.userId
    }

    /// Access to Supabase Edge Functions
    var functions: FunctionsClient {
        supabase.functions
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
        // Use local date formatter to match MoodCheckInView's date format
        // This ensures consistency when comparing saved moods with query dates
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let to = formatter.string(from: Date())
        guard let pastDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return []
        }
        let from = formatter.string(from: pastDate)
        return try await getMoods(from: from, to: to)
    }

    // MARK: - Home Context (Mood-Adaptive Home)

    /// Get personalized home context for the adaptive home screen
    /// Returns mood trends, recommended actions, supportive messages, and crisis indicators
    /// Note: The RPC uses auth.uid() internally for security - no user_id parameter needed
    func getHomeContext() async throws -> HomeContext {
        // Validate authentication
        _ = try userId

        // Call the RPC that calculates all home context data
        // The function uses auth.uid() internally for IDOR protection
        let result: HomeContext = try await supabase
            .rpc("get_home_context")
            .execute()
            .value

        return result
    }

    // MARK: - Recovery Mode

    /// Fetches the current recovery mode state for the authenticated user
    /// Returns active status, entry time, and reason for entering recovery mode
    func fetchRecoveryModeState() async throws -> RecoveryModeState {
        _ = try userId

        struct SettingsResult: Codable {
            let recoveryModeActive: Bool?
            let recoveryModeEnteredAt: Date?
            let recoveryModeReason: String?

            enum CodingKeys: String, CodingKey {
                case recoveryModeActive = "recovery_mode_active"
                case recoveryModeEnteredAt = "recovery_mode_entered_at"
                case recoveryModeReason = "recovery_mode_reason"
            }
        }

        let results: [SettingsResult] = try await supabase
            .from("user_settings")
            .select("recovery_mode_active, recovery_mode_entered_at, recovery_mode_reason")
            .eq("user_id", value: try userId)
            .execute()
            .value

        guard let settings = results.first else {
            return .inactive
        }

        let reason: RecoveryModeReason? = settings.recoveryModeReason.flatMap {
            RecoveryModeReason(rawValue: $0)
        }

        return RecoveryModeState(
            isActive: settings.recoveryModeActive ?? false,
            enteredAt: settings.recoveryModeEnteredAt,
            reason: reason
        )
    }

    /// Toggles recovery mode on or off for the authenticated user
    /// When enabling: Sets recovery_mode_active=true with manual reason
    /// When disabling: Enforces 24h minimum duration rule
    /// Returns the result of the toggle operation
    func toggleRecoveryMode(enable: Bool) async throws -> ToggleRecoveryModeResult {
        _ = try userId

        struct RPCResult: Codable {
            let success: Bool
            let errorMessage: String?
            let newState: Bool
            let enteredAt: Date?

            enum CodingKeys: String, CodingKey {
                case success
                case errorMessage = "error_message"
                case newState = "new_state"
                case enteredAt = "entered_at"
            }
        }

        let results: [RPCResult] = try await supabase
            .rpc("toggle_recovery_mode", params: ["p_enable": enable])
            .execute()
            .value

        guard let result = results.first else {
            return ToggleRecoveryModeResult(
                success: false,
                errorMessage: "No result from server",
                newState: .inactive
            )
        }

        let newState = RecoveryModeState(
            isActive: result.newState,
            enteredAt: result.enteredAt,
            reason: enable ? .manual : nil
        )

        return ToggleRecoveryModeResult(
            success: result.success,
            errorMessage: result.errorMessage,
            newState: newState
        )
    }

    // MARK: - Quests

    func getTodayQuest() async throws -> Quest? {
        let today = DateFormatter.dateOnly.string(from: Date())

        // Use the assign_daily_quest RPC which is idempotent - returns existing or creates new
        // The RPC returns the quest row directly
        struct AssignQuestResult: Codable {
            let id: UUID
            let userId: UUID
            let templateId: UUID
            let localDate: String
            let status: String
            let assignedAt: Date?
            let completedAt: Date?
            let createdAt: Date?

            enum CodingKeys: String, CodingKey {
                case id
                case userId = "user_id"
                case templateId = "template_id"
                case localDate = "local_date"
                case status
                case assignedAt = "assigned_at"
                case completedAt = "completed_at"
                case createdAt = "created_at"
            }
        }

        let results: [AssignQuestResult] = try await supabase
            .rpc("assign_daily_quest", params: ["p_local_date": AnyEncodable(today)])
            .execute()
            .value

        guard let result = results.first else { return nil }

        // Fetch the full quest with template data
        let quests: [DBQuestWithTemplate] = try await supabase
            .from(Tables.quests)
            .select("*, quest_templates(*)")
            .eq("id", value: result.id)
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
            .from(Tables.quests)
            .update(updates)
            .eq("id", value: questId)
            .eq("user_id", value: try userId)
            .execute()

        // Note: Stats/streak updates are handled by database trigger (trg_quest_completed_stats)

        Analytics.shared.track(.questCompleted, properties: [
            "quest_id": id,
            "has_reflection": reflectionNote != nil,
            "rating": rating ?? 0
        ])
    }

    func skipQuest(id: String) async throws {
        guard let questId = UUID(uuidString: id) else { return }

        try await supabase
            .from(Tables.quests)
            .update(["status": "skipped"])
            .eq("id", value: questId)
            .eq("user_id", value: try userId)
            .execute()

        Analytics.shared.track(.questSkipped, properties: ["quest_id": id])
    }

    // MARK: - Quest Alternatives (Quest Choice Feature)

    /// Get today's quest alternatives, generating them if needed
    /// Returns primary quest, quick variant, and alternative quest options
    func getTodayQuestAlternatives() async throws -> QuestAlternatives {
        let today = DateFormatter.dateOnly.string(from: Date())
        let currentUserId = try userId

        // First, try to generate/get alternatives via RPC
        let results: [QuestAlternatives] = try await supabase
            .rpc("generate_quest_alternatives", params: [
                "p_user_id": currentUserId.uuidString,
                "p_date": today
            ])
            .execute()
            .value

        guard var alternatives = results.first else {
            throw DataError.operationFailed("No quest alternatives available")
        }

        // Fetch the related quest templates to populate the joined data
        // Use DBQuestTemplate which has proper snake_case mappings for database decoding
        if let primaryId = alternatives.primaryQuestId as UUID? {
            let templates: [DBQuestTemplate] = try await supabase
                .from(Tables.questTemplates)
                .select()
                .eq("id", value: primaryId)
                .execute()
                .value
            alternatives.primaryQuest = templates.first?.toQuestTemplate()
        }

        if let quickId = alternatives.quickVariantId {
            let variants: [QuestQuickVariant] = try await supabase
                .from("quest_quick_variants")
                .select()
                .eq("id", value: quickId)
                .execute()
                .value
            alternatives.quickVariant = variants.first
        }

        if let altId = alternatives.altQuestId {
            let templates: [DBQuestTemplate] = try await supabase
                .from(Tables.questTemplates)
                .select()
                .eq("id", value: altId)
                .execute()
                .value
            alternatives.altQuest = templates.first?.toQuestTemplate()
        }

        return alternatives
    }

    /// Select a quest variant (primary, quick, or alt)
    func selectQuestVariant(_ variant: QuestAlternatives.SelectedVariant, alternativesId: UUID) async throws {
        try await supabase
            .from("quest_alternatives")
            .update(["selected_variant": variant.rawValue])
            .eq("id", value: alternativesId)
            .eq("user_id", value: try userId)
            .execute()

        Analytics.shared.track(.questVariantSelected, properties: [
            "variant": variant.rawValue,
            "alternatives_id": alternativesId.uuidString
        ])
    }

    /// Reroll the quest to get a new primary quest
    /// Returns updated alternatives with new primary quest
    func rerollQuest(alternativesId: UUID) async throws -> QuestAlternatives {
        let currentUserId = try userId

        let results: [QuestAlternatives] = try await supabase
            .rpc("reroll_quest", params: [
                "p_user_id": currentUserId.uuidString,
                "p_alternatives_id": alternativesId.uuidString
            ])
            .execute()
            .value

        guard var alternatives = results.first else {
            throw DataError.operationFailed("Reroll failed - no alternatives returned")
        }

        // Fetch the new primary quest template
        // Use DBQuestTemplate which has proper snake_case mappings for database decoding
        if let primaryId = alternatives.primaryQuestId as UUID? {
            let templates: [DBQuestTemplate] = try await supabase
                .from(Tables.questTemplates)
                .select()
                .eq("id", value: primaryId)
                .execute()
                .value
            alternatives.primaryQuest = templates.first?.toQuestTemplate()
        }

        // Fetch quick variant if available
        if let quickId = alternatives.quickVariantId {
            let variants: [QuestQuickVariant] = try await supabase
                .from("quest_quick_variants")
                .select()
                .eq("id", value: quickId)
                .execute()
                .value
            alternatives.quickVariant = variants.first
        }

        Analytics.shared.track(.questRerolled, properties: [
            "alternatives_id": alternativesId.uuidString,
            "rerolls_used": alternatives.rerollsUsed
        ])

        return alternatives
    }

    /// Update quest preference after completion or skip
    /// This helps the system learn user preferences for smarter recommendations
    func updateQuestPreference(category: String, completed: Bool, rating: Int? = nil) async throws {
        let currentUserId = try userId

        // Build params with proper types for Supabase RPC
        var params: [String: AnyEncodable] = [
            "p_user_id": AnyEncodable(currentUserId.uuidString),
            "p_quest_category": AnyEncodable(category),
            "p_completed": AnyEncodable(completed)
        ]

        if let rating = rating {
            params["p_rating"] = AnyEncodable(rating)
        } else {
            params["p_rating"] = AnyEncodable(nil as Int?)
        }

        try await supabase
            .rpc("update_quest_preference", params: params)
            .execute()
    }

    /// Get user's quest preferences for all categories
    func getQuestPreferences() async throws -> [QuestPreference] {
        let preferences: [QuestPreference] = try await supabase
            .from("user_quest_preferences")
            .select()
            .eq("user_id", value: try userId)
            .execute()
            .value

        return preferences
    }

    // MARK: - Streak Shields & Recovery

    /// Get current shield status from user_stats via RPC
    func getShieldStatus() async throws -> StreakShieldStatus {
        let result: [StreakShieldStatus] = try await supabase
            .rpc("get_shield_status", params: ["p_user_id": try userId])
            .execute()
            .value

        guard let status = result.first else {
            throw APIError.badRequest("Shield status not found")
        }

        return status
    }

    /// Check streak protection and apply shield or enable recovery if needed
    /// Call this on app open/foreground to check if streak needs protection
    func checkStreakProtection() async throws -> StreakProtectionResult {
        let result: StreakProtectionResult = try await supabase.functions.invoke(
            "assign-quest",
            options: .init(body: ["action": "check_protection"])
        )

        if result.streakProtected {
            Analytics.shared.track(.streakShieldUsed, properties: [
                "new_streak": result.newStreak,
                "shields_remaining": result.shieldsRemaining
            ])
        } else if result.recoveryAvailable {
            Analytics.shared.track(.recoveryQuestOffered, properties: [
                "streak_before_break": result.streakBeforeBreak ?? 0
            ])
        }

        return result
    }

    /// Start a recovery quest to restore a broken streak
    func startRecoveryQuest() async throws -> StartRecoveryResult {
        let result: StartRecoveryResult = try await supabase.functions.invoke(
            "assign-quest",
            options: .init(body: ["action": "start_recovery"])
        )

        if result.success {
            Analytics.shared.track(.recoveryQuestStarted, properties: [
                "attempt_id": result.attemptId ?? ""
            ])
        }

        return result
    }

    /// Complete a recovery quest and restore the streak
    func completeRecoveryQuest(attemptId: String) async throws -> CompleteRecoveryResult {
        let result: CompleteRecoveryResult = try await supabase.functions.invoke(
            "assign-quest",
            options: .init(body: [
                "action": "complete_recovery",
                "attemptId": attemptId
            ])
        )

        if result.success, let restoredStreak = result.restoredStreak {
            Analytics.shared.track(.recoveryQuestCompleted, properties: [
                "restored_streak": restoredStreak
            ])
        }

        return result
    }

    /// Get active recovery quest attempt (if any)
    func getActiveRecoveryQuest() async throws -> RecoveryQuestAttempt? {
        let attempts: [RecoveryQuestAttempt] = try await supabase
            .from("recovery_quest_attempts")
            .select("*, quest_templates(*)")
            .eq("user_id", value: try userId)
            .in("status", values: ["pending", "in_progress"])
            .order("started_at", ascending: false)
            .limit(1)
            .execute()
            .value

        return attempts.first
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
                durationSeconds: exercise.durationSeconds,  // Now directly from schema
                contentKind: ContentKind(rawValue: exercise.contentKind) ?? .text,
                contentText: exercise.contentText,
                audioUrl: exercise.audioUrl,
                evidenceBasis: exercise.evidenceBasis.flatMap { EvidenceBasis(rawValue: $0) },
                therapistReviewed: exercise.therapistReviewed,
                reviewDate: exercise.reviewDate,
                methodologyNote: exercise.methodologyNote
            )
        }
    }

    // MARK: - Credibility

    /// Fetches methodology info for a specific methodology code (cached)
    func getMethodologyInfo(code: String) async throws -> MethodologyInfo? {
        // Check cache first
        if let cached = methodologyCache[code] {
            return cached
        }

        let results: [DBMethodologyInfo] = try await supabase
            .from(Tables.methodologyInfo)
            .select()
            .eq("code", value: code)
            .limit(1)
            .execute()
            .value

        let info = results.first.map { info in
            MethodologyInfo(
                code: info.code,
                name: info.name,
                description: info.description,
                source: info.source
            )
        }

        // Cache the result
        if let info {
            methodologyCache[code] = info
        }

        return info
    }

    /// Fetches all methodology info for display (populates cache)
    func getAllMethodologies() async throws -> [MethodologyInfo] {
        let results: [DBMethodologyInfo] = try await supabase
            .from(Tables.methodologyInfo)
            .select()
            .execute()
            .value

        let methodologies = results.map { info in
            MethodologyInfo(
                code: info.code,
                name: info.name,
                description: info.description,
                source: info.source
            )
        }

        // Populate cache for subsequent individual lookups
        for methodology in methodologies {
            methodologyCache[methodology.code] = methodology
        }

        return methodologies
    }

    /// Fetches approved testimonials for display
    func getTestimonials() async throws -> [Testimonial] {
        struct DBTestimonial: Codable {
            let id: UUID
            let displayName: String
            let location: String?
            let content: String
            let rating: Int
            let featureHighlight: String?

            enum CodingKeys: String, CodingKey {
                case id, content, rating, location
                case displayName = "display_name"
                case featureHighlight = "feature_highlight"
            }
        }

        let results: [DBTestimonial] = try await supabase
            .from(Tables.testimonials)
            .select()
            .eq("approved", value: true)
            .execute()
            .value

        return results.map { t in
            Testimonial(
                id: t.id,
                displayName: t.displayName,
                location: t.location,
                content: t.content,
                rating: t.rating,
                featureHighlight: t.featureHighlight
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
            durationSeconds: nil,
            createdAt: Date()
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

        // Update stats (FIX: use user_stats table which has total_exercises_completed, not profiles)
        try await supabase
            .from(Tables.userStats)
            .update(["total_exercises_completed": AnyEncodable("total_exercises_completed + 1")])
            .eq("user_id", value: try userId)
            .execute()

        Analytics.shared.track(.exerciseCompleted, properties: [
            "session_id": sessionId,
            "rating": rating ?? 0
        ])
    }

    // MARK: - Conversations

    func getConversations() async throws -> [Conversation] {
        Log.data.debug("[Data] getConversations: Starting...")
        let uid = try userId
        Log.data.debug("[Data] getConversations: Got userId=\(uid)")

        let conversations: [DBConversation] = try await supabase
            .from(Tables.conversations)
            .select()
            .eq("user_id", value: uid)
            .order("updated_at", ascending: false)
            .execute()
            .value

        Log.data.debug("[Data] getConversations: Fetched \(conversations.count) conversations")
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
        let currentUserId = try self.userId
        Log.data.debug("[Data] Creating conversation for user: \(currentUserId)")

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
            Log.data.error("[Data] Conversation created but no ID returned")
            throw DataError.operationFailed("Failed to create conversation - no ID returned")
        }

        Log.data.debug("[Data] Conversation created with ID: \(conversationId)")
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

    /// Generate a conversation title based on content using Edge Function
    func generateConversationTitle(conversationId: String, content: String) async throws -> String {
        struct TitleResponse: Codable {
            let title: String
        }

        let response: TitleResponse = try await supabase.functions.invoke(
            "generate-conversation-title",
            options: .init(body: [
                "conversationId": conversationId,
                "content": content
            ])
        )

        return response.title
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
        Log.data.debug("[Data] Invoking chat function for conversation: \(conversationId)")

        // Validate conversation ID
        guard UUID(uuidString: conversationId) != nil else {
            Log.data.error("[Data] Invalid conversation ID: \(conversationId)")
            throw DataError.invalidId
        }

        // Ensure we have a valid session before calling Edge Function
        guard let accessToken = authService.session?.accessToken else {
            Log.data.warning("[Data] No access token available")
            throw APIError.badRequest("Not signed in. Please sign in again.")
        }

        // Refresh token to ensure it's valid
        do {
            try await authService.ensureValidSession()
        } catch {
            Log.data.warning("[Data] Session validation failed: \(error)")
            throw APIError.badRequest("Session expired. Please sign in again.")
        }

        // Get the refreshed access token
        guard let refreshedToken = authService.session?.accessToken else {
            Log.data.warning("[Data] No access token after refresh")
            throw APIError.badRequest("Session expired. Please sign in again.")
        }

        // SECURITY FIX #008: Don't log access token content - even partial tokens are secrets
        Log.data.debug("[Data] Using valid access token for chat request")

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
            Log.data.debug("[Data] Chat function returned successfully")
            Log.data.debug("[Data] Response: quotaUsed=\(chatResponse.quotaUsed ?? -1), quotaLimit=\(chatResponse.quotaLimit ?? -1)")
        } catch let error as FunctionsError {
            // Extract detailed error info from FunctionsError
            switch error {
            case .httpError(let code, let data):
                let responseBody = String(data: data, encoding: .utf8) ?? "unknown"
                Log.data.error("[Data] Chat function HTTP error \(code): \(responseBody)")

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
                Log.data.error("[Data] Chat function relay error")
                throw APIError.networkError("Unable to reach server")
            }
        } catch {
            Log.data.error("[Data] Chat function error: \(error)")
            throw error
        }

        Analytics.shared.track(.chatMessageSent)

        if chatResponse.isCrisisResponse == true {
            Analytics.shared.track(.crisisDetected)
        }

        return ChatResponse(
            message: Message(
                id: chatResponse.message.id,
                role: .assistant,
                content: chatResponse.message.content,
                createdAt: chatResponse.message.createdAt,
                blocked: chatResponse.message.blocked
            ),
            isCrisisResponse: chatResponse.isCrisisResponse ?? false,
            quotaUsed: chatResponse.quotaUsed,
            quotaLimit: chatResponse.quotaLimit,
            conversationTitle: chatResponse.conversationTitle,
            coachData: chatResponse.coachData
        )
    }

    /// Direct message insertion (without AI response)
    func insertMessage(conversationId: String, role: MessageRole, content: String) async throws -> Message {
        guard let convId = UUID(uuidString: conversationId) else {
            throw DataError.invalidId
        }

        let message = DBMessage(
            id: nil,
            conversationId: convId,
            role: role.rawValue,
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
            role: role,
            content: result.content,
            createdAt: result.createdAt ?? Date(),
            blocked: false
        )
    }

    /// Legacy method for direct user message insertion (without AI response)
    func insertUserMessage(conversationId: String, content: String) async throws -> Message {
        try await insertMessage(conversationId: conversationId, role: .user, content: content)
    }

    // MARK: - Circles

    func getCircles() async throws -> [FriendCircle] {
        let currentUserId = try userId
        let circles: [DBCircleWithMembers] = try await supabase
            .from(Tables.circles)
            .select("*, circle_members(id, circle_id, user_id, role, joined_at, profiles(display_name, avatar_url))")
            .execute()
            .value

        return circles.map { $0.toCircle(currentUserId: currentUserId) }
    }

    /// Creates a new circle with a unique invite code.
    ///
    /// The invite code is generated randomly from a 32-character alphabet (A-Z excluding I/O,
    /// 2-9 excluding 0/1), giving 32^6 ≈ 1 billion combinations. In the rare case of a
    /// collision, the function retries with exponential backoff.
    ///
    /// - Parameters:
    ///   - name: The display name for the circle
    ///   - description: Optional description
    /// - Returns: The created FriendCircle
    /// - Throws: DataError if creation fails after all retries
    func createCircle(name: String, description: String?) async throws -> FriendCircle {
        let maxRetries = 5
        let baseDelayMs: UInt64 = 100 // Start with 100ms delay
        var lastError: Error?

        // Retry loop for invite code collision with exponential backoff
        for attempt in 1...maxRetries {
            let inviteCode = generateInviteCode()

            let circle = DBCircle(
                id: nil,
                name: name,
                description: description,
                inviteCode: inviteCode,
                ownerId: try userId,
                createdAt: nil
            )

            do {
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
            } catch {
                lastError = error

                // Check for unique constraint violation (PostgreSQL error code 23505)
                // This happens when invite_code already exists - retry with new code
                if isUniqueConstraintViolation(error) {
                    Log.data.debug("Invite code collision on attempt \(attempt), retrying...")

                    // Exponential backoff: 100ms, 200ms, 400ms, 800ms, 1600ms
                    // Caps at ~1.6 seconds to avoid long waits
                    let delayMs = baseDelayMs * UInt64(1 << (attempt - 1))
                    let cappedDelayMs = min(delayMs, 2000)
                    try? await Task.sleep(nanoseconds: cappedDelayMs * 1_000_000)

                    continue
                }

                // For any other error, throw immediately
                throw error
            }
        }

        // If we exhausted all retries, throw the last error
        throw lastError ?? DataError.custom("Failed to create circle after \(maxRetries) attempts")
    }

    func joinCircle(inviteCode: String) async throws -> FriendCircle {
        // Use the join_circle_by_invite_code RPC (SECURITY DEFINER bypasses RLS)
        struct JoinCircleResult: Codable {
            let circleId: UUID?
            let circleName: String?
            let memberCount: Int
            let success: Bool
            let message: String

            enum CodingKeys: String, CodingKey {
                case circleId = "circle_id"
                case circleName = "circle_name"
                case memberCount = "member_count"
                case success
                case message
            }
        }

        let results: [JoinCircleResult] = try await supabase
            .rpc("join_circle_by_invite_code", params: ["p_invite_code": inviteCode])
            .execute()
            .value

        guard let result = results.first else {
            throw DataError.circleNotFound
        }

        guard result.success, let circleId = result.circleId, let circleName = result.circleName else {
            // Map error message to appropriate error
            switch result.message {
            case "Invalid invite code":
                throw DataError.circleNotFound
            case "Circle is full":
                throw DataError.circleFull
            default:
                throw DataError.custom(result.message)
            }
        }

        Analytics.shared.track(.circleJoined)

        return FriendCircle(
            id: circleId.uuidString,
            name: circleName,
            description: nil,
            inviteCode: inviteCode.uppercased(),
            maxMembers: 10,
            memberCount: result.memberCount,
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

        let members = (circle.circleMembers ?? []).compactMap { member -> CircleMember? in
            guard let profile = member.profiles else { return nil }
            return CircleMember(
                id: member.userId.uuidString,
                userId: member.userId.uuidString,
                displayName: profile.displayName ?? "User",
                role: .member, // TODO: Determine owner role from membership data
                joinedAt: member.joinedAt ?? Date(),
                premiumBadge: profile.premiumBadge
            )
        }

        return CircleDetail(
            circle: circle.toCircle(currentUserId: try userId),
            members: members
        )
    }

    func getCircleFeed(circleId: String, from: String, to: String) async throws -> [CirclePost] {
        guard let circleUUID = UUID(uuidString: circleId) else {
            throw DataError.invalidId
        }

        let checkins: [DBCircleCheckinWithProfile] = try await supabase
            .from(Tables.circlePosts)
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
                circleId: checkin.circleId.uuidString,
                userId: checkin.userId.uuidString,
                kind: .checkin,
                moodEmoji: checkin.moodEmoji,
                bodyText: checkin.bodyText,
                localDate: DateFormatter.dateOnly.string(from: checkin.createdAt ?? Date()),
                createdAt: checkin.createdAt ?? Date(),
                userDisplayName: checkin.profiles?.displayName ?? "User",
                ritualId: nil
            )
        }
    }

    func postCheckin(circleId: String, moodEmoji: String, bodyText: String?) async throws -> CirclePost {
        guard let circleUUID = UUID(uuidString: circleId) else {
            throw DataError.invalidId
        }

        let currentUserId = try userId

        let todayDate = DateFormatter.dateOnly.string(from: Date())

        let checkin = DBCircleCheckin(
            id: nil,
            circleId: circleUUID,
            userId: currentUserId,
            kind: "checkin",
            moodEmoji: moodEmoji,
            bodyText: bodyText,
            localDate: todayDate,
            createdAt: nil,
            postType: "checkin"
        )

        let result: DBCircleCheckin = try await supabase
            .from(Tables.circlePosts)
            .insert(checkin)
            .select()
            .single()
            .execute()
            .value

        // Fetch user's display name
        let profile: DBMemberProfile = try await supabase
            .from(Tables.profiles)
            .select("display_name, avatar_url")
            .eq("id", value: currentUserId)
            .single()
            .execute()
            .value

        let senderName = profile.displayName ?? "Someone"

        // Notify other circle members about the checkin
        Task {
            await notifyCircleMembersOfPost(
                circleId: circleId,
                posterId: currentUserId,
                senderName: senderName
            )
        }

        Analytics.shared.track(.circleCheckinPosted)

        return CirclePost(
            id: result.id?.uuidString ?? UUID().uuidString,
            circleId: circleUUID.uuidString,
            userId: currentUserId.uuidString,
            kind: .checkin,
            moodEmoji: moodEmoji,
            bodyText: bodyText,
            localDate: DateFormatter.dateOnly.string(from: Date()),
            createdAt: result.createdAt ?? Date(),
            userDisplayName: senderName,
            ritualId: nil
        )
    }

    /// Notify circle members about a new post (excluding the poster)
    /// Uses batch endpoint to reduce N+1 network calls
    private func notifyCircleMembersOfPost(circleId: String, posterId: UUID, senderName: String) async {
        guard let circleUUID = UUID(uuidString: circleId) else { return }

        do {
            // Get all circle members except the poster
            let members: [DBCircleMemberWithProfile] = try await supabase
                .from(Tables.circleMembers)
                .select("user_id, profiles(display_name, avatar_url)")
                .eq("circle_id", value: circleUUID)
                .neq("user_id", value: posterId)
                .execute()
                .value

            guard !members.isEmpty else { return }

            // Batch send notifications to all members in a single request
            let recipientIds = members.map { $0.userId.uuidString }

            let notificationBody: [String: AnyEncodable] = [
                "type": AnyEncodable("circle_activity"),
                "recipientIds": AnyEncodable(recipientIds),
                "data": AnyEncodable([
                    "circleId": circleId,
                    "senderName": senderName
                ])
            ]

            let _: Void = try await supabase.functions.invoke(
                "send-notification-batch",
                options: .init(body: notificationBody)
            )
        } catch {
            Log.data.error("[Data] Failed to notify circle members: \(error)")
        }
    }

    // MARK: - Circle Hugs

    /// Send a hug to a circle member. Limited to 5 per day per recipient.
    func sendHug(to recipientId: String, in circleId: String) async throws {
        guard let recipientUUID = UUID(uuidString: recipientId),
              let circleUUID = UUID(uuidString: circleId) else {
            throw DataError.invalidId
        }

        // Check hug limit (5/day per recipient)
        let limitResult: [DBHugLimitResult] = try await supabase
            .rpc("check_hug_limit", params: [
                "p_sender_id": AnyEncodable(try userId),
                "p_recipient_id": AnyEncodable(recipientUUID),
                "p_limit": AnyEncodable(5)
            ])
            .execute()
            .value

        guard let result = limitResult.first, result.allowed else {
            throw DataError.hugLimitReached
        }

        // Insert hug
        let hugData: [String: AnyEncodable] = [
            "sender_id": AnyEncodable(try userId),
            "recipient_id": AnyEncodable(recipientUUID),
            "circle_id": AnyEncodable(circleUUID)
        ]
        try await supabase
            .from("circle_hugs")
            .insert(hugData)
            .execute()

        // Trigger notification via edge function
        // Note: senderId and circleId must be nested in "data" per API contract
        let hugNotificationBody: [String: AnyEncodable] = [
            "type": AnyEncodable("hug"),
            "recipientId": AnyEncodable(recipientId),
            "data": AnyEncodable([
                "senderId": try userId.uuidString,
                "circleId": circleId
            ])
        ]
        _ = try? await supabase.functions.invoke(
            "send-notification",
            options: .init(body: hugNotificationBody)
        )

        Analytics.shared.track(.hugSent)
    }

    /// Get hugs received since a date
    func getHugsReceived(since: Date) async throws -> [CircleHug] {
        let hugs: [DBCircleHug] = try await supabase
            .from("circle_hugs")
            .select("*, sender:profiles!sender_id(display_name)")
            .eq("recipient_id", value: try userId)
            .gte("created_at", value: ISO8601DateFormatter.full.string(from: since))
            .order("created_at", ascending: false)
            .execute()
            .value

        return hugs.map { hug in
            CircleHug(
                id: hug.id?.uuidString ?? "",
                senderId: hug.senderId.uuidString,
                recipientId: hug.recipientId.uuidString,
                circleId: hug.circleId.uuidString,
                createdAt: hug.createdAt ?? Date(),
                senderName: hug.sender?.displayName
            )
        }
    }

    // MARK: - Circle Challenges

    /// Create a 24-hour challenge (owner only)
    func createChallenge(
        in circleId: String,
        type: ChallengeType,
        title: String,
        description: String? = nil,
        exerciseId: String? = nil
    ) async throws -> CircleChallenge {
        guard let circleUUID = UUID(uuidString: circleId) else {
            throw DataError.invalidId
        }

        let endsAt = Calendar.current.date(byAdding: .hour, value: 24, to: Date()) ?? Date().addingTimeInterval(24 * 3600)

        var insertData: [String: AnyEncodable] = [
            "circle_id": AnyEncodable(circleUUID),
            "created_by": AnyEncodable(try userId),
            "challenge_type": AnyEncodable(type.rawValue),
            "title": AnyEncodable(title),
            "ends_at": AnyEncodable(ISO8601DateFormatter.full.string(from: endsAt))
        ]

        if let description = description {
            insertData["description"] = AnyEncodable(description)
        }

        if let exerciseId = exerciseId, let exerciseUUID = UUID(uuidString: exerciseId) {
            insertData["target_exercise_id"] = AnyEncodable(exerciseUUID)
        }

        let result: DBCircleChallenge = try await supabase
            .from("circle_challenges")
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value

        Analytics.shared.track(.challengeCreated)

        return CircleChallenge(
            id: result.id?.uuidString ?? "",
            circleId: result.circleId.uuidString,
            createdBy: result.createdBy.uuidString,
            challengeType: ChallengeType(rawValue: result.challengeType) ?? .custom,
            title: result.title,
            description: result.description,
            targetExerciseId: result.targetExerciseId?.uuidString,
            startsAt: result.startsAt ?? Date(),
            endsAt: result.endsAt ?? Date(),
            createdAt: result.createdAt ?? Date(),
            completions: nil,
            creatorName: nil
        )
    }

    /// Get the active challenge for a circle (if any)
    func getActiveChallenge(for circleId: String) async throws -> CircleChallenge? {
        guard let circleUUID = UUID(uuidString: circleId) else {
            throw DataError.invalidId
        }

        let now = ISO8601DateFormatter.full.string(from: Date())

        let challenges: [DBCircleChallengeWithCompletions] = try await supabase
            .from("circle_challenges")
            .select("*, completions:challenge_completions(*)")
            .eq("circle_id", value: circleUUID)
            .lte("starts_at", value: now)
            .gte("ends_at", value: now)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value

        guard let challenge = challenges.first else {
            return nil
        }

        return CircleChallenge(
            id: challenge.id?.uuidString ?? "",
            circleId: challenge.circleId.uuidString,
            createdBy: challenge.createdBy.uuidString,
            challengeType: ChallengeType(rawValue: challenge.challengeType) ?? .custom,
            title: challenge.title,
            description: challenge.description,
            targetExerciseId: challenge.targetExerciseId?.uuidString,
            startsAt: challenge.startsAt ?? Date(),
            endsAt: challenge.endsAt ?? Date(),
            createdAt: challenge.createdAt ?? Date(),
            completions: challenge.completions?.map { completion in
                ChallengeCompletion(
                    id: completion.id?.uuidString ?? "",
                    challengeId: completion.challengeId.uuidString,
                    userId: completion.userId.uuidString,
                    completedAt: completion.createdAt ?? Date(),
                    userName: nil
                )
            },
            creatorName: nil
        )
    }

    /// Mark a challenge as completed by the current user
    func completeChallenge(id: String) async throws {
        guard let challengeUUID = UUID(uuidString: id) else {
            throw DataError.invalidId
        }

        let currentUserId = try userId

        try await supabase
            .from("challenge_completions")
            .insert([
                "challenge_id": challengeUUID,
                "user_id": currentUserId
            ])
            .execute()

        Analytics.shared.track(.challengeCompleted)

        // Notify circle members about the completion
        Task {
            await notifyCircleMembersOfChallengeCompletion(challengeId: id, completerId: currentUserId)
        }
    }

    /// Notify circle members when someone completes a challenge
    /// Uses batch endpoint to reduce N+1 network calls
    private func notifyCircleMembersOfChallengeCompletion(challengeId: String, completerId: UUID) async {
        guard let challengeUUID = UUID(uuidString: challengeId) else { return }

        do {
            // Get challenge details to find the circle
            let challenges: [DBCircleChallenge] = try await supabase
                .from("circle_challenges")
                .select()
                .eq("id", value: challengeUUID)
                .limit(1)
                .execute()
                .value

            guard let challenge = challenges.first else {
                Log.data.warning("[Data] Challenge not found: \(challengeId)")
                return
            }

            // Get completer's display name
            let profile: DBMemberProfile = try await supabase
                .from(Tables.profiles)
                .select("display_name, avatar_url")
                .eq("id", value: completerId)
                .single()
                .execute()
                .value

            let completerName = profile.displayName ?? "Someone"

            // Count completions for progress message
            let completions: [DBChallengeCompletion] = try await supabase
                .from("challenge_completions")
                .select()
                .eq("challenge_id", value: challengeUUID)
                .execute()
                .value

            // Get all circle members except the completer
            let members: [DBCircleMemberWithProfile] = try await supabase
                .from(Tables.circleMembers)
                .select("user_id, profiles(display_name, avatar_url)")
                .eq("circle_id", value: challenge.circleId)
                .neq("user_id", value: completerId)
                .execute()
                .value

            guard !members.isEmpty else { return }

            // Batch send notifications to all members in a single request
            let recipientIds = members.map { $0.userId.uuidString }

            let challengeData: [String: AnyEncodable] = [
                "circleId": AnyEncodable(challenge.circleId.uuidString),
                "senderName": AnyEncodable(completerName),
                "challengeTitle": AnyEncodable(challenge.title),
                "completions": AnyEncodable(completions.count)
            ]

            let challengeNotifyBody: [String: AnyEncodable] = [
                "type": AnyEncodable("challenge"),
                "recipientIds": AnyEncodable(recipientIds),
                "data": AnyEncodable(challengeData)
            ]

            let _: Void = try await supabase.functions.invoke(
                "send-notification-batch",
                options: .init(body: challengeNotifyBody)
            )
        } catch {
            Log.data.error("[Data] Failed to notify challenge completion: \(error)")
        }
    }

    // MARK: - Circle Reactions

    /// Add or update a reaction to a post
    func addReaction(to postId: String, emoji: ReactionEmoji) async throws {
        guard let postUUID = UUID(uuidString: postId) else {
            throw DataError.invalidId
        }

        let reactionData: [String: AnyEncodable] = [
            "post_id": AnyEncodable(postUUID),
            "user_id": AnyEncodable(try userId),
            "emoji": AnyEncodable(emoji.rawValue)
        ]

        try await supabase
            .from("circle_reactions")
            .upsert(reactionData)
            .execute()
    }

    /// Remove reaction from a post
    func removeReaction(from postId: String) async throws {
        guard let postUUID = UUID(uuidString: postId) else {
            throw DataError.invalidId
        }

        try await supabase
            .from("circle_reactions")
            .delete()
            .eq("post_id", value: postUUID)
            .eq("user_id", value: try userId)
            .execute()
    }

    /// Get reactions for a post
    func getReactions(for postId: String) async throws -> [ReactionSummary] {
        guard let postUUID = UUID(uuidString: postId) else {
            throw DataError.invalidId
        }

        let reactions: [DBCircleReaction] = try await supabase
            .from("circle_reactions")
            .select()
            .eq("post_id", value: postUUID)
            .execute()
            .value

        let currentUser = try userId

        // Group reactions by emoji
        var emojiCounts: [String: (count: Int, userReacted: Bool)] = [:]
        for reaction in reactions {
            let key = reaction.emoji
            var entry = emojiCounts[key] ?? (count: 0, userReacted: false)
            entry.count += 1
            if reaction.userId == currentUser {
                entry.userReacted = true
            }
            emojiCounts[key] = entry
        }

        return emojiCounts.map { emoji, data in
            ReactionSummary(emoji: emoji, count: data.count, userReacted: data.userReacted)
        }.sorted { $0.count > $1.count }
    }

    /// Batch fetch reactions for multiple posts (Fix 5: N+1 query optimization)
    func getReactionsForPosts(postIds: [String]) async throws -> [String: [ReactionSummary]] {
        guard !postIds.isEmpty else { return [:] }

        let uuids = postIds.compactMap { UUID(uuidString: $0) }
        guard !uuids.isEmpty else { return [:] }

        let reactions: [DBCircleReaction] = try await supabase
            .from("circle_reactions")
            .select()
            .in("post_id", values: uuids)
            .execute()
            .value

        let currentUser = try userId

        // Group by post_id
        var result: [String: [ReactionSummary]] = [:]
        let grouped = Dictionary(grouping: reactions) { $0.postId.uuidString }

        for (postId, postReactions) in grouped {
            var emojiCounts: [String: (count: Int, userReacted: Bool)] = [:]
            for reaction in postReactions {
                var entry = emojiCounts[reaction.emoji] ?? (count: 0, userReacted: false)
                entry.count += 1
                if reaction.userId == currentUser {
                    entry.userReacted = true
                }
                emojiCounts[reaction.emoji] = entry
            }
            result[postId] = emojiCounts.map {
                ReactionSummary(emoji: $0.key, count: $0.value.count, userReacted: $0.value.userReacted)
            }.sorted { $0.count > $1.count }
        }

        // Initialize empty arrays for posts with no reactions
        for postId in postIds where result[postId] == nil {
            result[postId] = []
        }

        return result
    }

    // MARK: - Circle Invites

    /// Create an invite for a circle
    func createCircleInvite(circleId: String, email: String?, phone: String?) async throws -> CircleInvite {
        guard let circleUUID = UUID(uuidString: circleId) else {
            throw DataError.invalidId
        }

        guard email != nil || phone != nil else {
            throw DataError.missingInviteContact
        }

        // Get the circle's invite code
        let circle: DBCircle = try await supabase
            .from(Tables.circles)
            .select()
            .eq("id", value: circleUUID)
            .single()
            .execute()
            .value

        guard let inviteCode = circle.inviteCode else {
            throw DataError.circleNotFound
        }

        var insertData: [String: AnyEncodable] = [
            "circle_id": AnyEncodable(circleUUID),
            "inviter_id": AnyEncodable(try userId),
            "invite_code": AnyEncodable(inviteCode)
        ]

        if let email = email {
            insertData["invitee_email"] = AnyEncodable(email)
        }
        if let phone = phone {
            insertData["invitee_phone"] = AnyEncodable(phone)
        }

        let result: DBCircleInvite = try await supabase
            .from("circle_invites")
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value

        // TODO: Send invite email/SMS via edge function

        return CircleInvite(
            id: result.id?.uuidString ?? "",
            circleId: result.circleId.uuidString,
            inviterId: result.inviterId.uuidString,
            inviteeEmail: result.inviteeEmail,
            inviteePhone: result.inviteePhone,
            inviteCode: result.inviteCode,
            sentAt: result.sentAt ?? Date(),
            acceptedAt: result.acceptedAt,
            reminderSentAt: result.reminderSentAt,
            inviterName: nil,
            circleName: nil
        )
    }

    /// Get pending invites for a circle
    func getPendingInvites(for circleId: String) async throws -> [CircleInvite] {
        guard let circleUUID = UUID(uuidString: circleId) else {
            throw DataError.invalidId
        }

        let invites: [DBCircleInvite] = try await supabase
            .from("circle_invites")
            .select()
            .eq("circle_id", value: circleUUID)
            .is("accepted_at", value: nil)
            .order("sent_at", ascending: false)
            .execute()
            .value

        return invites.map { invite in
            CircleInvite(
                id: invite.id?.uuidString ?? "",
                circleId: invite.circleId.uuidString,
                inviterId: invite.inviterId.uuidString,
                inviteeEmail: invite.inviteeEmail,
                inviteePhone: invite.inviteePhone,
                inviteCode: invite.inviteCode,
                sentAt: invite.sentAt ?? Date(),
                acceptedAt: invite.acceptedAt,
                reminderSentAt: invite.reminderSentAt,
                inviterName: nil,
                circleName: nil
            )
        }
    }

    // MARK: - Buddy System

    /// Create a buddy invite during onboarding or from home screen
    func createBuddyInvite(contact: String, method: BuddyRelationship.InviteMethod) async throws -> BuddyRelationship {
        // Generate unique invite code via RPC
        let codeResults: [String] = try await supabase
            .rpc("generate_buddy_code")
            .execute()
            .value

        guard let inviteCode = codeResults.first else {
            throw DataError.custom("Failed to generate invite code")
        }

        let insertData: [String: AnyEncodable] = [
            "inviter_id": AnyEncodable(try userId),
            "invite_code": AnyEncodable(inviteCode),
            "invite_method": AnyEncodable(method.rawValue),
            "invitee_contact": AnyEncodable(contact),
            "status": AnyEncodable("pending"),
            "expires_at": AnyEncodable(Date().addingTimeInterval(30 * 24 * 60 * 60)) // 30 days
        ]

        let result: DBBuddyRelationship = try await supabase
            .from("buddy_relationships")
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value

        // Send invite via edge function
        do {
            try await supabase.functions.invoke("send-buddy-invite", options: .init(body: [
                "relationshipId": result.id?.uuidString ?? "",
                "contact": contact,
                "method": method.rawValue
            ]))
        } catch {
            Log.data.warning("[Data] Failed to send buddy invite: \(error)")
            // Don't fail - invite is created, just not sent
        }

        Analytics.shared.track(.buddyInviteSent, properties: [
            "method": method.rawValue
        ])

        return result.toBuddyRelationship(currentUserId: try userId)
    }

    /// Accept a buddy invite using the invite code
    func acceptBuddyInvite(code: String) async throws -> BuddyRelationship {
        let currentUserId = try userId
        let results: [DBBuddyRelationship] = try await supabase
            .rpc("accept_buddy_invite", params: [
                "p_invite_code": AnyEncodable(code.uppercased()),
                "p_user_id": AnyEncodable(currentUserId)
            ])
            .execute()
            .value

        guard let relationship = results.first else {
            throw DataError.custom("Invalid or expired invite code")
        }

        Analytics.shared.track(.buddyInviteAccepted)

        return relationship.toBuddyRelationship(currentUserId: currentUserId)
    }

    /// Get all buddy relationships for current user (active only)
    func getBuddyRelationships() async throws -> [BuddyRelationship] {
        let currentUserId = try userId

        let relationships: [DBBuddyRelationshipWithProfiles] = try await supabase
            .from("buddy_relationships")
            .select("*, buddy_profile:profiles!buddy_id(id, display_name, current_streak_days, last_active_at)")
            .or("user_id.eq.\(currentUserId),buddy_id.eq.\(currentUserId)")
            .eq("status", value: "accepted")
            .execute()
            .value

        return relationships.map { $0.toBuddyRelationship(currentUserId: currentUserId) }
    }

    /// Get buddy widget data for home screen
    func getBuddyWidgetData() async throws -> BuddyWidgetData? {
        let results: [DBBuddyWidgetData] = try await supabase
            .rpc("get_buddy_widget_data", params: [
                "p_user_id": try userId
            ])
            .execute()
            .value

        guard let data = results.first, data.buddyId != nil else {
            return nil
        }

        return BuddyWidgetData(
            buddyName: data.buddyName ?? "Buddy",
            buddyStreak: data.buddyStreak ?? 0,
            buddyId: data.buddyId.uuidString,
            relationshipId: data.relationshipId?.uuidString ?? "",
            hasCompletedToday: data.hasCompletedToday ?? false,
            needsCheckIn: data.needsCheckIn ?? false,
            lastEncouragementId: data.lastEncouragementId?.uuidString,
            lastEncouragementType: data.lastEncouragementType,
            lastEncouragementAt: data.lastEncouragementAt
        )
    }

    /// Send encouragement to buddy
    func sendEncouragement(to buddyId: String, relationshipId: String, type: BuddyEncouragement.MessageType) async throws {
        guard let buddyUUID = UUID(uuidString: buddyId),
              let relationshipUUID = UUID(uuidString: relationshipId) else {
            throw DataError.invalidId
        }

        let insertData: [String: AnyEncodable] = [
            "buddy_relationship_id": AnyEncodable(relationshipUUID),
            "sender_id": AnyEncodable(try userId),
            "recipient_id": AnyEncodable(buddyUUID),
            "message_type": AnyEncodable(type.rawValue)
        ]

        try await supabase
            .from("buddy_encouragements")
            .insert(insertData)
            .execute()

        // Notify buddy via push notification
        do {
            try await supabase.functions.invoke("send-notification", options: .init(body: [
                "type": AnyEncodable("buddy_encouragement"),
                "recipientId": AnyEncodable(buddyId),
                "data": AnyEncodable(["messageType": type.rawValue])
            ]))
        } catch {
            Log.data.warning("[Data] Failed to send encouragement notification: \(error)")
        }

        Analytics.shared.track(.buddyEncouragementSent, properties: [
            "type": type.rawValue
        ])
    }

    /// Mark encouragement as seen
    func markEncouragementSeen(id: String) async throws {
        guard let encouragementUUID = UUID(uuidString: id) else {
            throw DataError.invalidId
        }

        try await supabase
            .from("buddy_encouragements")
            .update(["seen_at": AnyEncodable(Date())])
            .eq("id", value: encouragementUUID)
            .execute()
    }

    /// Get pending (unaccepted) buddy invites sent by current user
    func getPendingBuddyInvites() async throws -> [BuddyRelationship] {
        let currentUserId = try userId

        let relationships: [DBBuddyRelationship] = try await supabase
            .from("buddy_relationships")
            .select()
            .eq("user_id", value: currentUserId)
            .eq("status", value: "pending")
            .execute()
            .value

        return relationships
            .filter { rel in
                guard let expiresAt = rel.expiresAt else { return true }
                return expiresAt > Date()
            }
            .map { $0.toBuddyRelationship(currentUserId: currentUserId) }
    }

    // MARK: - Partner Mode (Couples)

    /// Get active partner link for current user
    func getActivePartnerLink() async throws -> PartnerLink? {
        let currentUserId = try userId

        let links: [PartnerLink] = try await supabase
            .from("partner_links")
            .select()
            .or("user_id_1.eq.\(currentUserId),user_id_2.eq.\(currentUserId)")
            .eq("status", value: "active")
            .limit(1)
            .execute()
            .value

        return links.first
    }

    /// Get or create an invite code (returns existing unexpired code if available)
    func getOrCreatePartnerInviteCode() async throws -> (code: String, expiresAt: Date) {
        let currentUserId = try userId

        // Check for existing pending invite
        let existing: [DBBuddyRelationship] = try await supabase
            .from("buddy_relationships")
            .select()
            .eq("inviter_id", value: currentUserId)
            .eq("status", value: "pending")
            .gt("expires_at", value: Date().ISO8601Format())
            .order("invited_at", ascending: false)
            .limit(1)
            .execute()
            .value

        if let existingInvite = existing.first,
           let expiresAt = existingInvite.expiresAt,
           let inviteCode = existingInvite.inviteCode {
            return (inviteCode, expiresAt)
        }

        // Generate new code via RPC
        let codeResults: [String] = try await supabase
            .rpc("generate_buddy_code")
            .execute()
            .value

        guard let code = codeResults.first else {
            throw DataError.custom("Failed to generate invite code")
        }

        // Create buddy relationship row
        let expiresAt = Date().addingTimeInterval(30 * 24 * 60 * 60) // 30 days
        let insertData: [String: AnyEncodable] = [
            "inviter_id": AnyEncodable(currentUserId),
            "invite_code": AnyEncodable(code),
            "invite_method": AnyEncodable("link"),
            "status": AnyEncodable("pending"),
            "expires_at": AnyEncodable(expiresAt)
        ]

        try await supabase
            .from("buddy_relationships")
            .insert(insertData)
            .execute()

        Analytics.shared.track(.buddyInviteSent, properties: [
            "method": "link",
            "source": "partner_mode"
        ])

        return (code, expiresAt)
    }

    /// Update current user's sharing settings
    func updatePartnerSharingSettings(shareMood: Bool, shareExercises: Bool) async throws {
        guard let link = try await getActivePartnerLink() else {
            throw CouplesModeError.notPartnered
        }

        let currentUserId = try userId
        let isUser1 = link.userId1 == currentUserId

        let updateData: [String: AnyEncodable] = isUser1
            ? ["user_1_share_mood": AnyEncodable(shareMood),
               "user_1_share_exercises": AnyEncodable(shareExercises),
               "updated_at": AnyEncodable(Date())]
            : ["user_2_share_mood": AnyEncodable(shareMood),
               "user_2_share_exercises": AnyEncodable(shareExercises),
               "updated_at": AnyEncodable(Date())]

        try await supabase
            .from("partner_links")
            .update(updateData)
            .eq("id", value: link.id)
            .execute()
    }

    /// End current partnership
    func endPartnership() async throws {
        guard let link = try await getActivePartnerLink() else {
            throw CouplesModeError.notPartnered
        }

        try await supabase
            .from("partner_links")
            .update([
                "status": AnyEncodable("ended"),
                "ended_at": AnyEncodable(Date())
            ])
            .eq("id", value: link.id)
            .execute()
    }

    /// Get partner's mood history (respects sharing settings)
    func getPartnerMoodHistory(partnerId: UUID) async throws -> [MoodEntry] {
        guard let link = try await getActivePartnerLink() else {
            throw CouplesModeError.notPartnered
        }

        let currentUserId = try userId
        let partnerSettings = link.partnerSharingSettings(for: currentUserId)

        guard partnerSettings.shareMood else {
            throw CouplesModeError.partnerNotSharing
        }

        // Get moods from past 7 days
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let startDate = dateFormatter.string(from: sevenDaysAgo)

        let moods: [DBMood] = try await supabase
            .from("moods")
            .select()
            .eq("user_id", value: partnerId)
            .gte("local_date", value: startDate)
            .order("local_date", ascending: false)
            .limit(7)
            .execute()
            .value

        return moods.map { $0.toMoodEntry() }
    }

    /// Get partner's today's quest status (respects sharing settings)
    func getPartnerQuestStatus(partnerId: UUID) async throws -> Quest? {
        guard let link = try await getActivePartnerLink() else {
            throw CouplesModeError.notPartnered
        }

        let currentUserId = try userId
        let partnerSettings = link.partnerSharingSettings(for: currentUserId)

        guard partnerSettings.shareExercises else {
            throw CouplesModeError.partnerNotSharing
        }

        // Note: This query doesn't fetch the template, so we can't construct a full Quest object
        // The function signature should probably return DBQuest or change to fetch with template
        return nil
    }

    /// Get partner info for dashboard
    func getPartnerInfo() async throws -> PartnerInfo? {
        guard let link = try await getActivePartnerLink() else {
            return nil
        }

        let currentUserId = try userId
        guard let partnerId = link.partnerId(for: currentUserId) else {
            return nil
        }

        // Get partner profile
        let profiles: [DBProfile] = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: partnerId)
            .limit(1)
            .execute()
            .value

        guard let partnerProfile = profiles.first else {
            return nil
        }

        // Check if partner completed quest today
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())

        let todayQuests: [DBQuest] = try await supabase
            .from("quests")
            .select()
            .eq("user_id", value: partnerId)
            .eq("local_date", value: today)
            .eq("status", value: "completed")
            .limit(1)
            .execute()
            .value

        let hasCompletedToday = !todayQuests.isEmpty

        // Get partner's sharing settings (what they share with us)
        let partnerSettings = link.partnerSharingSettings(for: currentUserId)

        return PartnerInfo(
            partnerId: partnerId,
            partnerName: partnerProfile.displayName ?? "Partner",
            partnerStreak: partnerProfile.currentStreakDays ?? 0,
            hasCompletedToday: hasCompletedToday,
            lastActive: partnerProfile.lastActiveAt ?? partnerProfile.createdAt,
            isSharingMood: partnerSettings.shareMood,
            isSharingExercises: partnerSettings.shareExercises
        )
    }

    /// Get list of couples exercises
    func getCouplesExercises() async throws -> [CouplesExercise] {
        let exercises: [CouplesExercise] = try await supabase
            .from("couples_exercises")
            .select()
            .order("type")
            .order("name")
            .execute()
            .value

        return exercises
    }

    /// Start a couples exercise session
    func startCouplesSession(exerciseId: UUID) async throws -> CouplesExerciseSession {
        guard let link = try await getActivePartnerLink() else {
            throw CouplesModeError.notPartnered
        }

        let currentUserId = try userId
        guard let partnerId = link.partnerId(for: currentUserId) else {
            throw CouplesModeError.notPartnered
        }

        // Check if exercise requires premium
        let exercises: [CouplesExercise] = try await supabase
            .from("couples_exercises")
            .select()
            .eq("id", value: exerciseId)
            .execute()
            .value

        guard let exercise = exercises.first else {
            throw CouplesModeError.notFound
        }

        if exercise.requiresPremium {
            // TODO: Check if either user has premium entitlement
            throw CouplesModeError.exercisePremiumOnly
        }

        let isUser1 = link.userId1 == currentUserId

        let insertData: [String: AnyEncodable] = [
            "partner_link_id": AnyEncodable(link.id),
            "exercise_id": AnyEncodable(exerciseId),
            "user_id_1": AnyEncodable(isUser1 ? currentUserId : partnerId),
            "user_id_2": AnyEncodable(isUser1 ? partnerId : currentUserId),
            "status": AnyEncodable("pending"),
            "user_1_progress_percent": AnyEncodable(0),
            "user_2_progress_percent": AnyEncodable(0),
            "started_at": AnyEncodable(Date()),
            "last_activity_at": AnyEncodable(Date())
        ]

        let session: CouplesExerciseSession = try await supabase
            .from("couples_exercise_sessions")
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value

        // Send notification to partner
        do {
            try await supabase.functions.invoke("send-notification", options: .init(body: [
                "type": AnyEncodable("couples_exercise_invite"),
                "recipientId": AnyEncodable(partnerId.uuidString),
                "data": AnyEncodable(["sessionId": session.id.uuidString, "exerciseName": exercise.name])
            ]))
        } catch {
            Log.data.warning("[Data] Failed to send exercise invite notification: \(error)")
        }

        return session
    }

    /// Send encouragement to partner with rate limiting
    func sendPartnerEncouragement(type: BuddyEncouragement.MessageType) async throws {
        // Check local rate limit (1 per hour)
        let buddyData = try await getBuddyWidgetData()
        guard let data = buddyData else {
            throw CouplesModeError.notPartnered
        }

        let lastSendKey = "lastEncouragement_\(data.relationshipId)"
        if let lastSend = UserDefaults.standard.object(forKey: lastSendKey) as? Date,
           Date().timeIntervalSince(lastSend) < 3600 {
            let remaining = Int(3600 - Date().timeIntervalSince(lastSend))
            throw CouplesModeError.rateLimited(retryAfterSeconds: remaining)
        }

        // Send via existing method
        try await sendEncouragement(to: data.buddyId, relationshipId: data.relationshipId, type: type)

        // Update rate limit cache
        UserDefaults.standard.set(Date(), forKey: lastSendKey)
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

    func registerDevice(apnsToken: String) async throws {
        let device = DBDevice(
            id: nil,
            userId: try userId,
            deviceToken: apnsToken,
            platform: "ios",
            createdAt: nil,
            updatedAt: Date()
        )

        try await supabase
            .from(Tables.pushTokens)
            .upsert(device, onConflict: "user_id,device_token")
            .execute()
    }

    // MARK: - User Settings

    /// Get current user settings
    func getUserSettings() async throws -> UserSettings {
        guard let userId = supabase.auth.currentUser?.id else {
            throw DataError.notAuthenticated
        }
        
        let profiles: [DBProfile] = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value
        
        guard let profile = profiles.first else {
            throw DataError.operationFailed("User settings not available")
        }
        
        // Convert aiTone string to enum with fallback
        let aiTone = AITone(rawValue: profile.aiTone) ?? .friendly
        
        // Convert privacyMode string to enum with fallback
        let privacyMode = PrivacyMode(rawValue: profile.privacyMode) ?? .standard
        
        // Construct UserSettings from DBProfile fields
        return UserSettings(
            dailyQuestTimeLocal: profile.dailyQuestTimeLocal,
            quietHoursStartLocal: profile.quietHoursStartLocal,
            quietHoursEndLocal: profile.quietHoursEndLocal,
            remindersEnabled: profile.remindersEnabled,
            nudgeAfterDaysInactive: profile.nudgeAfterDaysInactive,
            shareMoodInCircles: profile.shareMoodInCircles,
            aiTone: aiTone,
            privacyMode: privacyMode
        )
    }

    /// Update user settings with a UserSettings object
    func updateUserSettings(_ settings: UserSettings) async throws {
        try await updateUserSettings(
            dailyQuestTimeLocal: settings.dailyQuestTimeLocal,
            quietHoursStartLocal: settings.quietHoursStartLocal,
            quietHoursEndLocal: settings.quietHoursEndLocal,
            remindersEnabled: settings.remindersEnabled,
            nudgeAfterDaysInactive: settings.nudgeAfterDaysInactive,
            shareMoodInCircles: settings.shareMoodInCircles,
            aiTone: settings.aiTone,
            privacyMode: settings.privacyMode
        )
    }

    /// Update all user settings including notifications, reminders, AI preferences, and privacy
    func updateUserSettings(
        dailyQuestTimeLocal: String? = nil,
        quietHoursStartLocal: String? = nil,
        quietHoursEndLocal: String? = nil,
        remindersEnabled: Bool? = nil,
        notifyCircleActivity: Bool? = nil,
        notifyHugs: Bool? = nil,
        notifyChallenges: Bool? = nil,
        notifyStreakRisk: Bool? = nil,
        notifyWeeklySummary: Bool? = nil,
        preferredNotifyHour: Int? = nil,
        nudgeAfterDaysInactive: Int? = nil,
        shareMoodInCircles: Bool? = nil,
        aiTone: AITone? = nil,
        privacyMode: PrivacyMode? = nil
    ) async throws {
        var updates: [String: AnyEncodable] = [:]

        if let dailyQuestTimeLocal = dailyQuestTimeLocal {
            updates["daily_quest_time_local"] = AnyEncodable(dailyQuestTimeLocal)
        }
        if let quietHoursStartLocal = quietHoursStartLocal {
            updates["quiet_hours_start_local"] = AnyEncodable(quietHoursStartLocal)
        }
        if let quietHoursEndLocal = quietHoursEndLocal {
            updates["quiet_hours_end_local"] = AnyEncodable(quietHoursEndLocal)
        }
        if let remindersEnabled = remindersEnabled {
            updates["reminders_enabled"] = AnyEncodable(remindersEnabled)
        }
        if let notifyCircleActivity = notifyCircleActivity {
            updates["notify_circle_activity"] = AnyEncodable(notifyCircleActivity)
        }
        if let notifyHugs = notifyHugs {
            updates["notify_hugs"] = AnyEncodable(notifyHugs)
        }
        if let notifyChallenges = notifyChallenges {
            updates["notify_challenges"] = AnyEncodable(notifyChallenges)
        }
        if let notifyStreakRisk = notifyStreakRisk {
            updates["notify_streak_risk"] = AnyEncodable(notifyStreakRisk)
        }
        if let notifyWeeklySummary = notifyWeeklySummary {
            updates["notify_weekly_summary"] = AnyEncodable(notifyWeeklySummary)
        }
        if let preferredNotifyHour = preferredNotifyHour {
            updates["preferred_notify_hour"] = AnyEncodable(preferredNotifyHour)
        }
        if let nudgeAfterDaysInactive = nudgeAfterDaysInactive {
            updates["nudge_after_days_inactive"] = AnyEncodable(nudgeAfterDaysInactive)
        }
        if let shareMoodInCircles = shareMoodInCircles {
            updates["share_mood_in_circles"] = AnyEncodable(shareMoodInCircles)
        }
        if let aiTone = aiTone {
            updates["ai_tone"] = AnyEncodable(aiTone.rawValue)
        }
        if let privacyMode = privacyMode {
            updates["privacy_mode"] = AnyEncodable(privacyMode.rawValue)
        }

        guard !updates.isEmpty else { return }

        try await supabase
            .from(Tables.userSettings)
            .update(updates)
            .eq("user_id", value: try userId)
            .execute()

        Analytics.shared.track(.settingsChanged)
    }

    // MARK: - Smart Notifications

    /// Update notification preferences
    func updateNotificationSettings(
        circleActivity: Bool? = nil,
        hugs: Bool? = nil,
        challenges: Bool? = nil,
        streakRisk: Bool? = nil,
        weeklySummary: Bool? = nil,
        preferredNotifyHour: Int? = nil,
        quietHoursStart: String? = nil,
        quietHoursEnd: String? = nil
    ) async throws {
        var updates: [String: AnyEncodable] = [:]

        if let circleActivity = circleActivity {
            updates["notify_circle_activity"] = AnyEncodable(circleActivity)
        }
        if let hugs = hugs {
            updates["notify_hugs"] = AnyEncodable(hugs)
        }
        if let challenges = challenges {
            updates["notify_challenges"] = AnyEncodable(challenges)
        }
        if let streakRisk = streakRisk {
            updates["notify_streak_risk"] = AnyEncodable(streakRisk)
        }
        if let weeklySummary = weeklySummary {
            updates["notify_weekly_summary"] = AnyEncodable(weeklySummary)
        }
        if let preferredNotifyHour = preferredNotifyHour {
            updates["preferred_notify_hour"] = AnyEncodable(preferredNotifyHour)
        }
        if let quietHoursStart = quietHoursStart {
            updates["quiet_hours_start_local"] = AnyEncodable(quietHoursStart)
        }
        if let quietHoursEnd = quietHoursEnd {
            updates["quiet_hours_end_local"] = AnyEncodable(quietHoursEnd)
        }

        guard !updates.isEmpty else { return }

        try await supabase
            .from(Tables.userSettings)
            .update(updates)
            .eq("user_id", value: try userId)
            .execute()

        Analytics.shared.track(.notificationSettingsUpdated)
    }

    /// Mark a notification as opened (for analytics)
    func markNotificationOpened(notificationId: String) async throws {
        guard let notifId = UUID(uuidString: notificationId) else {
            throw DataError.invalidId
        }

        let now = ISO8601DateFormatter().string(from: Date())

        try await supabase
            .from("notification_history")
            .update([
                "status": "opened",
                "opened_at": now
            ])
            .eq("id", value: notifId)
            .eq("user_id", value: try userId)
            .execute()

        Analytics.shared.track(.notificationOpened, properties: [
            "notification_id": notificationId
        ])
    }

    // MARK: - Notification Engagement (Smart Notifications) - DISABLED
    // TODO: Re-enable when SmartNotification feature types are complete

    /// Update typical active hour based on app open time (rolling average)
    func updateTypicalActiveHour() async throws {
        let currentHour = Calendar.current.component(.hour, from: Date())

        // Call the database function that handles the rolling average
        try await supabase
            .rpc("update_typical_active_hour", params: [
                "p_user_id": AnyEncodable(try userId),
                "p_hour": AnyEncodable(currentHour)
            ])
            .execute()
    }

    /// Get the current week's summary with insights
    func getWeeklySummary() async throws -> WeeklySummary? {
        // Calculate week start (Monday of current week)
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        // weekday 1 = Sunday, 2 = Monday, etc.
        let daysFromMonday = (weekday == 1) ? 6 : weekday - 2
        guard let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: now) else {
            Log.data.error("Failed to calculate week start")
            return nil
        }
        let weekStartStr = DateFormatter.dateOnly.string(from: weekStart)

        Log.data.info("Fetching weekly summary for week_start: \(weekStartStr)")

        let summaries: [DBWeeklySummary] = try await supabase
            .from("weekly_summaries")
            .select()
            .eq("user_id", value: try userId)
            .eq("week_start", value: weekStartStr)
            .limit(1)
            .execute()
            .value

        Log.data.info("Weekly summaries found: \(summaries.count)")

        if summaries.isEmpty {
            // Debug: Try fetching any summary to see if any exist
            let anySummaries: [DBWeeklySummary] = try await supabase
                .from("weekly_summaries")
                .select()
                .eq("user_id", value: try userId)
                .order("week_start", ascending: false)
                .limit(3)
                .execute()
                .value
            Log.data.info("Any summaries in DB: \(anySummaries.count), week_starts: \(anySummaries.map { $0.weekStart })")
        }

        guard let summary = summaries.first else {
            return nil
        }

        return summary.toWeeklySummary()
    }

    /// Get insights history (past weeks' summaries)
    func getInsightsHistory(limit: Int = 12) async throws -> [WeeklySummary] {
        let summaries: [DBWeeklySummary] = try await supabase
            .from("weekly_summaries")
            .select()
            .eq("user_id", value: try userId)
            .order("week_start", ascending: false)
            .limit(limit)
            .execute()
            .value

        return summaries.map { $0.toWeeklySummary() }
    }

    /// Get a specific week's insight by week start date
    func getInsightForWeek(weekStart: String) async throws -> WeeklySummary? {
        let summaries: [DBWeeklySummary] = try await supabase
            .from("weekly_summaries")
            .select()
            .eq("user_id", value: try userId)
            .eq("week_start", value: weekStart)
            .limit(1)
            .execute()
            .value

        return summaries.first?.toWeeklySummary()
    }

    /// Generate weekly insight on-demand for the current user
    /// Calls the generate-weekly-summary Edge Function which will calculate
    /// stats, detect patterns, and generate AI insights
    func generateWeeklyInsight() async throws -> WeeklySummary? {
        // Validate and refresh session if needed
        do {
            try await authService.ensureValidSession()
        } catch {
            Log.data.warning("[WeeklyInsight] Session validation failed: \(error)")
            throw APIError.badRequest("Session expired. Please sign in again.")
        }

        // Get the refreshed access token
        guard let accessToken = authService.session?.accessToken else {
            Log.data.warning("[WeeklyInsight] No access token after refresh")
            throw APIError.badRequest("Session expired. Please sign in again.")
        }

        Log.data.info("Calling generate-weekly-summary edge function...")

        // Invoke the Edge Function with explicit auth header (SDK doesn't auto-include it)
        try await supabase.functions.invoke(
            "generate-weekly-summary",
            options: .init(
                headers: ["Authorization": "Bearer \(accessToken)"]
            )
        )

        Log.data.info("Edge function completed successfully")

        // After successful generation, fetch the newly created summary
        let summary = try await getWeeklySummary()
        Log.data.info("Fetched summary after generation: \(summary != nil ? "found" : "nil")")
        return summary
    }

    // MARK: - Data Export

    func exportUserData() async throws -> UserDataExport {
        let currentUserId = try userId
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        // Fetch profile
        let profile: DBProfile = try await supabase
            .from(Tables.profiles)
            .select()
            .eq("id", value: currentUserId)
            .single()
            .execute()
            .value

        // Settings are embedded in profile (DBProfile has all settings fields)
        // No need for separate fetch

        // Fetch moods
        let moods: [DBMood] = try await supabase
            .from(Tables.moods)
            .select()
            .eq("user_id", value: currentUserId)
            .order("created_at", ascending: false)
            .execute()
            .value

        // Fetch quests with template info for export
        let quests: [DBQuestWithTemplate] = try await supabase
            .from(Tables.quests)
            .select("*, quest_templates(*)")
            .eq("user_id", value: currentUserId)
            .order("assigned_at", ascending: false)
            .execute()
            .value

        // Fetch conversations with messages
        let conversations: [DBConversation] = try await supabase
            .from(Tables.conversations)
            .select()
            .eq("user_id", value: currentUserId)
            .order("created_at", ascending: false)
            .execute()
            .value

        var conversationExports: [UserDataExport.ConversationExportData] = []
        for conv in conversations {
            let messages: [DBMessage] = try await supabase
                .from(Tables.messages)
                .select()
                .eq("conversation_id", value: conv.id ?? UUID())
                .order("created_at", ascending: true)
                .execute()
                .value

            conversationExports.append(UserDataExport.ConversationExportData(
                id: conv.id?.uuidString ?? "",
                title: conv.title,
                createdAt: conv.createdAt.map { formatter.string(from: $0) } ?? "",
                messages: messages.map { msg in
                    UserDataExport.MessageExportData(
                        role: msg.role,
                        content: msg.content,
                        createdAt: msg.createdAt.map { formatter.string(from: $0) } ?? ""
                    )
                }
            ))
        }

        // Fetch circle memberships
        let memberships: [DBCircleMembership] = try await supabase
            .from(Tables.circleMembers)
            .select("*, circles(*)")
            .eq("user_id", value: currentUserId)
            .execute()
            .value

        // Fetch exercise sessions with exercise details
        let sessions: [DBExerciseSessionForExport] = try await supabase
            .from(Tables.exerciseSessions)
            .select("*, exercises(*)")
            .eq("user_id", value: currentUserId)
            .order("completed_at", ascending: false)
            .execute()
            .value

        // EXE-010: Fetch subscription data
        let subscription: DBSubscriptionForExport? = try? await supabase
            .from(Tables.subscriptions)
            .select()
            .eq("user_id", value: currentUserId)
            .single()
            .execute()
            .value

        // EXE-010: Fetch crisis events (keyword + timestamp only for privacy)
        let crisisEvents: [DBCrisisEventForExport] = try await supabase
            .from(Tables.crisisEvents)
            .select("id, user_id, trigger_content, detected_at")
            .eq("user_id", value: currentUserId)
            .order("detected_at", ascending: false)
            .execute()
            .value

        return UserDataExport(
            exportedAt: formatter.string(from: Date()),
            user: UserDataExport.UserExportData(
                id: currentUserId.uuidString,
                handle: profile.handle ?? "",
                displayName: profile.displayName ?? "User",
                email: profile.email,
                timezone: profile.timezone,
                createdAt: formatter.string(from: profile.createdAt)
            ),
            settings: UserDataExport.SettingsExportData(
                notificationsEnabled: profile.remindersEnabled,
                quietHoursStart: profile.quietHoursStartLocal,
                quietHoursEnd: profile.quietHoursEndLocal,
                privacyMode: profile.privacyMode == "strict",  // Convert String to Bool
                aiTone: profile.aiTone
            ),
            moods: moods.map { m in
                UserDataExport.MoodExportData(
                    date: m.localDate,
                    moodScore: m.moodScore,
                    anxietyScore: m.anxietyScore,
                    energyScore: m.energyScore,
                    notes: m.note,  // DBMood uses 'note' singular
                    tags: nil       // Tags not stored in DB, export as nil
                )
            },
            quests: quests.map { q in
                UserDataExport.QuestExportData(
                    id: q.id.uuidString,
                    title: q.questTemplates?.title ?? "Unknown Quest",
                    assignedAt: q.assignedAt.map { formatter.string(from: $0) } ?? "",
                    completedAt: q.completedAt.map { formatter.string(from: $0) },
                    status: q.status
                )
            },
            conversations: conversationExports,
            circles: memberships.map { m in
                UserDataExport.CircleExportData(
                    id: m.circleId.uuidString,
                    name: m.circles?.name ?? "Unknown Circle",
                    role: m.role ?? "member",
                    joinedAt: m.joinedAt.map { formatter.string(from: $0) } ?? ""
                )
            },
            exerciseSessions: sessions.map { s in
                UserDataExport.ExerciseSessionExportData(
                    exerciseName: s.exercises?.title ?? "Unknown Exercise",
                    exerciseType: s.exercises?.type ?? "unknown",
                    completedAt: s.completedAt.map { formatter.string(from: $0) } ?? "",
                    durationSeconds: s.durationSeconds ?? 0
                )
            },
            // EXE-010: Include subscription data in export
            subscription: {
                if let s = subscription {
                    return UserDataExport.SubscriptionExportData(
                        productId: s.productId ?? s.tier,
                        planType: s.planType ?? s.tier,
                        billingPeriod: s.billingPeriod ?? "unknown",
                        status: s.status,
                        expiresAt: s.expiresAt.map { formatter.string(from: $0) },
                        createdAt: (s.createdAt ?? s.startedAt).map { formatter.string(from: $0) }
                    )
                }
                return nil
            }(),
            // EXE-010: Include crisis events in export (keyword + timestamp only for privacy)
            crisisEvents: crisisEvents.map { e in
                UserDataExport.CrisisEventExportData(
                    triggerKeyword: e.triggerWords?.first ?? "unknown",
                    detectedAt: e.createdAt.map { formatter.string(from: $0) } ?? ""
                )
            }
        )
    }

    // MARK: - Memory Management

    func getMemories() async throws -> [MemoryFragment] {
        let now = ISO8601DateFormatter().string(from: Date())

        // Fetch expired memories at database level for efficiency
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

        // Fetch expired memories at database level for efficiency
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
        Log.data.debug("[Data] Updating wellness focus to '\(focus.rawValue)' for user: \(currentUserId)")

        try await supabase
            .from(Tables.profiles)
            .update(["wellness_focus": focus.rawValue])
            .eq("id", value: currentUserId)
            .execute()

        Log.data.debug("[Data] Wellness focus updated successfully")
        Analytics.shared.track(.onboardingStepCompleted, properties: [
            "step": "quiz",
            "wellness_focus": focus.rawValue
        ])
    }

    /// Mark onboarding as complete for the current user
    func markOnboardingComplete() async throws {
        let currentUserId = try userId
        let now = ISO8601DateFormatter().string(from: Date())
        Log.data.debug("[Data] Marking onboarding complete for user: \(currentUserId)")

        try await supabase
            .from(Tables.profiles)
            .update(["onboarding_completed_at": now])
            .eq("id", value: currentUserId)
            .execute()

        Log.data.debug("[Data] Onboarding marked complete at: \(now)")
        Analytics.shared.track(.onboardingCompleted)
    }

    /// Complete onboarding in a single atomic operation
    func completeOnboarding(focus: WellnessFocus) async throws {
        let currentUserId = try userId
        let now = ISO8601DateFormatter().string(from: Date())
        Log.data.debug("[Data] Completing onboarding with focus '\(focus.rawValue)' for user: \(currentUserId)")

        // Single atomic update
        try await supabase
            .from(Tables.profiles)
            .update([
                "wellness_focus": focus.rawValue,
                "onboarding_completed_at": now
            ])
            .eq("id", value: currentUserId)
            .execute()

        Log.data.debug("[Data] Onboarding completed successfully")
        Analytics.shared.track(.onboardingStepCompleted, properties: [
            "step": "quiz",
            "wellness_focus": focus.rawValue
        ])
        Analytics.shared.track(.onboardingCompleted)
    }

    // MARK: - XP & Progression

    /// Award XP for completing an activity
    func awardXP(activity: XPActivity) async throws -> XPAward {
        let currentUserId = try userId

        // Call the award_xp RPC function
        let result: [DBXPAwardResult] = try await supabase
            .rpc("award_xp", params: [
                "p_user_id": AnyEncodable(currentUserId),
                "p_amount": AnyEncodable(activity.xpAmount),
                "p_activity_type": AnyEncodable(activity.activityTypeString),
                "p_skill_type": AnyEncodable(activity.skillType)
            ])
            .execute()
            .value

        guard let first = result.first else {
            throw DataError.operationFailed("XP award failed")
        }

        let award = XPAward(
            amount: activity.xpAmount,
            newTotal: first.newXp,
            newLevel: first.newLevel,
            newTitle: first.newTitle,
            leveledUp: first.levelUp
        )

        Analytics.shared.track(.xpAwarded, properties: [
            "amount": activity.xpAmount,
            "activity_type": activity.activityTypeString,
            "new_total": first.newXp,
            "level_up": first.levelUp
        ])

        if award.leveledUp {
            Analytics.shared.track(.levelUp, properties: [
                "new_level": award.newLevel,
                "new_title": award.newTitle
            ])
        }

        return award
    }

    /// Get skill progress for all exercise types
    func getSkillProgress() async throws -> [SkillProgress] {
        let skills: [DBSkillProgress] = try await supabase
            .from(Tables.skillProgress)
            .select()
            .eq("user_id", value: try userId)
            .execute()
            .value

        return skills.compactMap { skill in
            guard let exerciseType = ExerciseType(rawValue: skill.skillType) else { return nil }
            return SkillProgress(
                id: skill.id.uuidString,
                userId: skill.userId.uuidString,
                skillType: exerciseType,
                xp: skill.xp,
                skillLevel: skill.level,
                exercisesCompleted: skill.exercisesCompleted,
                createdAt: skill.createdAt ?? Date(),
                updatedAt: skill.updatedAt ?? Date()
            )
        }
    }

    /// Get currently active seasonal events
    func getActiveEvents() async throws -> [SeasonalEvent] {
        let now = ISO8601DateFormatter.full.string(from: Date())

        let events: [DBSeasonalEvent] = try await supabase
            .from(Tables.seasonalEvents)
            .select()
            .lte("starts_at", value: now)
            .gte("ends_at", value: now)
            .order("ends_at", ascending: true)
            .execute()
            .value

        return events.map { event in
            SeasonalEvent(
                id: event.id.uuidString,
                name: event.name,
                description: event.description,
                startsAt: event.startsAt,
                endsAt: event.endsAt,
                eventType: event.eventType,
                requiredActivityType: event.requiredActivityType,
                rewardBadgeId: event.rewardBadgeId?.uuidString,
                targetCount: event.targetCount,
                xpMultiplier: event.xpMultiplier,
                createdAt: event.createdAt ?? Date()
            )
        }
    }

    /// Join a seasonal event
    func joinEvent(id: String) async throws {
        guard let eventId = UUID(uuidString: id) else {
            throw DataError.invalidId
        }

        try await supabase
            .from(Tables.eventParticipation)
            .insert([
                "user_id": try userId,
                "event_id": eventId
            ])
            .execute()

        Analytics.shared.track(.eventJoined, properties: ["event_id": id])
    }

    /// Get user's event participation records
    func getEventParticipation() async throws -> [EventParticipation] {
        let participations: [DBEventParticipation] = try await supabase
            .from(Tables.eventParticipation)
            .select()
            .eq("user_id", value: try userId)
            .execute()
            .value

        return participations.map { p in
            EventParticipation(
                id: p.id.uuidString,
                userId: p.userId.uuidString,
                eventId: p.eventId.uuidString,
                progress: p.progress,
                completedAt: p.completedAt,
                joinedAt: p.joinedAt ?? Date()
            )
        }
    }

    /// Increment event progress for a completed activity
    func incrementEventProgress(activityType: String) async throws -> [EventProgressUpdate] {
        let currentUserId = try userId

        let results: [DBEventProgressResult] = try await supabase
            .rpc("increment_event_progress", params: [
                "p_user_id": AnyEncodable(currentUserId),
                "p_activity_type": AnyEncodable(activityType)
            ])
            .execute()
            .value

        let updates = results.map { result in
            EventProgressUpdate(
                eventId: result.eventId.uuidString,
                eventName: result.eventName,
                newProgress: result.newProgress,
                targetCount: result.targetCount,
                justCompleted: result.justCompleted
            )
        }

        for update in updates where update.justCompleted {
            Analytics.shared.track(.eventCompleted, properties: [
                "event_id": update.eventId,
                "event_name": update.eventName
            ])
        }

        return updates
    }

    /// Check and reset weekly XP if needed (called on app launch)
    func resetWeeklyXPIfNeeded() async throws -> Bool {
        let result: Bool = try await supabase
            .rpc("reset_weekly_xp_if_needed", params: [
                "p_user_id": try userId
            ])
            .execute()
            .value

        if result {
            Analytics.shared.track(.weeklyXPReset)
        }

        return result
    }

    // MARK: - Re-engagement

    /// Check user absence and get activity summary since last session
    /// Returns nil if user is active (less than 3 days absent)
    func checkUserAbsence() async throws -> AbsenceSummary? {
        let currentUserId = try userId

        struct AbsenceResult: Decodable {
            let absenceDays: Int
            let lapseTier: String
            let hugsReceived: Int
            let circlePosts: Int
            let friendMilestones: [AbsenceSummary.FriendMilestone]

            enum CodingKeys: String, CodingKey {
                case absenceDays = "absence_days"
                case lapseTier = "lapse_tier"
                case hugsReceived = "hugs_received"
                case circlePosts = "circle_posts"
                case friendMilestones = "friend_milestones"
            }
        }

        let results: [AbsenceResult] = try await supabase
            .rpc("calculate_user_absence", params: [
                "p_user_id": AnyEncodable(currentUserId)
            ])
            .execute()
            .value

        guard let result = results.first else { return nil }

        // Only return if user has been absent 3+ days
        guard result.absenceDays >= 3 else { return nil }

        guard let tier = LapseTier(rawValue: result.lapseTier) else {
            return nil
        }

        let summary = AbsenceSummary(
            absenceDays: result.absenceDays,
            lapseTier: tier,
            hugsReceived: result.hugsReceived,
            circlePosts: result.circlePosts,
            friendMilestones: result.friendMilestones
        )

        Analytics.shared.track(.reengagementAbsenceChecked, properties: [
            "absence_days": result.absenceDays,
            "lapse_tier": result.lapseTier,
            "hugs_received": result.hugsReceived,
            "circle_posts": result.circlePosts
        ])

        return summary
    }

    /// Record session start and get previous absence info
    /// Should be called when user opens the app
    func recordSessionStart() async throws -> SessionStartResult {
        let currentUserId = try userId

        struct SessionResult: Decodable {
            let previousAbsenceDays: Int
            let lapseTier: String
            let isReturning: Bool

            enum CodingKeys: String, CodingKey {
                case previousAbsenceDays = "previous_absence_days"
                case lapseTier = "lapse_tier"
                case isReturning = "is_returning"
            }
        }

        let results: [SessionResult] = try await supabase
            .rpc("record_session_start", params: [
                "p_user_id": AnyEncodable(currentUserId)
            ])
            .execute()
            .value

        guard let result = results.first else {
            throw DataError.operationFailed("Session start recording failed")
        }

        let tier = LapseTier(rawValue: result.lapseTier) ?? .active

        Analytics.shared.track(.sessionStarted, properties: [
            "previous_absence_days": result.previousAbsenceDays,
            "lapse_tier": result.lapseTier,
            "is_returning": result.isReturning
        ])

        return SessionStartResult(
            previousAbsenceDays: result.previousAbsenceDays,
            lapseTier: tier,
            isReturning: result.isReturning
        )
    }

    /// Log a re-engagement event for analytics
    func logReengagementEvent(
        type: ReengagementEventType,
        absenceDays: Int,
        metadata: [String: Any] = [:]
    ) async throws {
        let currentUserId = try userId

        // Convert metadata to JSONB-compatible format
        let jsonMetadata = try JSONSerialization.data(withJSONObject: metadata)
        let metadataString = String(data: jsonMetadata, encoding: .utf8) ?? "{}"

        try await supabase
            .from("reengagement_events")
            .insert([
                "user_id": AnyEncodable(currentUserId),
                "event_type": AnyEncodable(type.rawValue),
                "absence_days": AnyEncodable(absenceDays),
                "metadata": AnyEncodable(metadataString)
            ])
            .execute()

        Analytics.shared.track(.reengagementEventLogged, properties: [
            "event_type": type.rawValue,
            "absence_days": absenceDays
        ])
    }

    /// Perform fresh start - resets visible streak but preserves history
    /// User starts at Day 2 as a bonus for coming back
    func performFreshStart() async throws -> FreshStartResult {
        let currentUserId = try userId

        struct FreshResult: Decodable {
            let success: Bool
            let newStreak: Int
            let freshStartBonus: Int

            enum CodingKeys: String, CodingKey {
                case success
                case newStreak = "new_streak"
                case freshStartBonus = "fresh_start_bonus"
            }
        }

        let results: [FreshResult] = try await supabase
            .rpc("perform_fresh_start", params: [
                "p_user_id": AnyEncodable(currentUserId)
            ])
            .execute()
            .value

        guard let result = results.first, result.success else {
            throw DataError.operationFailed("Fresh start failed")
        }

        Analytics.shared.track(.freshStartPerformed, properties: [
            "new_streak": result.newStreak,
            "fresh_start_bonus": result.freshStartBonus
        ])

        return FreshStartResult(
            success: result.success,
            newStreak: result.newStreak,
            freshStartBonus: result.freshStartBonus
        )
    }

    /// Get AI context for re-engagement acknowledgment in chat
    /// Returns context string to inject into AI system prompt
    func getReengagementAIContext(absenceDays: Int, lapseTier: LapseTier) -> String {
        var context = "The user is returning after \(absenceDays) days away. "

        switch lapseTier {
        case .active:
            return "" // No special context needed
        case .briefBreak:
            context += "They took a brief break (3-6 days). Welcome them back warmly but don't make a big deal of it. "
        case .extendedBreak:
            context += "They've been away for about a week (7-13 days). Acknowledge their return positively and gently check in on how they're doing. "
        case .longAbsence:
            context += "They've been away for a while (14-29 days). Be especially warm and supportive. Don't ask why they were away - focus on being glad they're back. "
        case .hiatus:
            context += "They're returning after a long hiatus (30+ days). This is a significant return - be very welcoming and supportive. Help them ease back in without pressure. "
        }

        context += "Do not mention specific day counts. Focus on the present moment and supporting their wellness journey."
        return context
    }

    // MARK: - Proactive Intelligence

    /// Get the user's current engagement state
    func getEngagementState() async throws -> UserEngagementState? {
        let currentUserId = try userId

        let states: [DBUserEngagementState] = try await supabase
            .from(Tables.userEngagementStates)
            .select()
            .eq("user_id", value: currentUserId)
            .limit(1)
            .execute()
            .value

        return states.first?.toModel()
    }

    /// Get detected patterns for the user
    func getUserPatterns(activeOnly: Bool = true) async throws -> [UserPattern] {
        let currentUserId = try userId

        var query = supabase
            .from(Tables.userPatterns)
            .select()
            .eq("user_id", value: currentUserId)

        if activeOnly {
            query = query.eq("is_active", value: true)
        }

        let patterns: [DBUserPattern] = try await query
            .order("confidence", ascending: false)
            .execute()
            .value

        return patterns.map { $0.toModel() }
    }

    /// Get high-confidence patterns that should be surfaced to the user
    func getSurfaceablePatterns() async throws -> [UserPattern] {
        let currentUserId = try userId

        let patterns: [DBUserPattern] = try await supabase
            .from(Tables.userPatterns)
            .select()
            .eq("user_id", value: currentUserId)
            .eq("is_active", value: true)
            .eq("user_acknowledged", value: false)
            .gte("confidence", value: 0.7)
            .order("confidence", ascending: false)
            .execute()
            .value

        return patterns.map { $0.toModel() }
    }

    /// Acknowledge a pattern (mark as seen by user)
    func acknowledgePattern(patternId: String) async throws {
        guard let patternUUID = UUID(uuidString: patternId) else {
            throw DataError.invalidId
        }

        try await supabase
            .rpc("acknowledge_pattern", params: [
                "p_user_id": AnyEncodable(try userId),
                "p_pattern_id": AnyEncodable(patternUUID)
            ])
            .execute()
    }

    /// Get proactive messages for the user
    func getProactiveMessages(status: ProactiveMessageStatus? = nil, limit: Int = 20) async throws -> [ProactiveMessage] {
        let currentUserId = try userId

        var query = supabase
            .from(Tables.proactiveMessages)
            .select()
            .eq("user_id", value: currentUserId)

        if let status = status {
            query = query.eq("status", value: status.rawValue)
        }

        let messages: [DBProactiveMessage] = try await query
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return messages.map { $0.toModel() }
    }

    /// Record engagement with a proactive message
    func recordProactiveEngagement(messageId: String, engaged: Bool) async throws {
        guard let messageUUID = UUID(uuidString: messageId) else {
            throw DataError.invalidId
        }

        let params: [String: AnyEncodable] = [
            "p_user_id": AnyEncodable(try userId),
            "p_message_id": AnyEncodable(messageUUID),
            "p_engaged": AnyEncodable(engaged)
        ]

        try await supabase
            .rpc("record_proactive_engagement", params: params)
            .execute()
    }

    /// Get the user's proactive settings
    func getProactiveSettings() async throws -> ProactiveSettings {
        let currentUserId = try userId

        let settings: [DBProactiveSettings] = try await supabase
            .from(Tables.userSettings)
            .select("proactive_enabled, proactive_max_daily, proactive_types_enabled, calendar_integration_enabled, weather_insights_enabled")
            .eq("user_id", value: currentUserId)
            .limit(1)
            .execute()
            .value

        return settings.first?.toModel() ?? ProactiveSettings.default
    }

    /// Update the user's proactive settings
    func updateProactiveSettings(_ settings: ProactiveSettings) async throws {
        let currentUserId = try userId

        let typesEnabled = settings.proactiveTypesEnabled.map { $0.rawValue }

        let updates: [String: AnyEncodable] = [
            "proactive_enabled": AnyEncodable(settings.proactiveEnabled),
            "proactive_max_daily": AnyEncodable(settings.proactiveMaxDaily),
            "proactive_types_enabled": AnyEncodable(typesEnabled),
            "calendar_integration_enabled": AnyEncodable(settings.calendarIntegrationEnabled),
            "weather_insights_enabled": AnyEncodable(settings.weatherInsightsEnabled)
        ]

        try await supabase
            .from(Tables.userSettings)
            .update(updates)
            .eq("user_id", value: currentUserId)
            .execute()
    }

    /// Toggle a specific proactive trigger type
    func toggleProactiveTriggerType(_ triggerType: ProactiveTriggerType, enabled: Bool) async throws {
        let currentSettings = try await getProactiveSettings()
        var typesEnabled = currentSettings.proactiveTypesEnabled

        if enabled && !typesEnabled.contains(triggerType) {
            typesEnabled.append(triggerType)
        } else if !enabled {
            typesEnabled.removeAll { $0 == triggerType }
        }

        var newSettings = currentSettings
        newSettings.proactiveTypesEnabled = typesEnabled
        try await updateProactiveSettings(newSettings)
    }

    // MARK: - Helpers

    private func generateInviteCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    /// Checks if an error is a PostgreSQL unique constraint violation (error code 23505).
    /// Used for retry logic when generating unique codes (invite codes, etc.)
    /// Internal visibility for testability.
    func isUniqueConstraintViolation(_ error: Error) -> Bool {
        let errorString = String(describing: error).lowercased()
        return errorString.contains("23505") ||
               errorString.contains("unique") ||
               errorString.contains("duplicate key")
    }

    // MARK: - Celebrations

    /// Get pending celebrations that haven't been shown to the user yet
    func getPendingCelebrations() async throws -> [CelebrationEvent] {
        let currentUserId = try userId

        let pending: [PendingCelebration] = try await supabase
            .rpc("get_pending_celebrations", params: ["p_user_id": currentUserId])
            .execute()
            .value

        return pending.map { $0.toCelebrationEvent(userId: currentUserId) }
    }

    /// Mark a celebration as shown to the user
    func markCelebrationShown(celebrationId: UUID) async throws {
        try await supabase
            .rpc("mark_celebration_shown", params: ["p_celebration_id": celebrationId])
            .execute()
    }

    /// Share a celebration to the user's circles
    /// Returns the circle post ID if successful
    func shareCelebrationToCircles(celebrationId: UUID) async throws -> UUID? {
        struct ShareResult: Codable {
            let shareToCircles: UUID?

            enum CodingKeys: String, CodingKey {
                case shareToCircles = "share_celebration_to_circles"
            }
        }

        let result: UUID? = try await supabase
            .rpc("share_celebration_to_circles", params: ["p_celebration_id": celebrationId])
            .execute()
            .value

        if result != nil {
            Analytics.shared.track(.celebrationSharedToCircle)
        }

        return result
    }

    /// Mark a celebration as shared externally (social media, etc.)
    func markCelebrationSharedExternally(celebrationId: UUID) async throws {
        try await supabase
            .from("celebration_events")
            .update(["shared_externally": true])
            .eq("id", value: celebrationId)
            .eq("user_id", value: try userId)
            .execute()

        Analytics.shared.track(.celebrationSharedExternally)
    }

    /// Add a reaction to a celebration
    func addCelebrationReaction(celebrationId: UUID, emoji: String) async throws {
        let currentUserId = try userId

        try await supabase
            .from("celebration_reactions")
            .upsert([
                "celebration_event_id": AnyEncodable(celebrationId),
                "reactor_user_id": AnyEncodable(currentUserId),
                "emoji": AnyEncodable(emoji)
            ], onConflict: "celebration_event_id,reactor_user_id")
            .execute()

        Analytics.shared.track(.celebrationReactionAdded)
    }

    /// Remove a reaction from a celebration
    func removeCelebrationReaction(celebrationId: UUID) async throws {
        try await supabase
            .from("celebration_reactions")
            .delete()
            .eq("celebration_event_id", value: celebrationId)
            .eq("reactor_user_id", value: try userId)
            .execute()
    }

    /// Get reaction summary for a celebration
    func getCelebrationReactions(celebrationId: UUID) async throws -> [CelebrationReactionSummary] {
        try await supabase
            .rpc("get_celebration_reactions", params: ["p_celebration_id": celebrationId])
            .execute()
            .value
    }

    /// Check and trigger milestone celebrations based on current stats
    /// Call this after quest completion, exercise completion, level up, or badge unlock
    func checkMilestoneTriggers(
        streak: Int? = nil,
        questCount: Int? = nil,
        exerciseCount: Int? = nil,
        newLevel: Int? = nil,
        badgeId: UUID? = nil
    ) async throws -> [MilestoneTriggerResult] {
        let currentUserId = try userId

        var params: [String: AnyEncodable] = [
            "p_user_id": AnyEncodable(currentUserId)
        ]

        if let streak = streak {
            params["p_streak"] = AnyEncodable(streak)
        }
        if let questCount = questCount {
            params["p_quest_count"] = AnyEncodable(questCount)
        }
        if let exerciseCount = exerciseCount {
            params["p_exercise_count"] = AnyEncodable(exerciseCount)
        }
        if let newLevel = newLevel {
            params["p_new_level"] = AnyEncodable(newLevel)
        }
        if let badgeId = badgeId {
            params["p_badge_id"] = AnyEncodable(badgeId)
        }

        let results: [MilestoneTriggerResult] = try await supabase
            .rpc("check_milestone_triggers", params: params)
            .execute()
            .value

        return results
    }

    /// Get share card templates
    func getShareCardTemplates() async throws -> [ShareCardTemplate] {
        try await supabase
            .from("share_card_templates")
            .select()
            .eq("is_active", value: true)
            .execute()
            .value
    }

    // MARK: - Program Enrollment Methods

    /// Enroll user in a program
    func enrollInProgram(programId: String, preferredTime: String) async throws -> ProgramEnrollment {
        guard let userId = currentUserId else {
            throw DataError.notAuthenticated
        }

        struct EnrollmentInsert: Encodable {
            let user_id: String
            let program_id: String
            let status: String
            let current_day: Int
            let preferred_time_local: String
            let skips_used: Int
            let streak_days: Int
            let longest_streak: Int
        }

        let enrollmentData = EnrollmentInsert(
            user_id: userId.uuidString,
            program_id: programId,
            status: "active",
            current_day: 1,
            preferred_time_local: preferredTime,
            skips_used: 0,
            streak_days: 0,
            longest_streak: 0
        )

        let enrollment: ProgramEnrollment = try await supabase
            .from("program_enrollments")
            .insert(enrollmentData)
            .select()
            .single()
            .execute()
            .value

        return enrollment
    }

    /// Resume a paused enrollment
    func resumeEnrollment(_ enrollmentId: String) async throws {
        try await supabase
            .from("program_enrollments")
            .update(["status": "active", "paused_at": nil])
            .eq("id", value: enrollmentId)
            .execute()
    }

    /// Abandon an enrollment
    func abandonEnrollment(_ enrollmentId: String) async throws {
        try await supabase
            .from("program_enrollments")
            .update(["status": "abandoned"])
            .eq("id", value: enrollmentId)
            .execute()
    }

    // MARK: - Program Methods (TODO: Implement these methods)

    func getProgramDay(programId: String, dayNumber: Int) async throws -> ProgramDay? {
        // TODO: Implement getProgramDay
        return nil
    }

    func getDayProgress(enrollmentId: String, dayNumber: Int) async throws -> ProgramDayProgress? {
        // TODO: Implement getDayProgress
        return nil
    }

    func saveProgramDayProgress(enrollmentId: String, dayNumber: Int, contentCompleted: [String: Bool], reflectionResponse: String?, applyReport: String?, moodBefore: Int?) async throws {
        // TODO: Implement saveProgramDayProgress
    }

    func completeProgramDay(enrollmentId: String) async throws -> (programComplete: Bool, certificateNumber: String?) {
        // TODO: Implement completeProgramDay
        return (programComplete: false, certificateNumber: nil)
    }

    func skipProgramDay(enrollmentId: String, dayNumber: Int) async throws {
        // TODO: Implement skipProgramDay
    }

    func pauseEnrollment(enrollmentId: String) async throws {
        // TODO: Implement pauseEnrollment
    }

    func getProgramDays(programId: String) async throws -> [ProgramDay] {
        // TODO: Implement getProgramDays
        return []
    }

    func getEnrollment(programId: String) async throws -> ProgramEnrollment? {
        // TODO: Implement getEnrollment
        return nil
    }

    func getActiveEnrollment() async throws -> ProgramEnrollment? {
        // TODO: Implement getActiveEnrollment
        return nil
    }

    // MARK: - Programs (stub - not implemented yet)
    
    func getPrograms() async throws -> [Program] {
        throw DataError.notImplemented("Programs feature not yet implemented")
    }
    
    // MARK: - Stress Signature

    /// Fetch stress signature patterns for current user
    func fetchStressSignature() async throws -> StressSignature {
        let currentUserId = try userId

        // Response DTOs
        struct StressSignatureResponse: Decodable {
            let userId: UUID
            let generatedAt: Date
            let patterns: [PatternResponse]
        }

        struct PatternResponse: Decodable {
            let id: UUID
            let category: String
            let type: String
            let confidenceScore: Double
            let evidenceCount: Int
            let firstDetected: Date
            let lastDetected: Date
            let data: PatternDataResponse

            private enum CodingKeys: String, CodingKey {
                case id, category, type, data
                case confidenceScore  // RPC outputs camelCase
                case evidenceCount
                case firstDetected
                case lastDetected
            }
        }

        struct PatternDataResponse: Decodable {
            let category: String
            let frequency: Double
            let timeline: [TimelinePoint]
            let topExercises: [String]?
            let peakTimes: [String]?
        }

        struct TimelinePoint: Decodable {
            let date: Date
            let count: Int
        }

        let response: StressSignatureResponse = try await supabase
            .rpc("get_stress_signature", params: ["p_user_id": currentUserId])
            .execute()
            .value

        return StressSignature(
            userId: response.userId,
            generatedAt: response.generatedAt,
            patterns: response.patterns.map { pattern in
                SignaturePattern(
                    id: pattern.id,
                    category: pattern.data.category,
                    type: SignaturePatternType(rawValue: pattern.type) ?? .other,
                    confidenceScore: pattern.confidenceScore,
                    evidenceCount: pattern.evidenceCount,
                    frequency: pattern.data.frequency,
                    timeline: pattern.data.timeline.map { point in
                        TimelineDataPoint(date: point.date, count: point.count)
                    },
                    firstDetected: pattern.firstDetected,
                    lastDetected: pattern.lastDetected,
                    topExercises: pattern.data.topExercises,
                    peakTimes: pattern.data.peakTimes
                )
            }
        )
    }

    // MARK: - Post-MVP Features

    /// Fetch weekly progress story for a given week
    func getWeeklyStory(weekStart: Date) async throws -> [String: Any]? {
        // Post-MVP feature - stub implementation
        return nil
    }

    /// Generate a new weekly progress story
    func generateWeeklyStory(weekStart: Date) async throws -> [String: Any] {
        // Post-MVP feature - stub implementation
        throw DataError.notImplemented("Weekly story generation not yet implemented")
    }

    /// Upload a story card image
    func uploadStoryCardImage(_ image: UIImage) async throws -> URL {
        // Post-MVP feature - stub implementation
        throw DataError.notImplemented("Story card image upload not yet implemented")
    }

    /// Share a story to a circle
    func shareStoryToCircle(_ imageUrl: String?, circleId: UUID, caption: String?) async throws {
        // Post-MVP feature - stub implementation
        throw DataError.notImplemented("Story circle sharing not yet implemented")
    }
    
    // MARK: - Certificates
    
    /// Get user's certificates
    func getCertificates() async throws -> [ProgramCertificate] {
        // Post-MVP feature - stub implementation
        return []
    }
    
    /// Share certificate to circle
    func shareCertificateToCircle(certificateId: String, circleId: UUID? = nil, caption: String? = nil) async throws {
        // Post-MVP feature - stub implementation
        throw DataError.notImplemented("Certificate circle sharing not yet implemented")
    }
    
    /// Share certificate externally
    func shareCertificateExternally(certificateId: String) async throws -> String {
        // Post-MVP feature - stub implementation
        throw DataError.notImplemented("External certificate sharing not yet implemented")
    }
    
    // MARK: - Safety Plan
    
    /// Fetch user's safety plan
    func fetchSafetyPlan() async throws -> SafetyPlanResponse {
        // Post-MVP feature - stub implementation
        throw DataError.notImplemented("Safety plan fetching not yet implemented")
    }
    
    /// Save user's safety plan
    func saveSafetyPlan(payload: SafetyPlanPayload, operation: SafetyPlanOperation) async throws -> SafetyPlanResponse {
        // Post-MVP feature - stub implementation
        throw DataError.notImplemented("Safety plan saving not yet implemented")
    }
    
    /// Update safety plan settings
    func updateSafetyPlanSettings(settings: SafetyPlanSettings) async throws -> SafetyPlanResponse {
        // Post-MVP feature - stub implementation
        throw DataError.notImplemented("Safety plan settings update not yet implemented")
    }
    
    /// Delete user's safety plan
    func deleteSafetyPlan() async throws -> SafetyPlanResponse {
        // Post-MVP feature - stub implementation
        throw DataError.notImplemented("Safety plan deletion not yet implemented")
    }
    
    // MARK: - AI Coaching
    
    /// Invoke coaching function
    func invokeCoachingFunction(_ request: CoachingModeRequest) async throws -> CoachingModeResponse {
        // Post-MVP feature - stub implementation
        throw DataError.notImplemented("AI coaching function invocation not yet implemented")
    }
    
    // MARK: - Weekly Wellbeing
    
    /// Submit weekly wellbeing response
    func submitWeeklyWellbeing(_ request: WeeklyWellbeingRequest) async throws -> WeeklyWellbeingResponse {
        // Post-MVP feature - stub implementation
        throw DataError.notImplemented("Weekly wellbeing submission not yet implemented")
    }

    // MARK: - Circle Habits
    
    /// Invoke circle habits function
    func invokeCircleHabitsFunction(_ request: CircleHabitsRequest) async throws -> CircleHabitsResponse {
        // Post-MVP feature - stub implementation
        throw DataError.notImplemented("Circle habits function invocation not yet implemented")
    }
    
    // MARK: - Notification Engagement
    
    /// Log notification engagement event
    func logNotificationEngagement(_ event: EngagementEvent) async throws {
        // Post-MVP feature - stub implementation
        throw DataError.notImplemented("Notification engagement logging not yet implemented")
    }
    
    /// Fetch notification training data for smart scheduling
    func fetchNotificationTrainingData() async throws -> [EngagementEvent] {
        // Post-MVP feature - stub implementation
        return []
    }
    
    /// Fetch notification engagement statistics
    func fetchNotificationEngagementStats() async throws -> EngagementStats {
        // Post-MVP feature - stub implementation
        return EngagementStats(
            delivered: 0,
            opened: 0,
            completed: 0,
            dismissed: 0,
            rate: 0.0,
            periodStart: Date(),
            periodEnd: Date()
        )
    }
    
    // MARK: - Circadian Vulnerability Shield Methods
    
    func getCurrentUserId() async throws -> UUID {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "SupabaseDataService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }
        return userId
    }
    
    func saveCircadianProfile(_ profile: CircadianProfile) async throws {
        struct ProfileDTO: Encodable {
            let id: UUID
            let user_id: UUID
            let chronotype: String
            let chronotype_confidence: Double
            let natural_wake_time: Int
            let natural_sleep_time: Int
            let social_jet_lag_minutes: Int
            let vulnerable_windows: String
            let peak_performance_window: String?
            let created_at: Date
            let updated_at: Date
        }
        
        let vulnerableWindowsJSON = try JSONEncoder().encode(profile.vulnerableWindows)
        let vulnerableWindowsString = String(data: vulnerableWindowsJSON, encoding: .utf8) ?? "[]"
        
        var peakJSON: String? = nil
        if let peak = profile.peakPerformanceWindow {
            let peakData = try JSONEncoder().encode(peak)
            peakJSON = String(data: peakData, encoding: .utf8)
        }
        
        let dto = ProfileDTO(
            id: profile.id,
            user_id: profile.userId,
            chronotype: profile.chronotype.rawValue,
            chronotype_confidence: profile.chronotypeConfidence,
            natural_wake_time: profile.naturalWakeTime,
            natural_sleep_time: profile.naturalSleepTime,
            social_jet_lag_minutes: profile.socialJetLagMinutes,
            vulnerable_windows: vulnerableWindowsString,
            peak_performance_window: peakJSON,
            created_at: profile.createdAt,
            updated_at: profile.updatedAt
        )
        
        try await supabase.from("circadian_profiles")
            .upsert(dto)
            .execute()
    }
    
    func fetchCircadianProfile() async throws -> CircadianProfile? {
        let userId = try await getCurrentUserId()
        
        struct ProfileDTO: Decodable {
            let id: UUID
            let user_id: UUID
            let chronotype: String
            let chronotype_confidence: Double
            let natural_wake_time: Int
            let natural_sleep_time: Int
            let social_jet_lag_minutes: Int
            let vulnerable_windows: String
            let peak_performance_window: String?
            let created_at: Date
            let updated_at: Date
        }
        
        let response: [ProfileDTO] = try await supabase.from("circadian_profiles")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        guard let dto = response.first else { return nil }
        
        let windowsData = dto.vulnerable_windows.data(using: .utf8) ?? Data()
        let windows = (try? JSONDecoder().decode([VulnerableWindow].self, from: windowsData)) ?? []
        
        var peak: PeakPerformanceWindow? = nil
        if let peakJSON = dto.peak_performance_window,
           let peakData = peakJSON.data(using: .utf8) {
            peak = try? JSONDecoder().decode(PeakPerformanceWindow.self, from: peakData)
        }
        
        guard let chronotype = Chronotype(rawValue: dto.chronotype) else { return nil }
        
        return CircadianProfile(
            id: dto.id,
            userId: dto.user_id,
            chronotype: chronotype,
            chronotypeConfidence: dto.chronotype_confidence,
            naturalWakeTime: dto.natural_wake_time,
            naturalSleepTime: dto.natural_sleep_time,
            socialJetLagMinutes: dto.social_jet_lag_minutes,
            vulnerableWindows: windows,
            peakPerformanceWindow: peak,
            createdAt: dto.created_at,
            updatedAt: dto.updated_at
        )
    }
    
    func saveVulnerableWindow(_ window: VulnerableWindow) async throws {
        struct WindowDTO: Encodable {
            let id: UUID
            let user_id: UUID
            let date: Date
            let start_time: Date
            let end_time: Date
            let severity: String
            let confidence: Double
            let predicted_triggers: [String]
            let armor_delivered: Bool
            let armor_completed: Bool
            let armor_exercise_id: String?
            let mood_during_window: Double?
            let crash_occurred: Bool?
            let created_at: Date
        }
        
        let dto = WindowDTO(
            id: window.id,
            user_id: window.userId,
            date: window.date,
            start_time: window.startTime,
            end_time: window.endTime,
            severity: window.severity.rawValue,
            confidence: window.confidence,
            predicted_triggers: window.predictedTriggers,
            armor_delivered: window.armorDelivered,
            armor_completed: window.armorCompleted,
            armor_exercise_id: window.armorExerciseId,
            mood_during_window: window.moodDuringWindow,
            crash_occurred: window.crashOccurred,
            created_at: window.createdAt
        )
        
        try await supabase.from("vulnerable_windows")
            .upsert(dto)
            .execute()
    }
    
    func fetchVulnerableWindows(for date: Date) async throws -> [VulnerableWindow] {
        let userId = try await getCurrentUserId()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }
        
        struct WindowDTO: Decodable {
            let id: UUID
            let user_id: UUID
            let date: Date
            let start_time: Date
            let end_time: Date
            let severity: String
            let confidence: Double
            let predicted_triggers: [String]
            let armor_delivered: Bool
            let armor_completed: Bool
            let armor_exercise_id: String?
            let mood_during_window: Double?
            let crash_occurred: Bool?
            let created_at: Date
        }
        
        let response: [WindowDTO] = try await supabase.from("vulnerable_windows")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("date", value: startOfDay.ISO8601Format())
            .lt("date", value: endOfDay.ISO8601Format())
            .execute()
            .value
        
        return response.compactMap { dto in
            guard let severity = VulnerableWindow.VulnerabilitySeverity(rawValue: dto.severity) else {
                return nil
            }
            
            return VulnerableWindow(
                id: dto.id,
                userId: dto.user_id,
                date: dto.date,
                startTime: dto.start_time,
                endTime: dto.end_time,
                severity: severity,
                confidence: dto.confidence,
                predictedTriggers: dto.predicted_triggers,
                armorDelivered: dto.armor_delivered,
                armorCompleted: dto.armor_completed,
                armorExerciseId: dto.armor_exercise_id,
                moodDuringWindow: dto.mood_during_window,
                crashOccurred: dto.crash_occurred,
                createdAt: dto.created_at
            )
        }
    }
    
    func fetchVulnerableWindows(lastDays: Int) async throws -> [VulnerableWindow] {
        let userId = try await getCurrentUserId()
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .day, value: -lastDays, to: Date()) else {
            return []
        }
        
        struct WindowDTO: Decodable {
            let id: UUID
            let user_id: UUID
            let date: Date
            let start_time: Date
            let end_time: Date
            let severity: String
            let confidence: Double
            let predicted_triggers: [String]
            let armor_delivered: Bool
            let armor_completed: Bool
            let armor_exercise_id: String?
            let mood_during_window: Double?
            let crash_occurred: Bool?
            let created_at: Date
        }
        
        let response: [WindowDTO] = try await supabase.from("vulnerable_windows")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("date", value: startDate.ISO8601Format())
            .execute()
            .value
        
        return response.compactMap { dto in
            guard let severity = VulnerableWindow.VulnerabilitySeverity(rawValue: dto.severity) else {
                return nil
            }
            
            return VulnerableWindow(
                id: dto.id,
                userId: dto.user_id,
                date: dto.date,
                startTime: dto.start_time,
                endTime: dto.end_time,
                severity: severity,
                confidence: dto.confidence,
                predictedTriggers: dto.predicted_triggers,
                armorDelivered: dto.armor_delivered,
                armorCompleted: dto.armor_completed,
                armorExerciseId: dto.armor_exercise_id,
                moodDuringWindow: dto.mood_during_window,
                crashOccurred: dto.crash_occurred,
                createdAt: dto.created_at
            )
        }
    }
    
    func deleteVulnerableWindows(after date: Date) async throws {
        let userId = try await getCurrentUserId()
        
        try await supabase.from("vulnerable_windows")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .gte("date", value: date.ISO8601Format())
            .execute()
    }
    
    func updateVulnerableWindowOutcome(windowId: UUID, moodDuring: Double?, crashOccurred: Bool) async throws {
        struct UpdateDTO: Encodable {
            let mood_during_window: Double?
            let crash_occurred: Bool
        }

        let dto = UpdateDTO(
            mood_during_window: moodDuring,
            crash_occurred: crashOccurred
        )

        try await supabase.from("vulnerable_windows")
            .update(dto)
            .eq("id", value: windowId.uuidString)
            .execute()
    }

    // MARK: - Cognitive Distortion Detection (F006)

    /// Fetches distortion events for the current user
    /// - Parameter limit: Maximum number of events to fetch (default: 50)
    /// - Returns: Array of distortion events
    func fetchDistortionEvents(limit: Int = 50) async throws -> [DistortionEvent] {
        let userId = try await getCurrentUserId()

        let events: [DistortionEvent] = try await supabase
            .from("distortion_events")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return events
    }

    /// Fetches distortion events for a specific session
    /// - Parameter sessionId: Voice journal session ID
    /// - Returns: Array of distortion events for the session
    func fetchDistortionEvents(forSession sessionId: String) async throws -> [DistortionEvent] {
        let userId = try await getCurrentUserId()

        let events: [DistortionEvent] = try await supabase
            .from("distortion_events")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("session_id", value: sessionId)
            .order("created_at", ascending: false)
            .execute()
            .value

        return events
    }

    /// Updates distortion event acknowledgment status
    /// - Parameter eventId: Distortion event ID
    func acknowledgeDistortionEvent(_ eventId: UUID) async throws {
        struct UpdateDTO: Encodable {
            let user_acknowledged: Bool
        }

        let dto = UpdateDTO(user_acknowledged: true)

        try await supabase
            .from("distortion_events")
            .update(dto)
            .eq("id", value: eventId.uuidString)
            .execute()
    }

    /// Fetches distortion statistics for the current user
    /// - Parameter days: Number of days to look back (default: 30)
    /// - Returns: Dictionary mapping distortion type to count
    func fetchDistortionStats(lastDays days: Int = 30) async throws -> [DistortionType: Int] {
        let userId = try await getCurrentUserId()
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: Date()) else {
            return [:]
        }

        let events: [DistortionEvent] = try await supabase
            .from("distortion_events")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("created_at", value: startDate.ISO8601Format())
            .execute()
            .value

        // Count occurrences by type
        var stats: [DistortionType: Int] = [:]
        for event in events {
            stats[event.distortionType, default: 0] += 1
        }

        return stats
    }

    /// Deletes distortion events for the current user (GDPR Right to Erasure)
    /// - Parameter eventIds: Optional array of specific event IDs to delete (nil deletes all)
    func deleteDistortionEvents(eventIds: [UUID]? = nil) async throws {
        let userId = try await getCurrentUserId()

        var query = supabase
            .from("distortion_events")
            .delete()
            .eq("user_id", value: userId.uuidString)

        if let ids = eventIds {
            query = query.in("id", values: ids.map { $0.uuidString })
        }

        try await query.execute()
    }

    // MARK: - Weekly Stories & Narrative Preferences

    /// Fetches weekly stories for the current user with pagination and filtering
    /// - Parameters:
    ///   - limit: Number of stories to fetch (default: 20)
    ///   - offset: Pagination offset (default: 0)
    ///   - favoritesOnly: If true, only return favorited stories (default: false)
    /// - Returns: Array of WeeklyStory objects sorted by week_start descending
    func fetchWeeklyStories(
        limit: Int = 20,
        offset: Int = 0,
        favoritesOnly: Bool = false
    ) async throws -> [WeeklyStory] {
        let userId = try await getCurrentUserId()

        var query = supabase
            .from("weekly_stories")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("week_start", ascending: false)
            .range(from: offset, to: offset + limit - 1)

        if favoritesOnly {
            query = query.eq("is_favorite", value: true)
        }

        let response: [WeeklyStory] = try await query.execute().value
        return response
    }

    /// Updates the user rating for a specific story
    /// - Parameters:
    ///   - id: Story UUID
    ///   - rating: -1 (thumbs down), 1 (thumbs up), or nil (remove rating)
    func updateStoryRating(id: UUID, rating: Int?) async throws {
        try await supabase
            .from("weekly_stories")
            .update(["user_rating": rating as Any])
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Toggles the favorite status of a story
    /// - Parameters:
    ///   - id: Story UUID
    ///   - isFavorite: New favorite status
    func toggleStoryFavorite(id: UUID, isFavorite: Bool) async throws {
        try await supabase
            .from("weekly_stories")
            .update(["is_favorite": isFavorite])
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Fetches narrative preferences for the current user
    /// - Returns: NarrativePreferences if they exist, nil otherwise
    func fetchNarrativePreferences() async throws -> NarrativePreferences? {
        let userId = try await getCurrentUserId()

        let response: [NarrativePreferences] = try await supabase
            .from("narrative_preferences")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value

        return response.first
    }

    /// Updates (upserts) narrative preferences for the current user
    /// - Parameter preferences: NarrativePreferences to save
    func updateNarrativePreferences(_ preferences: NarrativePreferences) async throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(preferences)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "SupabaseDataService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to serialize preferences"]
            )
        }

        try await supabase
            .from("narrative_preferences")
            .upsert(dict)
            .execute()
    }
}
