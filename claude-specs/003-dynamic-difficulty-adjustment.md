# F005: Dynamic Difficulty Adjustment

> **Feature ID:** F005
> **Phase:** 1 - Foundation
> **Priority:** P1 (High)
> **Dependencies:** None
> **Dependents:** F014, F015

---

## 1. Overview

### 1.1 Summary

Dynamic Difficulty Adjustment (DDA) automatically tailors quest difficulty, exercise length, coaching intensity, and challenge level based on the user's current capacity, historical performance, and real-time signals. This prevents burnout during low-energy periods while introducing appropriate challenges during high-capacity periods.

### 1.2 Business Value

- **User Value:** Experience that adapts to how they're actually feeling—lighter on hard days, engaging on good days
- **Product Value:** Reduces churn from overwhelming/underwhelming experiences
- **Competitive Value:** Most wellness apps have fixed difficulty; adaptive difficulty feels personalized

### 1.3 User Benefit

Users receive appropriately-sized wellness activities that match their current energy and capacity, making the app usable every day regardless of how they're feeling.

---

## 2. Requirements

### 2.1 Functional Requirements

| ID     | Requirement                                                                                       | Priority |
| ------ | ------------------------------------------------------------------------------------------------- | -------- |
| FR-001 | Calculate user capacity score (0-100) from recent mood, sleep, streak status, and completion rate | Must     |
| FR-002 | Adjust quest difficulty and duration based on capacity score                                      | Must     |
| FR-003 | Adjust exercise recommendations (suggest shorter exercises on low-capacity days)                  | Must     |
| FR-004 | Adjust AI coaching intensity (more gentle on low days, more challenging on high days)             | Should   |
| FR-005 | Display capacity indicator to user ("Taking it easy today" / "Ready for a challenge")             | Should   |
| FR-006 | Allow manual override ("I want an easier day" / "Challenge me today")                             | Must     |
| FR-007 | Learn optimal difficulty from completion rates and user feedback                                  | Should   |
| FR-008 | Prevent difficulty from changing too rapidly (smoothing)                                          | Must     |
| FR-009 | Apply difficulty to quest arc progression                                                         | Should   |

### 2.2 Non-Functional Requirements

| ID      | Requirement                    | Target                            |
| ------- | ------------------------------ | --------------------------------- |
| NFR-001 | Capacity calculation latency   | < 100ms                           |
| NFR-002 | Difficulty adjustment accuracy | > 80% appropriate (user feedback) |
| NFR-003 | Override latency               | Immediate effect                  |

### 2.3 Acceptance Criteria

1. **AC-001:** User who slept poorly and logged low mood sees "Light day" quest (5 min vs 15 min)
2. **AC-002:** User on 30-day streak with high mood sees "Challenge quest" option
3. **AC-003:** User can tap "Take it easy" to reduce today's difficulty
4. **AC-004:** User can tap "Challenge me" to increase today's difficulty
5. **AC-005:** Difficulty changes smoothly over days, not jumping between extremes

---

## 3. Technical Design

### 3.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                          iOS App                                 │
├─────────────────────────────────────────────────────────────────┤
│  DifficultyService                                              │
│  ├─ calculateCapacity()                                         │
│  ├─ getDifficultyLevel()                                        │
│  ├─ applyOverride(level:)                                       │
│  └─ resetOverride()                                             │
│                                                                  │
│  Integration Points:                                             │
│  ├─ QuestService (filter/select quests)                         │
│  ├─ ExerciseService (recommend exercises)                       │
│  └─ ChatService (adjust coaching prompts)                       │
├─────────────────────────────────────────────────────────────────┤
│                        Supabase                                  │
├─────────────────────────────────────────────────────────────────┤
│  Tables:                      Edge Functions:                    │
│  ├─ user_capacity             ├─ calculate-capacity             │
│  └─ difficulty_overrides      └─ get-difficulty-adjusted-content │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Data Models

#### 3.2.1 Database Schema

```sql
-- User capacity tracking
CREATE TABLE user_capacity (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Current capacity score
    capacity_score INT NOT NULL DEFAULT 50 CHECK (capacity_score BETWEEN 0 AND 100),
    capacity_level VARCHAR(16) NOT NULL DEFAULT 'normal', -- 'low', 'normal', 'high'

    -- Component scores
    mood_component INT CHECK (mood_component BETWEEN 0 AND 100),
    sleep_component INT CHECK (sleep_component BETWEEN 0 AND 100),
    streak_component INT CHECK (streak_component BETWEEN 0 AND 100),
    completion_component INT CHECK (completion_component BETWEEN 0 AND 100),

    -- Smoothing
    previous_capacity_score INT,
    smoothing_factor DECIMAL(3,2) NOT NULL DEFAULT 0.3, -- How much today's raw score influences final

    -- Metadata
    last_calculated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    calculation_inputs JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Manual overrides
CREATE TABLE difficulty_overrides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    local_date DATE NOT NULL,

    override_type VARCHAR(16) NOT NULL, -- 'easier', 'harder', 'specific_level'
    target_level VARCHAR(16), -- 'low', 'normal', 'high' if specific
    reason TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(user_id, local_date)
);

-- Quest difficulty mapping
CREATE TABLE quest_difficulty_mapping (
    quest_template_id UUID NOT NULL REFERENCES quest_templates(id),
    difficulty_level VARCHAR(16) NOT NULL, -- 'low', 'normal', 'high'

    duration_minutes INT NOT NULL,
    intensity VARCHAR(16) NOT NULL, -- 'gentle', 'moderate', 'challenging'
    modifications JSONB, -- Specific changes for this difficulty

    PRIMARY KEY (quest_template_id, difficulty_level)
);

-- RLS Policies
ALTER TABLE user_capacity ENABLE ROW LEVEL SECURITY;
ALTER TABLE difficulty_overrides ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own capacity"
    ON user_capacity FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own overrides"
    ON difficulty_overrides FOR ALL
    USING (auth.uid() = user_id);
```

#### 3.2.2 Swift Models

```swift
// DifficultyModels.swift

import Foundation

// MARK: - Capacity Level

enum CapacityLevel: String, Codable, CaseIterable {
    case low = "low"
    case normal = "normal"
    case high = "high"

    var displayName: String {
        switch self {
        case .low: return "Taking it easy"
        case .normal: return "Balanced"
        case .high: return "Ready for a challenge"
        }
    }

    var icon: String {
        switch self {
        case .low: return "leaf"
        case .normal: return "circle.grid.2x2"
        case .high: return "flame"
        }
    }

    var color: Color {
        switch self {
        case .low: return .blue
        case .normal: return .green
        case .high: return .orange
        }
    }

    static func from(score: Int) -> CapacityLevel {
        switch score {
        case 0..<35: return .low
        case 35..<70: return .normal
        default: return .high
        }
    }
}

// MARK: - User Capacity

struct UserCapacity: Codable {
    let userId: UUID
    let capacityScore: Int
    let capacityLevel: CapacityLevel

    let moodComponent: Int?
    let sleepComponent: Int?
    let streakComponent: Int?
    let completionComponent: Int?

    let previousCapacityScore: Int?
    let lastCalculatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case capacityScore = "capacity_score"
        case capacityLevel = "capacity_level"
        case moodComponent = "mood_component"
        case sleepComponent = "sleep_component"
        case streakComponent = "streak_component"
        case completionComponent = "completion_component"
        case previousCapacityScore = "previous_capacity_score"
        case lastCalculatedAt = "last_calculated_at"
    }

    var componentBreakdown: [CapacityComponent] {
        var components: [CapacityComponent] = []

        if let mood = moodComponent {
            components.append(CapacityComponent(type: .mood, score: mood, weight: 0.35))
        }
        if let sleep = sleepComponent {
            components.append(CapacityComponent(type: .sleep, score: sleep, weight: 0.30))
        }
        if let streak = streakComponent {
            components.append(CapacityComponent(type: .streak, score: streak, weight: 0.20))
        }
        if let completion = completionComponent {
            components.append(CapacityComponent(type: .completion, score: completion, weight: 0.15))
        }

        return components
    }
}

struct CapacityComponent: Identifiable {
    var id: ComponentType { type }

    let type: ComponentType
    let score: Int
    let weight: Double

    var weightedScore: Int {
        Int(Double(score) * weight)
    }

    enum ComponentType: String {
        case mood
        case sleep
        case streak
        case completion

        var displayName: String {
            switch self {
            case .mood: return "Current Mood"
            case .sleep: return "Recent Sleep"
            case .streak: return "Streak Momentum"
            case .completion: return "Completion Rate"
            }
        }

        var icon: String {
            switch self {
            case .mood: return "face.smiling"
            case .sleep: return "moon.zzz"
            case .streak: return "flame"
            case .completion: return "checkmark.circle"
            }
        }
    }
}

// MARK: - Difficulty Override

struct DifficultyOverride: Codable {
    let id: UUID
    let userId: UUID
    let localDate: Date
    let overrideType: OverrideType
    let targetLevel: CapacityLevel?
    let reason: String?

    enum OverrideType: String, Codable {
        case easier
        case harder
        case specificLevel = "specific_level"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case localDate = "local_date"
        case overrideType = "override_type"
        case targetLevel = "target_level"
        case reason
    }
}

// MARK: - Difficulty-Adjusted Content

struct DifficultyAdjustedQuest {
    let baseQuest: Quest
    let adjustedDuration: Int
    let adjustedIntensity: String
    let modifications: [String]
}

struct DifficultyAdjustedExercise {
    let exercise: Exercise
    let isRecommended: Bool
    let recommendationReason: String?
}
```

### 3.3 Capacity Calculation Algorithm

```typescript
// calculate-capacity.ts

interface CapacityInputs {
  // Mood (weight: 35%)
  todayMood?: number; // 1-10
  moodTrend3d?: number; // Slope of last 3 days

  // Sleep (weight: 30%)
  lastNightSleep?: number; // hours
  sleepQuality?: number; // 0-100
  sleepDeficit7d?: number; // Cumulative hours below 7

  // Streak (weight: 20%)
  streakDays?: number;
  questCompletedToday?: boolean;

  // Completion rate (weight: 15%)
  completionRate7d?: number; // 0-1
  skipsRecent?: number; // Skips in last 7 days
}

interface CapacityResult {
  capacityScore: number; // 0-100
  capacityLevel: "low" | "normal" | "high";
  components: {
    mood: number;
    sleep: number;
    streak: number;
    completion: number;
  };
}

function calculateCapacity(
  inputs: CapacityInputs,
  previousScore?: number,
  smoothingFactor: number = 0.3,
): CapacityResult {
  const weights = {
    mood: 0.35,
    sleep: 0.3,
    streak: 0.2,
    completion: 0.15,
  };

  // Mood component (0-100)
  let moodScore = 50; // Default
  if (inputs.todayMood !== undefined) {
    moodScore = (inputs.todayMood / 10) * 100;

    // Adjust for trend
    if (inputs.moodTrend3d !== undefined) {
      moodScore += inputs.moodTrend3d * 10; // Positive trend adds points
    }
  }
  moodScore = clamp(moodScore, 0, 100);

  // Sleep component (0-100)
  let sleepScore = 50;
  if (inputs.lastNightSleep !== undefined) {
    // Optimal: 7-9 hours
    if (inputs.lastNightSleep >= 7 && inputs.lastNightSleep <= 9) {
      sleepScore = 100;
    } else if (inputs.lastNightSleep >= 6) {
      sleepScore = 70;
    } else if (inputs.lastNightSleep >= 5) {
      sleepScore = 40;
    } else {
      sleepScore = 20;
    }

    // Factor in quality if available
    if (inputs.sleepQuality !== undefined) {
      sleepScore = (sleepScore + inputs.sleepQuality) / 2;
    }

    // Penalize for accumulated deficit
    if (inputs.sleepDeficit7d !== undefined && inputs.sleepDeficit7d > 0) {
      sleepScore -= Math.min(20, inputs.sleepDeficit7d * 2);
    }
  }
  sleepScore = clamp(sleepScore, 0, 100);

  // Streak component (0-100)
  let streakScore = 50;
  if (inputs.streakDays !== undefined) {
    // Logarithmic growth, max around 30 days
    streakScore = Math.min(100, 30 + Math.log2(inputs.streakDays + 1) * 15);

    // Boost if already completed today
    if (inputs.questCompletedToday) {
      streakScore = Math.min(100, streakScore + 15);
    }
  }

  // Completion component (0-100)
  let completionScore = 50;
  if (inputs.completionRate7d !== undefined) {
    completionScore = inputs.completionRate7d * 100;

    // Penalize for recent skips
    if (inputs.skipsRecent !== undefined && inputs.skipsRecent > 0) {
      completionScore -= inputs.skipsRecent * 10;
    }
  }
  completionScore = clamp(completionScore, 0, 100);

  // Calculate raw weighted score
  const rawScore = Math.round(
    moodScore * weights.mood +
      sleepScore * weights.sleep +
      streakScore * weights.streak +
      completionScore * weights.completion,
  );

  // Apply smoothing if we have previous score
  let finalScore = rawScore;
  if (previousScore !== undefined) {
    finalScore = Math.round(
      previousScore * (1 - smoothingFactor) + rawScore * smoothingFactor,
    );
  }

  // Determine level
  let capacityLevel: "low" | "normal" | "high";
  if (finalScore < 35) {
    capacityLevel = "low";
  } else if (finalScore < 70) {
    capacityLevel = "normal";
  } else {
    capacityLevel = "high";
  }

  return {
    capacityScore: finalScore,
    capacityLevel,
    components: {
      mood: Math.round(moodScore),
      sleep: Math.round(sleepScore),
      streak: Math.round(streakScore),
      completion: Math.round(completionScore),
    },
  };
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}
```

### 3.4 Difficulty Application

```swift
// DifficultyService.swift

@MainActor
final class DifficultyService: ObservableObject {
    @Published private(set) var currentCapacity: UserCapacity?
    @Published private(set) var activeOverride: DifficultyOverride?

    private let supabase: SupabaseClient
    private let moodService: MoodService
    private let biometricService: BiometricSyncService
    private let questService: QuestService

    var effectiveLevel: CapacityLevel {
        if let override = activeOverride {
            switch override.overrideType {
            case .easier:
                return currentCapacity?.capacityLevel.lower ?? .low
            case .harder:
                return currentCapacity?.capacityLevel.higher ?? .high
            case .specificLevel:
                return override.targetLevel ?? .normal
            }
        }
        return currentCapacity?.capacityLevel ?? .normal
    }

    func calculateCapacity() async throws {
        // Gather inputs
        let todayMood = await moodService.getTodayMood()?.moodScore
        let sleepData = await biometricService.getLastNightSleep()
        let streakDays = await questService.getCurrentStreak()
        let completionRate = await questService.getCompletionRate(days: 7)

        // Call edge function
        let result: UserCapacity = try await supabase.functions
            .invoke("calculate-capacity", options: .init(body: [
                "today_mood": todayMood,
                "sleep_hours": sleepData?.durationHours,
                "sleep_quality": sleepData?.qualityScore,
                "streak_days": streakDays,
                "completion_rate": completionRate
            ]))
            .value

        currentCapacity = result
    }

    func applyEasierOverride(reason: String? = nil) async throws {
        let override = DifficultyOverride(
            id: UUID(),
            userId: currentUserId,
            localDate: Date(),
            overrideType: .easier,
            targetLevel: nil,
            reason: reason
        )

        try await saveOverride(override)
        activeOverride = override
    }

    func applyHarderOverride(reason: String? = nil) async throws {
        let override = DifficultyOverride(
            id: UUID(),
            userId: currentUserId,
            localDate: Date(),
            overrideType: .harder,
            targetLevel: nil,
            reason: reason
        )

        try await saveOverride(override)
        activeOverride = override
    }

    func clearOverride() async throws {
        guard let override = activeOverride else { return }

        try await supabase.from("difficulty_overrides")
            .delete()
            .eq("id", value: override.id)
            .execute()

        activeOverride = nil
    }

    // Quest difficulty adjustment
    func adjustQuest(_ quest: Quest) -> DifficultyAdjustedQuest {
        let level = effectiveLevel

        var adjustedDuration = quest.template.estimatedMinutes
        var adjustedIntensity = "moderate"
        var modifications: [String] = []

        switch level {
        case .low:
            adjustedDuration = max(3, Int(Double(adjustedDuration) * 0.5))
            adjustedIntensity = "gentle"
            modifications = ["Shortened version", "Focus on completion over perfection"]

        case .normal:
            // No changes
            break

        case .high:
            adjustedDuration = Int(Double(adjustedDuration) * 1.25)
            adjustedIntensity = "challenging"
            modifications = ["Extended version", "Added reflection prompts"]
        }

        return DifficultyAdjustedQuest(
            baseQuest: quest,
            adjustedDuration: adjustedDuration,
            adjustedIntensity: adjustedIntensity,
            modifications: modifications
        )
    }

    // Exercise recommendations
    func getRecommendedExercises(from exercises: [Exercise]) -> [DifficultyAdjustedExercise] {
        let level = effectiveLevel

        return exercises.map { exercise in
            var isRecommended = false
            var reason: String?

            switch level {
            case .low:
                // Recommend short, calming exercises
                if exercise.durationMinutes <= 5 &&
                   (exercise.type == .breathing || exercise.type == .grounding) {
                    isRecommended = true
                    reason = "Quick and calming for a low-energy day"
                }

            case .normal:
                // Recommend moderate exercises
                if exercise.durationMinutes <= 15 {
                    isRecommended = true
                }

            case .high:
                // Recommend challenging exercises
                if exercise.difficulty == .advanced ||
                   exercise.durationMinutes >= 15 {
                    isRecommended = true
                    reason = "Ready for a deeper practice"
                }
            }

            return DifficultyAdjustedExercise(
                exercise: exercise,
                isRecommended: isRecommended,
                recommendationReason: reason
            )
        }
    }
}

extension CapacityLevel {
    var lower: CapacityLevel {
        switch self {
        case .high: return .normal
        case .normal: return .low
        case .low: return .low
        }
    }

    var higher: CapacityLevel {
        switch self {
        case .low: return .normal
        case .normal: return .high
        case .high: return .high
        }
    }
}
```

---

## 4. Implementation Details

### 4.1 Step-by-Step Implementation

#### Step 1: Database Schema

1. Create migration for `user_capacity` table
2. Create migration for `difficulty_overrides` table
3. Create migration for `quest_difficulty_mapping` table
4. Add RLS policies

#### Step 2: Capacity Calculation

1. Implement `calculate-capacity` edge function
2. Create capacity calculation algorithm
3. Add smoothing logic

#### Step 3: iOS Service Layer

1. Create `DifficultyService`
2. Implement capacity calculation trigger
3. Add override management
4. Create difficulty adjustment methods

#### Step 4: Integration

1. Modify `QuestService` to use difficulty adjustment
2. Modify `ExerciseService` to filter/rank by difficulty
3. Modify chat prompts to include difficulty context

#### Step 5: iOS UI

1. Create capacity indicator widget
2. Add override buttons ("Take it easy" / "Challenge me")
3. Show adjusted quest/exercise info

### 4.2 File Structure

```
apps/ios/MindFriendApp/
├── Core/
│   ├── Models/
│   │   └── DifficultyModels.swift
│   └── Services/
│       └── DifficultyService.swift
├── Features/
│   └── Difficulty/
│       ├── Views/
│       │   ├── CapacityIndicatorView.swift
│       │   └── DifficultyOverrideSheet.swift
│       └── ViewModels/
│           └── DifficultyViewModel.swift

supabase/
├── functions/
│   ├── calculate-capacity/
│   │   └── index.ts
│   └── get-difficulty-adjusted-content/
│       └── index.ts
└── migrations/
    └── 20260122000005_difficulty_adjustment.sql
```

---

## 5. Dependencies

### 5.1 Prerequisites

- None (uses existing mood, biometric, quest data)

### 5.2 Internal Modules

| Module                 | Purpose                    |
| ---------------------- | -------------------------- |
| `MoodService`          | Current mood data          |
| `BiometricSyncService` | Sleep data                 |
| `QuestService`         | Streak and completion data |

---

## 6. Edge Cases and Error Handling

### 6.1 Edge Cases

| Scenario                      | Expected Behavior                         |
| ----------------------------- | ----------------------------------------- |
| No data available             | Default to normal capacity (50)           |
| User always overrides to easy | Track pattern, don't judge                |
| Capacity changes mid-day      | Apply smoothing, don't change drastically |
| Multiple overrides same day   | Keep most recent                          |
| Very new user (<3 days)       | Use default normal, build over time       |

---

## 7. Testing Requirements

### 7.1 Unit Test Scenarios

| Test Case            | Input                             | Expected Output          |
| -------------------- | --------------------------------- | ------------------------ |
| Low capacity         | mood=3, sleep=4h, streak=0        | Capacity <35, level=low  |
| High capacity        | mood=9, sleep=8h, streak=30       | Capacity >70, level=high |
| Smoothing            | Previous=70, raw=30               | Final ~58 (not 30)       |
| Override easier      | Normal capacity + easier override | Effective level = low    |
| Quest adjustment low | 15min quest, low capacity         | Adjusted to ~7min        |
