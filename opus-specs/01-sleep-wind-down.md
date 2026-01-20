# Sleep & Wind-Down Experience

> Transform MindFriend into the companion that helps users both start and end their day with intention.

**Priority:** P0 - Critical
**Effort:** High (6-8 weeks)
**Impact:** 40%+ retention lift based on competitor data

---

## 1. Overview

### 1.1 What It Does

A comprehensive sleep module providing sleep stories, ambient soundscapes, bedtime reminders, wind-down routines, and sleep quality tracking that correlates with mood data.

### 1.2 Why It Exists

- **Market Gap:** Sleep is the #1 requested feature in mental health apps
- **Retention Driver:** Calm reports 40%+ of sessions are sleep-related
- **Clinical Link:** Poor sleep directly correlates with anxiety and depression
- **Daily Touchpoint:** Creates "bookend" habit (morning mood + evening wind-down)
- **Current State:** MindFriend has ZERO sleep-specific content

### 1.3 Success Metrics

| Metric                           | Target                 | Measurement     |
| -------------------------------- | ---------------------- | --------------- |
| Sleep content sessions/week      | 3+ per active user     | Analytics       |
| 7-day retention lift             | +15%                   | Cohort analysis |
| Sleep quality rating improvement | +0.5 pts over 30 days  | Self-reported   |
| Wind-down routine completion     | 60% of users who start | Funnel tracking |

---

## 2. User Stories

### 2.1 Primary Users

| Persona                   | Need                                | Story                                                                                                         |
| ------------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| **Anxious Sleeper**       | Quieting racing thoughts            | "As someone who lies awake worrying, I want calming stories to distract my mind so I can fall asleep faster." |
| **Stressed Professional** | Transitioning from work mode        | "As a busy professional, I want a wind-down routine that signals my brain it's time to relax."                |
| **Mood Tracker**          | Understanding sleep-mood connection | "As someone tracking my mental health, I want to see how my sleep quality affects my mood."                   |
| **Parent**                | Helping children sleep              | "As a parent, I want age-appropriate sleep content for my kids in our family plan."                           |

### 2.2 User Journey

```
Evening Trigger (8-10pm)
        │
        ▼
┌───────────────────┐
│ Wind-Down Nudge   │──▶ Dismiss / Snooze
│ (Smart Timing)    │
└───────────────────┘
        │ Tap
        ▼
┌───────────────────┐
│ Wind-Down Home    │
│ • Tonight's Pick  │
│ • Quick Routines  │
│ • Sleep Stories   │
│ • Soundscapes     │
└───────────────────┘
        │
        ▼
┌───────────────────┐
│ Content Playback  │
│ • Sleep Timer     │
│ • Background Play │
│ • Screen Dimming  │
└───────────────────┘
        │ Timer ends / Morning
        ▼
┌───────────────────┐
│ Morning Check-in  │
│ "How did you      │
│  sleep last night?"│
└───────────────────┘
        │
        ▼
┌───────────────────┐
│ Sleep Insights    │
│ • Quality Trend   │
│ • Mood Correlation│
└───────────────────┘
```

---

## 3. Functional Requirements

### 3.1 Sleep Stories

| ID    | Requirement                                                   | Priority |
| ----- | ------------------------------------------------------------- | -------- |
| SS-01 | Library of 20+ sleep stories at launch (10 free, 10 premium)  | Must     |
| SS-02 | Stories are 15-45 minutes, designed to induce sleep           | Must     |
| SS-03 | Multiple narrators with different voice styles                | Should   |
| SS-04 | Categories: Nature, Fiction, Non-fiction, ASMR-style          | Must     |
| SS-05 | New story added weekly                                        | Should   |
| SS-06 | "Continue where I left off" for stories                       | Should   |
| SS-07 | Download for offline playback                                 | Must     |
| SS-08 | Sleep timer with fade-out (15/30/45/60 min or "end of story") | Must     |

### 3.2 Soundscapes

| ID    | Requirement                                                      | Priority |
| ----- | ---------------------------------------------------------------- | -------- |
| SC-01 | 15+ ambient soundscapes (rain, ocean, forest, white noise, etc.) | Must     |
| SC-02 | Mixing board: combine up to 3 sounds with individual volume      | Should   |
| SC-03 | Infinite looping without audio gaps                              | Must     |
| SC-04 | Binaural beats option for deep sleep (delta waves)               | Should   |
| SC-05 | Download for offline playback                                    | Must     |
| SC-06 | Sleep timer (same as stories)                                    | Must     |
| SC-07 | Save custom mixes as presets                                     | Should   |

### 3.3 Wind-Down Routines

| ID    | Requirement                                                         | Priority |
| ----- | ------------------------------------------------------------------- | -------- |
| WD-01 | Pre-built routines: 5-min, 10-min, 20-min                           | Must     |
| WD-02 | Routine steps: breathing → body scan → gratitude → story/soundscape | Must     |
| WD-03 | Custom routine builder (select steps, duration, ending)             | Should   |
| WD-04 | "Tonight's Pick" AI recommendation based on mood/stress             | Should   |
| WD-05 | Routine completion tracking with streak                             | Should   |
| WD-06 | XP rewards for completing routines                                  | Must     |

### 3.4 Bedtime Reminders

| ID    | Requirement                                    | Priority |
| ----- | ---------------------------------------------- | -------- |
| BR-01 | User sets target bedtime and wake time         | Must     |
| BR-02 | Smart reminder 30-60 min before bedtime        | Must     |
| BR-03 | Reminder respects existing quiet hours setting | Must     |
| BR-04 | Adaptive timing based on actual sleep patterns | Should   |
| BR-05 | Option to snooze reminder (15 min increments)  | Should   |

### 3.5 Sleep Quality Tracking

| ID    | Requirement                                           | Priority |
| ----- | ----------------------------------------------------- | -------- |
| SQ-01 | Morning prompt: "How did you sleep?" (1-5 scale)      | Must     |
| SQ-02 | Optional: hours slept, time to fall asleep, wake-ups  | Should   |
| SQ-03 | HealthKit integration for automatic sleep data        | Must     |
| SQ-04 | Sleep quality trends visualization (7/30/90 days)     | Must     |
| SQ-05 | Correlation analysis: sleep vs mood, sleep vs anxiety | Must     |
| SQ-06 | Weekly sleep insights in insights dashboard           | Should   |

### 3.6 Kids Sleep (Family Feature)

| ID    | Requirement                                         | Priority |
| ----- | --------------------------------------------------- | -------- |
| KS-01 | Age-appropriate stories (5-12 years)                | Should   |
| KS-02 | Shorter duration (5-15 min)                         | Should   |
| KS-03 | Parental controls for content access                | Should   |
| KS-04 | Parent notification when child starts sleep content | Could    |

---

## 4. Technical Requirements

### 4.1 Data Models

```sql
-- Sleep content metadata
CREATE TABLE sleep_content (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    content_type TEXT NOT NULL CHECK (content_type IN ('story', 'soundscape', 'routine')),
    category TEXT NOT NULL, -- 'nature', 'fiction', 'asmr', 'ambient', etc.
    duration_seconds INTEGER NOT NULL,
    narrator TEXT, -- for stories
    is_premium BOOLEAN DEFAULT false,
    is_kids BOOLEAN DEFAULT false,
    audio_url TEXT NOT NULL, -- Supabase Storage URL
    thumbnail_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- User's sleep settings
CREATE TABLE user_sleep_settings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    target_bedtime TIME, -- e.g., '22:30'
    target_wake_time TIME, -- e.g., '07:00'
    reminder_minutes_before INTEGER DEFAULT 30,
    reminder_enabled BOOLEAN DEFAULT true,
    auto_play_timer_minutes INTEGER DEFAULT 30,
    preferred_soundscape_ids UUID[], -- saved favorites
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Sleep quality logs
CREATE TABLE sleep_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    log_date DATE NOT NULL,
    quality_rating INTEGER CHECK (quality_rating BETWEEN 1 AND 5),
    hours_slept DECIMAL(3,1),
    minutes_to_fall_asleep INTEGER,
    wake_ups INTEGER,
    notes TEXT,
    healthkit_synced BOOLEAN DEFAULT false,
    healthkit_data JSONB, -- raw HealthKit sleep data
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, log_date)
);

-- Sleep content sessions (for analytics and progress)
CREATE TABLE sleep_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content_id UUID NOT NULL REFERENCES sleep_content(id),
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    duration_listened_seconds INTEGER,
    completed BOOLEAN DEFAULT false,
    sleep_timer_used BOOLEAN DEFAULT false,
    timer_duration_minutes INTEGER
);

-- Custom soundscape mixes
CREATE TABLE soundscape_mixes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    sounds JSONB NOT NULL, -- [{soundscape_id, volume}]
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS Policies
ALTER TABLE sleep_content ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_sleep_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE sleep_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE sleep_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE soundscape_mixes ENABLE ROW LEVEL SECURITY;

-- Sleep content is readable by all authenticated users
CREATE POLICY "Sleep content readable by authenticated users"
    ON sleep_content FOR SELECT
    USING (auth.role() = 'authenticated');

-- Users manage their own sleep data
CREATE POLICY "Users manage own sleep settings"
    ON user_sleep_settings FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users manage own sleep logs"
    ON sleep_logs FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users manage own sleep sessions"
    ON sleep_sessions FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users manage own soundscape mixes"
    ON soundscape_mixes FOR ALL
    USING (auth.uid() = user_id);
```

### 4.2 Swift Models

```swift
// MARK: - Sleep Content Models

enum SleepContentType: String, Codable {
    case story
    case soundscape
    case routine
}

enum SleepCategory: String, Codable, CaseIterable {
    case nature
    case fiction
    case nonfiction
    case asmr
    case ambient
    case whiteNoise
    case binaural
    case routine
}

struct SleepContent: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String?
    let contentType: SleepContentType
    let category: SleepCategory
    let durationSeconds: Int
    let narrator: String?
    let isPremium: Bool
    let isKids: Bool
    let audioUrl: URL
    let thumbnailUrl: URL?
    let createdAt: Date

    var formattedDuration: String {
        let minutes = durationSeconds / 60
        return "\(minutes) min"
    }
}

struct UserSleepSettings: Codable {
    var userId: UUID
    var targetBedtime: Date? // Time component only
    var targetWakeTime: Date?
    var reminderMinutesBefore: Int
    var reminderEnabled: Bool
    var autoPlayTimerMinutes: Int
    var preferredSoundscapeIds: [UUID]
}

struct SleepLog: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let logDate: Date
    var qualityRating: Int? // 1-5
    var hoursSlept: Double?
    var minutesToFallAsleep: Int?
    var wakeUps: Int?
    var notes: String?
    var healthKitSynced: Bool
}

struct SleepSession: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let contentId: UUID
    let startedAt: Date
    var endedAt: Date?
    var durationListenedSeconds: Int?
    var completed: Bool
    var sleepTimerUsed: Bool
    var timerDurationMinutes: Int?
}

struct SoundscapeMix: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    var name: String
    var sounds: [SoundComponent]
    let createdAt: Date

    struct SoundComponent: Codable {
        let soundscapeId: UUID
        var volume: Float // 0.0 - 1.0
    }
}
```

### 4.3 API Contracts

#### Get Sleep Content Library

```typescript
// GET /rest/v1/sleep_content?select=*&order=created_at.desc
// Headers: Authorization: Bearer <jwt>

// Response
[
  {
    id: "uuid",
    title: "Rainy Night in the Forest",
    description: "...",
    content_type: "story",
    category: "nature",
    duration_seconds: 1800,
    narrator: "Sarah",
    is_premium: false,
    is_kids: false,
    audio_url: "https://storage.supabase.co/...",
    thumbnail_url: "https://storage.supabase.co/...",
  },
];
```

#### Log Sleep Quality

```typescript
// POST /rest/v1/sleep_logs
// Headers: Authorization: Bearer <jwt>

// Request
{
    "log_date": "2026-01-19",
    "quality_rating": 4,
    "hours_slept": 7.5,
    "minutes_to_fall_asleep": 15,
    "wake_ups": 1,
    "notes": "Felt rested"
}

// Response: 201 Created
```

#### Get Sleep Insights

```typescript
// Edge Function: get-sleep-insights
// POST /functions/v1/get-sleep-insights

// Request
{
    "days": 30
}

// Response
{
    "average_quality": 3.8,
    "average_hours": 7.2,
    "trend": "improving", // "improving" | "declining" | "stable"
    "mood_correlation": 0.72, // correlation coefficient
    "best_sleep_day": "Saturday",
    "worst_sleep_day": "Tuesday",
    "recommendations": [
        "Your mood is 23% better on days after 7+ hours of sleep",
        "Consider moving bedtime 30 minutes earlier on weeknights"
    ],
    "daily_data": [
        {"date": "2026-01-19", "quality": 4, "hours": 7.5, "mood": 7}
    ]
}
```

### 4.4 Edge Functions

```typescript
// supabase/functions/get-sleep-insights/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const authHeader = req.headers.get("Authorization")!;
  const {
    data: { user },
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

  if (!user) {
    return new Response("Unauthorized", { status: 401 });
  }

  const { days } = await req.json();
  const startDate = new Date();
  startDate.setDate(startDate.getDate() - days);

  // Fetch sleep logs
  const { data: sleepLogs } = await supabase
    .from("sleep_logs")
    .select("*")
    .eq("user_id", user.id)
    .gte("log_date", startDate.toISOString().split("T")[0])
    .order("log_date", { ascending: true });

  // Fetch mood logs for correlation
  const { data: moodLogs } = await supabase
    .from("moods")
    .select("*")
    .eq("user_id", user.id)
    .gte("created_at", startDate.toISOString())
    .order("created_at", { ascending: true });

  // Calculate insights
  const insights = calculateSleepInsights(sleepLogs, moodLogs);

  return new Response(JSON.stringify(insights), {
    headers: { "Content-Type": "application/json" },
  });
});

function calculateSleepInsights(sleepLogs, moodLogs) {
  // Implementation: calculate averages, trends, correlations
  // ...
}
```

### 4.5 Audio Infrastructure

```
Supabase Storage Structure:
└── sleep-content/
    ├── stories/
    │   ├── {content_id}.mp3
    │   └── {content_id}.m4a (AAC for smaller file size)
    ├── soundscapes/
    │   ├── {content_id}.mp3
    │   └── {content_id}_loop.mp3 (seamless loop version)
    └── thumbnails/
        └── {content_id}.jpg

Audio Specifications:
- Format: AAC (M4A) preferred for iOS, MP3 fallback
- Bitrate: 128kbps for stories, 192kbps for soundscapes
- Sample Rate: 44.1kHz
- Channels: Stereo
- Loudness: -16 LUFS (consistent across content)
```

---

## 5. UI/UX Specifications

### 5.1 Sleep Tab Navigation

```
┌─────────────────────────────────┐
│ Sleep                      ⚙️   │
├─────────────────────────────────┤
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Tonight's Wind-Down         │ │
│ │ ┌───────────────────────┐   │ │
│ │ │ 🌙 Recommended for    │   │ │
│ │ │    your mood tonight  │   │ │
│ │ │                       │   │ │
│ │ │ "Forest Rain"         │   │ │
│ │ │ 25 min • Soundscape   │   │ │
│ │ │                       │   │ │
│ │ │    [Start Wind-Down]  │   │ │
│ │ └───────────────────────┘   │ │
│ └─────────────────────────────┘ │
│                                 │
│ Quick Routines                  │
│ ┌────┐ ┌────┐ ┌────┐           │
│ │5min│ │10m │ │20m │           │
│ └────┘ └────┘ └────┘           │
│                                 │
│ Sleep Stories                ▶  │
│ ┌────────────────────────────┐  │
│ │ 🌲 Rainy Night    │ 🏔️ Mount│  │
│ │ 30 min            │ 25 min  │  │
│ └────────────────────────────┘  │
│                                 │
│ Soundscapes                  ▶  │
│ ┌────────────────────────────┐  │
│ │ 🌊 Ocean  │ 🌧️ Rain │ 🔥 Fire│  │
│ └────────────────────────────┘  │
│                                 │
│ My Sleep                     ▶  │
│ ┌────────────────────────────┐  │
│ │ Last 7 Days: ⭐ 3.8 avg    │  │
│ │ ████████░░ 76% goal met   │  │
│ └────────────────────────────┘  │
│                                 │
└─────────────────────────────────┘
```

### 5.2 Sleep Player Screen

```
┌─────────────────────────────────┐
│ ←                          ⋮   │
├─────────────────────────────────┤
│                                 │
│         ┌─────────────┐         │
│         │             │         │
│         │   🌲🌧️      │         │
│         │             │         │
│         │   Artwork   │         │
│         │             │         │
│         └─────────────┘         │
│                                 │
│      Rainy Night in the Forest  │
│      Sleep Story • 30 min       │
│      Narrated by Sarah          │
│                                 │
│  ━━━━━━━━━━━━━○━━━━━━━━━━━━━   │
│  12:34              17:26       │
│                                 │
│       ⏮️    ▶️/⏸️    ⏭️          │
│                                 │
│  ┌────────────────────────────┐ │
│  │ 🕐 Sleep Timer: 30 min     │ │
│  │    [15] [30] [45] [End]    │ │
│  └────────────────────────────┘ │
│                                 │
│  🔊 ━━━━━━━━━━━○━━━━━━━━━━━━   │
│                                 │
│  [Download for Offline]         │
│                                 │
└─────────────────────────────────┘
```

### 5.3 Morning Sleep Check-in

```
┌─────────────────────────────────┐
│                                 │
│          Good morning! ☀️       │
│                                 │
│    How did you sleep last       │
│    night?                       │
│                                 │
│    😫  😕  😐  🙂  😴           │
│    Poor     OK     Great        │
│                                 │
│    ─────────────────────────    │
│                                 │
│    Hours slept (optional)       │
│    ┌─────────────────────┐      │
│    │ ← 7.5 hours →       │      │
│    └─────────────────────┘      │
│                                 │
│    How long to fall asleep?     │
│    ┌─────────────────────┐      │
│    │ ← 15 minutes →      │      │
│    └─────────────────────┘      │
│                                 │
│    [Skip] [Continue to Home →]  │
│                                 │
└─────────────────────────────────┘
```

### 5.4 Design System

| Element                | Specification                                           |
| ---------------------- | ------------------------------------------------------- |
| **Color Palette**      | Dark mode default for sleep screens (reduce blue light) |
| **Primary Background** | `#0D1B2A` (deep navy)                                   |
| **Accent Color**       | `#7B68EE` (soft purple, calming)                        |
| **Typography**         | SF Pro Rounded for softer feel                          |
| **Animations**         | Slow fade transitions (500ms+), no jarring movements    |
| **Haptics**            | Minimal - soft confirmation only                        |
| **Screen Dimming**     | Automatic brightness reduction when player active       |

---

## 6. Acceptance Criteria

### 6.1 Sleep Stories

- [ ] User can browse sleep stories by category
- [ ] User can play a sleep story with background audio support
- [ ] User can set a sleep timer that fades out audio
- [ ] User can download stories for offline playback
- [ ] Premium stories show lock icon for free users
- [ ] Playback position is saved when user closes app

### 6.2 Soundscapes

- [ ] User can browse and play soundscapes
- [ ] User can mix up to 3 soundscapes with individual volume control
- [ ] Soundscapes loop seamlessly without gaps
- [ ] User can save custom mixes as presets
- [ ] Downloaded soundscapes work offline

### 6.3 Wind-Down Routines

- [ ] User can start a pre-built 5/10/20-minute routine
- [ ] Routine guides through breathing → body scan → gratitude → content
- [ ] User earns XP upon completing a routine
- [ ] Wind-down streak is tracked separately from daily quest streak

### 6.4 Sleep Tracking

- [ ] User is prompted for sleep quality each morning (can dismiss)
- [ ] Sleep quality syncs from HealthKit when authorized
- [ ] User can view sleep quality trends over 7/30/90 days
- [ ] Sleep-mood correlation is shown in insights
- [ ] User receives personalized sleep recommendations

### 6.5 Notifications

- [ ] Bedtime reminder fires at configured time
- [ ] Reminder respects quiet hours setting
- [ ] User can snooze reminder for 15 minutes
- [ ] Reminder deep links to wind-down screen

---

## 7. Edge Cases & Error Handling

| Scenario                          | Behavior                                                          |
| --------------------------------- | ----------------------------------------------------------------- |
| No internet during playback       | Downloaded content plays; streaming content shows offline message |
| Audio interrupted (call)          | Pause playback, resume after call if within 5 min                 |
| Sleep timer ends mid-story        | Fade out over 30 seconds, save position                           |
| HealthKit permission denied       | Show manual entry UI, prompt to enable later                      |
| Storage full during download      | Alert user, offer to delete old downloads                         |
| User falls asleep during check-in | Auto-dismiss after 2 min of inactivity                            |
| Midnight crosses during playback  | Log session to correct date (start date)                          |
| Multiple devices                  | Sync settings, but offline downloads are device-specific          |

---

## 8. Security Considerations

| Area          | Requirement                                             |
| ------------- | ------------------------------------------------------- |
| Audio Content | Signed URLs with 24-hour expiry to prevent hotlinking   |
| Sleep Data    | RLS enforced; user can only access own sleep logs       |
| HealthKit     | Request minimal permissions (sleep analysis only)       |
| Analytics     | Aggregate sleep insights only; no raw data in analytics |
| Export        | User can export own sleep data (GDPR compliance)        |

---

## 9. Performance Requirements

| Metric              | Target                                  |
| ------------------- | --------------------------------------- |
| Audio start latency | < 2 seconds                             |
| Download speed      | Full story (50MB) in < 60 seconds on 4G |
| Offline storage     | Cap at 500MB default, user-configurable |
| Battery impact      | < 5% per hour during playback           |
| Memory usage        | < 100MB during playback                 |
| Background audio    | Zero dropped frames when screen off     |

---

## 10. Dependencies

### 10.1 Internal Dependencies

| Dependency            | Reason                           |
| --------------------- | -------------------------------- |
| HealthKit Service     | Sleep data sync                  |
| Notification Manager  | Bedtime reminders                |
| Offline Manager (new) | Content downloads                |
| Audio Player Service  | Playback infrastructure (exists) |
| Insights Module       | Sleep-mood correlation display   |
| Achievement Service   | XP rewards for routines          |

### 10.2 External Dependencies

| Dependency       | Reason                  |
| ---------------- | ----------------------- |
| Supabase Storage | Audio file hosting      |
| Content Creators | Sleep story production  |
| Audio Licensing  | Soundscape source files |

---

## 11. Content Production Plan

### 11.1 Launch Content (MVP)

| Type               | Count | Source                                  |
| ------------------ | ----- | --------------------------------------- |
| Sleep Stories      | 20    | Contract narrators, original scripts    |
| Soundscapes        | 15    | Licensed ambient audio + original       |
| Wind-Down Routines | 3     | Repurpose existing breathing/meditation |

### 11.2 Ongoing Content

- 1 new sleep story per week
- 2 new soundscapes per month
- Seasonal content (holiday stories, nature cycles)

### 11.3 Content Guidelines

- Stories should have slow pacing, no climax
- Avoid stimulating topics (conflict, suspense)
- Narration should be monotone, not dramatic
- Background music minimal (10-15 dB below voice)
- End with 2 minutes of ambient sound fade-out

---

## 12. Analytics Events

```swift
// Track for product insights
enum SleepAnalyticsEvent {
    case sleepTabViewed
    case sleepContentStarted(contentId: UUID, contentType: String)
    case sleepContentCompleted(contentId: UUID, durationListened: Int)
    case sleepTimerSet(minutes: Int)
    case sleepTimerExpired
    case soundscapeMixCreated(soundCount: Int)
    case windDownRoutineStarted(durationMinutes: Int)
    case windDownRoutineCompleted(durationMinutes: Int)
    case sleepQualityLogged(rating: Int)
    case sleepInsightsViewed
    case contentDownloaded(contentId: UUID)
    case bedtimeReminderDismissed
    case bedtimeReminderSnoozed
}
```

---

## 13. Rollout Plan

### Phase 1: Foundation (Week 1-2)

- Database schema and migrations
- Basic audio playback for sleep content
- Sleep tab UI shell

### Phase 2: Core Content (Week 3-4)

- Sleep stories library and player
- Soundscapes with basic playback
- Sleep timer functionality

### Phase 3: Tracking (Week 5-6)

- Morning sleep check-in
- Sleep quality trends
- HealthKit integration

### Phase 4: Intelligence (Week 7-8)

- Sleep-mood correlation
- "Tonight's Pick" recommendations
- Bedtime reminders
- Wind-down routines

### Phase 5: Polish (Week 8+)

- Offline downloads
- Soundscape mixing
- Custom routines
- Kids content (if family plan active)

---

## 14. Open Questions

| Question                                               | Owner       | Due Date         |
| ------------------------------------------------------ | ----------- | ---------------- |
| Licensing model for soundscapes?                       | Product     | Before dev start |
| Celebrity narrators for premium stories?               | Marketing   | Phase 2          |
| Sleep coaching integration with therapist marketplace? | Product     | Future           |
| Apple Watch sleep tracking integration?                | Engineering | Phase 3          |
