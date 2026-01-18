// MindFriend Achievement Service
// Manages achievements, badges, XP, skill trees, and streaks

import Foundation
import Supabase

// MARK: - Request Types

private struct AwardXPRequest: Encodable {
    let source: String
    let baseAmount: Int
    let sourceId: String?
    let description: String?
    let skillTreeId: String?
}

private struct EmptyRequest: Encodable {}

private struct StreakShieldUpdate: Encodable {
    let shields_available: Int
    let shields_used_this_week: Int
    let last_shield_used_date: String
    let recovery_available: Bool
    let recovery_deadline: String
}

private struct NotifiedUpdate: Encodable {
    let notified_at_90: Bool
}

private struct ShowcasedUpdate: Encodable {
    let is_showcased: Bool
}

@MainActor
final class AchievementService: ObservableObject {
    // MARK: - Published State

    @Published private(set) var userExperience: UserExperience?
    @Published private(set) var badges: [AchievementBadge] = []
    @Published private(set) var userBadgeProgress: [UserBadgeProgress] = []
    @Published private(set) var skillTrees: [SkillTree] = []
    @Published private(set) var userSkillProgress: [UserSkillProgress] = []
    @Published private(set) var streaks: [UserStreak] = []
    @Published private(set) var currentSeason: Season?
    @Published private(set) var weeklyChallenges: [WeeklyChallenge] = []
    @Published private(set) var userChallengeProgress: [UserChallengeProgress] = []
    @Published private(set) var newlyEarnedBadges: [AchievementBadge] = []

    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    // MARK: - Private

    private let supabase: SupabaseClient

    // MARK: - Init

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Experience & Level

    func loadUserExperience() async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AchievementError.notAuthenticated
        }

        let dbExperience: DBUserExperience = try await supabase
            .from("user_experience")
            .select()
            .eq("user_id", value: userId)
            .single()
            .execute()
            .value

        self.userExperience = UserExperience(from: dbExperience)
    }

    func awardXP(source: XPSource, amount: Int, sourceId: UUID? = nil, description: String? = nil, skillTreeId: UUID? = nil) async throws -> AwardXPResponse {
        struct AwardXPRequest: Encodable {
            let source: String
            let baseAmount: Int
            let sourceId: String?
            let description: String?
            let skillTreeId: String?

            enum CodingKeys: String, CodingKey {
                case source
                case baseAmount = "base_amount"
                case sourceId = "source_id"
                case description
                case skillTreeId = "skill_tree_id"
            }
        }

        let request = AwardXPRequest(
            source: source.rawValue,
            baseAmount: amount,
            sourceId: sourceId?.uuidString,
            description: description,
            skillTreeId: skillTreeId?.uuidString
        )

        let response: AwardXPResponse = try await supabase.functions
            .invoke("award-xp", options: .init(body: request))

        // Reload user experience after awarding XP
        try await loadUserExperience()

        return response
    }

    // MARK: - Badges

    func loadBadges() async throws {
        let dbBadges: [DBBadge] = try await supabase
            .from("badges_v2")
            .select()
            .eq("is_active", value: true)
            .order("sort_order")
            .execute()
            .value

        self.badges = dbBadges.map { AchievementBadge(from: $0) }
    }

    func loadUserBadgeProgress() async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AchievementError.notAuthenticated
        }

        // First ensure we have badges loaded
        if badges.isEmpty {
            try await loadBadges()
        }

        let dbUserBadges: [DBUserBadge] = try await supabase
            .from("user_badges_v2")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value

        // Create a badge lookup map
        let badgeMap = Dictionary(uniqueKeysWithValues: badges.map { ($0.id, $0) })

        self.userBadgeProgress = dbUserBadges.compactMap { dbUserBadge in
            guard let badge = badgeMap[dbUserBadge.badgeId] else { return nil }
            return UserBadgeProgress(userBadge: dbUserBadge, badge: badge)
        }
    }

    func checkBadgeProgress() async throws -> CheckBadgeProgressResponse {
        // Empty request body for this endpoint
        let response: CheckBadgeProgressResponse = try await supabase.functions
            .invoke("check-badge-progress", options: FunctionInvokeOptions())

        // Track newly earned badges for UI celebration
        if !response.newlyEarned.isEmpty {
            let earnedIds = Set(response.newlyEarned.map { $0.id })
            self.newlyEarnedBadges = badges.filter { earnedIds.contains($0.id) }
        }

        // Reload badge progress
        try await loadUserBadgeProgress()

        return response
    }

    func markBadgeAsSeen(badgeId: UUID) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AchievementError.notAuthenticated
        }

        // Mark as notified at 90% (which we use as the "seen" indicator)
        try await supabase
            .from("user_badges_v2")
            .update(NotifiedUpdate(notified_at_90: true))
            .eq("user_id", value: userId)
            .eq("badge_id", value: badgeId)
            .execute()

        // Remove from newly earned
        newlyEarnedBadges.removeAll { $0.id == badgeId }

        // Update local state
        if userBadgeProgress.contains(where: { $0.badge.id == badgeId }) {
            // Reload the updated badge progress
            try await loadUserBadgeProgress()
        }
    }

    func toggleBadgeFavorite(badgeId: UUID, isFavorite: Bool) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AchievementError.notAuthenticated
        }

        // Use is_showcased column (maps to isFavorite in UI)
        try await supabase
            .from("user_badges_v2")
            .update(ShowcasedUpdate(is_showcased: isFavorite))
            .eq("user_id", value: userId)
            .eq("badge_id", value: badgeId)
            .execute()

        try await loadUserBadgeProgress()
    }

    // MARK: - Skill Trees

    func loadSkillTrees() async throws {
        let dbSkillTrees: [DBSkillTree] = try await supabase
            .from("skill_trees")
            .select()
            .eq("is_active", value: true)
            .order("name")
            .execute()
            .value

        let dbNodes: [DBSkillTreeNode] = try await supabase
            .from("skill_tree_nodes")
            .select()
            .order("tier")
            .order("position")
            .execute()
            .value

        // Group nodes by tree ID
        let nodesByTree = Dictionary(grouping: dbNodes) { $0.treeId }

        self.skillTrees = dbSkillTrees.map { dbTree in
            let treeNodes = nodesByTree[dbTree.id] ?? []
            return SkillTree(from: dbTree, nodes: treeNodes)
        }
    }

    func loadUserSkillProgress() async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AchievementError.notAuthenticated
        }

        // Ensure skill trees are loaded
        if skillTrees.isEmpty {
            try await loadSkillTrees()
        }

        let dbProgress: [DBUserSkillProgress] = try await supabase
            .from("user_skill_progress")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value

        let treeMap = Dictionary(uniqueKeysWithValues: skillTrees.map { ($0.id, $0) })

        self.userSkillProgress = dbProgress.compactMap { dbProg in
            guard let tree = treeMap[dbProg.treeId] else { return nil }
            return UserSkillProgress(from: dbProg, tree: tree)
        }
    }

    // MARK: - Streaks

    func loadStreaks() async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AchievementError.notAuthenticated
        }

        let dbStreaks: [DBUserStreak] = try await supabase
            .from("user_streaks_v2")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value

        self.streaks = dbStreaks.map { UserStreak(from: $0) }
    }

    func useStreakShield(streakType: StreakType) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AchievementError.notAuthenticated
        }

        // Get current streak
        guard let streak = streaks.first(where: { $0.streakType == streakType }),
              streak.shieldsRemaining > 0 else {
            throw AchievementError.noShieldsAvailable
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let updates = StreakShieldUpdate(
            shields_available: streak.shieldsRemaining - 1,
            shields_used_this_week: streak.shieldsUsedThisWeek + 1,
            last_shield_used_date: dateFormatter.string(from: Date()),
            recovery_available: true,
            recovery_deadline: ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        )

        try await supabase
            .from("user_streaks_v2")
            .update(updates)
            .eq("user_id", value: userId)
            .eq("streak_type", value: streakType.rawValue)
            .execute()

        try await loadStreaks()
    }

    // MARK: - Seasons

    func loadCurrentSeason() async throws {
        let now = ISO8601DateFormatter().string(from: Date())

        let dbSeason: DBSeason? = try await supabase
            .from("seasons")
            .select()
            .eq("is_active", value: true)
            .lte("starts_at", value: now)
            .gte("ends_at", value: now)
            .single()
            .execute()
            .value

        if let dbSeason = dbSeason {
            self.currentSeason = Season(from: dbSeason)
        }
    }

    // MARK: - Weekly Challenges

    func loadWeeklyChallenges() async throws {
        // Get the start of the current week (Monday)
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysToMonday = weekday == 1 ? -6 : 2 - weekday
        let mondayDate = calendar.date(byAdding: .day, value: daysToMonday, to: today) ?? today

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let weekStartString = dateFormatter.string(from: mondayDate)

        let dbChallenges: [DBWeeklyChallenge] = try await supabase
            .from("weekly_challenges")
            .select()
            .eq("is_active", value: true)
            .eq("week_start", value: weekStartString)
            .execute()
            .value

        self.weeklyChallenges = dbChallenges.map { WeeklyChallenge(from: $0) }
    }

    func loadUserChallengeProgress() async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AchievementError.notAuthenticated
        }

        // Ensure challenges are loaded
        if weeklyChallenges.isEmpty {
            try await loadWeeklyChallenges()
        }

        let challengeIds = weeklyChallenges.map { $0.id }
        guard !challengeIds.isEmpty else {
            self.userChallengeProgress = []
            return
        }

        let dbProgress: [DBUserChallengeProgress] = try await supabase
            .from("user_challenge_progress")
            .select()
            .eq("user_id", value: userId)
            .in("challenge_id", values: challengeIds)
            .execute()
            .value

        let challengeMap = Dictionary(uniqueKeysWithValues: weeklyChallenges.map { ($0.id, $0) })

        self.userChallengeProgress = dbProgress.compactMap { dbProg in
            guard let challenge = challengeMap[dbProg.challengeId] else { return nil }
            return UserChallengeProgress(from: dbProg, challenge: challenge)
        }
    }

    // MARK: - Load All Data

    func loadAllAchievementData() async {
        isLoading = true
        error = nil

        do {
            async let experienceTask: () = loadUserExperience()
            async let badgesTask: () = loadBadges()
            async let skillTreesTask: () = loadSkillTrees()
            async let streaksTask: () = loadStreaks()
            async let seasonTask: () = loadCurrentSeason()
            async let challengesTask: () = loadWeeklyChallenges()

            _ = try await (experienceTask, badgesTask, skillTreesTask, streaksTask, seasonTask, challengesTask)

            // These depend on the above
            async let badgeProgressTask: () = loadUserBadgeProgress()
            async let skillProgressTask: () = loadUserSkillProgress()
            async let challengeProgressTask: () = loadUserChallengeProgress()

            _ = try await (badgeProgressTask, skillProgressTask, challengeProgressTask)

            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    // MARK: - Computed Properties

    var earnedBadges: [UserBadgeProgress] {
        userBadgeProgress.filter { $0.isEarned }
    }

    var inProgressBadges: [UserBadgeProgress] {
        userBadgeProgress.filter { !$0.isEarned && $0.progressCurrent > 0 }
    }

    var favoriteBadges: [UserBadgeProgress] {
        userBadgeProgress.filter { $0.isFavorite }
    }

    var questStreak: UserStreak? {
        streaks.first { $0.streakType == .quest }
    }

    func badgesInCategory(_ category: BadgeCategory) -> [AchievementBadge] {
        badges.filter { $0.category == category }
    }

    func progressForBadge(_ badgeId: UUID) -> UserBadgeProgress? {
        userBadgeProgress.first { $0.badge.id == badgeId }
    }
}

// MARK: - Errors

enum AchievementError: LocalizedError {
    case notAuthenticated
    case noShieldsAvailable
    case badgeNotFound
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to access achievements"
        case .noShieldsAvailable:
            return "No streak shields available"
        case .badgeNotFound:
            return "Badge not found"
        case .operationFailed(let message):
            return message
        }
    }
}
