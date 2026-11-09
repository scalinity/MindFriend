import SwiftUI

/// Displays earned badges and achievements
struct BadgesView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var earnedBadges: [UserBadgeProgress] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if earnedBadges.isEmpty {
                    EmptyBadgesCard()
                } else {
                    // Stats summary
                    BadgeStatsCard(badgeCount: earnedBadges.count)

                    // Earned badges grid
                    BadgesGrid(badges: earnedBadges)
                }
            }
            .padding()
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("Badges")
        .background(SupportTheme.canvas)
        .task {
            await loadBadges()
        }
    }

    private func loadBadges() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await container.achievementService.loadBadges()
            try await container.achievementService.loadUserBadgeProgress()
            earnedBadges = container.achievementService.earnedBadges.filter { $0.badge.category != .streaks }
        } catch {
            // Silently fail - show empty state
        }
    }
}

// MARK: - Badge Stats Card

struct BadgeStatsCard: View {
    let badgeCount: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text("\(badgeCount)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(SupportTheme.Celebration.gold)

                Text(badgeCount == 1 ? "Badge Earned" : "Badges Earned")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            Spacer()

            Image(systemName: "medal.fill")
                .font(.system(size: 48))
                .foregroundStyle(SupportTheme.Celebration.gold)
        }
        .supportCard()
    }
}

// MARK: - Badges Grid

struct BadgesGrid: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let badges: [UserBadgeProgress]

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Your Collection")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: columns, spacing: SupportTheme.Spacing.m) {
                ForEach(badges) { badgeProgress in
                    BadgeCard(badgeProgress: badgeProgress)
                }
            }
        }
    }
}

// MARK: - Badge Card

struct BadgeCard: View {
    let badgeProgress: UserBadgeProgress

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            ZStack {
                Circle()
                    .fill(SupportTheme.Celebration.gold.opacity(0.2))
                    .frame(width: 60, height: 60)

                // Use SF Symbol based on badge category
                Image(systemName: iconForBadge(badgeProgress.badge))
                    .font(.system(size: 26))
                    .foregroundStyle(SupportTheme.Celebration.gold)
            }

            Text(badgeProgress.badge.name)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let earnedAt = badgeProgress.earnedAt {
                Text(earnedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SupportTheme.Spacing.xs)
    }

    private func iconForBadge(_ badge: AchievementBadge) -> String {
        switch badge.category {
        case .gettingStarted: return "star.fill"
        case .streaks: return "leaf.fill"
        case .quests: return "checkmark.seal.fill"
        case .exercises: return "figure.mind.and.body"
        case .meditation: return "brain.head.profile"
        case .mood: return "heart.fill"
        case .circles: return "person.2.fill"
        case .sensory: return "hand.tap.fill"
        case .seasonal: return "leaf.fill"
        case .special: return "medal.fill"
        }
    }
}

// MARK: - Empty State

struct EmptyBadgesCard: View {
    var body: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "medal")
                .font(.system(size: 48))
                .foregroundStyle(SupportTheme.textSecondary)

            Text("No Badges Yet")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text("Complete quests and explore exercises to earn badges.")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(SupportTheme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BadgesView()
            .environmentObject(AppState())
            .environmentObject(DependencyContainer())
    }
}
