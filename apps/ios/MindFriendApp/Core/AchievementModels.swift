// MindFriend Achievement Models
// Data models for gamification: badges, XP, skill trees, streaks, seasons, and challenges

import Foundation

// MARK: - Enums

enum BadgeCategory: String, Codable, CaseIterable {
    case gettingStarted = "getting_started"
    case streaks = "streaks"
    case quests = "quests"
    case exercises = "exercises"
    case meditation = "meditation"
    case mood = "mood"
    case circles = "circles"
    case sensory = "sensory"
    case special = "special"
    case seasonal = "seasonal"

    var displayName: String {
        switch self {
        case .gettingStarted: return "Getting Started"
        case .streaks: return "Streaks"
        case .quests: return "Quests"
        case .exercises: return "Exercises"
        case .meditation: return "Meditation"
        case .mood: return "Mood"
        case .circles: return "Circles"
        case .sensory: return "Sensory Regulation"
        case .special: return "Special"
        case .seasonal: return "Seasonal"
        }
    }
}

enum BadgeTier: String, Codable {
    case bronze
    case silver
    case gold
    case diamond
    case legendary

    var displayName: String {
        rawValue.capitalized
    }

    var color: String {
        switch self {
        case .bronze: return "#CD7F32"
        case .silver: return "#C0C0C0"
        case .gold: return "#FFD700"
        case .diamond: return "#B9F2FF"
        case .legendary: return "#9400D3"
        }
    }
}

enum BadgeRarity: String, Codable {
    case common
    case uncommon
    case rare
    case epic
    case legendary

    var displayName: String {
        rawValue.capitalized
    }
}

enum StreakType: String, Codable, CaseIterable {
    case quest
    case mood
    case exercise
    case meditation
    case checkin
    case sensory
    case appOpen = "app_open"

    var displayName: String {
        switch self {
        case .quest: return "Quest Streak"
        case .mood: return "Mood Logging"
        case .exercise: return "Exercise"
        case .meditation: return "Meditation"
        case .checkin: return "Check-in"
        case .appOpen: return "Daily App Open"
        }
    }
}

enum XPSource: String, Codable {
    case quest
    case exercise
    case mood
    case badge
    case streak
    case bonus
    case meditation
    case checkin
}

// MARK: - Database Models

struct DBBadge: Codable {
    let id: UUID
    let slug: String
    let name: String
    let description: String
    let iconUrl: String
    let backgroundColor: String?
    let animationType: String?
    let category: String
    let subcategory: String?
    let tier: String?
    let tierOrder: Int?
    let parentBadgeId: UUID?
    let requirementType: String
    let requirementConfig: [String: AnyCodable]
    let progressTrackable: Bool?
    let progressMetric: String?
    let rarity: String
    let isSecret: Bool
    let revealHint: String?
    let isSeasonal: Bool
    let seasonId: UUID?
    let availableFrom: String?
    let availableUntil: String?
    let xpReward: Int
    let unlockContent: [String: AnyCodable]?
    let totalEarners: Int
    let isActive: Bool
    let sortOrder: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, slug, name, description
        case iconUrl = "icon_url"
        case backgroundColor = "background_color"
        case animationType = "animation_type"
        case category, subcategory, tier
        case tierOrder = "tier_order"
        case parentBadgeId = "parent_badge_id"
        case requirementType = "requirement_type"
        case requirementConfig = "requirement_config"
        case progressTrackable = "progress_trackable"
        case progressMetric = "progress_metric"
        case rarity
        case isSecret = "is_secret"
        case revealHint = "reveal_hint"
        case isSeasonal = "is_seasonal"
        case seasonId = "season_id"
        case availableFrom = "available_from"
        case availableUntil = "available_until"
        case xpReward = "xp_reward"
        case unlockContent = "unlock_content"
        case totalEarners = "total_earners"
        case isActive = "is_active"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}

struct DBUserBadge: Codable {
    let id: UUID
    let userId: UUID
    let badgeId: UUID
    let progressCurrent: Int
    let progressTarget: Int?
    let progressPercentage: Double?
    let earnedAt: String?
    let isEarned: Bool
    let sharedToCircle: Bool
    let isShowcased: Bool
    let notifiedAt50: Bool
    let notifiedAt75: Bool
    let notifiedAt90: Bool
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case badgeId = "badge_id"
        case progressCurrent = "progress_current"
        case progressTarget = "progress_target"
        case progressPercentage = "progress_percentage"
        case earnedAt = "earned_at"
        case isEarned = "is_earned"
        case sharedToCircle = "shared_to_circle"
        case isShowcased = "is_showcased"
        case notifiedAt50 = "notified_at_50"
        case notifiedAt75 = "notified_at_75"
        case notifiedAt90 = "notified_at_90"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DBUserExperience: Codable {
    let id: UUID
    let userId: UUID
    let totalXp: Int
    let currentLevel: Int
    let xpToNextLevel: Int
    let dailyXp: Int
    let dailyXpDate: String?
    let weeklyXp: Int
    let weekStartDate: String?
    let prestigeLevel: Int
    let xpMultiplier: Double
    let multiplierExpiresAt: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case totalXp = "total_xp"
        case currentLevel = "current_level"
        case xpToNextLevel = "xp_to_next_level"
        case dailyXp = "daily_xp"
        case dailyXpDate = "daily_xp_date"
        case weeklyXp = "weekly_xp"
        case weekStartDate = "week_start_date"
        case prestigeLevel = "prestige_level"
        case xpMultiplier = "xp_multiplier"
        case multiplierExpiresAt = "multiplier_expires_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DBSkillTree: Codable {
    let id: UUID
    let slug: String
    let name: String
    let description: String?
    let iconUrl: String?
    let color: String?
    let maxLevel: Int
    let isActive: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, slug, name, description
        case iconUrl = "icon_url"
        case color
        case maxLevel = "max_level"
        case isActive = "is_active"
        case createdAt = "created_at"
    }
}

struct DBSkillTreeNode: Codable {
    let id: UUID
    let treeId: UUID
    let slug: String
    let name: String
    let description: String?
    let iconUrl: String?
    let tier: Int
    let position: Int
    let prerequisiteNodes: [UUID]?
    let unlockType: String
    let unlockConfig: [String: AnyCodable]
    let xpReward: Int
    let badgeRewardId: UUID?
    let unlockContent: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case id
        case treeId = "tree_id"
        case slug, name, description
        case iconUrl = "icon_url"
        case tier, position
        case prerequisiteNodes = "prerequisite_nodes"
        case unlockType = "unlock_type"
        case unlockConfig = "unlock_config"
        case xpReward = "xp_reward"
        case badgeRewardId = "badge_reward_id"
        case unlockContent = "unlock_content"
    }
}

struct DBUserSkillProgress: Codable {
    let id: UUID
    let userId: UUID
    let treeId: UUID
    let currentLevel: Int
    let currentXp: Int
    let totalXp: Int
    let unlockedNodes: [UUID]
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case treeId = "tree_id"
        case currentLevel = "current_level"
        case currentXp = "current_xp"
        case totalXp = "total_xp"
        case unlockedNodes = "unlocked_nodes"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DBUserStreak: Codable {
    let id: UUID
    let userId: UUID
    let streakType: String
    let currentCount: Int
    let longestCount: Int
    let lastActivityDate: String?
    let streakStartDate: String?
    let shieldsAvailable: Int
    let shieldsUsedThisWeek: Int
    let lastShieldUsedDate: String?
    let recoveryAvailable: Bool
    let recoveryDeadline: String?
    let brokenStreakCount: Int?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case streakType = "streak_type"
        case currentCount = "current_count"
        case longestCount = "longest_count"
        case lastActivityDate = "last_activity_date"
        case streakStartDate = "streak_start_date"
        case shieldsAvailable = "shields_available"
        case shieldsUsedThisWeek = "shields_used_this_week"
        case lastShieldUsedDate = "last_shield_used_date"
        case recoveryAvailable = "recovery_available"
        case recoveryDeadline = "recovery_deadline"
        case brokenStreakCount = "broken_streak_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct DBSeason: Codable {
    let id: UUID
    let slug: String
    let name: String
    let description: String?
    let theme: String?
    let bannerUrl: String?
    let colorPrimary: String?
    let colorSecondary: String?
    let startsAt: String
    let endsAt: String
    let freeTrackRewards: [String: AnyCodable]?
    let premiumTrackRewards: [String: AnyCodable]?
    let isActive: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, slug, name, description, theme
        case bannerUrl = "banner_url"
        case colorPrimary = "color_primary"
        case colorSecondary = "color_secondary"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case freeTrackRewards = "free_track_rewards"
        case premiumTrackRewards = "premium_track_rewards"
        case isActive = "is_active"
        case createdAt = "created_at"
    }
}

struct DBWeeklyChallenge: Codable {
    let id: UUID
    let weekStart: String
    let title: String
    let description: String?
    let challengeType: String
    let targetValue: Int
    let xpReward: Int
    let badgeRewardId: UUID?
    let isActive: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case weekStart = "week_start"
        case title, description
        case challengeType = "challenge_type"
        case targetValue = "target_value"
        case xpReward = "xp_reward"
        case badgeRewardId = "badge_reward_id"
        case isActive = "is_active"
        case createdAt = "created_at"
    }
}

struct DBUserChallengeProgress: Codable {
    let id: UUID
    let userId: UUID
    let challengeId: UUID
    let currentProgress: Int
    let completedAt: String?
    let rewardClaimed: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case challengeId = "challenge_id"
        case currentProgress = "current_progress"
        case completedAt = "completed_at"
        case rewardClaimed = "reward_claimed"
    }
}

// MARK: - Domain Models

/// Achievement System 2.0 badge (renamed to avoid conflict with MVP Badge in Models.swift)
struct AchievementBadge: Identifiable, Hashable {
    let id: UUID
    let slug: String
    let name: String
    let description: String
    let iconUrl: String
    let category: BadgeCategory
    let subcategory: String?
    let tier: BadgeTier?
    let tierOrder: Int?
    let parentBadgeId: UUID?
    let requirementType: String
    let requirementConfig: [String: AnyCodable]
    let rarity: BadgeRarity
    let isSecret: Bool
    let revealHint: String?
    let isSeasonal: Bool
    let xpReward: Int
    let earnedByCount: Int
    let sortOrder: Int

    init(from db: DBBadge) {
        self.id = db.id
        self.slug = db.slug
        self.name = db.name
        self.description = db.description
        self.iconUrl = db.iconUrl
        self.category = BadgeCategory(rawValue: db.category) ?? .special
        self.subcategory = db.subcategory
        self.tier = db.tier.flatMap { BadgeTier(rawValue: $0) }
        self.tierOrder = db.tierOrder
        self.parentBadgeId = db.parentBadgeId
        self.requirementType = db.requirementType
        self.requirementConfig = db.requirementConfig
        self.rarity = BadgeRarity(rawValue: db.rarity) ?? .common
        self.isSecret = db.isSecret
        self.revealHint = db.revealHint
        self.isSeasonal = db.isSeasonal
        self.xpReward = db.xpReward
        self.earnedByCount = db.totalEarners
        self.sortOrder = db.sortOrder
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AchievementBadge, rhs: AchievementBadge) -> Bool {
        lhs.id == rhs.id
    }
}

struct UserBadgeProgress: Identifiable {
    let id: UUID
    let badge: AchievementBadge
    let progressCurrent: Int
    let progressTarget: Int?
    let progressPercentage: Double
    let isEarned: Bool
    let earnedAt: Date?
    let isShowcased: Bool
    let isNew: Bool

    // Computed for backward compatibility in views
    var isFavorite: Bool { isShowcased }

    init(userBadge: DBUserBadge, badge: AchievementBadge) {
        self.id = userBadge.id
        self.badge = badge
        self.progressCurrent = userBadge.progressCurrent
        self.progressTarget = userBadge.progressTarget
        self.progressPercentage = userBadge.progressPercentage.map { $0 / 100.0 } ?? 0.0
        self.isEarned = userBadge.isEarned
        self.earnedAt = userBadge.earnedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        self.isShowcased = userBadge.isShowcased
        // Consider a badge "new" if it was recently earned and not yet notified at 100%
        self.isNew = userBadge.isEarned && !userBadge.notifiedAt90
    }
}

struct UserExperience {
    let totalXp: Int
    let currentLevel: Int
    let xpToNextLevel: Int
    let dailyXp: Int
    let weeklyXp: Int
    let prestigeLevel: Int
    let xpMultiplier: Double
    let multiplierExpiresAt: Date?

    var progressToNextLevel: Double {
        guard xpToNextLevel > 0 else { return 0 }
        // Calculate XP required to reach current level
        let xpForCurrentLevel = 50 * (currentLevel - 1) * (currentLevel - 1)
        let xpForNextLevel = 50 * currentLevel * currentLevel
        let xpInCurrentLevel = totalXp - xpForCurrentLevel
        let xpNeededForLevel = xpForNextLevel - xpForCurrentLevel
        return Double(xpInCurrentLevel) / Double(xpNeededForLevel)
    }

    /// Memberwise initializer for constructing from profile stats
    init(
        totalXp: Int,
        currentLevel: Int,
        xpToNextLevel: Int,
        dailyXp: Int,
        weeklyXp: Int,
        prestigeLevel: Int,
        xpMultiplier: Double,
        multiplierExpiresAt: Date?
    ) {
        self.totalXp = totalXp
        self.currentLevel = currentLevel
        self.xpToNextLevel = xpToNextLevel
        self.dailyXp = dailyXp
        self.weeklyXp = weeklyXp
        self.prestigeLevel = prestigeLevel
        self.xpMultiplier = xpMultiplier
        self.multiplierExpiresAt = multiplierExpiresAt
    }

    init(from db: DBUserExperience) {
        self.totalXp = db.totalXp
        self.currentLevel = db.currentLevel
        self.xpToNextLevel = db.xpToNextLevel
        self.dailyXp = db.dailyXp
        self.weeklyXp = db.weeklyXp
        self.prestigeLevel = db.prestigeLevel
        self.xpMultiplier = db.xpMultiplier
        self.multiplierExpiresAt = db.multiplierExpiresAt.flatMap { ISO8601DateFormatter().date(from: $0) }
    }
}

struct SkillTree: Identifiable, Hashable {
    let id: UUID
    let slug: String
    let name: String
    let description: String
    let iconUrl: String
    let color: String
    let maxLevel: Int
    let nodes: [SkillTreeNode]

    init(from db: DBSkillTree, nodes: [DBSkillTreeNode]) {
        self.id = db.id
        self.slug = db.slug
        self.name = db.name
        self.description = db.description ?? ""
        self.iconUrl = db.iconUrl ?? ""
        self.color = db.color ?? "#7C3AED"
        self.maxLevel = db.maxLevel
        self.nodes = nodes
            .sorted { ($0.tier, $0.position) < ($1.tier, $1.position) }
            .map { SkillTreeNode(from: $0) }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SkillTree, rhs: SkillTree) -> Bool {
        lhs.id == rhs.id
    }
}

struct SkillTreeNode: Identifiable {
    let id: UUID
    let treeId: UUID
    let slug: String
    let name: String
    let description: String
    let iconUrl: String?
    let tier: Int
    let position: Int
    let prerequisiteNodeIds: [UUID]
    let unlockType: String
    let xpRequired: Int
    let xpReward: Int
    let badgeRewardId: UUID?

    var levelRequired: Int {
        // Approximate level based on XP required using formula: level = sqrt(xp / 50) + 1
        guard xpRequired > 0 else { return 1 }
        return Int(sqrt(Double(xpRequired) / 50.0)) + 1
    }

    init(from db: DBSkillTreeNode) {
        self.id = db.id
        self.treeId = db.treeId
        self.slug = db.slug
        self.name = db.name
        self.description = db.description ?? ""
        self.iconUrl = db.iconUrl
        self.tier = db.tier
        self.position = db.position
        self.prerequisiteNodeIds = db.prerequisiteNodes ?? []
        self.unlockType = db.unlockType
        
        // Extract xp_required from AnyCodable dictionary
        var xpRequired = 0
        if case .int(let value) = db.unlockConfig["xp_required"] {
            xpRequired = value
        }
        self.xpRequired = xpRequired
        
        self.xpReward = db.xpReward
        self.badgeRewardId = db.badgeRewardId
    }
}

struct UserSkillProgress: Identifiable {
    let id: UUID
    let tree: SkillTree
    let currentLevel: Int
    let currentXp: Int
    let totalXp: Int
    let unlockedNodeIds: Set<UUID>

    var progressToNextLevel: Double {
        guard tree.maxLevel > 0, currentLevel < tree.maxLevel else { return 1.0 }
        // Calculate XP required for levels using formula: total_xp = 50 * (level-1)^2
        let xpForCurrentLevel = 50 * (currentLevel - 1) * (currentLevel - 1)
        let xpForNextLevel = 50 * currentLevel * currentLevel
        let xpInCurrentLevel = totalXp - xpForCurrentLevel
        let xpNeededForLevel = xpForNextLevel - xpForCurrentLevel
        guard xpNeededForLevel > 0 else { return 0 }
        return Double(xpInCurrentLevel) / Double(xpNeededForLevel)
    }

    init(from db: DBUserSkillProgress, tree: SkillTree) {
        self.id = db.id
        self.tree = tree
        self.currentLevel = db.currentLevel
        self.currentXp = db.currentXp
        self.totalXp = db.totalXp
        self.unlockedNodeIds = Set(db.unlockedNodes)
    }
}

struct UserStreak: Identifiable {
    let id: UUID
    let streakType: StreakType
    let currentCount: Int
    let longestCount: Int
    let lastActivityDate: Date?
    let streakStartDate: Date?
    let shieldsRemaining: Int
    let shieldsUsedThisWeek: Int
    let lastShieldUsedDate: Date?
    let recoveryAvailable: Bool
    let recoveryDeadline: Date?
    let brokenStreakCount: Int?

    var isAtRisk: Bool {
        guard let lastActivity = lastActivityDate else { return false }
        let calendar = Calendar.current
        let daysSinceActivity = calendar.dateComponents([.day], from: lastActivity, to: Date()).day ?? 0
        return daysSinceActivity >= 1
    }

    var freezeUntil: Date? {
        // Streak is "frozen" if there's a recovery deadline and recovery is available
        guard recoveryAvailable, let deadline = recoveryDeadline else { return nil }
        return deadline
    }

    init(from db: DBUserStreak) {
        self.id = db.id
        self.streakType = StreakType(rawValue: db.streakType) ?? .quest
        self.currentCount = db.currentCount
        self.longestCount = db.longestCount
        self.lastActivityDate = db.lastActivityDate.flatMap { parseDate($0) }
        self.streakStartDate = db.streakStartDate.flatMap { parseDate($0) }
        self.shieldsRemaining = db.shieldsAvailable
        self.shieldsUsedThisWeek = db.shieldsUsedThisWeek
        self.lastShieldUsedDate = db.lastShieldUsedDate.flatMap { parseDate($0) }
        self.recoveryAvailable = db.recoveryAvailable
        self.recoveryDeadline = db.recoveryDeadline.flatMap { ISO8601DateFormatter().date(from: $0) }
        self.brokenStreakCount = db.brokenStreakCount
    }
}

struct Season: Identifiable {
    let id: UUID
    let slug: String
    let name: String
    let description: String?
    let theme: String?
    let bannerUrl: String?
    let colorPrimary: String
    let colorSecondary: String?
    let startsAt: Date
    let endsAt: Date
    let isActive: Bool

    init(from db: DBSeason) {
        self.id = db.id
        self.slug = db.slug
        self.name = db.name
        self.description = db.description
        self.theme = db.theme
        self.bannerUrl = db.bannerUrl
        self.colorPrimary = db.colorPrimary ?? "#7C3AED"
        self.colorSecondary = db.colorSecondary
        self.startsAt = ISO8601DateFormatter().date(from: db.startsAt) ?? Date()
        self.endsAt = ISO8601DateFormatter().date(from: db.endsAt) ?? Date()
        self.isActive = db.isActive
    }
}

struct WeeklyChallenge: Identifiable {
    let id: UUID
    let weekStart: Date
    let title: String
    let description: String?
    let challengeType: String
    let targetValue: Int
    let xpReward: Int
    let badgeRewardId: UUID?

    init(from db: DBWeeklyChallenge) {
        self.id = db.id
        self.weekStart = parseDate(db.weekStart) ?? Date()
        self.title = db.title
        self.description = db.description
        self.challengeType = db.challengeType
        self.targetValue = db.targetValue
        self.xpReward = db.xpReward
        self.badgeRewardId = db.badgeRewardId
    }
}

struct UserChallengeProgress: Identifiable {
    let id: UUID
    let challenge: WeeklyChallenge
    let currentProgress: Int
    let completedAt: Date?
    let rewardClaimed: Bool

    var progressPercentage: Double {
        guard challenge.targetValue > 0 else { return 0 }
        return min(1.0, Double(currentProgress) / Double(challenge.targetValue))
    }

    var isCompleted: Bool {
        completedAt != nil || currentProgress >= challenge.targetValue
    }

    init(from db: DBUserChallengeProgress, challenge: WeeklyChallenge) {
        self.id = db.id
        self.challenge = challenge
        self.currentProgress = db.currentProgress
        self.completedAt = db.completedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        self.rewardClaimed = db.rewardClaimed
    }
}

// MARK: - API Response Models

struct AwardXPResponse: Codable {
    let success: Bool
    let totalXp: Int
    let newLevel: Int
    let leveledUp: Bool
    let xpAwarded: Int

    enum CodingKeys: String, CodingKey {
        case success
        case totalXp = "total_xp"
        case newLevel = "new_level"
        case leveledUp = "leveled_up"
        case xpAwarded = "xp_awarded"
    }
}

struct CheckBadgeProgressResponse: Codable {
    let checked: Int
    let newlyEarned: [EarnedBadge]
    let progressUpdated: [String]

    struct EarnedBadge: Codable {
        let id: UUID
        let slug: String
        let name: String
        let xpReward: Int

        enum CodingKeys: String, CodingKey {
            case id, slug, name
            case xpReward = "xp_reward"
        }
    }

    enum CodingKeys: String, CodingKey {
        case checked
        case newlyEarned = "newly_earned"
        case progressUpdated = "progress_updated"
    }
}

// MARK: - Helper Types

// AnyCodable is defined in Models.swift - using that definition to avoid duplication

// MARK: - Date Parsing Helper

private func parseDate(_ string: String) -> Date? {
    // Try ISO8601 first
    if let date = ISO8601DateFormatter().date(from: string) {
        return date
    }

    // Try date-only format (YYYY-MM-DD)
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    dateFormatter.timeZone = TimeZone(identifier: "UTC")
    return dateFormatter.date(from: string)
}
