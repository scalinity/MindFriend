import SwiftUI

/// Current account progress, using the same quiet card as the Today summary.
struct LevelProgressView: View {
    let userLevel: UserLevel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: SupportTheme.Spacing.s))
                : AnyLayout(HStackLayout(alignment: .top, spacing: SupportTheme.Spacing.m))
            layout {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text("Level \(userLevel.level)").font(.headline)
                    Text(userLevel.title).font(.subheadline).foregroundStyle(SupportTheme.textSecondary)
                }
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text("\(userLevel.currentXP) XP").font(.headline).foregroundStyle(SupportTheme.accent)
                    Text("\(userLevel.xpThisWeek) XP this week").font(.caption).foregroundStyle(SupportTheme.textSecondary)
                }
            }
            ProgressView(value: min(1, max(0, userLevel.progress)))
                .tint(SupportTheme.accent).accessibilityLabel("Progress to next level")
            Text(userLevel.level < 50 ? "\(userLevel.xpToNextLevel) XP to next level" : "Highest level reached")
                .font(.caption).foregroundStyle(SupportTheme.textSecondary)
        }
        .foregroundStyle(SupportTheme.textPrimary)
        .supportCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Level \(userLevel.level), \(userLevel.title). \(userLevel.currentXP) XP total. \(userLevel.xpToNextLevel) XP to next level.")
    }
}

struct LevelBadgeView: View {
    let level: Int
    let title: String

    var body: some View {
        Label("Level \(level) · \(title)", systemImage: "sparkles")
            .font(.caption).foregroundStyle(SupportTheme.accent)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    VStack(spacing: SupportTheme.Spacing.m) {
        LevelProgressView(userLevel: UserLevel(
            level: 12,
            title: "Explorer",
            currentXP: 3850,
            nextLevelXP: 4500,
            xpThisWeek: 180
        ))

        LevelProgressView(userLevel: UserLevel(
            level: 50,
            title: "Transcendent",
            currentXP: 65000,
            nextLevelXP: 63700,
            xpThisWeek: 450
        ))

        LevelBadgeView(level: 12, title: "Explorer")
    }
    .padding(SupportTheme.Spacing.m)
}
