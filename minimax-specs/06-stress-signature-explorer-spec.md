# Stress Signature Explorer

**Priority:** #7 (Implementation Roadmap)
**Scores:** Delight 7/10 | Differentiation 7/10 | Feasibility Medium | Revenue Medium

## Step 1: Feature Analysis

### Core purpose and value proposition
- Create an interactive visualization of the user's stress and emotional patterns using only in-app data.
- Transform intuition into clear insight without formal assessments or clinical questionnaires.
- Help users recognize their unique "stress signature" for earlier intervention.

### Target users and use cases
- Users who want to understand their emotional patterns without taking tests.
- Users trying to identify triggers for anxiety or stress.
- Users interested in self-awareness and personal growth.

### Dependencies / prerequisites
- Mood history data.
- Chat topic analysis (in-app, no external processing).
- Exercise completion patterns.
- Quest engagement data.

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Stress Signature Explorer
- **Description:** An interactive, visual map that reveals a user's internal triggers and stress patterns using data they already generate (mood logs, chat topics, exercise choices). No formal assessments required—just insights derived from behavior.
- **Business justification and user value:** Turns in-app behavior into self-knowledge. Pattern visualization without clinical assessments feels approachable and non-judgmental.

### 2. Functional Requirements

#### FR1: Data Aggregation
- User stories:
  - As a user, I want the system to understand me based on what I already share.
  - As a user, I want to see what patterns emerge from my app usage.
- Acceptance criteria:
  - Aggregate data from: mood entries, chat topics (anonymized), exercise preferences, quest completions, time-of-day patterns.
  - Minimum 7 days of data before generating insights.
  - Clear visualization of which data sources contribute to patterns.

#### FR2: Pattern Detection
- User stories:
  - As a user, I want to see what triggers my stress.
  - As a user, I want to understand my emotional rhythms.
- Acceptance criteria:
  - Detect patterns across: time of day, day of week, activity types, conversation topics, mood trends.
  - Show correlation strength for each pattern (strong, moderate, weak).
  - Explain how each pattern was detected.

#### FR3: Interactive Visualization
- User stories:
  - As a user, I want to explore my patterns visually.
  - As a user, I want to interact with the data to learn more.
- Acceptance criteria:
  - Interactive "stress signature" visualization:
    - Timeline view: emotional arc over time.
    - Trigger map: visual clustering of stressors.
    - Rhythm view: time-of-day/week patterns.
  - Tap/click to expand pattern details.
  - Filter by time range (week, month, all time).

#### FR4: Trigger Journaling
- User stories:
  - As a user, I want to add context to my identified triggers.
  - As a user, I want to track what helps when I'm stressed.
- Acceptance criteria:
  - Ability to annotate triggers with personal notes.
  - Add coping strategies to triggers that have worked.
  - Mark triggers as "managed" or "still working on."
  - Export trigger map as reference.

#### FR5: Progress Over Time
- User stories:
  - As a user, I want to see if my stress patterns are changing.
  - As a user, I want to see the impact of my efforts.
- Acceptance criteria:
  - "Compare periods" feature: Show pattern changes over time.
  - Highlight improvements: "Your Tuesday stress has decreased 30%."
  - Celebrate progress on managed triggers.
  - Suggest resources for remaining challenges.

### 3. Technical Specifications

#### Architecture and system design considerations
- All analysis runs on aggregated, anonymized data.
- No PII sent to external analysis services.
- Privacy-first: User sees only what affects them personally.
- Pattern detection uses simple statistical methods (correlation, clustering).

#### Data models and schemas (proposed)

```sql
-- Aggregated pattern snapshots (computed daily)
CREATE TABLE stress_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    period_start TIMESTAMPTZ NOT NULL,
    period_end TIMESTAMPTZ NOT NULL,
    dominant_mood TEXT,
    mood_volatility_score FLOAT,  -- 0-1 scale
    trigger_patterns JSONB NOT NULL,  -- Array of detected patterns
    time_patterns JSONB,  -- Time-of-day/week patterns
    coping_effectiveness JSONB,  -- What worked for what trigger
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Individual pattern detections
CREATE TABLE pattern_detections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    pattern_type TEXT NOT NULL,  -- 'time', 'topic', 'activity', 'relationship'
    pattern_category TEXT NOT NULL,  -- e.g., 'Tuesday_afternoon', 'work_related'
    confidence_score FLOAT NOT NULL,  -- 0-1 scale
    evidence_count INTEGER NOT NULL,  -- How many data points
    evidence_preview TEXT[],  -- Anonymized examples
    first_detected_at TIMESTAMPTZ DEFAULT NOW(),
    last_detected_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE
);

-- User annotations on patterns
CREATE TABLE pattern_annotations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern_id UUID REFERENCES pattern_detections(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    annotation_type TEXT NOT NULL,  -- 'note', 'coping_strategy', 'progress_update'
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Coping effectiveness tracking
CREATE TABLE coping_tracking (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    trigger_pattern_id UUID REFERENCES pattern_detections(id) ON DELETE CASCADE,
    coping_method TEXT NOT NULL,  -- 'breathing', 'exercise', 'journal', 'chat'
    effectiveness_rating INTEGER,  -- 1-5
    used_at TIMESTAMPTZ DEFAULT NOW(),
    notes TEXT
);
```

#### API endpoints / interfaces

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/functions/v1/generate-signature` | POST | Generate stress signature from data |
| `/functions/v1/get-patterns` | GET | Retrieve detected patterns |
| `/functions/v1/annotate-pattern` | POST | Add user annotation |
| `/functions/v1/track-coping` | POST | Record coping effectiveness |
| `/functions/v1/compare-periods` | POST | Compare patterns across time |
| `/functions/v1/export-signature` | GET | Export signature as PDF |

#### Integration points with existing systems
- **Mood Service:** Historical mood data.
- **Chat Service:** Anonymized topic analysis.
- **Exercise Service:** Activity preferences and completion.
- **Quest Service:** Engagement patterns.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions

**Main Explorer View**
```
┌─────────────────────────────────────────────────┐
│  Your Stress Signature                          │
│  Last 30 days                                   │
├─────────────────────────────────────────────────┤
│                                                 │
│      ┌─────────────────────────────────┐       │
│      │                                 │       │
│      │     🌊                          │       │
│      │    /‾‾‾\    🌊      🌊         │       │
│      │   /    \  /‾‾\   /    \        │       │
│      │  /      \/    \ /      \       │       │
│      │                                 │       │
│      │    Timeline of emotional        │       │
│      │    patterns over the month      │       │
│      └─────────────────────────────────┘       │
│                                                 │
│  📍 Key Patterns                                │
│  ┌───────────────────────────────────────────┐ │
│  │ 🔴 High stress Tue-Thu afternoons         │ │
│  │    Based on 12 mood entries               │ │
│  │    [Explore →]                            │ │
│  ├───────────────────────────────────────────┤ │
│  │ 🟡 Energy dips on weekends                │ │
│  │    Pattern detected in activity           │ │
│  │    [Explore →]                            │ │
│  ├───────────────────────────────────────────┤ │
│  │ 🟢 Exercise reduces evening stress        │ │
│  │    Strong correlation (0.8)               │ │
│  │    [Explore →]                            │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  [Change Time Range: 7 days ▼]  [Export]       │
└─────────────────────────────────────────────────┘
```

**Trigger Map Detail**
```
┌─────────────────────────────────────────────────┐
│  Your Trigger Map                               │
├─────────────────────────────────────────────────┤
│                                                 │
│      ● ● ● ● ●                                 │
│     /││││││\    ← Cluster of work-related    │
│    ● ● ● ● ● ●        stress                   │
│     \││││││/                                │
│      ● ● ● ●                                 │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ 🏢 Work Stress Cluster                     │ │
│  │ Intensity: High (8.2/10)                  │ │
│  │ Evidence: Chat topics, mood logs          │ │
│  │                                             │ │
│  │ Common patterns:                           │ │
│  │ • Sunday evening anticipation             │ │
│  │ • Mid-week project deadlines              │ │
│  │ • Morning meeting anxiety                 │ │
│  │                                             │ │
│  │ 💡 What helps you:                         │ │
│  │ • Morning exercise (85% effectiveness)    │ │
│  │ • Breaking tasks into smaller steps       │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  [← Back]  [Add Note]  [Track Coping]          │
└─────────────────────────────────────────────────┘
```

**Time Rhythm View**
```
┌─────────────────────────────────────────────────┐
│  Your Emotional Rhythm                          │
├─────────────────────────────────────────────────┤
│                                                 │
│  Day/Time Grid:                                 │
│           Mon  Tue  Wed  Thu  Fri  Sat  Sun    │
│  6am    🟢   🟢   🟢   🟢   🟢   🟡   🟢      │
│  9am    🟢   🔴   🟢   🟢   🟢   🟢   🟢      │
│  12pm   🟢   🔴   🟡   🔴   🟢   🟢   🟢      │
│  3pm    🟢   🔴   🟡   🟡   🟢   🟢   🟢      │
│  6pm    🟡   🔴   🔴   🔴   🟢   🟢   🟢      │
│  9pm    🟢   🟡   🟢   🟡   🟢   🟢   🟢      │
│                                                 │
│  🟢 Low stress  🟡 Medium  🔴 High stress      │
│                                                 │
│  Tap any cell for details.                      │
└─────────────────────────────────────────────────┘
```

**Progress Comparison**
```
┌─────────────────────────────────────────────────┐
│  Pattern Changes                                │
├─────────────────────────────────────────────────┤
│                                                 │
│  This Month vs. Last Month:                     │
│                                                 │
│  📉 Improved                                    │
│  • Tuesday stress down 30%                     │
│  • Better sleep patterns                       │
│  • More consistent exercise                    │
│                                                 │
│  ➡️ Stable                                     │
│  • Work-related stress unchanged              │
│  • Weekend mood stable                        │
│                                                 │
│  📈 Needs Attention                            │
│  • Thursday anxiety up 15%                    │
│    (Consider: boundary setting, exercise)      │
│                                                 │
│  [View Detailed Report]  [Share with Support]  │
└─────────────────────────────────────────────────┘
```

#### User flow diagram (text)

1. **First-time user:**
   - Opens explorer → Sees empty state with explanation → "Generate from my data" → Views initial signature → Explores patterns → Adds annotations.

2. **Returning user:**
   - Opens explorer → Checks updated patterns → Compares with last period → Updates coping strategies → Exports if needed.

3. **Pattern discovery:**
   - User notices a pattern → Taps to expand → Reads evidence → Adds personal note → Marks coping strategy → Sets reminder.

#### Accessibility requirements
- All visualizations have text alternatives.
- Pattern data available in list format.
- Screen reader compatible descriptions for each pattern.
- Color-blind friendly palettes (not just red/green).

### 5. Edge Cases and Error Handling

| Scenario | Handling |
|----------|----------|
| Insufficient data (<7 days) | Show "collecting data" state with progress |
| No patterns detected | Show "keep using the app" encouragement |
| User wants patterns deleted | Offer "clear all data" option |
| Sensitive trigger detected | Offer crisis resources; don't emphasize |
| Data anomaly (spike) | Highlight for user attention; ask for context |

### 6. Testing Requirements

#### Unit tests
- Pattern detection accuracy with synthetic data.
- Correlation calculation correctness.
- Time zone handling for rhythm view.
- Data aggregation from multiple sources.

#### Integration tests
- Full signature generation flow.
- Pattern comparison calculations.
- Annotation save/retrieve.
- Export generation.

#### UAT scenarios
- Use app for 7+ days → See meaningful patterns.
- Compare two time periods → See accurate differences.
- Add annotation → Appears in pattern detail.
- Export signature → Complete PDF generated.

### 7. Implementation Notes

#### Suggested implementation approach
- **Phase 1:** Basic pattern detection from mood + exercise data.
- **Phase 2:** Add chat topic analysis, time patterns.
- **Phase 3:** Interactive visualizations, progress comparison.
- **Phase 4:** Coping tracking, export features.

#### Potential challenges and mitigations
- **Challenge:** Pattern detection with sparse data. **Mitigation:** Set minimum thresholds; be transparent about confidence.
- **Challenge:** User concerns about data use. **Mitigation:** Clear privacy dashboard; explain what data is used.
- **Challenge:** Patterns are obvious to user. **Mitigation:** Focus on non-obvious correlations; offer "new insight" badges.

#### Performance considerations
- Pattern computation runs asynchronously.
- Results cached and updated periodically.
- Visualization data pre-computed server-side.
- Client only renders lightweight views.

## Step 3: Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Explorer adoption | 30% of DAU visit within 30 days | Explorer visits / DAU |
| Pattern discovery | 80% find at least one new insight | User survey |
| Data contribution | 70% have 14+ days of data | Users with sufficient data |
| Coping action | 40% track coping for triggers | Coping records / triggers |
| Repeat usage | 50% return weekly | Weekly return rate |
| Insight sharing | 20% export/share signature | Export events / users |
