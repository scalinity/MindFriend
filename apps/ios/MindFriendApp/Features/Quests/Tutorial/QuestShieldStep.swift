import SwiftUI

/// The final step leaves room for pauses without presenting streak mechanics.
struct QuestShieldStep: View {
    let onComplete: () -> Void

    var body: some View {
        TutorialStepView(
            icon: "heart",
            iconColor: SupportTheme.accent,
            headline: "Room for a pause",
            subheadline: "A busy day does not erase the work you've done. Your progress is here when you return.",
            primaryLabel: "Start Your Journey",
            primaryAction: onComplete
        ) {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                SupportRowLabel(title: "Choose what fits", subtitle: "A shorter quest is an option on a full day", icon: "clock")
                SupportRowLabel(title: "Keep what you've learned", subtitle: "Completed quests and earned XP remain part of your journey", icon: "checkmark.circle")
            }
            .supportCard()
            .padding(.horizontal, SupportTheme.Spacing.m)
            .celebrationReveal()
        }
    }
}
