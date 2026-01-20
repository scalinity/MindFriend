# Predictive Intervention System

> The category-defining feature that makes MindFriend the first app to predict and prevent mental health dips before they happen.

**Priority:** P0 - Critical
**Effort:** High (8-10 weeks)
**Impact:** Category-defining differentiation; first-mover advantage

---

## 1. Overview

### 1.1 What It Does

An ML-powered system that analyzes mood patterns, behavioral signals, and biometric data to predict mental health dips BEFORE they happen, then proactively intervenes with personalized support.

### 1.2 Why It Exists

- **Unique Opportunity:** NO competitor has solved predictive intervention well
- **Clinical Reality:** Early intervention dramatically improves outcomes
- **User Experience:** Creates "magic moments" that drive word-of-mouth
- **Platform Advantage:** MindFriend already has mood data, AI chat, biometrics, and engagement signals
- **Differentiation:** Transforms from reactive app to proactive companion

### 1.3 Success Metrics

| Metric                  | Target            | Measurement                          |
| ----------------------- | ----------------- | ------------------------------------ |
| Prediction accuracy     | 70%+ precision    | Predicted dip vs actual mood drop    |
| Intervention acceptance | 50%+              | Interventions accepted / offered     |
| Crisis prevention       | 30% reduction     | Crisis events vs predicted           |
| User sentiment          | 4.5+ satisfaction | Post-intervention survey             |
| Retention lift          | +20%              | Cohort with interventions vs without |

---

## 2. User Stories

### 2.1 Primary Users

| Persona                | Need              | Story                                                                                                   |
| ---------------------- | ----------------- | ------------------------------------------------------------------------------------------------------- |
| **Anxiety Prone**      | Early warning     | "As someone with anxiety, I want to know when a bad episode is likely so I can take preventive action." |
| **Depression Manager** | Pattern awareness | "As someone managing depression, I want the app to notice when I'm slipping before I do."               |
| **Caregiver**          | Family alerts     | "As a parent, I want to be alerted if my child shows signs of declining mental health."                 |
| **Self-Optimizer**     | Insights          | "As someone tracking my wellness, I want to understand what triggers my low moods."                     |

### 2.2 Intervention Flow

```
Continuous Data Collection
         │
         ▼
┌─────────────────────────────┐
│ Signal Aggregation          │
│ • Mood trends               │
│ • App usage patterns        │
│ • Chat sentiment            │
│ • Biometric signals         │
│ • Sleep quality             │
│ • Quest completion          │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ Risk Scoring Model          │
│ • 24-hour prediction        │
│ • 7-day trend prediction    │
│ • Severity classification   │
└─────────────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ Risk Level Determined       │
│ Low | Medium | High | Crisis│
└─────────────────────────────┘
         │
    ┌────┴────┬────────┬───────┐
    ▼         ▼        ▼       ▼
┌───────┐ ┌───────┐ ┌──────┐ ┌──────┐
│ Low   │ │Medium │ │High  │ │Crisis│
│       │ │       │ │      │ │      │
│No     │ │Gentle │ │Active│ │Safety│
│Action │ │Nudge  │ │Check │ │Proto │
└───────┘ └───────┘ └──────┘ └──────┘
                       │
                       ▼
           ┌───────────────────┐
           │ Personalized      │
           │ Intervention      │
           │ • Context-aware   │
           │ • Time-optimized  │
           │ • Action-oriented │
           └───────────────────┘
                       │
                       ▼
           ┌───────────────────┐
           │ User Response     │
           │ Feedback Loop     │
           │ Model Learning    │
           └───────────────────┘
```

---

## 3. Functional Requirements

### 3.1 Signal Collection

| ID    | Requirement                                                     | Priority |
| ----- | --------------------------------------------------------------- | -------- |
| SC-01 | Aggregate mood scores from daily check-ins                      | Must     |
| SC-02 | Track mood velocity (rate of change)                            | Must     |
| SC-03 | Analyze app usage patterns (frequency, duration, features used) | Must     |
| SC-04 | Extract sentiment from chat conversations                       | Should   |
| SC-05 | Integrate HealthKit biometrics (HRV, sleep, activity)           | Must     |
| SC-06 | Track quest completion rate and streak status                   | Must     |
| SC-07 | Monitor social engagement (circle activity)                     | Should   |
| SC-08 | Note time-of-day and day-of-week patterns                       | Must     |
| SC-09 | Track response time to app notifications                        | Should   |
| SC-10 | Detect language pattern changes in chat                         | Could    |

### 3.2 Risk Scoring Model

| ID    | Requirement                                                                          | Priority |
| ----- | ------------------------------------------------------------------------------------ | -------- |
| RS-01 | Generate risk score 0-100 for each user daily                                        | Must     |
| RS-02 | Classify risk into levels: Low (0-25), Medium (26-50), High (51-75), Crisis (76-100) | Must     |
| RS-03 | Predict 24-hour mood trajectory                                                      | Must     |
| RS-04 | Predict 7-day trend direction                                                        | Should   |
| RS-05 | Identify top contributing factors to risk                                            | Must     |
| RS-06 | Account for user's baseline (personalized)                                           | Must     |
| RS-07 | Weight recent signals more heavily                                                   | Must     |
| RS-08 | Handle missing data gracefully                                                       | Must     |
| RS-09 | Explainability: provide human-readable risk factors                                  | Should   |
| RS-10 | Update model weights based on outcome feedback                                       | Should   |

### 3.3 Intervention Triggers

| ID    | Requirement                                                   | Priority |
| ----- | ------------------------------------------------------------- | -------- |
| IT-01 | No intervention for Low risk                                  | Must     |
| IT-02 | Gentle nudge for Medium risk (subtle, encouraging)            | Must     |
| IT-03 | Active check-in for High risk (direct, supportive)            | Must     |
| IT-04 | Safety protocol for Crisis risk (immediate, crisis resources) | Must     |
| IT-05 | Respect user's notification preferences                       | Must     |
| IT-06 | Rate-limit interventions (max 1 per 24 hours unless crisis)   | Must     |
| IT-07 | Time interventions for optimal user availability              | Should   |
| IT-08 | Escalate if no response within threshold                      | Should   |
| IT-09 | Allow user to disable predictive interventions                | Must     |
| IT-10 | Family alert for child accounts at High risk                  | Should   |

### 3.4 Intervention Content

| ID    | Requirement                                                       | Priority |
| ----- | ----------------------------------------------------------------- | -------- |
| IC-01 | Medium: "Noticed you might be having a tough time. Want to chat?" | Must     |
| IC-02 | High: "Hey, I'm here for you. Can we check in together?"          | Must     |
| IC-03 | Include personalized context (recent mood, contributing factors)  | Should   |
| IC-04 | Offer specific actions (breathing exercise, chat, call friend)    | Must     |
| IC-05 | Match intervention tone to user's communication style             | Could    |
| IC-06 | Reference past successful coping strategies                       | Should   |
| IC-07 | Provide one-tap access to recommended action                      | Must     |
| IC-08 | Allow dismissal without guilt                                     | Must     |

### 3.5 Feedback & Learning

| ID    | Requirement                                              | Priority |
| ----- | -------------------------------------------------------- | -------- |
| FL-01 | Track if intervention was accepted/dismissed             | Must     |
| FL-02 | Measure mood 24 hours post-intervention                  | Must     |
| FL-03 | Ask "Was this helpful?" after accepted interventions     | Should   |
| FL-04 | Correlate interventions with outcomes for model training | Should   |
| FL-05 | Identify which intervention types work for which users   | Could    |
| FL-06 | A/B test intervention messaging                          | Could    |

### 3.6 Privacy & Control

| ID    | Requirement                                               | Priority |
| ----- | --------------------------------------------------------- | -------- |
| PC-01 | User can disable predictive interventions entirely        | Must     |
| PC-02 | User can view what signals are being tracked              | Must     |
| PC-03 | User can exclude specific data sources                    | Should   |
| PC-04 | All prediction data stays on-device (privacy mode option) | Could    |
| PC-05 | No prediction data shared with third parties              | Must     |
| PC-06 | User can delete prediction history                        | Must     |

---

## 4. Technical Requirements

### 4.1 Data Models

```sql
-- Risk scores history
CREATE TABLE risk_assessments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    assessed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    risk_score INTEGER NOT NULL CHECK (risk_score BETWEEN 0 AND 100),
    risk_level TEXT NOT NULL CHECK (risk_level IN ('low', 'medium', 'high', 'crisis')),

    -- Contributing factors (JSON for flexibility)
    factors JSONB NOT NULL,
    -- Example: {
    --   "mood_trend": -15,
    --   "mood_volatility": 8,
    --   "app_engagement": -3,
    --   "sleep_quality": -2,
    --   "hrv_drop": -5,
    --   "streak_broken": true,
    --   "days_since_chat": 4
    -- }

    -- Predictions
    predicted_mood_24h DECIMAL(3,1), -- Predicted mood 24h from now
    predicted_trend_7d TEXT CHECK (predicted_trend_7d IN ('improving', 'stable', 'declining')),

    -- Model metadata
    model_version TEXT NOT NULL,
    confidence DECIMAL(3,2), -- 0.00 - 1.00

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Intervention history
CREATE TABLE interventions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    risk_assessment_id UUID REFERENCES risk_assessments(id),

    intervention_type TEXT NOT NULL CHECK (intervention_type IN ('gentle_nudge', 'active_checkin', 'crisis_protocol', 'family_alert')),
    channel TEXT NOT NULL CHECK (channel IN ('push', 'in_app', 'sms', 'email')),

    -- Content
    message_template TEXT NOT NULL,
    personalization JSONB, -- Dynamic elements inserted

    -- Timing
    scheduled_at TIMESTAMPTZ NOT NULL,
    delivered_at TIMESTAMPTZ,

    -- Response
    response TEXT CHECK (response IN ('accepted', 'dismissed', 'ignored', 'pending')),
    responded_at TIMESTAMPTZ,
    action_taken TEXT, -- 'started_chat', 'did_exercise', 'called_friend', etc.

    -- Outcome tracking
    mood_before INTEGER,
    mood_24h_after INTEGER,
    helpful_rating INTEGER CHECK (helpful_rating BETWEEN 1 AND 5),

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User prediction settings
CREATE TABLE prediction_settings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    predictions_enabled BOOLEAN DEFAULT true,

    -- Data sources user allows
    use_mood_data BOOLEAN DEFAULT true,
    use_chat_sentiment BOOLEAN DEFAULT true,
    use_biometrics BOOLEAN DEFAULT true,
    use_app_usage BOOLEAN DEFAULT true,
    use_sleep_data BOOLEAN DEFAULT true,

    -- Intervention preferences
    allow_gentle_nudges BOOLEAN DEFAULT true,
    allow_active_checkins BOOLEAN DEFAULT true,
    preferred_intervention_time TIME, -- Optimal time of day

    -- Family alerts
    allow_family_alerts BOOLEAN DEFAULT false,
    family_alert_threshold TEXT DEFAULT 'high', -- 'high' or 'crisis'

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Aggregated signals (computed daily)
CREATE TABLE daily_signals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    signal_date DATE NOT NULL,

    -- Mood signals
    mood_average DECIMAL(3,1),
    mood_min INTEGER,
    mood_max INTEGER,
    mood_variance DECIMAL(4,2),
    mood_trend DECIMAL(4,2), -- Slope of recent moods

    -- Engagement signals
    app_sessions INTEGER,
    total_active_minutes INTEGER,
    features_used TEXT[],
    quests_completed INTEGER,
    exercises_completed INTEGER,
    chat_messages_sent INTEGER,

    -- Social signals
    circle_posts INTEGER,
    circle_reactions_received INTEGER,

    -- Biometric signals (from HealthKit)
    avg_hrv DECIMAL(5,2),
    hrv_trend DECIMAL(5,2),
    sleep_hours DECIMAL(3,1),
    sleep_quality INTEGER,
    activity_minutes INTEGER,

    -- Computed
    engagement_score INTEGER, -- 0-100
    social_score INTEGER, -- 0-100
    biometric_score INTEGER, -- 0-100

    UNIQUE(user_id, signal_date)
);

-- RLS Policies
ALTER TABLE risk_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE interventions ENABLE ROW LEVEL SECURITY;
ALTER TABLE prediction_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_signals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own risk assessments"
    ON risk_assessments FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users view own interventions"
    ON interventions FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users manage own prediction settings"
    ON prediction_settings FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users view own signals"
    ON daily_signals FOR SELECT
    USING (auth.uid() = user_id);

-- Service role can insert risk assessments and interventions
CREATE POLICY "Service can insert risk assessments"
    ON risk_assessments FOR INSERT
    WITH CHECK (true);

CREATE POLICY "Service can insert interventions"
    ON interventions FOR INSERT
    WITH CHECK (true);
```

### 4.2 Swift Models

```swift
// MARK: - Predictive Intervention Models

enum RiskLevel: String, Codable, CaseIterable {
    case low
    case medium
    case high
    case crisis

    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .crisis: return .red
        }
    }

    var description: String {
        switch self {
        case .low: return "You're doing well"
        case .medium: return "Some signs to watch"
        case .high: return "We're here for you"
        case .crisis: return "Let's get you support"
        }
    }
}

struct RiskAssessment: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let assessedAt: Date
    let riskScore: Int // 0-100
    let riskLevel: RiskLevel
    let factors: RiskFactors
    let predictedMood24h: Double?
    let predictedTrend7d: TrendDirection?
    let modelVersion: String
    let confidence: Double?
}

struct RiskFactors: Codable {
    let moodTrend: Double? // Negative = declining
    let moodVolatility: Double?
    let appEngagement: Double? // Negative = disengaged
    let sleepQuality: Double?
    let hrvDrop: Double?
    let streakBroken: Bool?
    let daysSinceChat: Int?
    let socialEngagement: Double?

    var topFactors: [String] {
        var factors: [(String, Double)] = []

        if let trend = moodTrend, trend < -5 {
            factors.append(("Mood has been declining", abs(trend)))
        }
        if let volatility = moodVolatility, volatility > 10 {
            factors.append(("Mood has been variable", volatility))
        }
        if let engagement = appEngagement, engagement < -5 {
            factors.append(("Haven't been as active in the app", abs(engagement)))
        }
        if let sleep = sleepQuality, sleep < -3 {
            factors.append(("Sleep quality has dropped", abs(sleep)))
        }
        if streakBroken == true {
            factors.append(("Quest streak was broken", 10))
        }
        if let days = daysSinceChat, days > 3 {
            factors.append(("Haven't chatted in a while", Double(days)))
        }

        return factors
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map { $0.0 }
    }
}

enum TrendDirection: String, Codable {
    case improving
    case stable
    case declining
}

struct Intervention: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let riskAssessmentId: UUID?
    let interventionType: InterventionType
    let channel: InterventionChannel
    let messageTemplate: String
    let personalization: [String: String]?
    let scheduledAt: Date
    var deliveredAt: Date?
    var response: InterventionResponse?
    var respondedAt: Date?
    var actionTaken: String?
    var moodBefore: Int?
    var mood24hAfter: Int?
    var helpfulRating: Int?

    enum InterventionType: String, Codable {
        case gentleNudge = "gentle_nudge"
        case activeCheckin = "active_checkin"
        case crisisProtocol = "crisis_protocol"
        case familyAlert = "family_alert"
    }

    enum InterventionChannel: String, Codable {
        case push
        case inApp = "in_app"
        case sms
        case email
    }

    enum InterventionResponse: String, Codable {
        case accepted
        case dismissed
        case ignored
        case pending
    }
}

struct PredictionSettings: Codable {
    var predictionsEnabled: Bool
    var useMoodData: Bool
    var useChatSentiment: Bool
    var useBiometrics: Bool
    var useAppUsage: Bool
    var useSleepData: Bool
    var allowGentleNudges: Bool
    var allowActiveCheckins: Bool
    var preferredInterventionTime: Date?
    var allowFamilyAlerts: Bool
    var familyAlertThreshold: RiskLevel

    static var defaults: PredictionSettings {
        PredictionSettings(
            predictionsEnabled: true,
            useMoodData: true,
            useChatSentiment: true,
            useBiometrics: true,
            useAppUsage: true,
            useSleepData: true,
            allowGentleNudges: true,
            allowActiveCheckins: true,
            preferredInterventionTime: nil,
            allowFamilyAlerts: false,
            familyAlertThreshold: .high
        )
    }
}

struct DailySignals: Codable {
    let userId: UUID
    let signalDate: Date
    let moodAverage: Double?
    let moodMin: Int?
    let moodMax: Int?
    let moodVariance: Double?
    let moodTrend: Double?
    let appSessions: Int
    let totalActiveMinutes: Int
    let featuresUsed: [String]
    let questsCompleted: Int
    let exercisesCompleted: Int
    let chatMessagesSent: Int
    let circlePosts: Int
    let avgHrv: Double?
    let sleepHours: Double?
    let sleepQuality: Int?
    let activityMinutes: Int?
    let engagementScore: Int
    let socialScore: Int
    let biometricScore: Int?
}
```

### 4.3 Risk Scoring Algorithm

```typescript
// supabase/functions/calculate-risk-score/index.ts

interface DailySignals {
  mood_average: number | null;
  mood_trend: number | null;
  mood_variance: number | null;
  app_sessions: number;
  quests_completed: number;
  chat_messages_sent: number;
  circle_posts: number;
  avg_hrv: number | null;
  hrv_trend: number | null;
  sleep_hours: number | null;
  sleep_quality: number | null;
}

interface UserBaseline {
  avg_mood: number;
  avg_hrv: number;
  avg_app_sessions: number;
  avg_sleep_hours: number;
}

function calculateRiskScore(
  signals: DailySignals[],
  baseline: UserBaseline,
  settings: any,
): { score: number; factors: any } {
  const weights = {
    moodTrend: 25, // Most important
    moodVolatility: 15,
    engagement: 15,
    sleep: 15,
    biometrics: 15,
    social: 10,
    streak: 5,
  };

  let totalScore = 0;
  const factors: any = {};

  // Get most recent signals (last 7 days)
  const recent = signals.slice(-7);
  const today = signals[signals.length - 1];

  // 1. Mood Trend Score (0-25)
  if (today?.mood_trend !== null) {
    // Negative trend = higher risk
    const trendScore = Math.min(
      25,
      Math.max(0, (-today.mood_trend / 0.5) * 12.5 + 12.5),
    );
    totalScore += trendScore;
    factors.mood_trend = today.mood_trend;
  }

  // 2. Mood Volatility Score (0-15)
  if (today?.mood_variance !== null) {
    // High variance = higher risk
    const volatilityScore = Math.min(15, (today.mood_variance / 5) * 15);
    totalScore += volatilityScore;
    factors.mood_volatility = today.mood_variance;
  }

  // 3. Engagement Score (0-15)
  const avgRecentSessions =
    recent.reduce((sum, s) => sum + s.app_sessions, 0) / recent.length;
  const engagementDrop =
    (baseline.avg_app_sessions - avgRecentSessions) / baseline.avg_app_sessions;
  if (engagementDrop > 0) {
    const engagementScore = Math.min(15, engagementDrop * 30);
    totalScore += engagementScore;
    factors.app_engagement = -engagementDrop * 10;
  }

  // 4. Sleep Score (0-15)
  if (today?.sleep_quality !== null) {
    const sleepScore = Math.min(15, (5 - today.sleep_quality) * 3);
    totalScore += Math.max(0, sleepScore);
    factors.sleep_quality = today.sleep_quality - 3; // Relative to neutral
  }

  // 5. Biometric Score - HRV (0-15)
  if (today?.hrv_trend !== null && baseline.avg_hrv > 0) {
    const hrvDropPercent =
      (baseline.avg_hrv - (today.avg_hrv || 0)) / baseline.avg_hrv;
    if (hrvDropPercent > 0.1) {
      const hrvScore = Math.min(15, hrvDropPercent * 50);
      totalScore += hrvScore;
      factors.hrv_drop = -hrvDropPercent * 10;
    }
  }

  // 6. Social Score (0-10)
  const avgRecentPosts =
    recent.reduce((sum, s) => sum + s.circle_posts, 0) / recent.length;
  if (avgRecentPosts === 0 && baseline.avg_app_sessions > 1) {
    totalScore += 5; // Some social withdrawal
    factors.social_engagement = -5;
  }

  // 7. Streak Status (0-5)
  if (today?.quests_completed === 0) {
    totalScore += 5;
    factors.streak_broken = true;
  }

  // Normalize to 0-100
  const normalizedScore = Math.min(100, Math.round(totalScore));

  return {
    score: normalizedScore,
    factors,
  };
}

function classifyRiskLevel(score: number): string {
  if (score >= 76) return "crisis";
  if (score >= 51) return "high";
  if (score >= 26) return "medium";
  return "low";
}
```

### 4.4 Edge Functions

```typescript
// supabase/functions/run-risk-assessment/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // This function runs on a schedule (cron) for all users
  // Or can be triggered for a specific user

  const { user_id } = await req.json().catch(() => ({}));

  let usersToAssess: string[] = [];

  if (user_id) {
    usersToAssess = [user_id];
  } else {
    // Get all users with predictions enabled
    const { data: users } = await supabase
      .from("prediction_settings")
      .select("user_id")
      .eq("predictions_enabled", true);

    usersToAssess = users?.map((u) => u.user_id) || [];
  }

  const results = [];

  for (const userId of usersToAssess) {
    try {
      // 1. Fetch recent signals
      const { data: signals } = await supabase
        .from("daily_signals")
        .select("*")
        .eq("user_id", userId)
        .order("signal_date", { ascending: true })
        .limit(30);

      if (!signals || signals.length < 7) {
        continue; // Need at least 7 days of data
      }

      // 2. Calculate baseline (from older data)
      const baseline = calculateBaseline(signals.slice(0, -7));

      // 3. Calculate risk score
      const { score, factors } = calculateRiskScore(
        signals,
        baseline,
        {}, // settings
      );

      const riskLevel = classifyRiskLevel(score);

      // 4. Store assessment
      const { data: assessment } = await supabase
        .from("risk_assessments")
        .insert({
          user_id: userId,
          risk_score: score,
          risk_level: riskLevel,
          factors,
          model_version: "v1.0",
          confidence: 0.75,
        })
        .select()
        .single();

      // 5. Trigger intervention if needed
      if (riskLevel !== "low") {
        await triggerIntervention(supabase, userId, assessment);
      }

      results.push({ userId, score, riskLevel });
    } catch (error) {
      console.error(`Error assessing user ${userId}:`, error);
    }
  }

  return new Response(JSON.stringify({ assessed: results.length, results }), {
    headers: { "Content-Type": "application/json" },
  });
});

async function triggerIntervention(
  supabase: any,
  userId: string,
  assessment: any,
) {
  // Check user preferences
  const { data: settings } = await supabase
    .from("prediction_settings")
    .select("*")
    .eq("user_id", userId)
    .single();

  if (!settings) return;

  // Check rate limiting (1 per 24 hours unless crisis)
  const { data: recentInterventions } = await supabase
    .from("interventions")
    .select("id")
    .eq("user_id", userId)
    .gte(
      "scheduled_at",
      new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
    )
    .neq("intervention_type", "crisis_protocol");

  if (recentInterventions?.length > 0 && assessment.risk_level !== "crisis") {
    return; // Rate limited
  }

  let interventionType: string;
  let message: string;

  switch (assessment.risk_level) {
    case "crisis":
      interventionType = "crisis_protocol";
      message =
        "I'm concerned about you and want to make sure you're safe. Would you like to talk or connect with support resources?";
      break;
    case "high":
      if (!settings.allow_active_checkins) return;
      interventionType = "active_checkin";
      message =
        "Hey, I noticed things have been tough lately. I'm here for you – want to check in together?";
      break;
    case "medium":
      if (!settings.allow_gentle_nudges) return;
      interventionType = "gentle_nudge";
      message =
        "Just checking in 💙 Sometimes a small moment of reflection can help. Want to do a quick breathing exercise together?";
      break;
    default:
      return;
  }

  // Personalize message based on factors
  const topFactors = getTopFactors(assessment.factors);
  const personalization = {
    factors: topFactors.join(", "),
    user_name: await getUserName(supabase, userId),
  };

  // Schedule intervention
  await supabase.from("interventions").insert({
    user_id: userId,
    risk_assessment_id: assessment.id,
    intervention_type: interventionType,
    channel: "push",
    message_template: message,
    personalization,
    scheduled_at: new Date().toISOString(),
  });

  // Send push notification
  await supabase.functions.invoke("send-notification", {
    body: {
      user_id: userId,
      title: "MindFriend",
      body: message,
      data: {
        type: "intervention",
        intervention_id: assessment.id,
      },
    },
  });

  // Family alert for crisis
  if (assessment.risk_level === "crisis" && settings.allow_family_alerts) {
    await sendFamilyAlert(supabase, userId, assessment);
  }
}
```

---

## 5. UI/UX Specifications

### 5.1 Proactive Check-In Notification

```
┌─────────────────────────────────┐
│ MindFriend                  now │
│                                 │
│ Hey, I noticed things have been │
│ tough lately. I'm here for you  │
│ – want to check in together? 💙 │
│                                 │
│ [Let's Chat]    [Not Now]       │
│                                 │
└─────────────────────────────────┘
```

### 5.2 Intervention Response Screen (In-App)

```
┌─────────────────────────────────┐
│                            ✕    │
├─────────────────────────────────┤
│                                 │
│            💙                   │
│                                 │
│     I noticed some things       │
│     and wanted to check in      │
│                                 │
│  ┌─────────────────────────────┐│
│  │ • Mood has been lower       ││
│  │   than usual                ││
│  │ • Sleep quality dropped     ││
│  │ • Haven't chatted in        ││
│  │   a few days                ││
│  └─────────────────────────────┘│
│                                 │
│     How are you feeling         │
│     right now?                  │
│                                 │
│  😢  😕  😐  🙂  😊            │
│                                 │
│  ─────────────────────────────  │
│                                 │
│  What would help right now?     │
│                                 │
│  ┌────────────────────────────┐ │
│  │ 💬 Chat with me            │ │
│  └────────────────────────────┘ │
│  ┌────────────────────────────┐ │
│  │ 🌬️ Quick breathing exercise │ │
│  └────────────────────────────┘ │
│  ┌────────────────────────────┐ │
│  │ 📞 Call a friend           │ │
│  └────────────────────────────┘ │
│  ┌────────────────────────────┐ │
│  │ 🚨 Talk to someone now     │ │
│  └────────────────────────────┘ │
│                                 │
│  [I'm okay, just checking app]  │
│                                 │
└─────────────────────────────────┘
```

### 5.3 Prediction Insights (Settings)

```
┌─────────────────────────────────┐
│ ← Predictive Support            │
├─────────────────────────────────┤
│                                 │
│ Your Wellness Signals           │
│ MindFriend learns your patterns │
│ to offer proactive support.     │
│                                 │
│ ─────────────────────────────── │
│                                 │
│ Current Status                  │
│ ┌─────────────────────────────┐ │
│ │ 🟢 Looking Good              │ │
│ │ Your signals are positive    │ │
│ │ No concerns right now        │ │
│ └─────────────────────────────┘ │
│                                 │
│ Data Sources                    │
│ ┌─────────────────────────────┐ │
│ │ ✓ Mood check-ins       [•]  │ │
│ │ ✓ Chat conversations   [•]  │ │
│ │ ✓ App activity         [•]  │ │
│ │ ✓ Sleep data           [•]  │ │
│ │ ✓ Heart rate (HRV)     [•]  │ │
│ └─────────────────────────────┘ │
│                                 │
│ Intervention Preferences        │
│ ┌─────────────────────────────┐ │
│ │ Gentle nudges          [•]  │ │
│ │ Active check-ins       [•]  │ │
│ │ Best time to reach me       │ │
│ │ [Evening (6-9 PM)      ▼]   │ │
│ └─────────────────────────────┘ │
│                                 │
│ Family Alerts                   │
│ ┌─────────────────────────────┐ │
│ │ Allow family alerts    [ ]  │ │
│ │ If enabled, your family     │ │
│ │ admin will be notified if   │ │
│ │ you're at high risk.        │ │
│ └─────────────────────────────┘ │
│                                 │
│ [View My Prediction History]    │
│                                 │
└─────────────────────────────────┘
```

### 5.4 Crisis Intervention Screen

```
┌─────────────────────────────────┐
│                                 │
│                                 │
│            ❤️                    │
│                                 │
│     I'm here with you           │
│                                 │
│     It sounds like you're       │
│     going through something     │
│     really hard right now.      │
│                                 │
│     You're not alone.           │
│                                 │
│  ┌────────────────────────────┐ │
│  │ 📞 Call Crisis Line        │ │
│  │    988 (Available 24/7)    │ │
│  └────────────────────────────┘ │
│                                 │
│  ┌────────────────────────────┐ │
│  │ 💬 Text HOME to 741741     │ │
│  │    Crisis Text Line        │ │
│  └────────────────────────────┘ │
│                                 │
│  ┌────────────────────────────┐ │
│  │ 🗣️ Talk to MindFriend      │ │
│  │    I'm here to listen      │ │
│  └────────────────────────────┘ │
│                                 │
│                                 │
│  [I'm safe right now]           │
│                                 │
└─────────────────────────────────┘
```

---

## 6. Acceptance Criteria

### 6.1 Signal Collection

- [ ] Daily signals are computed each night at 11:59 PM user local time
- [ ] Mood data from past 7 days is aggregated correctly
- [ ] HealthKit data (HRV, sleep) is incorporated when authorized
- [ ] App usage patterns (sessions, features, engagement) are tracked
- [ ] Missing data is handled gracefully (partial signals still computed)

### 6.2 Risk Scoring

- [ ] Risk score (0-100) is calculated for users with 7+ days of data
- [ ] Risk level classification matches score ranges correctly
- [ ] Top contributing factors are identified and explainable
- [ ] Baseline is personalized to each user
- [ ] Model version is tracked for each assessment

### 6.3 Interventions

- [ ] No intervention sent for low risk
- [ ] Gentle nudge sent for medium risk (if enabled)
- [ ] Active check-in sent for high risk (if enabled)
- [ ] Crisis protocol triggered for crisis risk
- [ ] Interventions respect user's notification preferences
- [ ] Rate limiting prevents spam (max 1 per 24h unless crisis)
- [ ] Family alerts work for child accounts at high risk

### 6.4 User Experience

- [ ] Intervention notification deep links to response screen
- [ ] User can select from helpful action options
- [ ] User can dismiss without guilt ("I'm okay")
- [ ] Post-intervention mood is captured 24h later
- [ ] "Was this helpful?" feedback is collected

### 6.5 Privacy & Control

- [ ] User can disable predictive interventions
- [ ] User can view what signals are being tracked
- [ ] User can exclude specific data sources
- [ ] User can delete prediction history

---

## 7. Edge Cases & Error Handling

| Scenario                          | Behavior                                                |
| --------------------------------- | ------------------------------------------------------- |
| User has < 7 days of data         | Skip prediction; use engagement-based nudges instead    |
| Missing mood data                 | Weight other signals more heavily                       |
| Missing biometrics                | Score without biometric component                       |
| User disables predictions         | Stop all predictions; delete pending interventions      |
| Intervention goes unresponded 24h | Mark as "ignored"; factor into future predictions       |
| Risk spikes suddenly              | Allow immediate intervention despite rate limit         |
| User dismisses repeatedly         | Reduce frequency; ask if they want to adjust settings   |
| Family alert recipient blocked    | Log error; don't retry                                  |
| Model confidence very low         | Lower intervention threshold; add uncertainty messaging |

---

## 8. Security Considerations

| Area            | Requirement                                                     |
| --------------- | --------------------------------------------------------------- |
| Prediction Data | Encrypted at rest; RLS enforced                                 |
| Risk Scores     | Never shared with third parties                                 |
| Chat Sentiment  | Analyzed server-side; sentiment score only stored (not content) |
| Family Alerts   | Require explicit consent; minimal information shared            |
| Model Training  | Aggregate data only; no individual records                      |
| Export          | User can export own prediction history                          |
| Deletion        | User can delete all prediction data                             |

---

## 9. Performance Requirements

| Metric                       | Target                      |
| ---------------------------- | --------------------------- |
| Risk calculation latency     | < 5 seconds per user        |
| Batch processing (all users) | < 30 minutes for 100K users |
| Intervention delivery        | < 10 seconds from trigger   |
| Signal aggregation           | < 1 minute per user         |
| Model inference              | < 100ms                     |

---

## 10. Dependencies

### 10.1 Internal

| Dependency           | Reason                      |
| -------------------- | --------------------------- |
| Mood Service         | Primary signal source       |
| Chat Service         | Sentiment extraction        |
| HealthKit Service    | Biometric signals           |
| Notification Manager | Intervention delivery       |
| Crisis Resources     | Crisis protocol integration |
| Family Service       | Family alerts               |

### 10.2 External

| Dependency            | Reason                     |
| --------------------- | -------------------------- |
| Scheduled Jobs (Cron) | Daily risk assessment runs |
| ML Model (future)     | Advanced prediction model  |
| Clinical Validation   | Algorithm verification     |

---

## 11. Rollout Plan

### Phase 1: Foundation (Week 1-3)

- Database schema and migrations
- Signal aggregation job
- Basic risk scoring algorithm

### Phase 2: Interventions (Week 4-6)

- Intervention trigger logic
- Notification delivery
- Response capture

### Phase 3: Intelligence (Week 7-9)

- Model refinement based on outcomes
- Personalized baselines
- Factor explainability

### Phase 4: Polish (Week 10+)

- Family alerts
- Settings UI
- Feedback loops
- A/B testing infrastructure

---

## 12. Ethical Considerations

| Concern                          | Mitigation                                                |
| -------------------------------- | --------------------------------------------------------- |
| False positives cause anxiety    | Gentle messaging; allow easy dismissal                    |
| False negatives miss real crises | Supplement with keyword detection; err on side of caution |
| Over-reliance on app             | Encourage professional help; don't replace therapy        |
| Privacy of mental health data    | Strict data minimization; user control                    |
| Algorithm bias                   | Regular bias audits; diverse training data                |
| Notification fatigue             | Strict rate limiting; user control over frequency         |
