import SwiftUI

/// Displays earned badges and achievements
struct BadgesView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var earnedBadges: [UserBadgeProgress] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
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
        .navigationTitle("Badges")
        .background(Color(.systemGroupedBackground))
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
            earnedBadges = container.achievementService.earnedBadges
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
            VStack(alignment: .leading, spacing: 4) {
                Text("\(badgeCount)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.yellow)

                Text(badgeCount == 1 ? "Badge Earned" : "Badges Earned")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "medal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

// MARK: - Badges Grid

struct BadgesGrid: View {
    let badges: [UserBadgeProgress]

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Collection")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 16) {
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
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.2))
                    .frame(width: 60, height: 60)

                // Use SF Symbol based on badge category
                Image(systemName: iconForBadge(badgeProgress.badge))
                    .font(.system(size: 26))
                    .foregroundStyle(.yellow)
            }

            Text(badgeProgress.badge.name)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if let earnedAt = badgeProgress.earnedAt {
                Text(earnedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func iconForBadge(_ badge: AchievementBadge) -> String {
        switch badge.category {
        case .gettingStarted: return "star.fill"
        case .streaks: return "flame.fill"
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
        VStack(spacing: 16) {
            Image(systemName: "medal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Badges Yet")
                .font(.headline)

            Text("Complete quests, maintain streaks, and explore exercises to earn badges.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
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
