# F014: Contextual Micro-Interventions

## Overview

### Summary

Intelligent system that delivers brief, context-aware wellness prompts at optimal moments based on time of day, location, activity patterns, and emotional state predictions.

### Business Value

- Proactive engagement driving daily active usage
- Preventive support reducing crisis events
- Demonstrates AI intelligence differentiating from competitors

### User Benefit

- Right support at the right moment without asking
- Prevention of emotional spirals through timely intervention
- Feeling genuinely understood and cared for by the app

### Dependencies

- F003: Predictive Mood Intelligence (for mood prediction triggers)
- F001: Biometric Correlation Engine (for physiological triggers)
- F021: Ambient Wellness Presence (for widget delivery)

---

## Requirements

### Functional Requirements

| ID     | Requirement                                                                  | Priority    |
| ------ | ---------------------------------------------------------------------------- | ----------- |
| FR-001 | Deliver micro-interventions based on time patterns (morning, lunch, evening) | Must Have   |
| FR-002 | Trigger interventions based on predicted mood decline                        | Must Have   |
| FR-003 | Offer context-appropriate quick exercises (30s-2min)                         | Must Have   |
| FR-004 | Personalize intervention timing based on user responsiveness                 | Should Have |
| FR-005 | Location-aware interventions (commute, work, home)                           | Should Have |
| FR-006 | Biometric-triggered interventions (elevated heart rate, poor sleep)          | Should Have |
| FR-007 | Dismissable with single tap; respect "not now"                               | Must Have   |
| FR-008 | Track intervention effectiveness for optimization                            | Must Have   |
| FR-009 | Daily/weekly intervention frequency limits                                   | Must Have   |
| FR-010 | Integration with widgets and notifications                                   | Should Have |

### Non-Functional Requirements

| ID      | Requirement                                  | Target                  |
| ------- | -------------------------------------------- | ----------------------- |
| NFR-001 | Intervention selection latency               | < 500ms                 |
| NFR-002 | False positive rate (unwanted interventions) | < 20%                   |
| NFR-003 | Battery impact                               | < 1% additional drain   |
| NFR-004 | Notification delivery timing                 | Within 5 min of optimal |

### Acceptance Criteria

```gherkin
Feature: Contextual Micro-Interventions

Scenario: Morning routine intervention
  Given user typically wakes at 7:00 AM
  And it is now 7:15 AM
  When morning intervention window is reached
  Then gentle morning check-in notification should appear
  And notification should offer quick mood log option
  And positive morning affirmation should be included

Scenario: Predicted mood decline intervention
  Given predictive model detects likely mood decline in next 4 hours
  When confidence exceeds 70%
  Then proactive "armor" notification should be sent
  And quick breathing exercise should be offered
  And notification should acknowledge potential upcoming challenge

Scenario: Elevated heart rate intervention
  Given user's heart rate has been elevated for 15+ minutes
  And user is likely not exercising (based on motion data)
  When stress response is detected
  Then calming intervention should be delivered
  And 60-second grounding exercise should be offered

Scenario: Respecting user dismissal
  Given user dismissed last 3 interventions
  When next intervention would normally trigger
  Then intervention should be held
  And frequency should be reduced for 24 hours
  And preferences should be learned from pattern
```

---

## Technical Design

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    iOS Application                       │
├─────────────────────────────────────────────────────────┤
│  InterventionEngine                                     │
│  ├── Trigger evaluation                                 │
│  ├── Context gathering                                  │
│  ├── Intervention selection                             │
│  └── Delivery orchestration                             │
├─────────────────────────────────────────────────────────┤
│  TriggerMonitors                                        │
│  ├── TimeBasedTrigger                                   │
│  ├── LocationTrigger                                    │
│  ├── BiometricTrigger                                   │
│  └── PredictionTrigger                                  │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│              Supabase Edge Functions                     │
├─────────────────────────────────────────────────────────┤
│  select-intervention                                    │
│  ├── User context analysis                              │
│  ├── Intervention matching                              │
│  └── Personalization                                    │
├─────────────────────────────────────────────────────────┤
│  log-intervention-outcome                               │
│  └── Effectiveness tracking                             │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                  PostgreSQL Tables                       │
├─────────────────────────────────────────────────────────┤
│  interventions │ intervention_log │ user_intervention_prefs │
└─────────────────────────────────────────────────────────┘
```

### Data Models

#### Database Schema

```sql
-- Intervention definitions
CREATE TABLE interventions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN (
        'breathing', 'grounding', 'affirmation', 'prompt',
        'check_in', 'movement', 'reflection'
    )),
    trigger_contexts TEXT[] NOT NULL, -- ['morning', 'stress', 'predicted_decline']
    content JSONB NOT NULL,
    duration_seconds INTEGER NOT NULL,
    energy_required TEXT CHECK (energy_required IN ('low', 'medium', 'high')),
    is_premium BOOLEAN NOT NULL DEFAULT false,
    effectiveness_score DECIMAL(4,3) DEFAULT 0.5,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- User intervention preferences
CREATE TABLE user_intervention_prefs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Timing preferences
    morning_window_start TIME DEFAULT '07:00',
    morning_window_end TIME DEFAULT '09:00',
    evening_window_start TIME DEFAULT '18:00',
    evening_window_end TIME DEFAULT '21:00',

    -- Frequency limits
    max_daily_interventions INTEGER NOT NULL DEFAULT 5,
    max_hourly_interventions INTEGER NOT NULL DEFAULT 1,
    cooldown_after_dismiss_hours INTEGER NOT NULL DEFAULT 4,

    -- Type preferences
    preferred_types TEXT[] DEFAULT ARRAY['breathing', 'affirmation'],
    disabled_triggers TEXT[] DEFAULT ARRAY[],

    -- Learning parameters
    responsiveness_score DECIMAL(4,3) DEFAULT 0.5, -- How often they engage
    preferred_times JSONB DEFAULT '{}', -- Learned optimal times

    enabled BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Intervention delivery log
CREATE TABLE intervention_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    intervention_id UUID NOT NULL REFERENCES interventions(id),
    trigger_type TEXT NOT NULL,
    trigger_context JSONB NOT NULL,

    -- Delivery
    delivered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    delivery_method TEXT NOT NULL CHECK (delivery_method IN (
        'notification', 'widget', 'in_app', 'watch'
    )),

    -- Outcome
    seen_at TIMESTAMPTZ,
    engaged_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    dismissed_at TIMESTAMPTZ,
    outcome TEXT CHECK (outcome IN (
        'completed', 'partial', 'dismissed', 'ignored', 'deferred'
    )),

    -- Effectiveness
    mood_before INTEGER,
    mood_after INTEGER,
    user_rating INTEGER CHECK (user_rating BETWEEN 1 AND 5),
    feedback TEXT
);

-- Trigger events for analysis
CREATE TABLE intervention_triggers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    trigger_type TEXT NOT NULL,
    trigger_data JSONB NOT NULL,
    intervention_sent BOOLEAN NOT NULL DEFAULT false,
    suppression_reason TEXT, -- Why intervention wasn't sent
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_interventions_contexts ON interventions USING GIN (trigger_contexts);
CREATE INDEX idx_user_intervention_prefs ON user_intervention_prefs(user_id);
CREATE INDEX idx_intervention_log_user ON intervention_log(user_id, delivered_at DESC);
CREATE INDEX idx_intervention_log_outcome ON intervention_log(user_id, outcome);
CREATE INDEX idx_intervention_triggers ON intervention_triggers(user_id, created_at DESC);

-- RLS Policies
ALTER TABLE interventions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_intervention_prefs ENABLE ROW LEVEL SECURITY;
ALTER TABLE intervention_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE intervention_triggers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view interventions" ON interventions
    FOR SELECT USING (true);

CREATE POLICY "Users can manage own prefs" ON user_intervention_prefs
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view own intervention log" ON intervention_log
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view own triggers" ON intervention_triggers
    FOR SELECT USING (auth.uid() = user_id);
```

#### Intervention Seed Data

```sql
INSERT INTO interventions (key, name, type, trigger_contexts, content, duration_seconds, energy_required) VALUES
-- Morning interventions
('morning_breath', 'Morning Awakening Breath', 'breathing',
 ARRAY['morning'],
 '{"pattern": {"inhale": 4, "hold": 2, "exhale": 4}, "cycles": 3, "message": "Start your day with presence"}',
 45, 'low'),

('morning_intention', 'Set Your Intention', 'prompt',
 ARRAY['morning'],
 '{"prompt": "What''s one thing you want to focus on today?", "examples": ["Being patient", "Finding joy in small moments"]}',
 60, 'low'),

('morning_gratitude', 'Quick Gratitude', 'reflection',
 ARRAY['morning'],
 '{"prompt": "Name one thing you''re grateful for this morning", "affirmation": "Starting with gratitude sets a positive tone"}',
 30, 'low'),

-- Stress interventions
('stress_ground', '60-Second Grounding', 'grounding',
 ARRAY['stress', 'predicted_decline', 'elevated_hr'],
 '{"technique": "5-4-3-2-1", "abbreviated": true, "message": "Notice 5 things you can see right now"}',
 60, 'low'),

('stress_breath', 'Calm Breath', 'breathing',
 ARRAY['stress', 'predicted_decline', 'elevated_hr'],
 '{"pattern": {"inhale": 4, "hold": 0, "exhale": 6}, "cycles": 4, "message": "Extended exhales activate your calm response"}',
 45, 'low'),

('stress_pause', 'Mindful Pause', 'prompt',
 ARRAY['stress', 'predicted_decline'],
 '{"prompt": "Take a moment. What do you need right now?", "options": ["A break", "Support", "Movement", "Quiet"]}',
 30, 'low'),

-- Energy interventions
('low_energy_stretch', 'Desk Stretch', 'movement',
 ARRAY['low_energy', 'afternoon_slump'],
 '{"movements": [{"name": "Shoulder rolls", "duration": 15}, {"name": "Neck stretch", "duration": 15}]}',
 30, 'medium'),

('low_energy_breath', 'Energizing Breath', 'breathing',
 ARRAY['low_energy', 'afternoon_slump'],
 '{"pattern": {"inhale": 4, "hold": 4, "exhale": 4}, "cycles": 3, "message": "Equal breathing balances your energy"}',
 40, 'medium'),

-- Evening interventions
('evening_release', 'Release the Day', 'breathing',
 ARRAY['evening'],
 '{"pattern": {"inhale": 4, "hold": 0, "exhale": 8}, "cycles": 5, "message": "Let go of what you no longer need"}',
 60, 'low'),

('evening_reflect', 'Day Reflection', 'reflection',
 ARRAY['evening'],
 '{"prompt": "What went well today?", "followUp": "What would you do differently?"}',
 90, 'low'),

-- Affirmations
('affirmation_strength', 'You Are Capable', 'affirmation',
 ARRAY['stress', 'predicted_decline', 'morning'],
 '{"affirmation": "You have handled difficult things before. You can handle this too.", "followUp": "Take a breath and trust yourself."}',
 20, 'low'),

('affirmation_present', 'Be Here Now', 'affirmation',
 ARRAY['stress', 'distracted'],
 '{"affirmation": "This moment is all that exists right now. You are exactly where you need to be.", "followUp": "Notice your feet on the ground."}',
 20, 'low');
```

#### Swift Models

```swift
// MARK: - Intervention Models

struct Intervention: Codable, Identifiable {
    let id: UUID
    let key: String
    let name: String
    let type: InterventionType
    let triggerContexts: [String]
    let content: InterventionContent
    let durationSeconds: Int
    let energyRequired: EnergyLevel?
    let isPremium: Bool
    let effectivenessScore: Double
}

enum InterventionType: String, Codable {
    case breathing
    case grounding
    case affirmation
    case prompt
    case checkIn = "check_in"
    case movement
    case reflection

    var iconName: String {
        switch self {
        case .breathing: return "wind"
        case .grounding: return "leaf.fill"
        case .affirmation: return "heart.text.square.fill"
        case .prompt: return "bubble.left.fill"
        case .checkIn: return "face.smiling"
        case .movement: return "figure.walk"
        case .reflection: return "text.bubble"
        }
    }
}

enum EnergyLevel: String, Codable {
    case low, medium, high
}

enum InterventionContent: Codable {
    case breathing(BreathingIntervention)
    case grounding(GroundingIntervention)
    case affirmation(AffirmationIntervention)
    case prompt(PromptIntervention)
    case movement(MovementIntervention)
    case reflection(ReflectionIntervention)
}

struct BreathingIntervention: Codable {
    let pattern: SimpleBreathPattern
    let cycles: Int
    let message: String
}

struct SimpleBreathPattern: Codable {
    let inhale: Double
    let hold: Double
    let exhale: Double
}

struct GroundingIntervention: Codable {
    let technique: String
    let abbreviated: Bool
    let message: String
}

struct AffirmationIntervention: Codable {
    let affirmation: String
    let followUp: String?
}

struct PromptIntervention: Codable {
    let prompt: String
    let examples: [String]?
    let options: [String]?
}

struct MovementIntervention: Codable {
    let movements: [SimpleMovement]
}

struct SimpleMovement: Codable {
    let name: String
    let duration: Int
}

struct ReflectionIntervention: Codable {
    let prompt: String
    let followUp: String?
    let affirmation: String?
}

// User preferences
struct UserInterventionPrefs: Codable {
    let id: UUID
    let userId: UUID
    var morningWindowStart: Date
    var morningWindowEnd: Date
    var eveningWindowStart: Date
    var eveningWindowEnd: Date
    var maxDailyInterventions: Int
    var maxHourlyInterventions: Int
    var cooldownAfterDismissHours: Int
    var preferredTypes: [InterventionType]
    var disabledTriggers: [String]
    var responsivenessScore: Double
    var preferredTimes: [String: String]
    var enabled: Bool
}

// Log entry
struct InterventionLogEntry: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let interventionId: UUID
    let triggerType: String
    let triggerContext: [String: AnyCodable]
    let deliveredAt: Date
    let deliveryMethod: DeliveryMethod
    var seenAt: Date?
    var engagedAt: Date?
    var completedAt: Date?
    var dismissedAt: Date?
    var outcome: InterventionOutcome?
    var moodBefore: Int?
    var moodAfter: Int?
    var userRating: Int?
    var feedback: String?
}

enum DeliveryMethod: String, Codable {
    case notification
    case widget
    case inApp = "in_app"
    case watch
}

enum InterventionOutcome: String, Codable {
    case completed
    case partial
    case dismissed
    case ignored
    case deferred
}

// Trigger context
struct TriggerContext {
    let type: TriggerType
    let confidence: Double
    let data: [String: Any]

    enum TriggerType: String {
        case morning
        case evening
        case afternoonSlump = "afternoon_slump"
        case stress
        case predictedDecline = "predicted_decline"
        case elevatedHR = "elevated_hr"
        case lowEnergy = "low_energy"
        case location
    }
}
```

### API Contracts

#### Select Intervention

```
POST /functions/v1/select-intervention

Request:
{
  "triggerType": "stress",
  "triggerContext": {
    "confidence": 0.85,
    "heartRate": 95,
    "predictedMoodChange": -1.5
  },
  "deliveryMethod": "notification"
}

Response 200:
{
  "intervention": {
    "id": "uuid",
    "key": "stress_breath",
    "name": "Calm Breath",
    "type": "breathing",
    "content": {...},
    "durationSeconds": 45
  },
  "personalization": {
    "message": "I noticed your heart rate is elevated. Here's a quick calming breath.",
    "userName": "Sarah"
  },
  "delivery": {
    "notificationTitle": "Take a breath 🌬️",
    "notificationBody": "45 seconds to feel calmer"
  }
}

Response 200 (suppressed):
{
  "intervention": null,
  "suppression": {
    "reason": "cooldown_active",
    "cooldownEndsAt": "2024-01-15T14:00:00Z"
  }
}
```

#### Log Intervention Outcome

```
POST /rest/v1/intervention_log

Request:
{
  "intervention_id": "uuid",
  "trigger_type": "stress",
  "trigger_context": {...},
  "delivery_method": "notification",
  "outcome": "completed",
  "mood_before": 3,
  "mood_after": 5,
  "user_rating": 4
}
```

---

## Implementation Details

### Step-by-Step Approach

1. **Trigger Monitor Setup**
   - Time-based monitor for morning/evening windows
   - Background health monitoring for HR
   - Location services for context
   - Integration with prediction engine

2. **Intervention Selection Engine**
   - Load user preferences
   - Filter by trigger context
   - Score interventions by effectiveness + personalization
   - Apply frequency limits

3. **Delivery System**
   - Push notification formatting
   - Widget update for quick access
   - In-app modal for foreground delivery
   - Watch notification for wrist

4. **Outcome Tracking**
   - Track notification open
   - Track engagement vs dismissal
   - Optional mood check before/after
   - Feedback collection

5. **Learning Loop**
   - Analyze intervention effectiveness
   - Learn optimal delivery times
   - Adjust frequency based on responsiveness
   - Personalize intervention selection

### File Structure

```
apps/ios/MindFriendApp/
├── Features/
│   └── Interventions/
│       ├── InterventionEngine.swift
│       ├── Triggers/
│       │   ├── TriggerMonitor.swift
│       │   ├── TimeBasedTrigger.swift
│       │   ├── BiometricTrigger.swift
│       │   ├── LocationTrigger.swift
│       │   └── PredictionTrigger.swift
│       ├── Views/
│       │   ├── InterventionModalView.swift
│       │   ├── MiniInterventionView.swift
│       │   ├── InterventionPrefsView.swift
│       │   └── Players/
│       │       ├── QuickBreathingView.swift
│       │       ├── QuickGroundingView.swift
│       │       └── AffirmationView.swift
│       └── Delivery/
│           ├── NotificationDelivery.swift
│           └── WidgetDelivery.swift
│
supabase/
├── functions/
│   ├── select-intervention/
│   └── log-intervention-outcome/
├── migrations/
│   └── YYYYMMDD_interventions.sql
```

### Key Algorithms

#### Intervention Selection (TypeScript)

```typescript
interface SelectionContext {
  userId: string;
  triggerType: string;
  triggerContext: Record<string, any>;
  deliveryMethod: string;
  currentTime: Date;
}

async function selectIntervention(
  supabase: SupabaseClient,
  context: SelectionContext,
): Promise<InterventionResult | null> {
  const { userId, triggerType, currentTime } = context;

  // Load user preferences
  const { data: prefs } = await supabase
    .from("user_intervention_prefs")
    .select("*")
    .eq("user_id", userId)
    .single();

  if (!prefs?.enabled) {
    return null;
  }

  // Check frequency limits
  const limitCheck = await checkFrequencyLimits(
    supabase,
    userId,
    prefs,
    currentTime,
  );
  if (!limitCheck.allowed) {
    return { intervention: null, suppression: limitCheck.reason };
  }

  // Check cooldown from recent dismissals
  const cooldownCheck = await checkCooldown(supabase, userId, prefs);
  if (!cooldownCheck.allowed) {
    return { intervention: null, suppression: cooldownCheck.reason };
  }

  // Get matching interventions
  const { data: interventions } = await supabase
    .from("interventions")
    .select("*")
    .contains("trigger_contexts", [triggerType]);

  // Filter by user preferences
  const filtered = interventions?.filter((i) => {
    // Check if type is preferred
    if (
      prefs.preferred_types.length > 0 &&
      !prefs.preferred_types.includes(i.type)
    ) {
      return false;
    }
    // Check premium access
    if (i.is_premium && !(await hasPremium(userId))) {
      return false;
    }
    return true;
  });

  if (!filtered?.length) {
    return null;
  }

  // Score and rank interventions
  const scored = await scoreInterventions(supabase, userId, filtered, context);

  // Select best intervention
  const selected = scored[0];

  // Get personalization
  const personalization = await personalizeIntervention(
    supabase,
    userId,
    selected,
    context,
  );

  // Log trigger event
  await supabase.from("intervention_triggers").insert({
    user_id: userId,
    trigger_type: triggerType,
    trigger_data: context.triggerContext,
    intervention_sent: true,
  });

  return {
    intervention: selected,
    personalization,
    delivery: formatForDelivery(
      selected,
      personalization,
      context.deliveryMethod,
    ),
  };
}

async function scoreInterventions(
  supabase: SupabaseClient,
  userId: string,
  interventions: Intervention[],
  context: SelectionContext,
): Promise<ScoredIntervention[]> {
  // Get user's intervention history
  const { data: history } = await supabase
    .from("intervention_log")
    .select("intervention_id, outcome, user_rating")
    .eq("user_id", userId)
    .order("delivered_at", { ascending: false })
    .limit(50);

  // Calculate scores
  return interventions
    .map((intervention) => {
      let score = intervention.effectiveness_score;

      // Boost based on personal history
      const userHistory = history?.filter(
        (h) => h.intervention_id === intervention.id,
      );
      if (userHistory?.length) {
        const completionRate =
          userHistory.filter((h) => h.outcome === "completed").length /
          userHistory.length;
        const avgRating =
          userHistory.reduce((sum, h) => sum + (h.user_rating || 3), 0) /
          userHistory.length;

        score += completionRate * 0.2;
        score += (avgRating - 3) * 0.1; // Boost for high ratings
      }

      // Penalize recently used
      const recentUse = history?.find(
        (h) =>
          h.intervention_id === intervention.id &&
          Date.now() - new Date(h.delivered_at).getTime() < 24 * 60 * 60 * 1000,
      );
      if (recentUse) {
        score -= 0.3;
      }

      // Match energy to time of day
      const hour = context.currentTime.getHours();
      if (hour < 10 && intervention.energy_required === "low") {
        score += 0.1; // Gentle in morning
      }
      if (
        hour >= 14 &&
        hour <= 16 &&
        intervention.energy_required === "medium"
      ) {
        score += 0.1; // Energizing afternoon
      }

      return { intervention, score };
    })
    .sort((a, b) => b.score - a.score);
}

async function checkFrequencyLimits(
  supabase: SupabaseClient,
  userId: string,
  prefs: UserInterventionPrefs,
  currentTime: Date,
): Promise<{ allowed: boolean; reason?: SuppressionReason }> {
  const todayStart = new Date(currentTime);
  todayStart.setHours(0, 0, 0, 0);

  const hourAgo = new Date(currentTime.getTime() - 60 * 60 * 1000);

  // Check daily limit
  const { count: dailyCount } = await supabase
    .from("intervention_log")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("delivered_at", todayStart.toISOString());

  if ((dailyCount || 0) >= prefs.max_daily_interventions) {
    return { allowed: false, reason: { type: "daily_limit_reached" } };
  }

  // Check hourly limit
  const { count: hourlyCount } = await supabase
    .from("intervention_log")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("delivered_at", hourAgo.toISOString());

  if ((hourlyCount || 0) >= prefs.max_hourly_interventions) {
    return {
      allowed: false,
      reason: {
        type: "hourly_limit_reached",
        cooldownEndsAt: new Date(currentTime.getTime() + 60 * 60 * 1000),
      },
    };
  }

  return { allowed: true };
}
```

#### iOS Trigger Monitor (Swift)

```swift
class InterventionEngine: ObservableObject {
    private let supabase: SupabaseClient
    private var monitors: [TriggerMonitor] = []

    @Published var pendingIntervention: Intervention?

    init(supabase: SupabaseClient) {
        self.supabase = supabase
        setupMonitors()
    }

    private func setupMonitors() {
        monitors = [
            TimeBasedTrigger(delegate: self),
            BiometricTrigger(delegate: self),
            PredictionTrigger(delegate: self)
        ]

        monitors.forEach { $0.start() }
    }

    func handleTrigger(_ trigger: TriggerContext) async {
        // Request intervention selection from server
        do {
            let result = try await supabase.functions.invoke(
                "select-intervention",
                options: .init(body: [
                    "triggerType": trigger.type.rawValue,
                    "triggerContext": trigger.data,
                    "deliveryMethod": determineDeliveryMethod()
                ])
            )

            guard let intervention = result.intervention else {
                // Suppressed - log reason
                return
            }

            await MainActor.run {
                deliverIntervention(intervention, context: result)
            }
        } catch {
            print("Intervention selection failed: \(error)")
        }
    }

    private func determineDeliveryMethod() -> String {
        if UIApplication.shared.applicationState == .active {
            return "in_app"
        } else {
            return "notification"
        }
    }

    private func deliverIntervention(_ intervention: Intervention, context: InterventionResult) {
        switch context.delivery.method {
        case "in_app":
            pendingIntervention = intervention
        case "notification":
            scheduleNotification(intervention, context: context)
        case "widget":
            updateWidget(intervention)
        default:
            break
        }
    }
}

class TimeBasedTrigger: TriggerMonitor {
    weak var delegate: TriggerMonitorDelegate?
    private var timer: Timer?

    func start() {
        // Check every 5 minutes
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.checkTimeWindows()
        }
    }

    private func checkTimeWindows() {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        // Morning window check (7:00 - 7:30)
        if hour == 7 && minute >= 0 && minute <= 30 {
            if !hasDeliveredToday(type: .morning) {
                delegate?.triggerActivated(TriggerContext(
                    type: .morning,
                    confidence: 1.0,
                    data: ["hour": hour, "minute": minute]
                ))
            }
        }

        // Evening window check (20:00 - 21:00)
        if hour >= 20 && hour < 21 {
            if !hasDeliveredToday(type: .evening) {
                delegate?.triggerActivated(TriggerContext(
                    type: .evening,
                    confidence: 1.0,
                    data: ["hour": hour, "minute": minute]
                ))
            }
        }
    }
}

class BiometricTrigger: TriggerMonitor {
    weak var delegate: TriggerMonitorDelegate?
    private var healthStore: HKHealthStore?
    private var query: HKObserverQuery?

    func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        healthStore = HKHealthStore()
        startHeartRateMonitoring()
    }

    private func startHeartRateMonitoring() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        let query = HKObserverQuery(sampleType: heartRateType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }

            self?.checkHeartRate()
            completionHandler()
        }

        healthStore?.execute(query)
        self.query = query
    }

    private func checkHeartRate() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: heartRateType,
            predicate: HKQuery.predicateForSamples(
                withStart: Date().addingTimeInterval(-15 * 60), // Last 15 minutes
                end: Date(),
                options: .strictEndDate
            ),
            limit: 10,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else { return }

            let avgHR = samples.reduce(0.0) { sum, sample in
                sum + sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
            } / Double(samples.count)

            // Check for elevated HR when not exercising
            if avgHR > 90 && !self!.isLikelyExercising() {
                self?.delegate?.triggerActivated(TriggerContext(
                    type: .elevatedHR,
                    confidence: min(1.0, (avgHR - 90) / 30), // Scales with HR elevation
                    data: ["heartRate": avgHR, "sampleCount": samples.count]
                ))
            }
        }

        healthStore?.execute(query)
    }
}
```

---

## Dependencies

### Internal Dependencies

- **F003 Predictive Mood Intelligence**: For prediction-based triggers
- **F001 Biometric Correlation Engine**: For HR and biometric data
- **F021 Ambient Wellness Presence**: For widget delivery
- **Notification system**: For push delivery

### External Dependencies

- HealthKit for biometric monitoring
- CoreLocation for location context (optional)

### Infrastructure Requirements

- Background app refresh for trigger monitoring
- Push notification delivery
- WidgetKit for widget updates

---

## Edge Cases & Error Handling

| Scenario                               | Handling                                    |
| -------------------------------------- | ------------------------------------------- |
| User in Do Not Disturb mode            | Respect DND; defer intervention             |
| Multiple triggers fire simultaneously  | Prioritize highest confidence; queue others |
| User dismisses 5+ in a row             | Pause interventions; ask if want to disable |
| No network for intervention selection  | Use cached interventions                    |
| HealthKit access denied                | Disable biometric triggers only             |
| Location access denied                 | Disable location triggers only              |
| User manually opens app during trigger | Cancel notification; show in-app            |
| Intervention content fails to load     | Use simpler text-only fallback              |

---

## Testing Requirements

### Unit Tests

```swift
// InterventionEngineTests.swift

func testFrequencyLimitEnforcement() async throws {
    let engine = InterventionEngine(supabase: mockSupabase)

    // Simulate 5 interventions today
    mockSupabase.setTodayInterventionCount(5)

    let result = await engine.checkCanDeliver()

    XCTAssertFalse(result.allowed)
    XCTAssertEqual(result.reason, .dailyLimitReached)
}

func testCooldownAfterDismissal() async throws {
    let engine = InterventionEngine(supabase: mockSupabase)

    // Simulate recent dismissal
    mockSupabase.setLastDismissal(Date().addingTimeInterval(-2 * 3600)) // 2 hours ago
    mockSupabase.setCooldownHours(4)

    let result = await engine.checkCanDeliver()

    XCTAssertFalse(result.allowed)
    XCTAssertEqual(result.reason, .cooldownActive)
}

func testTimeWindowDetection() {
    let trigger = TimeBasedTrigger(delegate: nil)

    // Mock time as 7:15 AM
    let context = trigger.evaluateTimeWindow(hour: 7, minute: 15)

    XCTAssertEqual(context?.type, .morning)
    XCTAssertEqual(context?.confidence, 1.0)
}

func testHeartRateTriggerThreshold() {
    let trigger = BiometricTrigger(delegate: nil)

    // Below threshold
    XCTAssertNil(trigger.evaluateHeartRate(avgHR: 85, isExercising: false))

    // Above threshold
    let context = trigger.evaluateHeartRate(avgHR: 100, isExercising: false)
    XCTAssertNotNil(context)
    XCTAssertEqual(context?.type, .elevatedHR)
}

func testExercisingExcludesHRTrigger() {
    let trigger = BiometricTrigger(delegate: nil)

    let context = trigger.evaluateHeartRate(avgHR: 150, isExercising: true)

    XCTAssertNil(context) // Should not trigger during exercise
}
```

### Integration Tests

```typescript
// supabase/functions/select-intervention/test.ts

Deno.test("selects appropriate intervention for stress trigger", async () => {
  const userId = await createTestUser();
  await setInterventionPrefs(userId, { preferredTypes: ["breathing"] });

  const result = await invokeFunction(
    "select-intervention",
    {
      triggerType: "stress",
      triggerContext: { confidence: 0.8 },
      deliveryMethod: "notification",
    },
    userId,
  );

  assertExists(result.intervention);
  assertEquals(result.intervention.type, "breathing");
  assert(result.intervention.trigger_contexts.includes("stress"));
});

Deno.test("respects daily limit", async () => {
  const userId = await createTestUser();
  await setInterventionPrefs(userId, { maxDailyInterventions: 3 });
  await createInterventionLogs(userId, 3); // Already at limit

  const result = await invokeFunction(
    "select-intervention",
    {
      triggerType: "morning",
      triggerContext: {},
      deliveryMethod: "notification",
    },
    userId,
  );

  assertEquals(result.intervention, null);
  assertEquals(result.suppression.type, "daily_limit_reached");
});

Deno.test("avoids recently used interventions", async () => {
  const userId = await createTestUser();
  const recentInterventionId = await logIntervention(userId, "stress_breath");

  const result = await invokeFunction(
    "select-intervention",
    {
      triggerType: "stress",
      triggerContext: {},
      deliveryMethod: "notification",
    },
    userId,
  );

  // Should select different intervention
  assertNotEquals(result.intervention.key, "stress_breath");
});
```
