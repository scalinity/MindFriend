# Content That Compounds: Weekly Insights

## Overview

**Goal:** Generate AI-powered weekly insights from user data that reveal patterns, celebrate progress, and provide personalized recommendations. Data that only exists because they use the app creates switching cost.

**Why it matters:** Static content gets stale. Users need to see the value of their accumulated data - mood patterns, journaling themes, exercise preferences. Weekly insights transform raw data into actionable wisdom that feels personalized and valuable.

**Impact:** P6 priority - Value that compounds over time

---

## User Stories

- As a user, I want to see my weekly mood summary so that I can understand my emotional patterns
- As a user, I want the AI to detect patterns in my data so that I can make better decisions
- As a user, I want personalized recommendations so that my wellness practice evolves
- As a user, I want to see my progress over time so that I feel motivated to continue

---

## Product Requirements

### Must Have (MVP)

1. **Weekly Mood Analysis**
   - Average mood score for the week
   - Comparison to previous week
   - Day-by-day mood visualization
   - Trend indicator (improving/stable/declining)

2. **Pattern Detection**
   - Time-based patterns ("You tend to feel anxious on Mondays")
   - Activity correlations ("Your mood improves after breathing exercises")
   - Streak impact ("Your 7-day streak correlates with higher mood")

3. **AI-Generated Insight**
   - 2-3 sentence personalized observation
   - Based on actual user data
   - Actionable suggestion included

4. **Weekly Summary Push**
   - Sunday evening notification
   - Deep link to insights screen
   - Opt-out available

### Nice to Have (V2)

- Monthly/yearly insights
- Journal entry word cloud
- Exercise type effectiveness analysis
- Social comparison (anonymized averages)
- Export insights as PDF
- Mood predictions

### Out of Scope

- Real-time pattern detection
- Clinical assessments
- Sharing insights publicly
- Third-party data integration

---

## Technical Design

### Data Model Changes

```sql
-- Migration: 20260120_weekly_insights.sql

CREATE TABLE weekly_insights (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  week_start DATE NOT NULL,
  week_end DATE NOT NULL,

  -- Mood metrics
  mood_count INT DEFAULT 0,
  mood_avg FLOAT,
  mood_min INT,
  mood_max INT,
  mood_trend TEXT CHECK (mood_trend IN ('improving', 'stable', 'declining', 'insufficient_data')),
  mood_by_day JSONB,  -- {"mon": 3.5, "tue": 4.0, ...}

  -- Activity metrics
  quest_count INT DEFAULT 0,
  exercise_count INT DEFAULT 0,
  exercise_minutes INT DEFAULT 0,
  checkin_count INT DEFAULT 0,
  journal_count INT DEFAULT 0,

  -- Patterns detected
  patterns_detected JSONB DEFAULT '[]'::jsonb,
  -- Example: [{"type": "time", "description": "Higher mood on weekends", "confidence": 0.8}]

  -- AI-generated content
  ai_insight TEXT,
  ai_recommendations JSONB DEFAULT '[]'::jsonb,
  -- Example: [{"title": "Try morning meditation", "reason": "Your mood peaks after meditation"}]

  -- Meta
  generated_at TIMESTAMPTZ DEFAULT NOW(),
  notification_sent_at TIMESTAMPTZ,

  UNIQUE(user_id, week_start)
);

CREATE INDEX idx_insights_user_week ON weekly_insights(user_id, week_start DESC);

-- Journal analysis (for pattern detection)
CREATE TABLE journal_analyses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  journal_entry_id UUID,  -- Reference to exercise_sessions with journaling type
  themes JSONB DEFAULT '[]'::jsonb,  -- ["work", "stress", "family"]
  sentiment FLOAT,  -- -1 to 1
  key_phrases JSONB DEFAULT '[]'::jsonb,
  analyzed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_journal_analysis_user ON journal_analyses(user_id, analyzed_at DESC);

-- RLS
ALTER TABLE weekly_insights ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_analyses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users see own insights" ON weekly_insights
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users see own journal analyses" ON journal_analyses
  FOR SELECT USING (auth.uid() = user_id);
```

### iOS Implementation

**New Models** (`Core/Models.swift`):

```swift
struct WeeklyInsight: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let weekStart: Date
    let weekEnd: Date

    // Mood metrics
    let moodCount: Int
    let moodAvg: Double?
    let moodMin: Int?
    let moodMax: Int?
    let moodTrend: MoodTrend?
    let moodByDay: [String: Double]?

    // Activity metrics
    let questCount: Int
    let exerciseCount: Int
    let exerciseMinutes: Int
    let checkinCount: Int
    let journalCount: Int

    // Patterns
    let patternsDetected: [Pattern]?

    // AI content
    let aiInsight: String?
    let aiRecommendations: [Recommendation]?

    let generatedAt: Date

    enum MoodTrend: String, Codable {
        case improving, stable, declining, insufficientData = "insufficient_data"

        var emoji: String {
            switch self {
            case .improving: return "📈"
            case .stable: return "➡️"
            case .declining: return "📉"
            case .insufficientData: return "❓"
            }
        }

        var message: String {
            switch self {
            case .improving: return "Your mood is trending up!"
            case .stable: return "Your mood has been steady."
            case .declining: return "It's been a challenging week."
            case .insufficientData: return "Log more moods to see trends."
            }
        }

        var color: Color {
            switch self {
            case .improving: return .green
            case .stable: return .blue
            case .declining: return .orange
            case .insufficientData: return .gray
            }
        }
    }

    struct Pattern: Codable {
        let type: String  // "time", "activity", "streak"
        let description: String
        let confidence: Double
    }

    struct Recommendation: Codable {
        let title: String
        let reason: String
    }
}

extension WeeklyInsight {
    var weekLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: weekStart)) - \(formatter.string(from: weekEnd))"
    }

    var moodChangeFromLastWeek: Double? {
        // Would need previous week data
        nil
    }
}
```

**Service Methods** (`Networking/Services/SupabaseDataService.swift`):

```swift
// MARK: - Weekly Insights

func getCurrentWeekInsight() async throws -> WeeklyInsight? {
    let weekStart = getWeekStart(for: Date())

    let insights: [WeeklyInsight] = try await supabase
        .from("weekly_insights")
        .select()
        .eq("user_id", try await getCurrentUserId())
        .eq("week_start", weekStart.ISO8601Format().split(separator: "T").first!)
        .limit(1)
        .execute()
        .value

    return insights.first
}

func getInsightsHistory(limit: Int = 12) async throws -> [WeeklyInsight] {
    try await supabase
        .from("weekly_insights")
        .select()
        .eq("user_id", try await getCurrentUserId())
        .order("week_start", ascending: false)
        .limit(limit)
        .execute()
        .value
}

private func getWeekStart(for date: Date) -> Date {
    var calendar = Calendar.current
    calendar.firstWeekday = 2 // Monday
    return calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
}
```

**New Views** (`Features/Insights/`):

```swift
// WeeklyInsightsView.swift
struct WeeklyInsightsView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var currentInsight: WeeklyInsight?
    @State private var pastInsights: [WeeklyInsight] = []
    @State private var isLoading = true
    @State private var selectedTab = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Current week summary
                if let insight = currentInsight {
                    CurrentWeekCard(insight: insight)

                    MoodChartCard(insight: insight)

                    if let patterns = insight.patternsDetected, !patterns.isEmpty {
                        PatternsCard(patterns: patterns)
                    }

                    if let aiInsight = insight.aiInsight {
                        AIInsightCard(insight: aiInsight, recommendations: insight.aiRecommendations ?? [])
                    }

                    ActivitySummaryCard(insight: insight)
                } else {
                    EmptyInsightCard()
                }

                // Past weeks
                if !pastInsights.isEmpty {
                    PastWeeksSection(insights: pastInsights)
                }
            }
            .padding()
        }
        .navigationTitle("Weekly Insights")
        .task { await loadInsights() }
        .refreshable { await loadInsights() }
    }

    func loadInsights() async {
        isLoading = true
        defer { isLoading = false }

        currentInsight = try? await container.supabaseDataService.getCurrentWeekInsight()
        pastInsights = (try? await container.supabaseDataService.getInsightsHistory()) ?? []

        // Remove current week from history if present
        if let current = currentInsight {
            pastInsights.removeAll { $0.id == current.id }
        }
    }
}

// CurrentWeekCard.swift
struct CurrentWeekCard: View {
    let insight: WeeklyInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("This Week")
                    .font(.headline)
                Spacer()
                Text(insight.weekLabel)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let avg = insight.moodAvg {
                HStack(spacing: 20) {
                    VStack {
                        Text(String(format: "%.1f", avg))
                            .font(.system(size: 48, weight: .bold))
                        Text("avg mood")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let trend = insight.moodTrend {
                        VStack(alignment: .leading) {
                            Text(trend.emoji)
                                .font(.title)
                            Text(trend.message)
                                .font(.subheadline)
                                .foregroundColor(trend.color)
                        }
                    }
                }
            } else {
                Text("Not enough mood data yet")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

// MoodChartCard.swift
struct MoodChartCard: View {
    let insight: WeeklyInsight

    let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    let dayKeys = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mood by Day")
                .font(.headline)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(zip(days, dayKeys)), id: \.0) { day, key in
                    VStack {
                        if let moods = insight.moodByDay,
                           let value = moods[key] {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(moodColor(value))
                                .frame(width: 30, height: CGFloat(value) * 15)
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 30, height: 20)
                        }

                        Text(day)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }

    func moodColor(_ value: Double) -> Color {
        switch value {
        case 4...: return .green
        case 3..<4: return .blue
        case 2..<3: return .orange
        default: return .red
        }
    }
}

// PatternsCard.swift
struct PatternsCard: View {
    let patterns: [WeeklyInsight.Pattern]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Patterns Detected", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            ForEach(patterns, id: \.description) { pattern in
                HStack(alignment: .top) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                    Text(pattern.description)
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

// AIInsightCard.swift
struct AIInsightCard: View {
    let insight: String
    let recommendations: [WeeklyInsight.Recommendation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI Insight", systemImage: "sparkles")
                .font(.headline)

            Text(insight)
                .font(.body)

            if !recommendations.isEmpty {
                Divider()

                Text("Recommendations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(recommendations, id: \.title) { rec in
                    HStack(alignment: .top) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading) {
                            Text(rec.title)
                                .fontWeight(.medium)
                            Text(rec.reason)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(16)
    }
}

// ActivitySummaryCard.swift
struct ActivitySummaryCard: View {
    let insight: WeeklyInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity Summary")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatBox(icon: "checkmark.circle", label: "Quests", value: "\(insight.questCount)")
                StatBox(icon: "figure.mind.and.body", label: "Exercises", value: "\(insight.exerciseCount)")
                StatBox(icon: "face.smiling", label: "Moods", value: "\(insight.moodCount)")
                StatBox(icon: "clock", label: "Minutes", value: "\(insight.exerciseMinutes)")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

struct StatBox: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
```

### Backend Implementation

**Edge Function** (`supabase/functions/generate-weekly-insight/index.ts`):

```typescript
// Run every Sunday at 6 PM user local time
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import OpenAI from "https://esm.sh/openai@4";

serve(async () => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const aiClient = new OpenAI({ apiKey: Deno.env.get("XAI_API_KEY")! });

  // Get users who need insights generated
  const weekStart = getWeekStart();
  const weekEnd = getWeekEnd();

  const { data: users } = await supabase
    .from("profiles")
    .select("id, display_name, wellness_focus, timezone");

  for (const user of users || []) {
    try {
      await generateInsightForUser(
        supabase,
        aiClient,
        user,
        weekStart,
        weekEnd,
      );
    } catch (error) {
      console.error(`Failed to generate insight for ${user.id}:`, error);
    }
  }

  return new Response(JSON.stringify({ processed: users?.length || 0 }));
});

async function generateInsightForUser(
  supabase: SupabaseClient,
  aiClient: OpenAI,
  user: any,
  weekStart: Date,
  weekEnd: Date,
) {
  // Gather data
  const { data: moods } = await supabase
    .from("moods")
    .select("mood_score, created_at, local_date")
    .eq("user_id", user.id)
    .gte("created_at", weekStart.toISOString())
    .lte("created_at", weekEnd.toISOString());

  const { data: quests } = await supabase
    .from("quests")
    .select("status, completed_at")
    .eq("user_id", user.id)
    .gte("created_at", weekStart.toISOString())
    .eq("status", "completed");

  const { data: exercises } = await supabase
    .from("exercise_sessions")
    .select("exercise_id, duration_seconds, created_at")
    .eq("user_id", user.id)
    .gte("created_at", weekStart.toISOString());

  // Calculate metrics
  const moodScores = moods?.map((m) => m.mood_score) || [];
  const moodAvg = moodScores.length
    ? moodScores.reduce((a, b) => a + b, 0) / moodScores.length
    : null;
  const moodMin = moodScores.length ? Math.min(...moodScores) : null;
  const moodMax = moodScores.length ? Math.max(...moodScores) : null;

  // Calculate mood by day
  const moodByDay = calculateMoodByDay(moods || []);

  // Determine trend
  const trend = await calculateTrend(supabase, user.id, moodAvg);

  // Detect patterns
  const patterns = detectPatterns(moods || [], exercises || [], quests || []);

  // Generate AI insight
  const aiInsight = await generateAIInsight(aiClient, {
    userName: user.display_name,
    wellnessFocus: user.wellness_focus,
    moodAvg,
    moodTrend: trend,
    patterns,
    questCount: quests?.length || 0,
    exerciseCount: exercises?.length || 0,
  });

  // Save insight
  await supabase.from("weekly_insights").upsert({
    user_id: user.id,
    week_start: weekStart.toISOString().split("T")[0],
    week_end: weekEnd.toISOString().split("T")[0],
    mood_count: moods?.length || 0,
    mood_avg: moodAvg,
    mood_min: moodMin,
    mood_max: moodMax,
    mood_trend: trend,
    mood_by_day: moodByDay,
    quest_count: quests?.length || 0,
    exercise_count: exercises?.length || 0,
    exercise_minutes: Math.round(
      (exercises?.reduce((sum, e) => sum + (e.duration_seconds || 0), 0) || 0) /
        60,
    ),
    patterns_detected: patterns,
    ai_insight: aiInsight.insight,
    ai_recommendations: aiInsight.recommendations,
  });

  // Send notification
  await supabase.functions.invoke("send-notification", {
    body: {
      type: "weekly_summary",
      recipientId: user.id,
      data: {
        checkins: moods?.length || 0,
        quests: quests?.length || 0,
        moodMessage: getTrendMessage(trend),
      },
    },
  });
}

function detectPatterns(moods: any[], exercises: any[], quests: any[]) {
  const patterns = [];

  // Time-based patterns
  const dayMoods: Record<string, number[]> = {};
  for (const mood of moods) {
    const day = new Date(mood.created_at)
      .toLocaleDateString("en-US", { weekday: "short" })
      .toLowerCase();
    if (!dayMoods[day]) dayMoods[day] = [];
    dayMoods[day].push(mood.mood_score);
  }

  const dayAverages = Object.entries(dayMoods).map(([day, scores]) => ({
    day,
    avg: scores.reduce((a, b) => a + b, 0) / scores.length,
  }));

  const highest = dayAverages.sort((a, b) => b.avg - a.avg)[0];
  const lowest = dayAverages.sort((a, b) => a.avg - b.avg)[0];

  if (highest && lowest && highest.avg - lowest.avg > 1) {
    patterns.push({
      type: "time",
      description: `Your mood tends to be higher on ${highest.day}s and lower on ${lowest.day}s`,
      confidence: 0.7,
    });
  }

  // Activity correlation
  if (exercises.length >= 3 && moods.length >= 3) {
    patterns.push({
      type: "activity",
      description: "You logged more moods on days you exercised",
      confidence: 0.6,
    });
  }

  return patterns;
}

async function generateAIInsight(aiClient: OpenAI, data: any) {
  const prompt = `Generate a brief, encouraging weekly wellness insight for ${data.userName || "this user"}.

Data:
- Average mood: ${data.moodAvg?.toFixed(1) || "N/A"} out of 5
- Mood trend: ${data.moodTrend || "unknown"}
- Quests completed: ${data.questCount}
- Exercises completed: ${data.exerciseCount}
- Wellness focus: ${data.wellnessFocus || "general"}
- Patterns: ${JSON.stringify(data.patterns)}

Write:
1. A 2-3 sentence personalized observation about their week
2. One specific, actionable recommendation

Be warm, supportive, and specific. Avoid generic platitudes.

Return JSON: {"insight": "...", "recommendations": [{"title": "...", "reason": "..."}]}`;

  const response = await aiClient.chat.completions.create({
    model: "grok-3-mini-fast",
    messages: [{ role: "user", content: prompt }],
    max_tokens: 300,
    temperature: 0.7,
  });

  try {
    return JSON.parse(response.choices[0]?.message?.content || "{}");
  } catch {
    return {
      insight:
        "You're making progress on your wellness journey. Keep showing up for yourself!",
      recommendations: [],
    };
  }
}
```

---

## UI/UX

### Insights Screen

```
┌─────────────────────────────────────┐
│ < Home        Weekly Insights       │
├─────────────────────────────────────┤
│                                     │
│  THIS WEEK                          │
│  Jan 8 - Jan 14                     │
│  ┌─────────────────────────────────┐│
│  │                                 ││
│  │     3.8        📈               ││
│  │   avg mood   Improving!         ││
│  │                                 ││
│  └─────────────────────────────────┘│
│                                     │
│  MOOD BY DAY                        │
│  ┌─────────────────────────────────┐│
│  │  █  █     █  █  █              ││
│  │  █  █  █  █  █  █  █           ││
│  │  M  T  W  T  F  S  S           ││
│  └─────────────────────────────────┘│
│                                     │
│  💡 PATTERNS DETECTED               │
│  ┌─────────────────────────────────┐│
│  │ Your mood tends to be higher   ││
│  │ on weekends than weekdays.     ││
│  └─────────────────────────────────┘│
│                                     │
│  ✨ AI INSIGHT                      │
│  ┌─────────────────────────────────┐│
│  │ Great week! You completed 4    ││
│  │ quests and your mood improved  ││
│  │ from last week. The breathing  ││
│  │ exercises seem to be helping.  ││
│  │                                ││
│  │ → Try morning meditation       ││
│  │   Your mood peaks after calm   ││
│  │   activities                   ││
│  └─────────────────────────────────┘│
│                                     │
│  📊 ACTIVITY SUMMARY                │
│  ┌──────────┬──────────┐           │
│  │ ✓ 4      │ 🧘 6     │           │
│  │ Quests   │ Exercises│           │
│  ├──────────┼──────────┤           │
│  │ 😊 7     │ ⏱ 45    │           │
│  │ Moods    │ Minutes  │           │
│  └──────────┴──────────┘           │
│                                     │
└─────────────────────────────────────┘
```

---

## Verification

### Manual Testing

1. **Insight Generation:**
   - Log moods/quests/exercises for a week
   - Trigger insight generation (or wait for Sunday)
   - Verify all metrics calculated correctly
   - Verify AI insight is personalized

2. **Pattern Detection:**
   - Create intentional patterns (high mood on weekends)
   - Verify pattern is detected
   - Verify description is accurate

3. **UI Display:**
   - View insights screen
   - Verify all cards render correctly
   - Verify mood chart matches data
   - Verify recommendations are actionable

4. **History:**
   - Generate insights for multiple weeks
   - Verify history shows past insights
   - Verify can compare weeks

---

## Dependencies

- Mood tracking working
- Quest tracking working
- Exercise sessions tracking
- AI API (xAI) configured

---

## Risks & Mitigations

| Risk                              | Likelihood       | Impact | Mitigation                                  |
| --------------------------------- | ---------------- | ------ | ------------------------------------------- |
| Not enough data                   | High (new users) | Medium | Show "Log more to see insights"             |
| AI insights generic               | Medium           | High   | Require minimum data, use specific patterns |
| Pattern detection false positives | Medium           | Medium | Only show patterns with >0.6 confidence     |
| Users ignore insights             | Medium           | Medium | Sunday notification, home screen teaser     |

---

## Implementation Estimate

| Task                    | Effort       |
| ----------------------- | ------------ |
| Database migration      | 1 hour       |
| iOS Models              | 1 hour       |
| Service methods         | 2 hours      |
| Insights UI (all cards) | 6 hours      |
| Edge Function           | 5 hours      |
| Pattern detection       | 3 hours      |
| AI prompt engineering   | 2 hours      |
| Testing                 | 3 hours      |
| **Total**               | **23 hours** |
