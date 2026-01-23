# F020: Community Wisdom Engine

## Overview

### Summary

Anonymized, aggregated insights from community experiences that provide users with "you're not alone" data and crowd-sourced coping strategies without compromising individual privacy.

### Business Value

- Unique differentiator through community intelligence
- Increases perceived app value through collective wisdom
- Drives engagement through relatable content

### User Benefit

- Validation that others share similar experiences
- Access to strategies that worked for others
- Reduced isolation through anonymized connection

### Dependencies

- F004: Companion Memory Enhancement (for personalized insight delivery)
- F015: Life Transition Pathways (for transition-specific insights)

---

## Requirements

### Functional Requirements

| ID     | Requirement                                                        | Priority    |
| ------ | ------------------------------------------------------------------ | ----------- |
| FR-001 | Aggregate anonymized mood patterns for "you're not alone" insights | Must Have   |
| FR-002 | Collect and surface effective coping strategies from users         | Must Have   |
| FR-003 | Show "X% of users going through Y found Z helpful" statistics      | Must Have   |
| FR-004 | Opt-in contribution to wisdom pool                                 | Must Have   |
| FR-005 | Context-aware insight delivery (right insight, right time)         | Should Have |
| FR-006 | Upvote/downvote community strategies                               | Should Have |
| FR-007 | Category-based strategy browsing                                   | Should Have |
| FR-008 | Personal strategy contribution flow                                | Should Have |
| FR-009 | Regional/demographic filtering (optional)                          | Could Have  |
| FR-010 | Trend insights (e.g., "Mondays are hardest for many")              | Could Have  |

### Non-Functional Requirements

| ID      | Requirement                      | Target                      |
| ------- | -------------------------------- | --------------------------- |
| NFR-001 | Anonymization guarantee          | Zero PII exposure           |
| NFR-002 | Insight relevance                | >70% user rating as helpful |
| NFR-003 | Statistics accuracy              | Updated daily               |
| NFR-004 | Minimum sample size for insights | 100+ data points            |

### Acceptance Criteria

```gherkin
Feature: Community Wisdom Engine

Scenario: Receive "you're not alone" insight
  Given user just logged a low mood
  And 2000+ users have logged similar moods today
  When insight is displayed
  Then message should show "2000+ others are feeling this way today"
  And no identifying information should be included

Scenario: View coping strategies
  Given user is experiencing anxiety
  When user browses community strategies for anxiety
  Then strategies should show sorted by helpfulness
  And each should show "X% found this helpful"
  And strategies should be anonymized

Scenario: Contribute a strategy
  Given user successfully used a coping technique
  When user contributes their strategy
  Then strategy should be reviewed for content
  And added to community pool if appropriate
  And contributor should be anonymized

Scenario: Contextual insight delivery
  Given user is in week 2 of grief pathway
  When AI companion provides support
  Then companion can reference "many going through grief find..."
  And specific statistics should be available if helpful
```

---

## Technical Design

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    iOS Application                       │
├─────────────────────────────────────────────────────────┤
│  WisdomService                                          │
│  ├── Insight fetching and caching                       │
│  ├── Strategy browsing                                  │
│  ├── Contribution submission                            │
│  └── Voting                                             │
├─────────────────────────────────────────────────────────┤
│  WisdomViews                                            │
│  ├── InsightCardView                                    │
│  ├── StrategiesBrowserView                              │
│  ├── ContributeStrategyFlow                             │
│  └── TrendsView                                         │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│              Supabase Edge Functions                     │
├─────────────────────────────────────────────────────────┤
│  get-wisdom-insights                                    │
│  submit-strategy                                        │
│  vote-strategy                                          │
│  aggregate-daily-stats (cron)                           │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                  PostgreSQL Tables                       │
├─────────────────────────────────────────────────────────┤
│  community_strategies │ strategy_votes │ aggregate_stats│
└─────────────────────────────────────────────────────────┘
```

### Data Models

#### Database Schema

```sql
-- Community coping strategies
CREATE TABLE community_strategies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category TEXT NOT NULL CHECK (category IN (
        'anxiety', 'depression', 'stress', 'grief', 'anger',
        'loneliness', 'overwhelm', 'sleep', 'motivation', 'general'
    )),
    subcategory TEXT,
    strategy_text TEXT NOT NULL,
    context TEXT, -- "When feeling...", "During..."

    -- Anonymized metadata
    contributor_demographic TEXT, -- 'young_adult', 'adult', 'senior' (opt-in)
    transition_context TEXT, -- 'job_loss', 'grief', etc. if relevant

    -- Stats
    helpful_count INTEGER NOT NULL DEFAULT 0,
    not_helpful_count INTEGER NOT NULL DEFAULT 0,
    view_count INTEGER NOT NULL DEFAULT 0,

    -- Moderation
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
        'pending', 'approved', 'rejected', 'flagged'
    )),
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES auth.users(id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Strategy votes (anonymous)
CREATE TABLE strategy_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    strategy_id UUID NOT NULL REFERENCES community_strategies(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    vote_type TEXT NOT NULL CHECK (vote_type IN ('helpful', 'not_helpful')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(strategy_id, user_id)
);

-- Aggregated community stats (privacy-safe)
CREATE TABLE community_aggregate_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stat_date DATE NOT NULL,
    stat_type TEXT NOT NULL CHECK (stat_type IN (
        'daily_mood', 'mood_by_day_of_week', 'mood_by_time',
        'common_emotions', 'exercise_effectiveness', 'pathway_stats'
    )),
    category TEXT, -- Optional subcategory
    stat_data JSONB NOT NULL,
    sample_size INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(stat_date, stat_type, category)
);

-- User contribution preferences
CREATE TABLE wisdom_contribution_prefs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    contribute_mood_data BOOLEAN NOT NULL DEFAULT true,
    contribute_strategies BOOLEAN NOT NULL DEFAULT true,
    share_demographic BOOLEAN NOT NULL DEFAULT false,
    demographic_info JSONB, -- age_group, etc.
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Precomputed insights for quick delivery
CREATE TABLE wisdom_insights (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    insight_type TEXT NOT NULL CHECK (insight_type IN (
        'not_alone', 'trend', 'strategy_highlight', 'milestone'
    )),
    context_filter JSONB, -- {"mood_score": [1,2], "category": "anxiety"}
    insight_text TEXT NOT NULL,
    supporting_stat TEXT, -- "2,340 others today"
    priority INTEGER NOT NULL DEFAULT 0,
    valid_from TIMESTAMPTZ NOT NULL DEFAULT now(),
    valid_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_strategies_category ON community_strategies(category, status);
CREATE INDEX idx_strategies_approved ON community_strategies(status, helpful_count DESC)
    WHERE status = 'approved';
CREATE INDEX idx_strategy_votes_strategy ON strategy_votes(strategy_id);
CREATE INDEX idx_aggregate_stats_date ON community_aggregate_stats(stat_date DESC, stat_type);
CREATE INDEX idx_wisdom_insights_context ON wisdom_insights USING GIN (context_filter);

-- RLS Policies
ALTER TABLE community_strategies ENABLE ROW LEVEL SECURITY;
ALTER TABLE strategy_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_aggregate_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE wisdom_contribution_prefs ENABLE ROW LEVEL SECURITY;
ALTER TABLE wisdom_insights ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view approved strategies" ON community_strategies
    FOR SELECT USING (status = 'approved');

CREATE POLICY "Users can manage own votes" ON strategy_votes
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Anyone can view aggregate stats" ON community_aggregate_stats
    FOR SELECT USING (true);

CREATE POLICY "Users can manage own prefs" ON wisdom_contribution_prefs
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Anyone can view insights" ON wisdom_insights
    FOR SELECT USING (valid_until IS NULL OR valid_until > now());
```

#### Swift Models

```swift
// MARK: - Wisdom Models

struct CommunityStrategy: Codable, Identifiable {
    let id: UUID
    let category: WisdomCategory
    let subcategory: String?
    let strategyText: String
    let context: String?
    let contributorDemographic: String?
    let transitionContext: String?
    var helpfulCount: Int
    var notHelpfulCount: Int
    let viewCount: Int
    let createdAt: Date

    var helpfulPercentage: Int {
        let total = helpfulCount + notHelpfulCount
        guard total > 0 else { return 0 }
        return Int((Double(helpfulCount) / Double(total)) * 100)
    }

    var myVote: VoteType?
}

enum WisdomCategory: String, Codable, CaseIterable {
    case anxiety
    case depression
    case stress
    case grief
    case anger
    case loneliness
    case overwhelm
    case sleep
    case motivation
    case general

    var displayName: String {
        rawValue.capitalized
    }

    var iconName: String {
        switch self {
        case .anxiety: return "waveform.path.ecg"
        case .depression: return "cloud.rain"
        case .stress: return "bolt.fill"
        case .grief: return "heart.slash"
        case .anger: return "flame"
        case .loneliness: return "person.crop.circle.badge.minus"
        case .overwhelm: return "tornado"
        case .sleep: return "moon.zzz"
        case .motivation: return "battery.25"
        case .general: return "sparkles"
        }
    }
}

enum VoteType: String, Codable {
    case helpful
    case notHelpful = "not_helpful"
}

struct CommunityAggregateStat: Codable {
    let id: UUID
    let statDate: Date
    let statType: StatType
    let category: String?
    let statData: StatData
    let sampleSize: Int

    enum StatType: String, Codable {
        case dailyMood = "daily_mood"
        case moodByDayOfWeek = "mood_by_day_of_week"
        case moodByTime = "mood_by_time"
        case commonEmotions = "common_emotions"
        case exerciseEffectiveness = "exercise_effectiveness"
        case pathwayStats = "pathway_stats"
    }
}

struct StatData: Codable {
    let averageMood: Double?
    let distribution: [String: Int]?
    let trend: String?
    let percentage: Double?
    let count: Int?
}

struct WisdomInsight: Codable, Identifiable {
    let id: UUID
    let insightType: InsightType
    let contextFilter: ContextFilter?
    let insightText: String
    let supportingStat: String?
    let priority: Int

    enum InsightType: String, Codable {
        case notAlone = "not_alone"
        case trend
        case strategyHighlight = "strategy_highlight"
        case milestone
    }
}

struct ContextFilter: Codable {
    let moodScore: [Int]?
    let category: String?
    let emotion: String?
    let timeOfDay: String?
    let dayOfWeek: Int?
}

struct WisdomContributionPrefs: Codable {
    let id: UUID
    let userId: UUID
    var contributeMoodData: Bool
    var contributeStrategies: Bool
    var shareDemographic: Bool
    var demographicInfo: DemographicInfo?
}

struct DemographicInfo: Codable {
    var ageGroup: String?
    var region: String?
}

// Display models
struct NotAloneInsight {
    let count: Int
    let timeframe: String // "today", "this week"
    let context: String // "feeling anxious", "having a tough Monday"
    let message: String

    var formattedCount: String {
        if count >= 1000 {
            return "\(count / 1000)k+"
        }
        return "\(count)+"
    }
}
```

### API Contracts

#### Get Insights

```
GET /functions/v1/get-wisdom-insights

Query:
{
  "moodScore": 2,
  "emotion": "anxious",
  "context": "morning"
}

Response 200:
{
  "notAloneInsight": {
    "count": 2340,
    "message": "2,340+ others are feeling anxious this morning too"
  },
  "topStrategies": [
    {
      "id": "uuid",
      "strategyText": "When anxiety hits, I do 4-7-8 breathing...",
      "helpfulPercentage": 87,
      "category": "anxiety"
    }
  ],
  "trendInsight": {
    "message": "Many find mornings hardest. It often eases after noon."
  }
}
```

#### Submit Strategy

```
POST /functions/v1/submit-strategy

Request:
{
  "category": "anxiety",
  "strategyText": "I find that going for a short walk and naming 5 things I see helps ground me.",
  "context": "When feeling overwhelmed at work"
}

Response 201:
{
  "id": "uuid",
  "status": "pending",
  "message": "Thanks for sharing! Your strategy will be reviewed."
}
```

#### Vote on Strategy

```
POST /rest/v1/strategy_votes

Request:
{
  "strategy_id": "uuid",
  "vote_type": "helpful"
}

Response 201:
{
  "id": "uuid",
  "strategy": {
    "helpfulCount": 124,
    "notHelpfulCount": 12
  }
}
```

---

## Implementation Details

### Step-by-Step Approach

1. **Data Aggregation Pipeline**
   - Nightly cron job aggregates mood data
   - Calculate "not alone" counts
   - Identify trends
   - Update insights cache

2. **Strategy Collection**
   - Prompt after positive experiences
   - Structured submission form
   - Content moderation queue
   - Approval workflow

3. **Insight Delivery**
   - Context-aware matching
   - Real-time "not alone" data
   - AI companion integration
   - Inline UI components

4. **Strategy Browsing**
   - Category filtering
   - Sort by helpfulness
   - Voting interface
   - Personal history

### File Structure

```
apps/ios/MindFriendApp/
├── Features/
│   └── Wisdom/
│       ├── WisdomService.swift
│       ├── Views/
│       │   ├── NotAloneInsightView.swift
│       │   ├── StrategiesBrowserView.swift
│       │   ├── StrategyCardView.swift
│       │   ├── ContributeStrategySheet.swift
│       │   └── TrendsView.swift
│       └── Components/
│           ├── InsightBanner.swift
│           ├── VoteButtons.swift
│           └── CategoryPicker.swift
│
supabase/
├── functions/
│   ├── get-wisdom-insights/
│   ├── submit-strategy/
│   ├── aggregate-daily-stats/  # Cron
│   └── moderate-strategy/
├── migrations/
│   └── YYYYMMDD_wisdom_engine.sql
```

### Key Algorithms

#### Daily Aggregation (TypeScript)

```typescript
// Runs nightly via cron
async function aggregateDailyStats(supabase: SupabaseClient): Promise<void> {
  const today = new Date().toISOString().split("T")[0];

  // 1. Aggregate daily mood distribution
  const { data: moodData } = await supabase
    .from("moods")
    .select("score, created_at")
    .gte("created_at", `${today}T00:00:00Z`)
    .lt("created_at", `${today}T23:59:59Z`);

  if (moodData && moodData.length >= 100) {
    // Minimum sample size
    const distribution: Record<string, number> = {};
    let total = 0;

    for (const mood of moodData) {
      const bucket =
        mood.score <= 2 ? "low" : mood.score <= 3 ? "medium" : "high";
      distribution[bucket] = (distribution[bucket] || 0) + 1;
      total += mood.score;
    }

    await supabase.from("community_aggregate_stats").upsert({
      stat_date: today,
      stat_type: "daily_mood",
      stat_data: {
        distribution,
        averageMood: total / moodData.length,
        count: moodData.length,
      },
      sample_size: moodData.length,
    });

    // Update "not alone" insight
    const lowMoodCount = distribution["low"] || 0;
    if (lowMoodCount >= 100) {
      await supabase.from("wisdom_insights").upsert({
        insight_type: "not_alone",
        context_filter: { moodScore: [1, 2] },
        insight_text: `${lowMoodCount.toLocaleString()}+ others are having a tough day too`,
        supporting_stat: `${lowMoodCount.toLocaleString()} today`,
        priority: 10,
        valid_from: `${today}T00:00:00Z`,
        valid_until: `${today}T23:59:59Z`,
      });
    }
  }

  // 2. Aggregate mood by time of day
  const timeDistribution = await aggregateMoodByTime(supabase, today);

  // 3. Aggregate common emotions
  await aggregateEmotions(supabase, today);

  // 4. Calculate exercise effectiveness
  await aggregateExerciseEffectiveness(supabase, today);
}

async function aggregateMoodByTime(
  supabase: SupabaseClient,
  date: string,
): Promise<void> {
  const { data: moods } = await supabase
    .from("moods")
    .select("score, created_at")
    .gte("created_at", `${date}T00:00:00Z`)
    .lt("created_at", `${date}T23:59:59Z`);

  const timeBlocks: Record<string, { total: number; count: number }> = {
    morning: { total: 0, count: 0 }, // 6-12
    afternoon: { total: 0, count: 0 }, // 12-17
    evening: { total: 0, count: 0 }, // 17-21
    night: { total: 0, count: 0 }, // 21-6
  };

  for (const mood of moods || []) {
    const hour = new Date(mood.created_at).getHours();
    let block: string;

    if (hour >= 6 && hour < 12) block = "morning";
    else if (hour >= 12 && hour < 17) block = "afternoon";
    else if (hour >= 17 && hour < 21) block = "evening";
    else block = "night";

    timeBlocks[block].total += mood.score;
    timeBlocks[block].count++;
  }

  const averages: Record<string, number> = {};
  for (const [block, data] of Object.entries(timeBlocks)) {
    if (data.count > 0) {
      averages[block] = data.total / data.count;
    }
  }

  await supabase.from("community_aggregate_stats").upsert({
    stat_date: date,
    stat_type: "mood_by_time",
    stat_data: { averages, distribution: timeBlocks },
    sample_size: moods?.length || 0,
  });
}

async function getContextualInsights(
  supabase: SupabaseClient,
  userId: string,
  context: InsightContext,
): Promise<WisdomInsights> {
  // Get matching "not alone" insight
  const { data: notAloneInsight } = await supabase
    .from("wisdom_insights")
    .select("*")
    .eq("insight_type", "not_alone")
    .containedBy("context_filter", {
      moodScore: [context.moodScore],
    })
    .gt("valid_until", new Date().toISOString())
    .order("priority", { ascending: false })
    .limit(1)
    .single();

  // Get top strategies for context
  const { data: strategies } = await supabase
    .from("community_strategies")
    .select("*")
    .eq("status", "approved")
    .eq("category", mapMoodToCategory(context))
    .order("helpful_count", { ascending: false })
    .limit(3);

  // Get trend insight
  const trend = await getTrendInsight(supabase, context);

  return {
    notAloneInsight,
    topStrategies: strategies,
    trendInsight: trend,
  };
}

function mapMoodToCategory(context: InsightContext): string {
  // Map emotion/mood to wisdom category
  if (context.emotion?.includes("anxious")) return "anxiety";
  if (context.emotion?.includes("sad")) return "depression";
  if (context.emotion?.includes("stressed")) return "stress";
  if (context.moodScore <= 2) return "general";
  return "motivation";
}
```

---

## Dependencies

### Internal Dependencies

- **F004 Companion Memory**: For AI companion insight integration
- **F015 Life Transition Pathways**: For transition-specific insights
- **Mood logging**: For aggregation source data

### External Dependencies

- Content moderation (manual or API)

### Infrastructure Requirements

- Nightly cron job for aggregation
- Sufficient data before enabling (cold start)

---

## Edge Cases & Error Handling

| Scenario                      | Handling                                                |
| ----------------------------- | ------------------------------------------------------- |
| Not enough data for insight   | Don't show insight; wait for sample size                |
| Strategy contains PII         | Moderation catches; reject with explanation             |
| Same strategy submitted twice | Fuzzy match detection; merge or reject                  |
| User withdraws data consent   | Remove from future aggregation; don't delete historical |
| Negative/harmful strategy     | Moderation rejects; flag pattern                        |
| Regional data too sparse      | Fall back to global stats                               |
| Vote manipulation             | Rate limiting; pattern detection                        |
| Outdated insight displayed    | TTL on insights; auto-expire                            |

---

## Testing Requirements

### Unit Tests

```swift
// WisdomServiceTests.swift

func testHelpfulPercentageCalculation() {
    let strategy = CommunityStrategy(
        helpfulCount: 80,
        notHelpfulCount: 20
    )

    XCTAssertEqual(strategy.helpfulPercentage, 80)
}

func testZeroVotesPercentage() {
    let strategy = CommunityStrategy(
        helpfulCount: 0,
        notHelpfulCount: 0
    )

    XCTAssertEqual(strategy.helpfulPercentage, 0)
}

func testMoodCategoryMapping() {
    XCTAssertEqual(WisdomService.mapMoodToCategory(emotion: "anxious"), .anxiety)
    XCTAssertEqual(WisdomService.mapMoodToCategory(emotion: "sad"), .depression)
    XCTAssertEqual(WisdomService.mapMoodToCategory(moodScore: 1), .general)
}

func testContextMatchingFilter() {
    let insight = WisdomInsight(
        contextFilter: ContextFilter(moodScore: [1, 2], category: nil)
    )

    XCTAssertTrue(WisdomService.matches(insight, moodScore: 2))
    XCTAssertFalse(WisdomService.matches(insight, moodScore: 4))
}
```

### Integration Tests

```typescript
// supabase/functions/aggregate-daily-stats/test.ts

Deno.test("aggregation respects minimum sample size", async () => {
  // Create only 50 moods (below 100 threshold)
  await createMoods(50);

  await invokeFunction("aggregate-daily-stats");

  const { data } = await supabase
    .from("community_aggregate_stats")
    .select("*")
    .eq("stat_date", today);

  // Should not create stats with insufficient data
  assertEquals(data.length, 0);
});

Deno.test("strategies require moderation", async () => {
  const userId = await createTestUser();

  const result = await invokeFunction(
    "submit-strategy",
    {
      category: "anxiety",
      strategyText: "Deep breathing helps me",
    },
    userId,
  );

  assertEquals(result.status, "pending");

  // Should not be visible yet
  const { data: visible } = await supabase
    .from("community_strategies")
    .select("*")
    .eq("id", result.id)
    .eq("status", "approved");

  assertEquals(visible.length, 0);
});

Deno.test("votes update counts correctly", async () => {
  const strategy = await createApprovedStrategy();
  const voter1 = await createTestUser();
  const voter2 = await createTestUser();

  await vote(voter1, strategy.id, "helpful");
  await vote(voter2, strategy.id, "helpful");

  const { data } = await supabase
    .from("community_strategies")
    .select("helpful_count")
    .eq("id", strategy.id)
    .single();

  assertEquals(data.helpful_count, 2);
});
```
