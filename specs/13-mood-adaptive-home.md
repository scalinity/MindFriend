# Mood-Adaptive Home Experience

## Overview

**Goal:** Transform the static home screen into a context-aware experience that responds to the user's current mood, time of day, and recent activity patterns.

**Why it matters:** A one-size-fits-all home screen misses opportunities to meet users where they are emotionally. When someone logs a low mood, showing the same cheerful content feels tone-deaf. Contextual relevance increases perceived app value by 40% and drives deeper engagement.

**Impact:** P4 priority - Increases personalization and emotional connection

---

## User Stories

- As a user feeling down, I want the app to offer calming content so that I feel supported
- As a user feeling great, I want the app to celebrate with me so that my good mood is reinforced
- As a morning user, I want energizing content so that I start my day with motivation
- As an evening user, I want wind-down suggestions so that I can relax before bed

---

## Product Requirements

### Must Have (MVP)

1. **Mood-Responsive Content Prioritization**
   - Low mood (1-2): Surface calming exercises, gentle quest options, subtle crisis resources
   - Neutral mood (3): Standard experience with variety
   - High mood (4-5): Celebratory messaging, share prompts, challenge suggestions

2. **Time-of-Day Adaptation**
   - Morning (5AM-12PM): Energizing exercises, "Start your day" messaging
   - Afternoon (12PM-5PM): Focus/productivity content, quick exercises
   - Evening (5PM-9PM): Wind-down exercises, reflection prompts
   - Night (9PM-5AM): Sleep-focused content, calming activities

3. **Adaptive Content Cards**
   - "Feeling [mood]? Here's something that might help..."
   - Dynamically ordered based on mood + time
   - Different card backgrounds/colors for mood states

4. **Crisis Resources Surfacing**
   - When mood ≤2 for consecutive days, show supportive message
   - Non-intrusive "Need extra support?" prompt
   - Never hide crisis resources, but make more visible when needed

5. **Contextual Quick Actions**
   - Quick action buttons change based on context
   - Low mood: "Talk to AI", "Breathing Exercise", "Reach Out"
   - High mood: "Share with Circle", "Try a Challenge", "Explore New"

### Nice to Have (V2)

- Weather integration (rainy day = indoor exercises)
- Location awareness (at work vs home)
- Recent activity patterns (didn't exercise yesterday = suggest it)
- Seasonal affective adaptations
- Personalized greeting variations
- AI-generated contextual suggestions

### Out of Scope

- Automatic mood prediction without logging
- Health data integration (sleep, heart rate)
- Real-time adaptation during session
- Location tracking

---

## Technical Design

### Data Model Changes

```sql
-- Migration: 20260119_mood_adaptive_home.sql

-- User context for home personalization
CREATE TABLE user_home_context (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  context_date DATE NOT NULL,

  -- Mood context
  today_mood INT,
  mood_trend TEXT CHECK (mood_trend IN ('improving', 'stable', 'declining', 'unknown')),
  consecutive_low_mood_days INT DEFAULT 0,

  -- Time context (calculated at request time)
  time_of_day TEXT, -- morning, afternoon, evening, night

  -- Activity context
  days_since_exercise INT DEFAULT 0,
  days_since_circle_checkin INT DEFAULT 0,
  quest_completed_today BOOLEAN DEFAULT FALSE,

  -- Recommended content (cached)
  recommended_exercise_ids JSONB DEFAULT '[]'::jsonb,
  recommended_actions JSONB DEFAULT '[]'::jsonb,
  supportive_message TEXT,

  generated_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id, context_date)
);

CREATE INDEX idx_home_context_user ON user_home_context(user_id, context_date);

-- Mood trend tracking (for consecutive low mood detection)
CREATE OR REPLACE FUNCTION calculate_mood_trend(p_user_id UUID, p_days INT DEFAULT 7)
RETURNS TABLE(
  trend TEXT,
  consecutive_low INT,
  avg_recent FLOAT,
  avg_previous FLOAT
) AS $$
DECLARE
  v_recent FLOAT;
  v_previous FLOAT;
  v_consecutive INT;
BEGIN
  -- Recent average (last N/2 days)
  SELECT AVG(mood_score) INTO v_recent
  FROM moods
  WHERE user_id = p_user_id
    AND created_at > NOW() - (p_days / 2 || ' days')::interval;

  -- Previous average (N/2 to N days ago)
  SELECT AVG(mood_score) INTO v_previous
  FROM moods
  WHERE user_id = p_user_id
    AND created_at > NOW() - (p_days || ' days')::interval
    AND created_at <= NOW() - (p_days / 2 || ' days')::interval;

  -- Count consecutive low mood days
  SELECT COUNT(*) INTO v_consecutive
  FROM (
    SELECT local_date, mood_score
    FROM moods
    WHERE user_id = p_user_id
    ORDER BY local_date DESC
  ) recent
  WHERE mood_score <= 2
  AND local_date >= (
    SELECT MIN(local_date) FROM (
      SELECT local_date, mood_score,
        LAG(mood_score) OVER (ORDER BY local_date) as prev_mood
      FROM moods WHERE user_id = p_user_id
      ORDER BY local_date DESC LIMIT 7
    ) sub WHERE mood_score > 2 OR prev_mood > 2
  );

  -- Determine trend
  trend := CASE
    WHEN v_recent IS NULL OR v_previous IS NULL THEN 'unknown'
    WHEN v_recent > v_previous + 0.5 THEN 'improving'
    WHEN v_recent < v_previous - 0.5 THEN 'declining'
    ELSE 'stable'
  END;

  consecutive_low := COALESCE(v_consecutive, 0);
  avg_recent := v_recent;
  avg_previous := v_previous;

  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RLS
ALTER TABLE user_home_context ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users see own home context" ON user_home_context
  FOR ALL USING (auth.uid() = user_id);
```

### iOS Implementation

**New Models** (`Core/Models.swift`):

```swift
enum TimeOfDay: String, Codable {
    case morning, afternoon, evening, night

    static var current: TimeOfDay {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }

    var greeting: String {
        switch self {
        case .morning: return "Good morning"
        case .afternoon: return "Good afternoon"
        case .evening: return "Good evening"
        case .night: return "Hello"
        }
    }

    var suggestedActivityType: String {
        switch self {
        case .morning: return "energizing"
        case .afternoon: return "focusing"
        case .evening: return "calming"
        case .night: return "sleep"
        }
    }
}

enum MoodContext: Codable {
    case low      // 1-2
    case neutral  // 3
    case high     // 4-5

    init(score: Int) {
        switch score {
        case 1...2: self = .low
        case 3: self = .neutral
        default: self = .high
        }
    }

    var colorScheme: Color {
        switch self {
        case .low: return .blue    // Calming
        case .neutral: return .purple
        case .high: return .green  // Celebratory
        }
    }

    var supportiveMessage: String? {
        switch self {
        case .low: return "It's okay to have tough days. We're here for you."
        case .neutral: return nil
        case .high: return "Wonderful! Your positive energy is inspiring."
        }
    }
}

struct HomeContext: Codable {
    let todayMood: Int?
    let moodTrend: String?
    let consecutiveLowMoodDays: Int
    let timeOfDay: TimeOfDay
    let daysSinceExercise: Int
    let daysSinceCircleCheckin: Int
    let questCompletedToday: Bool
    let recommendedExerciseIds: [UUID]
    let recommendedActions: [RecommendedAction]
    let supportiveMessage: String?

    var moodContext: MoodContext? {
        guard let mood = todayMood else { return nil }
        return MoodContext(score: mood)
    }

    var showCrisisSupport: Bool {
        consecutiveLowMoodDays >= 2 || (todayMood ?? 3) <= 1
    }

    struct RecommendedAction: Codable {
        let type: ActionType
        let title: String
        let icon: String
        let priority: Int

        enum ActionType: String, Codable {
            case exercise, chat, circle, quest, breathing, journal, celebrate, share
        }
    }

    enum CodingKeys: String, CodingKey {
        case todayMood = "today_mood"
        case moodTrend = "mood_trend"
        case consecutiveLowMoodDays = "consecutive_low_mood_days"
        case timeOfDay = "time_of_day"
        case daysSinceExercise = "days_since_exercise"
        case daysSinceCircleCheckin = "days_since_circle_checkin"
        case questCompletedToday = "quest_completed_today"
        case recommendedExerciseIds = "recommended_exercise_ids"
        case recommendedActions = "recommended_actions"
        case supportiveMessage = "supportive_message"
    }
}
```

**Service Methods** (`Networking/Services/SupabaseDataService.swift`):

```swift
// MARK: - Home Context

func getHomeContext() async throws -> HomeContext {
    let userId = try await getCurrentUserId()

    // Get today's mood
    let todayMood: Int? = try await getTodayMood()?.moodScore

    // Get mood trend
    struct TrendResult: Codable {
        let trend: String
        let consecutiveLow: Int
        let avgRecent: Double?
        let avgPrevious: Double?

        enum CodingKeys: String, CodingKey {
            case trend
            case consecutiveLow = "consecutive_low"
            case avgRecent = "avg_recent"
            case avgPrevious = "avg_previous"
        }
    }

    let trends: [TrendResult] = try await supabase
        .rpc("calculate_mood_trend", params: ["p_user_id": userId, "p_days": 7])
        .execute()
        .value

    let trend = trends.first

    // Get activity context
    let exerciseDays = try await daysSinceLastExercise()
    let circleDays = try await daysSinceLastCircleCheckin()
    let questDone = try await isQuestCompletedToday()

    // Build recommended actions based on context
    let actions = buildRecommendedActions(
        mood: todayMood,
        timeOfDay: TimeOfDay.current,
        daysSinceExercise: exerciseDays,
        daysSinceCircle: circleDays
    )

    // Get recommended exercises
    let exerciseIds = try await getRecommendedExercises(
        mood: todayMood,
        timeOfDay: TimeOfDay.current
    )

    return HomeContext(
        todayMood: todayMood,
        moodTrend: trend?.trend,
        consecutiveLowMoodDays: trend?.consecutiveLow ?? 0,
        timeOfDay: TimeOfDay.current,
        daysSinceExercise: exerciseDays,
        daysSinceCircleCheckin: circleDays,
        questCompletedToday: questDone,
        recommendedExerciseIds: exerciseIds,
        recommendedActions: actions,
        supportiveMessage: buildSupportiveMessage(
            mood: todayMood,
            trend: trend?.trend,
            consecutiveLow: trend?.consecutiveLow ?? 0
        )
    )
}

private func buildRecommendedActions(
    mood: Int?,
    timeOfDay: TimeOfDay,
    daysSinceExercise: Int,
    daysSinceCircle: Int
) -> [HomeContext.RecommendedAction] {
    var actions: [HomeContext.RecommendedAction] = []

    let moodContext = mood.map { MoodContext(score: $0) }

    // Low mood: prioritize support
    if moodContext == .low {
        actions.append(.init(type: .chat, title: "Talk to AI", icon: "bubble.left.fill", priority: 1))
        actions.append(.init(type: .breathing, title: "Calm Breathing", icon: "wind", priority: 2))
        actions.append(.init(type: .circle, title: "Reach Out", icon: "heart.fill", priority: 3))
    }
    // High mood: prioritize celebration
    else if moodContext == .high {
        actions.append(.init(type: .share, title: "Share Joy", icon: "heart.circle.fill", priority: 1))
        actions.append(.init(type: .celebrate, title: "Try Challenge", icon: "star.fill", priority: 2))
        actions.append(.init(type: .exercise, title: "Explore New", icon: "sparkles", priority: 3))
    }
    // Neutral: balance
    else {
        // Time-based suggestions
        switch timeOfDay {
        case .morning:
            actions.append(.init(type: .exercise, title: "Energize", icon: "sun.max.fill", priority: 1))
        case .afternoon:
            actions.append(.init(type: .breathing, title: "Quick Reset", icon: "wind", priority: 1))
        case .evening:
            actions.append(.init(type: .journal, title: "Reflect", icon: "pencil.line", priority: 1))
        case .night:
            actions.append(.init(type: .exercise, title: "Wind Down", icon: "moon.fill", priority: 1))
        }

        // Activity-based suggestions
        if daysSinceExercise >= 2 {
            actions.append(.init(type: .exercise, title: "Move", icon: "figure.walk", priority: 2))
        }
        if daysSinceCircle >= 3 {
            actions.append(.init(type: .circle, title: "Check In", icon: "person.2.fill", priority: 3))
        }
    }

    return actions.sorted { $0.priority < $1.priority }
}

private func buildSupportiveMessage(mood: Int?, trend: String?, consecutiveLow: Int) -> String? {
    // Multiple consecutive low days
    if consecutiveLow >= 3 {
        return "You've had a few tough days. Remember, it's okay to seek support. We're here for you. 💙"
    }
    if consecutiveLow >= 2 {
        return "It's okay to have hard days. Would you like to talk or try something calming?"
    }

    // Single low mood
    if let mood = mood, mood <= 2 {
        return "We're here for you. Take it one moment at a time."
    }

    // Declining trend
    if trend == "declining" {
        return "We noticed things might feel heavier lately. Small steps count."
    }

    // High mood
    if let mood = mood, mood >= 4 {
        return "You're radiating positivity today! 🌟"
    }

    return nil
}

private func getRecommendedExercises(mood: Int?, timeOfDay: TimeOfDay) async throws -> [UUID] {
    var typeFilter: [String] = []

    // Mood-based filtering
    if let mood = mood, mood <= 2 {
        typeFilter = ["breathing", "grounding", "meditation"]
    } else if let mood = mood, mood >= 4 {
        typeFilter = ["movement", "journaling", "meditation"]
    }

    // Time-based filtering
    switch timeOfDay {
    case .morning:
        typeFilter = typeFilter.isEmpty ? ["movement", "breathing"] : typeFilter
    case .evening, .night:
        typeFilter = typeFilter.isEmpty ? ["meditation", "breathing", "grounding"] : typeFilter
    default:
        break
    }

    let exercises: [Exercise] = try await supabase
        .from("exercises")
        .select("id")
        .in("type", typeFilter.isEmpty ? ["breathing", "meditation", "grounding", "journaling", "movement"] : typeFilter)
        .limit(5)
        .execute()
        .value

    return exercises.map { $0.id }
}
```

**Updated HomeView**:

```swift
// AdaptiveHomeView.swift
struct AdaptiveHomeView: View {
    @EnvironmentObject var container: DependencyContainer
    @EnvironmentObject var appState: AppState

    @State private var homeContext: HomeContext?
    @State private var isLoading = true

    var moodContext: MoodContext? {
        homeContext?.moodContext
    }

    var backgroundColor: Color {
        switch moodContext {
        case .low: return Color.blue.opacity(0.05)
        case .high: return Color.green.opacity(0.05)
        default: return Color(.systemBackground)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Greeting with context
                ContextualGreeting(
                    timeOfDay: homeContext?.timeOfDay ?? .current,
                    userName: appState.currentUser?.displayName
                )

                // Supportive message (if any)
                if let message = homeContext?.supportiveMessage {
                    SupportiveMessageCard(
                        message: message,
                        moodContext: moodContext ?? .neutral,
                        showCrisisSupport: homeContext?.showCrisisSupport ?? false
                    )
                }

                // Mood check-in prompt (if not logged today)
                if homeContext?.todayMood == nil {
                    MoodPromptCard(timeOfDay: homeContext?.timeOfDay ?? .current)
                }

                // Quest card (always show)
                TodayQuestCard()

                // Contextual quick actions
                if let actions = homeContext?.recommendedActions, !actions.isEmpty {
                    ContextualActionsRow(actions: actions)
                }

                // Recommended exercises
                if let exerciseIds = homeContext?.recommendedExerciseIds, !exerciseIds.isEmpty {
                    RecommendedExercisesSection(exerciseIds: exerciseIds)
                }

                // Streak card
                StreakCard(streak: appState.currentStreak)

                // Standard quick actions
                StandardQuickActions()
            }
            .padding()
        }
        .background(backgroundColor)
        .task { await loadContext() }
        .refreshable { await loadContext() }
    }

    func loadContext() async {
        isLoading = true
        defer { isLoading = false }

        do {
            homeContext = try await container.supabaseDataService.getHomeContext()
        } catch {
            print("Failed to load home context: \(error)")
        }
    }
}

// ContextualGreeting.swift
struct ContextualGreeting: View {
    let timeOfDay: TimeOfDay
    let userName: String?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeOfDay.greeting + (userName.map { ", \($0)" } ?? ""))
                    .font(.title2.bold())

                Text(subtitleForTime)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Time-appropriate icon
            Image(systemName: iconForTime)
                .font(.title)
                .foregroundStyle(colorForTime)
        }
    }

    var subtitleForTime: String {
        switch timeOfDay {
        case .morning: return "Ready to start your day?"
        case .afternoon: return "How's your day going?"
        case .evening: return "Time to wind down"
        case .night: return "Rest well tonight"
        }
    }

    var iconForTime: String {
        switch timeOfDay {
        case .morning: return "sun.max.fill"
        case .afternoon: return "sun.min.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }

    var colorForTime: Color {
        switch timeOfDay {
        case .morning: return .yellow
        case .afternoon: return .orange
        case .evening: return .purple
        case .night: return .indigo
        }
    }
}

// SupportiveMessageCard.swift
struct SupportiveMessageCard: View {
    let message: String
    let moodContext: MoodContext
    let showCrisisSupport: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: moodContext == .high ? "sparkles" : "heart.fill")
                    .foregroundStyle(moodContext.colorScheme)

                Text(message)
                    .font(.subheadline)
            }

            if showCrisisSupport {
                NavigationLink {
                    CrisisResourcesView()
                } label: {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                        Text("Need extra support?")
                            .font(.caption)
                    }
                    .foregroundStyle(.blue)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(moodContext.colorScheme.opacity(0.1))
        .cornerRadius(12)
    }
}

// ContextualActionsRow.swift
struct ContextualActionsRow: View {
    let actions: [HomeContext.RecommendedAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested for you")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(actions.prefix(3), id: \.type) { action in
                    ContextualActionButton(action: action)
                }
            }
        }
    }
}

struct ContextualActionButton: View {
    let action: HomeContext.RecommendedAction

    var body: some View {
        NavigationLink {
            destinationView
        } label: {
            VStack(spacing: 8) {
                Image(systemName: action.icon)
                    .font(.title2)
                    .foregroundStyle(.accentColor)

                Text(action.title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    @ViewBuilder
    var destinationView: some View {
        switch action.type {
        case .exercise, .breathing:
            ExerciseLibraryView()
        case .chat:
            ChatListView()
        case .circle:
            CirclesListView()
        case .quest:
            QuestChoiceView()
        case .journal:
            ExerciseLibraryView() // Filter to journaling
        case .celebrate, .share:
            CirclesListView() // Check-in
        }
    }
}
```

---

## UI/UX

### Low Mood Home Screen

```
┌─────────────────────────────────────────┐
│                               [🆘]      │
│ Good morning, Sarah            ☀️       │
│ Ready to start your day?               │
├─────────────────────────────────────────┤
│  ┌─────────────────────────────────┐   │
│  │ 💙 We're here for you. Take it  │   │
│  │ one moment at a time.            │   │
│  │                                  │   │
│  │ 🤚 Need extra support?           │   │
│  └─────────────────────────────────┘   │
│                                         │
│  SUGGESTED FOR YOU                      │
│  ┌───────┐ ┌───────┐ ┌───────┐        │
│  │  💬   │ │  🌬️  │ │  ❤️   │        │
│  │Talk to│ │ Calm  │ │ Reach │        │
│  │  AI   │ │Breath │ │  Out  │        │
│  └───────┘ └───────┘ └───────┘        │
│                                         │
│  [Today's Quest - Gentle option]        │
│                                         │
│  [Recommended: Grounding Exercises]     │
│                                         │
└─────────────────────────────────────────┘
```

### High Mood Home Screen

```
┌─────────────────────────────────────────┐
│ Good afternoon, Sarah          ☀️       │
│ How's your day going?                  │
├─────────────────────────────────────────┤
│  ┌─────────────────────────────────┐   │
│  │ ✨ You're radiating positivity  │   │
│  │ today! 🌟                       │   │
│  └─────────────────────────────────┘   │
│                                         │
│  SUGGESTED FOR YOU                      │
│  ┌───────┐ ┌───────┐ ┌───────┐        │
│  │  ❤️   │ │  ⭐   │ │  ✨   │        │
│  │Share  │ │ Try a │ │Explore│        │
│  │ Joy   │ │Chall. │ │ New   │        │
│  └───────┘ └───────┘ └───────┘        │
│                                         │
│  [Today's Quest - Challenge option]     │
│                                         │
│  [🔥 7 Day Streak - Share it!]          │
│                                         │
└─────────────────────────────────────────┘
```

---

## Verification

### Manual Testing

1. **Mood-Based Adaptation:**
   - Log mood of 2 (low)
   - Verify supportive message appears
   - Verify suggested actions are calming-focused
   - Verify crisis support link visible

2. **Time-Based Adaptation:**
   - Open app at different times
   - Verify greeting matches time
   - Verify suggested activities match time

3. **Consecutive Low Mood:**
   - Log low mood 3 days in a row
   - Verify stronger supportive message
   - Verify crisis resources more prominent

4. **High Mood Celebration:**
   - Log mood of 5
   - Verify celebratory messaging
   - Verify share/challenge suggestions

---

## Dependencies

- Mood logging working
- Exercise library populated
- Crisis resources feature
- Circle feature

---

## Risks & Mitigations

| Risk                              | Likelihood | Impact | Mitigation                               |
| --------------------------------- | ---------- | ------ | ---------------------------------------- |
| Over-personalization feels creepy | Medium     | Medium | Keep it subtle, transparent              |
| Wrong context detection           | Low        | Medium | Always show standard actions as fallback |
| Crisis detection false positives  | Low        | High   | Don't be alarmist, gentle prompts only   |

---

## Implementation Estimate

| Task                   | Effort       |
| ---------------------- | ------------ |
| Database migration     | 1 hour       |
| iOS Models             | 1 hour       |
| Context calculation    | 3 hours      |
| Adaptive UI components | 5 hours      |
| Supportive messaging   | 2 hours      |
| Testing                | 2 hours      |
| **Total**              | **14 hours** |

---

## Success Metrics

| Metric                                | Current | Target |
| ------------------------------------- | ------- | ------ |
| Home screen engagement time           | Measure | +20%   |
| Exercise completion from home         | Measure | +30%   |
| Crisis resources access (when needed) | Measure | +50%   |
| User satisfaction (contextual)        | N/A     | >4.2/5 |
