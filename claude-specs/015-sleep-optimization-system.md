# F012: Sleep Optimization System

## Overview

### Summary

Comprehensive sleep tracking and optimization system that learns user patterns, provides personalized wind-down routines, and correlates sleep quality with emotional wellness outcomes.

### Business Value

- Addresses top user wellness concern (sleep affects mood significantly)
- Daily engagement touchpoint (evening + morning)
- Premium feature with high perceived value

### User Benefit

- Better sleep through personalized routines
- Understanding of sleep-mood connections
- Actionable insights for sleep improvement

### Dependencies

- F001: Biometric Correlation Engine (for sleep data integration)
- F003: Predictive Mood Intelligence (for sleep-mood correlation)

---

## Requirements

### Functional Requirements

| ID     | Requirement                                                     | Priority    |
| ------ | --------------------------------------------------------------- | ----------- |
| FR-001 | Import sleep data from HealthKit (duration, stages, heart rate) | Must Have   |
| FR-002 | Manual sleep logging for users without wearables                | Must Have   |
| FR-003 | Personalized wind-down routine suggestions based on patterns    | Must Have   |
| FR-004 | Sleep quality score (0-100) with contributing factors           | Must Have   |
| FR-005 | Morning check-in with sleep rating and dream journaling         | Should Have |
| FR-006 | Sleep debt tracking and recovery recommendations                | Should Have |
| FR-007 | Bedtime reminders with smart timing based on patterns           | Should Have |
| FR-008 | Sleep environment tips personalized to user context             | Could Have  |
| FR-009 | Sleep sounds and guided wind-down exercises                     | Should Have |
| FR-010 | Weekly sleep report with trends and insights                    | Must Have   |

### Non-Functional Requirements

| ID      | Requirement                    | Target             |
| ------- | ------------------------------ | ------------------ |
| NFR-001 | HealthKit sync frequency       | Every 4 hours      |
| NFR-002 | Sleep score calculation        | < 500ms            |
| NFR-003 | Routine recommendation latency | < 1s               |
| NFR-004 | Offline sleep logging          | Full functionality |

### Acceptance Criteria

```gherkin
Feature: Sleep Optimization

Scenario: Morning sleep check-in
  Given user woke up and opens the app
  When the app detects it's within 2 hours of wake time
  Then morning check-in prompt should appear
  And user can rate sleep quality (1-5 stars)
  And user can optionally log dream notes
  And sleep score should display with breakdown

Scenario: Personalized wind-down routine
  Given user has 14+ days of sleep data
  When user requests wind-down routine at 9:30 PM
  Then routine should be personalized based on patterns
  And exercises should match user's preferred types
  And duration should fit time until target bedtime

Scenario: Sleep-mood correlation insight
  Given user has logged sleep and moods for 30+ days
  When viewing sleep insights
  Then correlation between sleep quality and next-day mood should show
  And specific patterns should be highlighted
  And actionable recommendations should appear
```

---

## Technical Design

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    iOS Application                       │
├─────────────────────────────────────────────────────────┤
│  SleepService                                           │
│  ├── HealthKit sleep data sync                          │
│  ├── Sleep score calculation                            │
│  ├── Pattern analysis                                   │
│  └── Wind-down routine engine                           │
├─────────────────────────────────────────────────────────┤
│  SleepViews                                             │
│  ├── SleepDashboardView                                 │
│  ├── MorningCheckInView                                 │
│  ├── WindDownRoutineView                                │
│  └── SleepInsightsView                                  │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│              Supabase Edge Functions                     │
├─────────────────────────────────────────────────────────┤
│  analyze-sleep-patterns                                 │
│  ├── Pattern detection algorithms                       │
│  ├── Correlation with mood data                         │
│  └── Recommendation generation                          │
├─────────────────────────────────────────────────────────┤
│  generate-wind-down                                     │
│  └── AI-powered routine creation                        │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                  PostgreSQL Tables                       │
├─────────────────────────────────────────────────────────┤
│  sleep_entries │ sleep_goals │ wind_down_sessions       │
└─────────────────────────────────────────────────────────┘
```

### Data Models

#### Database Schema

```sql
-- Sleep entries (synced from HealthKit or manual)
CREATE TABLE sleep_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    source TEXT NOT NULL CHECK (source IN ('healthkit', 'manual', 'apple_watch')),

    -- Timing
    bedtime TIMESTAMPTZ NOT NULL,
    wake_time TIMESTAMPTZ NOT NULL,
    time_in_bed_minutes INTEGER NOT NULL,
    time_asleep_minutes INTEGER,

    -- Stages (from wearables)
    deep_sleep_minutes INTEGER,
    rem_sleep_minutes INTEGER,
    light_sleep_minutes INTEGER,
    awake_minutes INTEGER,

    -- Quality metrics
    sleep_efficiency DECIMAL(5,2), -- % of time in bed actually asleep
    heart_rate_avg INTEGER,
    heart_rate_min INTEGER,
    hrv_avg DECIMAL(5,2),
    respiratory_rate DECIMAL(4,1),

    -- User input
    user_rating INTEGER CHECK (user_rating BETWEEN 1 AND 5),
    dream_notes TEXT,
    notes TEXT,

    -- Calculated
    sleep_score INTEGER CHECK (sleep_score BETWEEN 0 AND 100),
    score_breakdown JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, date)
);

-- Sleep goals and preferences
CREATE TABLE sleep_goals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    target_bedtime TIME,
    target_wake_time TIME,
    target_duration_minutes INTEGER NOT NULL DEFAULT 480, -- 8 hours
    wind_down_duration_minutes INTEGER NOT NULL DEFAULT 30,
    bedtime_reminder_enabled BOOLEAN NOT NULL DEFAULT true,
    bedtime_reminder_offset_minutes INTEGER NOT NULL DEFAULT 60,
    preferred_wind_down_types TEXT[] DEFAULT ARRAY['breathing', 'meditation'],
    sleep_environment_prefs JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Sleep debt tracking
CREATE TABLE sleep_debt (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    current_debt_minutes INTEGER NOT NULL DEFAULT 0,
    week_avg_duration_minutes INTEGER,
    optimal_duration_minutes INTEGER NOT NULL DEFAULT 480,
    last_calculated TIMESTAMPTZ NOT NULL DEFAULT now(),
    debt_history JSONB DEFAULT '[]', -- Last 7 days
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Wind-down sessions
CREATE TABLE wind_down_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    started_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    routine JSONB NOT NULL, -- Ordered list of activities
    duration_planned_minutes INTEGER NOT NULL,
    duration_actual_minutes INTEGER,
    completed BOOLEAN NOT NULL DEFAULT false,
    sleep_entry_id UUID REFERENCES sleep_entries(id),
    feedback_rating INTEGER CHECK (feedback_rating BETWEEN 1 AND 5),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Sleep insights cache
CREATE TABLE sleep_insights (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    insight_type TEXT NOT NULL,
    insight_data JSONB NOT NULL,
    generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_until TIMESTAMPTZ NOT NULL,
    viewed BOOLEAN NOT NULL DEFAULT false
);

-- Indexes
CREATE INDEX idx_sleep_entries_user_date ON sleep_entries(user_id, date DESC);
CREATE INDEX idx_sleep_entries_score ON sleep_entries(user_id, sleep_score);
CREATE INDEX idx_wind_down_sessions_user ON wind_down_sessions(user_id, started_at DESC);
CREATE INDEX idx_sleep_insights_user ON sleep_insights(user_id, generated_at DESC);

-- RLS Policies
ALTER TABLE sleep_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE sleep_goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE sleep_debt ENABLE ROW LEVEL SECURITY;
ALTER TABLE wind_down_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE sleep_insights ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own sleep entries" ON sleep_entries
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own sleep goals" ON sleep_goals
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view own sleep debt" ON sleep_debt
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own wind-down sessions" ON wind_down_sessions
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view own insights" ON sleep_insights
    FOR SELECT USING (auth.uid() = user_id);
```

#### Swift Models

```swift
// MARK: - Sleep Models

struct SleepEntry: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let date: Date
    let source: SleepSource

    // Timing
    let bedtime: Date
    let wakeTime: Date
    let timeInBedMinutes: Int
    let timeAsleepMinutes: Int?

    // Stages
    let deepSleepMinutes: Int?
    let remSleepMinutes: Int?
    let lightSleepMinutes: Int?
    let awakeMinutes: Int?

    // Quality
    let sleepEfficiency: Double?
    let heartRateAvg: Int?
    let heartRateMin: Int?
    let hrvAvg: Double?
    let respiratoryRate: Double?

    // User input
    var userRating: Int?
    var dreamNotes: String?
    var notes: String?

    // Calculated
    let sleepScore: Int?
    let scoreBreakdown: SleepScoreBreakdown?

    var durationFormatted: String {
        let hours = (timeAsleepMinutes ?? timeInBedMinutes) / 60
        let mins = (timeAsleepMinutes ?? timeInBedMinutes) % 60
        return "\(hours)h \(mins)m"
    }

    var hasWearableData: Bool {
        deepSleepMinutes != nil || remSleepMinutes != nil
    }
}

enum SleepSource: String, Codable {
    case healthkit
    case manual
    case appleWatch = "apple_watch"
}

struct SleepScoreBreakdown: Codable {
    let duration: Int // 0-25 points
    let efficiency: Int // 0-25 points
    let timing: Int // 0-20 points
    let stages: Int // 0-20 points
    let restfulness: Int // 0-10 points

    var total: Int {
        duration + efficiency + timing + stages + restfulness
    }

    var primaryFactor: String {
        let factors: [(String, Int)] = [
            ("Duration", duration),
            ("Efficiency", efficiency),
            ("Timing", timing),
            ("Sleep Stages", stages),
            ("Restfulness", restfulness)
        ]
        return factors.min(by: { $0.1 < $1.1 })?.0 ?? "Duration"
    }
}

struct SleepGoals: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var targetBedtime: Date?
    var targetWakeTime: Date?
    var targetDurationMinutes: Int
    var windDownDurationMinutes: Int
    var bedtimeReminderEnabled: Bool
    var bedtimeReminderOffsetMinutes: Int
    var preferredWindDownTypes: [String]
    var sleepEnvironmentPrefs: SleepEnvironmentPrefs
}

struct SleepEnvironmentPrefs: Codable {
    var prefersDarkRoom: Bool?
    var prefersCoolRoom: Bool?
    var usesWhiteNoise: Bool?
    var hasBlueLight: Bool?
}

struct SleepDebt: Codable {
    let id: UUID
    let userId: UUID
    var currentDebtMinutes: Int
    let weekAvgDurationMinutes: Int?
    let optimalDurationMinutes: Int
    let lastCalculated: Date
    let debtHistory: [DailyDebt]

    var debtHours: Double {
        Double(currentDebtMinutes) / 60.0
    }

    var isInDebt: Bool {
        currentDebtMinutes > 30 // More than 30 min debt
    }

    var recoveryNights: Int {
        // Estimate nights to recover (max 1 hour extra per night)
        Int(ceil(Double(currentDebtMinutes) / 60.0))
    }
}

struct DailyDebt: Codable {
    let date: Date
    let debtMinutes: Int
}

struct WindDownSession: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let startedAt: Date
    var completedAt: Date?
    let routine: [WindDownActivity]
    let durationPlannedMinutes: Int
    var durationActualMinutes: Int?
    var completed: Bool
    let sleepEntryId: UUID?
    var feedbackRating: Int?
}

struct WindDownActivity: Codable, Identifiable {
    let id: UUID
    let type: String // "breathing", "meditation", "journaling", "stretching"
    let exerciseId: UUID?
    let name: String
    let durationMinutes: Int
    var completed: Bool
}

struct SleepInsight: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let insightType: SleepInsightType
    let insightData: SleepInsightData
    let generatedAt: Date
    let validUntil: Date
    var viewed: Bool
}

enum SleepInsightType: String, Codable {
    case weeklyReport = "weekly_report"
    case moodCorrelation = "mood_correlation"
    case patternDetected = "pattern_detected"
    case improvement = "improvement"
    case concern = "concern"
}

struct SleepInsightData: Codable {
    let title: String
    let message: String
    let metric: String?
    let value: Double?
    let trend: String? // "improving", "declining", "stable"
    let recommendation: String?
}
```

### API Contracts

#### Log Sleep Entry

```
POST /rest/v1/sleep_entries

Request:
{
  "date": "2024-01-15",
  "source": "manual",
  "bedtime": "2024-01-14T23:00:00Z",
  "wake_time": "2024-01-15T07:00:00Z",
  "time_in_bed_minutes": 480,
  "user_rating": 4,
  "notes": "Slept well"
}

Response 201:
{
  "id": "uuid",
  "sleep_score": 78,
  "score_breakdown": {
    "duration": 22,
    "efficiency": 20,
    "timing": 18,
    "stages": 10,
    "restfulness": 8
  }
}
```

#### Get Wind-Down Routine

```
POST /functions/v1/generate-wind-down

Request:
{
  "targetBedtime": "2024-01-15T23:00:00Z",
  "availableMinutes": 30,
  "preferences": ["breathing", "meditation"]
}

Response 200:
{
  "session": {
    "id": "uuid",
    "routine": [
      {
        "id": "uuid",
        "type": "breathing",
        "exerciseId": "uuid",
        "name": "4-7-8 Breathing",
        "durationMinutes": 5
      },
      {
        "id": "uuid",
        "type": "meditation",
        "exerciseId": "uuid",
        "name": "Body Scan for Sleep",
        "durationMinutes": 15
      },
      {
        "id": "uuid",
        "type": "journaling",
        "name": "Gratitude Reflection",
        "durationMinutes": 10
      }
    ],
    "durationPlannedMinutes": 30
  },
  "tips": [
    "Your room is likely too warm based on your recent sleep data",
    "Try reducing screen time 30 minutes earlier tonight"
  ]
}
```

#### Get Sleep Analysis

```
GET /functions/v1/analyze-sleep-patterns

Response 200:
{
  "weeklyStats": {
    "avgDuration": 422,
    "avgScore": 74,
    "avgBedtime": "23:15",
    "avgWakeTime": "07:02",
    "consistency": 0.78
  },
  "sleepDebt": {
    "currentMinutes": 120,
    "trend": "decreasing"
  },
  "moodCorrelation": {
    "coefficient": 0.72,
    "insight": "Better sleep strongly correlates with improved mood next day"
  },
  "patterns": [
    {
      "type": "weekend_shift",
      "description": "You sleep 1.5 hours later on weekends",
      "impact": "negative",
      "recommendation": "Try keeping weekend bedtime within 30 min of weekday"
    }
  ],
  "recommendations": [
    "Your deep sleep is below optimal; try the Deep Sleep meditation",
    "Consistency is improving - keep it up!"
  ]
}
```

---

## Implementation Details

### Step-by-Step Approach

1. **HealthKit Integration**
   - Request sleep analysis authorization
   - Query HKCategorySample for sleep data
   - Map HealthKit sleep stages to our model
   - Background refresh every 4 hours

2. **Sleep Score Algorithm**
   - Duration score (vs optimal)
   - Efficiency score (asleep/in bed)
   - Timing score (consistency with goals)
   - Stages score (if available)
   - Restfulness score (wake events)

3. **Morning Check-In Flow**
   - Detect wake time from HealthKit or manual
   - Show check-in prompt within 2 hours
   - Collect rating, optional notes
   - Display score and insights

4. **Wind-Down Routine Engine**
   - Query user preferences
   - Select exercises based on time available
   - Order for optimal relaxation progression
   - Track completion and feedback

5. **Pattern Analysis**
   - Calculate rolling averages
   - Detect schedule inconsistencies
   - Correlate with mood data
   - Generate actionable insights

### File Structure

```
apps/ios/MindFriendApp/
├── Features/
│   └── Sleep/
│       ├── SleepService.swift
│       ├── SleepHealthKitManager.swift
│       ├── SleepScoreCalculator.swift
│       ├── Views/
│       │   ├── SleepDashboardView.swift
│       │   ├── MorningCheckInView.swift
│       │   ├── WindDownRoutineView.swift
│       │   ├── SleepInsightsView.swift
│       │   ├── SleepHistoryView.swift
│       │   └── SleepGoalsView.swift
│       └── Components/
│           ├── SleepScoreRing.swift
│           ├── SleepStageChart.swift
│           └── SleepTrendGraph.swift
│
supabase/
├── functions/
│   ├── generate-wind-down/
│   ├── analyze-sleep-patterns/
│   └── calculate-sleep-debt/
├── migrations/
│   └── YYYYMMDD_sleep_optimization.sql
```

### Key Algorithms

#### Sleep Score Calculation (Swift)

```swift
struct SleepScoreCalculator {

    func calculateScore(entry: SleepEntry, goals: SleepGoals) -> SleepScoreBreakdown {
        let duration = calculateDurationScore(entry: entry, goals: goals)
        let efficiency = calculateEfficiencyScore(entry: entry)
        let timing = calculateTimingScore(entry: entry, goals: goals)
        let stages = calculateStagesScore(entry: entry)
        let restfulness = calculateRestfulnessScore(entry: entry)

        return SleepScoreBreakdown(
            duration: duration,
            efficiency: efficiency,
            timing: timing,
            stages: stages,
            restfulness: restfulness
        )
    }

    // Duration: 0-25 points
    private func calculateDurationScore(entry: SleepEntry, goals: SleepGoals) -> Int {
        let target = Double(goals.targetDurationMinutes)
        let actual = Double(entry.timeAsleepMinutes ?? entry.timeInBedMinutes)

        // Optimal: 90-110% of target = 25 points
        // Acceptable: 70-90% or 110-130% = partial
        // Poor: <70% or >130% = low

        let ratio = actual / target

        if ratio >= 0.9 && ratio <= 1.1 {
            return 25
        } else if ratio >= 0.8 && ratio < 0.9 {
            return 20
        } else if ratio > 1.1 && ratio <= 1.2 {
            return 20
        } else if ratio >= 0.7 && ratio < 0.8 {
            return 15
        } else if ratio > 1.2 && ratio <= 1.3 {
            return 15
        } else {
            return max(5, Int(25 * min(ratio, 2 - ratio)))
        }
    }

    // Efficiency: 0-25 points
    private func calculateEfficiencyScore(entry: SleepEntry) -> Int {
        guard let efficiency = entry.sleepEfficiency else {
            // If no efficiency data, estimate from time in bed vs asleep
            guard let asleep = entry.timeAsleepMinutes else { return 15 }
            let estimated = Double(asleep) / Double(entry.timeInBedMinutes) * 100
            return efficiencyToPoints(estimated)
        }
        return efficiencyToPoints(efficiency)
    }

    private func efficiencyToPoints(_ efficiency: Double) -> Int {
        // 85%+ = 25, 80-85% = 20, 75-80% = 15, etc.
        if efficiency >= 85 { return 25 }
        if efficiency >= 80 { return 20 }
        if efficiency >= 75 { return 15 }
        if efficiency >= 70 { return 10 }
        return 5
    }

    // Timing: 0-20 points (consistency with target)
    private func calculateTimingScore(entry: SleepEntry, goals: SleepGoals) -> Int {
        guard let targetBedtime = goals.targetBedtime else { return 15 }

        let calendar = Calendar.current
        let bedtimeComponents = calendar.dateComponents([.hour, .minute], from: entry.bedtime)
        let targetComponents = calendar.dateComponents([.hour, .minute], from: targetBedtime)

        let bedtimeMinutes = (bedtimeComponents.hour ?? 0) * 60 + (bedtimeComponents.minute ?? 0)
        let targetMinutes = (targetComponents.hour ?? 0) * 60 + (targetComponents.minute ?? 0)

        let diff = abs(bedtimeMinutes - targetMinutes)

        // Within 15 min = 20, 30 min = 15, 60 min = 10, etc.
        if diff <= 15 { return 20 }
        if diff <= 30 { return 17 }
        if diff <= 45 { return 14 }
        if diff <= 60 { return 11 }
        if diff <= 90 { return 8 }
        return 5
    }

    // Stages: 0-20 points (quality of sleep architecture)
    private func calculateStagesScore(entry: SleepEntry) -> Int {
        guard let deep = entry.deepSleepMinutes,
              let rem = entry.remSleepMinutes,
              let totalAsleep = entry.timeAsleepMinutes else {
            return 10 // Default when no stage data
        }

        var score = 0

        // Deep sleep: 15-25% is optimal
        let deepPercent = Double(deep) / Double(totalAsleep) * 100
        if deepPercent >= 15 && deepPercent <= 25 {
            score += 10
        } else if deepPercent >= 10 && deepPercent < 15 {
            score += 7
        } else if deepPercent > 25 && deepPercent <= 30 {
            score += 8
        } else {
            score += 4
        }

        // REM: 20-25% is optimal
        let remPercent = Double(rem) / Double(totalAsleep) * 100
        if remPercent >= 20 && remPercent <= 25 {
            score += 10
        } else if remPercent >= 15 && remPercent < 20 {
            score += 7
        } else if remPercent > 25 && remPercent <= 30 {
            score += 8
        } else {
            score += 4
        }

        return score
    }

    // Restfulness: 0-10 points
    private func calculateRestfulnessScore(entry: SleepEntry) -> Int {
        guard let awake = entry.awakeMinutes,
              let totalInBed = entry.timeInBedMinutes else {
            return 5
        }

        let awakePercent = Double(awake) / Double(totalInBed) * 100

        // <5% awake = 10, 5-10% = 8, 10-15% = 6, etc.
        if awakePercent < 5 { return 10 }
        if awakePercent < 10 { return 8 }
        if awakePercent < 15 { return 6 }
        if awakePercent < 20 { return 4 }
        return 2
    }
}
```

#### Wind-Down Routine Generation (TypeScript)

```typescript
interface WindDownRequest {
  userId: string;
  targetBedtime: Date;
  availableMinutes: number;
  preferences: string[];
}

async function generateWindDownRoutine(
  supabase: SupabaseClient,
  request: WindDownRequest,
): Promise<WindDownSession> {
  const { userId, availableMinutes, preferences } = request;

  // Get user's exercise history for personalization
  const { data: history } = await supabase
    .from("exercise_sessions")
    .select("exercise_id, feedback_rating")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(50);

  // Get available wind-down exercises
  const { data: exercises } = await supabase
    .from("exercises")
    .select("*")
    .in("type", preferences)
    .eq("suitable_for_wind_down", true);

  // Rank exercises by preference and history
  const rankedExercises = rankExercises(exercises, history, preferences);

  // Build routine to fit time
  const routine = buildRoutine(rankedExercises, availableMinutes);

  // Create session
  const session = {
    user_id: userId,
    started_at: new Date().toISOString(),
    routine: routine,
    duration_planned_minutes: availableMinutes,
    completed: false,
  };

  const { data } = await supabase
    .from("wind_down_sessions")
    .insert(session)
    .select()
    .single();

  return data;
}

function buildRoutine(
  exercises: RankedExercise[],
  totalMinutes: number,
): WindDownActivity[] {
  const routine: WindDownActivity[] = [];
  let remaining = totalMinutes;

  // Always start with breathing (calming)
  const breathing = exercises.find((e) => e.type === "breathing");
  if (breathing && remaining >= 5) {
    routine.push({
      id: crypto.randomUUID(),
      type: "breathing",
      exerciseId: breathing.id,
      name: breathing.name,
      durationMinutes: Math.min(5, remaining),
      completed: false,
    });
    remaining -= 5;
  }

  // Add meditation if time
  const meditation = exercises.find((e) => e.type === "meditation");
  if (meditation && remaining >= 10) {
    const duration = Math.min(15, remaining - 5); // Leave room for closing
    routine.push({
      id: crypto.randomUUID(),
      type: "meditation",
      exerciseId: meditation.id,
      name: meditation.name,
      durationMinutes: duration,
      completed: false,
    });
    remaining -= duration;
  }

  // Add journaling/gratitude if time
  if (remaining >= 5) {
    routine.push({
      id: crypto.randomUUID(),
      type: "journaling",
      exerciseId: null,
      name: "Gratitude Reflection",
      durationMinutes: remaining,
      completed: false,
    });
  }

  return routine;
}
```

---

## Dependencies

### Internal Dependencies

- **F001 Biometric Correlation Engine**: Sleep data storage and correlation
- **F003 Predictive Mood Intelligence**: Sleep-mood pattern analysis
- **Exercise library**: Wind-down exercise content

### External Dependencies

- HealthKit for sleep data import
- AVFoundation for sleep sounds

### Infrastructure Requirements

- Background app refresh for HealthKit sync
- Local notifications for bedtime reminders

---

## Edge Cases & Error Handling

| Scenario                          | Handling                                                       |
| --------------------------------- | -------------------------------------------------------------- |
| No HealthKit authorization        | Graceful fallback to manual logging only                       |
| Incomplete sleep data (no stages) | Calculate score with available data; indicate limited accuracy |
| Very short sleep (<3 hours)       | Flag as nap or power sleep; don't penalize score heavily       |
| Very long sleep (>12 hours)       | Suggest potential oversleep issues                             |
| Split sleep (woke up, returned)   | Combine segments; calculate total                              |
| Time zone change                  | Use local timezone for consistency scoring                     |
| No sleep data for 7+ days         | Prompt to log manually; pause debt calculation                 |
| Wind-down not completed           | Save progress; offer resume or skip                            |

---

## Testing Requirements

### Unit Tests

```swift
// SleepScoreCalculatorTests.swift

func testOptimalDurationScores25() {
    let calculator = SleepScoreCalculator()
    let entry = MockData.sleepEntry(durationMinutes: 480)
    let goals = MockData.sleepGoals(targetDuration: 480)

    let score = calculator.calculateScore(entry: entry, goals: goals)

    XCTAssertEqual(score.duration, 25)
}

func testShortSleepReducesDurationScore() {
    let calculator = SleepScoreCalculator()
    let entry = MockData.sleepEntry(durationMinutes: 300) // 5 hours
    let goals = MockData.sleepGoals(targetDuration: 480)

    let score = calculator.calculateScore(entry: entry, goals: goals)

    XCTAssertLessThan(score.duration, 15)
}

func testHighEfficiencyScores25() {
    let calculator = SleepScoreCalculator()
    let entry = MockData.sleepEntry(efficiency: 90.0)

    let score = calculator.calculateEfficiencyScore(entry: entry)

    XCTAssertEqual(score, 25)
}

func testMissingStageDat aDefaults() {
    let calculator = SleepScoreCalculator()
    let entry = MockData.sleepEntry(deepSleep: nil, remSleep: nil)

    let score = calculator.calculateStagesScore(entry: entry)

    XCTAssertEqual(score, 10) // Default when no data
}

func testBedtimeConsistencyScore() {
    let calculator = SleepScoreCalculator()
    let entry = MockData.sleepEntry(bedtime: "23:10")
    let goals = MockData.sleepGoals(targetBedtime: "23:00")

    let score = calculator.calculateTimingScore(entry: entry, goals: goals)

    XCTAssertEqual(score, 20) // Within 15 min
}
```

### Integration Tests

```typescript
// supabase/functions/generate-wind-down/test.ts

Deno.test("routine fits available time", async () => {
  const userId = await createTestUser();
  await setExercisePreferences(userId, ["breathing", "meditation"]);

  const result = await invokeFunction(
    "generate-wind-down",
    {
      targetBedtime: new Date(Date.now() + 30 * 60 * 1000),
      availableMinutes: 20,
      preferences: ["breathing", "meditation"],
    },
    userId,
  );

  const totalDuration = result.routine.reduce(
    (sum, a) => sum + a.durationMinutes,
    0,
  );
  assertEquals(totalDuration, 20);
});

Deno.test("routine respects preferences", async () => {
  const userId = await createTestUser();

  const result = await invokeFunction(
    "generate-wind-down",
    {
      availableMinutes: 30,
      preferences: ["breathing"], // Only breathing
    },
    userId,
  );

  const types = result.routine.map((a) => a.type);
  assert(types.includes("breathing"));
  assert(!types.includes("meditation"));
});
```

### UI Tests

```swift
func testMorningCheckInFlow() async {
    let sleepEntry = MockData.recentSleepEntry
    let view = MorningCheckInView(sleepEntry: sleepEntry)

    let rendered = try view.inspect()

    // Should show sleep duration
    XCTAssertTrue(rendered.find(text: sleepEntry.durationFormatted).exists)

    // Should have rating stars
    XCTAssertEqual(rendered.findAll(RatingStar.self).count, 5)

    // Should have optional dream notes
    XCTAssertTrue(rendered.find(TextField.self, where: { $0.placeholder == "Dream notes" }).exists)
}
```
