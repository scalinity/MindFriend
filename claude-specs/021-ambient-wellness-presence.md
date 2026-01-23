# F021: Ambient Wellness Presence

> **Feature ID:** F021
> **Phase:** 6 - Platform Expansion
> **Priority:** P1 (High)
> **Dependencies:** F002 (Daily Wellness Score)
> **Dependents:** None

---

## 1. Overview

### 1.1 Summary

Ambient Wellness Presence extends MindFriend beyond the main app through rich home screen widgets, Apple Watch complications and app, and CarPlay integration. Users stay connected to their wellness data and can perform quick actions without opening the full app.

### 1.2 Business Value

- **User Value:** Wellness visible at a glance; quick actions without friction
- **Product Value:** Increases touchpoints dramatically; drives daily engagement
- **Competitive Value:** Most wellness apps have basic or no widgets; comprehensive platform presence is differentiating

### 1.3 User Benefit

Users maintain awareness of their wellness status passively and can take quick actions (log mood, start exercise) from wherever they are on iOS.

---

## 2. Requirements

### 2.1 Functional Requirements

| ID     | Requirement                                                            | Priority |
| ------ | ---------------------------------------------------------------------- | -------- |
| FR-001 | Home screen widget showing wellness score (small, medium, large sizes) | Must     |
| FR-002 | Widget showing today's quest with tap-to-start                         | Must     |
| FR-003 | Widget showing mood trend (7-day sparkline)                            | Should   |
| FR-004 | Lock screen widget showing streak count                                | Should   |
| FR-005 | Apple Watch complication showing wellness score                        | Must     |
| FR-006 | Apple Watch app with mood logging and quick exercises                  | Must     |
| FR-007 | CarPlay integration for voice-first wellness                           | Should   |
| FR-008 | Interactive widgets (iOS 17+) for quick mood log                       | Should   |
| FR-009 | Widget updates every 15 minutes or on significant changes              | Must     |
| FR-010 | StandBy mode support for iPhone                                        | Should   |

### 2.2 Non-Functional Requirements

| ID      | Requirement              | Target           |
| ------- | ------------------------ | ---------------- |
| NFR-001 | Widget load time         | < 1 second       |
| NFR-002 | Watch app launch time    | < 2 seconds      |
| NFR-003 | Battery impact (widgets) | < 1% daily       |
| NFR-004 | Widget refresh frequency | Every 15 minutes |

### 2.3 Acceptance Criteria

1. **AC-001:** User sees wellness score widget on home screen that updates
2. **AC-002:** User can tap widget and open directly to relevant screen
3. **AC-003:** Watch shows wellness score as complication on watch face
4. **AC-004:** User can log mood from Watch without phone
5. **AC-005:** CarPlay shows voice interface for hands-free check-in
6. **AC-006:** Lock screen widget shows streak with flame icon

---

## 3. Technical Design

### 3.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     iOS Main App                                 │
├─────────────────────────────────────────────────────────────────┤
│  WidgetDataService                                              │
│  ├─ updateSharedData()                                          │
│  ├─ getCurrentWidgetData()                                      │
│  └─ triggerWidgetReload()                                       │
│                                                                  │
│  App Groups: group.com.mindfriend.shared                        │
│  └─ UserDefaults (shared data)                                  │
├─────────────────────────────────────────────────────────────────┤
│                     Widget Extension                             │
├─────────────────────────────────────────────────────────────────┤
│  MindFriendWidgets (WidgetBundle)                               │
│  ├─ WellnessScoreWidget                                         │
│  ├─ QuestWidget                                                 │
│  ├─ MoodTrendWidget                                             │
│  └─ StreakWidget                                                │
├─────────────────────────────────────────────────────────────────┤
│                     Watch App                                    │
├─────────────────────────────────────────────────────────────────┤
│  MindFriendWatch                                                │
│  ├─ WatchHomeView                                               │
│  ├─ QuickMoodView                                               │
│  ├─ BreathingExerciseView                                       │
│  └─ ComplicationProviders                                        │
├─────────────────────────────────────────────────────────────────┤
│                     CarPlay App                                  │
├─────────────────────────────────────────────────────────────────┤
│  CarPlaySceneDelegate                                            │
│  └─ VoiceWellnessInterface                                       │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Data Models

```swift
// WidgetModels.swift

import Foundation
import WidgetKit

// MARK: - Shared Widget Data

struct WidgetData: Codable {
    let wellnessScore: Int
    let wellnessScoreDelta: Int?
    let scoreColorZone: String // "low", "medium", "high"

    let currentStreak: Int
    let streakType: String // "quest", "mood", etc.

    let todayQuest: WidgetQuest?
    let moodTrend: [Int] // Last 7 days

    let lastUpdated: Date

    static var placeholder: WidgetData {
        WidgetData(
            wellnessScore: 73,
            wellnessScoreDelta: 5,
            scoreColorZone: "high",
            currentStreak: 7,
            streakType: "quest",
            todayQuest: WidgetQuest(
                id: UUID(),
                title: "Morning Reset",
                duration: 5,
                isCompleted: false
            ),
            moodTrend: [6, 7, 6, 8, 7, 8, 7],
            lastUpdated: Date()
        )
    }
}

struct WidgetQuest: Codable {
    let id: UUID
    let title: String
    let duration: Int
    let isCompleted: Bool
}

// MARK: - Widget Entry

struct WellnessScoreEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
    let configuration: ConfigurationIntent
}

struct QuestEntry: TimelineEntry {
    let date: Date
    let quest: WidgetQuest?
    let configuration: ConfigurationIntent
}

// MARK: - Watch Data

struct WatchWellnessData: Codable {
    let wellnessScore: Int
    let todayMood: Int?
    let currentStreak: Int
    let todayQuestCompleted: Bool
    let syncedAt: Date
}
```

### 3.3 Widget Implementation

```swift
// WellnessScoreWidget.swift

import WidgetKit
import SwiftUI

struct WellnessScoreWidget: Widget {
    let kind: String = "WellnessScoreWidget"

    var body: some WidgetConfiguration {
        IntentConfiguration(
            kind: kind,
            intent: ConfigurationIntent.self,
            provider: WellnessScoreProvider()
        ) { entry in
            WellnessScoreWidgetView(entry: entry)
        }
        .configurationDisplayName("Wellness Score")
        .description("See your daily wellness score at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct WellnessScoreProvider: IntentTimelineProvider {
    func placeholder(in context: Context) -> WellnessScoreEntry {
        WellnessScoreEntry(
            date: Date(),
            data: .placeholder,
            configuration: ConfigurationIntent()
        )
    }

    func getSnapshot(
        for configuration: ConfigurationIntent,
        in context: Context,
        completion: @escaping (WellnessScoreEntry) -> Void
    ) {
        let data = loadWidgetData() ?? .placeholder
        let entry = WellnessScoreEntry(
            date: Date(),
            data: data,
            configuration: configuration
        )
        completion(entry)
    }

    func getTimeline(
        for configuration: ConfigurationIntent,
        in context: Context,
        completion: @escaping (Timeline<WellnessScoreEntry>) -> Void
    ) {
        let data = loadWidgetData() ?? .placeholder
        let entry = WellnessScoreEntry(
            date: Date(),
            data: data,
            configuration: configuration
        )

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(
            byAdding: .minute,
            value: 15,
            to: Date()
        )!

        let timeline = Timeline(
            entries: [entry],
            policy: .after(nextUpdate)
        )
        completion(timeline)
    }

    private func loadWidgetData() -> WidgetData? {
        guard let sharedDefaults = UserDefaults(suiteName: "group.com.mindfriend.shared"),
              let data = sharedDefaults.data(forKey: "widgetData") else {
            return nil
        }

        return try? JSONDecoder().decode(WidgetData.self, from: data)
    }
}

// MARK: - Widget Views

struct WellnessScoreWidgetView: View {
    let entry: WellnessScoreEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallScoreView(data: entry.data)
        case .systemMedium:
            MediumScoreView(data: entry.data)
        case .accessoryCircular:
            CircularScoreView(score: entry.data.wellnessScore)
        case .accessoryRectangular:
            RectangularScoreView(data: entry.data)
        default:
            SmallScoreView(data: entry.data)
        }
    }
}

struct SmallScoreView: View {
    let data: WidgetData

    var scoreColor: Color {
        switch data.scoreColorZone {
        case "high": return .green
        case "medium": return .yellow
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(scoreColor.opacity(0.3), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: Double(data.wellnessScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(data.wellnessScore)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    if let delta = data.wellnessScoreDelta {
                        Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                            .font(.caption2)
                            .foregroundColor(delta >= 0 ? .green : .red)
                    }
                }
            }
            .frame(width: 80, height: 80)

            Text("Wellness")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct CircularScoreView: View {
    let score: Int

    var body: some View {
        Gauge(value: Double(score), in: 0...100) {
            Text("WS")
        } currentValueLabel: {
            Text("\(score)")
                .font(.system(.body, design: .rounded, weight: .bold))
        }
        .gaugeStyle(.accessoryCircular)
    }
}

// Interactive Widget (iOS 17+)
struct InteractiveMoodWidget: Widget {
    let kind: String = "InteractiveMoodWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MoodWidgetProvider()) { entry in
            InteractiveMoodView(entry: entry)
        }
        .configurationDisplayName("Quick Mood")
        .description("Log your mood with one tap.")
        .supportedFamilies([.systemSmall])
    }
}

struct InteractiveMoodView: View {
    let entry: MoodEntry

    var body: some View {
        VStack {
            Text("How are you?")
                .font(.caption)

            HStack(spacing: 12) {
                ForEach([3, 5, 7, 9], id: \.self) { mood in
                    Button(intent: LogMoodIntent(mood: mood)) {
                        Text(moodEmoji(mood))
                            .font(.title)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    func moodEmoji(_ mood: Int) -> String {
        switch mood {
        case 1...3: return "😔"
        case 4...5: return "😐"
        case 6...7: return "🙂"
        default: return "😊"
        }
    }
}
```

### 3.4 Watch App

```swift
// WatchHomeView.swift

import SwiftUI
import WatchConnectivity

struct WatchHomeView: View {
    @StateObject private var viewModel = WatchHomeViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Wellness Score
                    WellnessScoreRing(score: viewModel.wellnessScore, size: 100)

                    // Quick Mood
                    NavigationLink(destination: QuickMoodView(viewModel: viewModel)) {
                        HStack {
                            Image(systemName: "face.smiling")
                            Text("Log Mood")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    // Quick Breathing
                    NavigationLink(destination: BreathingExerciseView()) {
                        HStack {
                            Image(systemName: "wind")
                            Text("Breathe")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    // Streak
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                        Text("\(viewModel.currentStreak) day streak")
                    }
                    .font(.caption)
                }
                .padding()
            }
        }
        .onAppear {
            viewModel.refresh()
        }
    }
}

struct QuickMoodView: View {
    @ObservedObject var viewModel: WatchHomeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedMood: Int = 5

    var body: some View {
        VStack {
            Text("How are you?")
                .font(.headline)

            // Digital Crown scroll for mood
            Picker("Mood", selection: $selectedMood) {
                ForEach(1...10, id: \.self) { mood in
                    Text("\(mood)")
                        .tag(mood)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 80)

            Button("Log Mood") {
                viewModel.logMood(selectedMood)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// Watch Complication
struct WellnessComplicationProvider: TimelineProvider {
    typealias Entry = WellnessComplicationEntry

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), score: 73)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let entry = Entry(date: Date(), score: loadScore() ?? 73)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: Date(), score: loadScore() ?? 73)
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900)))
        completion(timeline)
    }

    private func loadScore() -> Int? {
        // Load from shared UserDefaults or WCSession transfer
        UserDefaults.standard.integer(forKey: "wellnessScore")
    }
}

struct WellnessComplicationEntry: TimelineEntry {
    let date: Date
    let score: Int
}
```

### 3.5 Main App Integration

```swift
// WidgetDataService.swift

import Foundation
import WidgetKit

class WidgetDataService {
    static let shared = WidgetDataService()

    private let sharedDefaults = UserDefaults(suiteName: "group.com.mindfriend.shared")

    func updateWidgetData(
        wellnessScore: Int,
        delta: Int?,
        streak: Int,
        quest: Quest?,
        moodTrend: [Int]
    ) {
        let data = WidgetData(
            wellnessScore: wellnessScore,
            wellnessScoreDelta: delta,
            scoreColorZone: colorZone(for: wellnessScore),
            currentStreak: streak,
            streakType: "quest",
            todayQuest: quest.map {
                WidgetQuest(
                    id: $0.id,
                    title: $0.template.title,
                    duration: $0.template.estimatedMinutes,
                    isCompleted: $0.status == .completed
                )
            },
            moodTrend: moodTrend,
            lastUpdated: Date()
        )

        if let encoded = try? JSONEncoder().encode(data) {
            sharedDefaults?.set(encoded, forKey: "widgetData")
        }

        // Trigger widget reload
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func colorZone(for score: Int) -> String {
        switch score {
        case 0..<40: return "low"
        case 40..<70: return "medium"
        default: return "high"
        }
    }
}
```

---

## 4. Implementation Details

### 4.1 Step-by-Step Implementation

#### Step 1: App Groups Setup

1. Create App Group in Apple Developer Portal
2. Add App Group capability to main app
3. Add App Group capability to widget extension
4. Add App Group capability to watch app

#### Step 2: Widget Extension

1. Create Widget Extension target
2. Implement `WellnessScoreWidget`
3. Implement `QuestWidget`
4. Implement `StreakWidget`
5. Add interactive mood widget (iOS 17+)

#### Step 3: Main App Integration

1. Create `WidgetDataService`
2. Call `updateWidgetData` on relevant changes
3. Trigger `WidgetCenter.shared.reloadAllTimelines()`

#### Step 4: Watch App

1. Create Watch App target
2. Implement `WatchHomeView`
3. Implement `QuickMoodView`
4. Implement `BreathingExerciseView`
5. Add complication providers

#### Step 5: Watch Connectivity

1. Implement `WCSession` delegate
2. Sync wellness data to watch
3. Handle mood logs from watch

#### Step 6: CarPlay (Optional)

1. Add CarPlay capability
2. Create `CarPlaySceneDelegate`
3. Implement voice-first interface

### 4.2 File Structure

```
apps/ios/
├── MindFriendApp/
│   └── Core/Services/
│       └── WidgetDataService.swift
├── MindFriendWidget/
│   ├── MindFriendWidgets.swift
│   ├── WellnessScoreWidget.swift
│   ├── QuestWidget.swift
│   ├── StreakWidget.swift
│   ├── InteractiveMoodWidget.swift
│   └── Assets.xcassets/
├── MindFriendWatch/
│   ├── MindFriendWatchApp.swift
│   ├── Views/
│   │   ├── WatchHomeView.swift
│   │   ├── QuickMoodView.swift
│   │   └── BreathingExerciseView.swift
│   ├── Complications/
│   │   └── WellnessComplication.swift
│   └── ViewModels/
│       └── WatchHomeViewModel.swift
└── MindFriendCarPlay/
    └── CarPlaySceneDelegate.swift
```

---

## 5. Dependencies

### 5.1 Prerequisites

| Feature                    | Reason                   |
| -------------------------- | ------------------------ |
| F002: Daily Wellness Score | Primary data for widgets |

### 5.2 External Libraries

| Library           | Version     | Purpose             |
| ----------------- | ----------- | ------------------- |
| WidgetKit         | iOS 17+     | Home screen widgets |
| WatchKit          | watchOS 10+ | Watch app           |
| CarPlay           | iOS 17+     | CarPlay integration |
| WatchConnectivity | iOS 17+     | Phone-watch sync    |

---

## 6. Edge Cases

| Scenario                         | Expected Behavior                               |
| -------------------------------- | ----------------------------------------------- |
| No data yet (new user)           | Show placeholder with "Open app to get started" |
| App not launched today           | Show last known data with "Last updated X ago"  |
| Watch not paired                 | Widget works; watch features disabled           |
| Widget tap when app backgrounded | Deep link to correct screen                     |
| Data sync fails (watch)          | Show last synced data with indicator            |

---

## 7. Testing Requirements

### 7.1 Test Scenarios

| Test Case             | Input             | Expected Output                |
| --------------------- | ----------------- | ------------------------------ |
| Widget displays score | Score = 73        | Widget shows 73 with ring      |
| Widget updates        | Mood logged       | Widget refreshes within 15 min |
| Watch mood log        | Log 7 on watch    | Syncs to phone, updates widget |
| Interactive widget    | Tap mood emoji    | Mood logged, widget updates    |
| Complication          | Watch face active | Shows current score            |
