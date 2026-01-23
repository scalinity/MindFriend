# F006: Progress Narrative

> **Feature ID:** F006
> **Phase:** 2 - Engagement
> **Priority:** P0 (Critical)
> **Dependencies:** None
> **Dependents:** F019

---

## 1. Overview

### 1.1 Summary

Progress Narrative transforms raw wellness data into compelling, personalized stories that help users understand and celebrate their journey. AI-generated monthly narratives weave together mood patterns, milestone achievements, challenges overcome, and growth trajectories into a meaningful story—not just statistics.

### 1.2 Business Value

- **User Value:** Emotional connection to progress; meaning-making beyond numbers
- **Product Value:** High shareability creates organic growth; deepens emotional investment
- **Competitive Value:** No wellness app tells your story—they just show charts

### 1.3 User Benefit

Users experience their wellness journey as a meaningful narrative with story arcs, turning points, and growth, creating deeper emotional connection and motivation.

---

## 2. Requirements

### 2.1 Functional Requirements

| ID     | Requirement                                                                        | Priority |
| ------ | ---------------------------------------------------------------------------------- | -------- |
| FR-001 | Generate monthly wellness narrative summarizing key events and patterns            | Must     |
| FR-002 | Generate weekly mini-narratives with highlights                                    | Should   |
| FR-003 | Identify and highlight "story moments" (turning points, breakthroughs, challenges) | Must     |
| FR-004 | Create shareable narrative cards with key insights                                 | Must     |
| FR-005 | Allow user to view narrative history (past months)                                 | Must     |
| FR-006 | Personalize narrative voice to match user's communication style                    | Should   |
| FR-007 | Include specific details (dates, activities, people mentioned)                     | Must     |
| FR-008 | Generate narrative illustrations/visuals (optional)                                | Could    |
| FR-009 | Allow user to edit/hide parts of narrative before sharing                          | Should   |
| FR-010 | Push notification when new narrative is ready                                      | Should   |

### 2.2 Non-Functional Requirements

| ID      | Requirement               | Target                         |
| ------- | ------------------------- | ------------------------------ |
| NFR-001 | Narrative generation time | < 10 seconds                   |
| NFR-002 | Narrative length          | 200-400 words                  |
| NFR-003 | Privacy compliance        | No PII in shareable version    |
| NFR-004 | Narrative accuracy        | All facts verifiable from data |

### 2.3 Acceptance Criteria

1. **AC-001:** User receives notification on first of month: "Your January story is ready"
2. **AC-002:** Narrative references specific events: "That Wednesday you broke your 14-day streak..."
3. **AC-003:** Narrative identifies growth: "Your mood baseline improved 1.2 points this month"
4. **AC-004:** User can share narrative as image to social media
5. **AC-005:** Shareable version removes sensitive details automatically

---

## 3. Technical Design

### 3.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                          iOS App                                 │
├─────────────────────────────────────────────────────────────────┤
│  NarrativeService                                               │
│  ├─ getMonthlyNarrative(month:)                                 │
│  ├─ getWeeklyNarrative(week:)                                   │
│  ├─ getShareableCard()                                          │
│  └─ generateNarrativeImage()                                    │
│                                                                  │
│  Views:                                                          │
│  ├─ NarrativeView                                               │
│  ├─ NarrativeShareSheet                                         │
│  └─ NarrativeHistoryView                                        │
├─────────────────────────────────────────────────────────────────┤
│                        Supabase                                  │
├─────────────────────────────────────────────────────────────────┤
│  Tables:                      Edge Functions:                    │
│  ├─ narratives                ├─ generate-narrative             │
│  └─ narrative_moments         └─ get-narrative-data             │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Data Models

#### 3.2.1 Database Schema

```sql
-- Generated narratives
CREATE TABLE narratives (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Period
    narrative_type VARCHAR(16) NOT NULL, -- 'monthly', 'weekly', 'milestone'
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,

    -- Content
    title TEXT NOT NULL,
    full_narrative TEXT NOT NULL,
    summary TEXT NOT NULL, -- 1-2 sentence version
    key_moments JSONB NOT NULL DEFAULT '[]',
    -- Example: [
    --   {"type": "breakthrough", "date": "2026-01-15", "description": "First 14-day streak"},
    --   {"type": "challenge", "date": "2026-01-22", "description": "Rough week after..."}
    -- ]

    -- Stats summary
    stats JSONB NOT NULL DEFAULT '{}',
    -- Example: {
    --   "mood_average": 6.8,
    --   "mood_trend": 1.2,
    --   "exercises_completed": 15,
    --   "quests_completed": 28,
    --   "streak_max": 14
    -- }

    -- Shareable version (PII-removed)
    shareable_narrative TEXT,
    shareable_enabled BOOLEAN NOT NULL DEFAULT true,

    -- Metadata
    generation_model VARCHAR(64),
    generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_edited BOOLEAN NOT NULL DEFAULT false,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE(user_id, narrative_type, period_start)
);

-- Story moments (detected automatically)
CREATE TABLE narrative_moments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    moment_type VARCHAR(32) NOT NULL,
    -- Types: 'streak_milestone', 'streak_broken', 'mood_peak', 'mood_low',
    --        'first_exercise', 'badge_earned', 'circle_joined', 'crisis_recovery'

    moment_date DATE NOT NULL,
    description TEXT NOT NULL,
    significance INT NOT NULL DEFAULT 50 CHECK (significance BETWEEN 1 AND 100),

    -- Related data
    related_entity_type VARCHAR(32), -- 'badge', 'quest', 'exercise', etc.
    related_entity_id UUID,

    -- Usage
    included_in_narrative UUID REFERENCES narratives(id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_narratives_user_period ON narratives(user_id, narrative_type, period_start DESC);
CREATE INDEX idx_narrative_moments_user ON narrative_moments(user_id, moment_date DESC);
CREATE INDEX idx_narrative_moments_type ON narrative_moments(user_id, moment_type);

-- RLS Policies
ALTER TABLE narratives ENABLE ROW LEVEL SECURITY;
ALTER TABLE narrative_moments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own narratives"
    ON narratives FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update own narratives"
    ON narratives FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can read own moments"
    ON narrative_moments FOR SELECT
    USING (auth.uid() = user_id);
```

#### 3.2.2 Swift Models

```swift
// NarrativeModels.swift

import Foundation
import SwiftUI

// MARK: - Narrative

struct Narrative: Codable, Identifiable {
    let id: UUID
    let userId: UUID

    let narrativeType: NarrativeType
    let periodStart: Date
    let periodEnd: Date

    let title: String
    let fullNarrative: String
    let summary: String
    let keyMoments: [NarrativeMoment]
    let stats: NarrativeStats

    var shareableNarrative: String?
    let shareableEnabled: Bool

    let generatedAt: Date
    var userEdited: Bool

    enum NarrativeType: String, Codable {
        case monthly
        case weekly
        case milestone
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case narrativeType = "narrative_type"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case title
        case fullNarrative = "full_narrative"
        case summary
        case keyMoments = "key_moments"
        case stats
        case shareableNarrative = "shareable_narrative"
        case shareableEnabled = "shareable_enabled"
        case generatedAt = "generated_at"
        case userEdited = "user_edited"
    }

    var periodLabel: String {
        let formatter = DateFormatter()
        switch narrativeType {
        case .monthly:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: periodStart)
        case .weekly:
            formatter.dateFormat = "MMM d"
            let startStr = formatter.string(from: periodStart)
            let endStr = formatter.string(from: periodEnd)
            return "\(startStr) - \(endStr)"
        case .milestone:
            formatter.dateFormat = "MMMM d, yyyy"
            return formatter.string(from: periodStart)
        }
    }
}

// MARK: - Narrative Moment

struct NarrativeMoment: Codable, Identifiable {
    let id: UUID
    let momentType: MomentType
    let momentDate: Date
    let description: String
    let significance: Int

    enum MomentType: String, Codable {
        case streakMilestone = "streak_milestone"
        case streakBroken = "streak_broken"
        case moodPeak = "mood_peak"
        case moodLow = "mood_low"
        case firstExercise = "first_exercise"
        case badgeEarned = "badge_earned"
        case circleJoined = "circle_joined"
        case crisisRecovery = "crisis_recovery"
        case breakthrough = "breakthrough"
        case challenge = "challenge"

        var icon: String {
            switch self {
            case .streakMilestone: return "flame.fill"
            case .streakBroken: return "flame"
            case .moodPeak: return "sun.max.fill"
            case .moodLow: return "cloud.rain"
            case .firstExercise: return "heart.circle.fill"
            case .badgeEarned: return "star.fill"
            case .circleJoined: return "person.2.fill"
            case .crisisRecovery: return "sunrise.fill"
            case .breakthrough: return "sparkles"
            case .challenge: return "mountain.2"
            }
        }

        var color: Color {
            switch self {
            case .streakMilestone, .moodPeak, .badgeEarned, .breakthrough, .crisisRecovery:
                return .green
            case .streakBroken, .moodLow, .challenge:
                return .orange
            default:
                return .blue
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case momentType = "moment_type"
        case momentDate = "moment_date"
        case description
        case significance
    }
}

// MARK: - Narrative Stats

struct NarrativeStats: Codable {
    let moodAverage: Double
    let moodTrend: Double // Positive = improved
    let exercisesCompleted: Int
    let questsCompleted: Int
    let streakMax: Int
    let daysLogged: Int

    enum CodingKeys: String, CodingKey {
        case moodAverage = "mood_average"
        case moodTrend = "mood_trend"
        case exercisesCompleted = "exercises_completed"
        case questsCompleted = "quests_completed"
        case streakMax = "streak_max"
        case daysLogged = "days_logged"
    }
}

// MARK: - Share Card

struct NarrativeShareCard {
    let narrative: Narrative
    let includeStats: Bool
    let theme: ShareTheme

    enum ShareTheme: String, CaseIterable {
        case light
        case dark
        case gradient

        var backgroundColor: Color {
            switch self {
            case .light: return .white
            case .dark: return .black
            case .gradient: return .clear
            }
        }
    }
}
```

### 3.3 API Contracts

#### 3.3.1 Edge Function: `generate-narrative`

**Endpoint:** `POST /functions/v1/generate-narrative`

**Request:**

```json
{
  "narrative_type": "monthly",
  "period_start": "2026-01-01",
  "period_end": "2026-01-31",
  "force_regenerate": false
}
```

**Response (200):**

```json
{
  "narrative": {
    "id": "uuid",
    "title": "January 2026: Finding Your Rhythm",
    "full_narrative": "January started with uncertainty. After the holidays, you found yourself struggling to get back into routine—your first week showed a mood average of 5.2, and that Monday quest felt like climbing a mountain.\n\nBut something shifted around January 12th. You completed your first 7-day streak, and the momentum was palpable. \"I actually looked forward to my quest today,\" you wrote. The breathwork exercises became a morning ritual.\n\nThe middle of the month brought a challenge. That Wednesday, after 14 consecutive days, the streak broke. It would have been easy to spiral. Instead, you took a recovery day, logged how you felt, and started again. That resilience? That's growth.\n\nBy month's end, your mood baseline had improved from 5.2 to 6.4. You completed 28 quests, discovered that morning breathing works better for you than evening meditation, and earned 3 new badges.\n\nJanuary wasn't about perfection. It was about showing up, breaking, and starting again. That's the real victory.",
    "summary": "A month of finding rhythm through challenges, with a 1.2 point mood improvement and your first 14-day streak.",
    "key_moments": [
      {
        "type": "streak_milestone",
        "date": "2026-01-12",
        "description": "First 7-day streak achieved"
      },
      {
        "type": "streak_milestone",
        "date": "2026-01-19",
        "description": "Reached 14-day streak"
      },
      {
        "type": "streak_broken",
        "date": "2026-01-20",
        "description": "Streak ended after 14 days"
      },
      {
        "type": "breakthrough",
        "date": "2026-01-25",
        "description": "Discovered morning breathwork routine"
      }
    ],
    "stats": {
      "mood_average": 6.4,
      "mood_trend": 1.2,
      "exercises_completed": 15,
      "quests_completed": 28,
      "streak_max": 14,
      "days_logged": 28
    },
    "shareable_narrative": "January 2026: Finding Your Rhythm\n\nA month of growth through challenges. Started uncertain, ended with a 1.2 point mood improvement. Achieved a 14-day streak, learned that morning breathwork works best, and discovered that the real victory is starting again after breaking.\n\n28 quests completed. 15 exercises. A new rhythm found."
  }
}
```

### 3.4 Narrative Generation Prompt

```typescript
// narrative-generation-prompt.ts

const NARRATIVE_GENERATION_PROMPT = `
You are a skilled storyteller specializing in personal wellness narratives. Your task is to transform wellness data into a meaningful, engaging story that helps the user understand and appreciate their journey.

## Input Data
You will receive:
- Mood data (daily scores, trends)
- Quest completion data (streaks, skips)
- Exercise data (types, completion)
- Key moments (milestones, challenges)
- User personality traits (if available)

## Output Guidelines

### Tone
- Warm and supportive, never judgmental
- Celebrate progress without toxic positivity
- Acknowledge challenges without dwelling
- Match user's communication style if known

### Structure
1. **Opening Hook**: Set the scene for the time period
2. **Rising Action**: Describe early challenges or starting point
3. **Turning Point**: Identify the key moment(s) of change
4. **Development**: Show growth, learning, or persistence
5. **Resolution**: Celebrate where they ended up
6. **Looking Forward**: Brief hopeful note (optional)

### Content Requirements
- Reference specific dates and events
- Include direct quotes from mood notes when impactful
- Use concrete numbers but weave them into narrative
- Identify patterns the user might not have noticed
- Find the story in the data—every month has one

### Avoid
- Generic motivational language
- Comparing to others
- Medical advice or diagnoses
- Mentioning specific people by name in shareable version
- Being preachy or lecturing

### Length
- Full narrative: 200-400 words
- Summary: 1-2 sentences
- Shareable version: 100-150 words (no PII)

### Example Opening Styles
- "January started with uncertainty..."
- "There's a moment in February that stood out..."
- "This wasn't supposed to be a breakthrough month..."
- "Looking back at March, a pattern emerges..."

Output as JSON with fields: title, full_narrative, summary, shareable_narrative
`;
```

---

## 4. Implementation Details

### 4.1 Step-by-Step Implementation

#### Step 1: Database Schema

1. Create migration for `narratives` table
2. Create migration for `narrative_moments` table
3. Add RLS policies and indexes

#### Step 2: Moment Detection

1. Create cron job to detect story moments daily
2. Implement moment significance scoring
3. Store moments in database

#### Step 3: Narrative Generation

1. Implement `generate-narrative` edge function
2. Create narrative generation prompt
3. Add personality-based prompt modifiers
4. Implement shareable version generation

#### Step 4: iOS Service Layer

1. Create `NarrativeService`
2. Implement narrative fetching and caching
3. Add share card generation

#### Step 5: iOS UI

1. Create `NarrativeView`
2. Create `NarrativeShareSheet`
3. Create `NarrativeHistoryView`
4. Add to insights/profile navigation

#### Step 6: Notifications

1. Trigger notification on narrative ready
2. Implement monthly cron for generation

### 4.2 File Structure

```
apps/ios/MindFriendApp/
├── Core/
│   ├── Models/
│   │   └── NarrativeModels.swift
│   └── Services/
│       └── NarrativeService.swift
├── Features/
│   └── Narrative/
│       ├── Views/
│       │   ├── NarrativeView.swift
│       │   ├── NarrativeShareSheet.swift
│       │   ├── NarrativeHistoryView.swift
│       │   └── NarrativeMomentCard.swift
│       └── ViewModels/
│           └── NarrativeViewModel.swift

supabase/
├── functions/
│   ├── generate-narrative/
│   │   └── index.ts
│   ├── detect-story-moments/
│   │   └── index.ts
│   └── get-narrative-data/
│       └── index.ts
└── migrations/
    └── 20260122000006_narratives.sql
```

---

## 5. Dependencies

### 5.1 Prerequisites

- None (uses existing wellness data)

### 5.2 Internal Modules

| Module               | Purpose                  |
| -------------------- | ------------------------ |
| `MoodService`        | Mood history data        |
| `QuestService`       | Quest and streak data    |
| `ExerciseService`    | Exercise completion data |
| `PersonalityService` | Communication style      |

---

## 6. Edge Cases and Error Handling

### 6.1 Edge Cases

| Scenario                        | Expected Behavior                                       |
| ------------------------------- | ------------------------------------------------------- |
| Very little data (<5 days)      | Generate shorter narrative with "getting started" theme |
| All low mood scores             | Focus on persistence, not toxic positivity              |
| No key moments                  | Find smaller wins to highlight                          |
| User edited previous narrative  | Preserve edits, don't overwrite                         |
| User hasn't logged in for month | Generate based on available data, note gaps             |

---

## 7. Testing Requirements

### 7.1 Test Scenarios

| Test Case         | Input                      | Expected Output                    |
| ----------------- | -------------------------- | ---------------------------------- |
| Full month data   | 30 days, streak, exercises | Complete narrative with moments    |
| Sparse data       | 10 days, 3 exercises       | Shorter narrative, appropriate     |
| Streak broken     | 14-day streak, then break  | Narrative addresses resilience     |
| Improvement trend | Mood improved 2 points     | Narrative celebrates growth        |
| Decline trend     | Mood declined              | Narrative acknowledges, supportive |
