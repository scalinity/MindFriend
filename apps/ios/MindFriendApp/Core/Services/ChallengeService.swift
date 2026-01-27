import Foundation
import Combine
import Supabase

@MainActor
final class ChallengeService: ObservableObject {
    @Published var publicChallenges: [ChallengeWithParticipation] = []
    @Published var circleChallenges: [ChallengeWithParticipation] = []
    @Published var myChallenges: [ChallengeWithParticipation] = []
    @Published var isLoading = false
    @Published var error: ChallengeError?

    private let supabaseClient: SupabaseClient
    private var cancellables = Set<AnyCancellable>()

    init(supabaseClient: SupabaseClient) {
        self.supabaseClient = supabaseClient
    }

    // MARK: - Loading Challenges

    func loadChallenges() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard let userId = supabaseClient.auth.currentSession?.user.id else {
            error = .notAuthenticated
            return
        }

        do {
            async let publicResult = fetchPublicChallenges(userId: userId)
            async let circleResult = fetchCircleChallenges(userId: userId)
            async let myResult = fetchJoinedChallenges(userId: userId)

            let (publicChalls, circleChalls, myChalls) = try await (publicResult, circleResult, myResult)

            self.publicChallenges = publicChalls
            self.circleChallenges = circleChalls
            self.myChallenges = myChalls
        } catch let err as ChallengeError {
            self.error = err
        } catch {
            self.error = .loadFailed
        }
    }

    private func fetchPublicChallenges(userId: UUID) async throws -> [ChallengeWithParticipation] {
        // Fetch public challenges with participant count
        let challenges: [SocialChallenge] = try await supabaseClient
            .from("social_challenges")
            .select()
            .eq("is_public", value: true)
            .gte("ends_at", value: ISO8601DateFormatter().string(from: Date()))
            .order("starts_at", ascending: true)
            .execute()
            .value

        // Fetch user's participation for these challenges
        let challengeIds = challenges.map { $0.id.uuidString }
        let participations: [ChallengeParticipant] = challengeIds.isEmpty ? [] : try await supabaseClient
            .from("challenge_participants")
            .select()
            .eq("user_id", value: userId.uuidString)
            .in("challenge_id", values: challengeIds)
            .execute()
            .value

        let participationMap = Dictionary(uniqueKeysWithValues: participations.map { ($0.challengeId, $0) })

        return challenges.map { challenge in
            ChallengeWithParticipation(
                challenge: challenge,
                participation: participationMap[challenge.id],
                participantCount: 0 // Would need aggregation query for accurate count
            )
        }
    }

    private func fetchCircleChallenges(userId: UUID) async throws -> [ChallengeWithParticipation] {
        // First get user's circle IDs
        struct CircleMembership: Codable {
            let circleId: UUID
            enum CodingKeys: String, CodingKey {
                case circleId = "circle_id"
            }
        }

        let memberships: [CircleMembership] = try await supabaseClient
            .from("circle_members")
            .select("circle_id")
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value

        let circleIds = memberships.map { $0.circleId.uuidString }
        guard !circleIds.isEmpty else { return [] }

        // Fetch challenges for those circles
        let challenges: [SocialChallenge] = try await supabaseClient
            .from("social_challenges")
            .select()
            .in("circle_id", values: circleIds)
            .gte("ends_at", value: ISO8601DateFormatter().string(from: Date()))
            .order("starts_at", ascending: true)
            .execute()
            .value

        // Fetch user's participation
        let challengeIds = challenges.map { $0.id.uuidString }
        let participations: [ChallengeParticipant] = challengeIds.isEmpty ? [] : try await supabaseClient
            .from("challenge_participants")
            .select()
            .eq("user_id", value: userId.uuidString)
            .in("challenge_id", values: challengeIds)
            .execute()
            .value

        let participationMap = Dictionary(uniqueKeysWithValues: participations.map { ($0.challengeId, $0) })

        return challenges.map { challenge in
            ChallengeWithParticipation(
                challenge: challenge,
                participation: participationMap[challenge.id],
                participantCount: 0
            )
        }
    }

    private func fetchJoinedChallenges(userId: UUID) async throws -> [ChallengeWithParticipation] {
        // Fetch all participations for the user with challenge data
        struct ParticipationWithChallenge: Codable {
            let id: UUID
            let challengeId: UUID
            let currentProgress: Int
            let completed: Bool
            let completedAt: Date?
            let finalRank: Int?
            let showOnLeaderboard: Bool
            let joinedAt: Date
            let updatedAt: Date
            let socialChallenges: SocialChallenge

            enum CodingKeys: String, CodingKey {
                case id
                case challengeId = "challenge_id"
                case currentProgress = "current_progress"
                case completed
                case completedAt = "completed_at"
                case finalRank = "final_rank"
                case showOnLeaderboard = "show_on_leaderboard"
                case joinedAt = "joined_at"
                case updatedAt = "updated_at"
                case socialChallenges = "social_challenges"
            }
        }

        let results: [ParticipationWithChallenge] = try await supabaseClient
            .from("challenge_participants")
            .select("*, social_challenges(*)")
            .eq("user_id", value: userId.uuidString)
            .order("joined_at", ascending: false)
            .execute()
            .value

        return results.map { result in
            let participation = ChallengeParticipant(
                id: result.id,
                challengeId: result.challengeId,
                userId: userId,
                currentProgress: result.currentProgress,
                completed: result.completed,
                completedAt: result.completedAt,
                finalRank: result.finalRank,
                showOnLeaderboard: result.showOnLeaderboard,
                joinedAt: result.joinedAt,
                updatedAt: result.updatedAt
            )
            return ChallengeWithParticipation(
                challenge: result.socialChallenges,
                participation: participation,
                participantCount: 0
            )
        }
    }

    // MARK: - Join/Leave

    func joinChallenge(
        _ challengeId: UUID,
        showOnLeaderboard: Bool = true
    ) async throws {
        guard let userId = supabaseClient.auth.currentSession?.user.id else {
            throw ChallengeError.notAuthenticated
        }

        // Check rate limit - RPC params must all be strings
        let canJoin: Bool = try await supabaseClient
            .rpc("check_join_rate_limit", params: ["p_user_id": userId.uuidString])
            .execute()
            .value

        guard canJoin else {
            throw ChallengeError.rateLimited
        }

        // Create participation
        struct ParticipantInsert: Codable {
            let challenge_id: UUID
            let user_id: UUID
            let show_on_leaderboard: Bool
        }

        let insert = ParticipantInsert(
            challenge_id: challengeId,
            user_id: userId,
            show_on_leaderboard: showOnLeaderboard
        )

        let _ = try await supabaseClient
            .from("challenge_participants")
            .insert(insert)
            .execute()

        await loadChallenges()
    }

    func leaveChallenge(_ challengeId: UUID) async throws {
        guard let userId = supabaseClient.auth.currentSession?.user.id else {
            throw ChallengeError.notAuthenticated
        }

        let _ = try await supabaseClient
            .from("challenge_participants")
            .delete()
            .eq("challenge_id", value: challengeId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()

        await loadChallenges()
    }

    // MARK: - Leaderboard

    func getLeaderboard(
        _ challengeId: UUID,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [LeaderboardEntry] {
        guard let userId = supabaseClient.auth.currentSession?.user.id else {
            throw ChallengeError.notAuthenticated
        }

        struct LeaderboardRow: Codable {
            let user_id: String
            let rank_position: Int
            let current_progress: Int
            let user_display_name: String?
            let user_avatar_url: String?
            let is_tied: Bool?

            enum CodingKeys: String, CodingKey {
                case user_id
                case rank_position
                case current_progress
                case user_display_name
                case user_avatar_url
                case is_tied
            }
        }

        let leaderboard: [LeaderboardRow] = try await supabaseClient
            .rpc("get_challenge_leaderboard", params: [
                "p_challenge_id": challengeId.uuidString,
                "p_user_id": userId.uuidString,
                "p_limit": String(limit),
                "p_offset": String(offset)
            ])
            .execute()
            .value

        var entries: [LeaderboardEntry] = []

        for entry in leaderboard {
            if let uuid = UUID(uuidString: entry.user_id),
               let displayName = entry.user_display_name
            {
                let userProfile = UserProfile(
                    id: uuid,
                    handle: nil,
                    displayName: displayName,
                    email: nil,
                    avatarUrl: entry.user_avatar_url,
                    timezone: nil,
                    createdAt: nil,
                    onboardingCompletedAt: nil,
                    stats: nil,
                    settings: nil,
                    entitlements: nil,
                    badges: nil
                )

                let participant = ChallengeParticipant(
                    id: UUID(),
                    challengeId: challengeId,
                    userId: uuid,
                    currentProgress: entry.current_progress,
                    completed: false,
                    completedAt: nil,
                    finalRank: entry.rank_position,
                    showOnLeaderboard: true,
                    joinedAt: Date(),
                    updatedAt: Date()
                )

                let leaderboardEntry = LeaderboardEntry(
                    participant: participant,
                    userProfile: userProfile,
                    rank: entry.rank_position,
                    isCurrentUser: uuid == userId,
                    isTied: entry.is_tied ?? false
                )

                entries.append(leaderboardEntry)
            }
        }

        return entries
    }

    // MARK: - Create Challenge

    func createChallenge(
        title: String,
        description: String,
        challengeType: SocialChallengeType,
        targetValue: Int,
        durationDays: Int = 7,
        circleId: UUID? = nil,
        exerciseType: String? = nil
    ) async throws {
        guard let userId = supabaseClient.auth.currentSession?.user.id else {
            throw ChallengeError.notAuthenticated
        }

        // Check rate limit
        let canCreate: Bool = try await supabaseClient
            .rpc("check_challenge_creation_rate_limit", params: ["p_user_id": userId.uuidString])
            .execute()
            .value

        guard canCreate else {
            throw ChallengeError.rateLimited
        }

        let now = Date()
        let endsAt = Calendar.current.date(byAdding: .day, value: durationDays, to: now) ?? now

        struct ChallengeInsert: Codable {
            let title: String
            let description: String
            let challenge_type: String
            let target_value: Int
            let duration_days: Int
            let is_public: Bool
            let circle_id: UUID?
            let created_by: UUID
            let exercise_type: String?
            let starts_at: Date
            let ends_at: Date
        }

        let insert = ChallengeInsert(
            title: title,
            description: description,
            challenge_type: challengeType.rawValue,
            target_value: targetValue,
            duration_days: durationDays,
            is_public: circleId == nil,
            circle_id: circleId,
            created_by: userId,
            exercise_type: exerciseType,
            starts_at: now,
            ends_at: endsAt
        )

        let _ = try await supabaseClient
            .from("challenges")
            .insert(insert)
            .execute()

        await loadChallenges()
    }

    // MARK: - Privacy Controls

    func updateLeaderboardVisibility(
        _ challengeId: UUID,
        showOnLeaderboard: Bool
    ) async throws {
        guard let userId = supabaseClient.auth.currentSession?.user.id else {
            throw ChallengeError.notAuthenticated
        }

        struct VisibilityUpdate: Codable {
            let show_on_leaderboard: Bool
        }

        let update = VisibilityUpdate(show_on_leaderboard: showOnLeaderboard)

        let _ = try await supabaseClient
            .from("challenge_participants")
            .update(update)
            .eq("challenge_id", value: challengeId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()

        await loadChallenges()
    }
}
