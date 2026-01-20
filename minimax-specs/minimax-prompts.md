# Claude Code Implementation Prompts for MindFriend Minimax Specs

This file contains detailed, comprehensive, unambiguous implementation prompts for the breakthrough features and quick wins in `minimax-specs/`. These specs represent the next generation of MindFriend features identified in the App Analysis.

---

## Prompt 1: Conversation Rehearsal Studio

**Command:** `/dev-pipeline`

**Specification:** `minimax-specs/02-conversation-rehearsal-spec.md`

### Feature Summary

Interactive practice environment where users rehearse difficult conversations (boundaries, conflicts, feedback, job interviews) with AI that simulates realistic responses. Includes tone rewrite suggestions and real-time feedback.

### Implementation Requirements

#### 1.1 Database Schema

```sql
-- Pre-built scenario templates
CREATE TABLE conversation_scenarios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category TEXT NOT NULL CHECK (category IN ('work', 'relationships', 'social', 'family', 'health', 'financial')),
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    situation_context TEXT NOT NULL,
    other_party_role TEXT NOT NULL,  -- e.g., "manager", "partner", "friend"
    key_points_to_convey TEXT[],  -- Array of points user should cover
    desired_outcome TEXT NOT NULL,
    difficulty_level TEXT DEFAULT 'medium' CHECK (difficulty_level IN ('easy', 'medium', 'advanced')),
    estimated_minutes INTEGER DEFAULT 10,
    tips_for_user TEXT[],
    is_premium BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Custom scenarios created by users
CREATE TABLE custom_scenarios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    other_party_role TEXT NOT NULL,
    situation_summary TEXT NOT NULL,
    key_points TEXT NOT NULL,
    desired_outcome TEXT NOT NULL,
    is_public BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User rehearsal sessions
CREATE TABLE rehearsal_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    scenario_id UUID REFERENCES conversation_scenarios(id),
    custom_scenario_id UUID REFERENCES custom_scenarios(id),
    started_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    confidence_rating INTEGER CHECK (confidence_rating BETWEEN 1 AND 5),
    notes TEXT,
    transcript TEXT NOT NULL,
    feedback_summary TEXT,
    is_bookmarked BOOLEAN DEFAULT FALSE
);

-- Bookmarked messages from rehearsals
CREATE TABLE rehearsal_bookmarks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    session_id UUID REFERENCES rehearsal_sessions(id) ON DELETE CASCADE NOT NULL,
    original_message TEXT NOT NULL,
    rewritten_message TEXT,
    tone_type TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Communication style patterns (for feedback)
CREATE TABLE communication_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern_type TEXT NOT NULL CHECK (pattern_type IN ('assertive', 'passive', 'aggressive', 'collaborative', 'passive_aggressive')),
    keywords TEXT[],
    example_phrases TEXT[],
    feedback_message TEXT NOT NULL
);
```

#### 1.2 Edge Functions

**Function 1: `list-scenarios`**

```typescript
interface Request {
  category?: string;
  difficulty?: string;
  search?: string;
  includePremium?: boolean;
}

interface Response {
  scenarios: Array<{
    id: UUID;
    category: string;
    title: string;
    description: string;
    difficulty: string;
    estimatedMinutes: number;
    isPremium: boolean;
  }>;
  recommended?: UUID[];  -- Based on user context
}
```

**Function 2: `get-scenario`**

```typescript
interface Request {
  scenarioId: UUID;
}

interface Response {
  scenario: {
    id: UUID;
    category: string;
    title: string;
    description: string;
    situationContext: string;
    otherPartyRole: string;
    keyPoints: string[];
    desiredOutcome: string;
    difficulty: string;
    estimatedMinutes: number;
    tips: string[];
  };
  userHistory?: {
    timesPracticed: number;
    lastPracticedAt: ISO8601;
    averageConfidence: number;
  };
}
```

**Function 3: `start-rehearsal`**

```typescript
interface Request {
  scenarioId?: UUID;
  customScenarioId?: UUID;
  mode: 'practice' | 'focus';
}

interface Response {
  sessionId: UUID;
  systemContext: string;  -- AI persona description
  openingMessage: string;  -- AI's first line
  userContext: {
    scenarioTitle: string;
    keyPoints: string[];
    goal: string;
  };
  mode: string;
}
```

**Function 4: `rehearsal-message`**

```typescript
interface Request {
  sessionId: UUID;
  message: string;
  mode: 'practice' | 'focus';
}

interface Response {
  aiResponse: string;
  feedback?: {
    styleDetected: string;
    suggestions: string[];
    encouragement: string;
  };
  isComplete: boolean;
  nextPrompt?: string;
}
```

**Function 5: `tone-rewrite`**

```typescript
interface Request {
  message: string;
  toneOptions: Array<'direct' | 'gentle' | 'assertive' | 'collaborative'>;
}

interface Response {
  rewrites: Array<{
    tone: string;
    rewrittenMessage: string;
    explanation: string;
    whyItWorks: string;
  }>;
}
```

**Function 6: `complete-rehearsal`**

```typescript
interface Request {
  sessionId: UUID;
  confidenceRating: number;
  notes?: string;
}

interface Response {
  success: boolean;
  summary: {
    duration: number;
    exchangesCount: number;
    stylesUsed: string[];
    highlights: string[];
  };
  feedbackSummary: string;
  suggestions: string[];
  achievements?: {
    badges: string[];
    xpEarned: number;
  };
}
```

#### 1.3 iOS Implementation

**Views Required:**
- `ScenarioCatalogView.swift` - Browse scenarios with search/filter
- `ScenarioDetailView.swift` - View scenario with tips
- `RehearsalView.swift` - Main rehearsal interface
- `ToneRewriteView.swift` - Rewrite options panel
- `RehearsalSummaryView.swift` - Session summary with feedback
- `CustomScenarioCreatorView.swift` - Create custom scenarios
- `SessionHistoryView.swift` - View past rehearsals

**Key Flows:**
1. **Scenario Selection:** Browse → Filter → Preview → Start
2. **Rehearsal Mode:** Chat interface with context panel, tone rewrite, real-time feedback
3. **Tone Rewrite:** Select message → Generate alternatives → Choose → Use
4. **Session Complete:** Summary → Feedback → Save/Export → History

#### 1.4 AI Prompt Engineering

**System Prompt for AI Persona:**
```
You are role-playing as a {other_party_role} in a conversation practice scenario.
Scenario: {situation_context}
Your goal: {desired_outcome}

Be realistic and responsive. Respond naturally as this person would.
If the user is unclear, ask clarifying questions.
Do not be adversarial, but also don't make it too easy.
Keep responses moderate in length (1-3 sentences typically).
```

#### 1.5 Testing Requirements

- Scenario loading and filtering
- Chat flow with context preservation
- Tone rewrite generation quality
- Feedback accuracy and helpfulness
- Session completion and history
- Custom scenario creation and usage
- Bookmark functionality

#### 1.6 Success Criteria

- [ ] Session completion rate: 70%+
- [ ] Tone rewrite usefulness rating: 4.0/5.0
- [ ] Confidence improvement: +0.5 average from pre to post
- [ ] Return rate: 40% practice again within 7 days
- [ ] Custom scenario creation: 20% of users create at least one

---

## Prompt 2: Real-Time Cognitive Bias Coach

**Command:** `/dev-pipeline`

**Specification:** `minimax-specs/03-cognitive-bias-coach-spec.md`

### Feature Summary

Detects cognitive distortions (all-or-nothing thinking, catastrophizing, mind-reading, etc.) during chat conversations and offers gentle, educational reframes inline without requiring journaling.

### Implementation Requirements

#### 2.1 Database Schema

```sql
-- Cognitive distortion taxonomy
CREATE TABLE cognitive_distortions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,  -- e.g., 'all_or_nothing'
    name TEXT NOT NULL,
    short_description TEXT NOT NULL,
    full_description TEXT NOT NULL,
    examples TEXT[],
    questions_to_challenge TEXT[],  -- Socratic questions
    reframe_templates TEXT[],  -- Template variations
    severity_weight INTEGER DEFAULT 1,
    display_order INTEGER NOT NULL
);

-- Distortion examples:
-- all_or_nothing: "If I'm not perfect, I'm a failure"
-- catastrophizing: "This small mistake means everything will fall apart"
-- mind_reading: "They must think I'm stupid"
-- fortune_telling: "This will never work out"
-- labeling: "I'm such an idiot"
-- should_statements: "I should be doing better"
-- emotional_reasoning: "I feel like a failure, so I must be one"
-- minimizing: "My success doesn't count because it was easy"
-- blame: "This is all their fault"
-- comparison: "Everyone else has this figured out"
-- regret_orientation: "I shouldn't have done that"
-- what_if: "What if something goes wrong?"

-- User distortion encounters (stored locally on device)
CREATE TABLE local_distortion_encounters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    distortion_code TEXT NOT NULL,
    original_message_preview TEXT NOT NULL,
    reframe_offered BOOLEAN DEFAULT TRUE,
    reframe_accepted BOOLEAN DEFAULT FALSE,
    encounter_type TEXT DEFAULT 'chat',
    occurred_at TIMESTAMPTZ DEFAULT NOW(),
    client_generated_id TEXT NOT NULL
);

-- Coach settings (per-user)
CREATE TABLE coach_settings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    is_enabled BOOLEAN DEFAULT TRUE,
    sensitivity_level TEXT DEFAULT 'balanced' CHECK (sensitivity_level IN ('minimal', 'balanced', 'frequent')),
    silent_hours_start TIME,
    silent_hours_end TIME,
    disabled_distortions TEXT[],  -- Codes user doesn't want to see
    show_patterns BOOLEAN DEFAULT TRUE,
    last_sync_at TIMESTAMPTZ
);

-- Educational content translations
CREATE TABLE distortion_education (
    distortion_id UUID REFERENCES cognitive_distortions(id),
    locale TEXT NOT NULL,
    name_translated TEXT NOT NULL,
    description_translated TEXT NOT NULL,
    examples_translated TEXT[],
    reframe_templates_translated TEXT[],
    PRIMARY KEY (distortion_id, locale)
);
```

#### 2.2 Edge Functions

**Function 1: `analyze-message`**

```typescript
interface Request {
  message: string;
  context?: {
    previousMessages?: string[];
    moodScore?: number;
  };
  sensitivityLevel: 'minimal' | 'balanced' | 'frequent';
  disabledDistortions?: string[];
}

interface Response {
  hasDistortion: boolean;
  distortions: Array<{
    code: string;
    name: string;
    confidence: number;  -- 0.0-1.0
    evidence: string;  -- Why this was detected
    triggerThreshold: number;  -- Why this met threshold
  }>;
  shouldOfferReframe: boolean;
  reframe?: {
    distortionCode: string;
    distortionName: string;
    explanation: string;
    reframe: string;
    question?: string;
    learnMoreUrl?: string;
  };
}
```

**Function 2: `get-reframe`**

```typescript
interface Request {
  distortionCode: string;
  originalMessage: string;
  conversationContext?: string;
}

interface Response {
  distortion: {
    code: string;
    name: string;
    description: string;
  };
  reframe: {
    primary: string;
    alternatives: string[];
  };
  socraticQuestion: string;
  explanation: string;
  resources?: {
    articleUrl?: string;
    exerciseId?: UUID;
  };
}
```

**Function 3: `coach-settings`**

```typescript
interface Request {
  isEnabled?: boolean;
  sensitivityLevel?: 'minimal' | 'balanced' | 'frequent';
  silentHours?: {
    start: string;
    end: string;
  };
  disabledDistortions?: string[];
  showPatterns?: boolean;
}

interface Response {
  success: boolean;
  settings: CoachSettings;
}
```

**Function 4: `my-patterns`**

```typescript
interface Request {
  startDate?: ISO8601;
  endDate?: ISO8601;
}

interface Response {
  patterns: {
    totalEncounters: number;
    byDistortion: Array<{
      code: string;
      name: string;
      count: number;
      percentage: number;
      trend: 'increasing' | 'stable' | 'decreasing';
    }>;
    mostCommon: string;
    improvedDistortions: string[];
    recommendedFocus: string;
  };
  weeklyInsight: string;
}
```

#### 2.3 On-Device Detection

```swift
// On-device NLP for low-latency distortion detection
class DistortionDetector {
    private let distortionPatterns: [DistortionPattern]
    private let confidenceThreshold = 0.7  // For balanced sensitivity
    
    func analyze(_ message: String) -> DistortionAnalysis {
        // Keyword-based pre-filtering
        // Pattern matching for distortion signatures
        // Confidence scoring
        // Return detection results
    }
    
    func shouldShowReframe(_ analysis: DistortionAnalysis, settings: CoachSettings) -> Bool {
        // Check if distortion meets threshold
        // Check if distortion is not disabled
        // Check if not in silent hours
        // Check sensitivity level
    }
}
```

#### 2.4 iOS Implementation

**Views Required:**
- `DistortionCoachView.swift` - Inline coach card in chat
- `DistortionLibraryView.swift` - Educational library
- `PatternInsightsView.swift` - Personal patterns over time
- `CoachSettingsView.swift` - Sensitivity and preferences

**Inline Coach Card UI:**
```
MindFriend:
"I always mess everything up. Nothing ever goes right."

┌─────────────────────────────────────────────┐
│ 💭 Noticed something                        │
│                                             │
│ "Always" and "nothing ever" can signal     │
│ "all-or-nothing thinking" — seeing things  │
│ as completely good or bad, no middle       │
│ ground.                                    │
│                                             │
│ 💡 Reframe:                                 │
│ "Some things went wrong, and some went     │
│ right. What went well today?"              │
│                                             │
│ [This helps]  [Not right now]  [Learn more]│
└─────────────────────────────────────────────┘
```

#### 2.5 Testing Requirements

- Distortion detection accuracy (>85%)
- False positive rate (<10%)
- Sensitivity level filtering
- Silent hours enforcement
- Pattern tracking and aggregation
- Library content display

#### 2.6 Success Criteria

- [ ] Intervention rate: 20% of messages trigger detection
- [ ] User engagement: 40% click "This helps"
- [ ] Pattern review: 25% of users view weekly patterns
- [ ] Distortion awareness: +15% improvement in quiz after 30 days
- [ ] User satisfaction: "This helps me think differently" >= 4.0/5.0

---

## Prompt 3: Boundary & Needs Planner

**Command:** `/dev-pipeline`

**Specification:** `minimax-specs/04-boundary-planner-spec.md`

### Feature Summary

Guided tool to help users clarify needs, define boundaries, and generate personalized scripts with practice prompts. Converts vague stress into concrete next steps.

### Implementation Requirements

#### 3.1 Database Schema

```sql
-- Needs assessments
CREATE TABLE needs_assessments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    assessment_type TEXT NOT NULL CHECK (assessment_type IN ('work', 'relationships', 'family', 'friends')),
    responses JSONB NOT NULL,
    top_needs TEXT[],
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Defined boundaries
CREATE TABLE defined_boundaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    needs_assessment_id UUID REFERENCES needs_assessments(id),
    boundary_type TEXT NOT NULL CHECK (boundary_type IN ('time', 'emotional', 'digital', 'physical', 'financial')),
    statement_text TEXT NOT NULL,
    why_matters TEXT,
    stakeholder TEXT,
    expected_impact TEXT,
    status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'ready', 'practiced', 'set', 'adjusted')),
    scripts JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Boundary follow-ups
CREATE TABLE boundary_follow_ups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    boundary_id UUID REFERENCES defined_boundaries(id) ON DELETE CASCADE NOT NULL,
    check_in_at TIMESTAMPTZ NOT NULL,
    outcome TEXT CHECK (outcome IN ('successful', 'partially_successful', 'challenged', 'ignored')),
    notes TEXT,
    user_reflection TEXT,
    next_action TEXT,
    completed_at TIMESTAMPTZ
);

-- Script templates
CREATE TABLE boundary_script_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    boundary_type TEXT NOT NULL,
    relationship_type TEXT NOT NULL,
    template_variation TEXT NOT NULL CHECK (template_variation IN ('direct', 'gentle', 'assertive', 'collaborative')),
    template_text TEXT NOT NULL,
    tone_description TEXT,
    example_context TEXT
);
```

#### 3.2 Edge Functions

**Function 1: `create-assessment`**

```typescript
interface Request {
  assessmentType: 'work' | 'relationships' | 'family' | 'friends';
  responses: Record<string, unknown>;
}

interface Response {
  success: boolean;
  assessmentId: UUID;
  topNeeds: string[];
  recommendedBoundaries: Array<{
    type: string;
    suggestion: string;
    priority: 'high' | 'medium' | 'low';
  }>;
}
```

**Function 2: `generate-boundary`**

```typescript
interface Request {
  assessmentId?: UUID;
  boundaryType: string;
  statement: string;
  whyMatters: string;
  stakeholder?: string;
}

interface Response {
  success: boolean;
  boundary: {
    id: UUID;
    type: string;
    statement: string;
    whyMatters: string;
    stakeholder?: string;
    expectedImpact: string;
    status: string;
  };
  nextSteps: string[];
}
```

**Function 3: `generate-scripts`**

```typescript
interface Request {
  boundaryId: UUID;
  relationshipType: string;
  variations: Array<'direct' | 'gentle' | 'assertive' | 'collaborative'>;
}

interface Response {
  success: boolean;
  scripts: Array<{
    variation: string;
    script: string;
    toneDescription: string;
    tips: string[];
  }>;
  practicePrompts: string[];
}
```

**Function 4: `schedule-followup`**

```typescript
interface Request {
  boundaryId: UUID;
  checkInAt: ISO8601;
}

interface Response {
  success: boolean;
  followUpId: UUID;
  reminderSet: boolean;
}
```

**Function 5: `record-outcome`**

```typescript
interface Request {
  followUpId: UUID;
  outcome: 'successful' | 'partially_successful' | 'challenged' | 'ignored';
  notes?: string;
  reflection?: string;
  nextAction?: string;
}

interface Response {
  success: boolean;
  boundaryUpdated: {
    id: UUID;
    status: string;
  };
  encouragement?: string;
  suggestions?: string[];
}
```

#### 3.3 iOS Implementation

**Views Required:**
- `NeedsAssessmentView.swift` - Guided questionnaire
- `PriorityMatrixView.swift` - Visual needs prioritization
- `BoundaryDefinitionView.swift` - Define boundary statement
- `ScriptGeneratorView.swift` - Generate and customize scripts
- `BoundaryFollowUpView.swift` - Check-in and outcome tracking
- `BoundariesListView.swift` - View all defined boundaries

**Needs Assessment Flow:**
```
Step 1: Exploration Questions
"When do you feel most drained in your relationships?"
→ Options or free-form response

Step 2: Priority Matrix
Visual quadrant: Important/Unimportant × Currently Met/Unmet
→ Tap to explore each quadrant

Step 3: Top Needs Selection
User selects 3-5 priority needs from assessment

Step 4: Boundary Definition
→ Convert needs into boundary statements
```

**Boundary Definition UI:**
```
My boundary is:
┌─────────────────────────────────────────────┐
│                                             │
│  "I need to stop working at 6pm every day  │
│   so I can be present for dinner with my   ││
│   family."                                 ││
│                                             │
└─────────────────────────────────────────────┘

Why this matters to me:
→ "My mental health improves when I have
   time to recharge."

Who does this affect?
→ "My manager"
```

#### 3.4 Testing Requirements

- Assessment flow completeness
- Priority matrix logic
- Script generation quality
- Follow-up scheduling
- Outcome recording
- Progress tracking

#### 3.5 Success Criteria

- [ ] Assessment completion: 60% of starters complete
- [ ] Script usage: 50% of boundaries have scripts
- [ ] Practice conversion: 30% practice their scripts
- [ ] Follow-up completion: 70% complete first follow-up
- [ ] Boundary success: 60% report positive outcomes
- [ ] Return rate: 40% create multiple boundaries

---

## Prompt 4: Stress Signature Explorer

**Command:** `/dev-pipeline`

**Specification:** `minimax-specs/06-stress-signature-explorer-spec.md`

### Feature Summary

Interactive visualization of user's stress patterns using in-app data (mood, chat topics, exercises) without formal assessments. Turns intuition into clear insight.

### Implementation Requirements

#### 4.1 Database Schema

```sql
-- Aggregated pattern snapshots (computed daily)
CREATE TABLE stress_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    period_start TIMESTAMPTZ NOT NULL,
    period_end TIMESTAMPTZ NOT NULL,
    dominant_mood TEXT,
    mood_volatility_score FLOAT,  -- 0-1 scale
    trigger_patterns JSONB NOT NULL,
    time_patterns JSONB,
    coping_effectiveness JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Individual pattern detections
CREATE TABLE pattern_detections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    pattern_type TEXT NOT NULL CHECK (pattern_type IN ('time', 'topic', 'activity', 'relationship')),
    pattern_category TEXT NOT NULL,
    confidence_score FLOAT NOT NULL,
    evidence_count INTEGER NOT NULL,
    evidence_preview TEXT[],
    first_detected_at TIMESTAMPTZ DEFAULT NOW(),
    last_detected_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE
);

-- User annotations on patterns
CREATE TABLE pattern_annotations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern_id UUID REFERENCES pattern_detections(id) ON DELETE CASCADE NOT NULL,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    annotation_type TEXT NOT NULL CHECK (annotation_type IN ('note', 'coping_strategy', 'progress_update')),
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Coping effectiveness tracking
CREATE TABLE coping_tracking (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    trigger_pattern_id UUID REFERENCES pattern_detections(id) ON DELETE CASCADE NOT NULL,
    coping_method TEXT NOT NULL,
    effectiveness_rating INTEGER CHECK (effectiveness_rating BETWEEN 1 AND 5),
    used_at TIMESTAMPTZ DEFAULT NOW(),
    notes TEXT
);
```

#### 4.2 Edge Functions

**Function 1: `generate-signature`**

```typescript
interface Request {
  periodDays?: number;  -- Default 30
}

interface Response {
  success: boolean;
  signature: {
    period: { start: ISO8601; end: ISO8601 };
    dominantMood: string;
    volatilityScore: number;
    patterns: Array<{
      type: string;
      category: string;
      confidence: number;
      evidence: string[];
      trend: 'increasing' | 'stable' | 'decreasing';
    }>;
    timeRhythms: {
      daily: Array<{ hour: number; mood: number }>;
      weekly: Array<{ day: number; mood: number }>;
    };
    copingInsights: Array<{
      method: string;
      effectiveness: number;
      triggers: string[];
    }>;
  };
  dataSufficiency: {
    sufficient: boolean;
    daysCollected: number;
    recommendation: string;
  };
}
```

**Function 2: `get-patterns`**

```typescript
interface Request {
  patternType?: string;
  activeOnly?: boolean;
}

interface Response {
  patterns: Array<{
    id: UUID;
    type: string;
    category: string;
    confidence: number;
    evidenceCount: number;
    evidencePreview: string[];
    trend: string;
    firstDetected: ISO8601;
    lastDetected: ISO8601;
  }>;
  annotations?: Array<{
    patternId: UUID;
    type: string;
    content: string;
    createdAt: ISO8601;
  }>;
}
```

**Function 3: `annotate-pattern`**

```typescript
interface Request {
  patternId: UUID;
  annotationType: 'note' | 'coping_strategy' | 'progress_update';
  content: string;
}

interface Response {
  success: boolean;
  annotationId: UUID;
}
```

**Function 4: `track-coping`**

```typescript
interface Request {
  triggerPatternId: UUID;
  copingMethod: string;
  effectivenessRating: number;
  notes?: string;
}

interface Response {
  success: boolean;
  trackingId: UUID;
  insight?: {
    totalUses: number;
    averageEffectiveness: number;
    recommendation: string;
  };
}
```

**Function 5: `compare-periods`**

```typescript
interface Request {
  period1Start: ISO8601;
  period1End: ISO8601;
  period2Start: ISO8601;
  period2End: ISO8601;
}

interface Response {
  success: boolean;
  comparison: {
    improvedPatterns: Array<{
      pattern: string;
      beforeScore: number;
      afterScore: number;
      change: number;
    }>;
    stablePatterns: Array<{
      pattern: string;
      score: number;
    }>;
    needsAttentionPatterns: Array<{
      pattern: string;
      score: number;
      recommendation: string;
    }>;
  };
  weeklyInsight: string;
}
```

#### 4.3 iOS Implementation

**Views Required:**
- `StressSignatureView.swift` - Main visualization
- `TriggerMapView.swift` - Interactive trigger cluster
- `TimeRhythmView.swift` - Day/week pattern grid
- `PatternComparisonView.swift` - Period-over-period comparison
- `PatternDetailView.swift` - Deep dive into specific pattern

**Visualization Types:**
1. **Timeline:** Mood/emotion arc over time
2. **Trigger Map:** Visual clustering of stressors
3. **Time Rhythm:** Day/hour grid with color coding
4. **Coping Matrix:** What works for what

#### 4.4 Testing Requirements

- Pattern detection with various data completeness levels
- Time zone handling for rhythm view
- Annotation CRUD operations
- Comparison calculations accuracy
- Coping tracking aggregation

#### 4.5 Success Criteria

- [ ] Explorer adoption: 30% of DAU visit within 30 days
- [ ] Pattern discovery: 80% find at least one new insight
- [ ] Data contribution: 70% have 14+ days of data
- [ ] Coping action: 40% track coping for triggers
- [ ] Repeat usage: 50% return weekly
- [ ] User rating: "This helps me understand myself" >= 4.2/5.0

---

## Prompt 5: Sensory Regulation Toolkit (Non-Audio)

**Command:** `/dev-pipeline`

**Specification:** `minimax-specs/08-sensory-regulation-spec.md`

### Feature Summary

Visual and haptic regulation patterns (light pulsing, rhythmic vibration, tactile pacing) for discreet calming without headphones or audio.

### Implementation Requirements

#### 5.1 Database Schema

```sql
-- Visual pattern definitions
CREATE TABLE visual_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern_key TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL CHECK (category IN ('breathing', 'rhythmic', 'pacing')),
    default_duration_seconds INTEGER,
    default_speed INTEGER,
    is_premium BOOLEAN DEFAULT FALSE,
    icon TEXT,
    animation_config JSONB
);

-- Haptic pattern definitions
CREATE TABLE haptic_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern_key TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL CHECK (category IN ('breathing', 'pacing', 'alert')),
    haptic_schema JSONB NOT NULL,
    default_intensity FLOAT DEFAULT 0.5,
    is_premium BOOLEAN DEFAULT FALSE
);

-- User preferences
CREATE TABLE toolkit_preferences (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    default_pattern_key TEXT,
    default_duration INTEGER,
    haptic_enabled BOOLEAN DEFAULT TRUE,
    haptic_intensity FLOAT DEFAULT 0.5,
    visual_intensity FLOAT DEFAULT 0.7,
    dim_during_use BOOLEAN DEFAULT FALSE,
    quick_access_enabled BOOLEAN DEFAULT TRUE,
    quick_access_pattern_keys TEXT[],
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Usage tracking (privacy-preserving)
CREATE TABLE toolkit_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    pattern_key TEXT NOT NULL,
    duration_seconds INTEGER NOT NULL,
    completed BOOLEAN DEFAULT TRUE,
    helpful_rating INTEGER,
    occurred_at TIMESTAMPTZ DEFAULT NOW(),
    client_generated_id TEXT NOT NULL
);
```

#### 5.2 iOS Implementation (Core Features)

**Views Required:**
- `SensoryToolkitView.swift` - Main toolkit home
- `VisualPatternView.swift` - Breathing/visual patterns
- `HapticPatternView.swift` - Tactile patterns
- `ToolkitSettingsView.swift` - Preferences
- `QuickAccessWidget` - Home screen widget

**Visual Patterns:**
```swift
enum VisualPattern: String, CaseIterable {
    case expandingCircle = "expanding_circle"
    case pulsingSquare = "pulsing_square"
    case waveAnimation = "wave"
    case bouncingDot = "bouncing_dot"
    case spiralMotion = "spiral"
    case flowerBloom = "flower_bloom"
    case dotGrid = "dot_grid"
    case ribbonFlow = "ribbon_flow"
    
    var displayName: String { ... }
    var description: String { ... }
    var category: PatternCategory { ... }
}
```

**Haptic Patterns (Core Haptics):**
```swift
enum HapticPattern: String, CaseIterable {
    case breathCue = "breath_cue"  -- Inhale/exhale timing
    case heartbeat = "heartbeat"    -- 60 bpm pulse
    case wave = "wave"             -- Rising/falling intensity
    case counting = "counting"     -- Numbered taps for pacing
    case sos = "sos"               -- Emergency pattern
    
    var displayName: String { ... }
    var schema: CHHapticPattern { ... }
}
```

**Key Flows:**
1. **Quick Access:** Home widget → One-tap start
2. **Pattern Selection:** Browse categories → Select pattern → Adjust settings → Start
3. **Custom Session:** Adjust speed/duration/intensity → Save as preset

#### 5.3 Testing Requirements

- Animation timing accuracy
- Haptic pattern playback
- Duration timer accuracy
- Settings persistence
- Quick-access widget functionality
- Background session handling

#### 5.4 Success Criteria

- [ ] Toolkit adoption: 40% of DAU use within 30 days
- [ ] Session completion: 80% complete started sessions
- [ ] Quick-access: 60% of users enable widget
- [ ] Haptic engagement: 50% of sessions use haptics
- [ ] User rating: "This helps me calm down" >= 4.0/5.0
- [ ] Crisis usage: 20% report using in stressful moments

---

## Prompt 6: Values Compass & Decision Coach

**Command:** `/dev-pipeline`

**Specification:** `minimax-specs/11-values-compass-spec.md`

### Feature Summary

Values clarification tool with guided discovery, visual compass representation, and decision-making support for hard choices.

### Implementation Requirements

#### 6.1 Database Schema

```sql
-- User values profile
CREATE TABLE user_values (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    values_data JSONB NOT NULL,
    top_values TEXT[],
    custom_values TEXT[],
    values_categories JSONB,
    completed_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Values cards library
CREATE TABLE values_cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    value_key TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL CHECK (category IN ('personal', 'relationships', 'work', 'growth')),
    icon TEXT,
    questions TEXT[],
    examples TEXT[]
);

-- User decisions
CREATE TABLE user_decisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    question TEXT NOT NULL,
    options JSONB NOT NULL,
    relevant_values TEXT[],
    analysis JSONB,
    decision_made TEXT,
    confidence_score FLOAT,
    outcome TEXT,
    reflection TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

-- Values journal entries
CREATE TABLE values_journal (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    value_key TEXT NOT NULL,
    entry_type TEXT NOT NULL CHECK (entry_type IN ('action', 'conflict', 'alignment', 'growth')),
    description TEXT NOT NULL,
    impact_level INTEGER CHECK (impact_level BETWEEN 1 AND 5),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Trade-off exercises
CREATE TABLE trade_off_scenarios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scenario_type TEXT NOT NULL,
    scenario_text TEXT NOT NULL,
    value_a TEXT NOT NULL,
    value_b TEXT NOT NULL,
    questions TEXT[],
    example_resolution TEXT
);
```

#### 6.2 Edge Functions

**Function 1: `values-discovery`**

```typescript
interface Request {
  // No input - generates assessment based on user
}

interface Response {
  success: boolean;
  assessmentId: UUID;
  cards: Array<{
    id: UUID;
    valueKey: string;
    displayName: string;
    description: string;
    icon: string;
    category: string;
  }>;
  phase: 'must_have' | 'important' | 'less_important';
}

interface ContinueAssessmentRequest {
  assessmentId: UUID;
  phase: string;
  selections: string[];
}

interface ContinueAssessmentResponse {
  success: boolean;
  nextPhase?: string;
  cards?: Array<Card>;
  compass?: {
    topValues: string[];
    visualData: Record<string, unknown>;
  };
}
```

**Function 2: `analyze-decision`**

```typescript
interface Request {
  decisionQuestion: string;
  options: Array<{ id: string; description: string }>;
  relevantValues?: string[];
}

interface Response {
  success: boolean;
  analysis: {
    question: string;
    valuesAlignment: Array<{
      value: string;
      optionAlignments: Record<string, number>;  -- optionId: alignment score
    }>;
    prosConsByValue: Array<{
      value: string;
      pros: Array<{ option: string; text: string }>;
      cons: Array<{ option: string; text: string }>;
    }>;
    recommendation?: string;
    confidenceScore: number;
  };
  suggestedValues?: string[];  -- If user didn't provide
}
```

**Function 3: `trade-off-exercise`**

```typescript
interface Request {
  scenarioType?: string;
}

interface Response {
  success: boolean;
  scenario: {
    id: UUID;
    type: string;
    text: string;
    valueA: string;
    valueB: string;
    questions: string[];
  };
}
```

#### 6.3 iOS Implementation

**Views Required:**
- `ValuesDiscoveryView.swift` - Card selection flow
- `ValuesCompassView.swift` - Visual compass
- `DecisionCoachView.swift` - Decision analysis
- `TradeOffExerciseView.swift` - Values conflict practice
- `ValuesJournalView.swift` - Track values in action
- `ValuesSettingsView.swift` - Manage values profile

**Values Compass UI:**
```
                    Growth
                      ↑
                       \\
                        \\
    Freedom ──────────────── Autonomy
                          /
                         /
                        ↓
                   Family

Top 5:
1. 🧭 Growth (inner direction)
2. 🏔️ Autonomy (self-determination)
3. 🤝 Connection (meaningful bonds)
4. 🏠 Security (stability)
5. ✨ Creativity (expression)

[Export]  [Add Custom]  [Edit]
```

#### 6.4 Testing Requirements

- Values assessment flow completeness
- Compass visualization accuracy
- Decision analysis quality
- Trade-off exercise logic
- Journal entry tracking
- Export functionality

#### 6.5 Success Criteria

- [ ] Discovery completion: 50% of starters complete
- [ ] Compass export: 30% export their compass
- [ ] Decision coach usage: 25% use for a decision
- [ ] Decision confidence: 4.0/5.0 average rating
- [ ] Trade-off completion: 60% of started exercises
- [ ] Journal engagement: 20% add entries weekly

---

## Prompt 7: Emotion-Aware Voice Companion

**Command:** `/dev-pipeline`

**Specification:** `minimax-specs/12-emotion-aware-voice-spec.md`

### Feature Summary

Voice mode enhancement that analyzes speech prosody (tone, pace, stress) to detect emotional state and dynamically adjust AI response pacing and empathy level.

### Implementation Requirements

#### 7.1 Database Schema

```sql
-- Voice calibration profiles
CREATE TABLE voice_profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    baseline_metrics JSONB NOT NULL,
    is_calibrated BOOLEAN DEFAULT FALSE,
    calibration_completed_at TIMESTAMPTZ,
    sensitivity_level TEXT DEFAULT 'balanced' CHECK (sensitivity_level IN ('minimal', 'balanced', 'responsive')),
    disabled_adaptations TEXT[],
    last_calibration_at TIMESTAMPTZ
);

-- Voice session emotional summaries
CREATE TABLE voice_session_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    session_id UUID NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ NOT NULL,
    dominant_emotions JSONB NOT NULL,
    peak_distress_emotion TEXT,
    peak_distress_timestamp TIMESTAMPTZ,
    adaptations_applied JSONB,
    emotional_arc JSONB
);

-- Adaptation rules configuration
CREATE TABLE adaptation_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    emotion TEXT NOT NULL UNIQUE,
    speech_rate_multiplier FLOAT DEFAULT 1.0,
    empathy_level INTEGER DEFAULT 5 CHECK (empathy_level BETWEEN 1 AND 10),
    response_complexity TEXT DEFAULT 'normal' CHECK (response_complexity IN ('simple', 'normal', 'detailed')),
    intervention_type TEXT DEFAULT 'support' CHECK (intervention_type IN ('grounding', 'support', 'normal', 'challenging')),
    pause_duration_ms INTEGER DEFAULT 500,
    tone_adjustment JSONB
);
```

#### 7.2 Core Audio Analysis

```swift
// On-device prosody analysis
class ProsodyAnalyzer {
    func analyze(_ audioBuffer: AVAudioPCMBuffer) -> ProsodyAnalysis {
        // Pitch variation detection
        let pitchVariance = detectPitchVariance(audioBuffer)
        
        // Speech rate calculation
        let wordsPerMinute = calculateSpeechRate(audioBuffer)
        
        // Volume dynamics
        let dynamicRange = calculateDynamicRange(audioBuffer)
        
        // Pause patterns
        let pauseCount = countPauses(audioBuffer)
        let averagePauseDuration = calculateAveragePauseDuration(audioBuffer)
        
        // Tremor detection (stress indicator)
        let tremorLevel = detectTremor(audioBuffer)
        
        return ProsodyAnalysis(
            pitchVariance: pitchVariance,
            speechRate: wordsPerMinute,
            dynamicRange: dynamicRange,
            pauseCount: pauseCount,
            pauseDuration: averagePauseDuration,
            tremorLevel: tremorLevel,
            timestamp: Date()
        )
    }
    
    func detectEmotion(from analysis: ProsodyAnalysis) -> DetectedEmotion {
        // Classification based on metrics
        // Return emotion type + confidence
    }
}
```

#### 7.3 Adaptation Engine

```swift
class VoiceAdaptationEngine {
    func adaptedResponse(for emotion: DetectedEmotion, baseResponse: String) -> AdaptedResponse {
        let rules = getAdaptationRules(for: emotion)
        
        return AdaptedResponse(
            text: baseResponse,
            speechRate: baseSpeechRate * rules.speechRateMultiplier,
            empathyLevel: rules.empathyLevel,
            complexity: rules.responseComplexity,
            interventionType: rules.interventionType,
            extraPauseMs: rules.pauseDurationMs,
            extraPauses: insertExtraPauses(in: baseResponse, every: rules.pauseInterval)
        )
    }
}
```

#### 7.4 iOS Implementation

**Views Required:**
- `VoiceModeView.swift` - Voice chat with emotion indicator
- `VoiceCalibrationView.swift` - Initial voice profile setup
- `VoiceSettingsView.swift` - Sensitivity and preferences
- `VoiceSessionSummaryView.swift` - Post-session emotional recap

**Voice Mode UI with Emotion:**
```
┌─────────────────────────────────────────────────┐
│  MindFriend         [💬 🎤 🔴]  [End]           │
├─────────────────────────────────────────────────┤
│  💭 Detecting: Anxious (82% confidence)     │
│  → Adapting response for your state          │
├─────────────────────────────────────────────────┤
│                                             │
│         [Animated Voice Wave]                │
│                                             │
│  "I hear that presenting makes you          │
│   nervous. Let's try something together..."  │
│                                             │
└─────────────────────────────────────────────────┘
```

#### 7.5 Testing Requirements

- Emotion detection accuracy (>85%)
- Adaptation quality and naturalness
- Latency (adaptation in <100ms)
- Calibration effectiveness
- Session summary accuracy

#### 7.6 Success Criteria

- [ ] Adoption: 30% of voice users enable
- [ ] Detection accuracy: 85% correct
- [ ] User satisfaction: 4.5/5.0 with emotion-aware mode
- [ ] Perceived attunement: +20% vs standard voice
- [ ] Calibration completion: 70% complete initial

---

## Prompt 8: Camera Biofeedback Breathing Coach

**Command:** `/dev-pipeline`

**Specification:** `minimax-specs/13-camera-biofeedback-spec.md`

### Feature Summary

On-device camera respiration detection providing real-time visual feedback on breathing patterns. Adapts guidance pace until physiological calm is detected.

### Implementation Requirements

#### 8.1 Database Schema

```sql
-- Biofeedback session data
CREATE TABLE biofeedback_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    session_type TEXT NOT NULL CHECK (session_type IN ('guided', 'free', 'manual')),
    started_at TIMESTAMPTZ NOT NULL,
    duration_seconds INTEGER NOT NULL,
    baseline_rate FLOAT,
    ending_rate FLOAT,
    lowest_rate FLOAT,
    breath_count INTEGER,
    calming_detected BOOLEAN,
    quality_score FLOAT,
    metrics JSONB
);

-- Breathing pattern templates
CREATE TABLE breathing_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pattern_key TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    description TEXT NOT NULL,
    breaths_per_minute FLOAT NOT NULL,
    inhale_seconds FLOAT NOT NULL,
    hold_in_seconds FLOAT NOT NULL,
    exhale_seconds FLOAT NOT NULL,
    hold_out_seconds FLOAT DEFAULT 0,
    category TEXT NOT NULL CHECK (category IN ('calming', 'energizing', 'focus')),
    difficulty TEXT DEFAULT 'beginner' CHECK (difficulty IN ('beginner', 'intermediate', 'advanced'))
);

-- User preferences
CREATE TABLE biofeedback_preferences (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    target_bpm FLOAT DEFAULT 6.0,
    session_duration_default INTEGER DEFAULT 3,
    show_guidance_overlay BOOLEAN DEFAULT TRUE,
    audio_enabled BOOLEAN DEFAULT FALSE,
    haptics_enabled BOOLEAN DEFAULT TRUE,
    privacy_mode TEXT DEFAULT 'camera' CHECK (privacy_mode IN ('camera', 'manual', 'tap')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

#### 8.2 Camera-Based Respiration Detection

```swift
import AVFoundation
import Vision

class RespirationDetector {
    private var chestRegion: CGRect
    private var previousPositions: [CGPoint] = []
    
    func analyzeFrame(_ sampleBuffer: CMSampleBuffer) -> RespirationAnalysis {
        // Extract chest/shoulder region from frame
        let region = extractChestRegion(from: sampleBuffer)
        
        // Track pixel motion in region
        let motion = trackMotion(in: region, previousFrames: previousPositions)
        
        // Detect inhalation vs exhalation cycles
        let cycles = detectCycles(motion)
        
        // Calculate breathing rate
        let breathsPerMinute = calculateRate(cycles)
        
        // Assess depth (amplitude of motion)
        let depth = assessDepth(motion)
        
        // Detect regularity
        let regularity = assessRegularity(cycles)
        
        return RespirationAnalysis(
            rate: breathsPerMinute,
            depth: depth,  // 0.0-1.0
            regularity: regularity,  // 0.0-1.0
            currentPhase: cycles.last?.phase,  // inhale/exhale/hold
            quality: calculateQuality(rate, depth, regularity)
        )
    }
}
```

#### 8.3 iOS Implementation

**Views Required:**
- `BiofeedbackSessionView.swift` - Main breathing session
- `PatternSelectionView.swift` - Choose breathing pattern
- `SessionSummaryView.swift` - Session results
- `ManualModeView.swift` - Tap-to-breathe fallback

**Session UI:**
```
┌─────────────────────────────────────────────────┐
│  ← Back     3:00 remaining     [⚙️]            │
├─────────────────────────────────────────────────┤
│                                                 │
│              ○                                  │
│             /│\  ← Breath visualization         │
│              │                                 │
│         inhale      exhale      inhale          │
│           4s          7s          4s       │
│                                                 │
│  💓 Your breath: 8 bpm → 6 bpm (slowing!)    │
│  📈 Keep going! You're doing great.           │
│                                                 │
│  [Pause]                          [End Early]  │
└─────────────────────────────────────────────────┘
```

#### 8.4 Testing Requirements

- Respiration detection accuracy (>80%)
- Breath rate calculation correctness
- Session metrics accuracy
- Privacy mode fallback
- Performance on various devices

#### 8.5 Success Criteria

- [ ] Session completion: 85% of started sessions
- [ ] Detection accuracy: 80% match self-reported breath count
- [ ] Breath rate improvement: 20% average slowing
- [ ] Return rate: 50% of users return weekly
- [ ] Calming detection: 70% sessions show calming
- [ ] User satisfaction: 4.5/5.0 rating

---

## Prompt 9: Adaptive Home Layout & Ritual Surfaces

**Command:** `/dev-pipeline`

**Specification:** `minimax-specs/14-adaptive-home-spec.md`

### Feature Summary

Home screen modules reorder and change based on time of day, recent behavior, and in-app signals without external integrations. Creates a living, contextual interface.

### Implementation Requirements

#### 9.1 Database Schema

```sql
-- Home module definitions
CREATE TABLE home_modules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    module_key TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    category TEXT NOT NULL CHECK (category IN ('quest', 'mood', 'exercise', 'chat', 'progress')),
    priority_default INTEGER NOT NULL DEFAULT 5,
    time_slots JSONB,  -- {morning: [1,2], afternoon: [3,4]}
    is_pinnable BOOLEAN DEFAULT TRUE,
    icon TEXT,
    min_importance INTEGER DEFAULT 1,
    max_importance INTEGER DEFAULT 3,
    config JSONB
);

-- User home layout preferences
CREATE TABLE home_layout_preferences (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    pinned_modules TEXT[],
    hidden_modules TEXT[],
    custom_order TEXT[],
    adaptation_enabled BOOLEAN DEFAULT TRUE,
    time_adaptation_enabled BOOLEAN DEFAULT TRUE,
    behavior_adaptation_enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Behavior signals
CREATE TABLE behavior_signals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    signal_type TEXT NOT NULL,
    priority INTEGER NOT NULL DEFAULT 5,
    expires_at TIMESTAMPTZ NOT NULL,
    acknowledged_at TIMESTAMPTZ,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Ritual definitions
CREATE TABLE rituals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ritual_key TEXT NOT NULL UNIQUE,
    trigger_type TEXT NOT NULL,
    trigger_config JSONB NOT NULL,
    display_name TEXT NOT NULL,
    description TEXT NOT NULL,
    animation_config JSONB,
    duration_seconds INTEGER DEFAULT 5,
    is_premium BOOLEAN DEFAULT FALSE
);
```

#### 9.2 Layout Computation Engine

```swift
class HomeLayoutEngine {
    func computeLayout(for user: User, at time: Date) -> [LayoutModule] {
        var modules: [LayoutModule] = []
        
        // 1. Get base modules from preferences
        let preferences = user.layoutPreferences
        let availableModules = getAvailableModules()
        
        // 2. Apply time-based ordering
        let timeOfDay = classifyTimeOfDay(time)
        modules = orderByTimeSlot(availableModules, timeOfDay)
        
        // 3. Apply behavior signals
        let signals = getActiveSignals(for: user)
        modules = boostBySignals(modules, signals)
        
        // 4. Apply pinned/hidden preferences
        modules = applyPreferences(modules, preferences)
        
        // 5. Check for ritual triggers
        if let ritual = shouldShowRitual(for: user, at: time) {
            modules.insert(ritual, at: 0)
        }
        
        return modules
    }
    
    private func classifyTimeOfDay(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<11: return "morning"
        case 11..<17: return "afternoon"
        case 17..<21: return "evening"
        default: return "night"
        }
    }
}
```

#### 9.3 iOS Implementation

**Views Required:**
- `AdaptiveHomeView.swift` - Main home with adaptive layout
- `HomeCustomizationView.swift` - Pin/hide modules
- `RitualMomentView.swift` - Celebration animations
- `LayoutPreviewView.swift` - Preview different times

**Time-Based Layout Examples:**

*Morning:*
- Intent prompt (priority 1)
- Quick mood check (priority 2)
- Suggested exercise (priority 3)
- Quest (priority 4)

*Afternoon:*
- Mid-day check-in (priority 1)
- Quest progress (priority 2)
- Exercise (priority 3)
- Chat (priority 4)

*Evening:*
- Wind-down ritual (priority 1)
- Journal prompt (priority 2)
- Sleep prep (priority 3)
- Next day preview (priority 4)

#### 9.4 Testing Requirements

- Time-of-day detection accuracy
- Behavior signal priority handling
- Layout computation consistency
- Pin/hide persistence
- Ritual trigger conditions
- Performance (layout computes <50ms)

#### 9.5 Success Criteria

- [ ] Adaptation adoption: 70% keep enabled
- [ ] Ritual engagement: 60% complete rituals
- [ ] Customization: 40% modify layout
- [ ] Time-of-day engagement: +15% morning/evening opens
- [ ] User perception: "Feels personalized" 4/5.0

---

## Prompt 10: Multimodal Emotional State Engine (Moonshot)

**Command:** `/dev-pipeline`

**Specification:** `minimax-specs/15-multimodal-engine-spec.md`

### Feature Summary

Opt-in, on-device fusion of voice tone, typing cadence, and respiration to dynamically shape AI support. Closed-loop emotional co-regulation system.

### Implementation Requirements

#### 10.1 Database Schema

```sql
-- Multimodal fusion state (temporary, session-scoped)
CREATE TABLE multimodal_state (
    session_id UUID NOT NULL,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    voice_confidence FLOAT,
    typing_confidence FLOAT,
    respiration_confidence FLOAT,
    fused_state TEXT NOT NULL,
    fusion_confidence FLOAT NOT NULL,
    state_vector JSONB,
    adaptations_applied JSONB,
    raw_signals JSONB
);

-- User multimodal consent
CREATE TABLE multimodal_consent (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    is_enabled BOOLEAN DEFAULT FALSE,
    voice_consent BOOLEAN DEFAULT FALSE,
    typing_consent BOOLEAN DEFAULT FALSE,
    respiration_consent BOOLEAN DEFAULT FALSE,
    consent_timestamp TIMESTAMPTZ,
    last_active_at TIMESTAMPTZ,
    streams_active TEXT[],
    privacy_settings JSONB
);

-- Session multimodal summaries
CREATE TABLE multimodal_session_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    session_id UUID NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ NOT NULL,
    streams_used TEXT[],
    dominant_states JSONB,
    state_transitions INTEGER,
    crisis_indicators INTEGER,
    regulation_success_rate FLOAT,
    adaptations_applied JSONB,
    user_feedback TEXT
);
```

#### 10.2 Fusion Engine

```swift
class MultimodalFusionEngine {
    func fuse(
        voice: ProsodyAnalysis?,
        typing: TypingCadenceAnalysis?,
        respiration: RespirationAnalysis?
    ) -> FusedState {
        
        // Collect available signals
        var signals: [Signal] = []
        
        if let voice = voice {
            signals.append(Signal(
                type: .voice,
                confidence: voice.confidence,
                state: classifyEmotion(from: voice),
                weight: 1.0
            ))
        }
        
        if let typing = typing {
            signals.append(Signal(
                type: .typing,
                confidence: typing.confidence,
                state: classifyEmotion(from: typing),
                weight: 0.5
            ))
        }
        
        if let respiration = respiration {
            signals.append(Signal(
                type: .respiration,
                confidence: respiration.quality,
                state: classifyStress(from: respiration),
                weight: 0.3
            ))
        }
        
        // Weighted fusion
        let fusedState = weightedFusion(signals)
        let confidence = calculateOverallConfidence(signals)
        
        return FusedState(
            primaryEmotion: fusedState.primary,
            secondaryEmotion: fusedState.secondary,
            confidence: confidence,
            signals: signals,
            adaptationsNeeded: determineAdaptations(fusedState),
            crisisIndicators: detectCrisis(fusedState)
        )
    }
}
```

#### 10.3 iOS Implementation

**Views Required:**
- `MultimodalConsentView.swift` - Opt-in flow
- `MultimodalChatView.swift` - Chat with fusion state
- `StateVisualizationView.swift` - See detected state
- `MultimodalPrivacyView.swift` - Manage streams

**Consent Flow:**
1. Explanation of multimodal features
2. Per-stream consent (voice, typing, respiration)
3. Privacy guarantees (on-device only)
4. One-tap emergency disable

**Active State UI:**
```
┌─────────────────────────────────────────────────┐
│  MindFriend         [💬 🎤 📷 ◉]  [End]     │
│  ◉ Multimodal Active                            │
├─────────────────────────────────────────────────┤
│  💭 Calmly detected (92% confidence)        │
│  → Responding with gentle support           │
├─────────────────────────────────────────────────┤
│  Streams: 🎤 Voice ✓  ⌨️ Typing ✓  📷 Breath ✓│
│                                                 │
│  MindFriend:                                   │
│  "I hear how you're feeling. Let's take        │
│  a moment together..."                        │
│                                                 │
│  State: 🟢 Calm → 🟡 Mild concern (shifted)   │
│  [⚙️ Adjust Streams]  [🛡️ Pause Fusion]       │
└─────────────────────────────────────────────────┘
```

#### 10.4 Testing Requirements

- Fusion accuracy with synthetic data
- State transition detection
- Crisis detection accuracy
- Performance (<100ms latency)
- Privacy boundary enforcement
- Consent flow completeness

#### 10.5 Success Criteria

- [ ] Opt-in rate: 25% of engaged users
- [ ] Session engagement: +30% vs standard chat
- [ ] Regulation success: 75% distress reduction
- [ ] Crisis detection: 95% detection rate
- [ ] User satisfaction: 4.8/5.0 rating
- [ ] Retention impact: +20% weekly retention

---

## Prompt 11: Privacy Quick Lock

**Command:** `/dev-pipeline`

**Specification:** `minimax-specs/20-privacy-quick-lock-spec.md`

### Feature Summary

Optional app-level biometric authentication with auto-lock after inactivity for privacy-conscious users.

### Implementation Requirements

#### 11.1 Database Schema

```sql
CREATE TABLE privacy_lock_settings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    app_lock_enabled BOOLEAN DEFAULT FALSE,
    auto_lock_seconds INTEGER DEFAULT 300,
    quick_lock_method TEXT DEFAULT 'menu' CHECK (quick_lock_method IN ('menu', 'triple_tap')),
    triple_tap_enabled BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

#### 11.2 iOS Implementation

```swift
import LocalAuthentication

class PrivacyLockManager {
    private let context = LAContext()
    
    func isLockEnabled() -> Bool {
        // Check stored preference
    }
    
    func authenticate(reason: String) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            ) { success, error in
                if success {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(throwing: error ?? PrivacyLockError.authFailed)
                }
            }
        }
    }
    
    func shouldLock() -> Bool {
        // Check auto-lock timer
        // Check if app backgrounded
    }
}
```

**Views Required:**
- `PrivacyLockSettingsView.swift` - Toggle and options
- `LockScreenView.swift` - Authentication prompt

#### 11.3 Success Criteria

- [ ] Adoption: 30% of users enable
- [ ] Lock engagement: 10 locks/day per enabled user
- [ ] User satisfaction: 4.5/5.0 rating

---

## Prompt 12: Chat Action Cards

**Command:** `/dev-pipeline`

**Specification:** `minimax-specs/21-chat-action-cards-spec.md`

### Feature Summary

Convert AI suggestions into one-tap action cards in chat. Reduces friction between insight and action.

### Implementation Requirements

#### 12.1 Database Schema

```sql
CREATE TABLE action_card_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trigger_type TEXT NOT NULL,
    card_title TEXT NOT NULL,
    card_description TEXT NOT NULL,
    action_destination TEXT NOT NULL,
    icon TEXT,
    estimated_minutes INTEGER DEFAULT 1,
    priority INTEGER DEFAULT 5,
    is_premium BOOLEAN DEFAULT FALSE,
    conditions JSONB
);

CREATE TABLE chat_action_cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL,
    message_id UUID NOT NULL,
    card_type TEXT NOT NULL,
    card_data JSONB NOT NULL,
    is_dismissed BOOLEAN DEFAULT FALSE,
    is_completed BOOLEAN DEFAULT FALSE,
    displayed_at TIMESTAMPTZ DEFAULT NOW(),
    action_taken_at TIMESTAMPTZ
);
```

#### 12.2 iOS Implementation

**Views Required:**
- `ActionCardView.swift` - Inline card display
- `ActionCardStackView.swift` - Multiple cards

**Card Types:**
- Exercise: "Start breathing exercise (2 min)"
- Journal: "Write about this (5 min)"
- Quest: "Complete quest: X"
- Mood: "Log how you're feeling"

#### 12.3 Success Criteria

- [ ] Card CTR: 40% tap rate
- [ ] Action completion: 70% of taps complete
- [ ] Engagement lift: +15% exercise starts

---

## Prompt 13: One-Tap "Rewrite My Thought"

**Command:** `/dev-pipeline`

**Specification:** `minimax-specs/22-rewrite-my-thought-spec.md`

### Feature Summary

Instant cognitive reframing for selected chat messages. Users select their message and get alternative phrasings.

### Implementation Requirements

#### 13.1 Database Schema

```sql
CREATE TABLE rewrite_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    session_id UUID NOT NULL,
    original_message TEXT NOT NULL,
    rewrite_type TEXT NOT NULL,
    rewritten_message TEXT NOT NULL,
    was_applied BOOLEAN DEFAULT FALSE,
    feedback_rating INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE rewrite_types (
    type_key TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    description TEXT NOT NULL,
    system_prompt_suffix TEXT NOT NULL,
    icon TEXT
);
```

#### 13.2 Rewrite Types

| Type | Example Input | Example Output |
|------|--------------|---------------|
| Less Catastrophic | "I always fail" | "Some things haven't worked out" |
| More Balanced | "This is terrible" | "Some parts are challenging" |
| More Actionable | "Everything is wrong" | "What can I address first?" |
| More Self-Compassionate | "I'm a failure" | "I'm struggling but trying" |

#### 13.3 Success Criteria

- [ ] Rewrite usage: 15% of eligible messages
- [ ] Apply rate: 50% of rewrites applied
- [ ] User satisfaction: 4.2/5.0 rating

---

## Prompt 14: Calm Screen Mode

**Command:** `/dev-pipeline`

**Specification:** `minimax-specs/23-calm-screen-mode-spec.md`

### Feature Summary

Low-stimulus UI preset with reduced motion, softer typography, muted colors for sensory needs.

### Implementation Requirements

#### 14.1 Database Schema

```sql
CREATE TABLE ui_preferences (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    screen_mode TEXT DEFAULT 'standard' CHECK (screen_mode IN ('standard', 'calm')),
    reduced_motion BOOLEAN DEFAULT FALSE,
    reduced_transparency BOOLEAN DEFAULT FALSE,
    reduced_noise BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

#### 14.2 Theme Configuration

```swift
enum ScreenMode {
    case standard
    case calm
    
    var colors: ColorScheme {
        // Calm: muted, warm, lower saturation
    }
    
    var animationDuration: Double {
        // Calm: 0.5x standard duration
    }
    
    var hapticIntensity: Float {
        // Calm: 0.3x standard intensity
    }
}
```

#### 14.3 Visual Changes

| Element | Standard | Calm |
|---------|----------|------|
| Background | Light/neutral | Warm cream |
| Colors | Vibrant | Muted sage |
| Typography | Standard | Increased line height |
| Animations | Bouncy | Slow, smooth |
| Notifications | Banners | Subtle |
| Haptics | Standard | Softer |

#### 14.4 Success Criteria

- [ ] Adoption: 15% of users enable
- [ ] Retention: 80% stay enabled after 7 days
- [ ] User satisfaction: 4.5/5.0 rating

---

## Usage Instructions

Each prompt is designed for `/dev-pipeline` execution. Copy the relevant prompt section and execute with `/dev-pipeline` to implement the full feature including:

1. Database migrations
2. Edge Functions
3. iOS views and services
4. Tests
5. Integration with existing systems

Prompts are ordered by priority for incremental implementation.
