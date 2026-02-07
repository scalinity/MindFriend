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
    @Published private(set) var lastLoadTime: Date?
    
    // Celebration state
    @Published var pendingCelebration: LevelUpEvent?
    @Published var pendingMilestone: MilestoneCelebration?
    @Published var pendingSkillLevelUp: SkillLevelUpEvent?
    @Published var pendingXPGain: XPGainEvent?

    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    // MARK: - Private

    private let supabase: SupabaseClient
    private let authService: SupabaseAuthService

    // XP event queue for handling rapid XP gains
    private var xpEventQueue: [XPGainEvent] = []
    private var isProcessingXPQueue = false

    // MARK: - Init

    init(supabase: SupabaseClient, authService: SupabaseAuthService) {
        self.supabase = supabase
        self.authService = authService
    }

    // MARK: - Experience & Level

    func loadUserExperience() async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw AchievementError.notAuthenticated
        }

        do {
            // Query user_stats table (where actual XP data is stored)
            struct UserStatsRow: Decodable {
                let xpTotal: Int
                let level: Int
                let xpThisWeek: Int

                enum CodingKeys: String, CodingKey {
                    case xpTotal = "xp_total"
                    case level
                    case xpThisWeek = "xp_this_week"
                }
            }

            let statsRow: UserStatsRow = try await supabase
                .from("user_stats")
                .select("xp_total, level, xp_this_week")
                .eq("user_id", value: userId)
                .single()
                .execute()
                .value

            // Calculate XP to next level using thresholds
            // Array is 0-indexed: level 8 user needs index 8 (which is level 9 threshold = 2200)
            let nextLevelIndex = min(statsRow.level, 49)
            let xpToNext = max(0, UserLevel.xpThresholds[nextLevelIndex] - statsRow.xpTotal)

            // FIX: Explicit MainActor wrapping
            await MainActor.run {
                self.userExperience = UserExperience(
                    totalXp: statsRow.xpTotal,
                    currentLevel: statsRow.level,
                    xpToNextLevel: xpToNext,
                    dailyXp: 0,
                    weeklyXp: statsRow.xpThisWeek,
                    prestigeLevel: 0,
                    xpMultiplier: 1.0,
                    multiplierExpiresAt: nil
                )
            }

            Log.data.debug("Loaded user experience: Level \(statsRow.level), XP \(statsRow.xpTotal)")
        } catch {
            // If user_stats row doesn't exist, use default values
            Log.data.warning("Failed to load user stats, using defaults: \(error.localizedDescription)")
            
            await MainActor.run {
                self.userExperience = UserExperience(
                    totalXp: 0,
                    currentLevel: 1,
                    xpToNextLevel: 100,
                    dailyXp: 0,
                    weeklyXp: 0,
                    prestigeLevel: 0,
                    xpMultiplier: 1.0,
                    multiplierExpiresAt: nil
                )
            }
            
            // Don't throw - we have fallback data
        }
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

        // Trigger XP gain toast IMMEDIATELY for instant gratification
        triggerXPGainAnimation(amount: response.xpAwarded, source: source)

        // Trigger level-up celebration if level increased (after XP toast)
        if response.leveledUp, let levelUp = response.levelUp {
            // Delay level-up celebration slightly so XP toast shows first
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                self?.triggerLevelUpCelebration(
                    oldLevel: levelUp.oldLevel,
                    newLevel: levelUp.newLevel,
                    xpEarned: response.xpAwarded
                )
            }
        }

        // Reload user experience in background (don't block the return)
        Task {
            try? await loadUserExperience()
        }

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
        do {
            let response: CheckBadgeProgressResponse = try await supabase.functions
                .invoke("check-badge-progress", options: FunctionInvokeOptions())

            // Reload badge progress FIRST, before updating newlyEarnedBadges
            // This ensures consistency - if reload fails, we don't show stale celebrations
            try await loadUserBadgeProgress()
            
            // Only update celebration state after successful reload
            if !response.newlyEarned.isEmpty {
                let earnedIds = Set(response.newlyEarned.map { $0.id })
                self.newlyEarnedBadges = badges.filter { earnedIds.contains($0.id) }
            }

            return response
        } catch {
            // Edge Function may not exist or may fail - don't crash the app
            Log.data.warning("[Achievements] checkBadgeProgress failed: \(error.localizedDescription)")
            // Return empty response to allow caller to continue
            return CheckBadgeProgressResponse(badgesChecked: 0, newlyEarned: [])
        }
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

        // Query for active seasons (don't use .single() to avoid error when no seasons exist)
        let dbSeasons: [DBSeason] = try await supabase
            .from("seasons")
            .select()
            .eq("is_active", value: true)
            .lte("starts_at", value: now)
            .gte("ends_at", value: now)
            .limit(1)
            .execute()
            .value

        if let dbSeason = dbSeasons.first {
            self.currentSeason = Season(from: dbSeason)
        } else {
            self.currentSeason = nil
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

            await MainActor.run {
                self.lastLoadTime = Date()
                self.isLoading = false
            }
        } catch {
            Log.data.error("Failed to load achievement data", error: error)
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
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
    
    // MARK: - Celebration Management (NEW)
    
    func triggerLevelUpCelebration(oldLevel: Int, newLevel: Int, xpEarned: Int) {
        pendingCelebration = LevelUpEvent(
            oldLevel: oldLevel,
            newLevel: newLevel,
            xpEarned: xpEarned
        )
        
        // Check if this is a milestone level
        let milestones = [5, 10, 25, 50, 100]
        if milestones.contains(newLevel) {
            Task {
                do {
                    let celebration = try await fetchMilestoneNarrative(level: newLevel)
                    pendingMilestone = celebration
                } catch {
                    print("Failed to fetch milestone narrative: \(error)")
                }
            }
        }
    }

    // MARK: - Skill Level Up Celebration

    /// Trigger skill level-up celebration
    func triggerSkillLevelUpCelebration(
        skillType: ExerciseType,
        oldLevel: Int,
        newLevel: Int,
        xpEarned: Int
    ) {
        pendingSkillLevelUp = SkillLevelUpEvent(
            skillType: skillType,
            oldLevel: oldLevel,
            newLevel: newLevel,
            xpEarned: xpEarned
        )
    }

    /// Clear pending skill level-up celebration
    func clearPendingSkillLevelUp() {
        pendingSkillLevelUp = nil
    }

    /// Trigger XP gain toast animation and refresh XP data
    /// Uses a queue to prevent rapid XP gains from being lost
    func triggerXPGainAnimation(amount: Int, source: XPSource) {
        let event = XPGainEvent(amount: amount, source: source)
        xpEventQueue.append(event)

        // Refresh XP data in background so the XP bar updates
        Task {
            try? await loadUserExperience()
        }

        // Process queue if not already processing
        processXPQueue()
    }

    /// Trigger XP gain toast for XPActivity (convenience for views using SupabaseDataService)
    func triggerXPGainAnimation(amount: Int, activity: XPActivity) {
        let source: XPSource = switch activity {
        case .questComplete: .quest
        case .exerciseComplete: .exercise
        case .moodCheckin: .mood
        case .circleCheckin: .checkin
        }
        triggerXPGainAnimation(amount: amount, source: source)
    }

    /// Clear pending XP gain toast and show next queued event
    func clearXPGain() {
        pendingXPGain = nil
        isProcessingXPQueue = false

        // Show next event if queue has more
        processXPQueue()
    }

    /// Process the XP event queue
    private func processXPQueue() {
        guard !isProcessingXPQueue, !xpEventQueue.isEmpty else { return }

        isProcessingXPQueue = true
        let event = xpEventQueue.removeFirst()
        pendingXPGain = event
    }

    func fetchMilestoneNarrative(level: Int) async throws -> MilestoneCelebration {
        struct MilestoneRequest: Encodable {
            let level: Int
        }
        
        struct MilestoneResponse: Decodable {
            let narrative: String
            let celebrationId: String
            let stats: JourneyStats
            
            enum CodingKeys: String, CodingKey {
                case narrative
                case celebrationId = "celebrationId"
                case stats
            }
        }
        
        let request = MilestoneRequest(level: level)
        let response: MilestoneResponse = try await supabase.functions
            .invoke("generate-milestone-narrative", options: .init(body: request))
        
        // Fetch the full celebration record
        let celebration: MilestoneCelebration = try await supabase
            .from("milestone_celebrations")
            .select()
            .eq("id", value: response.celebrationId)
            .single()
            .execute()
            .value
        
        return celebration
    }
    
    func markMilestoneViewed(celebrationId: UUID) async throws {
        try await supabase
            .from("milestone_celebrations")
            .update(["viewed": true])
            .eq("id", value: celebrationId)
            .execute()
    }
}

// MARK: - Level Up Event (NEW)

struct LevelUpEvent: Identifiable {
    let id = UUID()
    let oldLevel: Int
    let newLevel: Int
    let xpEarned: Int
}

// MARK: - Errors

enum AchievementError: LocalizedError {
    case notAuthenticated
    case statsNotFound
    case noShieldsAvailable
    case badgeNotFound
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to access achievements"
        case .statsNotFound:
            return "Stats not found"
        case .noShieldsAvailable:
            return "No streak shields available"
        case .badgeNotFound:
            return "Badge not found"
        case .operationFailed(let message):
            return message
        }
    }
}
