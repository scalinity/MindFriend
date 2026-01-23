# F002: Daily Wellness Score

> **Feature ID:** F002
> **Phase:** 1 - Foundation
> **Priority:** P0 (Critical)
> **Dependencies:** F001 (Biometric Correlation Engine)
> **Dependents:** F009, F021

---

## 1. Overview

### 1.1 Summary

The Daily Wellness Score synthesizes multiple data sources (mood, sleep, activity, streaks, exercise completion) into a single 1-100 score that represents the user's overall wellness for the day. This score is prominently displayed on the home screen and widgets, gamifying holistic wellness without requiring manual calculation by the user.

### 1.2 Business Value

- **User Value:** Single glanceable metric that answers "How am I doing overall?"
- **Product Value:** Creates a primary engagement hook and daily ritual
- **Competitive Value:** Most apps track metrics in silos; this creates a unified wellness identity

### 1.3 User Benefit

Users can quickly assess their wellness trajectory without analyzing multiple metrics, enabling faster insight-to-action and creating a satisfying daily progress loop.

---

## 2. Requirements

### 2.1 Functional Requirements

| ID     | Requirement                                                                                            | Priority |
| ------ | ------------------------------------------------------------------------------------------------------ | -------- |
| FR-001 | Calculate wellness score from: mood (30%), sleep (25%), activity (20%), streaks (15%), exercises (10%) | Must     |
| FR-002 | Update score in real-time as contributing factors change throughout the day                            | Must     |
| FR-003 | Display score on home screen with visual ring/gauge indicator                                          | Must     |
| FR-004 | Show score breakdown when tapped (which factors contributed what)                                      | Must     |
| FR-005 | Display 7-day trend sparkline beneath score                                                            | Must     |
| FR-006 | Show score delta from yesterday ("+5 from yesterday")                                                  | Must     |
| FR-007 | Generate contextual message based on score ("Great day!" / "You're building momentum")                 | Should   |
| FR-008 | Store historical scores for trend analysis                                                             | Must     |
| FR-009 | Provide score via WidgetKit for home screen widget                                                     | Must     |
| FR-010 | Calculate partial score when some data is missing (with reduced confidence)                            | Must     |
| FR-011 | Allow users to see projected score impact of actions ("Complete quest for +8 points")                  | Should   |

### 2.2 Non-Functional Requirements

| ID      | Requirement               | Target                                     |
| ------- | ------------------------- | ------------------------------------------ |
| NFR-001 | Score calculation latency | < 200ms                                    |
| NFR-002 | Score update frequency    | Within 5 seconds of data change            |
| NFR-003 | Widget refresh frequency  | Every 15 minutes or on significant change  |
| NFR-004 | Score precision           | Whole numbers only (no decimals displayed) |

### 2.3 Acceptance Criteria

1. **AC-001:** User sees wellness score (1-100) on home screen immediately upon app open
2. **AC-002:** Score updates visibly within 5 seconds of logging mood
3. **AC-003:** User can tap score to see breakdown showing each factor's contribution
4. **AC-004:** 7-day trend shows previous scores with current day highlighted
5. **AC-005:** Widget displays current score and updates every 15 minutes
6. **AC-006:** Score of 0-39 shows red ring, 40-69 shows yellow, 70-100 shows green

---

## 3. Technical Design

### 3.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                          iOS App                                 │
├─────────────────────────────────────────────────────────────────┤
│  WellnessScoreService                                           │
│  ├─ calculateScore()                                            │
│  ├─ getBreakdown()                                              │
│  ├─ getHistory(days:)                                           │
│  └─ getProjectedImpact(action:)                                 │
│                                                                  │
│  WellnessScoreViewModel                                         │
│  ├─ @Published score: Int                                       │
│  ├─ @Published breakdown: ScoreBreakdown                        │
│  └─ @Published trend: [DailyScore]                              │
├─────────────────────────────────────────────────────────────────┤
│  Views:                              Widget:                     │
│  ├─ WellnessScoreCard               ├─ WellnessScoreWidget      │
│  ├─ WellnessScoreRing               └─ WellnessScoreProvider    │
│  ├─ ScoreBreakdownSheet                                         │
│  └─ ScoreTrendChart                                             │
├─────────────────────────────────────────────────────────────────┤
│                        Supabase                                  │
├─────────────────────────────────────────────────────────────────┤
│  Tables:                   Edge Functions:                       │
│  └─ wellness_scores        └─ calculate-wellness-score          │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Data Models

#### 3.2.1 Database Schema

```sql
-- Daily wellness scores
CREATE TABLE wellness_scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    local_date DATE NOT NULL,

    -- Overall score
    score INT NOT NULL CHECK (score BETWEEN 0 AND 100),
    confidence DECIMAL(3,2) NOT NULL DEFAULT 1.0, -- 0.0 to 1.0, based on data completeness

    -- Component scores (0-100 each, before weighting)
    mood_score INT CHECK (mood_score BETWEEN 0 AND 100),
    sleep_score INT CHECK (sleep_score BETWEEN 0 AND 100),
    activity_score INT CHECK (activity_score BETWEEN 0 AND 100),
    streak_score INT CHECK (streak_score BETWEEN 0 AND 100),
    exercise_score INT CHECK (exercise_score BETWEEN 0 AND 100),

    -- Raw inputs used for calculation
    inputs JSONB NOT NULL DEFAULT '{}',
    -- Example: {
    --   "mood_value": 7,
    --   "sleep_hours": 7.5,
    --   "steps": 8000,
    --   "streak_days": 5,
    --   "exercises_completed": 1
    -- }

    -- Metadata
    calculated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    version INT NOT NULL DEFAULT 1, -- Algorithm version for migrations

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(user_id, local_date)
);

-- Indexes
CREATE INDEX idx_wellness_scores_user_date ON wellness_scores(user_id, local_date DESC);
CREATE INDEX idx_wellness_scores_score ON wellness_scores(user_id, score);

-- RLS Policies
ALTER TABLE wellness_scores ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own wellness scores"
    ON wellness_scores FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Service can insert/update wellness scores"
    ON wellness_scores FOR ALL
    USING (auth.uid() = user_id);
```

#### 3.2.2 Swift Models

```swift
// WellnessScoreModels.swift

import Foundation

// MARK: - Wellness Score

struct WellnessScore: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let localDate: Date
    let score: Int
    let confidence: Double

    // Component scores
    let moodScore: Int?
    let sleepScore: Int?
    let activityScore: Int?
    let streakScore: Int?
    let exerciseScore: Int?

    let inputs: ScoreInputs
    let calculatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case localDate = "local_date"
        case score, confidence
        case moodScore = "mood_score"
        case sleepScore = "sleep_score"
        case activityScore = "activity_score"
        case streakScore = "streak_score"
        case exerciseScore = "exercise_score"
        case inputs
        case calculatedAt = "calculated_at"
    }

    var colorZone: ScoreColorZone {
        switch score {
        case 0..<40: return .low
        case 40..<70: return .medium
        default: return .high
        }
    }
}

enum ScoreColorZone {
    case low    // 0-39, red
    case medium // 40-69, yellow
    case high   // 70-100, green

    var color: Color {
        switch self {
        case .low: return .red
        case .medium: return .yellow
        case .high: return .green
        }
    }

    var label: String {
        switch self {
        case .low: return "Needs attention"
        case .medium: return "Building momentum"
        case .high: return "Great day!"
        }
    }
}

// MARK: - Score Inputs

struct ScoreInputs: Codable {
    let moodValue: Int?          // 1-10
    let sleepHours: Double?      // 0-24
    let sleepQuality: Int?       // 0-100
    let steps: Int?              // 0+
    let workoutMinutes: Int?     // 0+
    let streakDays: Int?         // 0+
    let exercisesCompleted: Int? // 0+

    enum CodingKeys: String, CodingKey {
        case moodValue = "mood_value"
        case sleepHours = "sleep_hours"
        case sleepQuality = "sleep_quality"
        case steps
        case workoutMinutes = "workout_minutes"
        case streakDays = "streak_days"
        case exercisesCompleted = "exercises_completed"
    }
}

// MARK: - Score Breakdown

struct ScoreBreakdown {
    let components: [ScoreComponent]
    let totalScore: Int
    let confidence: Double

    struct ScoreComponent {
        let type: ComponentType
        let rawScore: Int      // 0-100 before weighting
        let weightedScore: Int // After applying weight
        let weight: Double     // 0.0 to 1.0
        let hasData: Bool
        let improvementTip: String?
    }

    enum ComponentType: String, CaseIterable {
        case mood = "Mood"
        case sleep = "Sleep"
        case activity = "Activity"
        case streak = "Streak"
        case exercise = "Exercise"

        var icon: String {
            switch self {
            case .mood: return "face.smiling"
            case .sleep: return "moon.zzz"
            case .activity: return "figure.walk"
            case .streak: return "flame"
            case .exercise: return "heart.circle"
            }
        }

        var weight: Double {
            switch self {
            case .mood: return 0.30
            case .sleep: return 0.25
            case .activity: return 0.20
            case .streak: return 0.15
            case .exercise: return 0.10
            }
        }
    }
}

// MARK: - Daily Score (for history)

struct DailyScore: Codable, Identifiable {
    var id: Date { localDate }
    let localDate: Date
    let score: Int
    let delta: Int? // Change from previous day

    enum CodingKeys: String, CodingKey {
        case localDate = "local_date"
        case score
        case delta
    }
}

// MARK: - Score Projection

struct ScoreProjection {
    let action: ProjectedAction
    let currentScore: Int
    let projectedScore: Int
    let delta: Int

    var displayText: String {
        let sign = delta >= 0 ? "+" : ""
        return "\(action.label) for \(sign)\(delta) points"
    }
}

enum ProjectedAction {
    case completeQuest
    case logMood
    case completeExercise
    case getSleep(hours: Double)

    var label: String {
        switch self {
        case .completeQuest: return "Complete quest"
        case .logMood: return "Log mood"
        case .completeExercise: return "Complete exercise"
        case .getSleep(let hours): return "Get \(Int(hours))h sleep"
        }
    }
}

// MARK: - Widget Data

struct WellnessScoreWidgetData: Codable {
    let score: Int
    let colorZone: String
    let delta: Int?
    let lastUpdated: Date
    let trend: [Int] // Last 7 scores
}
```

### 3.3 API Contracts

#### 3.3.1 Edge Function: `calculate-wellness-score`

**Endpoint:** `POST /functions/v1/calculate-wellness-score`

**Request:**

```json
{
  "local_date": "2026-01-22",
  "timezone": "America/New_York",
  "force_recalculate": false
}
```

**Response (200):**

```json
{
  "score": 73,
  "confidence": 0.92,
  "components": {
    "mood": {
      "raw_score": 80,
      "weighted_score": 24,
      "weight": 0.3,
      "has_data": true,
      "input": 8
    },
    "sleep": {
      "raw_score": 78,
      "weighted_score": 19,
      "weight": 0.25,
      "has_data": true,
      "input": 7.5
    },
    "activity": {
      "raw_score": 65,
      "weighted_score": 13,
      "weight": 0.2,
      "has_data": true,
      "input": 8000
    },
    "streak": {
      "raw_score": 70,
      "weighted_score": 10,
      "weight": 0.15,
      "has_data": true,
      "input": 5
    },
    "exercise": {
      "raw_score": 70,
      "weighted_score": 7,
      "weight": 0.1,
      "has_data": true,
      "input": 1
    }
  },
  "delta_from_yesterday": 5,
  "trend": [68, 72, 65, 70, 71, 68, 73],
  "message": "Great progress! Your sleep and mood are driving today's score.",
  "improvement_tips": [
    {
      "component": "activity",
      "tip": "2000 more steps would add ~4 points"
    }
  ]
}
```

#### 3.3.2 Edge Function: `get-wellness-history`

**Endpoint:** `GET /functions/v1/get-wellness-history?days=30`

**Response (200):**

```json
{
  "scores": [
    {
      "local_date": "2026-01-22",
      "score": 73,
      "delta": 5
    },
    {
      "local_date": "2026-01-21",
      "score": 68,
      "delta": -4
    }
  ],
  "average_30_day": 69,
  "average_7_day": 70,
  "best_day": {
    "local_date": "2026-01-15",
    "score": 85
  },
  "trend_direction": "improving"
}
```

### 3.4 Score Calculation Algorithm

```typescript
// calculate-wellness-score.ts

interface ScoreWeights {
  mood: 0.3;
  sleep: 0.25;
  activity: 0.2;
  streak: 0.15;
  exercise: 0.1;
}

interface ScoreInputs {
  moodValue?: number; // 1-10
  sleepHours?: number; // 0-24
  sleepQuality?: number; // 0-100 (from biometrics)
  steps?: number; // 0+
  workoutMinutes?: number; // 0+
  streakDays?: number; // 0+
  questCompleted?: boolean;
  exercisesCompleted?: number; // 0+
}

function calculateWellnessScore(inputs: ScoreInputs): {
  score: number;
  confidence: number;
  components: Record<string, ComponentScore>;
} {
  const weights: ScoreWeights = {
    mood: 0.3,
    sleep: 0.25,
    activity: 0.2,
    streak: 0.15,
    exercise: 0.1,
  };

  const components: Record<string, ComponentScore> = {};
  let totalWeight = 0;
  let weightedSum = 0;
  let dataPoints = 0;

  // Mood Score (0-100)
  if (inputs.moodValue !== undefined) {
    const moodScore = Math.round((inputs.moodValue / 10) * 100);
    components.mood = {
      raw_score: moodScore,
      weighted_score: Math.round(moodScore * weights.mood),
      weight: weights.mood,
      has_data: true,
      input: inputs.moodValue,
    };
    weightedSum += moodScore * weights.mood;
    totalWeight += weights.mood;
    dataPoints++;
  } else {
    components.mood = {
      raw_score: 0,
      weighted_score: 0,
      weight: weights.mood,
      has_data: false,
      input: null,
    };
  }

  // Sleep Score (0-100)
  if (inputs.sleepHours !== undefined || inputs.sleepQuality !== undefined) {
    let sleepScore: number;

    if (inputs.sleepQuality !== undefined) {
      // Use biometric sleep quality if available
      sleepScore = inputs.sleepQuality;
    } else {
      // Calculate from hours only
      const hours = inputs.sleepHours!;
      if (hours >= 7 && hours <= 9) sleepScore = 100;
      else if (hours >= 6 && hours < 7) sleepScore = 70;
      else if (hours >= 9 && hours < 10) sleepScore = 80;
      else if (hours >= 5 && hours < 6) sleepScore = 50;
      else if (hours < 5) sleepScore = 30;
      else sleepScore = 60;
    }

    components.sleep = {
      raw_score: sleepScore,
      weighted_score: Math.round(sleepScore * weights.sleep),
      weight: weights.sleep,
      has_data: true,
      input: inputs.sleepHours ?? inputs.sleepQuality,
    };
    weightedSum += sleepScore * weights.sleep;
    totalWeight += weights.sleep;
    dataPoints++;
  } else {
    components.sleep = {
      raw_score: 0,
      weighted_score: 0,
      weight: weights.sleep,
      has_data: false,
      input: null,
    };
  }

  // Activity Score (0-100)
  if (inputs.steps !== undefined || inputs.workoutMinutes !== undefined) {
    let activityScore = 0;

    if (inputs.steps !== undefined) {
      // Steps: 10000 = 100, linear scaling
      activityScore += Math.min(100, (inputs.steps / 10000) * 70);
    }

    if (inputs.workoutMinutes !== undefined) {
      // Workout: 30 min = 30 points additional
      activityScore += Math.min(30, inputs.workoutMinutes);
    }

    activityScore = Math.min(100, Math.round(activityScore));

    components.activity = {
      raw_score: activityScore,
      weighted_score: Math.round(activityScore * weights.activity),
      weight: weights.activity,
      has_data: true,
      input: inputs.steps ?? inputs.workoutMinutes,
    };
    weightedSum += activityScore * weights.activity;
    totalWeight += weights.activity;
    dataPoints++;
  } else {
    components.activity = {
      raw_score: 0,
      weighted_score: 0,
      weight: weights.activity,
      has_data: false,
      input: null,
    };
  }

  // Streak Score (0-100)
  if (inputs.streakDays !== undefined || inputs.questCompleted !== undefined) {
    let streakScore = 0;

    if (inputs.streakDays !== undefined) {
      // Streak: logarithmic scaling, max at ~30 days
      streakScore = Math.min(
        100,
        Math.round(Math.log2(inputs.streakDays + 1) * 20),
      );
    }

    // Bonus for completing today's quest
    if (inputs.questCompleted) {
      streakScore = Math.min(100, streakScore + 20);
    }

    components.streak = {
      raw_score: streakScore,
      weighted_score: Math.round(streakScore * weights.streak),
      weight: weights.streak,
      has_data: true,
      input: inputs.streakDays,
    };
    weightedSum += streakScore * weights.streak;
    totalWeight += weights.streak;
    dataPoints++;
  } else {
    components.streak = {
      raw_score: 0,
      weighted_score: 0,
      weight: weights.streak,
      has_data: false,
      input: null,
    };
  }

  // Exercise Score (0-100)
  if (inputs.exercisesCompleted !== undefined) {
    // 1 exercise = 70, 2+ = 100
    const exerciseScore =
      inputs.exercisesCompleted === 0
        ? 0
        : inputs.exercisesCompleted === 1
          ? 70
          : 100;

    components.exercise = {
      raw_score: exerciseScore,
      weighted_score: Math.round(exerciseScore * weights.exercise),
      weight: weights.exercise,
      has_data: true,
      input: inputs.exercisesCompleted,
    };
    weightedSum += exerciseScore * weights.exercise;
    totalWeight += weights.exercise;
    dataPoints++;
  } else {
    components.exercise = {
      raw_score: 0,
      weighted_score: 0,
      weight: weights.exercise,
      has_data: false,
      input: null,
    };
  }

  // Calculate final score (normalize if missing data)
  const score = totalWeight > 0 ? Math.round(weightedSum / totalWeight) : 50; // Default neutral score if no data

  // Confidence based on data completeness
  const confidence = dataPoints / 5;

  return { score, confidence, components };
}
```

---

## 4. Implementation Details

### 4.1 Step-by-Step Implementation

#### Step 1: Database Schema

1. Create migration for `wellness_scores` table
2. Add RLS policies
3. Add indexes

#### Step 2: Edge Function

1. Implement `calculate-wellness-score` function
2. Implement `get-wellness-history` function
3. Add score calculation algorithm

#### Step 3: iOS Service Layer

1. Create `WellnessScoreService`
2. Implement local calculation for real-time updates
3. Add caching for widget data
4. Create sync with server

#### Step 4: iOS UI Components

1. Create `WellnessScoreCard` view
2. Create `WellnessScoreRing` view
3. Create `ScoreBreakdownSheet` view
4. Create `ScoreTrendChart` view

#### Step 5: Home Integration

1. Add score card to `HomeView`
2. Wire up real-time score updates
3. Add tap-to-expand breakdown

#### Step 6: Widget Implementation

1. Create widget target if not exists
2. Implement `WellnessScoreWidget`
3. Create timeline provider
4. Add widget refresh on score change

### 4.2 File Structure

```
apps/ios/MindFriendApp/
├── Core/
│   ├── Models/
│   │   └── WellnessScoreModels.swift
│   └── Services/
│       └── WellnessScoreService.swift
├── Features/
│   └── WellnessScore/
│       ├── Views/
│       │   ├── WellnessScoreCard.swift
│       │   ├── WellnessScoreRing.swift
│       │   ├── ScoreBreakdownSheet.swift
│       │   └── ScoreTrendChart.swift
│       └── ViewModels/
│           └── WellnessScoreViewModel.swift

apps/ios/MindFriendWidget/
├── WellnessScoreWidget.swift
├── WellnessScoreProvider.swift
└── WellnessScoreEntryView.swift

supabase/
├── functions/
│   ├── calculate-wellness-score/
│   │   └── index.ts
│   └── get-wellness-history/
│       └── index.ts
└── migrations/
    └── 20260122000002_wellness_scores.sql
```

### 4.3 UI Components

```swift
// WellnessScoreRing.swift

import SwiftUI

struct WellnessScoreRing: View {
    let score: Int
    let size: CGFloat

    private var progress: Double {
        Double(score) / 100.0
    }

    private var color: Color {
        switch score {
        case 0..<40: return .red
        case 40..<70: return .yellow
        default: return .green
        }
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(color.opacity(0.2), lineWidth: size * 0.1)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: size * 0.1,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: score)

            // Score text
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: size * 0.35, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Wellness")
                    .font(.system(size: size * 0.1, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

// WellnessScoreCard.swift

struct WellnessScoreCard: View {
    @ObservedObject var viewModel: WellnessScoreViewModel
    @State private var showBreakdown = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Wellness")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    if let delta = viewModel.deltaFromYesterday {
                        HStack(spacing: 4) {
                            Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            Text("\(delta >= 0 ? "+" : "")\(delta) from yesterday")
                        }
                        .font(.subheadline)
                        .foregroundColor(delta >= 0 ? .green : .red)
                    }
                }

                Spacer()

                WellnessScoreRing(score: viewModel.score, size: 80)
            }

            // 7-day trend
            if !viewModel.trend.isEmpty {
                ScoreTrendChart(scores: viewModel.trend)
                    .frame(height: 40)
            }

            // Message
            if let message = viewModel.contextMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        .onTapGesture {
            showBreakdown = true
        }
        .sheet(isPresented: $showBreakdown) {
            ScoreBreakdownSheet(breakdown: viewModel.breakdown)
        }
    }
}
```

---

## 5. Dependencies

### 5.1 Prerequisites

| Feature                            | Reason                                     |
| ---------------------------------- | ------------------------------------------ |
| F001: Biometric Correlation Engine | Provides sleep quality and activity scores |

### 5.2 External Libraries

| Library   | Version | Purpose             |
| --------- | ------- | ------------------- |
| WidgetKit | iOS 17+ | Home screen widget  |
| Charts    | iOS 16+ | Trend visualization |

### 5.3 Internal Modules

| Module                 | Purpose                          |
| ---------------------- | -------------------------------- |
| `MoodService`          | Get today's mood score           |
| `BiometricSyncService` | Get sleep/activity data          |
| `QuestService`         | Get streak and completion status |
| `ExerciseService`      | Get exercise completions         |

---

## 6. Edge Cases and Error Handling

### 6.1 Edge Cases

| Scenario                      | Expected Behavior                                                            |
| ----------------------------- | ---------------------------------------------------------------------------- |
| No data for today             | Show score of 50 with "Log mood to see your score" message                   |
| Only mood logged              | Calculate partial score (mood only), show "Add more data for complete score" |
| User hasn't used app for days | Show last known score grayed out with "Check in to update"                   |
| Score drops significantly     | Show supportive message, not alarming                                        |
| First day user                | Show onboarding state with potential score preview                           |
| Timezone change mid-day       | Keep current day's data, recalculate at midnight new timezone                |

### 6.2 Validation Rules

| Field            | Validation                   | Error Message                                      |
| ---------------- | ---------------------------- | -------------------------------------------------- |
| `local_date`     | Must be within last 365 days | "Cannot calculate score for dates over 1 year old" |
| Component scores | Must be 0-100                | "Invalid component score"                          |

---

## 7. Testing Requirements

### 7.1 Unit Test Scenarios

| Test Case          | Input                                                  | Expected Output                          |
| ------------------ | ------------------------------------------------------ | ---------------------------------------- |
| Perfect day        | mood=10, sleep=8h, steps=12000, streak=30, exercises=2 | Score ~95                                |
| Average day        | mood=6, sleep=7h, steps=6000, streak=3, exercises=0    | Score ~62                                |
| Poor day           | mood=3, sleep=4h, steps=2000, streak=0, exercises=0    | Score ~32                                |
| Missing sleep data | mood=7, steps=8000, streak=5, exercises=1              | Score calculated with reduced confidence |
| No data            | all undefined                                          | Score 50, confidence 0                   |

### 7.2 Integration Test Scenarios

| Test Case                 | Steps                                   | Expected Result                          |
| ------------------------- | --------------------------------------- | ---------------------------------------- |
| Score updates on mood log | 1. Log mood 7<br>2. Check score         | Score reflects mood component            |
| Widget updates            | 1. Complete quest<br>2. Check widget    | Widget shows updated score within 15 min |
| History retrieval         | 1. Get 30-day history<br>2. Verify data | All 30 days returned with deltas         |
