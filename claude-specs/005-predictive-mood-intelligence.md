# F003: Predictive Mood Intelligence

> **Feature ID:** F003
> **Phase:** 1 - Foundation
> **Priority:** P0 (Critical)
> **Dependencies:** F001 (Biometric Correlation Engine)
> **Dependents:** F009, F014, F025, F027

---

## 1. Overview

### 1.1 Summary

Predictive Mood Intelligence uses machine learning to forecast mood states 24-48 hours in advance based on patterns in biometrics, behavior, calendar events, and historical mood data. When a low-mood day is predicted, the system proactively delivers "armor" interventions to help users prepare.

### 1.2 Business Value

- **User Value:** Transform from reactive to proactive mental wellness—address problems before they manifest
- **Product Value:** Creates a unique "it knows me" experience that dramatically increases retention
- **Competitive Value:** Only wellness app that predicts and prevents mood dips instead of just responding

### 1.3 User Benefit

Users receive advance warning and preparation tools for difficult days, reducing the severity and duration of mood dips through proactive intervention.

---

## 2. Requirements

### 2.1 Functional Requirements

| ID     | Requirement                                                             | Priority |
| ------ | ----------------------------------------------------------------------- | -------- |
| FR-001 | Predict mood score for next 24-48 hours with confidence level           | Must     |
| FR-002 | Identify contributing factors to prediction (sleep, schedule, patterns) | Must     |
| FR-003 | Send proactive push notification when low mood predicted                | Must     |
| FR-004 | Offer "armor" interventions tailored to predicted trigger               | Must     |
| FR-005 | Allow user to schedule proactive exercises before predicted low period  | Should   |
| FR-006 | Learn from prediction accuracy and user feedback                        | Must     |
| FR-007 | Display prediction on home screen with explanation                      | Must     |
| FR-008 | Integrate with calendar (optional) to detect high-stress events         | Should   |
| FR-009 | Support user override/dismissal of predictions                          | Must     |
| FR-010 | Provide weekly prediction accuracy summary                              | Should   |
| FR-011 | Detect recurring patterns (Sunday scaries, Monday blues)                | Should   |

### 2.2 Non-Functional Requirements

| ID      | Requirement                             | Target                             |
| ------- | --------------------------------------- | ---------------------------------- |
| NFR-001 | Prediction calculation time             | < 2 seconds                        |
| NFR-002 | Minimum data for prediction             | 14 days of mood + biometric data   |
| NFR-003 | Prediction accuracy                     | > 70% within ±1 point (1-10 scale) |
| NFR-004 | False positive rate for low mood alerts | < 20%                              |
| NFR-005 | Model update frequency                  | Weekly retraining                  |

### 2.3 Acceptance Criteria

1. **AC-001:** User with 14+ days of data sees "Tomorrow's outlook" on home screen
2. **AC-002:** When low mood predicted, user receives notification: "Tomorrow might be challenging. Want to prepare?"
3. **AC-003:** Prediction shows top 3 contributing factors (e.g., "Poor sleep last night", "Monday", "Low activity")
4. **AC-004:** User can tap prediction to see suggested interventions
5. **AC-005:** User can provide feedback on prediction accuracy ("Was this helpful?")
6. **AC-006:** Prediction confidence displayed (e.g., "72% confident")

---

## 3. Technical Design

### 3.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                          iOS App                                 │
├─────────────────────────────────────────────────────────────────┤
│  MoodPredictionService                                          │
│  ├─ getPrediction()                                             │
│  ├─ getContributingFactors()                                    │
│  ├─ getArmorInterventions()                                     │
│  └─ submitFeedback()                                            │
│                                                                  │
│  Views:                                                          │
│  ├─ MoodPredictionCard                                          │
│  ├─ PredictionDetailSheet                                       │
│  └─ ArmorInterventionList                                       │
├─────────────────────────────────────────────────────────────────┤
│                        Supabase                                  │
├─────────────────────────────────────────────────────────────────┤
│  Tables:                      Edge Functions:                    │
│  ├─ mood_predictions          ├─ predict-mood                   │
│  ├─ prediction_feedback       ├─ train-mood-model               │
│  └─ prediction_patterns       └─ get-prediction-insights        │
│                                                                  │
│  ML Pipeline:                                                    │
│  └─ Scheduled model training (weekly)                           │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Data Models

#### 3.2.1 Database Schema

```sql
-- Mood predictions
CREATE TABLE mood_predictions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Prediction target
    target_date DATE NOT NULL,
    predicted_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Prediction results
    predicted_mood DECIMAL(3,1) NOT NULL, -- 1.0 to 10.0
    confidence DECIMAL(3,2) NOT NULL, -- 0.0 to 1.0
    prediction_range_low DECIMAL(3,1), -- Lower bound
    prediction_range_high DECIMAL(3,1), -- Upper bound

    -- Contributing factors (ordered by importance)
    factors JSONB NOT NULL DEFAULT '[]',
    -- Example: [
    --   {"factor": "sleep_deficit", "impact": -1.2, "description": "Poor sleep last night"},
    --   {"factor": "day_of_week", "impact": -0.5, "description": "Monday typically harder"},
    --   {"factor": "streak_momentum", "impact": 0.3, "description": "5-day streak boost"}
    -- ]

    -- Model metadata
    model_version VARCHAR(32) NOT NULL,
    features_used JSONB NOT NULL DEFAULT '{}',

    -- Outcome tracking
    actual_mood DECIMAL(3,1), -- Filled in after target_date
    accuracy_score DECIMAL(3,2), -- How accurate was prediction

    -- Notification tracking
    notification_sent BOOLEAN NOT NULL DEFAULT false,
    notification_sent_at TIMESTAMPTZ,
    armor_offered BOOLEAN NOT NULL DEFAULT false,
    armor_accepted BOOLEAN,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(user_id, target_date, model_version)
);

-- User feedback on predictions
CREATE TABLE prediction_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prediction_id UUID NOT NULL REFERENCES mood_predictions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    feedback_type VARCHAR(32) NOT NULL, -- 'accuracy', 'helpfulness', 'dismissal'
    rating INT CHECK (rating BETWEEN 1 AND 5),
    feedback_text TEXT,
    action_taken VARCHAR(64), -- 'scheduled_exercise', 'dismissed', 'viewed_only'

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Detected recurring patterns
CREATE TABLE prediction_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    pattern_type VARCHAR(64) NOT NULL, -- 'weekly_dip', 'monthly_cycle', 'seasonal', 'event_triggered'
    pattern_name VARCHAR(128) NOT NULL, -- "Sunday scaries", "Post-meeting slump"

    -- Pattern details
    trigger_conditions JSONB NOT NULL,
    -- Example: {"day_of_week": 0, "confidence": 0.85} for Sunday
    -- Example: {"calendar_event_type": "meeting", "duration_min": 60}

    average_impact DECIMAL(3,1) NOT NULL, -- Typical mood change
    occurrence_count INT NOT NULL DEFAULT 0,
    last_occurrence DATE,

    -- Status
    is_active BOOLEAN NOT NULL DEFAULT true,
    user_acknowledged BOOLEAN NOT NULL DEFAULT false,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_mood_predictions_user_date ON mood_predictions(user_id, target_date DESC);
CREATE INDEX idx_mood_predictions_pending ON mood_predictions(user_id, target_date) WHERE actual_mood IS NULL;
CREATE INDEX idx_prediction_patterns_user ON prediction_patterns(user_id, is_active);

-- RLS Policies
ALTER TABLE mood_predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE prediction_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE prediction_patterns ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own predictions"
    ON mood_predictions FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can read own feedback"
    ON prediction_feedback FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own feedback"
    ON prediction_feedback FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can read own patterns"
    ON prediction_patterns FOR SELECT
    USING (auth.uid() = user_id);
```

#### 3.2.2 Swift Models

```swift
// MoodPredictionModels.swift

import Foundation

// MARK: - Mood Prediction

struct MoodPrediction: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let targetDate: Date
    let predictedAt: Date

    let predictedMood: Double // 1.0 to 10.0
    let confidence: Double    // 0.0 to 1.0
    let predictionRangeLow: Double?
    let predictionRangeHigh: Double?

    let factors: [ContributingFactor]
    let modelVersion: String

    var actualMood: Double?
    var accuracyScore: Double?

    let notificationSent: Bool
    let armorOffered: Bool
    var armorAccepted: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case targetDate = "target_date"
        case predictedAt = "predicted_at"
        case predictedMood = "predicted_mood"
        case confidence
        case predictionRangeLow = "prediction_range_low"
        case predictionRangeHigh = "prediction_range_high"
        case factors
        case modelVersion = "model_version"
        case actualMood = "actual_mood"
        case accuracyScore = "accuracy_score"
        case notificationSent = "notification_sent"
        case armorOffered = "armor_offered"
        case armorAccepted = "armor_accepted"
    }

    var isLowMoodPredicted: Bool {
        predictedMood < 5.0
    }

    var outlookLabel: String {
        switch predictedMood {
        case 0..<4: return "Challenging"
        case 4..<6: return "Moderate"
        case 6..<8: return "Good"
        default: return "Great"
        }
    }

    var confidenceLabel: String {
        switch confidence {
        case 0..<0.5: return "Low"
        case 0.5..<0.75: return "Medium"
        default: return "High"
        }
    }
}

// MARK: - Contributing Factor

struct ContributingFactor: Codable, Identifiable {
    var id: String { factor }

    let factor: String        // Machine identifier
    let impact: Double        // Positive or negative impact on mood
    let description: String   // Human-readable explanation

    var impactLabel: String {
        if impact > 0 {
            return "+\(String(format: "%.1f", impact))"
        } else {
            return String(format: "%.1f", impact)
        }
    }

    var isPositive: Bool {
        impact > 0
    }

    var icon: String {
        switch factor {
        case let f where f.contains("sleep"): return "moon.zzz"
        case let f where f.contains("activity"): return "figure.walk"
        case let f where f.contains("streak"): return "flame"
        case let f where f.contains("day_of_week"): return "calendar"
        case let f where f.contains("calendar"): return "calendar.badge.exclamationmark"
        case let f where f.contains("weather"): return "cloud.sun"
        default: return "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - Prediction Pattern

struct PredictionPattern: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let patternType: PatternType
    let patternName: String
    let triggerConditions: [String: AnyCodable]
    let averageImpact: Double
    let occurrenceCount: Int
    let lastOccurrence: Date?
    let isActive: Bool
    let userAcknowledged: Bool

    enum PatternType: String, Codable {
        case weeklyDip = "weekly_dip"
        case monthlyCycle = "monthly_cycle"
        case seasonal = "seasonal"
        case eventTriggered = "event_triggered"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case patternType = "pattern_type"
        case patternName = "pattern_name"
        case triggerConditions = "trigger_conditions"
        case averageImpact = "average_impact"
        case occurrenceCount = "occurrence_count"
        case lastOccurrence = "last_occurrence"
        case isActive = "is_active"
        case userAcknowledged = "user_acknowledged"
    }
}

// MARK: - Armor Intervention

struct ArmorIntervention: Identifiable {
    let id: UUID
    let type: InterventionType
    let title: String
    let description: String
    let duration: Int // minutes
    let scheduledFor: Date?
    let targetFactor: String // Which factor this addresses

    enum InterventionType {
        case exercise(exerciseId: UUID)
        case microMoment(type: String)
        case questPreload
        case sleepReminder
        case socialNudge
    }
}

// MARK: - Prediction Feedback

struct PredictionFeedback: Codable {
    let predictionId: UUID
    let feedbackType: FeedbackType
    let rating: Int?
    let feedbackText: String?
    let actionTaken: String?

    enum FeedbackType: String, Codable {
        case accuracy
        case helpfulness
        case dismissal
    }

    enum CodingKeys: String, CodingKey {
        case predictionId = "prediction_id"
        case feedbackType = "feedback_type"
        case rating
        case feedbackText = "feedback_text"
        case actionTaken = "action_taken"
    }
}
```

### 3.3 API Contracts

#### 3.3.1 Edge Function: `predict-mood`

**Endpoint:** `POST /functions/v1/predict-mood`

**Request:**

```json
{
  "target_date": "2026-01-23",
  "include_armor": true,
  "calendar_events": [
    {
      "title": "Performance Review",
      "start_time": "2026-01-23T14:00:00Z",
      "duration_minutes": 60
    }
  ]
}
```

**Response (200):**

```json
{
  "prediction": {
    "id": "uuid",
    "target_date": "2026-01-23",
    "predicted_mood": 4.8,
    "confidence": 0.72,
    "prediction_range_low": 4.0,
    "prediction_range_high": 5.5,
    "factors": [
      {
        "factor": "sleep_deficit",
        "impact": -1.2,
        "description": "You averaged 5.5h sleep this week (vs 7.2h usual)"
      },
      {
        "factor": "calendar_stress",
        "impact": -0.8,
        "description": "Performance Review at 2pm typically impacts mood"
      },
      {
        "factor": "day_of_week",
        "impact": -0.3,
        "description": "Thursdays average 0.3 points lower for you"
      },
      {
        "factor": "streak_momentum",
        "impact": 0.4,
        "description": "Your 7-day streak is providing stability"
      }
    ],
    "model_version": "v2.3.1"
  },
  "armor_interventions": [
    {
      "id": "uuid",
      "type": "exercise",
      "title": "Pre-meeting grounding",
      "description": "5-minute grounding exercise before your review",
      "duration": 5,
      "scheduled_for": "2026-01-23T13:45:00Z",
      "target_factor": "calendar_stress"
    },
    {
      "id": "uuid",
      "type": "sleep_reminder",
      "title": "Sleep recovery tonight",
      "description": "Set a sleep reminder for 10pm to catch up",
      "target_factor": "sleep_deficit"
    }
  ],
  "patterns_detected": [
    {
      "pattern_name": "Thursday dip",
      "pattern_type": "weekly_dip",
      "average_impact": -0.3
    }
  ]
}
```

**Response (400) - Insufficient data:**

```json
{
  "error": {
    "code": "INSUFFICIENT_DATA",
    "message": "Need at least 14 days of mood data for predictions",
    "days_available": 8,
    "days_required": 14
  }
}
```

#### 3.3.2 Edge Function: `submit-prediction-feedback`

**Endpoint:** `POST /functions/v1/submit-prediction-feedback`

**Request:**

```json
{
  "prediction_id": "uuid",
  "feedback_type": "accuracy",
  "rating": 4,
  "feedback_text": "The sleep factor was spot on",
  "action_taken": "scheduled_exercise"
}
```

### 3.4 ML Model Architecture

```typescript
// Prediction model features

interface PredictionFeatures {
  // Historical mood (rolling windows)
  mood_avg_7d: number;
  mood_avg_14d: number;
  mood_trend_7d: number; // Slope of 7-day trend
  mood_volatility_7d: number; // Standard deviation

  // Sleep features
  sleep_hours_last_night: number;
  sleep_quality_last_night: number;
  sleep_avg_7d: number;
  sleep_deficit_cumulative: number; // Hours below target

  // Activity features
  steps_yesterday: number;
  steps_avg_7d: number;
  workout_minutes_7d: number;

  // Engagement features
  streak_days: number;
  exercises_completed_7d: number;
  quest_completion_rate_7d: number;

  // Temporal features
  day_of_week: number; // 0-6
  is_weekend: boolean;
  day_of_month: number;
  week_of_year: number;

  // Historical patterns
  same_day_avg_mood: number; // Average for this day of week
  same_week_avg_mood: number; // Average for this week of year

  // Calendar features (optional)
  has_stressful_event: boolean;
  meetings_count: number;
  meeting_duration_total: number;
}

// Model training pipeline (pseudo-code)
async function trainMoodModel(userId: string): Promise<ModelMetadata> {
  // 1. Fetch training data (last 90 days)
  const trainingData = await fetchTrainingData(userId, 90);

  // 2. Feature engineering
  const features = trainingData.map((day) => extractFeatures(day));

  // 3. Split train/validation
  const { train, validation } = splitData(features, 0.8);

  // 4. Train gradient boosting model
  const model = new XGBoostRegressor({
    maxDepth: 4,
    learningRate: 0.1,
    nEstimators: 100,
  });

  model.fit(train.X, train.y);

  // 5. Evaluate
  const predictions = model.predict(validation.X);
  const mae = meanAbsoluteError(validation.y, predictions);

  // 6. Save model
  const modelId = await saveModel(userId, model);

  return {
    modelId,
    version: "v2.3.1",
    mae,
    featureImportance: model.featureImportances,
    trainingDate: new Date(),
  };
}

// Prediction function
async function predictMood(
  userId: string,
  targetDate: Date,
  calendarEvents?: CalendarEvent[],
): Promise<MoodPrediction> {
  // 1. Load user's model
  const model = await loadModel(userId);

  // 2. Extract features for target date
  const features = await extractFeaturesForDate(
    userId,
    targetDate,
    calendarEvents,
  );

  // 3. Make prediction
  const predictedMood = model.predict([features])[0];

  // 4. Calculate confidence (based on feature completeness and model accuracy)
  const confidence = calculateConfidence(features, model.metadata);

  // 5. Get feature contributions (SHAP values)
  const contributions = model.explainPrediction(features);

  // 6. Map to factors
  const factors = contributions
    .filter((c) => Math.abs(c.value) > 0.1)
    .sort((a, b) => Math.abs(b.value) - Math.abs(a.value))
    .slice(0, 5)
    .map((c) => ({
      factor: c.feature,
      impact: c.value,
      description: generateFactorDescription(c),
    }));

  return {
    predictedMood,
    confidence,
    factors,
  };
}
```

---

## 4. Implementation Details

### 4.1 Step-by-Step Implementation

#### Step 1: Database Schema

1. Create migration for `mood_predictions` table
2. Create migration for `prediction_feedback` table
3. Create migration for `prediction_patterns` table
4. Add RLS policies and indexes

#### Step 2: Feature Pipeline

1. Create feature extraction functions
2. Implement rolling window calculations
3. Add calendar event processing (optional)
4. Create feature normalization

#### Step 3: ML Model

1. Implement XGBoost training pipeline
2. Create model serialization/storage
3. Implement prediction function
4. Add SHAP explainability

#### Step 4: Edge Functions

1. Implement `predict-mood` function
2. Implement `submit-prediction-feedback` function
3. Implement `train-mood-model` function (cron)
4. Implement pattern detection

#### Step 5: iOS Service Layer

1. Create `MoodPredictionService`
2. Implement prediction caching
3. Add calendar integration (optional)
4. Create notification scheduling

#### Step 6: iOS UI

1. Create `MoodPredictionCard` view
2. Create `PredictionDetailSheet` view
3. Create `ArmorInterventionList` view
4. Add to home screen

### 4.2 File Structure

```
apps/ios/MindFriendApp/
├── Core/
│   ├── Models/
│   │   └── MoodPredictionModels.swift
│   └── Services/
│       └── MoodPredictionService.swift
├── Features/
│   └── Prediction/
│       ├── Views/
│       │   ├── MoodPredictionCard.swift
│       │   ├── PredictionDetailSheet.swift
│       │   ├── ContributingFactorRow.swift
│       │   └── ArmorInterventionList.swift
│       └── ViewModels/
│           └── MoodPredictionViewModel.swift

supabase/
├── functions/
│   ├── predict-mood/
│   │   └── index.ts
│   ├── submit-prediction-feedback/
│   │   └── index.ts
│   └── train-mood-model/
│       └── index.ts
└── migrations/
    └── 20260122000003_mood_predictions.sql
```

### 4.3 Notification Strategy

```swift
// Prediction notification scheduling

func scheduleArmorNotification(prediction: MoodPrediction) {
    guard prediction.isLowMoodPredicted else { return }
    guard prediction.confidence > 0.6 else { return }

    let content = UNMutableNotificationContent()
    content.title = "Tomorrow's outlook"
    content.body = "Tomorrow might be \(prediction.outlookLabel.lowercased()). Want to prepare with a quick exercise?"
    content.sound = .default
    content.categoryIdentifier = "PREDICTION_ARMOR"

    // Schedule for evening before target date (8pm)
    let targetDate = prediction.targetDate
    let notificationDate = Calendar.current.date(
        bySettingHour: 20,
        minute: 0,
        second: 0,
        of: Calendar.current.date(byAdding: .day, value: -1, to: targetDate)!
    )!

    let trigger = UNCalendarNotificationTrigger(
        dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: notificationDate),
        repeats: false
    )

    let request = UNNotificationRequest(
        identifier: "prediction-\(prediction.id)",
        content: content,
        trigger: trigger
    )

    UNUserNotificationCenter.current().add(request)
}
```

---

## 5. Dependencies

### 5.1 Prerequisites

| Feature                            | Reason                                          |
| ---------------------------------- | ----------------------------------------------- |
| F001: Biometric Correlation Engine | Provides sleep/activity features for prediction |

### 5.2 External Libraries

| Library  | Version | Purpose                         |
| -------- | ------- | ------------------------------- |
| EventKit | iOS 17+ | Calendar integration (optional) |

### 5.3 Internal Modules

| Module                 | Purpose                    |
| ---------------------- | -------------------------- |
| `MoodService`          | Historical mood data       |
| `BiometricSyncService` | Sleep/activity features    |
| `QuestService`         | Streak and completion data |
| `NotificationService`  | Armor notifications        |

---

## 6. Edge Cases and Error Handling

### 6.1 Edge Cases

| Scenario                          | Expected Behavior                                             |
| --------------------------------- | ------------------------------------------------------------- |
| User has < 14 days of data        | Hide prediction card, show "Predictions unlock after 14 days" |
| No mood logged for 3+ days        | Show lower confidence, note data gap in factors               |
| Model accuracy < 50%              | Suppress predictions, retrain model                           |
| Calendar permission denied        | Make predictions without calendar features                    |
| Prediction consistently wrong     | Offer to retrain model, gather feedback                       |
| User always dismisses predictions | Reduce notification frequency                                 |
| Timezone change                   | Recalculate with new timezone context                         |

### 6.2 Error Handling

```swift
enum PredictionError: LocalizedError {
    case insufficientData(daysAvailable: Int, daysRequired: Int)
    case modelNotReady
    case predictionFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .insufficientData(let available, let required):
            return "Need \(required - available) more days of data for predictions"
        case .modelNotReady:
            return "Your prediction model is being trained"
        case .predictionFailed:
            return "Unable to generate prediction"
        }
    }
}
```

---

## 7. Testing Requirements

### 7.1 Unit Test Scenarios

| Test Case                          | Input                        | Expected Output            |
| ---------------------------------- | ---------------------------- | -------------------------- |
| Feature extraction                 | 14 days of mood + sleep data | Valid feature vector       |
| Prediction with high sleep deficit | sleep_deficit > 10h          | Predicted mood < 5         |
| Prediction with strong streak      | streak_days > 30             | Positive streak factor     |
| Calendar stress detection          | 3+ hour meeting              | has_stressful_event = true |
| Confidence calculation             | Missing 2/10 features        | Confidence ~0.8            |

### 7.2 Integration Test Scenarios

| Test Case            | Steps                                                                             | Expected Result                     |
| -------------------- | --------------------------------------------------------------------------------- | ----------------------------------- |
| Full prediction flow | 1. Create 14 days history<br>2. Request prediction<br>3. Verify response          | Valid prediction with factors       |
| Feedback loop        | 1. Get prediction<br>2. Log actual mood<br>3. Submit feedback<br>4. Verify stored | Feedback saved, accuracy calculated |
| Pattern detection    | 1. Create 60 days with Sunday dips<br>2. Run pattern detection                    | "Sunday dip" pattern detected       |

### 7.3 Model Evaluation

| Metric                    | Target | Measurement Method                            |
| ------------------------- | ------ | --------------------------------------------- |
| MAE (Mean Absolute Error) | < 1.0  | Cross-validation on held-out data             |
| Low mood recall           | > 80%  | Percentage of actual lows correctly predicted |
| False positive rate       | < 20%  | Low predictions that were actually fine       |
