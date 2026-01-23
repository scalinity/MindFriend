# F025: Autonomous Wellness Agent

## Overview

### Summary

An intelligent, proactive AI agent that operates independently in the background, monitoring user patterns, anticipating needs, initiating wellness check-ins, and taking preventive actions without requiring user prompts—transforming the companion from reactive to genuinely proactive.

### Business Value

- Creates "magical" user experience that feels truly intelligent
- Dramatically increases engagement through proactive outreach
- Reduces churn by preventing wellness declines before they happen
- Positions MindFriend as next-generation AI wellness platform

### User Benefit

- AI companion that genuinely watches out for their wellbeing
- Timely interventions before problems escalate
- Reduced cognitive load—don't have to remember to check in
- Feeling of having a caring presence that notices patterns

### Dependencies

- F003 (Predictive Mood Intelligence) - Prediction engine for anticipation
- F004 (Companion Memory Enhancement) - Context and history awareness
- F014 (Contextual Micro-Interventions) - Intervention delivery
- Core Notification System - Proactive outreach

---

## Requirements

### Functional Requirements

| ID        | Requirement                                               | Priority |
| --------- | --------------------------------------------------------- | -------- |
| FR-025-01 | Monitor user patterns and detect concerning trends        | P0       |
| FR-025-02 | Initiate check-ins at optimal times without prompts       | P0       |
| FR-025-03 | Generate personalized proactive messages                  | P0       |
| FR-025-04 | Take preventive actions (queue exercises, adjust content) | P0       |
| FR-025-05 | Learn from user responses to improve timing               | P1       |
| FR-025-06 | Coordinate across multiple data signals                   | P1       |
| FR-025-07 | Respect quiet hours and user preferences                  | P1       |
| FR-025-08 | Explain reasoning for proactive actions                   | P2       |
| FR-025-09 | Allow user to adjust agent autonomy level                 | P2       |
| FR-025-10 | Generate weekly wellness reports autonomously             | P2       |

### Non-Functional Requirements

| ID         | Requirement                           | Target      |
| ---------- | ------------------------------------- | ----------- |
| NFR-025-01 | Pattern detection latency             | < 1 hour    |
| NFR-025-02 | Message personalization time          | < 5 seconds |
| NFR-025-03 | False positive rate for interventions | < 10%       |
| NFR-025-04 | User preference adherence             | 100%        |
| NFR-025-05 | Agent decision explainability         | Required    |
| NFR-025-06 | Battery impact from monitoring        | Negligible  |

### Acceptance Criteria (Gherkin)

```gherkin
Feature: Autonomous Wellness Agent

  Scenario: Agent detects mood decline trend
    Given the user's mood has decreased for 3 consecutive days
    And the agent is monitoring patterns
    When the trend is detected
    Then the agent initiates a gentle check-in
    And the message references the observed pattern
    And suggests relevant support options

  Scenario: Proactive morning briefing
    Given the user typically wakes at 7 AM
    And today has a predicted stressful event (calendar)
    When the optimal check-in time arrives
    Then the agent sends a supportive morning message
    And suggests a calming exercise before the event
    And offers to be available if needed

  Scenario: User hasn't logged mood in a while
    Given the user hasn't logged mood in 3 days
    And they typically log daily
    When the absence is detected
    Then the agent sends a caring check-in
    And makes logging easy (inline response)
    And doesn't pressure the user

  Scenario: Agent respects user autonomy settings
    Given the user has set autonomy to "minimal"
    When a concerning pattern is detected
    Then the agent only notifies within app
    And does not send push notifications
    And waits for user to open app

  Scenario: Agent explains its reasoning
    Given the agent has initiated a check-in
    When the user asks "why did you reach out?"
    Then the agent explains the pattern it noticed
    And references specific data points
    And reassures user about privacy
```

---

## Technical Design

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                   Autonomous Wellness Agent                      │
├─────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Agent Orchestrator                       │ │
│  │  • Decision Engine  • Action Planner  • Timing Optimizer   │ │
│  └───────────────────────────┬────────────────────────────────┘ │
├──────────────────────────────┼──────────────────────────────────┤
│                              │                                  │
│  ┌───────────────────────────▼───────────────────────────────┐  │
│  │                   Signal Aggregator                        │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │  │
│  │  │ Mood     │ │ Activity │ │ Calendar │ │ Biometric    │  │  │
│  │  │ Patterns │ │ Patterns │ │ Events   │ │ Signals      │  │  │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   Action Executors                         │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌────────────────────┐ │  │
│  │  │ Message      │ │ Content      │ │ Notification       │ │  │
│  │  │ Generator    │ │ Curator      │ │ Scheduler          │ │  │
│  │  └──────────────┘ └──────────────┘ └────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   Learning System                          │  │
│  │  • Response Tracking  • Timing Optimization  • Preference │  │
│  │    Learning            Refinement             Adaptation  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Database Schema

```sql
-- Agent configuration per user
CREATE TABLE agent_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    autonomy_level TEXT DEFAULT 'balanced' CHECK (autonomy_level IN (
        'minimal', 'balanced', 'proactive', 'guardian'
    )),
    enabled_signals TEXT[] DEFAULT ARRAY['mood', 'activity', 'streaks'],
    quiet_hours_start TIME DEFAULT '22:00',
    quiet_hours_end TIME DEFAULT '07:00',
    max_daily_outreach INTEGER DEFAULT 3,
    preferred_channels TEXT[] DEFAULT ARRAY['push', 'in_app'],
    explain_reasoning BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)
);

-- Detected patterns and signals
CREATE TABLE agent_signals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    signal_type TEXT NOT NULL CHECK (signal_type IN (
        'mood_decline', 'mood_improvement', 'activity_drop',
        'streak_risk', 'sleep_decline', 'stress_spike',
        'positive_momentum', 'upcoming_challenge', 'inactivity'
    )),
    severity TEXT DEFAULT 'low' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    confidence DECIMAL(3,2) NOT NULL,
    evidence JSONB NOT NULL DEFAULT '{}',
    detected_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ,
    is_resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMPTZ,
    resolution_type TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Planned and executed agent actions
CREATE TABLE agent_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    signal_id UUID REFERENCES agent_signals(id),
    action_type TEXT NOT NULL CHECK (action_type IN (
        'check_in', 'suggest_exercise', 'morning_briefing',
        'encouragement', 'streak_reminder', 'mood_prompt',
        'weekly_report', 'content_recommendation', 'concern_alert'
    )),
    status TEXT DEFAULT 'planned' CHECK (status IN (
        'planned', 'scheduled', 'delivered', 'opened',
        'responded', 'dismissed', 'cancelled'
    )),
    scheduled_for TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    content JSONB NOT NULL DEFAULT '{}',
    channel TEXT DEFAULT 'push',
    reasoning TEXT,
    user_response JSONB,
    effectiveness_score DECIMAL(3,2),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Agent learning data
CREATE TABLE agent_learnings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    learning_type TEXT NOT NULL CHECK (learning_type IN (
        'optimal_time', 'response_preference', 'content_preference',
        'signal_sensitivity', 'channel_preference', 'frequency_tolerance'
    )),
    learned_value JSONB NOT NULL,
    confidence DECIMAL(3,2) DEFAULT 0.5,
    sample_count INTEGER DEFAULT 0,
    last_updated TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, learning_type)
);

-- Agent decision audit log
CREATE TABLE agent_decisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    decision_type TEXT NOT NULL,
    inputs JSONB NOT NULL,
    reasoning TEXT NOT NULL,
    outcome TEXT NOT NULL,
    action_taken UUID REFERENCES agent_actions(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE agent_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_signals ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_learnings ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_decisions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own agent settings"
    ON agent_settings FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users view own signals"
    ON agent_signals FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users view own actions"
    ON agent_actions FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users view own learnings"
    ON agent_learnings FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users view own decisions"
    ON agent_decisions FOR SELECT
    USING (auth.uid() = user_id);

-- Indexes
CREATE INDEX idx_agent_signals_user ON agent_signals(user_id);
CREATE INDEX idx_agent_signals_active ON agent_signals(user_id)
    WHERE is_resolved = FALSE;
CREATE INDEX idx_agent_actions_user ON agent_actions(user_id);
CREATE INDEX idx_agent_actions_scheduled ON agent_actions(scheduled_for)
    WHERE status = 'scheduled';
```

### Swift Models

```swift
import Foundation

// MARK: - Agent Settings

struct AgentSettings: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var autonomyLevel: AutonomyLevel
    var enabledSignals: [SignalType]
    var quietHoursStart: String  // "HH:mm"
    var quietHoursEnd: String
    var maxDailyOutreach: Int
    var preferredChannels: [Channel]
    var explainReasoning: Bool
    let createdAt: Date
    var updatedAt: Date

    enum AutonomyLevel: String, Codable, CaseIterable {
        case minimal     // Only critical alerts
        case balanced    // Default, moderate proactivity
        case proactive   // More frequent check-ins
        case guardian    // Maximum care, frequent outreach

        var description: String {
            switch self {
            case .minimal: return "Only reach out for critical concerns"
            case .balanced: return "Balanced check-ins when helpful"
            case .proactive: return "Frequent supportive outreach"
            case .guardian: return "Maximum care and attention"
            }
        }

        var maxDailyActions: Int {
            switch self {
            case .minimal: return 1
            case .balanced: return 3
            case .proactive: return 5
            case .guardian: return 8
            }
        }
    }

    enum Channel: String, Codable {
        case push, inApp, sms, email
    }
}

// MARK: - Signal Models

struct AgentSignal: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let signalType: SignalType
    let severity: Severity
    let confidence: Double
    let evidence: SignalEvidence
    let detectedAt: Date
    let expiresAt: Date?
    var isResolved: Bool
    var resolvedAt: Date?
    var resolutionType: String?
    let createdAt: Date

    enum Severity: String, Codable {
        case low, medium, high, critical

        var color: String {
            switch self {
            case .low: return "green"
            case .medium: return "yellow"
            case .high: return "orange"
            case .critical: return "red"
            }
        }
    }
}

enum SignalType: String, Codable, CaseIterable {
    case moodDecline = "mood_decline"
    case moodImprovement = "mood_improvement"
    case activityDrop = "activity_drop"
    case streakRisk = "streak_risk"
    case sleepDecline = "sleep_decline"
    case stressSpike = "stress_spike"
    case positiveMomentum = "positive_momentum"
    case upcomingChallenge = "upcoming_challenge"
    case inactivity = "inactivity"

    var displayName: String {
        switch self {
        case .moodDecline: return "Mood Decline"
        case .moodImprovement: return "Mood Improvement"
        case .activityDrop: return "Activity Drop"
        case .streakRisk: return "Streak at Risk"
        case .sleepDecline: return "Sleep Quality Decline"
        case .stressSpike: return "Stress Increase"
        case .positiveMomentum: return "Positive Momentum"
        case .upcomingChallenge: return "Upcoming Challenge"
        case .inactivity: return "Extended Inactivity"
        }
    }

    var suggestedActions: [ActionType] {
        switch self {
        case .moodDecline: return [.checkIn, .suggestExercise]
        case .moodImprovement: return [.encouragement]
        case .activityDrop: return [.checkIn, .moodPrompt]
        case .streakRisk: return [.streakReminder]
        case .sleepDecline: return [.checkIn, .suggestExercise]
        case .stressSpike: return [.suggestExercise, .checkIn]
        case .positiveMomentum: return [.encouragement]
        case .upcomingChallenge: return [.morningBriefing, .suggestExercise]
        case .inactivity: return [.checkIn, .moodPrompt]
        }
    }
}

struct SignalEvidence: Codable {
    let dataPoints: [EvidencePoint]
    let trend: TrendInfo?
    let comparison: ComparisonInfo?
}

struct EvidencePoint: Codable {
    let metric: String
    let value: Double
    let timestamp: Date
    let context: String?
}

struct TrendInfo: Codable {
    let direction: String  // "up", "down", "stable"
    let magnitude: Double
    let durationDays: Int
}

struct ComparisonInfo: Codable {
    let baseline: Double
    let current: Double
    let percentChange: Double
}

// MARK: - Action Models

struct AgentAction: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let signalId: UUID?
    let actionType: ActionType
    var status: ActionStatus
    var scheduledFor: Date?
    var deliveredAt: Date?
    let content: ActionContent
    let channel: String
    let reasoning: String?
    var userResponse: UserResponse?
    var effectivenessScore: Double?
    let createdAt: Date
    var updatedAt: Date
}

enum ActionType: String, Codable {
    case checkIn = "check_in"
    case suggestExercise = "suggest_exercise"
    case morningBriefing = "morning_briefing"
    case encouragement = "encouragement"
    case streakReminder = "streak_reminder"
    case moodPrompt = "mood_prompt"
    case weeklyReport = "weekly_report"
    case contentRecommendation = "content_recommendation"
    case concernAlert = "concern_alert"

    var displayName: String {
        switch self {
        case .checkIn: return "Check-In"
        case .suggestExercise: return "Exercise Suggestion"
        case .morningBriefing: return "Morning Briefing"
        case .encouragement: return "Encouragement"
        case .streakReminder: return "Streak Reminder"
        case .moodPrompt: return "Mood Prompt"
        case .weeklyReport: return "Weekly Report"
        case .contentRecommendation: return "Content Recommendation"
        case .concernAlert: return "Concern Alert"
        }
    }
}

enum ActionStatus: String, Codable {
    case planned, scheduled, delivered, opened, responded, dismissed, cancelled
}

struct ActionContent: Codable {
    let title: String
    let body: String
    let quickActions: [QuickAction]?
    let deepLink: String?
    let metadata: [String: AnyCodable]?
}

struct QuickAction: Codable {
    let label: String
    let action: String
    let value: String?
}

struct UserResponse: Codable {
    let responseType: String
    let selectedAction: String?
    let timestamp: Date
    let sentiment: String?
}

// MARK: - Learning Models

struct AgentLearning: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let learningType: LearningType
    var learnedValue: [String: AnyCodable]
    var confidence: Double
    var sampleCount: Int
    var lastUpdated: Date
    let createdAt: Date

    enum LearningType: String, Codable {
        case optimalTime = "optimal_time"
        case responsePreference = "response_preference"
        case contentPreference = "content_preference"
        case signalSensitivity = "signal_sensitivity"
        case channelPreference = "channel_preference"
        case frequencyTolerance = "frequency_tolerance"
    }
}
```

### API Contracts

```typescript
// Edge Function: agent-process
// POST /functions/v1/agent-process (Cron-triggered)

interface AgentProcessRequest {
  user_ids?: string[]; // Optional, process all if empty
}

interface AgentProcessResponse {
  processed: number;
  signals_detected: number;
  actions_scheduled: number;
  errors: string[];
}

// Edge Function: agent-action-generate
// POST /functions/v1/agent-action-generate

interface GenerateActionRequest {
  user_id: string;
  signal_id: string;
  action_type: string;
}

interface GenerateActionResponse {
  action: {
    id: string;
    content: ActionContent;
    scheduled_for: string;
    reasoning: string;
  };
}

// REST API endpoints
// GET /rest/v1/agent_settings?user_id=eq.{userId}
// PUT /rest/v1/agent_settings

// GET /rest/v1/agent_signals?user_id=eq.{userId}&is_resolved=eq.false
// GET /rest/v1/agent_actions?user_id=eq.{userId}&order=created_at.desc

// PATCH /rest/v1/agent_actions?id=eq.{id}
interface UpdateActionRequest {
  status?: string;
  user_response?: UserResponse;
  effectiveness_score?: number;
}
```

---

## Implementation Details

### Step-by-Step Approach

1. **Phase 1: Signal Detection Engine** (Week 1)
   - Create pattern detection algorithms
   - Build signal aggregation system
   - Implement confidence scoring
   - Set up scheduled processing job

2. **Phase 2: Decision Engine** (Week 2)
   - Build action selection logic
   - Create timing optimization
   - Implement user preference filtering
   - Add quiet hours enforcement

3. **Phase 3: Message Generation** (Week 3)
   - Create personalized message templates
   - Build AI-powered message customization
   - Implement quick action system
   - Add reasoning explanations

4. **Phase 4: Delivery & Response** (Week 4)
   - Integrate with notification system
   - Build in-app action cards
   - Create response tracking
   - Implement effectiveness measurement

5. **Phase 5: Learning System** (Week 5)
   - Build response analysis
   - Create timing optimization ML
   - Implement preference learning
   - Add continuous improvement loop

### File Structure

```
apps/ios/MindFriendApp/Features/Agent/
├── AgentView.swift
├── AgentSettingsView.swift
├── AgentActivityView.swift
├── Models/
│   └── AgentModels.swift
├── Components/
│   ├── AgentActionCard.swift
│   ├── SignalIndicator.swift
│   └── ReasoningExplanationView.swift
└── Services/
    └── AgentService.swift

supabase/functions/
├── agent-process/
│   └── index.ts
├── agent-action-generate/
│   └── index.ts
├── agent-deliver/
│   └── index.ts
└── _shared/
    ├── signal-detectors.ts
    ├── action-templates.ts
    └── message-generator.ts
```

### Key Algorithms

#### Signal Detection Engine

```typescript
// supabase/functions/_shared/signal-detectors.ts

interface SignalDetectionResult {
  type: SignalType;
  severity: "low" | "medium" | "high" | "critical";
  confidence: number;
  evidence: SignalEvidence;
}

type SignalType =
  | "mood_decline"
  | "mood_improvement"
  | "activity_drop"
  | "streak_risk"
  | "inactivity"
  | "stress_spike"
  | "positive_momentum";

export async function detectSignals(
  supabase: any,
  userId: string,
): Promise<SignalDetectionResult[]> {
  const signals: SignalDetectionResult[] = [];

  // Parallel signal detection
  const [
    moodSignal,
    activitySignal,
    streakSignal,
    inactivitySignal,
    momentumSignal,
  ] = await Promise.all([
    detectMoodTrend(supabase, userId),
    detectActivityDrop(supabase, userId),
    detectStreakRisk(supabase, userId),
    detectInactivity(supabase, userId),
    detectPositiveMomentum(supabase, userId),
  ]);

  if (moodSignal) signals.push(moodSignal);
  if (activitySignal) signals.push(activitySignal);
  if (streakSignal) signals.push(streakSignal);
  if (inactivitySignal) signals.push(inactivitySignal);
  if (momentumSignal) signals.push(momentumSignal);

  return signals;
}

async function detectMoodTrend(
  supabase: any,
  userId: string,
): Promise<SignalDetectionResult | null> {
  const sevenDaysAgo = new Date();
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

  const { data: moods } = await supabase
    .from("moods")
    .select("score, created_at")
    .eq("user_id", userId)
    .gte("created_at", sevenDaysAgo.toISOString())
    .order("created_at", { ascending: true });

  if (!moods || moods.length < 3) return null;

  // Calculate trend using linear regression
  const n = moods.length;
  const xSum = moods.reduce((sum: number, _: any, i: number) => sum + i, 0);
  const ySum = moods.reduce((sum: number, m: any) => sum + m.score, 0);
  const xySum = moods.reduce(
    (sum: number, m: any, i: number) => sum + i * m.score,
    0,
  );
  const x2Sum = moods.reduce(
    (sum: number, _: any, i: number) => sum + i * i,
    0,
  );

  const slope = (n * xySum - xSum * ySum) / (n * x2Sum - xSum * xSum);
  const avgScore = ySum / n;

  // Detect significant decline
  if (slope < -0.3) {
    // Declining more than 0.3 points per entry
    const recentAvg =
      moods.slice(-3).reduce((sum: number, m: any) => sum + m.score, 0) / 3;
    const olderAvg =
      moods.slice(0, 3).reduce((sum: number, m: any) => sum + m.score, 0) / 3;
    const percentDrop = ((olderAvg - recentAvg) / olderAvg) * 100;

    return {
      type: "mood_decline",
      severity: percentDrop > 30 ? "high" : percentDrop > 15 ? "medium" : "low",
      confidence: Math.min(0.9, 0.5 + n * 0.05),
      evidence: {
        dataPoints: moods.map((m: any) => ({
          metric: "mood_score",
          value: m.score,
          timestamp: m.created_at,
        })),
        trend: {
          direction: "down",
          magnitude: Math.abs(slope),
          durationDays: Math.ceil(n / 2),
        },
        comparison: {
          baseline: olderAvg,
          current: recentAvg,
          percentChange: -percentDrop,
        },
      },
    };
  }

  return null;
}

async function detectActivityDrop(
  supabase: any,
  userId: string,
): Promise<SignalDetectionResult | null> {
  const fourteenDaysAgo = new Date();
  fourteenDaysAgo.setDate(fourteenDaysAgo.getDate() - 14);

  const { data: activities } = await supabase
    .from("exercise_sessions")
    .select("duration_seconds, created_at")
    .eq("user_id", userId)
    .gte("created_at", fourteenDaysAgo.toISOString());

  if (!activities) return null;

  const sevenDaysAgo = new Date();
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

  const thisWeek = activities.filter(
    (a: any) => new Date(a.created_at) >= sevenDaysAgo,
  );
  const lastWeek = activities.filter(
    (a: any) => new Date(a.created_at) < sevenDaysAgo,
  );

  const thisWeekTotal = thisWeek.reduce(
    (sum: number, a: any) => sum + a.duration_seconds,
    0,
  );
  const lastWeekTotal = lastWeek.reduce(
    (sum: number, a: any) => sum + a.duration_seconds,
    0,
  );

  if (lastWeekTotal > 0) {
    const dropPercent = ((lastWeekTotal - thisWeekTotal) / lastWeekTotal) * 100;

    if (dropPercent > 40) {
      return {
        type: "activity_drop",
        severity: dropPercent > 70 ? "high" : "medium",
        confidence: 0.75,
        evidence: {
          dataPoints: [
            {
              metric: "last_week_minutes",
              value: lastWeekTotal / 60,
              timestamp: fourteenDaysAgo.toISOString(),
            },
            {
              metric: "this_week_minutes",
              value: thisWeekTotal / 60,
              timestamp: new Date().toISOString(),
            },
          ],
          trend: {
            direction: "down",
            magnitude: dropPercent / 100,
            durationDays: 7,
          },
          comparison: {
            baseline: lastWeekTotal / 60,
            current: thisWeekTotal / 60,
            percentChange: -dropPercent,
          },
        },
      };
    }
  }

  return null;
}

async function detectStreakRisk(
  supabase: any,
  userId: string,
): Promise<SignalDetectionResult | null> {
  // Get user's current streak and typical completion time
  const { data: profile } = await supabase
    .from("profiles")
    .select("current_streak")
    .eq("id", userId)
    .single();

  if (!profile || profile.current_streak < 3) return null; // Not significant streak

  // Check today's quest status
  const today = new Date().toISOString().split("T")[0];
  const { data: todayQuest } = await supabase
    .from("quests")
    .select("*")
    .eq("user_id", userId)
    .eq("assigned_date", today)
    .single();

  if (!todayQuest || todayQuest.status === "completed") return null;

  // Check if it's getting late in user's day
  const now = new Date();
  const hourOfDay = now.getHours();

  if (hourOfDay >= 20) {
    // After 8 PM
    return {
      type: "streak_risk",
      severity: profile.current_streak > 14 ? "high" : "medium",
      confidence: 0.8,
      evidence: {
        dataPoints: [
          {
            metric: "current_streak",
            value: profile.current_streak,
            timestamp: now.toISOString(),
          },
          {
            metric: "hour_of_day",
            value: hourOfDay,
            timestamp: now.toISOString(),
          },
        ],
        trend: null,
        comparison: null,
      },
    };
  }

  return null;
}

async function detectInactivity(
  supabase: any,
  userId: string,
): Promise<SignalDetectionResult | null> {
  const { data: lastActivity } = await supabase
    .from("user_activity_log")
    .select("created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(1)
    .single();

  if (!lastActivity) return null;

  const daysSinceActivity = Math.floor(
    (Date.now() - new Date(lastActivity.created_at).getTime()) /
      (1000 * 60 * 60 * 24),
  );

  if (daysSinceActivity >= 3) {
    return {
      type: "inactivity",
      severity: daysSinceActivity >= 7 ? "high" : "medium",
      confidence: 0.9,
      evidence: {
        dataPoints: [
          {
            metric: "days_since_activity",
            value: daysSinceActivity,
            timestamp: lastActivity.created_at,
          },
        ],
        trend: null,
        comparison: null,
      },
    };
  }

  return null;
}

async function detectPositiveMomentum(
  supabase: any,
  userId: string,
): Promise<SignalDetectionResult | null> {
  const sevenDaysAgo = new Date();
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

  // Check for consistent positive indicators
  const [{ data: moods }, { data: exercises }, { data: profile }] =
    await Promise.all([
      supabase
        .from("moods")
        .select("score")
        .eq("user_id", userId)
        .gte("created_at", sevenDaysAgo.toISOString()),
      supabase
        .from("exercise_sessions")
        .select("id")
        .eq("user_id", userId)
        .gte("created_at", sevenDaysAgo.toISOString()),
      supabase
        .from("profiles")
        .select("current_streak")
        .eq("id", userId)
        .single(),
    ]);

  const avgMood = moods?.length
    ? moods.reduce((sum: number, m: any) => sum + m.score, 0) / moods.length
    : 0;
  const exerciseCount = exercises?.length || 0;
  const streak = profile?.current_streak || 0;

  // Positive momentum: good mood + regular exercises + healthy streak
  if (avgMood >= 3.5 && exerciseCount >= 3 && streak >= 5) {
    return {
      type: "positive_momentum",
      severity: "low",
      confidence: 0.7,
      evidence: {
        dataPoints: [
          {
            metric: "avg_mood",
            value: avgMood,
            timestamp: new Date().toISOString(),
          },
          {
            metric: "exercise_count",
            value: exerciseCount,
            timestamp: new Date().toISOString(),
          },
          {
            metric: "streak",
            value: streak,
            timestamp: new Date().toISOString(),
          },
        ],
        trend: { direction: "up", magnitude: 0.3, durationDays: 7 },
        comparison: null,
      },
    };
  }

  return null;
}
```

#### Message Generation

```typescript
// supabase/functions/_shared/message-generator.ts

interface MessageContext {
  user: {
    name: string;
    preferences: any;
    recentMood: number | null;
    streak: number;
  };
  signal: SignalDetectionResult;
  actionType: string;
  timeOfDay: "morning" | "afternoon" | "evening" | "night";
}

export async function generatePersonalizedMessage(
  context: MessageContext,
): Promise<ActionContent> {
  const template = getTemplateForAction(
    context.actionType,
    context.signal.type,
  );

  // Use AI for personalization
  const prompt = buildPrompt(template, context);

  const response = await fetch("https://api.x.ai/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${Deno.env.get("XAI_API_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "grok-beta",
      messages: [{ role: "user", content: prompt }],
      max_tokens: 200,
      temperature: 0.7,
    }),
  });

  const result = await response.json();
  const generatedContent = result.choices[0].message.content;

  return parseGeneratedMessage(generatedContent, context);
}

function getTemplateForAction(
  actionType: string,
  signalType: string,
): MessageTemplate {
  const templates: Record<string, MessageTemplate> = {
    "check_in:mood_decline": {
      titlePatterns: [
        "Hey {{name}}, just checking in",
        "{{name}}, I've been thinking about you",
        "A moment for you, {{name}}",
      ],
      bodyGuidance:
        "Express gentle concern about noticed mood pattern without being alarming. Offer support and an easy way to share how they're feeling.",
      quickActions: [
        { label: "I'm doing okay", action: "respond", value: "okay" },
        { label: "Could use support", action: "start_chat", value: null },
        { label: "Not now", action: "dismiss", value: null },
      ],
    },
    "check_in:inactivity": {
      titlePatterns: [
        "Miss you, {{name}}",
        "{{name}}, I'm here when you're ready",
        "Thinking of you",
      ],
      bodyGuidance:
        "Warm, non-judgmental message acknowledging absence. Make returning feel easy and welcoming.",
      quickActions: [
        { label: "Log today's mood", action: "mood_log", value: null },
        { label: "Quick exercise", action: "exercise", value: "quick" },
        { label: "Just browsing", action: "open_app", value: null },
      ],
    },
    "encouragement:positive_momentum": {
      titlePatterns: [
        "You're on a roll, {{name}}! 🌟",
        "{{name}}, your consistency is inspiring",
        "Look at you go!",
      ],
      bodyGuidance:
        "Celebrate their positive momentum with specific acknowledgment. Reinforce the behavior without pressure.",
      quickActions: [
        { label: "Thanks!", action: "acknowledge", value: null },
        { label: "Keep going", action: "open_app", value: null },
      ],
    },
    "streak_reminder:streak_risk": {
      titlePatterns: [
        "{{name}}, your {{streak}}-day streak is waiting",
        "Don't forget your streak!",
        "Quick reminder for {{name}}",
      ],
      bodyGuidance:
        "Friendly reminder about streak without being pushy. Emphasize how close they are to keeping it.",
      quickActions: [
        { label: "Complete quest", action: "quest", value: null },
        { label: "Quick check-in", action: "mood_log", value: null },
        { label: "Remind later", action: "snooze", value: "1h" },
      ],
    },
  };

  const key = `${actionType}:${signalType}`;
  return templates[key] || templates[actionType] || getDefaultTemplate();
}

function buildPrompt(
  template: MessageTemplate,
  context: MessageContext,
): string {
  return `You are a caring AI wellness companion. Generate a personalized notification message.

USER CONTEXT:
- Name: ${context.user.name}
- Recent mood: ${context.user.recentMood || "unknown"}
- Current streak: ${context.user.streak} days
- Time of day: ${context.timeOfDay}

SIGNAL DETECTED: ${context.signal.type}
Severity: ${context.signal.severity}
Evidence: ${JSON.stringify(context.signal.evidence)}

MESSAGE GUIDANCE:
${template.bodyGuidance}

CONSTRAINTS:
- Be warm but not overly cheerful if mood is low
- Keep message under 100 characters for body
- Sound natural, not robotic
- Reference specific pattern if relevant
- Don't be preachy or lecturing

Generate a JSON response with:
{
  "title": "short title (max 50 chars)",
  "body": "message body (max 100 chars)"
}`;
}

interface MessageTemplate {
  titlePatterns: string[];
  bodyGuidance: string;
  quickActions: QuickAction[];
}
```

#### Timing Optimization

```typescript
// supabase/functions/_shared/timing-optimizer.ts

interface DeliveryWindow {
  hour: number;
  score: number;
  reason: string;
}

export async function findOptimalDeliveryTime(
  supabase: any,
  userId: string,
  actionType: string,
): Promise<Date> {
  // Get user's learned preferences
  const { data: learning } = await supabase
    .from("agent_learnings")
    .select("*")
    .eq("user_id", userId)
    .eq("learning_type", "optimal_time")
    .single();

  // Get user's settings
  const { data: settings } = await supabase
    .from("agent_settings")
    .select("quiet_hours_start, quiet_hours_end")
    .eq("user_id", userId)
    .single();

  // Get historical response patterns
  const { data: actions } = await supabase
    .from("agent_actions")
    .select("delivered_at, status, action_type")
    .eq("user_id", userId)
    .eq("action_type", actionType)
    .in("status", ["opened", "responded", "dismissed"])
    .order("created_at", { ascending: false })
    .limit(20);

  const now = new Date();
  const windows = generateDeliveryWindows(now, settings, learning, actions);

  // Find best window
  const bestWindow = windows
    .filter((w) => isOutsideQuietHours(w.hour, settings))
    .sort((a, b) => b.score - a.score)[0];

  // Calculate actual delivery time
  const deliveryTime = new Date(now);
  if (bestWindow.hour <= now.getHours()) {
    deliveryTime.setDate(deliveryTime.getDate() + 1);
  }
  deliveryTime.setHours(bestWindow.hour, Math.floor(Math.random() * 30), 0, 0);

  return deliveryTime;
}

function generateDeliveryWindows(
  now: Date,
  settings: any,
  learning: any,
  historicalActions: any[],
): DeliveryWindow[] {
  const windows: DeliveryWindow[] = [];

  for (let hour = 7; hour <= 21; hour++) {
    let score = 50; // Base score

    // Learned preference boost
    if (learning?.learned_value?.preferred_hours?.includes(hour)) {
      score += 30;
    }

    // Historical success rate
    const actionsAtHour = historicalActions.filter(
      (a) => new Date(a.delivered_at).getHours() === hour,
    );
    const successRate =
      actionsAtHour.length > 0
        ? actionsAtHour.filter((a) => a.status === "responded").length /
          actionsAtHour.length
        : 0.5;
    score += successRate * 20;

    // Time-of-day patterns
    if (hour >= 8 && hour <= 10) score += 10; // Morning boost
    if (hour >= 18 && hour <= 20) score += 5; // Evening boost
    if (hour >= 12 && hour <= 14) score -= 5; // Lunch dip

    windows.push({
      hour,
      score,
      reason: `Score based on learned patterns and historical responses`,
    });
  }

  return windows;
}

function isOutsideQuietHours(hour: number, settings: any): boolean {
  if (!settings) return true;

  const start = parseInt(settings.quiet_hours_start?.split(":")[0] || "22");
  const end = parseInt(settings.quiet_hours_end?.split(":")[0] || "7");

  if (start > end) {
    // Quiet hours span midnight
    return hour < start && hour >= end;
  } else {
    return hour < start || hour >= end;
  }
}
```

---

## Dependencies

### Internal Dependencies

- F003 (Predictive Mood Intelligence) - Prediction capabilities
- F004 (Companion Memory Enhancement) - User context
- F014 (Contextual Micro-Interventions) - Delivery system
- Core Notification System - Push delivery

### External Dependencies

- xAI Grok API - Message personalization
- APNs - Push notification delivery
- Supabase Cron - Scheduled processing

### Infrastructure

- Supabase Edge Functions - Agent processing
- Supabase Database - Signal and action storage
- Background job scheduler - Pattern monitoring

---

## Edge Cases & Error Handling

| Scenario                         | Handling                                          |
| -------------------------------- | ------------------------------------------------- |
| User hasn't set preferences      | Use sensible defaults, learn from responses       |
| Conflicting signals detected     | Prioritize by severity, avoid message bombardment |
| User dismisses all messages      | Reduce frequency, ask for feedback                |
| Quiet hours span midnight        | Correctly handle time zone edge cases             |
| User in different time zone      | Detect and adjust to local time                   |
| Signal detection false positive  | Track and learn from dismissals                   |
| Message generation fails         | Use template fallback                             |
| User changes settings mid-action | Cancel pending actions, respect new settings      |
| Very high severity signal        | Bypass some limits, ensure delivery               |

---

## Testing Requirements

### Unit Tests

```swift
import XCTest
@testable import MindFriendApp

final class AgentTests: XCTestCase {

    func testAutonomyLevelMaxActions() {
        XCTAssertEqual(AgentSettings.AutonomyLevel.minimal.maxDailyActions, 1)
        XCTAssertEqual(AgentSettings.AutonomyLevel.balanced.maxDailyActions, 3)
        XCTAssertEqual(AgentSettings.AutonomyLevel.proactive.maxDailyActions, 5)
        XCTAssertEqual(AgentSettings.AutonomyLevel.guardian.maxDailyActions, 8)
    }

    func testSignalTypeSuggestedActions() {
        let moodDecline = SignalType.moodDecline
        XCTAssertTrue(moodDecline.suggestedActions.contains(.checkIn))
        XCTAssertTrue(moodDecline.suggestedActions.contains(.suggestExercise))

        let streakRisk = SignalType.streakRisk
        XCTAssertTrue(streakRisk.suggestedActions.contains(.streakReminder))
    }

    func testSeverityOrdering() {
        let signals = [
            AgentSignal.Severity.low,
            AgentSignal.Severity.critical,
            AgentSignal.Severity.medium,
            AgentSignal.Severity.high
        ]

        // Verify we can sort by severity
        let sorted = signals.sorted { s1, s2 in
            let order: [AgentSignal.Severity: Int] = [.low: 0, .medium: 1, .high: 2, .critical: 3]
            return order[s1]! > order[s2]!
        }

        XCTAssertEqual(sorted.first, .critical)
        XCTAssertEqual(sorted.last, .low)
    }

    func testActionStatusProgression() {
        let validProgressions: [(ActionStatus, ActionStatus)] = [
            (.planned, .scheduled),
            (.scheduled, .delivered),
            (.delivered, .opened),
            (.opened, .responded),
            (.delivered, .dismissed),
            (.scheduled, .cancelled)
        ]

        // All progressions should be valid enum values
        for (from, to) in validProgressions {
            XCTAssertNotEqual(from, to)
        }
    }
}
```

### Integration Tests

```swift
final class AgentIntegrationTests: XCTestCase {
    var service: AgentService!

    override func setUp() async throws {
        service = AgentService(supabase: TestSupabaseClient())
    }

    func testSignalDetectionAndActionCreation() async throws {
        // Seed declining mood data
        await seedDecliningMoodData()

        // Trigger agent processing
        let signals = try await service.detectSignals()
        XCTAssertFalse(signals.isEmpty)

        let moodSignal = signals.first { $0.signalType == .moodDecline }
        XCTAssertNotNil(moodSignal)

        // Generate action
        let action = try await service.createAction(
            forSignal: moodSignal!,
            actionType: .checkIn
        )

        XCTAssertNotNil(action.id)
        XCTAssertEqual(action.status, .scheduled)
        XCTAssertNotNil(action.scheduledFor)
    }

    func testUserResponseTracking() async throws {
        let action = try await createTestAction()

        // Simulate user response
        let updated = try await service.recordResponse(
            actionId: action.id,
            response: UserResponse(
                responseType: "quick_action",
                selectedAction: "start_chat",
                timestamp: Date(),
                sentiment: "positive"
            )
        )

        XCTAssertEqual(updated.status, .responded)
        XCTAssertNotNil(updated.userResponse)
    }

    func testQuietHoursEnforcement() async throws {
        // Set quiet hours
        try await service.updateSettings(
            quietHoursStart: "22:00",
            quietHoursEnd: "08:00"
        )

        // Create action
        let action = try await createTestAction()

        // Verify scheduled time is outside quiet hours
        let scheduledHour = Calendar.current.component(.hour, from: action.scheduledFor!)
        XCTAssertTrue(scheduledHour >= 8 && scheduledHour < 22)
    }
}
```

### UI Tests

```swift
final class AgentUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        app = XCUIApplication()
        app.launch()
    }

    func testAgentSettingsToggle() {
        navigateToAgentSettings()

        // Toggle autonomy level
        app.buttons["Autonomy Level"].tap()
        app.buttons["Proactive"].tap()

        XCTAssertTrue(app.staticTexts["Frequent supportive outreach"].exists)
    }

    func testAgentActivityView() {
        navigateToAgentSettings()
        app.buttons["View Activity"].tap()

        // Should show recent actions
        XCTAssertTrue(app.staticTexts["Recent Actions"].exists)
    }

    func testQuickActionFromNotification() {
        // Simulate receiving notification
        simulateAgentNotification()

        // Tap quick action
        let quickAction = app.buttons["Log today's mood"]
        XCTAssertTrue(quickAction.waitForExistence(timeout: 5))
        quickAction.tap()

        // Should navigate to mood logging
        XCTAssertTrue(app.staticTexts["How are you feeling?"].exists)
    }

    func testReasoningExplanation() {
        navigateToAgentSettings()
        app.buttons["View Activity"].tap()
        app.cells.firstMatch.tap()

        // Tap "Why did I get this?"
        app.buttons["Why did I get this?"].tap()

        // Should show reasoning
        XCTAssertTrue(app.staticTexts["I noticed"].exists)
    }

    private func navigateToAgentSettings() {
        app.tabBars["TabBar"].buttons["Settings"].tap()
        app.buttons["Agent Settings"].tap()
    }

    private func simulateAgentNotification() {
        // Implementation depends on test infrastructure
    }
}
```
