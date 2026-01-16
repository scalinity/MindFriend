// MindFriend Achievements View
// Main achievements hub showing XP, badges, skill trees, and streaks

import SwiftUI

struct AchievementsView: View {
    @EnvironmentObject private var achievementService: AchievementService

    @State private var selectedTab: AchievementTab = .badges

    enum AchievementTab: String, CaseIterable {
        case badges = "Badges"
        case skills = "Skills"
        case streaks = "Streaks"

        var icon: String {
            switch self {
            case .badges: return "star.circle.fill"
            case .skills: return "chart.bar.fill"
            case .streaks: return "flame.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // XP and Level Header
                    XPProgressView()

                    // Tab Picker
                    Picker("Tab", selection: $selectedTab) {
                        ForEach(AchievementTab.allCases, id: \.self) { tab in
                            Label(tab.rawValue, systemImage: tab.icon)
                                .tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Tab Content
                    switch selectedTab {
                    case .badges:
                        BadgeCollectionView()
                    case .skills:
                        SkillTreesListView()
                    case .streaks:
                        StreaksListView()
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await achievementService.loadAllAchievementData()
            }
            .task {
                if achievementService.badges.isEmpty {
                    await achievementService.loadAllAchievementData()
                }
            }
            .overlay {
                if achievementService.isLoading && achievementService.badges.isEmpty {
                    ProgressView("Loading achievements...")
                }
            }
        }
    }
}

// MARK: - XP Progress View

struct XPProgressView: View {
    @EnvironmentObject private var achievementService: AchievementService

    private var experience: UserExperience? {
        achievementService.userExperience
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                // Level Badge
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 80, height: 80)

                    VStack(spacing: 2) {
                        Text("LVL")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white.opacity(0.8))

                        Text("\(experience?.currentLevel ?? 1)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    // XP Progress
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(experience?.totalXp ?? 0) XP")
                                .font(.headline)

                            Spacer()

                            Text("\(experience?.xpToNextLevel ?? 100) to next level")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ProgressView(value: experience?.progressToNextLevel ?? 0)
                            .tint(.purple)
                    }

                    // Daily/Weekly Stats
                    HStack(spacing: 16) {
                        StatBadge(
                            label: "Today",
                            value: "\(experience?.dailyXp ?? 0) XP",
                            color: .green
                        )

                        StatBadge(
                            label: "This Week",
                            value: "\(experience?.weeklyXp ?? 0) XP",
                            color: .blue
                        )

                        if let multiplier = experience?.xpMultiplier, multiplier > 1.0 {
                            StatBadge(
                                label: "Bonus",
                                value: String(format: "%.1fx", multiplier),
                                color: .orange
                            )
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

struct StatBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Badge Collection View

struct BadgeCollectionView: View {
    @EnvironmentObject private var achievementService: AchievementService

    @State private var selectedCategory: BadgeCategory? = nil

    private var categories: [BadgeCategory] {
        Array(Set(achievementService.badges.map { $0.category })).sorted { $0.displayName < $1.displayName }
    }

    private var displayedBadges: [Badge] {
        if let category = selectedCategory {
            return achievementService.badgesInCategory(category)
        }
        return achievementService.badges
    }

    var body: some View {
        VStack(spacing: 16) {
            // Category Filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryChip(
                        title: "All",
                        isSelected: selectedCategory == nil,
                        action: { selectedCategory = nil }
                    )

                    ForEach(categories, id: \.self) { category in
                        CategoryChip(
                            title: category.displayName,
                            isSelected: selectedCategory == category,
                            action: { selectedCategory = category }
                        )
                    }
                }
                .padding(.horizontal)
            }

            // Stats Summary
            HStack(spacing: 24) {
                BadgeStatView(
                    count: achievementService.earnedBadges.count,
                    total: achievementService.badges.count,
                    label: "Earned"
                )

                BadgeStatView(
                    count: achievementService.inProgressBadges.count,
                    label: "In Progress"
                )

                BadgeStatView(
                    count: achievementService.favoriteBadges.count,
                    label: "Favorites"
                )
            }
            .padding(.horizontal)

            // Badge Grid
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 100), spacing: 16)
            ], spacing: 16) {
                ForEach(displayedBadges) { badge in
                    NavigationLink(value: badge) {
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
        .navigationDestination(for: Badge.self) { badge in
            BadgeDetailView(badge: badge)
        }
    }
}

struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.tertiarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

struct BadgeStatView: View {
    let count: Int
    var total: Int? = nil
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            if let total = total {
                Text("\(count)/\(total)")
                    .font(.title2)
                    .fontWeight(.bold)
            } else {
                Text("\(count)")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct BadgeGridItem: View {
    let badge: Badge
    let progress: UserBadgeProgress?

    private var isEarned: Bool {
        progress?.isEarned ?? false
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Badge Icon
                AsyncImage(url: URL(string: badge.iconUrl)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: "star.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.gray)
                }
                .frame(width: 60, height: 60)
                .opacity(isEarned ? 1.0 : 0.4)
                .grayscale(isEarned ? 0 : 1)

                // Progress Ring (if not earned)
                if !isEarned, let progress = progress {
                    Circle()
                        .trim(from: 0, to: progress.progressPercentage)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 70, height: 70)
                }

                // New Badge Indicator
                if progress?.isNew == true {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .offset(x: 25, y: -25)
                }
            }

            Text(badge.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let tier = badge.tier {
                Text(tier.displayName)
                    .font(.caption2)
                    .foregroundStyle(Color(hex: tier.color) ?? .gray)
            }
        }
        .frame(width: 100)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Badge Detail View

struct BadgeDetailView: View {
    @EnvironmentObject private var achievementService: AchievementService

    let badge: Badge

    private var progress: UserBadgeProgress? {
        achievementService.progressForBadge(badge.id)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Badge Icon
                AsyncImage(url: URL(string: badge.iconUrl)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: "star.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.gray)
                }
                .frame(width: 120, height: 120)
                .opacity(progress?.isEarned == true ? 1.0 : 0.5)
                .grayscale(progress?.isEarned == true ? 0 : 1)

                // Badge Info
                VStack(spacing: 8) {
                    Text(badge.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    if let tier = badge.tier {
                        Text(tier.displayName)
                            .font(.subheadline)
                            .foregroundStyle(Color(hex: tier.color) ?? .gray)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color(hex: tier.color)?.opacity(0.2) ?? .gray.opacity(0.2))
                            .clipShape(Capsule())
                    }

                    Text(badge.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Progress Section
                if let progress = progress {
                    VStack(spacing: 12) {
                        if progress.isEarned {
                            Label("Earned!", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.green)

                            if let earnedAt = progress.earnedAt {
                                Text("on \(earnedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if let target = progress.progressTarget {
                            VStack(spacing: 8) {
                                Text("Progress: \(progress.progressCurrent)/\(target)")
                                    .font(.subheadline)

                                ProgressView(value: progress.progressPercentage)
                                    .tint(.accentColor)
                                    .frame(maxWidth: 200)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Stats
                HStack(spacing: 24) {
                    VStack(spacing: 4) {
                        Text("\(badge.xpReward)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.purple)
                        Text("XP Reward")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 4) {
                        Text(badge.rarity.displayName)
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("Rarity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 4) {
                        Text("\(badge.earnedByCount)")
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("Earned By")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Favorite Button
                if progress?.isEarned == true {
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
                    .buttonStyle(.borderedProminent)
                    .tint(progress?.isFavorite == true ? .red : .accentColor)
                }
            }
            .padding()
        }
        .navigationTitle(badge.category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if progress?.isNew == true {
                try? await achievementService.markBadgeAsSeen(badgeId: badge.id)
            }
        }
    }
}

// MARK: - Skill Trees List View

struct SkillTreesListView: View {
    @EnvironmentObject private var achievementService: AchievementService

    var body: some View {
        VStack(spacing: 16) {
            ForEach(achievementService.skillTrees) { tree in
                NavigationLink(value: tree) {
                    SkillTreeCard(tree: tree)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .navigationDestination(for: SkillTree.self) { tree in
            SkillTreeDetailView(tree: tree)
        }
    }
}

struct SkillTreeCard: View {
    @EnvironmentObject private var achievementService: AchievementService

    let tree: SkillTree

    private var progress: UserSkillProgress? {
        achievementService.userSkillProgress.first { $0.tree.id == tree.id }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Tree Icon
            AsyncImage(url: URL(string: tree.iconUrl)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                Image(systemName: "chart.bar.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Color(hex: tree.color) ?? .blue)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(tree.name)
                    .font(.headline)

                Text(tree.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let progress = progress {
                    HStack {
                        Text("Level \(progress.currentLevel)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color(hex: tree.color) ?? .blue)

                        ProgressView(value: progress.progressToNextLevel)
                            .tint(Color(hex: tree.color))
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SkillTreeDetailView: View {
    @EnvironmentObject private var achievementService: AchievementService

    let tree: SkillTree

    private var progress: UserSkillProgress? {
        achievementService.userSkillProgress.first { $0.tree.id == tree.id }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    AsyncImage(url: URL(string: tree.iconUrl)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Image(systemName: "chart.bar.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(Color(hex: tree.color) ?? .blue)
                    }
                    .frame(width: 80, height: 80)

                    Text(tree.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(tree.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let progress = progress {
                        VStack(spacing: 8) {
                            Text("Level \(progress.currentLevel) / \(tree.maxLevel)")
                                .font(.headline)
                                .foregroundStyle(Color(hex: tree.color) ?? .blue)

                            ProgressView(value: progress.progressToNextLevel)
                                .tint(Color(hex: tree.color))
                                .frame(maxWidth: 200)

                            Text("\(progress.currentXp) XP")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()

                // Nodes
                VStack(spacing: 16) {
                    ForEach(tree.nodes) { node in
                        SkillNodeRow(
                            node: node,
                            isUnlocked: progress?.unlockedNodeIds.contains(node.id) ?? false,
                            treeColor: tree.color
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle(tree.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SkillNodeRow: View {
    let node: SkillTreeNode
    let isUnlocked: Bool
    let treeColor: String

    var body: some View {
        HStack(spacing: 16) {
            // Node Icon
            ZStack {
                Circle()
                    .fill(isUnlocked ? (Color(hex: treeColor) ?? .blue) : Color.gray.opacity(0.3))
                    .frame(width: 44, height: 44)

                if isUnlocked {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.white)
                        .fontWeight(.bold)
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.gray)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(node.name)
                    .font(.headline)
                    .opacity(isUnlocked ? 1.0 : 0.6)

                Text(node.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if !isUnlocked {
                    Text("Requires Level \(node.levelRequired) • \(node.xpRequired) XP")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isUnlocked ? 1.0 : 0.7)
    }
}

// MARK: - Streaks List View

struct StreaksListView: View {
    @EnvironmentObject private var achievementService: AchievementService

    var body: some View {
        VStack(spacing: 16) {
            ForEach(achievementService.streaks) { streak in
                StreakCard(streak: streak)
            }

            if achievementService.streaks.isEmpty {
                ContentUnavailableView(
                    "No Streaks Yet",
                    systemImage: "flame",
                    description: Text("Complete activities to start building streaks!")
                )
            }
        }
        .padding(.horizontal)
    }
}

struct StreakCard: View {
    @EnvironmentObject private var achievementService: AchievementService

    let streak: UserStreak

    @State private var showingShieldAlert = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                // Streak Icon
                ZStack {
                    Circle()
                        .fill(streak.isAtRisk ? Color.orange : Color.red)
                        .frame(width: 50, height: 50)

                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(streak.streakType.displayName)
                        .font(.headline)

                    HStack(spacing: 4) {
                        Text("\(streak.currentCount)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(streak.isAtRisk ? .orange : .primary)

                        Text("day streak")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Best: \(streak.longestCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if streak.shieldsRemaining > 0 {
                        Label("\(streak.shieldsRemaining)", systemImage: "shield.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }

            if streak.isAtRisk {
                HStack {
                    Label("At risk! Complete today's activity", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Spacer()

                    if streak.shieldsRemaining > 0 {
                        Button("Use Shield") {
                            showingShieldAlert = true
                        }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                    }
                }
            }

            if let freezeUntil = streak.freezeUntil, freezeUntil > Date() {
                Label("Protected until \(freezeUntil.formatted(date: .abbreviated, time: .omitted))", systemImage: "shield.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .alert("Use Streak Shield?", isPresented: $showingShieldAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Use Shield") {
                Task {
                    try? await achievementService.useStreakShield(streakType: streak.streakType)
                }
            }
        } message: {
            Text("This will protect your streak for 24 hours. You have \(streak.shieldsRemaining) shield\(streak.shieldsRemaining == 1 ? "" : "s") remaining.")
        }
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
        .environmentObject(AchievementService(supabase: DependencyContainer.shared.supabase))
}
