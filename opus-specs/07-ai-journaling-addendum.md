# Specification Revision Addendum: AI-Powered Journaling

**Spec Version:** 1.1 (Addendum)
**Status:** Approved - Revision to address spec-analyzer feedback
**Original Spec:** `opus-specs/07-ai-journaling.md`
**Date:** 2026-01-19

---

## Addendum Overview

This addendum addresses 8 issues identified by the spec-analyzer:

1. Journal Streak Tracking
2. Personalized Prompt Selection Algorithm
3. Mood-Journal Correlation
4. "Supportive, Not Clinical" Language Enforcement
5. Premium vs Free Tier Differentiation
6. AA-08 Dismiss/Disagree Tracking
7. Auto-save Mechanism
8. Export Format

---

## 1. Journal Streak Tracking

### 1.1 Database Schema Addition

```sql
-- Journal streaks and statistics
CREATE TABLE journal_streaks (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Current streak
    current_streak INTEGER NOT NULL DEFAULT 0,
    streak_started_at DATE,
    last_entry_date DATE,

    -- Best streak
    longest_streak INTEGER NOT NULL DEFAULT 0,
    longest_streak_started_at DATE,
    longest_streak_ended_at DATE,

    -- Lifetime stats
    total_entries INTEGER NOT NULL DEFAULT 0,
    total_words INTEGER NOT NULL DEFAULT 0,
    total_days_with_entries INTEGER NOT NULL DEFAULT 0,

    -- Metadata
    timezone TEXT NOT NULL DEFAULT 'America/Los_Angeles',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE journal_streaks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own streaks"
    ON journal_streaks FOR ALL
    USING (auth.uid() = user_id);

-- Index for fast lookups
CREATE INDEX idx_journal_streaks_user ON journal_streaks(user_id);
```

### 1.2 Streak Calculation Rules (Pseudocode)

```
FUNCTION update_journal_streak(user_id, entry_date, user_timezone):
    // Get user's current streak data
    streak_data = GET journal_streaks WHERE user_id = user_id

    // Convert entry_date to user's local timezone for comparison
    local_entry_date = entry_date AT TIME ZONE user_timezone
    local_today = NOW() AT TIME ZONE user_timezone

    IF streak_data IS NULL:
        // First ever entry
        INSERT INTO journal_streaks:
            current_streak = 1
            streak_started_at = local_entry_date
            last_entry_date = local_entry_date
            longest_streak = 1
            total_entries = 1
        RETURN

    // Check if this is a duplicate entry for today (already counted)
    IF local_entry_date = streak_data.last_entry_date:
        // Same day, just increment entry count, don't affect streak
        UPDATE total_entries = total_entries + 1
        RETURN

    // Calculate days since last entry
    days_gap = local_entry_date - streak_data.last_entry_date

    IF days_gap = 1:
        // Consecutive day - extend streak
        new_streak = streak_data.current_streak + 1
        UPDATE journal_streaks:
            current_streak = new_streak
            last_entry_date = local_entry_date
            total_entries = total_entries + 1
            total_days_with_entries = total_days_with_entries + 1

        // Check if this is a new record
        IF new_streak > streak_data.longest_streak:
            UPDATE longest_streak = new_streak
            UPDATE longest_streak_ended_at = local_entry_date

    ELSE IF days_gap > 1:
        // Streak broken - start new streak
        UPDATE journal_streaks:
            current_streak = 1
            streak_started_at = local_entry_date
            last_entry_date = local_entry_date
            total_entries = total_entries + 1
            total_days_with_entries = total_days_with_entries + 1

    ELSE IF days_gap < 0:
        // Backdated entry - don't affect current streak
        UPDATE total_entries = total_entries + 1
```

### 1.3 Streak Break vs Maintain Rules

| Scenario                            | Streak Action                     | Rationale                      |
| ----------------------------------- | --------------------------------- | ------------------------------ |
| Entry today, entry yesterday        | **Maintain/Extend**               | Consecutive days               |
| Entry today, no entry yesterday     | **Break** (reset to 1)            | Gap in consistency             |
| Multiple entries same day           | **Maintain** (count +1)           | Same day counts once           |
| Backdated entry (past date)         | **No change to current streak**   | Prevents gaming                |
| Entry at 11:59 PM, next at 12:01 AM | **Extend** (uses user's timezone) | Local date comparison          |
| User changes timezone               | **Preserve streak**               | Use last_entry_date comparison |
| Missed day, used "streak freeze"    | **Maintain**                      | Premium feature                |

### 1.4 Swift Model

```swift
struct JournalStreak: Codable {
    let userId: UUID
    let currentStreak: Int
    let streakStartedAt: Date?
    let lastEntryDate: Date?
    let longestStreak: Int
    let longestStreakStartedAt: Date?
    let longestStreakEndedAt: Date?
    let totalEntries: Int
    let totalWords: Int
    let totalDaysWithEntries: Int
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case currentStreak = "current_streak"
        case streakStartedAt = "streak_started_at"
        case lastEntryDate = "last_entry_date"
        case longestStreak = "longest_streak"
        case longestStreakStartedAt = "longest_streak_started_at"
        case longestStreakEndedAt = "longest_streak_ended_at"
        case totalEntries = "total_entries"
        case totalWords = "total_words"
        case totalDaysWithEntries = "total_days_with_entries"
        case timezone
    }

    var streakMessage: String {
        switch currentStreak {
        case 0: return "Start your journaling journey today!"
        case 1: return "Great start! Write again tomorrow to build your streak."
        case 2...6: return "\(currentStreak)-day streak! Keep it going!"
        case 7...13: return "🔥 \(currentStreak)-day streak! You're building a habit!"
        case 14...29: return "🔥🔥 \(currentStreak)-day streak! Incredible consistency!"
        case 30...59: return "🔥🔥🔥 \(currentStreak) days! You're a journaling master!"
        default: return "🔥🔥🔥🔥 \(currentStreak) days! Legendary dedication!"
        }
    }

    var nextMilestone: Int {
        let milestones = [7, 14, 30, 60, 90, 180, 365]
        return milestones.first { $0 > currentStreak } ?? currentStreak + 30
    }

    var milestoneProgress: Double {
        let previous = [0, 7, 14, 30, 60, 90, 180].last { $0 < nextMilestone } ?? 0
        let range = nextMilestone - previous
        let progress = currentStreak - previous
        return Double(progress) / Double(range)
    }
}
```

---

## 2. Personalized Prompt Selection Algorithm

### 2.1 Extended Schema

```sql
-- Extend journal_prompts table
ALTER TABLE journal_prompts ADD COLUMN IF NOT EXISTS
    mood_affinity JSONB DEFAULT '{"low": 0.5, "medium": 0.5, "high": 0.5}';

ALTER TABLE journal_prompts ADD COLUMN IF NOT EXISTS
    emotion_tags TEXT[] DEFAULT '{}';

ALTER TABLE journal_prompts ADD COLUMN IF NOT EXISTS
    time_of_day TEXT CHECK (time_of_day IN ('morning', 'afternoon', 'evening', 'any')) DEFAULT 'any';

ALTER TABLE journal_prompts ADD COLUMN IF NOT EXISTS
    effectiveness_score DECIMAL(3,2) DEFAULT 0.5;

-- Track which prompts were shown to users
CREATE TABLE journal_prompt_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    prompt_id UUID NOT NULL REFERENCES journal_prompts(id) ON DELETE CASCADE,
    shown_at TIMESTAMPTZ DEFAULT NOW(),
    mood_context TEXT,
    was_used BOOLEAN DEFAULT false,
    entry_id UUID REFERENCES journal_entries(id),

    UNIQUE(user_id, prompt_id, DATE(shown_at))
);

ALTER TABLE journal_prompt_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own prompt history" ON journal_prompt_history FOR ALL USING (auth.uid() = user_id);

CREATE INDEX idx_prompt_history_user ON journal_prompt_history(user_id, shown_at DESC);
```

### 2.2 Prompt Categories with Mood Affinity

| Category             | Description           | Low Mood (1-3) | Mid Mood (4-6) | High Mood (7-10) |
| -------------------- | --------------------- | -------------- | -------------- | ---------------- |
| `gratitude`          | Count blessings       | 0.6            | 0.8            | 0.9              |
| `reflection`         | Daily review          | 0.5            | 0.9            | 0.7              |
| `emotion_processing` | Work through feelings | 0.9            | 0.6            | 0.3              |
| `goals`              | Future planning       | 0.3            | 0.7            | 0.9              |
| `self_compassion`    | Self-kindness         | 0.9            | 0.5            | 0.4              |
| `cognitive_reframe`  | Challenge thoughts    | 0.8            | 0.6            | 0.2              |
| `celebration`        | Acknowledge wins      | 0.4            | 0.7            | 0.9              |
| `anxiety_relief`     | Calm anxiety          | 0.9            | 0.4            | 0.2              |

### 2.3 Selection Algorithm (Pseudocode)

```
FUNCTION select_personalized_prompts(user_id, num_prompts=3):
    // STEP 1: Gather user's recent mood data
    recent_moods = GET moods WHERE user_id = user_id
                   AND created_at > NOW() - 7 DAYS
                   ORDER BY created_at DESC LIMIT 14

    // STEP 2: Calculate mood context
    IF recent_moods IS EMPTY:
        mood_bucket = 'medium'
        dominant_emotions = []
    ELSE:
        avg_mood = AVERAGE(recent_moods.score)

        IF avg_mood <= 3:
            mood_bucket = 'low'
        ELSE IF avg_mood <= 6:
            mood_bucket = 'medium'
        ELSE:
            mood_bucket = 'high'

        // Detect dominant emotions from recent journal analyses
        recent_analyses = GET journal_analyses
                         WHERE user_id = user_id
                         AND analyzed_at > NOW() - 7 DAYS

        dominant_emotions = AGGREGATE emotions FROM recent_analyses
                           GROUP BY emotion ORDER BY COUNT DESC LIMIT 3

    // STEP 3: Determine time-of-day preference
    current_hour = EXTRACT(HOUR FROM NOW() AT TIME ZONE user_timezone)
    IF current_hour BETWEEN 5 AND 11:
        time_preference = 'morning'
    ELSE IF current_hour BETWEEN 12 AND 17:
        time_preference = 'afternoon'
    ELSE:
        time_preference = 'evening'

    // STEP 4: Build weighted prompt pool
    all_prompts = GET journal_prompts WHERE is_active = true

    FOR EACH prompt IN all_prompts:
        weight = 1.0

        // Apply mood affinity weight
        mood_weight = prompt.mood_affinity[mood_bucket] OR 0.5
        weight = weight * mood_weight

        // Boost prompts matching dominant emotions
        FOR EACH emotion IN dominant_emotions:
            IF emotion IN prompt.emotion_tags:
                weight = weight * 1.3

        // Boost time-appropriate prompts
        IF prompt.time_of_day = time_preference OR prompt.time_of_day = 'any':
            weight = weight * 1.2
        ELSE:
            weight = weight * 0.5

        // Apply effectiveness score
        weight = weight * (0.5 + prompt.effectiveness_score)

        // Penalize recently shown prompts
        last_shown = GET prompt_history WHERE user_id = user_id
                     AND prompt_id = prompt.id
                     ORDER BY shown_at DESC LIMIT 1

        IF last_shown EXISTS:
            days_ago = (NOW() - last_shown.shown_at) / 1 DAY
            IF days_ago < 3:
                weight = weight * 0.1
            ELSE IF days_ago < 7:
                weight = weight * 0.5

        prompt.selection_weight = weight

    // STEP 5: Select top prompts with randomization
    sorted_prompts = SORT all_prompts BY selection_weight DESC
    candidates = sorted_prompts[0:10]
    selected = WEIGHTED_RANDOM_SAMPLE(candidates, num_prompts, weight_field='selection_weight')

    // STEP 6: Record what was shown
    FOR EACH prompt IN selected:
        INSERT INTO prompt_history (user_id, prompt_id, shown_at, mood_context)
        VALUES (user_id, prompt.id, NOW(), mood_bucket)

    RETURN selected
```

### 2.4 Edge Case: No Mood History

For new users without mood history, return curated onboarding prompts:

- "What brings you to journaling today?"
- "Describe your day in three words."
- "What's one thing you're looking forward to?"

---

## 3. Mood-Journal Correlation

### 3.1 Correlation Calculation (Pearson's r)

```
r = Σ[(xi - x̄)(yi - ȳ)] / √[Σ(xi - x̄)² × Σ(yi - ȳ)²]

Where:
- xi = journal sentiment score (normalized to 0-10)
- yi = mood score for same day (1-10)
```

### 3.2 SQL Function

```sql
CREATE OR REPLACE FUNCTION calculate_mood_journal_correlation(
    p_user_id UUID,
    p_time_window_days INTEGER DEFAULT 30
)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
    v_min_sample INTEGER := 7;
BEGIN
    WITH paired_data AS (
        SELECT
            DATE(m.created_at AT TIME ZONE 'UTC') as day,
            AVG(m.score) as mood_score,
            AVG((ja.sentiment_score + 1) * 5) as journal_sentiment_normalized
        FROM moods m
        JOIN journal_entries je ON je.user_id = m.user_id
            AND DATE(je.created_at AT TIME ZONE 'UTC') = DATE(m.created_at AT TIME ZONE 'UTC')
        JOIN journal_analyses ja ON ja.entry_id = je.id
        WHERE m.user_id = p_user_id
            AND m.created_at > NOW() - (p_time_window_days || ' days')::INTERVAL
        GROUP BY DATE(m.created_at AT TIME ZONE 'UTC')
    ),
    stats AS (
        SELECT
            COUNT(*) as n,
            AVG(mood_score) as mood_mean,
            AVG(journal_sentiment_normalized) as sentiment_mean,
            STDDEV_POP(mood_score) as mood_stddev,
            STDDEV_POP(journal_sentiment_normalized) as sentiment_stddev
        FROM paired_data
    ),
    correlation AS (
        SELECT
            s.n,
            CASE
                WHEN s.mood_stddev = 0 OR s.sentiment_stddev = 0 THEN 0
                ELSE COALESCE(
                    SUM((p.mood_score - s.mood_mean) * (p.journal_sentiment_normalized - s.sentiment_mean)) /
                    NULLIF(s.n * s.mood_stddev * s.sentiment_stddev, 0),
                    0
                )
            END as pearson_r
        FROM paired_data p, stats s
        GROUP BY s.n, s.mood_stddev, s.sentiment_stddev, s.mood_mean, s.sentiment_mean
    )
    SELECT
        jsonb_build_object(
            'sample_size', COALESCE(c.n, 0),
            'correlation_coefficient', ROUND(COALESCE(c.pearson_r, 0)::NUMERIC, 3),
            'is_significant', c.n >= v_min_sample,
            'interpretation', CASE
                WHEN c.n < v_min_sample THEN 'insufficient_data'
                WHEN ABS(c.pearson_r) >= 0.7 THEN 'strong'
                WHEN ABS(c.pearson_r) >= 0.4 THEN 'moderate'
                WHEN ABS(c.pearson_r) >= 0.2 THEN 'weak'
                ELSE 'negligible'
            END,
            'direction', CASE
                WHEN c.pearson_r > 0 THEN 'positive'
                WHEN c.pearson_r < 0 THEN 'negative'
                ELSE 'none'
            END,
            'time_window_days', p_time_window_days
        ) INTO v_result
    FROM correlation c;

    RETURN COALESCE(v_result, jsonb_build_object('sample_size', 0, 'is_significant', false));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 3.3 Interpretation Thresholds

| Correlation       | Range          | Template                                                                                                    |
| ----------------- | -------------- | ----------------------------------------------------------------------------------------------------------- |
| Strong positive   | r >= 0.7       | "Your journal entries closely match your mood. When you write positively, you tend to report higher moods." |
| Moderate positive | 0.4 <= r < 0.7 | "There's a connection between your writing tone and mood. Journaling may help you process emotions."        |
| Weak positive     | 0.2 <= r < 0.4 | "Your journal tone somewhat reflects your mood."                                                            |
| Negligible        | r < 0.2        | "Your journal content varies independently of your mood. This is normal."                                   |
| Insufficient data | n < 7          | "Keep journaling! After 7 days with both mood logs and entries, we'll show you personalized patterns."      |

### 3.4 Swift Model

```swift
struct MoodJournalCorrelation: Codable {
    let sampleSize: Int
    let correlationCoefficient: Double
    let isSignificant: Bool
    let interpretation: CorrelationStrength
    let direction: CorrelationDirection
    let timeWindowDays: Int

    enum CorrelationStrength: String, Codable {
        case insufficientData = "insufficient_data"
        case negligible, weak, moderate, strong
    }

    enum CorrelationDirection: String, Codable {
        case positive, negative, none
    }

    enum CodingKeys: String, CodingKey {
        case sampleSize = "sample_size"
        case correlationCoefficient = "correlation_coefficient"
        case isSignificant = "is_significant"
        case interpretation, direction
        case timeWindowDays = "time_window_days"
    }

    var insightMessage: String {
        guard isSignificant else {
            return "Keep journaling! After 7 days with both mood logs and entries, we'll show you personalized patterns."
        }

        switch (interpretation, direction) {
        case (.strong, .positive):
            return "Your journal entries closely match your mood. When you write positively, you tend to report higher moods."
        case (.moderate, .positive):
            return "There's a connection between your writing tone and mood. Journaling may help you process emotions."
        case (.weak, .positive):
            return "Your journal tone somewhat reflects your mood."
        case (_, .negative):
            return "Interestingly, you often journal about challenges even when your mood is good. This shows healthy processing."
        default:
            return "Your journal content varies independently of your mood. This is normal."
        }
    }
}
```

---

## 4. "Supportive, Not Clinical" Language Enforcement

### 4.1 Core Tone Principles

1. **Warmth over authority** - Sound like a caring friend, not a textbook
2. **Curiosity over judgment** - Ask questions, don't diagnose
3. **Empowerment over prescription** - Suggest exploration, not mandates
4. **Normalization over pathologizing** - "Many people experience this" not "This is a symptom of..."

### 4.2 Banned Words/Phrases

| Category         | Banned                                                     | Reason                        |
| ---------------- | ---------------------------------------------------------- | ----------------------------- |
| **Prescriptive** | "You should", "You must", "You need to", "You have to"     | Removes user agency           |
| **Judgmental**   | "That's wrong", "That's bad", "You're being irrational"    | Creates shame                 |
| **Clinical**     | "Diagnosis", "Disorder", "Symptom", "Treatment", "Patient" | Medicalizes normal emotions   |
| **Absolutist**   | "Always", "Never", "Completely" (when describing user)     | Mirrors cognitive distortions |
| **Dismissive**   | "Just relax", "Don't worry", "It's not a big deal"         | Invalidates feelings          |
| **Labeling**     | "You are anxious", "You are depressed"                     | Identity vs experience        |

### 4.3 Required Patterns

| Pattern                         | Example                                                      | Purpose                   |
| ------------------------------- | ------------------------------------------------------------ | ------------------------- |
| **Questions over statements**   | "What might happen if...?"                                   | Promotes reflection       |
| **"I notice" language**         | "I notice some all-or-nothing thinking here"                 | Observation, not judgment |
| **Invitation language**         | "You might consider...", "Some people find it helpful to..." | Respects autonomy         |
| **"It sounds like" validation** | "It sounds like this has been really hard"                   | Empathy before advice     |
| **Normalizing phrases**         | "Many people experience...", "It's common to feel..."        | Reduces shame             |

### 4.4 Good vs Bad Reframe Examples

**Scenario: User writes "I'll never get promoted, I'm such a failure"**

| Bad (Clinical)                                                                 | Good (Supportive)                                                                                                                                    |
| ------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| "This is an example of labeling. You should avoid calling yourself a failure." | "I notice some really harsh self-talk here. 'Never' and 'failure' are pretty strong words. What would you say to a friend who was feeling this way?" |

**Scenario: User catastrophizes about a presentation**

| Bad                                                     | Good                                                                                                                                  |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| "You're catastrophizing. Focus on facts, not feelings." | "It sounds like this presentation feels really high-stakes right now. What's one small thing that's gone well in past presentations?" |

### 4.5 AI System Prompt Enhancement

```typescript
const JOURNAL_ANALYSIS_SYSTEM_PROMPT = `
You are a compassionate journaling companion analyzing a user's journal entry.

TONE REQUIREMENTS (CRITICAL):
- Be warm and supportive, like a caring friend
- Use "I notice..." instead of "You are..."
- Ask reflective questions instead of giving advice
- Validate feelings before offering perspective
- Use phrases like "many people find..." or "you might consider..."

NEVER USE:
- "You should", "You must", "You need to"
- "That's wrong", "That's irrational"
- Clinical terms: diagnosis, disorder, symptom, treatment
- Dismissive phrases: "just relax", "don't worry"
- Labels as identity: "You are anxious" (use "you're experiencing anxiety")

ALWAYS:
- Acknowledge the emotion first: "It sounds like..."
- Normalize the experience: "It's understandable that..."
- Offer reframes as invitations: "What if..." or "I wonder..."
- End with a gentle question for reflection

REFRAME FORMAT:
1. Validate: Acknowledge the feeling behind the thought
2. Observe: Gently name the pattern without judgment
3. Invite: Offer an alternative perspective as a question
`;
```

### 4.6 Post-Processing Validation

```typescript
const BANNED_PATTERNS = [
  /\byou (should|must|need to|have to)\b/gi,
  /\bthat'?s (wrong|bad|irrational)\b/gi,
  /\b(diagnosis|disorder|symptom|treatment|patient)\b/gi,
  /\bjust (relax|calm down|don't worry)\b/gi,
  /\byou are (anxious|depressed|broken|damaged)\b/gi,
];

const REQUIRED_PATTERNS = [
  /\b(sounds like|seems like|appears)\b/i,
  /\b(many people|it'?s common|understandable)\b/i,
  /\?\s*$/,
];

function validateReframeTone(reframeText: string): {
  isValid: boolean;
  violations: string[];
} {
  const violations: string[] = [];

  for (const pattern of BANNED_PATTERNS) {
    if (pattern.test(reframeText)) {
      violations.push(`Contains banned pattern: ${pattern.source}`);
    }
  }

  return { isValid: violations.length === 0, violations };
}

async function ensureSupportiveTone(reframeText: string): Promise<string> {
  const validation = validateReframeTone(reframeText);

  if (validation.isValid) {
    return reframeText;
  }

  // Regenerate with correction prompt
  const correctionPrompt = `
    Rewrite this to be warm, question-based, and non-prescriptive:
    Original: "${reframeText}"
    Issues: ${validation.violations.join(", ")}
    `;

  return await regenerateWithCorrection(correctionPrompt);
}
```

---

## 5. Premium vs Free Tier Differentiation

### 5.1 Entitlements Table

| Feature                     | Free Tier              | Premium Tier                          |
| --------------------------- | ---------------------- | ------------------------------------- |
| Journal entries per day     | **3**                  | Unlimited                             |
| AI analyses per day         | **1**                  | Unlimited                             |
| Export entries              | Last 7 days            | All time                              |
| Prompt library access       | 20 basic prompts       | 200+ prompts                          |
| Cognitive distortion detail | Type only              | Type + explanation + reframe          |
| Insights dashboard          | Basic (sentiment only) | Full (themes, patterns, correlations) |
| Voice journaling            | 2 min/day              | 10 min/entry                          |
| Streak freeze               | Not available          | 2 per month                           |

### 5.2 Database Schema for Limits

```sql
-- Track daily usage for journaling
CREATE TABLE journal_daily_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    usage_date DATE NOT NULL DEFAULT CURRENT_DATE,

    entries_created INTEGER DEFAULT 0,
    analyses_requested INTEGER DEFAULT 0,
    voice_minutes_used DECIMAL(5,2) DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_id, usage_date)
);

ALTER TABLE journal_daily_usage ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own usage" ON journal_daily_usage FOR ALL USING (auth.uid() = user_id);

-- Streak freezes (premium feature)
CREATE TABLE journal_streak_freezes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    freeze_date DATE NOT NULL,
    used_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_id, freeze_date)
);

ALTER TABLE journal_streak_freezes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own freezes" ON journal_streak_freezes FOR ALL USING (auth.uid() = user_id);

CREATE INDEX idx_journal_usage_user_date ON journal_daily_usage(user_id, usage_date);
```

### 5.3 Limit Checking Function

```typescript
interface JournalEntitlements {
  entriesPerDay: number | null;
  analysesPerDay: number | null;
  voiceMinutesPerDay: number;
  canExportAllTime: boolean;
  canAccessFullPrompts: boolean;
  canSeeDetailedDistortions: boolean;
  canUseStreakFreeze: boolean;
}

const FREE_TIER: JournalEntitlements = {
  entriesPerDay: 3,
  analysesPerDay: 1,
  voiceMinutesPerDay: 2,
  canExportAllTime: false,
  canAccessFullPrompts: false,
  canSeeDetailedDistortions: false,
  canUseStreakFreeze: false,
};

const PREMIUM_TIER: JournalEntitlements = {
  entriesPerDay: null,
  analysesPerDay: null,
  voiceMinutesPerDay: 10,
  canExportAllTime: true,
  canAccessFullPrompts: true,
  canSeeDetailedDistortions: true,
  canUseStreakFreeze: true,
};

async function checkJournalLimit(
  supabase: SupabaseClient,
  userId: string,
  action: "entry" | "analysis" | "voice",
): Promise<{
  allowed: boolean;
  remaining: number | null;
  upgradePrompt?: string;
}> {
  const isPremium = await checkPremiumStatus(supabase, userId);
  const entitlements = isPremium ? PREMIUM_TIER : FREE_TIER;

  const today = new Date().toISOString().split("T")[0];
  const { data: usage } = await supabase
    .from("journal_daily_usage")
    .select("*")
    .eq("user_id", userId)
    .eq("usage_date", today)
    .single();

  const currentUsage = usage || { entries_created: 0, analyses_requested: 0 };

  switch (action) {
    case "entry":
      if (entitlements.entriesPerDay === null)
        return { allowed: true, remaining: null };
      const remaining =
        entitlements.entriesPerDay - currentUsage.entries_created;
      return {
        allowed: remaining > 0,
        remaining: Math.max(0, remaining),
        upgradePrompt:
          remaining <= 0
            ? "You've reached your daily limit. Upgrade for unlimited entries."
            : undefined,
      };
    // ... similar for analysis and voice
  }
}
```

### 5.4 Behavior When Limit Reached

| Scenario               | Behavior                     | UI                                           |
| ---------------------- | ---------------------------- | -------------------------------------------- |
| Entry limit reached    | Block new entry creation     | Show upgrade modal with "3/3 entries today"  |
| Analysis limit reached | Save entry but skip analysis | Show entry without insights + upgrade banner |
| Voice limit reached    | Stop recording, save current | "Upgrade for longer recordings."             |

---

## 6. AA-08 Dismiss/Disagree Tracking

### 6.1 Database Schema

```sql
-- Track user feedback on AI-detected distortions
CREATE TABLE journal_distortion_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    analysis_id UUID NOT NULL REFERENCES journal_analyses(id) ON DELETE CASCADE,
    distortion_index INTEGER NOT NULL,

    feedback_type TEXT NOT NULL CHECK (feedback_type IN (
        'helpful', 'not_helpful', 'disagree', 'dismissed'
    )),

    user_comment TEXT,
    original_distortion_type TEXT NOT NULL,
    original_excerpt TEXT NOT NULL,

    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(analysis_id, distortion_index)
);

ALTER TABLE journal_distortion_feedback ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own feedback" ON journal_distortion_feedback FOR ALL USING (auth.uid() = user_id);

-- Extend journal_analyses
ALTER TABLE journal_analyses ADD COLUMN IF NOT EXISTS
    distortions_dismissed INTEGER[] DEFAULT '{}';

ALTER TABLE journal_analyses ADD COLUMN IF NOT EXISTS
    user_feedback_summary JSONB DEFAULT '{}';
```

### 6.2 Learning from Feedback

```typescript
async function recordDistortionFeedback(
  supabase: SupabaseClient,
  userId: string,
  analysisId: string,
  distortionIndex: number,
  feedbackType: "helpful" | "not_helpful" | "disagree" | "dismissed",
): Promise<void> {
  const { data: analysis } = await supabase
    .from("journal_analyses")
    .select("distortions")
    .eq("id", analysisId)
    .single();

  const distortion = analysis.distortions[distortionIndex];

  await supabase.from("journal_distortion_feedback").upsert({
    user_id: userId,
    analysis_id: analysisId,
    distortion_index: distortionIndex,
    feedback_type: feedbackType,
    original_distortion_type: distortion.type,
    original_excerpt: distortion.excerpt,
  });

  // If user disagrees frequently, adjust sensitivity
  if (feedbackType === "disagree") {
    await adjustDistortionSensitivity(supabase, userId, distortion.type);
  }
}
```

---

## 7. Auto-save Mechanism

### 7.1 Specification

| Parameter               | Value                   | Rationale                              |
| ----------------------- | ----------------------- | -------------------------------------- |
| Debounce interval       | 2 seconds               | Balance responsiveness and performance |
| Save location           | Local first, then cloud | Offline resilience                     |
| Draft retention         | 7 days                  | Reasonable recovery window             |
| Maximum drafts per user | 5                       | Prevent storage bloat                  |

### 7.2 Database Schema for Drafts

```sql
CREATE TABLE journal_drafts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    content TEXT NOT NULL,
    word_count INTEGER DEFAULT 0,
    prompt_id UUID REFERENCES journal_prompts(id),
    mood_tag INTEGER CHECK (mood_tag BETWEEN 1 AND 10),

    last_modified_at TIMESTAMPTZ DEFAULT NOW(),
    device_id TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '7 days')
);

ALTER TABLE journal_drafts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users manage own drafts" ON journal_drafts FOR ALL USING (auth.uid() = user_id);

CREATE INDEX idx_drafts_expiry ON journal_drafts(expires_at);
```

### 7.3 Swift Auto-save Implementation

```swift
@MainActor
final class JournalEntryViewModel: ObservableObject {
    @Published var content: String = "" {
        didSet { scheduleAutoSave() }
    }

    private var autoSaveTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval = 2.0

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()

        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(2_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.performAutoSave()
        }
    }

    private func performAutoSave() async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // 1. Save locally first
        saveToLocalStorage()

        // 2. Then sync to cloud
        await syncToCloud()
    }
}
```

---

## 8. Export Format

### 8.1 Format Specification

| Format       | When to Use                     | Includes                       |
| ------------ | ------------------------------- | ------------------------------ |
| **JSON**     | Data portability, backup        | Entries + analyses + metadata  |
| **Markdown** | Human readable, therapy sharing | Entries + insights (formatted) |
| **PDF**      | Printing, formal sharing        | Entries + insights + charts    |

### 8.2 JSON Export Schema

```typescript
interface JournalExport {
  exportVersion: "1.0";
  exportedAt: string;
  userId: string;
  dateRange: { from: string; to: string };

  entries: Array<{
    id: string;
    date: string;
    time: string;
    content: string;
    wordCount: number;
    moodTag?: number;
    prompt?: string;
  }>;

  analyses?: Array<{
    entryId: string;
    sentiment: string;
    sentimentScore: number;
    emotions: Array<{ emotion: string; intensity: number }>;
    themes: string[];
    distortions: Array<{ type: string; excerpt: string; reframe?: string }>;
  }>;

  statistics: {
    totalEntries: number;
    totalWords: number;
    averageSentiment: number;
    topThemes: string[];
    distortionFrequency: Record<string, number>;
  };
}
```

### 8.3 File Naming Convention

```
mindfriend_journal_export_[YYYY-MM-DD]_[format].[ext]

Examples:
- mindfriend_journal_export_2026-01-19_full.json
- mindfriend_journal_export_2026-01-19_entries.md
- mindfriend_journal_export_2026-01-19_report.pdf
```

---

## 9. Additional Edge Cases

| Scenario                        | Behavior                                                         |
| ------------------------------- | ---------------------------------------------------------------- |
| Empty entry submission          | Show validation: "Write at least a few words before saving"      |
| Network failure during analysis | Save entry locally, show "Analysis pending", retry in background |
| Repeated failures (3x)          | Save entry, show "Analysis unavailable" with manual retry button |
| Rate limiting exceeded          | Queue requests, show loading state                               |

---

## 10. Testable Acceptance Criteria

### Streak Tracking

- [ ] AC-STR-01: Creating first entry sets `current_streak = 1`
- [ ] AC-STR-02: Entry on consecutive day increments streak
- [ ] AC-STR-03: Missing a day resets streak to 1 on next entry
- [ ] AC-STR-04: Multiple entries same day count once for streak

### Prompt Selection

- [ ] AC-PRM-01: New user with no moods gets default prompts
- [ ] AC-PRM-02: User with low recent mood gets emotion_processing prompts weighted higher
- [ ] AC-PRM-03: Same prompt not shown twice within 3 days

### Mood Correlation

- [ ] AC-COR-01: Correlation returns `insufficient_data` with < 7 paired days
- [ ] AC-COR-02: Pearson r calculated correctly (within 0.01 of expected)

### Tone Validation

- [ ] AC-TONE-01: AI reframes never contain "you should"
- [ ] AC-TONE-02: AI reframes end with a question 90%+ of the time

### Entitlements

- [ ] AC-ENT-01: Free user blocked at 4th entry attempt
- [ ] AC-ENT-02: Free user sees analysis for first entry only
- [ ] AC-ENT-03: Premium user has no entry limit

### Auto-save

- [ ] AC-SAVE-01: Draft saved locally within 2.5s of typing stop
- [ ] AC-SAVE-02: App crash preserves draft
- [ ] AC-SAVE-03: Drafts expire after 7 days

### Export

- [ ] AC-EXP-01: JSON export validates against schema
- [ ] AC-EXP-02: Free tier limited to 7 days

---

**Addendum Version:** 1.0
**Status:** Ready for Implementation
