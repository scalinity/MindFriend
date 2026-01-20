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
    private var realtimeChannel: RealtimeChannel?
    private var cancellables = Set<AnyCancellable>()

    init(supabaseClient: SupabaseClient = SupabaseClient.shared) {
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

            let (publicChalls, circleChalls, myChalls) = await (publicResult, circleResult, myResult)

            self.publicChallenges = publicChalls
            self.circleChallenges = circleChalls
            self.myChallenges = myChalls
        } catch let err as ChallengeError {
            error = err
        } catch {
            error = .loadFailed
        }
    }

    private func fetchPublicChallenges(userId: UUID) async throws -> [ChallengeWithParticipation] {
        let results: [[String: Any]] = try await supabaseClient
            .rpc("get_public_challenges_with_participation", params: ["p_user_id": userId])
            .execute()
            .value
        
        return results.compactMap { dict -> ChallengeWithParticipation? in
            guard let id = dict["id"] as? String,
                  let title = dict["title"] as? String,
                  let description = dict["description"] as? String,
                  let typeStr = dict["challenge_type"] as? String,
                  let targetValue = dict["target_value"] as? Int,
                  let createdBy = dict["created_by"] as? String,
                  let isPublic = dict["is_public"] as? Bool,
                  let createdAt = dict["created_at"] as? String,
                  let startsAt = dict["starts_at"] as? String,
                  let endsAt = dict["ends_at"] as? String,
                  let participantCount = dict["participant_count"] as? Int
            else { return nil }
            
            let type = SocialChallengeType(rawValue: typeStr) ?? .quest
            let circleId = dict["circle_id"] as? String
            let exerciseType = dict["exercise_type"] as? String
            
            let challenge = SocialChallenge(
                id: UUID(uuidString: id) ?? UUID(),
                title: title,
                description: description,
                type: type,
                targetValue: targetValue,
                createdBy: UUID(uuidString: createdBy) ?? UUID(),
                circleId: circleId.flatMap { UUID(uuidString: $0) },
                isPublic: isPublic,
                createdAt: ISO8601DateFormatter().date(from: createdAt) ?? Date(),
                startsAt: ISO8601DateFormatter().date(from: startsAt) ?? Date(),
                endsAt: ISO8601DateFormatter().date(from: endsAt) ?? Date(),
                exerciseType: exerciseType
            )
            
            var participation: ChallengeParticipant? = nil
            if let userParticipated = dict["user_participated"] as? Bool, userParticipated {
                let progress = dict["user_current_progress"] as? Int ?? 0
                let joinedAtStr = dict["user_joined_at"] as? String ?? ""
                let showOnLeaderboard = dict["user_show_on_leaderboard"] as? Bool ?? false
                
                participation = ChallengeParticipant(
                    challengeId: challenge.id,
                    userId: userId,
                    currentProgress: progress,
                    joinedAt: ISO8601DateFormatter().date(from: joinedAtStr) ?? Date(),
                    showOnLeaderboard: showOnLeaderboard
                )
            }
            
            return ChallengeWithParticipation(
                challenge: challenge,
                participation: participation,
                participantCount: participantCount
            )
        }
    }

    private func fetchCircleChallenges(userId: UUID) async throws -> [ChallengeWithParticipation] {
        let results: [[String: Any]] = try await supabaseClient
            .rpc("get_circle_challenges_with_participation", params: ["p_user_id": userId])
            .execute()
            .value
        
        return results.compactMap { dict -> ChallengeWithParticipation? in
            guard let id = dict["id"] as? String,
                  let title = dict["title"] as? String,
                  let description = dict["description"] as? String,
                  let typeStr = dict["challenge_type"] as? String,
                  let targetValue = dict["target_value"] as? Int,
                  let createdBy = dict["created_by"] as? String,
                  let isPublic = dict["is_public"] as? Bool,
                  let createdAt = dict["created_at"] as? String,
                  let startsAt = dict["starts_at"] as? String,
                  let endsAt = dict["ends_at"] as? String,
                  let participantCount = dict["participant_count"] as? Int
            else { return nil }
            
            let type = SocialChallengeType(rawValue: typeStr) ?? .quest
            let circleId = dict["circle_id"] as? String
            let exerciseType = dict["exercise_type"] as? String
            
            let challenge = SocialChallenge(
                id: UUID(uuidString: id) ?? UUID(),
                title: title,
                description: description,
                type: type,
                targetValue: targetValue,
                createdBy: UUID(uuidString: createdBy) ?? UUID(),
                circleId: circleId.flatMap { UUID(uuidString: $0) },
                isPublic: isPublic,
                createdAt: ISO8601DateFormatter().date(from: createdAt) ?? Date(),
                startsAt: ISO8601DateFormatter().date(from: startsAt) ?? Date(),
                endsAt: ISO8601DateFormatter().date(from: endsAt) ?? Date(),
                exerciseType: exerciseType
            )
            
            var participation: ChallengeParticipant? = nil
            if let userParticipated = dict["user_participated"] as? Bool, userParticipated {
                let progress = dict["user_current_progress"] as? Int ?? 0
                let joinedAtStr = dict["user_joined_at"] as? String ?? ""
                let showOnLeaderboard = dict["user_show_on_leaderboard"] as? Bool ?? false
                
                participation = ChallengeParticipant(
                    challengeId: challenge.id,
                    userId: userId,
                    currentProgress: progress,
                    joinedAt: ISO8601DateFormatter().date(from: joinedAtStr) ?? Date(),
                    showOnLeaderboard: showOnLeaderboard
                )
            }
            
            return ChallengeWithParticipation(
                challenge: challenge,
                participation: participation,
                participantCount: participantCount
            )
        }
    }

    private func fetchJoinedChallenges(userId: UUID) async throws -> [ChallengeWithParticipation] {
        let results: [[String: Any]] = try await supabaseClient
            .rpc("get_joined_challenges_with_details", params: ["p_user_id": userId])
            .execute()
            .value
        
        return results.compactMap { dict -> ChallengeWithParticipation? in
            guard let id = dict["id"] as? String,
                  let title = dict["title"] as? String,
                  let description = dict["description"] as? String,
                  let typeStr = dict["challenge_type"] as? String,
                  let targetValue = dict["target_value"] as? Int,
                  let createdBy = dict["created_by"] as? String,
                  let isPublic = dict["is_public"] as? Bool,
                  let createdAt = dict["created_at"] as? String,
                  let startsAt = dict["starts_at"] as? String,
                  let endsAt = dict["ends_at"] as? String,
                  let progress = dict["user_current_progress"] as? Int,
                  let joinedAtStr = dict["user_joined_at"] as? String,
                  let showOnLeaderboard = dict["user_show_on_leaderboard"] as? Bool,
                  let participantCount = dict["participant_count"] as? Int
            else { return nil }
            
            let type = SocialChallengeType(rawValue: typeStr) ?? .quest
            let circleId = dict["circle_id"] as? String
            let exerciseType = dict["exercise_type"] as? String
            
            let challenge = SocialChallenge(
                id: UUID(uuidString: id) ?? UUID(),
                title: title,
                description: description,
                type: type,
                targetValue: targetValue,
                createdBy: UUID(uuidString: createdBy) ?? UUID(),
                circleId: circleId.flatMap { UUID(uuidString: $0) },
                isPublic: isPublic,
                createdAt: ISO8601DateFormatter().date(from: createdAt) ?? Date(),
                startsAt: ISO8601DateFormatter().date(from: startsAt) ?? Date(),
                endsAt: ISO8601DateFormatter().date(from: endsAt) ?? Date(),
                exerciseType: exerciseType
            )
            
            let participation = ChallengeParticipant(
                challengeId: challenge.id,
                userId: userId,
                currentProgress: progress,
                joinedAt: ISO8601DateFormatter().date(from: joinedAtStr) ?? Date(),
                showOnLeaderboard: showOnLeaderboard
            )
            
            return ChallengeWithParticipation(
                challenge: challenge,
                participation: participation,
                participantCount: participantCount
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

        // Check rate limit
        let canJoin: Bool = try await supabaseClient
            .rpc("check_join_rate_limit", params: ["p_user_id": userId])
            .execute()
            .value

        guard canJoin else {
            throw ChallengeError.rateLimited
        }

        // Create participation
        let _ = try await supabaseClient
            .from("challenge_participants")
            .insert(["challenge_id": challengeId, "user_id": userId, "show_on_leaderboard": showOnLeaderboard])
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
            .eq("challenge_id", value: challengeId)
            .eq("user_id", value: userId)
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

        let leaderboard: [[String: Any]] = try await supabaseClient
            .rpc("get_challenge_leaderboard", params: [
                "p_challenge_id": challengeId,
                "p_user_id": userId,
                "p_limit": limit,
                "p_offset": offset
            ])
            .execute()
            .value

        var entries: [LeaderboardEntry] = []

        for entry in leaderboard {
            if let participantData = entry as? [String: Any],
               let userIdValue = participantData["user_id"] as? String,
               let uuid = UUID(uuidString: userIdValue),
               let rank = participantData["rank_position"] as? Int,
               let progress = participantData["current_progress"] as? Int,
               let displayName = participantData["user_display_name"] as? String
            {
                let avatarUrl = participantData["user_avatar_url"] as? String
                let isTied = participantData["is_tied"] as? Bool ?? false

                let userProfile = UserProfile(
                    id: uuid,
                    displayName: displayName,
                    avatarUrl: avatarUrl
                )

                let participant = ChallengeParticipant(
                    id: UUID(),
                    challengeId: challengeId,
                    userId: uuid,
                    currentProgress: progress,
                    completed: false,
                    completedAt: nil,
                    finalRank: rank,
                    showOnLeaderboard: true,
                    joinedAt: Date(),
                    updatedAt: Date()
                )

                let leaderboardEntry = LeaderboardEntry(
                    participant: participant,
                    userProfile: userProfile,
                    rank: rank,
                    isCurrentUser: uuid == userId,
                    isTied: isTied
                )

                entries.append(leaderboardEntry)
            }
        }

        return entries
    }

    // MARK: - Real-Time Updates

    func subscribeToLeaderboard(
        _ challengeId: UUID,
        onUpdate: @escaping ([LeaderboardEntry]) -> Void
    ) async throws {
        let channelName = "challenge:\(challengeId)"

        realtimeChannel = supabaseClient.channel(channelName)

        realtimeChannel?.onPostgresChange(
            event: .all,
            schema: "public",
            table: "challenge_participants",
            filter: PostgresChangeFilter(
                column: "challenge_id",
                type: "eq",
                value: challengeId.uuidString
            )
        ) { [weak self] payload in
            Task { @MainActor in
                do {
                    let leaderboard = try await self?.getLeaderboard(challengeId)
                    if let leaderboard = leaderboard {
                        onUpdate(leaderboard)
                    }
                } catch {
                    print("Error updating leaderboard: \(error)")
                }
            }
        }

        try await realtimeChannel?.subscribe()
    }

    func unsubscribeFromLeaderboard() async {
        guard let channel = realtimeChannel else { return }
        await channel.unsubscribe()
        realtimeChannel = nil
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
            .rpc("check_challenge_creation_rate_limit", params: ["p_user_id": userId])
            .execute()
            .value

        guard canCreate else {
            throw ChallengeError.rateLimited
        }

        let now = Date()
        let endsAt = Calendar.current.date(byAdding: .day, value: durationDays, to: now) ?? now

        let _ = try await supabaseClient
            .from("challenges")
            .insert([
                "title": title,
                "description": description,
                "challenge_type": challengeType.rawValue,
                "target_value": targetValue,
                "duration_days": durationDays,
                "is_public": circleId == nil,
                "circle_id": circleId,
                "created_by": userId,
                "exercise_type": exerciseType,
                "starts_at": ISO8601DateFormatter().string(from: now),
                "ends_at": ISO8601DateFormatter().string(from: endsAt)
            ])
            .execute()

        // Auto-join creator
        if let challengeId: [["id": UUID]] = try? await supabaseClient
            .from("challenges")
            .select("id")
            .eq("created_by", value: userId)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value,
           let firstChallenge = challengeId.first
        {
            guard let challengeId = firstChallenge["id"] as? String else {
                return
            }
            try await joinChallenge(challengeId, showOnLeaderboard: true)
        }

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

        let _ = try await supabaseClient
            .from("challenge_participants")
            .update(["show_on_leaderboard": showOnLeaderboard])
            .eq("challenge_id", value: challengeId)
            .eq("user_id", value: userId)
            .execute()

        await loadChallenges()
    }
}

// MARK: - UserProfile (simple model for leaderboard)
extension ChallengeService {
    struct UserProfile {
        let id: UUID
        let displayName: String?
        let avatarUrl: String?
    }
}
