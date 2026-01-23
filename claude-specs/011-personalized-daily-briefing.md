# F009: Personalized Daily Briefing

> **Feature ID:** F009
> **Phase:** 2 - Engagement
> **Priority:** P0 (Critical)
> **Dependencies:** F002 (Daily Wellness Score), F003 (Predictive Mood Intelligence)
> **Dependents:** F025

---

## 1. Overview

### 1.1 Summary

Personalized Daily Briefing delivers a synthesized morning notification and home screen card that combines: predicted mood outlook, today's quest, relevant life context (calendar events, important dates), wellness score trajectory, and one personalized proactive suggestion. Optionally voice-enabled for hands-free morning routines.

### 1.2 Business Value

- **User Value:** Start every day with clarity and intention; one place for everything relevant
- **Product Value:** Creates daily ritual that increases open rates and DAU
- **Competitive Value:** Most wellness apps require you to hunt for information; this brings it to you

### 1.3 User Benefit

Users begin each day with a personalized synthesis of what matters—mood outlook, daily focus, and proactive suggestions—reducing friction to engagement.

---

## 2. Requirements

### 2.1 Functional Requirements

| ID     | Requirement                                                                         | Priority |
| ------ | ----------------------------------------------------------------------------------- | -------- |
| FR-001 | Generate daily briefing synthesizing wellness score, prediction, quest, and context | Must     |
| FR-002 | Deliver as push notification at user's preferred wake time                          | Must     |
| FR-003 | Display as expandable card on home screen                                           | Must     |
| FR-004 | Include personalized greeting based on time and mood context                        | Must     |
| FR-005 | Include today's quest with estimated time                                           | Must     |
| FR-006 | Include mood prediction if available (with confidence)                              | Should   |
| FR-007 | Include relevant upcoming events from calendar (if connected)                       | Should   |
| FR-008 | Include upcoming important dates from companion memory                              | Should   |
| FR-009 | Provide one actionable suggestion based on context                                  | Must     |
| FR-010 | Support voice read-aloud of briefing                                                | Should   |
| FR-011 | Allow customization of briefing components                                          | Should   |

### 2.2 Non-Functional Requirements

| ID      | Requirement                    | Target                         |
| ------- | ------------------------------ | ------------------------------ |
| NFR-001 | Briefing generation time       | < 3 seconds                    |
| NFR-002 | Notification delivery accuracy | Within 5 min of scheduled time |
| NFR-003 | Voice briefing length          | < 60 seconds                   |

### 2.3 Acceptance Criteria

1. **AC-001:** User receives notification at 7am (their time): "Good morning! Here's your wellness brief"
2. **AC-002:** Briefing card shows: wellness score (73), mood outlook (moderate), today's quest (5-min breathing)
3. **AC-003:** If calendar connected and meeting at 2pm, briefing mentions it
4. **AC-004:** If birthday in companion memory, briefing mentions "Sarah's birthday in 2 days"
5. **AC-005:** Suggestion is contextual: "Based on your sleep, a short grounding might help today"
6. **AC-006:** User can tap play button to hear briefing read aloud

---

## 3. Technical Design

### 3.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                          iOS App                                 │
├─────────────────────────────────────────────────────────────────┤
│  DailyBriefingService                                           │
│  ├─ generateBriefing()                                          │
│  ├─ scheduleBriefingNotification()                              │
│  ├─ getBriefingAudio()                                          │
│  └─ updateBriefingPreferences()                                 │
│                                                                  │
│  Views:                                                          │
│  ├─ DailyBriefingCard                                           │
│  ├─ BriefingExpandedView                                        │
│  └─ BriefingSettingsView                                        │
├─────────────────────────────────────────────────────────────────┤
│                        Supabase                                  │
├─────────────────────────────────────────────────────────────────┤
│  Tables:                      Edge Functions:                    │
│  ├─ daily_briefings           ├─ generate-daily-briefing        │
│  └─ briefing_preferences      └─ send-briefing-notification     │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Data Models

#### 3.2.1 Database Schema

```sql
-- Daily briefings
CREATE TABLE daily_briefings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    local_date DATE NOT NULL,

    -- Greeting
    greeting TEXT NOT NULL,
    time_of_day VARCHAR(16) NOT NULL, -- 'morning', 'afternoon', 'evening'

    -- Core components
    wellness_score INT,
    wellness_delta INT, -- Change from yesterday
    mood_prediction DECIMAL(3,1),
    mood_prediction_confidence DECIMAL(3,2),
    mood_outlook VARCHAR(32), -- 'challenging', 'moderate', 'good', 'great'

    -- Quest
    quest_id UUID REFERENCES quests(id),
    quest_title TEXT,
    quest_duration_minutes INT,

    -- Context
    calendar_events JSONB DEFAULT '[]',
    important_dates JSONB DEFAULT '[]',
    -- Example: [{"type": "birthday", "name": "Sarah", "days_until": 2}]

    -- Suggestion
    suggestion_text TEXT NOT NULL,
    suggestion_type VARCHAR(32), -- 'exercise', 'rest', 'social', 'preparation'
    suggestion_action_id UUID, -- Optional link to exercise, quest, etc.

    -- Voice
    audio_text TEXT, -- Text-to-speech version
    audio_url TEXT, -- Pre-generated audio URL

    -- Metadata
    generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    opened_at TIMESTAMPTZ,
    voice_played BOOLEAN NOT NULL DEFAULT false,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(user_id, local_date)
);

-- User briefing preferences
CREATE TABLE briefing_preferences (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Delivery
    enabled BOOLEAN NOT NULL DEFAULT true,
    delivery_time_local TIME NOT NULL DEFAULT '07:00:00',
    delivery_method VARCHAR(16) NOT NULL DEFAULT 'notification', -- 'notification', 'silent'

    -- Components
    include_wellness_score BOOLEAN NOT NULL DEFAULT true,
    include_prediction BOOLEAN NOT NULL DEFAULT true,
    include_calendar BOOLEAN NOT NULL DEFAULT true,
    include_important_dates BOOLEAN NOT NULL DEFAULT true,
    include_suggestion BOOLEAN NOT NULL DEFAULT true,

    -- Voice
    voice_enabled BOOLEAN NOT NULL DEFAULT false,
    voice_gender VARCHAR(16) DEFAULT 'neutral', -- 'male', 'female', 'neutral'

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_daily_briefings_user_date ON daily_briefings(user_id, local_date DESC);

-- RLS Policies
ALTER TABLE daily_briefings ENABLE ROW LEVEL SECURITY;
ALTER TABLE briefing_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own briefings"
    ON daily_briefings FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own preferences"
    ON briefing_preferences FOR ALL
    USING (auth.uid() = user_id);
```

#### 3.2.2 Swift Models

```swift
// DailyBriefingModels.swift

import Foundation
import AVFoundation

// MARK: - Daily Briefing

struct DailyBriefing: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let localDate: Date

    let greeting: String
    let timeOfDay: TimeOfDay

    // Core components
    let wellnessScore: Int?
    let wellnessDelta: Int?
    let moodPrediction: Double?
    let moodPredictionConfidence: Double?
    let moodOutlook: MoodOutlook?

    // Quest
    let questId: UUID?
    let questTitle: String?
    let questDurationMinutes: Int?

    // Context
    let calendarEvents: [BriefingCalendarEvent]
    let importantDates: [BriefingImportantDate]

    // Suggestion
    let suggestionText: String
    let suggestionType: SuggestionType?
    let suggestionActionId: UUID?

    // Voice
    let audioText: String?
    let audioUrl: URL?

    let generatedAt: Date
    var openedAt: Date?
    var voicePlayed: Bool

    enum TimeOfDay: String, Codable {
        case morning
        case afternoon
        case evening
        case night
    }

    enum MoodOutlook: String, Codable {
        case challenging
        case moderate
        case good
        case great

        var emoji: String {
            switch self {
            case .challenging: return "🌧️"
            case .moderate: return "⛅"
            case .good: return "🌤️"
            case .great: return "☀️"
            }
        }
    }

    enum SuggestionType: String, Codable {
        case exercise
        case rest
        case social
        case preparation
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case localDate = "local_date"
        case greeting
        case timeOfDay = "time_of_day"
        case wellnessScore = "wellness_score"
        case wellnessDelta = "wellness_delta"
        case moodPrediction = "mood_prediction"
        case moodPredictionConfidence = "mood_prediction_confidence"
        case moodOutlook = "mood_outlook"
        case questId = "quest_id"
        case questTitle = "quest_title"
        case questDurationMinutes = "quest_duration_minutes"
        case calendarEvents = "calendar_events"
        case importantDates = "important_dates"
        case suggestionText = "suggestion_text"
        case suggestionType = "suggestion_type"
        case suggestionActionId = "suggestion_action_id"
        case audioText = "audio_text"
        case audioUrl = "audio_url"
        case generatedAt = "generated_at"
        case openedAt = "opened_at"
        case voicePlayed = "voice_played"
    }
}

// MARK: - Briefing Components

struct BriefingCalendarEvent: Codable, Identifiable {
    var id: String { title + startTime.description }
    let title: String
    let startTime: Date
    let durationMinutes: Int
    let isAllDay: Bool

    enum CodingKeys: String, CodingKey {
        case title
        case startTime = "start_time"
        case durationMinutes = "duration_minutes"
        case isAllDay = "is_all_day"
    }
}

struct BriefingImportantDate: Codable, Identifiable {
    var id: String { name + type }
    let type: String // 'birthday', 'anniversary', 'custom'
    let name: String
    let daysUntil: Int

    enum CodingKeys: String, CodingKey {
        case type, name
        case daysUntil = "days_until"
    }
}

// MARK: - Briefing Preferences

struct BriefingPreferences: Codable {
    var enabled: Bool
    var deliveryTimeLocal: Date
    var deliveryMethod: DeliveryMethod

    var includeWellnessScore: Bool
    var includePrediction: Bool
    var includeCalendar: Bool
    var includeImportantDates: Bool
    var includeSuggestion: Bool

    var voiceEnabled: Bool
    var voiceGender: VoiceGender

    enum DeliveryMethod: String, Codable {
        case notification
        case silent
    }

    enum VoiceGender: String, Codable {
        case male
        case female
        case neutral
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case deliveryTimeLocal = "delivery_time_local"
        case deliveryMethod = "delivery_method"
        case includeWellnessScore = "include_wellness_score"
        case includePrediction = "include_prediction"
        case includeCalendar = "include_calendar"
        case includeImportantDates = "include_important_dates"
        case includeSuggestion = "include_suggestion"
        case voiceEnabled = "voice_enabled"
        case voiceGender = "voice_gender"
    }
}
```

### 3.3 API Contracts

#### 3.3.1 Edge Function: `generate-daily-briefing`

**Endpoint:** `POST /functions/v1/generate-daily-briefing`

**Request:**

```json
{
  "local_date": "2026-01-22",
  "timezone": "America/New_York",
  "calendar_events": [
    {
      "title": "Team Meeting",
      "start_time": "2026-01-22T14:00:00Z",
      "duration_minutes": 60,
      "is_all_day": false
    }
  ]
}
```

**Response (200):**

```json
{
  "briefing": {
    "id": "uuid",
    "greeting": "Good morning, Daniel! Let's make today count.",
    "time_of_day": "morning",
    "wellness_score": 73,
    "wellness_delta": 5,
    "mood_prediction": 6.2,
    "mood_prediction_confidence": 0.72,
    "mood_outlook": "good",
    "quest_id": "uuid",
    "quest_title": "5-minute morning reset",
    "quest_duration_minutes": 5,
    "calendar_events": [
      {
        "title": "Team Meeting",
        "start_time": "2026-01-22T14:00:00Z",
        "duration_minutes": 60,
        "is_all_day": false
      }
    ],
    "important_dates": [
      {
        "type": "birthday",
        "name": "Sarah",
        "days_until": 2
      }
    ],
    "suggestion_text": "Your sleep was light last night. A 3-minute grounding exercise before your meeting might help you focus.",
    "suggestion_type": "exercise",
    "suggestion_action_id": "uuid",
    "audio_text": "Good morning, Daniel. Your wellness score is 73, up 5 from yesterday. Today looks good for mood. Your quest is a 5-minute morning reset. You have a team meeting at 2 PM. Quick tip: a grounding exercise before your meeting could help you focus."
  }
}
```

### 3.4 Briefing Generation Logic

```typescript
// generate-briefing.ts

interface BriefingContext {
  user: User;
  wellnessScore?: WellnessScore;
  moodPrediction?: MoodPrediction;
  todayQuest?: Quest;
  calendarEvents?: CalendarEvent[];
  importantDates?: ImportantDate[];
  sleepData?: BiometricDaily;
  preferences: BriefingPreferences;
}

function generateGreeting(context: BriefingContext): string {
  const hour = new Date().getHours();
  const name = context.user.displayName || "there";

  let timeGreeting: string;
  if (hour < 12) {
    timeGreeting = "Good morning";
  } else if (hour < 17) {
    timeGreeting = "Good afternoon";
  } else {
    timeGreeting = "Good evening";
  }

  // Add personality based on mood/wellness
  let personalizer = "";
  if (context.wellnessScore && context.wellnessScore.score >= 70) {
    personalizer = "Let's keep the momentum going.";
  } else if (
    context.moodPrediction &&
    context.moodPrediction.predictedMood < 5
  ) {
    personalizer = "Taking it easy today is okay.";
  } else {
    personalizer = "Let's make today count.";
  }

  return `${timeGreeting}, ${name}! ${personalizer}`;
}

function generateSuggestion(context: BriefingContext): {
  text: string;
  type: string;
  actionId?: string;
} {
  // Priority order for suggestions:
  // 1. Sleep deficit recovery
  // 2. Pre-event preparation
  // 3. Streak maintenance
  // 4. General wellness

  // Sleep-based suggestion
  if (context.sleepData && context.sleepData.sleepDurationHours < 6) {
    return {
      text: `Your sleep was light last night (${context.sleepData.sleepDurationHours.toFixed(1)}h). A short rest or gentle breathing exercise might help replenish your energy.`,
      type: "rest",
    };
  }

  // Calendar-based suggestion
  if (context.calendarEvents && context.calendarEvents.length > 0) {
    const nextMeeting = context.calendarEvents[0];
    if (nextMeeting.durationMinutes >= 60) {
      return {
        text: `You have ${nextMeeting.title} at ${formatTime(nextMeeting.startTime)}. A 3-minute grounding exercise beforehand might help you focus.`,
        type: "preparation",
        actionId: "grounding-quick", // Link to exercise
      };
    }
  }

  // Mood prediction based
  if (context.moodPrediction && context.moodPrediction.predictedMood < 5) {
    return {
      text: `Today might feel challenging. Consider scheduling a short walk or breathwork to build your armor.`,
      type: "exercise",
    };
  }

  // Default wellness suggestion
  return {
    text: `Your quest today is ready. Starting with a small win sets the tone for the day.`,
    type: "exercise",
    actionId: context.todayQuest?.id,
  };
}

function generateAudioText(briefing: DailyBriefing): string {
  const parts: string[] = [];

  parts.push(briefing.greeting);

  if (briefing.wellnessScore !== undefined) {
    parts.push(`Your wellness score is ${briefing.wellnessScore}`);
    if (briefing.wellnessDelta !== undefined && briefing.wellnessDelta !== 0) {
      const direction = briefing.wellnessDelta > 0 ? "up" : "down";
      parts.push(
        `${direction} ${Math.abs(briefing.wellnessDelta)} from yesterday.`,
      );
    }
  }

  if (briefing.moodOutlook) {
    parts.push(`Today looks ${briefing.moodOutlook} for mood.`);
  }

  if (briefing.questTitle) {
    parts.push(
      `Your quest is ${briefing.questTitle}, about ${briefing.questDurationMinutes} minutes.`,
    );
  }

  if (briefing.calendarEvents.length > 0) {
    const event = briefing.calendarEvents[0];
    parts.push(
      `You have ${event.title} at ${formatTimeSpoken(event.startTime)}.`,
    );
  }

  if (briefing.importantDates.length > 0) {
    const date = briefing.importantDates[0];
    if (date.daysUntil === 0) {
      parts.push(`Today is ${date.name}'s ${date.type}.`);
    } else {
      parts.push(`${date.name}'s ${date.type} is in ${date.daysUntil} days.`);
    }
  }

  parts.push(`Quick tip: ${briefing.suggestionText}`);

  return parts.join(" ");
}
```

---

## 4. Implementation Details

### 4.1 Step-by-Step Implementation

#### Step 1: Database Schema

1. Create migration for `daily_briefings` table
2. Create migration for `briefing_preferences` table
3. Add RLS policies

#### Step 2: Briefing Generation

1. Implement `generate-daily-briefing` edge function
2. Create greeting generation logic
3. Create suggestion generation logic
4. Create audio text generation

#### Step 3: Notification Scheduling

1. Implement `send-briefing-notification` edge function
2. Create cron job to trigger daily
3. Respect user's delivery time preference

#### Step 4: iOS Service Layer

1. Create `DailyBriefingService`
2. Implement briefing fetching
3. Add calendar integration (EventKit)
4. Create voice playback

#### Step 5: iOS UI

1. Create `DailyBriefingCard` view
2. Create `BriefingExpandedView`
3. Create `BriefingSettingsView`
4. Add to home screen

### 4.2 File Structure

```
apps/ios/MindFriendApp/
├── Core/
│   ├── Models/
│   │   └── DailyBriefingModels.swift
│   └── Services/
│       └── DailyBriefingService.swift
├── Features/
│   └── Briefing/
│       ├── Views/
│       │   ├── DailyBriefingCard.swift
│       │   ├── BriefingExpandedView.swift
│       │   └── BriefingSettingsView.swift
│       └── ViewModels/
│           └── DailyBriefingViewModel.swift

supabase/
├── functions/
│   ├── generate-daily-briefing/
│   │   └── index.ts
│   └── send-briefing-notification/
│       └── index.ts
└── migrations/
    └── 20260122000009_daily_briefings.sql
```

---

## 5. Dependencies

### 5.1 Prerequisites

| Feature                            | Reason                               |
| ---------------------------------- | ------------------------------------ |
| F002: Daily Wellness Score         | Provides wellness score for briefing |
| F003: Predictive Mood Intelligence | Provides mood prediction             |

### 5.2 External Libraries

| Library      | Version | Purpose              |
| ------------ | ------- | -------------------- |
| EventKit     | iOS 17+ | Calendar integration |
| AVFoundation | iOS 17+ | Voice playback       |

### 5.3 Internal Modules

| Module                   | Purpose             |
| ------------------------ | ------------------- |
| `WellnessScoreService`   | Get current score   |
| `MoodPredictionService`  | Get prediction      |
| `QuestService`           | Get today's quest   |
| `CompanionMemoryService` | Get important dates |

---

## 6. Edge Cases

| Scenario                       | Expected Behavior                     |
| ------------------------------ | ------------------------------------- |
| No wellness score yet          | Omit from briefing, focus on quest    |
| No prediction (new user)       | Omit prediction, use general greeting |
| Calendar permission denied     | Omit calendar events                  |
| No quest assigned              | Generate quest first, then include    |
| User opens at night            | Show evening briefing variant         |
| Notification permission denied | Show briefing only in-app             |

---

## 7. Testing Requirements

### 7.1 Test Scenarios

| Test Case               | Input                         | Expected Output             |
| ----------------------- | ----------------------------- | --------------------------- |
| Morning briefing        | 7am, score=73, quest assigned | Full briefing with greeting |
| Low sleep briefing      | sleep<6h                      | Suggestion mentions rest    |
| Calendar event briefing | Meeting at 2pm                | Briefing mentions meeting   |
| Voice text              | Complete briefing             | <60 second read time        |
