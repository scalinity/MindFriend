import WidgetKit
import SwiftUI

/// Widget bundle for all MindFriend watch complications
@main
struct MindFriendWatchComplicationsBundle: WidgetBundle {
    var body: some Widget {
        StreakComplication()
        MoodComplication()
        BreathingComplication()
    }
}
