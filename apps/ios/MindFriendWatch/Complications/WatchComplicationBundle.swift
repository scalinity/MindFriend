import WidgetKit
import SwiftUI

#if os(watchOS)
/// Widget bundle for all MindFriend watch complications
@main
struct MindFriendWatchComplicationsBundle: WidgetBundle {
    var body: some Widget {
        StreakComplication()
        MoodComplication()
        BreathingComplication()
    }
}
#endif
