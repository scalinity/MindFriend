import WidgetKit
import SwiftUI

/// Widget bundle entry point for all MindFriend widgets
@main
struct MindFriendWidgets: WidgetBundle {
    var body: some Widget {
        StreakWidget()
        MoodWidget()
        ProgressWidget()
        QuickActionsWidget()
        QuestWidget()
        QuoteWidget()
        // Ambient Wellness Presence widgets
        QuickBreathWidget()
        AffirmationWidget()
        WellnessScoreWidget()
    }
}
