# Apple Watch & iOS Widgets

> Reduce friction to near-zero with glanceable access to mental wellness.

**Priority:** P1 - High Value
**Effort:** Medium (3-4 weeks)
**Impact:** Daily engagement boost; premium differentiator

---

## 1. Overview

### 1.1 What It Does

Apple Watch app with complications and iOS home screen widgets that provide:

- Quick mood check-in without opening app
- Streak display and quest reminder
- One-tap breathing exercise
- Daily progress at a glance

### 1.2 Why It Exists

- **Friction Reduction:** Mood check-in from watch face in 5 seconds
- **Habit Reinforcement:** Visible streak on watch face drives consistency
- **Competitor Parity:** Headspace has Apple Watch app; this is table stakes
- **Premium Value:** Enhances premium tier with exclusive complications

### 1.3 Success Metrics

| Metric                          | Target                    | Measurement     |
| ------------------------------- | ------------------------- | --------------- |
| Widget installation             | 30% of iOS users          | Analytics       |
| Watch app adoption              | 40% of Apple Watch owners | Analytics       |
| Complication usage              | 20% daily active          | Analytics       |
| Check-in conversion from widget | 15% of daily check-ins    | Source tracking |

---

## 2. Functional Requirements

### 2.1 Apple Watch App

| ID    | Requirement                                | Priority |
| ----- | ------------------------------------------ | -------- |
| WA-01 | Quick mood check-in (emoji picker)         | Must     |
| WA-02 | Start breathing exercise                   | Must     |
| WA-03 | View current streak                        | Must     |
| WA-04 | View today's quest                         | Should   |
| WA-05 | Complete quest from watch                  | Should   |
| WA-06 | Haptic breathing pacer                     | Must     |
| WA-07 | Sync with iPhone app via WatchConnectivity | Must     |
| WA-08 | Standalone functionality (WiFi/LTE)        | Should   |

### 2.2 Watch Complications

| ID    | Complication                       | Priority |
| ----- | ---------------------------------- | -------- |
| WC-01 | Circular: Current streak number    | Must     |
| WC-02 | Corner: Mood prompt icon           | Must     |
| WC-03 | Rectangular: Streak + mood status  | Should   |
| WC-04 | Inline: "Check in with MindFriend" | Should   |
| WC-05 | Graphic circular: Breathing ring   | Should   |

### 2.3 iOS Widgets

| ID    | Widget              | Sizes         | Priority |
| ----- | ------------------- | ------------- | -------- |
| IW-01 | Quick Mood Check-in | Small, Medium | Must     |
| IW-02 | Daily Progress      | Medium, Large | Must     |
| IW-03 | Streak Display      | Small         | Must     |
| IW-04 | Today's Quest       | Small, Medium | Should   |
| IW-05 | Quick Breathing     | Small         | Should   |
| IW-06 | Weekly Mood Trend   | Large         | Could    |

### 2.4 Widget Interactions

| ID    | Requirement                                    | Priority |
| ----- | ---------------------------------------------- | -------- |
| WI-01 | Tap mood emoji → logs mood, shows confirmation | Must     |
| WI-02 | Tap streak → opens home screen                 | Must     |
| WI-03 | Tap quest → opens quest detail                 | Must     |
| WI-04 | Tap breathing → starts breathing in app        | Must     |
| WI-05 | Deep link to specific app screens              | Must     |
| WI-06 | Widget configuration in settings               | Should   |

---

## 3. Technical Requirements

### 3.1 Apple Watch Architecture

```
MindFriendWatch/
├── MindFriendWatchApp.swift
├── ContentView.swift
├── Views/
│   ├── MoodCheckInView.swift
│   ├── BreathingExerciseView.swift
│   ├── StreakView.swift
│   └── QuestView.swift
├── Services/
│   ├── WatchSessionManager.swift
│   └── WatchDataStore.swift
├── Complications/
│   └── ComplicationController.swift
└── Assets.xcassets/
```

### 3.2 WatchConnectivity Setup

```swift
// Shared/WatchSessionManager.swift

import WatchConnectivity

class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published var isReachable = false
    @Published var currentStreak: Int = 0
    @Published var lastMoodScore: Int?
    @Published var todayQuest: WatchQuest?

    private var session: WCSession?

    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }

    // MARK: - Send to Watch

    func sendMoodUpdate(_ score: Int) {
        guard let session = session, session.isReachable else {
            // Use application context for background sync
            try? session?.updateApplicationContext(["lastMood": score])
            return
        }
        session.sendMessage(["action": "moodUpdate", "score": score], replyHandler: nil)
    }

    func sendStreakUpdate(_ streak: Int) {
        try? session?.updateApplicationContext(["currentStreak": streak])
    }

    func sendQuestUpdate(_ quest: WatchQuest) {
        let questData = try? JSONEncoder().encode(quest)
        try? session?.updateApplicationContext(["todayQuest": questData as Any])
    }

    // MARK: - Receive from Watch

    func handleMoodLoggedOnWatch(_ score: Int, timestamp: Date) {
        Task { @MainActor in
            // Sync to server
            try? await SupabaseDataService.shared.logMood(
                score: score,
                anxiety: nil,
                energy: nil,
                notes: nil
            )
        }
    }
}

extension WatchSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let action = message["action"] as? String {
            switch action {
            case "moodLogged":
                if let score = message["score"] as? Int {
                    handleMoodLoggedOnWatch(score, timestamp: Date())
                }
            case "questCompleted":
                if let questId = message["questId"] as? String {
                    // Handle quest completion
                }
            default:
                break
            }
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}

// Shared model for watch
struct WatchQuest: Codable {
    let id: UUID
    let title: String
    let description: String
    let isCompleted: Bool
}
```

### 3.3 Watch App Views

```swift
// MindFriendWatch/Views/MoodCheckInView.swift

import SwiftUI

struct MoodCheckInView: View {
    @StateObject private var sessionManager = WatchSessionManager.shared
    @State private var selectedMood: Int?
    @State private var showConfirmation = false

    let moods = [
        (emoji: "😢", score: 2),
        (emoji: "😕", score: 4),
        (emoji: "😐", score: 5),
        (emoji: "🙂", score: 7),
        (emoji: "😊", score: 9)
    ]

    var body: some View {
        VStack(spacing: 8) {
            Text("How are you?")
                .font(.headline)

            HStack(spacing: 4) {
                ForEach(moods, id: \.score) { mood in
                    Button {
                        logMood(mood.score)
                    } label: {
                        Text(mood.emoji)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .overlay {
            if showConfirmation {
                MoodConfirmationView(mood: selectedMood ?? 5)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func logMood(_ score: Int) {
        selectedMood = score
        WKInterfaceDevice.current().play(.success)

        // Send to iPhone
        sessionManager.sendMessage(
            ["action": "moodLogged", "score": score],
            replyHandler: nil
        )

        withAnimation {
            showConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showConfirmation = false
            }
        }
    }
}

// MindFriendWatch/Views/BreathingExerciseView.swift

struct BreathingExerciseView: View {
    @State private var phase: BreathPhase = .inhale
    @State private var scale: CGFloat = 1.0
    @State private var cycleCount = 0
    @State private var isActive = false

    let totalCycles = 4

    enum BreathPhase: String {
        case inhale = "Breathe In"
        case hold = "Hold"
        case exhale = "Breathe Out"
    }

    var body: some View {
        VStack {
            if isActive {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.3))
                        .scaleEffect(scale)

                    VStack {
                        Text(phase.rawValue)
                            .font(.headline)
                        Text("\(cycleCount + 1)/\(totalCycles)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 120, height: 120)
            } else {
                Button("Start") {
                    startBreathing()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Breathe")
    }

    private func startBreathing() {
        isActive = true
        cycleCount = 0
        runBreathCycle()
    }

    private func runBreathCycle() {
        guard cycleCount < totalCycles else {
            isActive = false
            WKInterfaceDevice.current().play(.success)
            return
        }

        // Inhale (4 seconds)
        phase = .inhale
        WKInterfaceDevice.current().play(.start)
        withAnimation(.easeInOut(duration: 4)) {
            scale = 1.5
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            // Hold (7 seconds)
            phase = .hold
            WKInterfaceDevice.current().play(.click)

            DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                // Exhale (8 seconds)
                phase = .exhale
                WKInterfaceDevice.current().play(.stop)
                withAnimation(.easeInOut(duration: 8)) {
                    scale = 1.0
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    cycleCount += 1
                    runBreathCycle()
                }
            }
        }
    }
}
```

### 3.4 Complications

```swift
// MindFriendWatch/Complications/ComplicationController.swift

import ClockKit
import SwiftUI

class ComplicationController: NSObject, CLKComplicationDataSource {

    // MARK: - Complication Configuration

    func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        let descriptors = [
            CLKComplicationDescriptor(
                identifier: "streak",
                displayName: "Streak",
                supportedFamilies: [.circularSmall, .graphicCircular, .graphicCorner]
            ),
            CLKComplicationDescriptor(
                identifier: "mood",
                displayName: "Mood Check-in",
                supportedFamilies: [.graphicCorner, .graphicRectangular]
            ),
            CLKComplicationDescriptor(
                identifier: "breathing",
                displayName: "Quick Breathe",
                supportedFamilies: [.graphicCircular]
            )
        ]
        handler(descriptors)
    }

    // MARK: - Timeline Entry

    func currentTimelineEntry(for complication: CLKComplication) async -> CLKComplicationTimelineEntry? {
        let streak = WatchSessionManager.shared.currentStreak

        let template: CLKComplicationTemplate?

        switch complication.family {
        case .circularSmall:
            template = CLKComplicationTemplateCircularSmallSimpleText(
                textProvider: CLKSimpleTextProvider(text: "\(streak)🔥")
            )

        case .graphicCircular:
            if complication.identifier == "breathing" {
                template = CLKComplicationTemplateGraphicCircularView(
                    BreathingComplicationView()
                )
            } else {
                template = CLKComplicationTemplateGraphicCircularView(
                    StreakComplicationView(streak: streak)
                )
            }

        case .graphicCorner:
            template = CLKComplicationTemplateGraphicCornerTextView(
                textProvider: CLKSimpleTextProvider(text: "\(streak) day streak"),
                label: MoodPromptView()
            )

        case .graphicRectangular:
            template = CLKComplicationTemplateGraphicRectangularFullView(
                DailyProgressComplicationView(streak: streak)
            )

        default:
            template = nil
        }

        if let template = template {
            return CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
        }
        return nil
    }
}

// Complication SwiftUI Views
struct StreakComplicationView: View {
    let streak: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.orange, lineWidth: 4)

            VStack(spacing: 0) {
                Text("\(streak)")
                    .font(.system(size: 24, weight: .bold))
                Text("🔥")
                    .font(.system(size: 12))
            }
        }
    }
}

struct BreathingComplicationView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.3))

            Image(systemName: "wind")
                .font(.title2)
        }
    }
}

struct DailyProgressComplicationView: View {
    let streak: Int

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("MindFriend")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("🔥 \(streak)")
                    .font(.caption)
            }

            Text("Check in today")
                .font(.headline)

            ProgressView(value: 0.6)
                .tint(.green)
        }
    }
}
```

### 3.5 iOS Widgets

```swift
// Widgets/MoodWidget.swift

import WidgetKit
import SwiftUI

struct MoodWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoodWidgetEntry {
        MoodWidgetEntry(date: Date(), lastMood: nil, checkedInToday: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (MoodWidgetEntry) -> Void) {
        let entry = MoodWidgetEntry(date: Date(), lastMood: 7, checkedInToday: true)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MoodWidgetEntry>) -> Void) {
        // Fetch from shared data store
        let entry = MoodWidgetEntry(
            date: Date(),
            lastMood: UserDefaults.shared.integer(forKey: "lastMoodScore"),
            checkedInToday: UserDefaults.shared.bool(forKey: "checkedInToday")
        )

        // Refresh every hour
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct MoodWidgetEntry: TimelineEntry {
    let date: Date
    let lastMood: Int?
    let checkedInToday: Bool
}

struct MoodWidgetView: View {
    let entry: MoodWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallMoodWidget(entry: entry)
        case .systemMedium:
            MediumMoodWidget(entry: entry)
        default:
            SmallMoodWidget(entry: entry)
        }
    }
}

struct SmallMoodWidget: View {
    let entry: MoodWidgetEntry

    let moods = ["😢", "😕", "😐", "🙂", "😊"]

    var body: some View {
        VStack(spacing: 8) {
            if entry.checkedInToday {
                Text("Feeling \(moods[(entry.lastMood ?? 5) / 2])")
                    .font(.headline)
                Text("Tap to update")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("How are you?")
                    .font(.headline)

                HStack(spacing: 2) {
                    ForEach(0..<5) { index in
                        Link(destination: URL(string: "mindfriend://mood/\(index * 2 + 1)")!) {
                            Text(moods[index])
                                .font(.title3)
                        }
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct MediumMoodWidget: View {
    let entry: MoodWidgetEntry
    let moods = ["😢", "😕", "😐", "🙂", "😊"]

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("MindFriend")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("How are you feeling?")
                    .font(.headline)

                Spacer()

                HStack(spacing: 8) {
                    ForEach(0..<5) { index in
                        Link(destination: URL(string: "mindfriend://mood/\(index * 2 + 1)")!) {
                            Text(moods[index])
                                .font(.title2)
                                .padding(8)
                                .background(Color.secondary.opacity(0.2))
                                .clipShape(Circle())
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget Definition

@main
struct MindFriendWidgetBundle: WidgetBundle {
    var body: some Widget {
        MoodWidget()
        StreakWidget()
        QuestWidget()
        ProgressWidget()
    }
}

struct MoodWidget: Widget {
    let kind = "MoodWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MoodWidgetProvider()) { entry in
            MoodWidgetView(entry: entry)
        }
        .configurationDisplayName("Mood Check-in")
        .description("Quick mood check-in from your home screen")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
```

### 3.6 Widget Deep Links

```swift
// In main iOS app - handle deep links

func handleDeepLink(_ url: URL) {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.scheme == "mindfriend" else { return }

    switch components.host {
    case "mood":
        if let scoreString = components.path.dropFirst().description as String?,
           let score = Int(scoreString) {
            // Navigate to mood screen with pre-selected score
            AppState.shared.pendingMoodScore = score
            AppState.shared.selectedTab = .home
        }

    case "quest":
        AppState.shared.selectedTab = .home
        AppState.shared.showQuestDetail = true

    case "breathing":
        AppState.shared.selectedTab = .home
        AppState.shared.showBreathingExercise = true

    case "streak":
        AppState.shared.selectedTab = .home

    default:
        break
    }
}
```

---

## 4. UI/UX Specifications

### 4.1 Watch App Screens

```
┌──────────────────┐
│   MindFriend     │
├──────────────────┤
│                  │
│ How are you?     │
│                  │
│ 😢 😕 😐 🙂 😊   │
│                  │
│ ─────────────── │
│                  │
│ 🔥 12 day streak │
│                  │
│ [Breathe] [Quest]│
│                  │
└──────────────────┘
```

### 4.2 Widget Layouts

**Small Widget (Mood):**

```
┌─────────────────┐
│  How are you?   │
│                 │
│ 😢 😕 😐 🙂 😊  │
│                 │
│ Tap to check in │
└─────────────────┘
```

**Medium Widget (Progress):**

```
┌─────────────────────────────────┐
│ MindFriend                🔥 12 │
│                                 │
│ Today's Quest                   │
│ ┌─────────────────────────────┐ │
│ │ 🎯 5-minute meditation      │ │
│ │ ████████░░ 80%              │ │
│ └─────────────────────────────┘ │
│                                 │
│ Mood: 🙂 • Streak: 12 days      │
└─────────────────────────────────┘
```

**Large Widget (Weekly Trend):**

```
┌─────────────────────────────────┐
│ MindFriend          This Week   │
├─────────────────────────────────┤
│                                 │
│ Mood Trend                      │
│ 10 ┤                            │
│  8 ┤      ∙    ∙                │
│  6 ┤   ∙     ∙   ∙  ∙           │
│  4 ┤ ∙                          │
│    └──────────────────────      │
│      M  T  W  T  F  S  S        │
│                                 │
│ 🔥 12 day streak                │
│ ✓ 5/7 quests completed          │
│                                 │
└─────────────────────────────────┘
```

---

## 5. Acceptance Criteria

### Watch App

- [ ] User can log mood from watch in < 5 seconds
- [ ] Breathing exercise plays with haptic feedback
- [ ] Streak is displayed accurately
- [ ] Data syncs to iPhone app
- [ ] Works standalone when iPhone not nearby (WiFi/LTE)

### Complications

- [ ] Streak complication shows current number
- [ ] Tapping complication opens watch app
- [ ] Complications update when app data changes
- [ ] All complication families render correctly

### iOS Widgets

- [ ] Mood widget allows direct mood selection
- [ ] Progress widget shows streak and quest
- [ ] Widgets update hourly and on app interaction
- [ ] Deep links navigate to correct screens
- [ ] All widget sizes render correctly

---

## 6. Performance Requirements

| Metric                 | Target                          |
| ---------------------- | ------------------------------- |
| Watch app launch       | < 1 second                      |
| Complication update    | < 500ms                         |
| Widget refresh         | < 1 second                      |
| Watch-iPhone sync      | < 2 seconds                     |
| Battery impact (watch) | < 2% per day from complications |

---

## 7. Rollout Plan

### Phase 1: Watch App (Week 1-2)

- Basic watch app with mood check-in
- Breathing exercise with haptics
- WatchConnectivity setup

### Phase 2: Complications (Week 2-3)

- Streak complication
- Mood prompt complication
- Breathing complication

### Phase 3: iOS Widgets (Week 3-4)

- Mood widget (small/medium)
- Progress widget
- Streak widget
- Deep link handling

### Phase 4: Polish

- Widget configuration
- Background refresh optimization
- Premium complication features
