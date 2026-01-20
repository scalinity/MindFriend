# Journaling with AI Insights

> Transform free-form writing into actionable self-awareness with AI-powered cognitive analysis.

**Priority:** P1 - High Value
**Effort:** Medium (4-5 weeks)
**Impact:** Evidence-based engagement; unique differentiation

---

## 1. Overview

### 1.1 What It Does

A journaling feature with:

- Free-form text journaling with prompts
- AI analysis of themes, sentiment, and patterns
- Cognitive distortion detection (catastrophizing, black-and-white thinking, etc.)
- Long-term trend visualization
- Integration with mood data

### 1.2 Why It Exists

- **Clinical Evidence:** Journaling is proven effective for mental health
- **Unique Value:** No app has AI-powered cognitive distortion detection
- **Data Enrichment:** Journal content enhances personalization and insights
- **Engagement:** Writing creates deeper engagement than passive consumption

### 1.3 Success Metrics

| Metric                | Target                | Measurement     |
| --------------------- | --------------------- | --------------- |
| Journal entries/week  | 2+ per active user    | Analytics       |
| Insight engagement    | 60% view AI insights  | Click-through   |
| User satisfaction     | 4.5+ rating           | In-app survey   |
| Retention correlation | +25% 30-day retention | Cohort analysis |

---

## 2. User Stories

| Persona             | Need                 | Story                                                                                                |
| ------------------- | -------------------- | ---------------------------------------------------------------------------------------------------- |
| **Anxious Thinker** | Pattern awareness    | "As someone with anxiety, I want to see when I'm catastrophizing so I can challenge those thoughts." |
| **Therapy User**    | Between-session tool | "As someone in therapy, I want to journal between sessions and share insights with my therapist."    |
| **Self-Improver**   | Growth tracking      | "As someone focused on growth, I want to see how my thinking patterns change over time."             |

---

## 3. Functional Requirements

### 3.1 Journal Entry

| ID    | Requirement                                  | Priority |
| ----- | -------------------------------------------- | -------- |
| JE-01 | Free-form text entry with no character limit | Must     |
| JE-02 | Daily journal prompts (optional)             | Should   |
| JE-03 | Mood tagging on entry                        | Should   |
| JE-04 | Photo attachment                             | Could    |
| JE-05 | Voice-to-text option                         | Should   |
| JE-06 | Auto-save while typing                       | Must     |
| JE-07 | Entry timestamps                             | Must     |
| JE-08 | Edit/delete entries                          | Must     |

### 3.2 AI Analysis

| ID    | Requirement                                                | Priority |
| ----- | ---------------------------------------------------------- | -------- |
| AA-01 | Sentiment analysis (positive/negative/neutral + intensity) | Must     |
| AA-02 | Cognitive distortion detection                             | Must     |
| AA-03 | Theme extraction (work, relationships, health, etc.)       | Should   |
| AA-04 | Emotion identification beyond mood                         | Should   |
| AA-05 | Highlight sentences with distortions                       | Must     |
| AA-06 | Generate alternative perspectives                          | Should   |
| AA-07 | Analysis runs automatically after save                     | Must     |
| AA-08 | User can dismiss/disagree with insights                    | Should   |

### 3.3 Cognitive Distortions

| Distortion          | Detection                                         | Priority |
| ------------------- | ------------------------------------------------- | -------- |
| All-or-Nothing      | "always", "never", "everyone", "no one" + context | Must     |
| Catastrophizing     | Worst-case predictions, "what if" spirals         | Must     |
| Mind Reading        | Assuming others' thoughts without evidence        | Must     |
| Overgeneralization  | Single event → universal conclusion               | Should   |
| Emotional Reasoning | Feelings as facts                                 | Should   |
| Should Statements   | "should", "must", "have to" without flexibility   | Must     |
| Labeling            | Global labels from specific events                | Should   |
| Personalization     | Taking blame for external events                  | Should   |
| Mental Filter       | Focus on negatives, ignore positives              | Should   |
| Fortune Telling     | Predicting negative outcomes                      | Should   |

### 3.4 Insights & Trends

| ID    | Requirement                               | Priority |
| ----- | ----------------------------------------- | -------- |
| IT-01 | Weekly summary of journal themes          | Should   |
| IT-02 | Most common distortions over time         | Must     |
| IT-03 | Sentiment trend visualization             | Must     |
| IT-04 | Correlation with mood entries             | Should   |
| IT-05 | "This time last month" comparisons        | Could    |
| IT-06 | Progress on reducing specific distortions | Should   |

### 3.5 Privacy & Control

| ID    | Requirement                                         | Priority |
| ----- | --------------------------------------------------- | -------- |
| PC-01 | Entries encrypted at rest                           | Must     |
| PC-02 | AI analysis runs on secure server (not third-party) | Must     |
| PC-03 | User can disable AI analysis                        | Must     |
| PC-04 | Export all journal entries                          | Must     |
| PC-05 | Delete individual or all entries                    | Must     |
| PC-06 | Local-only mode option (no sync)                    | Could    |

---

## 4. Technical Requirements

### 4.1 Data Models

```sql
-- Journal entries
CREATE TABLE journal_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    word_count INTEGER NOT NULL,
    mood_tag INTEGER CHECK (mood_tag BETWEEN 1 AND 10),
    prompt_id UUID REFERENCES journal_prompts(id),
    photo_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- AI analysis results
CREATE TABLE journal_analyses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entry_id UUID NOT NULL REFERENCES journal_entries(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Sentiment
    sentiment TEXT CHECK (sentiment IN ('positive', 'negative', 'neutral', 'mixed')),
    sentiment_score DECIMAL(3,2), -- -1.0 to 1.0
    sentiment_intensity DECIMAL(3,2), -- 0.0 to 1.0

    -- Emotions detected
    emotions JSONB, -- [{emotion: "anxiety", intensity: 0.8}, ...]

    -- Themes
    themes TEXT[], -- ['work', 'relationships', 'health']

    -- Cognitive distortions
    distortions JSONB NOT NULL DEFAULT '[]',
    -- [{
    --   type: "catastrophizing",
    --   excerpt: "I'll probably fail the interview",
    --   explanation: "Predicting worst-case without evidence",
    --   reframe: "I have skills that make me a good candidate"
    -- }]

    distortion_count INTEGER DEFAULT 0,

    -- Summary
    ai_summary TEXT, -- 1-2 sentence summary

    analyzed_at TIMESTAMPTZ DEFAULT NOW(),
    model_version TEXT NOT NULL,

    UNIQUE(entry_id)
);

-- Journal prompts library
CREATE TABLE journal_prompts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prompt_text TEXT NOT NULL,
    category TEXT, -- 'gratitude', 'reflection', 'goals', 'emotions'
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User journal settings
CREATE TABLE journal_settings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    ai_analysis_enabled BOOLEAN DEFAULT true,
    show_prompts BOOLEAN DEFAULT true,
    daily_reminder_enabled BOOLEAN DEFAULT false,
    daily_reminder_time TIME,
    local_only_mode BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_analyses ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_prompts ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own entries"
    ON journal_entries FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users view own analyses"
    ON journal_analyses FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Prompts readable by authenticated"
    ON journal_prompts FOR SELECT
    USING (auth.role() = 'authenticated');

CREATE POLICY "Users manage own settings"
    ON journal_settings FOR ALL
    USING (auth.uid() = user_id);

-- Indexes
CREATE INDEX idx_journal_entries_user_date ON journal_entries(user_id, created_at DESC);
CREATE INDEX idx_journal_analyses_distortions ON journal_analyses USING GIN (distortions);
```

### 4.2 Swift Models

```swift
// MARK: - Journal Models

struct JournalEntry: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    var content: String
    var wordCount: Int
    var moodTag: Int?
    var promptId: UUID?
    var photoUrl: URL?
    let createdAt: Date
    var updatedAt: Date

    var analysis: JournalAnalysis?
}

struct JournalAnalysis: Codable {
    let id: UUID
    let entryId: UUID

    let sentiment: Sentiment
    let sentimentScore: Double // -1.0 to 1.0
    let sentimentIntensity: Double // 0.0 to 1.0

    let emotions: [DetectedEmotion]
    let themes: [String]
    let distortions: [CognitiveDistortionInstance]
    let distortionCount: Int

    let aiSummary: String?
    let analyzedAt: Date
    let modelVersion: String

    enum Sentiment: String, Codable {
        case positive, negative, neutral, mixed
    }
}

struct DetectedEmotion: Codable {
    let emotion: String // "anxiety", "sadness", "frustration", etc.
    let intensity: Double // 0.0 to 1.0
}

struct CognitiveDistortionInstance: Identifiable, Codable {
    var id: UUID { UUID() } // Computed for SwiftUI
    let type: CognitiveDistortionType
    let excerpt: String // The sentence/phrase from entry
    let explanation: String // Why it's this distortion
    let reframe: String? // Alternative perspective
}

enum CognitiveDistortionType: String, Codable, CaseIterable {
    case allOrNothing = "all_or_nothing"
    case catastrophizing
    case mindReading = "mind_reading"
    case overgeneralization
    case emotionalReasoning = "emotional_reasoning"
    case shouldStatements = "should_statements"
    case labeling
    case personalization
    case mentalFilter = "mental_filter"
    case fortuneTelling = "fortune_telling"

    var displayName: String {
        switch self {
        case .allOrNothing: return "All-or-Nothing Thinking"
        case .catastrophizing: return "Catastrophizing"
        case .mindReading: return "Mind Reading"
        case .overgeneralization: return "Overgeneralization"
        case .emotionalReasoning: return "Emotional Reasoning"
        case .shouldStatements: return "Should Statements"
        case .labeling: return "Labeling"
        case .personalization: return "Personalization"
        case .mentalFilter: return "Mental Filter"
        case .fortuneTelling: return "Fortune Telling"
        }
    }

    var description: String {
        switch self {
        case .allOrNothing:
            return "Seeing things in black and white, with no middle ground"
        case .catastrophizing:
            return "Expecting the worst possible outcome"
        case .mindReading:
            return "Assuming you know what others are thinking"
        case .overgeneralization:
            return "Making broad conclusions from a single event"
        case .emotionalReasoning:
            return "Believing something is true because it feels that way"
        case .shouldStatements:
            return "Rigid rules about how things 'should' be"
        case .labeling:
            return "Attaching a negative label to yourself or others"
        case .personalization:
            return "Blaming yourself for things outside your control"
        case .mentalFilter:
            return "Focusing on negatives while ignoring positives"
        case .fortuneTelling:
            return "Predicting negative outcomes without evidence"
        }
    }

    var icon: String {
        switch self {
        case .allOrNothing: return "circle.lefthalf.filled"
        case .catastrophizing: return "exclamationmark.triangle"
        case .mindReading: return "brain.head.profile"
        case .overgeneralization: return "arrow.left.arrow.right"
        case .emotionalReasoning: return "heart"
        case .shouldStatements: return "checklist"
        case .labeling: return "tag"
        case .personalization: return "person.crop.circle.badge.exclamationmark"
        case .mentalFilter: return "line.3.horizontal.decrease.circle"
        case .fortuneTelling: return "crystal.ball"
        }
    }
}

struct JournalPrompt: Identifiable, Codable {
    let id: UUID
    let promptText: String
    let category: String?
}

struct JournalSettings: Codable {
    var aiAnalysisEnabled: Bool
    var showPrompts: Bool
    var dailyReminderEnabled: Bool
    var dailyReminderTime: Date?
    var localOnlyMode: Bool

    static var defaults: JournalSettings {
        JournalSettings(
            aiAnalysisEnabled: true,
            showPrompts: true,
            dailyReminderEnabled: false,
            dailyReminderTime: nil,
            localOnlyMode: false
        )
    }
}
```

### 4.3 AI Analysis Edge Function

```typescript
// supabase/functions/analyze-journal/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const COGNITIVE_DISTORTIONS = {
  all_or_nothing: {
    patterns: [
      "always",
      "never",
      "everyone",
      "no one",
      "completely",
      "totally",
      "nothing",
    ],
    description: "Seeing things in black and white",
  },
  catastrophizing: {
    patterns: ["worst", "terrible", "awful", "disaster", "ruin", "what if"],
    description: "Expecting the worst possible outcome",
  },
  mind_reading: {
    patterns: [
      "they think",
      "he thinks",
      "she thinks",
      "probably thinks",
      "must think",
    ],
    description: "Assuming you know what others are thinking",
  },
  should_statements: {
    patterns: ["should", "must", "have to", "ought to", "need to"],
    description: "Rigid rules about how things should be",
  },
  fortune_telling: {
    patterns: [
      "will fail",
      "won't work",
      "going to",
      "bound to",
      "definitely will",
    ],
    description: "Predicting negative outcomes",
  },
};

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

  const { entry_id } = await req.json();

  // Fetch entry
  const { data: entry } = await supabase
    .from("journal_entries")
    .select("*")
    .eq("id", entry_id)
    .eq("user_id", user.id)
    .single();

  if (!entry) {
    return new Response("Entry not found", { status: 404 });
  }

  // Analyze with AI
  const analysis = await analyzeWithAI(entry.content);

  // Store analysis
  const { data: result } = await supabase
    .from("journal_analyses")
    .upsert({
      entry_id: entry_id,
      user_id: user.id,
      sentiment: analysis.sentiment,
      sentiment_score: analysis.sentimentScore,
      sentiment_intensity: analysis.sentimentIntensity,
      emotions: analysis.emotions,
      themes: analysis.themes,
      distortions: analysis.distortions,
      distortion_count: analysis.distortions.length,
      ai_summary: analysis.summary,
      model_version: "grok-beta-v1",
    })
    .select()
    .single();

  return new Response(JSON.stringify(result), {
    headers: { "Content-Type": "application/json" },
  });
});

async function analyzeWithAI(content: string): Promise<any> {
  const prompt = `Analyze this journal entry for a mental wellness app. Provide JSON output only.

Journal entry:
"${content}"

Analyze for:
1. Overall sentiment (positive/negative/neutral/mixed) and score (-1.0 to 1.0)
2. Emotions present with intensity (0.0 to 1.0)
3. Themes (work, relationships, health, finances, self-esteem, family, etc.)
4. Cognitive distortions (see list below)

For cognitive distortions, look for:
- all_or_nothing: Black and white thinking ("always", "never", "everyone")
- catastrophizing: Worst-case thinking ("disaster", "terrible", "what if" spirals)
- mind_reading: Assuming others' thoughts ("they probably think I'm...")
- overgeneralization: Single event to universal ("this always happens")
- emotional_reasoning: Feelings as facts ("I feel stupid so I must be")
- should_statements: Rigid rules ("I should", "I must", "I have to")
- labeling: Global labels ("I'm a failure", "they're a jerk")
- personalization: Taking blame for external events
- mental_filter: Focus on negatives only
- fortune_telling: Predicting negative outcomes

For each distortion found, include:
- The exact excerpt from the text
- Brief explanation of why it's this distortion
- A gentle reframe suggestion

Return JSON in this exact format:
{
    "sentiment": "negative",
    "sentimentScore": -0.6,
    "sentimentIntensity": 0.8,
    "emotions": [{"emotion": "anxiety", "intensity": 0.8}, {"emotion": "frustration", "intensity": 0.5}],
    "themes": ["work", "self-esteem"],
    "distortions": [
        {
            "type": "catastrophizing",
            "excerpt": "I'll probably bomb the interview and never get a good job",
            "explanation": "Predicting worst-case outcome without evidence",
            "reframe": "You have skills and experience. One interview doesn't determine your entire career."
        }
    ],
    "summary": "This entry reflects work-related anxiety with some catastrophic thinking patterns."
}`;

  const response = await fetch("https://api.x.ai/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${Deno.env.get("XAI_API_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "grok-beta",
      messages: [{ role: "user", content: prompt }],
      max_tokens: 1000,
      response_format: { type: "json_object" },
    }),
  });

  const data = await response.json();
  return JSON.parse(data.choices[0].message.content);
}
```

---

## 5. UI/UX Specifications

### 5.1 Journal Entry Screen

```
┌─────────────────────────────────┐
│ ← New Entry              Done   │
├─────────────────────────────────┤
│                                 │
│ Today's Prompt (optional)       │
│ ┌─────────────────────────────┐ │
│ │ What's one thing you're     │ │
│ │ grateful for today?    [×]  │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │                             │ │
│ │ Start writing...            │ │
│ │                             │ │
│ │                             │ │
│ │                             │ │
│ │                             │ │
│ │                             │ │
│ │                             │ │
│ │                             │ │
│ │                             │ │
│ └─────────────────────────────┘ │
│                                 │
│ How are you feeling?            │
│ 😢 😕 😐 🙂 😊                  │
│                                 │
│ [📷 Photo]  [🎤 Voice]  [Save]  │
│                                 │
└─────────────────────────────────┘
```

### 5.2 Entry with Analysis

```
┌─────────────────────────────────┐
│ ← Jan 19, 2026            Edit  │
├─────────────────────────────────┤
│                                 │
│ Work has been so stressful      │
│ lately. I feel like I'm never   │
│ going to get caught up. My      │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│ boss probably thinks I'm        │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│ incompetent. I should be        │
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│ doing better by now.            │
│                                 │
│ Mood: 😕                        │
│                                 │
│ ─────────────────────────────── │
│                                 │
│ AI Insights                     │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 📊 Sentiment: Negative      │ │
│ │ 🎭 Emotions: Anxiety (80%), │ │
│ │    Frustration (50%)        │ │
│ │ 🏷️ Themes: Work, Self-esteem│ │
│ └─────────────────────────────┘ │
│                                 │
│ Thinking Patterns Noticed       │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ ⚠️ Catastrophizing          │ │
│ │ "I'm never going to get     │ │
│ │ caught up"                  │ │
│ │                             │ │
│ │ 💡 Reframe: Feeling behind  │ │
│ │ doesn't mean you'll never   │ │
│ │ catch up. What's one small  │ │
│ │ step you could take today?  │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ ⚠️ Mind Reading             │ │
│ │ "My boss probably thinks    │ │
│ │ I'm incompetent"            │ │
│ │                             │ │
│ │ 💡 Reframe: You don't know  │ │
│ │ what your boss thinks. Have │ │
│ │ they said anything to       │ │
│ │ indicate this?              │ │
│ └─────────────────────────────┘ │
│                                 │
│ [This was helpful]  [Dismiss]   │
│                                 │
└─────────────────────────────────┘
```

### 5.3 Journal Insights Dashboard

```
┌─────────────────────────────────┐
│ ← Journal Insights              │
├─────────────────────────────────┤
│                                 │
│ This Month                      │
│ 12 entries • 3,450 words        │
│                                 │
│ Sentiment Trend                 │
│ ┌─────────────────────────────┐ │
│ │ + ┤      ∙  ∙               │ │
│ │ 0 ┤   ∙∙   ∙  ∙ ∙ ∙         │ │
│ │ - ┤ ∙∙                      │ │
│ │   └──────────────────       │ │
│ │   Week 1   Week 2   Week 3  │ │
│ └─────────────────────────────┘ │
│                                 │
│ Common Themes                   │
│ [Work 45%] [Relationships 25%]  │
│ [Health 15%] [Goals 15%]        │
│                                 │
│ Thinking Patterns               │
│ ┌─────────────────────────────┐ │
│ │ Should Statements    5 times │ │
│ │ ████████░░░░░░░              │ │
│ │                              │ │
│ │ Catastrophizing     3 times │ │
│ │ █████░░░░░░░░░░░             │ │
│ │                              │ │
│ │ Mind Reading        2 times │ │
│ │ ███░░░░░░░░░░░░░             │ │
│ └─────────────────────────────┘ │
│                                 │
│ 📈 Progress: "Should statements"│
│ appeared 40% less this month!   │
│                                 │
└─────────────────────────────────┘
```

---

## 6. Acceptance Criteria

### 6.1 Journal Entry

- [ ] User can write free-form journal entries
- [ ] Auto-save preserves content if app closes
- [ ] Mood can be tagged on entry
- [ ] Voice-to-text input works
- [ ] Entries are encrypted at rest

### 6.2 AI Analysis

- [ ] Analysis runs automatically after save
- [ ] Sentiment is detected accurately
- [ ] Cognitive distortions are identified with excerpts
- [ ] Reframes are provided for each distortion
- [ ] User can disable AI analysis in settings

### 6.3 Insights

- [ ] Weekly/monthly summary is generated
- [ ] Sentiment trend is visualized
- [ ] Most common distortions are shown
- [ ] Progress on reducing distortions is tracked

### 6.4 Privacy

- [ ] User can export all entries
- [ ] User can delete individual entries
- [ ] User can delete all entries
- [ ] Local-only mode prevents cloud sync

---

## 7. Edge Cases & Error Handling

| Scenario                       | Behavior                                         |
| ------------------------------ | ------------------------------------------------ |
| Very short entry (< 10 words)  | Skip distortion analysis; basic sentiment only   |
| Very long entry (> 2000 words) | Analyze first 2000 words; note truncation        |
| AI analysis fails              | Show entry without insights; retry in background |
| Non-English text               | Note that analysis may be less accurate          |
| Entry with only emojis         | Skip analysis; show as entered                   |
| Gibberish/spam text            | Detect and skip analysis                         |

---

## 8. Dependencies

| Dependency           | Reason              |
| -------------------- | ------------------- |
| Grok AI              | Journal analysis    |
| Mood Service         | Mood correlation    |
| Insights Module      | Trend visualization |
| Notification Manager | Journal reminders   |

---

## 9. Rollout Plan

### Phase 1: Core Journaling (Week 1-2)

- Entry creation/editing
- Prompts library
- Basic UI

### Phase 2: AI Analysis (Week 3-4)

- Sentiment analysis
- Distortion detection
- Reframe generation

### Phase 3: Insights (Week 5)

- Trend visualization
- Pattern tracking
- Export functionality
