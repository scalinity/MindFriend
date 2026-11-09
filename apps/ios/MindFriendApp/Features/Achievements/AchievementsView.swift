// MindFriend Achievements View
// Main achievements hub showing XP, badges and skill trees

import SwiftUI

struct AchievementsView: View {
    @EnvironmentObject private var achievementService: AchievementService

    @State private var selectedTab: AchievementTab = .badges

    // Achievements tutorial state
    @AppStorage("achievements_tutorial_completed") private var achievementsTutorialCompleted = false
    @State private var showAchievementsTutorial = false

    enum AchievementTab: String, CaseIterable {
        case badges = "Badges"
        case skills = "Skills"

        var icon: String {
            switch self {
            case .badges: return "star.circle.fill"
            case .skills: return "chart.bar.fill"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                // XP and Level Header
                XPProgressView()

                // Tab Picker
                Picker("Tab", selection: $selectedTab) {
                    ForEach(AchievementTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)

                // Tab Content
                switch selectedTab {
                case .badges:
                    BadgeCollectionView()
                case .skills:
                    SkillTreesListView()
                }
            }
            .padding(.vertical)
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            // Check badge progress first to catch up on any missed badges
            _ = try? await achievementService.checkBadgeProgress()
            await achievementService.loadAllAchievementData()
        }
        .task {
            // Check if data is stale (> 5 minutes old)
            let shouldRefresh =
                achievementService.lastLoadTime == nil
                || Date().timeIntervalSince(achievementService.lastLoadTime!) > 300

            if shouldRefresh {
                // Check badge progress first to catch up on any missed badges
                _ = try? await achievementService.checkBadgeProgress()
                await achievementService.loadAllAchievementData()
            }
        }
        .overlay {
            if achievementService.isLoading && achievementService.badges.isEmpty {
                ProgressView("Loading achievements...")
            }
        }
        .overlay(alignment: .top) {
            if let error = achievementService.error {
                ErrorBanner(
                    message: error.localizedDescription,
                    onRetry: {
                        Task {
                            await achievementService.loadAllAchievementData()
                        }
                    }
                )
                .padding(.top, SupportTheme.Spacing.xs)
                .transition(.opacity)
            }
        }
        // Level-Up Celebration (NEW)
        .fullScreenCover(item: $achievementService.pendingCelebration) { event in
            LevelUpCelebrationView(
                oldLevel: event.oldLevel,
                newLevel: event.newLevel,
                xpEarned: event.xpEarned,
                onDismiss: {
                    achievementService.pendingCelebration = nil
                }
            )
        }
        // Milestone Narrative (NEW)
        .sheet(item: $achievementService.pendingMilestone) { celebration in
            MilestoneNarrativeView(celebration: celebration)
                .onDisappear {
                    Task {
                        try? await achievementService.markMilestoneViewed(celebrationId: celebration.id)
                        achievementService.pendingMilestone = nil
                    }
                }
        }
        .onAppear {
            if !achievementsTutorialCompleted {
                showAchievementsTutorial = true
            }
        }
        .fullScreenCover(isPresented: $showAchievementsTutorial) {
            AchievementsTutorialFlow(onComplete: {
                achievementsTutorialCompleted = true
                showAchievementsTutorial = false
            })
        }
    }
}

// MARK: - XP Progress View

struct XPProgressView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var achievementService: AchievementService

    private var experience: UserExperience? {
        achievementService.userExperience
    }

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            (typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: SupportTheme.Spacing.m))
                : AnyLayout(HStackLayout(spacing: SupportTheme.Spacing.m))) {
                    CelebrationEmblem(
                        .text("\(experience?.currentLevel ?? 1)"), tint: SupportTheme.accent, diameter: 80
                    )
                    .accessibilityLabel("Level \(experience?.currentLevel ?? 1)")

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        // XP Progress
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                                Text("Level \(experience?.currentLevel ?? 1)")
                                    .font(.headline)
                                    .accessibilityAddTraits(.isHeader)
                                Text("\(experience?.totalXp ?? 0) XP")
                                    .font(.headline)
                                    .accessibilityAddTraits(.isHeader)

                                Spacer()

                                Text("\(experience?.xpToNextLevel ?? 100) to next level")
                                    .font(.caption)
                                    .foregroundStyle(SupportTheme.textSecondary)
                            }

                            ProgressView(value: experience?.progressToNextLevel ?? 0)
                                .tint(SupportTheme.accent)
                        }

                        // Daily/Weekly Stats
                        (typeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: SupportTheme.Spacing.s))
                            : AnyLayout(HStackLayout(spacing: SupportTheme.Spacing.m))) {
                                AchievementStatBadge(
                                    label: "Today",
                                    value: "\(experience?.dailyXp ?? 0) XP",
                                    color: SupportTheme.accent
                                )

                                AchievementStatBadge(
                                    label: "This Week",
                                    value: "\(experience?.weeklyXp ?? 0) XP",
                                    color: SupportTheme.accent
                                )

                                if let multiplier = experience?.xpMultiplier, multiplier > 1.0 {
                                    AchievementStatBadge(
                                        label: "Bonus",
                                        value: String(format: "%.1fx", multiplier),
                                        color: SupportTheme.accent
                                    )
                                }
                            }
                    }
                }
        }
        .supportCard()
        .padding(.horizontal)
    }
}

struct AchievementStatBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xxs) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)

            Text(label)
                .font(.caption2)
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }
}

// MARK: - Badge Collection View

struct BadgeCollectionView: View {
    @EnvironmentObject private var achievementService: AchievementService

    @State private var selectedCategory: BadgeCategory? = nil

    // Streak badges stay on the server but are not shown, so chips, grid and counts all use this set.
    private func visible(_ badges: [AchievementBadge]) -> [AchievementBadge] {
        badges.filter { $0.category != .streaks }
    }

    private func visible(_ progress: [UserBadgeProgress]) -> [UserBadgeProgress] {
        progress.filter { $0.badge.category != .streaks }
    }

    private var categories: [BadgeCategory] {
        Array(Set(visible(achievementService.badges).map { $0.category })).sorted { $0.displayName < $1.displayName }
    }

    private var displayedBadges: [AchievementBadge] {
        if let category = selectedCategory {
            return visible(achievementService.badgesInCategory(category))
        }
        return visible(achievementService.badges)
    }

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            // Category Filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SupportTheme.Spacing.xs) {
                    AchievementCategoryChip(
                        title: "All",
                        isSelected: selectedCategory == nil,
                        action: { selectedCategory = nil }
                    )

                    ForEach(categories, id: \.self) { category in
                        AchievementCategoryChip(
                            title: category.displayName,
                            isSelected: selectedCategory == category,
                            action: { selectedCategory = category }
                        )
                    }
                }
                .padding(.horizontal)
            }

            // Stats Summary
            HStack(spacing: SupportTheme.Spacing.l) {
                BadgeStatView(
                    count: visible(achievementService.earnedBadges).count,
                    total: visible(achievementService.badges).count,
                    label: "Earned"
                )

                BadgeStatView(
                    count: visible(achievementService.inProgressBadges).count,
                    label: "In Progress"
                )

                BadgeStatView(
                    count: visible(achievementService.favoriteBadges).count,
                    label: "Favorites"
                )
            }
            .padding(.horizontal)

            // Badge Grid
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 100), spacing: SupportTheme.Spacing.m)
                ], spacing: SupportTheme.Spacing.m
            ) {
                ForEach(displayedBadges) { badge in
                    NavigationLink {
                        BadgeDetailView(badge: badge)
                            .environmentObject(achievementService)
                    } label: {
                        BadgeGridItem(
                            badge: badge,
                            progress: achievementService.progressForBadge(badge.id)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct AchievementCategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, SupportTheme.Spacing.s)
                .padding(.vertical, SupportTheme.Spacing.xs)
                .background(isSelected ? SupportTheme.accent : SupportTheme.surface)
                .foregroundStyle(isSelected ? SupportTheme.onAccent : SupportTheme.textPrimary)
                .clipShape(Capsule())
        }
    }
}

struct BadgeStatView: View {
    let count: Int
    var total: Int? = nil
    let label: String

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xxs) {
            if let total = total {
                Text("\(count)/\(total)")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                    .fontWeight(.bold)
            } else {
                Text("\(count)")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                    .fontWeight(.bold)
            }

            Text(label)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }
}

struct BadgeGridItem: View {
    let badge: AchievementBadge
    let progress: UserBadgeProgress?

    private var isEarned: Bool {
        progress?.isEarned ?? false
    }

    /// Tier color with consistent opacity for earned/unearned state
    private var tierColor: Color {
        guard let tier = badge.tier else { return .clear }
        let baseColor = SupportTheme.accent
        return isEarned ? baseColor : SupportTheme.textSecondary
    }

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            ZStack {
                // Badge Icon (using SF Symbols)
                Image(systemName: badge.sfSymbolName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(
                        isEarned
                            ? (badge.tier != nil ? (SupportTheme.accent) : SupportTheme.Celebration.gold)
                            : SupportTheme.textSecondary
                    )
                    .frame(width: 56, height: 56)
                    .opacity(isEarned ? 1.0 : 0.35)

                // Progress Ring (if not earned)
                if !isEarned, let progress = progress {
                    Circle()
                        .trim(from: 0, to: progress.progressPercentage)
                        .stroke(SupportTheme.accent, lineWidth: 3)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 66, height: 66)
                }

                // New Badge Indicator
                if progress?.isNew == true {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .offset(x: 23, y: -23)
                }
            }
            .frame(height: 70)

            VStack(spacing: SupportTheme.Spacing.xxs) {
                Text(badge.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isEarned ? SupportTheme.textPrimary : SupportTheme.textSecondary)

                Text(badge.tier?.displayName ?? " ")
                    .font(.caption2)
                    .foregroundStyle(tierColor)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .padding(.vertical, SupportTheme.Spacing.xs)
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }
}

// MARK: - Badge Detail View

struct BadgeDetailView: View {
    @EnvironmentObject private var achievementService: AchievementService

    let badge: AchievementBadge

    private var progress: UserBadgeProgress? {
        achievementService.progressForBadge(badge.id)
    }

    private var isEarned: Bool {
        progress?.isEarned ?? false
    }

    /// Tier color based on earned state
    private var tierColor: Color {
        guard let tier = badge.tier else { return SupportTheme.textSecondary }
        return isEarned ? (SupportTheme.accent) : SupportTheme.textSecondary
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                // Badge Icon (using SF Symbols)
                Image(systemName: badge.sfSymbolName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(
                        isEarned
                            ? (badge.tier != nil ? (SupportTheme.accent) : SupportTheme.accent)
                            : SupportTheme.textSecondary
                    )
                    .frame(width: 120, height: 120)
                    .opacity(isEarned ? 1.0 : 0.4)

                // Badge Info
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Text(badge.name)
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)
                        .fontWeight(.bold)

                    if let tier = badge.tier {
                        Text(tier.displayName)
                            .font(.subheadline)
                            .foregroundStyle(tierColor)
                            .padding(.horizontal, SupportTheme.Spacing.s)
                            .padding(.vertical, SupportTheme.Spacing.xxs)
                            .background(tierColor.opacity(0.2))
                            .clipShape(Capsule())
                    }

                    Text(badge.description)
                        .font(.body)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Tier Progression (NEW - for tiered badges)
                if badge.tier != nil {
                    TierProgressView(badge: badge, progress: progress)
                        .padding(.horizontal)
                }

                // How to Progress (NEW - for non-earned badges)
                if !isEarned, let target = progress?.progressTarget {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        Text("How to Progress")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        let remaining = target - (progress?.progressCurrent ?? 0)
                        Text(getProgressTip(badge: badge, remaining: remaining))
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .supportCard()
                    .padding(.horizontal)
                }

                // Progress Section
                if let progress = progress {
                    VStack(spacing: SupportTheme.Spacing.s) {
                        if progress.isEarned {
                            Label("Earned!", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(SupportTheme.accent)

                            if let earnedAt = progress.earnedAt {
                                Text("on \(earnedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(SupportTheme.textSecondary)
                            }
                        } else if let target = progress.progressTarget {
                            VStack(spacing: SupportTheme.Spacing.xs) {
                                Text("Progress: \(progress.progressCurrent)/\(target)")
                                    .font(.subheadline)

                                ProgressView(value: progress.progressPercentage)
                                    .tint(SupportTheme.accent)
                                    .frame(maxWidth: 200)
                            }
                        }
                    }
                    .supportCard()
                    .padding(.horizontal)
                }

                // Stats
                HStack(spacing: 0) {
                    VStack(spacing: SupportTheme.Spacing.xxs) {
                        Text("\(badge.xpReward)")
                            .font(.title3)
                            .accessibilityAddTraits(.isHeader)
                            .fontWeight(.bold)
                            .foregroundStyle(SupportTheme.accent)
                        Text("XP Reward")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: SupportTheme.Spacing.xxs) {
                        Text(badge.rarity.displayName)
                            .font(.title3)
                            .accessibilityAddTraits(.isHeader)
                            .fontWeight(.bold)
                            .fixedSize(horizontal: false, vertical: true)
                            .minimumScaleFactor(0.8)
                        Text("Rarity")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: SupportTheme.Spacing.xxs) {
                        Text("\(badge.earnedByCount)")
                            .font(.title3)
                            .accessibilityAddTraits(.isHeader)
                            .fontWeight(.bold)
                        Text("Earned By")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .supportCard()
                .padding(.horizontal)

                // Favorite Button
                if isEarned {
                    Button {
                        Task {
                            try? await achievementService.toggleBadgeFavorite(
                                badgeId: badge.id,
                                isFavorite: !(progress?.isFavorite ?? false)
                            )
                        }
                    } label: {
                        Label(
                            progress?.isFavorite == true ? "Remove from Favorites" : "Add to Favorites",
                            systemImage: progress?.isFavorite == true ? "heart.fill" : "heart"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.supportPrimary)
                    .tint(progress?.isFavorite == true ? .red : SupportTheme.accent)
                    .padding(.horizontal)
                }
            }
            .padding()
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle(badge.category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if progress?.isNew == true {
                try? await achievementService.markBadgeAsSeen(badgeId: badge.id)
            }
        }
    }

    private func getProgressTip(badge: AchievementBadge, remaining: Int) -> String {
        switch badge.requirementType {
        case "quest_count":
            return "Complete \(remaining) more daily quests to unlock this badge."
        case "streak_days":
            return "Explore another activity whenever you feel ready."
        case "exercise_count":
            return "Practice \(remaining) more exercises to earn this badge."
        case "meditation_minutes":
            return "Meditate for \(remaining) more minutes to unlock."
        case "mood_entries":
            return "Log \(remaining) more mood entries to progress."
        default:
            return "Keep completing activities to unlock this badge!"
        }
    }
}

// MARK: - Skill Trees List View

struct SkillTreesListView: View {
    @EnvironmentObject private var achievementService: AchievementService

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            ForEach(achievementService.skillTrees) { tree in
                NavigationLink {
                    SkillTreeDetailView(tree: tree)
                        .environmentObject(achievementService)
                } label: {
                    SkillTreeCard(tree: tree)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
}

struct SkillTreeCard: View {
    @EnvironmentObject private var achievementService: AchievementService

    let tree: SkillTree

    private var progress: UserSkillProgress? {
        achievementService.userSkillProgress.first { $0.tree.id == tree.id }
    }

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.m) {
            // Tree Icon (using SF Symbols)
            Image(systemName: "chart.bar.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(SupportTheme.accent)
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(tree.name)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Text(tree.description)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .lineLimit(2)

                if let progress = progress {
                    HStack {
                        Text("Level \(progress.currentLevel)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(SupportTheme.accent)

                        ProgressView(value: progress.progressToNextLevel)
                            .tint(SupportTheme.accent)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .supportCard()
    }
}

struct SkillTreeDetailView: View {
    @EnvironmentObject private var achievementService: AchievementService

    let tree: SkillTree

    private var progress: UserSkillProgress? {
        achievementService.userSkillProgress.first { $0.tree.id == tree.id }
    }

    /// Check if user meets requirements for a node based on overall level and XP
    private func isNodeUnlocked(_ node: SkillTreeNode) -> Bool {
        // If explicitly unlocked in progress, it's unlocked
        if progress?.unlockedNodeIds.contains(node.id) == true {
            return true
        }
        // Otherwise check if user meets the level/XP requirements
        guard let userExp = achievementService.userExperience else { return false }
        let userLevel = userExp.currentLevel
        let userXp = userExp.totalXp
        return userLevel >= node.levelRequired && userXp >= node.xpRequired
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                // Header
                VStack(spacing: SupportTheme.Spacing.s) {
                    // Tree Icon (using SF Symbols)
                    Image(systemName: "chart.bar.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(SupportTheme.accent)
                        .frame(width: 80, height: 80)

                    Text(tree.name)
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)
                        .fontWeight(.bold)

                    Text(tree.description)
                        .font(.body)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    if let progress = progress {
                        VStack(spacing: SupportTheme.Spacing.xs) {
                            Text("Level \(progress.currentLevel) / \(tree.maxLevel)")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                                .foregroundStyle(SupportTheme.accent)

                            ProgressView(value: progress.progressToNextLevel)
                                .tint(SupportTheme.accent)
                                .frame(maxWidth: 200)

                            Text("\(progress.currentXp) XP")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                    }
                }
                .padding()

                // Nodes
                VStack(spacing: SupportTheme.Spacing.m) {
                    ForEach(tree.nodes) { node in
                        SkillNodeRow(
                            node: node,
                            isUnlocked: isNodeUnlocked(node),
                            treeColor: tree.color
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle(tree.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SkillNodeRow: View {
    let node: SkillTreeNode
    let isUnlocked: Bool
    let treeColor: String

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.m) {
            // Node Icon
            ZStack {
                Circle()
                    .fill(isUnlocked ? (SupportTheme.accent) : SupportTheme.textSecondary.opacity(0.3))
                    .frame(width: 44, height: 44)

                if isUnlocked {
                    Image(systemName: "checkmark")
                        .foregroundStyle(SupportTheme.textPrimary)
                        .fontWeight(.bold)
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(node.name)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .opacity(isUnlocked ? 1.0 : 0.6)

                Text(node.description)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .lineLimit(2)

                if !isUnlocked {
                    Text("Requires Level \(node.levelRequired) • \(node.xpRequired) XP")
                        .font(.caption2)
                        .foregroundStyle(SupportTheme.accent)
                }
            }

            Spacer()
        }
        .supportCard()
        .opacity(isUnlocked ? 1.0 : 0.7)
    }
}

// MARK: - Inline load error

struct ErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SupportTheme.accent)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text("Error Loading Data")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Button("Retry") {
                onRetry()
            }
            .buttonStyle(.supportSecondary)
            .controlSize(.small)
        }
        .supportCard()
        .shadow(color: SupportTheme.canvas.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    AchievementsView()
        .environmentObject(
            AchievementService(
                supabase: DependencyContainer.shared.supabaseClient,
                authService: DependencyContainer.shared.supabaseAuthService))
}
