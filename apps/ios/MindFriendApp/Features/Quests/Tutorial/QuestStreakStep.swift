import SwiftUI

/// The third tutorial step explains progress without a consecutive-day target.
struct QuestStreakStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    var body: some View {
        TutorialStepView(
            icon: "leaf",
            iconColor: SupportTheme.accent,
            headline: "Small steps add up",
            subheadline: "Every completed quest contributes to your progress. Come back when it works for you.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                SupportRowLabel(title: "Earn XP", subtitle: "Completed quests count toward your next level", icon: "sparkles")
                SupportRowLabel(title: "Explore what helps", subtitle: "Try different practices at your own pace", icon: "leaf")
                SupportRowLabel(title: "Notice your progress", subtitle: "Find your completed quests and badges in You", icon: "trophy")
            }
            .supportCard()
            .padding(.horizontal, SupportTheme.Spacing.m)
            .celebrationReveal()
        }
    }
}
