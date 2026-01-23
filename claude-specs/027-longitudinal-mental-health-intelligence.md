# F027: Longitudinal Mental Health Intelligence

## Overview

### Summary

Long-term mental health tracking and analysis system that aggregates years of user data to identify patterns, track progress, predict seasonal variations, and provide meaningful insights about the user's mental health journey over time—transforming the app from a daily tool into a lifelong mental wellness companion.

### Business Value

- Creates irreplaceable user data that drives extreme retention
- Premium differentiator for long-term subscribers
- Positions MindFriend as serious mental health platform
- Enables research partnerships and population insights
- Justifies higher premium pricing for historical insights

### User Benefit

- Understand their mental health patterns across years
- See concrete evidence of growth and progress
- Anticipate and prepare for seasonal challenges
- Have a complete mental wellness history for healthcare
- Gain deep self-knowledge impossible without longitudinal data

### Dependencies

- F001 (Biometric Correlation Engine) - Biometric data integration
- F002 (Daily Wellness Score) - Consistent scoring metrics
- F003 (Predictive Mood Intelligence) - Prediction infrastructure
- Core Data System - Historical data storage

---

## Requirements

### Functional Requirements

| ID        | Requirement                                     | Priority |
| --------- | ----------------------------------------------- | -------- |
| FR-027-01 | Store and analyze years of mental health data   | P0       |
| FR-027-02 | Generate annual mental health reports           | P0       |
| FR-027-03 | Identify seasonal and cyclical patterns         | P0       |
| FR-027-04 | Track long-term improvement metrics             | P0       |
| FR-027-05 | Detect significant life events and their impact | P1       |
| FR-027-06 | Compare current state to historical baselines   | P1       |
| FR-027-07 | Generate milestone celebrations for progress    | P1       |
| FR-027-08 | Provide exportable mental health timeline       | P2       |
| FR-027-09 | Enable sharing with healthcare providers        | P2       |
| FR-027-10 | Support data portability and user ownership     | P2       |

### Non-Functional Requirements

| ID         | Requirement                               | Target                   |
| ---------- | ----------------------------------------- | ------------------------ |
| NFR-027-01 | Historical data retention                 | 10+ years                |
| NFR-027-02 | Query performance for yearly aggregations | < 3 seconds              |
| NFR-027-03 | Storage efficiency                        | < 5 MB per user per year |
| NFR-027-04 | Data privacy compliance                   | HIPAA-aligned            |
| NFR-027-05 | Export format compatibility               | PDF, JSON, FHIR          |
| NFR-027-06 | Pattern detection accuracy                | > 85%                    |

### Acceptance Criteria (Gherkin)

```gherkin
Feature: Longitudinal Mental Health Intelligence

  Scenario: User views their annual mental health report
    Given the user has been using the app for 12+ months
    When they access their annual report
    Then they see year-over-year mood trends
    And seasonal pattern analysis
    And key life events mapped to mood changes
    And overall progress assessment
    And personalized insights for the coming year

  Scenario: Seasonal pattern detection
    Given the user has 2+ years of data
    When the system analyzes seasonal patterns
    Then it identifies their most challenging seasons
    And correlates with external factors (weather, holidays)
    And provides proactive preparation suggestions
    And compares to previous year's patterns

  Scenario: Long-term progress celebration
    Given the user's average mood this year is higher than last year
    When the milestone is detected
    Then they receive a celebratory notification
    And see visualized before/after comparison
    And can share their progress privately

  Scenario: Healthcare provider export
    Given the user wants to share data with their therapist
    When they generate a clinical export
    Then the report includes standardized metrics
    And timeline of mood, sleep, and activity
    And notes of significant events
    And is formatted for clinical use
```

---

## Technical Design

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│              Longitudinal Mental Health Intelligence             │
├─────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Insights Generator                       │ │
│  │  • Pattern Detector  • Report Builder  • Export Engine     │ │
│  └───────────────────────────┬────────────────────────────────┘ │
├──────────────────────────────┼──────────────────────────────────┤
│                              │                                  │
│  ┌───────────────────────────▼───────────────────────────────┐  │
│  │                   Analysis Engines                         │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌────────────────────┐ │  │
│  │  │ Seasonal     │ │ Life Event   │ │ Progress           │ │  │
│  │  │ Analyzer     │ │ Detector     │ │ Tracker            │ │  │
│  │  └──────────────┘ └──────────────┘ └────────────────────┘ │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌────────────────────┐ │  │
│  │  │ Trend        │ │ Correlation  │ │ Milestone          │ │  │
│  │  │ Calculator   │ │ Finder       │ │ Generator          │ │  │
│  │  └──────────────┘ └──────────────┘ └────────────────────┘ │  │
│  └───────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   Data Aggregation Layer                   │  │
│  │  • Daily → Weekly → Monthly → Yearly rollups              │  │
│  │  • Compressed historical storage                          │  │
│  │  • Efficient time-series queries                          │  │
│  └───────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   Source Data Layer                        │  │
│  │  • Moods  • Sleep  • Activity  • Journal  • Events        │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Database Schema

```sql
-- Weekly aggregated data (compressed from daily)
CREATE TABLE longitudinal_weekly_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    week_start DATE NOT NULL,
    year INTEGER NOT NULL,
    week_number INTEGER NOT NULL,
    avg_mood DECIMAL(4,2),
    min_mood DECIMAL(4,2),
    max_mood DECIMAL(4,2),
    mood_variance DECIMAL(4,2),
    mood_entry_count INTEGER DEFAULT 0,
    avg_wellness_score DECIMAL(4,2),
    total_exercise_minutes INTEGER DEFAULT 0,
    exercise_session_count INTEGER DEFAULT 0,
    avg_sleep_hours DECIMAL(4,2),
    avg_sleep_quality DECIMAL(4,2),
    quest_completion_rate DECIMAL(4,2),
    streak_maintained BOOLEAN,
    journal_entry_count INTEGER DEFAULT 0,
    dominant_emotions TEXT[] DEFAULT '{}',
    notable_events JSONB DEFAULT '[]',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, week_start)
);

-- Monthly aggregated data
CREATE TABLE longitudinal_monthly_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    month_start DATE NOT NULL,
    year INTEGER NOT NULL,
    month INTEGER NOT NULL,
    avg_mood DECIMAL(4,2),
    mood_trend TEXT CHECK (mood_trend IN ('improving', 'stable', 'declining')),
    mood_volatility DECIMAL(4,2),
    avg_wellness_score DECIMAL(4,2),
    wellness_trend TEXT,
    total_exercise_minutes INTEGER DEFAULT 0,
    avg_daily_exercise_minutes DECIMAL(5,2),
    avg_sleep_hours DECIMAL(4,2),
    sleep_consistency_score DECIMAL(4,2),
    quest_completion_rate DECIMAL(4,2),
    longest_streak INTEGER DEFAULT 0,
    total_journal_entries INTEGER DEFAULT 0,
    key_themes TEXT[] DEFAULT '{}',
    significant_events JSONB DEFAULT '[]',
    month_over_month_change JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, month_start)
);

-- Yearly summary data
CREATE TABLE longitudinal_yearly_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    year INTEGER NOT NULL,
    avg_mood DECIMAL(4,2),
    mood_high_month INTEGER,
    mood_low_month INTEGER,
    mood_range DECIMAL(4,2),
    overall_trend TEXT,
    avg_wellness_score DECIMAL(4,2),
    wellness_improvement_percent DECIMAL(5,2),
    total_exercise_hours DECIMAL(7,2),
    total_meditation_hours DECIMAL(7,2),
    avg_sleep_hours DECIMAL(4,2),
    total_quests_completed INTEGER DEFAULT 0,
    longest_streak_achieved INTEGER DEFAULT 0,
    total_journal_entries INTEGER DEFAULT 0,
    most_common_emotions TEXT[] DEFAULT '{}',
    seasonal_patterns JSONB DEFAULT '{}',
    life_events JSONB DEFAULT '[]',
    year_over_year_comparison JSONB DEFAULT '{}',
    insights JSONB DEFAULT '[]',
    report_generated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, year)
);

-- Detected patterns and insights
CREATE TABLE longitudinal_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    pattern_type TEXT NOT NULL CHECK (pattern_type IN (
        'seasonal', 'weekly_cycle', 'monthly_cycle',
        'trigger', 'correlation', 'improvement', 'regression'
    )),
    pattern_description TEXT NOT NULL,
    confidence DECIMAL(3,2) NOT NULL,
    evidence JSONB NOT NULL DEFAULT '{}',
    first_detected_at TIMESTAMPTZ DEFAULT NOW(),
    last_confirmed_at TIMESTAMPTZ DEFAULT NOW(),
    occurrences INTEGER DEFAULT 1,
    is_active BOOLEAN DEFAULT TRUE,
    user_acknowledged BOOLEAN DEFAULT FALSE,
    user_feedback TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Life events with mental health impact
CREATE TABLE longitudinal_life_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    event_date DATE NOT NULL,
    event_type TEXT NOT NULL CHECK (event_type IN (
        'positive', 'negative', 'neutral', 'milestone', 'transition'
    )),
    event_category TEXT NOT NULL CHECK (event_category IN (
        'work', 'relationship', 'health', 'family', 'personal',
        'financial', 'social', 'achievement', 'loss', 'other'
    )),
    title TEXT NOT NULL,
    description TEXT,
    impact_duration_days INTEGER,
    mood_before DECIMAL(4,2),
    mood_during DECIMAL(4,2),
    mood_after DECIMAL(4,2),
    recovery_days INTEGER,
    is_user_logged BOOLEAN DEFAULT FALSE,
    is_system_detected BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Generated reports
CREATE TABLE longitudinal_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    report_type TEXT NOT NULL CHECK (report_type IN (
        'annual', 'quarterly', 'monthly_summary', 'clinical_export', 'custom'
    )),
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    report_data JSONB NOT NULL,
    pdf_url TEXT,
    json_export_url TEXT,
    fhir_export_url TEXT,
    shared_with JSONB DEFAULT '[]',
    generated_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ
);

-- Milestones and achievements
CREATE TABLE longitudinal_milestones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    milestone_type TEXT NOT NULL CHECK (milestone_type IN (
        'mood_improvement', 'consistency', 'streak_record',
        'exercise_goal', 'sleep_improvement', 'journey_anniversary',
        'pattern_broken', 'recovery', 'personal_best'
    )),
    title TEXT NOT NULL,
    description TEXT,
    achieved_date DATE NOT NULL,
    metric_name TEXT,
    previous_value DECIMAL(10,2),
    new_value DECIMAL(10,2),
    improvement_percent DECIMAL(5,2),
    is_celebrated BOOLEAN DEFAULT FALSE,
    celebrated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE longitudinal_weekly_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE longitudinal_monthly_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE longitudinal_yearly_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE longitudinal_patterns ENABLE ROW LEVEL SECURITY;
ALTER TABLE longitudinal_life_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE longitudinal_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE longitudinal_milestones ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users access own weekly stats"
    ON longitudinal_weekly_stats FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users access own monthly stats"
    ON longitudinal_monthly_stats FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users access own yearly stats"
    ON longitudinal_yearly_stats FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users access own patterns"
    ON longitudinal_patterns FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users manage own life events"
    ON longitudinal_life_events FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users access own reports"
    ON longitudinal_reports FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users access own milestones"
    ON longitudinal_milestones FOR ALL
    USING (auth.uid() = user_id);

-- Indexes for time-based queries
CREATE INDEX idx_weekly_stats_user_date ON longitudinal_weekly_stats(user_id, week_start);
CREATE INDEX idx_monthly_stats_user_date ON longitudinal_monthly_stats(user_id, month_start);
CREATE INDEX idx_yearly_stats_user ON longitudinal_yearly_stats(user_id, year);
CREATE INDEX idx_patterns_user_active ON longitudinal_patterns(user_id) WHERE is_active = TRUE;
CREATE INDEX idx_life_events_user_date ON longitudinal_life_events(user_id, event_date);
CREATE INDEX idx_milestones_user_date ON longitudinal_milestones(user_id, achieved_date);
```

### Swift Models

```swift
import Foundation

// MARK: - Aggregated Stats

struct WeeklyStats: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let weekStart: Date
    let year: Int
    let weekNumber: Int
    let avgMood: Double?
    let minMood: Double?
    let maxMood: Double?
    let moodVariance: Double?
    let moodEntryCount: Int
    let avgWellnessScore: Double?
    let totalExerciseMinutes: Int
    let exerciseSessionCount: Int
    let avgSleepHours: Double?
    let avgSleepQuality: Double?
    let questCompletionRate: Double?
    let streakMaintained: Bool
    let journalEntryCount: Int
    let dominantEmotions: [String]
    let notableEvents: [NotableEvent]
    let createdAt: Date
}

struct MonthlyStats: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let monthStart: Date
    let year: Int
    let month: Int
    let avgMood: Double?
    let moodTrend: Trend?
    let moodVolatility: Double?
    let avgWellnessScore: Double?
    let wellnessTrend: Trend?
    let totalExerciseMinutes: Int
    let avgDailyExerciseMinutes: Double?
    let avgSleepHours: Double?
    let sleepConsistencyScore: Double?
    let questCompletionRate: Double?
    let longestStreak: Int
    let totalJournalEntries: Int
    let keyThemes: [String]
    let significantEvents: [LifeEventSummary]
    let monthOverMonthChange: ChangeMetrics
    let createdAt: Date

    enum Trend: String, Codable {
        case improving, stable, declining
    }
}

struct YearlyStats: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let year: Int
    let avgMood: Double?
    let moodHighMonth: Int?
    let moodLowMonth: Int?
    let moodRange: Double?
    let overallTrend: String?
    let avgWellnessScore: Double?
    let wellnessImprovementPercent: Double?
    let totalExerciseHours: Double
    let totalMeditationHours: Double
    let avgSleepHours: Double?
    let totalQuestsCompleted: Int
    let longestStreakAchieved: Int
    let totalJournalEntries: Int
    let mostCommonEmotions: [String]
    let seasonalPatterns: SeasonalPatterns
    let lifeEvents: [LifeEventSummary]
    let yearOverYearComparison: YearComparison?
    let insights: [YearlyInsight]
    let reportGeneratedAt: Date?
    let createdAt: Date
}

struct ChangeMetrics: Codable {
    let moodChange: Double?
    let wellnessChange: Double?
    let exerciseChange: Double?
    let sleepChange: Double?
}

struct SeasonalPatterns: Codable {
    let spring: SeasonMetrics
    let summer: SeasonMetrics
    let fall: SeasonMetrics
    let winter: SeasonMetrics
    let bestSeason: String?
    let challengingSeason: String?
}

struct SeasonMetrics: Codable {
    let avgMood: Double?
    let avgWellness: Double?
    let typicalChallenges: [String]
    let successStrategies: [String]
}

struct YearComparison: Codable {
    let previousYear: Int
    let moodImprovement: Double?
    let wellnessImprovement: Double?
    let exerciseChange: Double?
    let sleepImprovement: Double?
    let streakImprovement: Int?
}

struct YearlyInsight: Codable {
    let category: String
    let title: String
    let description: String
    let dataSupport: String
    let recommendation: String?
}

// MARK: - Patterns

struct LongitudinalPattern: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let patternType: PatternType
    let patternDescription: String
    let confidence: Double
    let evidence: PatternEvidence
    let firstDetectedAt: Date
    let lastConfirmedAt: Date
    let occurrences: Int
    let isActive: Bool
    var userAcknowledged: Bool
    var userFeedback: String?
    let createdAt: Date

    enum PatternType: String, Codable {
        case seasonal
        case weeklyCycle = "weekly_cycle"
        case monthlyCycle = "monthly_cycle"
        case trigger
        case correlation
        case improvement
        case regression
    }
}

struct PatternEvidence: Codable {
    let dataPoints: [PatternDataPoint]
    let statisticalSignificance: Double
    let affectedMetrics: [String]
    let timeframeDescription: String
}

struct PatternDataPoint: Codable {
    let period: String
    let value: Double
    let comparison: Double?
}

// MARK: - Life Events

struct LifeEvent: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let eventDate: Date
    let eventType: EventType
    let eventCategory: EventCategory
    let title: String
    let description: String?
    let impactDurationDays: Int?
    let moodBefore: Double?
    let moodDuring: Double?
    let moodAfter: Double?
    let recoveryDays: Int?
    let isUserLogged: Bool
    let isSystemDetected: Bool
    let createdAt: Date

    enum EventType: String, Codable {
        case positive, negative, neutral, milestone, transition
    }

    enum EventCategory: String, Codable {
        case work, relationship, health, family, personal
        case financial, social, achievement, loss, other
    }
}

struct LifeEventSummary: Codable {
    let date: Date
    let title: String
    let type: LifeEvent.EventType
    let category: LifeEvent.EventCategory
    let impactLevel: String  // "significant", "moderate", "minor"
}

struct NotableEvent: Codable {
    let date: Date
    let description: String
    let moodImpact: Double?
}

// MARK: - Reports

struct LongitudinalReport: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let reportType: ReportType
    let periodStart: Date
    let periodEnd: Date
    let reportData: ReportContent
    let pdfUrl: String?
    let jsonExportUrl: String?
    let fhirExportUrl: String?
    let sharedWith: [ShareRecipient]
    let generatedAt: Date
    let expiresAt: Date?

    enum ReportType: String, Codable {
        case annual
        case quarterly
        case monthlySummary = "monthly_summary"
        case clinicalExport = "clinical_export"
        case custom
    }
}

struct ReportContent: Codable {
    let summary: ReportSummary
    let charts: [ChartData]
    let patterns: [PatternSummary]
    let milestones: [MilestoneSummary]
    let recommendations: [String]
}

struct ReportSummary: Codable {
    let periodDescription: String
    let overallAssessment: String
    let keyHighlights: [String]
    let areasOfProgress: [String]
    let areasForFocus: [String]
}

struct ChartData: Codable {
    let chartType: String
    let title: String
    let dataPoints: [[String: Double]]
}

struct PatternSummary: Codable {
    let type: String
    let description: String
    let impact: String
}

struct MilestoneSummary: Codable {
    let title: String
    let date: Date
    let significance: String
}

struct ShareRecipient: Codable {
    let email: String?
    let sharedAt: Date
    let accessType: String
    let expiresAt: Date?
}

// MARK: - Milestones

struct LongitudinalMilestone: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let milestoneType: MilestoneType
    let title: String
    let description: String?
    let achievedDate: Date
    let metricName: String?
    let previousValue: Double?
    let newValue: Double?
    let improvementPercent: Double?
    var isCelebrated: Bool
    var celebratedAt: Date?
    let createdAt: Date

    enum MilestoneType: String, Codable {
        case moodImprovement = "mood_improvement"
        case consistency
        case streakRecord = "streak_record"
        case exerciseGoal = "exercise_goal"
        case sleepImprovement = "sleep_improvement"
        case journeyAnniversary = "journey_anniversary"
        case patternBroken = "pattern_broken"
        case recovery
        case personalBest = "personal_best"
    }
}
```

### API Contracts

```typescript
// Edge Function: aggregate-stats
// POST /functions/v1/aggregate-stats (Cron - daily)

interface AggregateStatsRequest {
  user_ids?: string[]; // Optional, process all if empty
  force_recalculate?: boolean;
}

interface AggregateStatsResponse {
  weekly_updated: number;
  monthly_updated: number;
  yearly_updated: number;
  patterns_detected: number;
  milestones_created: number;
}

// Edge Function: generate-annual-report
// POST /functions/v1/generate-annual-report

interface GenerateReportRequest {
  year: number;
  include_pdf: boolean;
  include_fhir: boolean;
}

interface GenerateReportResponse {
  report_id: string;
  pdf_url?: string;
  json_url?: string;
  fhir_url?: string;
}

// Edge Function: detect-patterns
// POST /functions/v1/detect-patterns

interface DetectPatternsRequest {
  lookback_months?: number; // Default 24
}

interface DetectPatternsResponse {
  patterns: LongitudinalPattern[];
  new_patterns: number;
  updated_patterns: number;
}

// Edge Function: export-clinical
// POST /functions/v1/export-clinical

interface ClinicalExportRequest {
  start_date: string;
  end_date: string;
  format: "pdf" | "json" | "fhir";
  include_raw_data: boolean;
}

interface ClinicalExportResponse {
  export_url: string;
  expires_at: string;
}

// REST API
// GET /rest/v1/longitudinal_weekly_stats?user_id=eq.{userId}&year=eq.{year}
// GET /rest/v1/longitudinal_monthly_stats?user_id=eq.{userId}&year=eq.{year}
// GET /rest/v1/longitudinal_yearly_stats?user_id=eq.{userId}
// GET /rest/v1/longitudinal_patterns?user_id=eq.{userId}&is_active=eq.true
// GET /rest/v1/longitudinal_milestones?user_id=eq.{userId}
// POST /rest/v1/longitudinal_life_events
```

---

## Implementation Details

### Step-by-Step Approach

1. **Phase 1: Data Aggregation Pipeline** (Week 1-2)
   - Create daily to weekly aggregation job
   - Build weekly to monthly rollup
   - Implement monthly to yearly summary
   - Set up scheduled processing

2. **Phase 2: Pattern Detection** (Week 3)
   - Implement seasonal pattern algorithm
   - Build weekly cycle detector
   - Create correlation finder
   - Add improvement/regression detection

3. **Phase 3: Report Generation** (Week 4)
   - Design annual report template
   - Build PDF generation
   - Implement FHIR export
   - Create JSON export

4. **Phase 4: Milestone System** (Week 5)
   - Create milestone detection rules
   - Build celebration notification system
   - Implement progress comparison
   - Add shareable achievements

5. **Phase 5: UI & Polish** (Week 6)
   - Build timeline visualization
   - Create pattern display components
   - Implement sharing features
   - Add healthcare provider export

### File Structure

```
apps/ios/MindFriendApp/Features/Longitudinal/
├── LongitudinalView.swift
├── LongitudinalViewModel.swift
├── Timeline/
│   ├── TimelineView.swift
│   ├── YearSelectorView.swift
│   ├── MonthDetailView.swift
│   └── EventMarkerView.swift
├── Patterns/
│   ├── PatternsView.swift
│   ├── PatternDetailView.swift
│   └── SeasonalChartView.swift
├── Reports/
│   ├── AnnualReportView.swift
│   ├── ReportGeneratorView.swift
│   └── ClinicalExportView.swift
├── Milestones/
│   ├── MilestonesView.swift
│   ├── MilestoneCardView.swift
│   └── CelebrationView.swift
├── LifeEvents/
│   ├── LifeEventsView.swift
│   └── AddLifeEventView.swift
├── Models/
│   └── LongitudinalModels.swift
├── Components/
│   ├── TrendLineChart.swift
│   ├── YearComparisonChart.swift
│   ├── SeasonalHeatmap.swift
│   └── ProgressGaugeView.swift
└── Services/
    └── LongitudinalService.swift

supabase/functions/
├── aggregate-stats/
│   └── index.ts
├── detect-patterns/
│   └── index.ts
├── generate-annual-report/
│   └── index.ts
├── export-clinical/
│   └── index.ts
└── _shared/
    ├── aggregation-utils.ts
    ├── pattern-algorithms.ts
    └── report-templates.ts
```

### Key Algorithms

#### Data Aggregation Pipeline

```typescript
// supabase/functions/aggregate-stats/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { user_ids, force_recalculate } = await req.json();

  // Get users to process
  const usersToProcess = user_ids || (await getAllActiveUsers(supabase));

  let weeklyUpdated = 0;
  let monthlyUpdated = 0;
  let yearlyUpdated = 0;

  for (const userId of usersToProcess) {
    // Aggregate weekly stats
    const weeklyResult = await aggregateWeeklyStats(
      supabase,
      userId,
      force_recalculate,
    );
    weeklyUpdated += weeklyResult.updated;

    // Aggregate monthly stats (depends on weekly)
    const monthlyResult = await aggregateMonthlyStats(
      supabase,
      userId,
      force_recalculate,
    );
    monthlyUpdated += monthlyResult.updated;

    // Aggregate yearly stats (depends on monthly)
    const yearlyResult = await aggregateYearlyStats(
      supabase,
      userId,
      force_recalculate,
    );
    yearlyUpdated += yearlyResult.updated;
  }

  return new Response(
    JSON.stringify({
      weekly_updated: weeklyUpdated,
      monthly_updated: monthlyUpdated,
      yearly_updated: yearlyUpdated,
    }),
    {
      headers: { "Content-Type": "application/json" },
    },
  );
});

async function aggregateWeeklyStats(
  supabase: any,
  userId: string,
  force: boolean,
): Promise<{ updated: number }> {
  // Get the last aggregated week
  const { data: lastWeek } = await supabase
    .from("longitudinal_weekly_stats")
    .select("week_start")
    .eq("user_id", userId)
    .order("week_start", { ascending: false })
    .limit(1)
    .single();

  const startDate = force
    ? new Date(0)
    : lastWeek
      ? new Date(lastWeek.week_start)
      : await getFirstDataDate(supabase, userId);

  // Get weeks to process
  const weeks = getWeeksBetween(startDate, new Date());
  let updated = 0;

  for (const weekStart of weeks) {
    const weekEnd = new Date(weekStart);
    weekEnd.setDate(weekEnd.getDate() + 7);

    // Fetch all relevant data for the week
    const [moods, exercises, sleep, quests, journals] = await Promise.all([
      fetchMoodsForPeriod(supabase, userId, weekStart, weekEnd),
      fetchExercisesForPeriod(supabase, userId, weekStart, weekEnd),
      fetchSleepForPeriod(supabase, userId, weekStart, weekEnd),
      fetchQuestsForPeriod(supabase, userId, weekStart, weekEnd),
      fetchJournalsForPeriod(supabase, userId, weekStart, weekEnd),
    ]);

    // Calculate aggregates
    const stats = {
      user_id: userId,
      week_start: weekStart.toISOString().split("T")[0],
      year: weekStart.getFullYear(),
      week_number: getWeekNumber(weekStart),
      avg_mood: moods.length ? avg(moods.map((m: any) => m.score)) : null,
      min_mood: moods.length
        ? Math.min(...moods.map((m: any) => m.score))
        : null,
      max_mood: moods.length
        ? Math.max(...moods.map((m: any) => m.score))
        : null,
      mood_variance:
        moods.length >= 2 ? variance(moods.map((m: any) => m.score)) : null,
      mood_entry_count: moods.length,
      total_exercise_minutes: exercises.reduce(
        (sum: number, e: any) => sum + e.duration_seconds / 60,
        0,
      ),
      exercise_session_count: exercises.length,
      avg_sleep_hours: sleep.length
        ? avg(sleep.map((s: any) => s.duration_hours))
        : null,
      avg_sleep_quality: sleep.length
        ? avg(sleep.map((s: any) => s.quality_score))
        : null,
      quest_completion_rate: calculateQuestCompletionRate(quests),
      streak_maintained: calculateStreakMaintained(quests),
      journal_entry_count: journals.length,
      dominant_emotions: extractDominantEmotions(moods),
    };

    // Upsert
    await supabase
      .from("longitudinal_weekly_stats")
      .upsert(stats, { onConflict: "user_id,week_start" });

    updated++;
  }

  return { updated };
}

async function aggregateMonthlyStats(
  supabase: any,
  userId: string,
  force: boolean,
): Promise<{ updated: number }> {
  // Get weeks to aggregate into months
  const { data: weeks } = await supabase
    .from("longitudinal_weekly_stats")
    .select("*")
    .eq("user_id", userId)
    .order("week_start", { ascending: true });

  if (!weeks || weeks.length === 0) return { updated: 0 };

  // Group by month
  const monthGroups = groupByMonth(weeks);
  let updated = 0;

  for (const [monthKey, monthWeeks] of Object.entries(monthGroups)) {
    const [year, month] = monthKey.split("-").map(Number);
    const monthStart = new Date(year, month - 1, 1);

    // Get previous month for comparison
    const prevMonthStart = new Date(year, month - 2, 1);
    const { data: prevMonth } = await supabase
      .from("longitudinal_monthly_stats")
      .select("*")
      .eq("user_id", userId)
      .eq("month_start", prevMonthStart.toISOString().split("T")[0])
      .single();

    const avgMood = avgOfProperty(monthWeeks as any[], "avg_mood");
    const prevAvgMood = prevMonth?.avg_mood;

    const stats = {
      user_id: userId,
      month_start: monthStart.toISOString().split("T")[0],
      year,
      month,
      avg_mood: avgMood,
      mood_trend: determineTrend(prevAvgMood, avgMood),
      mood_volatility: avgOfProperty(monthWeeks as any[], "mood_variance"),
      avg_wellness_score: avgOfProperty(
        monthWeeks as any[],
        "avg_wellness_score",
      ),
      total_exercise_minutes: sumOfProperty(
        monthWeeks as any[],
        "total_exercise_minutes",
      ),
      avg_daily_exercise_minutes:
        sumOfProperty(monthWeeks as any[], "total_exercise_minutes") /
        getDaysInMonth(year, month),
      avg_sleep_hours: avgOfProperty(monthWeeks as any[], "avg_sleep_hours"),
      sleep_consistency_score: calculateSleepConsistency(monthWeeks as any[]),
      quest_completion_rate: avgOfProperty(
        monthWeeks as any[],
        "quest_completion_rate",
      ),
      longest_streak:
        Math.max(
          ...(monthWeeks as any[]).filter((w: any) => w.streak_maintained)
            .length,
          0,
        ) * 7,
      total_journal_entries: sumOfProperty(
        monthWeeks as any[],
        "journal_entry_count",
      ),
      key_themes: extractKeyThemes(monthWeeks as any[]),
      month_over_month_change: prevMonth
        ? {
            mood_change: prevAvgMood
              ? ((avgMood - prevAvgMood) / prevAvgMood) * 100
              : null,
            exercise_change: prevMonth.total_exercise_minutes
              ? ((sumOfProperty(monthWeeks as any[], "total_exercise_minutes") -
                  prevMonth.total_exercise_minutes) /
                  prevMonth.total_exercise_minutes) *
                100
              : null,
          }
        : {},
    };

    await supabase
      .from("longitudinal_monthly_stats")
      .upsert(stats, { onConflict: "user_id,month_start" });

    updated++;
  }

  return { updated };
}

function determineTrend(prev: number | null, current: number | null): string {
  if (!prev || !current) return "stable";
  const change = ((current - prev) / prev) * 100;
  if (change > 5) return "improving";
  if (change < -5) return "declining";
  return "stable";
}

function avg(arr: number[]): number {
  return arr.reduce((a, b) => a + b, 0) / arr.length;
}

function variance(arr: number[]): number {
  const mean = avg(arr);
  return (
    arr.reduce((sum, val) => sum + Math.pow(val - mean, 2), 0) / arr.length
  );
}

function avgOfProperty(arr: any[], prop: string): number | null {
  const values = arr.map((x) => x[prop]).filter((x) => x != null);
  return values.length ? avg(values) : null;
}

function sumOfProperty(arr: any[], prop: string): number {
  return arr.reduce((sum, x) => sum + (x[prop] || 0), 0);
}
```

#### Pattern Detection Algorithm

```typescript
// supabase/functions/detect-patterns/index.ts

interface DetectedPattern {
  type: string;
  description: string;
  confidence: number;
  evidence: any;
}

export async function detectPatterns(
  supabase: any,
  userId: string,
  lookbackMonths: number = 24,
): Promise<DetectedPattern[]> {
  const patterns: DetectedPattern[] = [];

  // Get historical data
  const lookbackDate = new Date();
  lookbackDate.setMonth(lookbackDate.getMonth() - lookbackMonths);

  const { data: monthlyStats } = await supabase
    .from("longitudinal_monthly_stats")
    .select("*")
    .eq("user_id", userId)
    .gte("month_start", lookbackDate.toISOString())
    .order("month_start", { ascending: true });

  if (!monthlyStats || monthlyStats.length < 12) {
    return patterns; // Not enough data
  }

  // Detect seasonal patterns
  const seasonalPattern = detectSeasonalPattern(monthlyStats);
  if (seasonalPattern) patterns.push(seasonalPattern);

  // Detect weekly cycles from weekly data
  const { data: weeklyStats } = await supabase
    .from("longitudinal_weekly_stats")
    .select("*")
    .eq("user_id", userId)
    .gte("week_start", lookbackDate.toISOString())
    .order("week_start", { ascending: true });

  const weekdayPattern = detectWeekdayPattern(weeklyStats);
  if (weekdayPattern) patterns.push(weekdayPattern);

  // Detect improvement trends
  const improvementPattern = detectImprovementTrend(monthlyStats);
  if (improvementPattern) patterns.push(improvementPattern);

  // Detect correlations
  const correlations = detectCorrelations(monthlyStats);
  patterns.push(...correlations);

  return patterns;
}

function detectSeasonalPattern(monthlyStats: any[]): DetectedPattern | null {
  // Group by season
  const seasons: Record<string, number[]> = {
    winter: [], // Dec, Jan, Feb
    spring: [], // Mar, Apr, May
    summer: [], // Jun, Jul, Aug
    fall: [], // Sep, Oct, Nov
  };

  const seasonMap: Record<number, string> = {
    12: "winter",
    1: "winter",
    2: "winter",
    3: "spring",
    4: "spring",
    5: "spring",
    6: "summer",
    7: "summer",
    8: "summer",
    9: "fall",
    10: "fall",
    11: "fall",
  };

  for (const stat of monthlyStats) {
    if (stat.avg_mood != null) {
      const season = seasonMap[stat.month];
      seasons[season].push(stat.avg_mood);
    }
  }

  // Calculate seasonal averages
  const seasonalAvgs: Record<string, number> = {};
  for (const [season, moods] of Object.entries(seasons)) {
    if (moods.length >= 3) {
      seasonalAvgs[season] = moods.reduce((a, b) => a + b, 0) / moods.length;
    }
  }

  if (Object.keys(seasonalAvgs).length < 4) {
    return null; // Not enough seasonal data
  }

  // Find significant differences
  const avgValues = Object.values(seasonalAvgs);
  const overallAvg = avgValues.reduce((a, b) => a + b, 0) / avgValues.length;
  const maxDiff = Math.max(...avgValues.map((v) => Math.abs(v - overallAvg)));

  if (maxDiff < 0.3) {
    return null; // No significant seasonal variation
  }

  const worstSeason = Object.entries(seasonalAvgs).sort(
    ([, a], [, b]) => a - b,
  )[0][0];
  const bestSeason = Object.entries(seasonalAvgs).sort(
    ([, a], [, b]) => b - a,
  )[0][0];

  return {
    type: "seasonal",
    description: `Your mood tends to be ${Math.round((seasonalAvgs[bestSeason] - seasonalAvgs[worstSeason]) * 20)}% higher in ${bestSeason} compared to ${worstSeason}.`,
    confidence: Math.min(0.9, 0.5 + monthlyStats.length * 0.02),
    evidence: {
      seasonal_averages: seasonalAvgs,
      best_season: bestSeason,
      worst_season: worstSeason,
      sample_size: monthlyStats.length,
    },
  };
}

function detectImprovementTrend(monthlyStats: any[]): DetectedPattern | null {
  if (monthlyStats.length < 6) return null;

  // Split into first half and second half
  const halfPoint = Math.floor(monthlyStats.length / 2);
  const firstHalf = monthlyStats.slice(0, halfPoint);
  const secondHalf = monthlyStats.slice(halfPoint);

  const firstAvg = avgOfNonNull(firstHalf.map((s: any) => s.avg_mood));
  const secondAvg = avgOfNonNull(secondHalf.map((s: any) => s.avg_mood));

  if (firstAvg == null || secondAvg == null) return null;

  const improvement = ((secondAvg - firstAvg) / firstAvg) * 100;

  if (Math.abs(improvement) < 5) return null;

  return {
    type: improvement > 0 ? "improvement" : "regression",
    description:
      improvement > 0
        ? `Your mood has improved by ${Math.round(improvement)}% over the past ${monthlyStats.length} months.`
        : `Your mood has decreased by ${Math.round(Math.abs(improvement))}% over the past ${monthlyStats.length} months.`,
    confidence: Math.min(0.85, 0.5 + monthlyStats.length * 0.015),
    evidence: {
      first_period_avg: firstAvg,
      second_period_avg: secondAvg,
      improvement_percent: improvement,
      months_analyzed: monthlyStats.length,
    },
  };
}

function detectCorrelations(monthlyStats: any[]): DetectedPattern[] {
  const correlations: DetectedPattern[] = [];

  // Check exercise-mood correlation
  const exerciseMoodCorr = calculateCorrelation(
    monthlyStats.map((s: any) => s.total_exercise_minutes),
    monthlyStats.map((s: any) => s.avg_mood),
  );

  if (Math.abs(exerciseMoodCorr) > 0.5) {
    correlations.push({
      type: "correlation",
      description:
        exerciseMoodCorr > 0
          ? "Months when you exercise more tend to have better moods."
          : "Interestingly, exercise and mood don't correlate as expected for you.",
      confidence: Math.min(0.8, Math.abs(exerciseMoodCorr)),
      evidence: {
        correlation_coefficient: exerciseMoodCorr,
        metrics: ["exercise", "mood"],
      },
    });
  }

  // Check sleep-mood correlation
  const sleepMoodCorr = calculateCorrelation(
    monthlyStats.map((s: any) => s.avg_sleep_hours),
    monthlyStats.map((s: any) => s.avg_mood),
  );

  if (Math.abs(sleepMoodCorr) > 0.5) {
    correlations.push({
      type: "correlation",
      description:
        sleepMoodCorr > 0
          ? "Better sleep months correlate with better mood months."
          : "Sleep duration doesn't strongly predict mood for you.",
      confidence: Math.min(0.8, Math.abs(sleepMoodCorr)),
      evidence: {
        correlation_coefficient: sleepMoodCorr,
        metrics: ["sleep", "mood"],
      },
    });
  }

  return correlations;
}

function calculateCorrelation(x: number[], y: number[]): number {
  // Filter out nulls and align arrays
  const pairs = x
    .map((xi, i) => [xi, y[i]])
    .filter(([a, b]) => a != null && b != null);

  if (pairs.length < 5) return 0;

  const xs = pairs.map((p) => p[0]);
  const ys = pairs.map((p) => p[1]);

  const n = pairs.length;
  const sumX = xs.reduce((a, b) => a + b, 0);
  const sumY = ys.reduce((a, b) => a + b, 0);
  const sumXY = pairs.reduce((sum, [x, y]) => sum + x * y, 0);
  const sumX2 = xs.reduce((sum, x) => sum + x * x, 0);
  const sumY2 = ys.reduce((sum, y) => sum + y * y, 0);

  const numerator = n * sumXY - sumX * sumY;
  const denominator = Math.sqrt(
    (n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY),
  );

  return denominator === 0 ? 0 : numerator / denominator;
}

function avgOfNonNull(arr: (number | null)[]): number | null {
  const valid = arr.filter((x) => x != null) as number[];
  return valid.length ? valid.reduce((a, b) => a + b, 0) / valid.length : null;
}
```

---

## Dependencies

### Internal Dependencies

- F001 (Biometric Correlation Engine) - Biometric data
- F002 (Daily Wellness Score) - Scoring consistency
- F003 (Predictive Mood Intelligence) - Pattern detection foundation
- Core Data System - Historical storage

### External Dependencies

- PDF generation library - Report exports
- FHIR library - Clinical export format
- Chart rendering - Visualizations

### Infrastructure

- Supabase Cron - Scheduled aggregation
- Supabase Storage - Report storage
- Supabase Edge Functions - Processing

---

## Edge Cases & Error Handling

| Scenario                         | Handling                                            |
| -------------------------------- | --------------------------------------------------- |
| User has < 1 year of data        | Show available data with "keep going" encouragement |
| Missing data periods             | Interpolate carefully, note gaps in reports         |
| Extreme outlier data             | Flag for review, don't let skew aggregates          |
| Pattern detection low confidence | Don't surface patterns below 60% confidence         |
| Export file too large            | Compress, offer date range selection                |
| User deletes account             | Preserve anonymized data for research with consent  |
| Cross-timezone data              | Normalize to user's primary timezone                |
| Data corruption detected         | Alert, attempt recovery from aggregates             |
| Healthcare format incompatible   | Fallback to PDF with disclaimer                     |

---

## Testing Requirements

### Unit Tests

```swift
import XCTest
@testable import MindFriendApp

final class LongitudinalTests: XCTestCase {

    func testSeasonalPatternsDecoding() throws {
        let json = """
        {
            "spring": {"avg_mood": 3.5, "avg_wellness": 75},
            "summer": {"avg_mood": 4.0, "avg_wellness": 80},
            "fall": {"avg_mood": 3.2, "avg_wellness": 70},
            "winter": {"avg_mood": 2.8, "avg_wellness": 65},
            "best_season": "summer",
            "challenging_season": "winter"
        }
        """

        let patterns = try JSONDecoder().decode(SeasonalPatterns.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(patterns.bestSeason, "summer")
        XCTAssertEqual(patterns.challengingSeason, "winter")
        XCTAssertEqual(patterns.summer.avgMood, 4.0)
    }

    func testMilestoneTypeDisplayNames() {
        XCTAssertEqual(LongitudinalMilestone.MilestoneType.moodImprovement.rawValue, "mood_improvement")
        XCTAssertEqual(LongitudinalMilestone.MilestoneType.journeyAnniversary.rawValue, "journey_anniversary")
    }

    func testYearComparisonCalculation() {
        let comparison = YearComparison(
            previousYear: 2024,
            moodImprovement: 15.5,
            wellnessImprovement: 10.0,
            exerciseChange: 25.0,
            sleepImprovement: 5.0,
            streakImprovement: 50
        )

        XCTAssertEqual(comparison.previousYear, 2024)
        XCTAssertEqual(comparison.moodImprovement, 15.5)
    }

    func testPatternConfidenceThreshold() {
        let lowConfidencePattern = LongitudinalPattern(
            id: UUID(),
            userId: UUID(),
            patternType: .seasonal,
            patternDescription: "Test",
            confidence: 0.4,
            evidence: PatternEvidence(
                dataPoints: [],
                statisticalSignificance: 0.4,
                affectedMetrics: [],
                timeframeDescription: ""
            ),
            firstDetectedAt: Date(),
            lastConfirmedAt: Date(),
            occurrences: 1,
            isActive: true,
            userAcknowledged: false,
            userFeedback: nil,
            createdAt: Date()
        )

        // Pattern should not be shown to user (< 0.6 confidence)
        XCTAssertTrue(lowConfidencePattern.confidence < 0.6)
    }
}
```

### Integration Tests

```swift
final class LongitudinalIntegrationTests: XCTestCase {
    var service: LongitudinalService!

    override func setUp() async throws {
        service = LongitudinalService(supabase: TestSupabaseClient())
    }

    func testFetchYearlyStats() async throws {
        let stats = try await service.fetchYearlyStats(year: 2025)

        XCTAssertNotNil(stats)
        XCTAssertEqual(stats.year, 2025)
        XCTAssertNotNil(stats.avgMood)
    }

    func testFetchPatterns() async throws {
        let patterns = try await service.fetchActivePatterns()

        // All returned patterns should be active
        for pattern in patterns {
            XCTAssertTrue(pattern.isActive)
        }
    }

    func testGenerateAnnualReport() async throws {
        let report = try await service.generateAnnualReport(year: 2025, includePDF: false)

        XCTAssertNotNil(report.id)
        XCTAssertEqual(report.reportType, .annual)
        XCTAssertNotNil(report.reportData.summary)
    }

    func testMilestoneDetection() async throws {
        // Seed improvement data
        await seedImprovingMoodData()

        // Trigger milestone detection
        let milestones = try await service.detectNewMilestones()

        XCTAssertFalse(milestones.isEmpty)
        XCTAssertTrue(milestones.contains { $0.milestoneType == .moodImprovement })
    }

    func testClinicalExport() async throws {
        let export = try await service.generateClinicalExport(
            startDate: Calendar.current.date(byAdding: .year, value: -1, to: Date())!,
            endDate: Date(),
            format: .pdf
        )

        XCTAssertNotNil(export.exportUrl)
        XCTAssertNotNil(export.expiresAt)
    }
}
```

### UI Tests

```swift
final class LongitudinalUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        app = XCUIApplication()
        app.launch()
    }

    func testTimelineNavigation() {
        navigateToLongitudinal()

        // Select different years
        app.buttons["2025"].tap()
        XCTAssertTrue(app.staticTexts["2025 Overview"].exists)

        app.buttons["2024"].tap()
        XCTAssertTrue(app.staticTexts["2024 Overview"].exists)
    }

    func testPatternDisplay() {
        navigateToLongitudinal()
        app.buttons["Patterns"].tap()

        XCTAssertTrue(app.staticTexts["Your Patterns"].exists)
        // Should show discovered patterns
        XCTAssertTrue(app.cells.count > 0)
    }

    func testAnnualReportGeneration() {
        navigateToLongitudinal()
        app.buttons["Annual Report"].tap()
        app.buttons["Generate 2025 Report"].tap()

        // Wait for generation
        XCTAssertTrue(app.activityIndicators["Generating..."].exists)
        XCTAssertTrue(app.buttons["View Report"].waitForExistence(timeout: 30))
    }

    func testMilestonesCelebration() {
        navigateToLongitudinal()
        app.buttons["Milestones"].tap()

        XCTAssertTrue(app.staticTexts["Your Milestones"].exists)

        // Tap uncelebrated milestone
        let milestone = app.cells.firstMatch
        if milestone.exists {
            milestone.tap()
            XCTAssertTrue(app.buttons["Celebrate"].exists)
        }
    }

    func testClinicalExport() {
        navigateToLongitudinal()
        app.buttons["Export"].tap()
        app.buttons["Clinical Export"].tap()

        XCTAssertTrue(app.staticTexts["Export for Healthcare Provider"].exists)

        app.buttons["Generate PDF"].tap()

        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 15))
    }

    private func navigateToLongitudinal() {
        app.tabBars["TabBar"].buttons["Profile"].tap()
        app.buttons["Mental Health Journey"].tap()
    }
}
```
