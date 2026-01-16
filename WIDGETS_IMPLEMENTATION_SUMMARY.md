# Widgets & Ambient Feature Implementation Summary

**Spec:** `docs/specs/12-widgets-ambient.md`
**Implementation Date:** 2026-01-16
**Status:** Phase 5 Complete (Build verification pending)

---

## What Has Been Implemented

### ✅ Phase 1: Database Layer

- **Status:** Complete (No migrations needed)
- **Reason:** Widgets use App Group UserDefaults for data synchronization
- **Files:** None (data persisted in shared container)

### ✅ Phase 2: Shared Data & App Groups

#### SharedDataStore.swift (`apps/ios/MindFriendWidgets/SharedDataStore.swift`)

- Singleton managing App Group (`group.com.mindfriend.app`) data
- **Read Methods:**
  - `currentStreak: Int` - Current wellness streak
  - `todayMood: String?` - Today's mood emoji/label
  - `todayMoodScore: Int?` - Mood numeric score (1-5)
  - `todayCompletedActivities: Int` - Completed activities
  - `todayGoalActivities: Int` - Daily goal (default: 3)
  - `weekMoods: [WidgetDailyMood]` - 7-day mood history
  - `dailyQuote: WidgetDailyQuote?` - Daily inspirational quote
  - `quickActions: [WidgetQuickAction]` - Quick action buttons
  - `lastUpdated: Date?` - Last widget data sync timestamp

- **Write Methods (called from main app):**
  - `updateStreak(_ streak: Int)` - Update streak on quest completion
  - `updateTodayMood(_ mood: String?, score: Int?)` - Log mood
  - `updateTodayProgress(completed: Int, goal: Int)` - Update progress
  - `updateWeekMoods(_ moods: [WidgetDailyMood])` - Update mood history
  - `updateDailyQuote(_ quote: WidgetDailyQuote)` - Update daily quote
  - `updateQuickActions(_ actions: [WidgetQuickAction])` - Update quick actions

#### WidgetModels.swift (`apps/ios/MindFriendWidgets/WidgetModels.swift`)

Shared data models:

- `WidgetDailyMood` - Daily mood entry with date, mood, score
- `WidgetDailyQuote` - Quote with text, author, date
- `WidgetQuickAction` - Quick action definition with icon, title, deep link
- `WidgetMoodHelper` - Enum with helper functions:
  - `emoji(for mood: String) -> String` - Mood to emoji mapping
  - `score(for mood: String) -> Int` - Mood to numeric score
  - `mood(for score: Int) -> String` - Score to mood label
- `WidgetDeepLink` - URL scheme constants for widget deep links

### ✅ Phase 3: Widget Extension

#### 1. StreakWidget.swift

**Families:** `.systemSmall`, `.accessoryCircular`, `.accessoryInline`

- Small (2x2): Large flame icon + streak number + "days"
- Circular Lock Screen (50x50pt): Flame icon + streak number
- Inline Lock Screen: "🔥 14 day streak"
- Features:
  - Dynamic streak color (gray → yellow → orange → red)
  - Refresh every hour or at midnight (whichever comes first)
  - Deep link to streak detail screen

#### 2. MoodWidget.swift

**Families:** `.systemSmall`, `.systemMedium`, `.accessoryRectangular`

- Small (2x2): Current mood emoji OR interactive mood buttons (iOS 17+)
- Medium (4x2): Current mood + 7-day mood mini heatmap
- Rectangular Lock Screen (160x50pt): "Mood: [emoji name]" + quick mood buttons
- Features:
  - Interactive buttons with `LogMoodIntent` for direct mood logging
  - 7-day mood visualization with color-coded squares
  - Deep link to mood detail screen

#### 3. ProgressWidget.swift

**Families:** `.systemMedium`, `.systemLarge`

- Medium (4x2): 3-column layout - Streak circle + Progress circle + Mood emoji
- Large (4x4): Full dashboard with header, progress circle, week mood heatmap
- Features:
  - Real-time progress rings (circular progress)
  - 7-day mood heatmap with emoji overlay
  - Color-coded moods (green → gray → yellow → orange → red)
  - Refresh every 30 minutes

#### 4. QuickActionsWidget.swift

**Families:** `.systemMedium`

- 3 quick action buttons in a row
- Default actions: Breathe, Log Mood, Meditate
- Customizable via `SharedDataStore.updateQuickActions()`
- Features:
  - Dynamic deep links to app features
  - Icon + label layout
  - Tappable buttons for direct navigation

#### 5. MindFriendWidgets.swift (Bundle Entry)

```swift
@main
struct MindFriendWidgets: WidgetBundle {
    var body: some Widget {
        StreakWidget()
        MoodWidget()
        ProgressWidget()
        QuickActionsWidget()
    }
}
```

### ✅ Phase 4: Live Activities

#### MeditationLiveActivity.swift (`apps/ios/MindFriendWidgets/LiveActivities/MeditationLiveActivity.swift`)

**Attributes:**

- `MeditationActivityAttributes` - Activity metadata
  - `sessionTitle: String` - "10-min Meditation", "5-min Breathing", etc.
  - `sessionType: String` - "meditation", "breathing", "focus"
  - `ContentState` - Dynamic session state
    - `elapsedSeconds` - Time elapsed
    - `totalSeconds` - Total session duration
    - `isPaused` - Pause state
    - `currentPhase` - "Starting" → "Settling in" → "Deepening" → "Present" → "Emerging" → "Complete"

**Displays:**

1. **Lock Screen View**
   - Progress ring (50x50pt)
   - Session title + time remaining
   - Pause/Resume and Stop buttons

2. **Dynamic Island - Expanded**
   - Leading: Icon + Session title
   - Trailing: Time remaining
   - Center: Progress bar
   - Bottom: Pause/Resume and Stop buttons

3. **Dynamic Island - Compact**
   - Leading: Session icon
   - Trailing: Time remaining

4. **Dynamic Island - Minimal**
   - Breathing animation circle (scales based on pause state)

**Controls (AppIntents):**

- `PauseMeditationIntent()` - Toggle pause/resume
- `StopMeditationIntent()` - End activity

**Manager (`MeditationActivityManager`):**

- `startActivity(title:type:durationSeconds:)` - Begin live activity
- `togglePause()` - Pause/resume session
- `stopActivity()` - End activity
- Auto-updates every second with countdown and phase transitions

### ✅ Phase 5: Apple Watch App

#### MindFriendWatchApp.swift (`apps/ios/MindFriendWatch/MindFriendWatchApp.swift`)

**Navigation Structure:**

- Tab-based navigation with 3 views: Home, Mood, Stats

**1. WatchHomeView**

- Streak badge with flame icon
- Quick action buttons (Breathe, Focus)
- Today's progress ring
- Model: `WatchHomeViewModel`
  - `streak: Int` - Current streak
  - `completedToday: Int` - Completed activities
  - `dailyGoal: Int` - Daily goal
  - Loads from UserDefaults

**2. WatchBreathingView**

- Large animated circle for breathing guidance
- "Breathe In" / "Breathe Out" instructions
- Countdown timer (4 seconds per phase)
- Configurable cycles (default: 5 inhale/exhale pairs)
- Model: `WatchBreathingViewModel`
  - 4-second breathing pattern
  - Auto-completes after 5 cycles
  - Smooth circle scaling animation

**3. WatchMoodView**

- 5 mood options with emojis
- Tappable mood buttons
- Current selection highlight with checkmark
- Saves to UserDefaults with timestamp
- Syncs with phone via WatchConnectivity

**4. WatchStatsView**

- 7-day mood history with emoji display
- Summary stats: Exercises done, Moods logged
- Day labels (M, T, W, etc.)
- Read-only display

**5. WatchFocusView**

- Placeholder for future focus timer feature
- Shows "10 minutes" session

#### WatchConnectivityManager.swift (`apps/ios/MindFriendWatch/WatchConnectivityManager.swift`)

**Features:**

- Bi-directional communication between iPhone and Apple Watch
- `WCSessionDelegate` implementation
- **Sends to Watch (from iPhone):**
  - `sendStreak(_ streak: Int)`
  - `sendDailyProgress(completed: Int, goal: Int)`
- **Receives from Watch (to iPhone):**
  - Mood logs with timestamp
  - Session updates
- **Properties:**
  - `@Published var isReachable` - Watch connectivity status
  - `@Published var session` - WCSession reference

---

## File Structure

```
apps/ios/
├── MindFriendApp/
│   ├── Shared/
│   │   └── WidgetModels.swift                    [Shared types]
│   └── [existing app files]
│
├── MindFriendWidgets/                           [Widget Extension Target]
│   ├── MindFriendWidgets.swift                  [Widget bundle entry]
│   ├── WidgetModels.swift                       [Widget data types]
│   ├── SharedDataStore.swift                    [App Group sync]
│   ├── Widgets/
│   │   ├── StreakWidget.swift
│   │   ├── MoodWidget.swift
│   │   ├── ProgressWidget.swift
│   │   └── QuickActionsWidget.swift
│   └── LiveActivities/
│       └── MeditationLiveActivity.swift
│
└── MindFriendWatch/                             [watchOS App Target]
    ├── MindFriendWatchApp.swift
    ├── WatchConnectivityManager.swift
    └── Views/
        ├── WatchHomeView
        ├── WatchBreathingView
        ├── WatchMoodView
        ├── WatchStatsView
        └── WatchFocusView
```

---

## Integration Points

### Main App → Widgets

The main app should call `SharedDataStore` when:

- Quest completed: `SharedDataStore.shared.updateStreak(newStreak)`
- Mood logged: `SharedDataStore.shared.updateTodayMood(mood, score: score)`
- Activity completed: `SharedDataStore.shared.updateTodayProgress(completed:goal:)`
- Mood history loaded: `SharedDataStore.shared.updateWeekMoods(moods)`

Example from QuestView or HomeView:

```swift
// In your quest completion handler
let newStreak = calculateNewStreak()
SharedDataStore.shared.updateStreak(newStreak)  // Updates all widgets
```

### Main App → Live Activities

In your meditation/breathing session view:

```swift
// Start session
await MeditationActivityManager.shared.startActivity(
    title: "10-min Meditation",
    type: "meditation",
    durationSeconds: 600
)

// Handle pause/resume from user button
// (Live Activity handles pause/resume from Dynamic Island)

// Session ends automatically or user stops
// Activity automatically dismissed
```

### iPhone ↔ Apple Watch

In your mood logging and quest completion handlers:

```swift
// When mood is logged
WatchConnectivityManager.shared.sendStreak(currentStreak)
WatchConnectivityManager.shared.sendDailyProgress(completed, goal: goal)

// Watch sends mood back
WatchConnectivityManager.shared.session(
    _:didReceiveApplicationContext:[
        "mood": "great",
        "timestamp": Date().timeIntervalSince1970
    ]
)
```

---

## Next Steps for Full Integration

### 1. Main App Updates Needed

- [ ] Import SharedDataStore in main app
- [ ] Add Widget Extension target to Xcode project (with App Groups)
- [ ] Add watchOS target to Xcode project
- [ ] Update Quest completion handler to call `SharedDataStore.updateStreak()`
- [ ] Update Mood logging to call `SharedDataStore.updateTodayMood()`
- [ ] Update Activity progress to call `SharedDataStore.updateTodayProgress()`
- [ ] Wire up `MeditationActivityManager` in meditation/breathing views
- [ ] Initialize `WatchConnectivityManager` in AppDelegate

### 2. Configuration

- [ ] Enable App Groups capability in both targets (group.com.mindfriend.app)
- [ ] Add WidgetKit framework to Widget Extension
- [ ] Add ActivityKit framework to main app (iOS 16.1+)
- [ ] Add WatchConnectivity framework to both iOS and watchOS targets
- [ ] Update Info.plist for supported widget families

### 3. Testing

- [ ] Test widget data sync with main app
- [ ] Test widget deep links (launch main app at correct screen)
- [ ] Test Live Activities during meditation session
- [ ] Test Dynamic Island display
- [ ] Test Watch app standalone functionality
- [ ] Test Watch ↔ iPhone sync

### 4. Analytics (Future)

- [ ] Track widget_added events
- [ ] Track widget_tapped with deep link parameters
- [ ] Track live_activity_completed with duration
- [ ] Track watch_mood_logged
- [ ] Track complication_tapped

---

## Design Notes

### Color Scheme

- **Streak:** Gray (0 days) → Yellow (1-6) → Orange (7-29) → Red (30+)
- **Mood:** Green (Great) → Green.opacity(0.6) (Good) → Yellow (Okay) → Orange (Low) → Red (Stressed)
- **Progress:** Green for completion

### Widget Update Frequency

- **StreakWidget:** 1 hour or at midnight (whichever sooner)
- **MoodWidget:** 1 hour
- **ProgressWidget:** 30 minutes
- **QuickActionsWidget:** 4 hours
- All automatically refresh when data changes via `SharedDataStore.reloadWidgets()`

### Deep Links

All widgets support tapping to launch the main app at relevant screens:

- `mindfriend://home` - Home screen
- `mindfriend://streak` - Streak details
- `mindfriend://mood` - Mood logging
- `mindfriend://breathing` - Quick breathing exercise
- `mindfriend://progress` - Daily progress details
- `mindfriend://chat` - AI chat companion

---

## Success Metrics (from Spec)

| Metric               | Target           | How to Measure                           |
| -------------------- | ---------------- | ---------------------------------------- |
| Widget adoption      | 30% of users     | Analytics event widget_added             |
| Lock Screen adoption | 15% of users     | Analytics event lock_screen_widget_added |
| Widget taps/day      | 2.5 average      | Analytics event widget_tapped            |
| Watch app downloads  | 20% of iOS users | watchOS App Store analytics              |
| Time to first action | <3 seconds       | Measure from tap to main app displayed   |

---

## Known Limitations (MVP)

- [ ] Interactive widgets only available on iOS 17+ (fallback for iOS 16.4-16.8)
- [ ] Live Activities max duration: 8 hours (automatic dismissal)
- [ ] Watch app requires watchOS 8+ (check in deployment target)
- [ ] No background sync (widgets update on timeline refresh + App Group changes)
- [ ] No push-to-start Live Activities in MVP (future enhancement)

---

## Files Created

| File                                   | Size      | Purpose                |
| -------------------------------------- | --------- | ---------------------- |
| WidgetModels.swift (MindFriendApp)     | ~5KB      | Shared types           |
| WidgetModels.swift (MindFriendWidgets) | ~5KB      | Widget types           |
| SharedDataStore.swift                  | ~4KB      | App Group sync         |
| StreakWidget.swift                     | ~5KB      | Streak display         |
| MoodWidget.swift                       | ~8KB      | Mood tracking          |
| ProgressWidget.swift                   | ~11KB     | Daily progress         |
| QuickActionsWidget.swift               | ~3KB      | Quick actions          |
| MeditationLiveActivity.swift           | ~12KB     | Live Activity          |
| MindFriendWatchApp.swift               | ~15KB     | Watch app              |
| WatchConnectivityManager.swift         | ~4KB      | Phone-Watch sync       |
| **Total**                              | **~72KB** | Complete widget system |

---

**Implementation Status:** Phase 5 Complete ✅
**Next Phase:** Phase 6 - Build Verification & Testing
