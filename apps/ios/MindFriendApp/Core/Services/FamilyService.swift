import Foundation
import Supabase

/// Service for family wellness features: groups, members, challenges, and together sessions
@MainActor
final class FamilyService: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var familyGroup: FamilyWellnessGroup?
    @Published private(set) var familyMembers: [FamilyWellnessMember] = []
    @Published private(set) var challenges: [FamilyChallenge] = []
    @Published private(set) var challengeTemplates: [FamilyChallengeTemplate] = []
    @Published private(set) var togetherSessions: [TogetherSession] = []
    @Published private(set) var togetherTemplates: [TogetherTemplate] = []
    @Published private(set) var familyAlerts: [FamilyAlert] = []
    @Published private(set) var currentSessionParticipants: [TogetherParticipant] = []
    @Published private(set) var parentalConsents: [ParentalConsent] = []

    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    // MARK: - Private Properties

    private let supabase: SupabaseClient
    private var familyChannel: RealtimeChannelV2?
    private var sessionsSubscriptionTask: Task<Void, Never>?
    private var alertsSubscriptionTask: Task<Void, Never>?

    // MARK: - Initialization

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    deinit {
        sessionsSubscriptionTask?.cancel()
        alertsSubscriptionTask?.cancel()
        Task { [familyChannel] in
            await familyChannel?.unsubscribe()
        }
    }

    // MARK: - Load All Data

    /// Load all family wellness data for the hub view
    func loadData() async {
        isLoading = true
        error = nil

        async let familyTask = fetchFamilyGroup()
        async let membersTask = fetchFamilyMembers()
        async let challengesTask = fetchChallenges()
        async let templatesTask = fetchChallengeTemplates()
        async let sessionsTask = fetchTogetherSessions()
        async let alertsTask = fetchFamilyAlerts()
        async let consentsTask = fetchParentalConsents()

        do {
            familyGroup = try await familyTask
        } catch {
            Log.family.error("Failed to fetch family group", error: error)
            self.error = "Failed to load family group"
        }

        do {
            familyMembers = try await membersTask
        } catch {
            Log.family.error("Failed to fetch family members", error: error)
            self.error = "Failed to load family members"
        }

        do {
            challenges = try await challengesTask
        } catch {
            Log.family.error("Failed to fetch challenges", error: error)
        }

        do {
            challengeTemplates = try await templatesTask
        } catch {
            Log.family.error("Failed to fetch challenge templates", error: error)
        }

        do {
            togetherSessions = try await sessionsTask
        } catch {
            Log.family.error("Failed to fetch together sessions", error: error)
        }

        do {
            familyAlerts = try await alertsTask
        } catch {
            Log.family.error("Failed to fetch family alerts", error: error)
        }

        do {
            parentalConsents = try await consentsTask
        } catch {
            Log.family.error("Failed to fetch parental consents", error: error)
        }

        isLoading = false
    }

    // MARK: - Family Group Operations

    /// Fetch the current user's family group
    func fetchFamilyGroup() async throws -> FamilyWellnessGroup? {
        guard let userId = supabase.auth.currentUser?.id else { return nil }

        let response: [FamilyWellnessGroup] = try await supabase
            .from("family_groups")
            .select()
            .eq("admin_user_id", value: userId)
            .limit(1)
            .execute()
            .value

        return response.first
    }

    /// Create a new family group
    func createFamily(
        name: String,
        defaultChildAgeFilter: Int = 18,
        maxMembers: Int = 6
    ) async throws -> FamilyWellnessGroup {
        guard let userId = supabase.auth.currentUser?.id else {
            throw FamilyServiceError.notAuthenticated
        }

        let inviteCode = generateInviteCode()

        let newFamily: [String: FamilyAnyEncodable] = [
            "name": FamilyAnyEncodable(name),
            "admin_user_id": FamilyAnyEncodable(userId),
            "invite_code": FamilyAnyEncodable(inviteCode),
            "default_child_age_filter": FamilyAnyEncodable(defaultChildAgeFilter),
            "max_members": FamilyAnyEncodable(maxMembers),
            "created_at": FamilyAnyEncodable(Date().ISO8601Format()),
            "updated_at": FamilyAnyEncodable(Date().ISO8601Format())
        ]

        let response: [FamilyWellnessGroup] = try await supabase
            .from("family_groups")
            .insert(newFamily)
            .select()
            .execute()
            .value

        guard let family = response.first else {
            throw FamilyServiceError.createFamilyFailed
        }

        familyGroup = family

        // Also create the admin as a family member
        _ = try await addMemberToFamily(
            familyId: family.id,
            role: .admin,
            nickname: nil,
            birthDate: nil
        )

        return family
    }

    /// Join a family via invite code
    func joinFamily(
        inviteCode: String,
        nickname: String? = nil,
        birthDate: Date? = nil
    ) async throws {
        struct JoinResponse: Decodable {
            let success: Bool
        }

        let response: JoinResponse = try await supabase.functions.invoke(
            "join-family",
            options: .init(body: [
                "inviteCode": FamilyAnyEncodable(inviteCode),
                "nickname": FamilyAnyEncodable(nickname),
                "birthDate": FamilyAnyEncodable(birthDate.map { $0.ISO8601Format() })
            ])
        )

        guard response.success else {
            throw FamilyServiceError.joinFamilyFailed
        }

        // Refresh family data
        _ = try await fetchFamilyGroup()
        familyMembers = try await fetchFamilyMembers()
    }

    // MARK: - Family Member Operations

    /// Fetch all members of the current family
    func fetchFamilyMembers() async throws -> [FamilyWellnessMember] {
        guard let familyId = familyGroup?.id else { return [] }

        let response: [FamilyWellnessMember] = try await supabase
            .from("family_members")
            .select()
            .eq("family_id", value: familyId)
            .eq("status", value: "active")
            .order("created_at", ascending: true)
            .execute()
            .value

        return response
    }

    /// Add a member to the current family (admin only)
    func addMemberToFamily(
        familyId: String,
        role: FamilyRole,
        nickname: String? = nil,
        birthDate: Date? = nil
    ) async throws -> FamilyWellnessMember {
        guard let userId = supabase.auth.currentUser?.id else {
            throw FamilyServiceError.notAuthenticated
        }

        let newMember: [String: FamilyAnyEncodable] = [
            "family_id": FamilyAnyEncodable(familyId),
            "user_id": FamilyAnyEncodable(userId),
            "role": FamilyAnyEncodable(role.rawValue),
            "nickname": FamilyAnyEncodable(nickname),
            "birth_date": FamilyAnyEncodable(birthDate.map { $0.ISO8601Format() }),
            "share_mood_with_family": FamilyAnyEncodable(true),
            "share_activity_with_family": FamilyAnyEncodable(true),
            "share_achievements_with_family": FamilyAnyEncodable(true),
            "status": FamilyAnyEncodable("active"),
            "joined_at": FamilyAnyEncodable(Date().ISO8601Format()),
            "created_at": FamilyAnyEncodable(Date().ISO8601Format()),
            "updated_at": FamilyAnyEncodable(Date().ISO8601Format())
        ]

        let response: [FamilyWellnessMember] = try await supabase
            .from("family_members")
            .insert(newMember)
            .select()
            .execute()
            .value

        guard let member = response.first else {
            throw FamilyServiceError.addMemberFailed
        }

        familyMembers = try await fetchFamilyMembers()
        return member
    }

    /// Update a family member's settings
    func updateMemberSettings(
        memberId: String,
        nickname: String? = nil,
        shareMoodWithFamily: Bool? = nil,
        shareActivityWithFamily: Bool? = nil,
        shareAchievementsWithFamily: Bool? = nil,
        ageFilterOverride: Int? = nil
    ) async throws {
        var updates: [String: FamilyAnyEncodable] = [
            "updated_at": FamilyAnyEncodable(Date().ISO8601Format())
        ]

        if let nickname = nickname {
            updates["nickname"] = FamilyAnyEncodable(nickname)
        }
        if let shareMood = shareMoodWithFamily {
            updates["share_mood_with_family"] = FamilyAnyEncodable(shareMood)
        }
        if let shareActivity = shareActivityWithFamily {
            updates["share_activity_with_family"] = FamilyAnyEncodable(shareActivity)
        }
        if let shareAchievements = shareAchievementsWithFamily {
            updates["share_achievements_with_family"] = FamilyAnyEncodable(shareAchievements)
        }
        if let override = ageFilterOverride {
            updates["age_filter_override"] = FamilyAnyEncodable(override)
        }

        try await supabase
            .from("family_members")
            .update(updates)
            .eq("id", value: memberId)
            .execute()

        familyMembers = try await fetchFamilyMembers()
    }

    // MARK: - Challenge Operations

    /// Fetch all challenges for the current family
    func fetchChallenges() async throws -> [FamilyChallenge] {
        guard let familyId = familyGroup?.id else { return [] }

        let response: [FamilyChallenge] = try await supabase
            .from("family_challenges")
            .select()
            .eq("family_id", value: familyId)
            .order("created_at", ascending: false)
            .execute()
            .value

        return response
    }

    /// Fetch challenge templates
    func fetchChallengeTemplates() async throws -> [FamilyChallengeTemplate] {
        let response: [FamilyChallengeTemplate] = try await supabase
            .from("family_challenge_templates")
            .select()
            .eq("is_active", value: true)
            .order("category", ascending: true)
            .execute()
            .value

        return response
    }

    /// Create a new challenge in the family
    func createChallenge(
        title: String,
        description: String? = nil,
        challengeType: FamilyChallengeType,
        targetValue: Int,
        minimumParticipants: Int = 1,
        durationDays: Int = 7,
        requiresAllMembers: Bool = false,
        allowMakeupActivities: Bool = true
    ) async throws -> FamilyChallenge {
        guard let familyId = familyGroup?.id else {
            throw FamilyServiceError.noFamilyGroup
        }
        guard let userId = supabase.auth.currentUser?.id else {
            throw FamilyServiceError.notAuthenticated
        }

        let now = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: durationDays, to: now) ?? now

        let newChallenge: [String: FamilyAnyEncodable] = [
            "family_id": FamilyAnyEncodable(familyId),
            "title": FamilyAnyEncodable(title),
            "description": FamilyAnyEncodable(description),
            "challenge_type": FamilyAnyEncodable(challengeType.rawValue),
            "target_value": FamilyAnyEncodable(targetValue),
            "minimum_participants": FamilyAnyEncodable(minimumParticipants),
            "start_date": FamilyAnyEncodable(now.ISO8601Format()),
            "end_date": FamilyAnyEncodable(endDate.ISO8601Format()),
            "requires_all_members": FamilyAnyEncodable(requiresAllMembers),
            "allow_makeup_activities": FamilyAnyEncodable(allowMakeupActivities),
            "status": FamilyAnyEncodable("active"),
            "current_progress": FamilyAnyEncodable(0),
            "created_by": FamilyAnyEncodable(userId),
            "created_at": FamilyAnyEncodable(now.ISO8601Format()),
            "updated_at": FamilyAnyEncodable(now.ISO8601Format())
        ]

        let response: [FamilyChallenge] = try await supabase
            .from("family_challenges")
            .insert(newChallenge)
            .select()
            .execute()
            .value

        guard let challenge = response.first else {
            throw FamilyServiceError.createChallengeFailed
        }

        challenges = try await fetchChallenges()
        return challenge
    }

    /// Update challenge progress
    func updateChallengeProgress(
        challengeId: String,
        progress: Int
    ) async throws {
        try await supabase
            .from("family_challenges")
            .update([
                "current_progress": FamilyAnyEncodable(progress),
                "updated_at": FamilyAnyEncodable(Date().ISO8601Format())
            ])
            .eq("id", value: challengeId)
            .execute()

        challenges = try await fetchChallenges()
    }

    // MARK: - Together Session Operations

    /// Fetch all together sessions for the current family
    func fetchTogetherSessions() async throws -> [TogetherSession] {
        guard let familyId = familyGroup?.id else { return [] }

        let response: [TogetherSession] = try await supabase
            .from("together_sessions")
            .select()
            .eq("family_id", value: familyId)
            .order("created_at", ascending: false)
            .limit(50)
            .execute()
            .value

        return response
    }

    /// Fetch together templates
    func fetchTogetherTemplates() async throws -> [TogetherTemplate] {
        let response: [TogetherTemplate] = try await supabase
            .from("together_templates")
            .select()
            .eq("is_active", value: true)
            .order("category", ascending: true)
            .execute()
            .value

        togetherTemplates = response
        return response
    }

    /// Start a new together session
    func startTogetherSession(
        templateId: String? = nil,
        exerciseId: String? = nil,
        title: String = "Family Activity",
        invitedMemberIds: [String]? = nil,
        syncMode: String = "realtime"
    ) async throws -> TogetherSession {
        guard let familyId = familyGroup?.id else {
            throw FamilyServiceError.noFamilyGroup
        }

        struct StartSessionResponse: Decodable {
            let success: Bool
            let session: SessionData?
            let participantCount: Int?
            let error: String?

            struct SessionData: Decodable {
                let id: String
                let familyId: String
                let title: String
                let status: String

                enum CodingKeys: String, CodingKey {
                    case id
                    case familyId = "familyId"
                    case title
                    case status
                }
            }
        }

        let response: StartSessionResponse = try await supabase.functions.invoke(
            "start-together-session",
            options: .init(body: [
                "familyId": FamilyAnyEncodable(familyId),
                "templateId": FamilyAnyEncodable(templateId),
                "exerciseId": FamilyAnyEncodable(exerciseId),
                "title": FamilyAnyEncodable(title),
                "invitedMemberIds": FamilyAnyEncodable(invitedMemberIds),
                "syncMode": FamilyAnyEncodable(syncMode)
            ])
        )

        guard response.success, let sessionData = response.session else {
            throw FamilyServiceError.startSessionFailed
        }

        // Refresh sessions
        togetherSessions = try await fetchTogetherSessions()

        // Return a basic TogetherSession (would need full fetch in real scenario)
        return TogetherSession(
            id: sessionData.id,
            familyId: sessionData.familyId,
            exerciseId: exerciseId,
            togetherTemplateId: templateId,
            title: sessionData.title,
            scheduledFor: nil,
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: nil,
            minimumParticipants: 1,
            status: .inProgress,
            syncMode: syncMode == "realtime" ? .realtime : .asyncWindow,
            asyncWindowHours: syncMode == "async_window" ? 24 : nil,
            createdBy: supabase.auth.currentUser?.id.uuidString ?? "",
            createdAt: Date()
        )
    }

    /// Fetch participants in a together session
    func fetchSessionParticipants(sessionId: String) async throws -> [TogetherParticipant] {
        let response: [TogetherParticipant] = try await supabase
            .from("together_participants")
            .select()
            .eq("session_id", value: sessionId)
            .order("turn_order", ascending: true)
            .execute()
            .value

        currentSessionParticipants = response
        return response
    }

    /// Join a together session
    func joinTogetherSession(sessionId: String) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw FamilyServiceError.notAuthenticated
        }

        // Find the participant record for this user
        let participants: [TogetherParticipant] = try await supabase
            .from("together_participants")
            .select()
            .eq("session_id", value: sessionId)
            .execute()
            .value

        if let participantId = participants.first?.id {
            try await supabase
                .from("together_participants")
                .update([
                    "status": FamilyAnyEncodable("joined"),
                    "joined_at": FamilyAnyEncodable(Date().ISO8601Format())
                ])
                .eq("id", value: participantId)
                .execute()
        }

        currentSessionParticipants = try await fetchSessionParticipants(sessionId: sessionId)
    }

    /// Complete a together session
    func completeTogetherSession(sessionId: String) async throws {
        try await supabase
            .from("together_sessions")
            .update([
                "status": FamilyAnyEncodable("completed"),
                "ended_at": FamilyAnyEncodable(Date().ISO8601Format())
            ])
            .eq("id", value: sessionId)
            .execute()

        togetherSessions = try await fetchTogetherSessions()
    }

    // MARK: - Family Alert Operations

    /// Fetch family alerts for the current user
    func fetchFamilyAlerts() async throws -> [FamilyAlert] {
        guard let userId = supabase.auth.currentUser?.id else { return [] }

        let response: [FamilyAlert] = try await supabase
            .from("family_alerts")
            .select()
            .eq("for_parent_id", value: userId)
            .order("created_at", ascending: false)
            .limit(50)
            .execute()
            .value

        return response
    }

    /// Mark an alert as read
    func markAlertAsRead(alertId: String) async throws {
        try await supabase
            .from("family_alerts")
            .update([
                "was_read": FamilyAnyEncodable(true),
                "read_at": FamilyAnyEncodable(Date().ISO8601Format())
            ])
            .eq("id", value: alertId)
            .execute()

        familyAlerts = try await fetchFamilyAlerts()
    }

    /// Mark an alert as acted upon
    func markAlertAsActedUpon(alertId: String) async throws {
        try await supabase
            .from("family_alerts")
            .update(["was_acted_upon": FamilyAnyEncodable(true)])
            .eq("id", value: alertId)
            .execute()

        familyAlerts = try await fetchFamilyAlerts()
    }

    // MARK: - Parental Consent Operations

    /// Fetch parental consents for the current user
    func fetchParentalConsents() async throws -> [ParentalConsent] {
        guard let userId = supabase.auth.currentUser?.id else { return [] }

        let response: [ParentalConsent] = try await supabase
            .from("parental_consents")
            .select()
            .eq("parent_user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()
            .value

        return response
    }

    /// Request parental consent (COPPA)
    func requestParentalConsent(
        childUserId: String,
        parentEmail: String
    ) async throws -> ParentalConsent {
        guard let userId = supabase.auth.currentUser?.id else {
            throw FamilyServiceError.notAuthenticated
        }

        let expiresAt = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()

        let newConsent: [String: FamilyAnyEncodable] = [
            "child_user_id": FamilyAnyEncodable(childUserId),
            "parent_user_id": FamilyAnyEncodable(userId),
            "parent_email": FamilyAnyEncodable(parentEmail),
            "consent_type": FamilyAnyEncodable("initial"),
            "expires_at": FamilyAnyEncodable(expiresAt.ISO8601Format()),
            "created_at": FamilyAnyEncodable(Date().ISO8601Format())
        ]

        let response: [ParentalConsent] = try await supabase
            .from("parental_consents")
            .insert(newConsent)
            .select()
            .execute()
            .value

        guard let consent = response.first else {
            throw FamilyServiceError.requestConsentFailed
        }

        parentalConsents = try await fetchParentalConsents()
        return consent
    }

    // MARK: - Realtime Subscriptions

    /// Subscribe to together session updates
    func subscribeToSessionUpdates(sessionId: String) async {
        sessionsSubscriptionTask?.cancel()

        let channel = supabase.realtimeV2.channel("session:\(sessionId)")

        let insertions = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "together_participants",
            filter: "session_id=eq.\(sessionId)"
        )

        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "together_participants",
            filter: "session_id=eq.\(sessionId)"
        )

        await channel.subscribe()

        sessionsSubscriptionTask = Task {
            for await insertion in insertions {
                if Task.isCancelled { break }

                if let participant = try? insertion.decodeRecord(as: TogetherParticipant.self, decoder: JSONDecoder()) {
                    await MainActor.run {
                        if !Task.isCancelled {
                            // Update participant in current session
                            if let index = self.currentSessionParticipants.firstIndex(where: { $0.id == participant.id }) {
                                self.currentSessionParticipants[index] = participant
                            } else {
                                self.currentSessionParticipants.append(participant)
                            }
                        }
                    }
                }
            }
        }

        // Also handle updates
        Task {
            for await update in updates {
                if Task.isCancelled { break }

                if let participant = try? update.decodeRecord(as: TogetherParticipant.self, decoder: JSONDecoder()) {
                    await MainActor.run {
                        if !Task.isCancelled {
                            if let index = self.currentSessionParticipants.firstIndex(where: { $0.id == participant.id }) {
                                self.currentSessionParticipants[index] = participant
                            }
                        }
                    }
                }
            }
        }

        familyChannel = channel
    }

    /// Unsubscribe from session updates
    func unsubscribeFromSessionUpdates() async {
        sessionsSubscriptionTask?.cancel()
        sessionsSubscriptionTask = nil
        await familyChannel?.unsubscribe()
        familyChannel = nil
    }

    // MARK: - Helper Methods

    /// Generate a random invite code
    private func generateInviteCode() -> String {
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        var code = ""
        for _ in 0..<8 {
            code.append(characters.randomElement()!)
        }
        return code
    }
}

// MARK: - Error Type

enum FamilyServiceError: LocalizedError {
    case notAuthenticated
    case noFamilyGroup
    case createFamilyFailed
    case joinFamilyFailed
    case addMemberFailed
    case createChallengeFailed
    case startSessionFailed
    case requestConsentFailed
    case memberNotFound
    case familyNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to use family features."
        case .noFamilyGroup:
            return "You don't have an active family group."
        case .createFamilyFailed:
            return "Failed to create family group."
        case .joinFamilyFailed:
            return "Failed to join family group."
        case .addMemberFailed:
            return "Failed to add family member."
        case .createChallengeFailed:
            return "Failed to create challenge."
        case .startSessionFailed:
            return "Failed to start together session."
        case .requestConsentFailed:
            return "Failed to request parental consent."
        case .memberNotFound:
            return "Family member not found."
        case .familyNotFound:
            return "Family not found."
        }
    }
}

// MARK: - FamilyAnyEncodable Helper

private struct FamilyAnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ wrapped: T) {
        _encode = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
