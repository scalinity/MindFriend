// MindFriend XP Compact Widget
// Compact XP progress bar for HomeView

import SwiftUI

struct XPCompactWidget: View {
    @EnvironmentObject private var achievementService: AchievementService
    @Binding var selectedTab: MainTab // To navigate to achievements

    // Optional external level data (e.g., from HomeView's loaded state)
    var userLevel: UserLevel?

    private var experience: UserExperience? {
        // Prefer external userLevel if provided (already loaded from profile)
        if let level = userLevel {
            return UserExperience(
                totalXp: level.currentXP,
                currentLevel: level.level,
                xpToNextLevel: level.nextLevelXP,
                dailyXp: 0,
                weeklyXp: level.xpThisWeek,
                prestigeLevel: 0,
                xpMultiplier: 1.0,
                multiplierExpiresAt: nil
            )
        }
        // Fallback to achievementService
        return achievementService.userExperience
    }

    var body: some View {
        Button { selectedTab = .outcomes } label: {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                SupportRowLabel(title: "Level \(experience?.currentLevel ?? 1)",
                    subtitle: "\(experience?.xpToNextLevel ?? 100) XP to next", icon: "sparkles")
                ProgressView(value: min(1, max(0, experience?.progressToNextLevel ?? 0)))
                    .tint(SupportTheme.accent)
                    .accessibilityLabel("Progress to next level")
            }
            .supportCard()
        }
        .buttonStyle(.plain)
    }
}
