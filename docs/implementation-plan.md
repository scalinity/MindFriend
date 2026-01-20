# Implementation Plan: MindFriend Feature Suite

**Date:** 2026-01-20
**Status:** Ready for Implementation
**Features:**
1. Safety Plan Feature
2. AI Coaching Modes
3. Weekly Wellbeing Check + Circle Habit Mechanics

---

## Executive Summary

This plan implements three interconnected features that enhance user safety, AI coaching structure, and social engagement. The features build upon existing infrastructure (Supabase, SwiftUI, Edge Functions) while introducing new data models, API endpoints, and UI components.

**Implementation Order:**
1. Safety Plan (Foundation - safety-critical feature)
2. AI Coaching Modes (Depends on chat infrastructure)
3. Weekly Wellbeing + Circle Habits (Depends on existing circles feature)

**Risk Level:** Medium - New data models and API contracts required

---

## Part A: Safety Plan Feature

### Overview

User-authored safety plan with 6 sections, accessible offline during crisis moments. Integrates with existing crisis flows and AI coaching modes.

### Files to Modify

| File | Change Type | Description | Risk |
|------|-------------|-------------|------|
| `apps/ios/MindFriendApp/Core/Models.swift` | Modify | Add SafetyPlan model types | Low |
| `apps/ios/MindFriendApp/Features/Crisis/CrisisResourcesView.swift` | Modify | Add safety plan CTA to crisis flow | Low |
| `apps/ios/MindFriendApp/Networking/Services/SupabaseDataService.swift` | Modify | Add safety plan CRUD methods | Medium |
| `supabase/functions/_shared/crisis.ts` | Modify | Integrate safety plan reference in crisis flow | Medium |
| `apps/ios/MindFriendApp/Features/Home/HomeView.swift` | Modify | Add safety plan to quick actions | Medium |

### Files to Create

| File | Purpose | Template/Pattern |
|------|---------|------------------|
| `apps/ios/MindFriendApp/Features/SafetyPlan/SafetyPlanView.swift` | Main safety plan wizard view | CrisisResourcesView.swift |
| `apps/ios/MindFriendApp/Features/SafetyPlan/SafetyPlanWizardView.swift` | 6-step wizard for plan creation | OnboardingFlow.swift |
| `apps/ios/MindFriendApp/Features/SafetyPlan/SafetyPlanSectionView.swift` | Reusable section component | AssessmentView.swift |
| `apps/ios/MindFriendApp/Features/SafetyPlan/CondensedSafetyPlanView.swift` | Crisis "I Need Help Now" view | SOSResourcesView.swift |
| `apps/ios/MindFriendApp/Features/SafetyPlan/ContactEntryView.swift` | Trusted contact entry form | Form-style view |
| `apps/ios/MindFriendApp/Features/SafetyPlan/SafetyPlanViewModel.swift` | Business logic for safety plan | ViewModel pattern |
| `apps/ios/MindFriendApp/Networking/Services/SafetyPlanService.swift` | API communication service | JournalService.swift |
| `apps/ios/MindFriendAppTests/SafetyPlanTests.swift` | Unit tests for safety plan | ModelsTests.swift |
| `supabase/functions/manage-safety-plan/index.ts` | Safety plan CRUD Edge Function | send-notification/index.ts |
| `supabase/functions/manage-safety-plan/test.ts` | Edge Function tests | send-notification/test.ts |

### Database Schema

**New Migration:** `supabase/migrations/20260415000000_safety_plan.sql`

```sql
-- Safety Plans Table (JSONB payload for MVP flexibility)
CREATE TABLE IF NOT EXISTS safety_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    version INTEGER NOT NULL DEFAULT 1,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    allow_ai_reference BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT one_plan_per_user UNIQUE (user_id)
);

-- Enable RLS
ALTER TABLE safety_plans ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can select own safety plan"
    ON safety_plans FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own safety plan"
    ON safety_plans FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own safety plan"
    ON safety_plans FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own safety plan"
    ON safety_plans FOR DELETE
    USING (auth.uid() = user_id);

-- Index for fast user lookup
CREATE INDEX idx_safety_plans_user_id ON safety_plans(user_id);

-- Updated_at trigger for versioning
CREATE OR REPLACE FUNCTION update_safety_plan_version()
RETURNS TRIGGER AS $$
BEGIN
    NEW.version = OLD.version + 1;
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_safety_plan_version
    BEFORE UPDATE ON safety_plans
    FOR EACH ROW
    EXECUTE FUNCTION update_safety_plan_version();

-- Safety Plan Cache Table (for offline access)
CREATE TABLE IF NOT EXISTS safety_plan_cache (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    cached_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days')
);

-- RLS for cache
ALTER TABLE safety_plan_cache ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own safety plan cache"
    ON safety_plan_cache FOR ALL
    USING (auth.uid() = user_id);
```

### API Contract

**Edge Function:** `POST /functions/v1/manage-safety-plan`

```typescript
// Request
interface SafetyPlanRequest {
  operation: "get" | "create" | "update" | "delete";
  payload?: SafetyPlanPayload;
  settings?: {
    allowAiReference?: boolean;
    pinnedToQuickActions?: boolean;
  };
}

// Response (200)
interface SafetyPlanResponse {
  success: boolean;
  data: SafetyPlan;
  error?: {
    code: string;
    message: string;
  };
}

interface SafetyPlan {
  id: string;
  version: number;
  payload: SafetyPlanPayload;
  settings: {
    allowAiReference: boolean;
    pinnedToQuickActions: boolean;
  };
  createdAt: string;
  updatedAt: string;
}

// Payload Schema
interface SafetyPlanPayload {
  warningSigns: SafetyPlanItem[];
  coping: CopingStrategy[];
  contacts: TrustedContact[];
  resources: ProfessionalResource[];
  environmentSteps: SafetyPlanItem[];
  anchors: SafetyPlanItem[];
}

interface SafetyPlanItem {
  id: string;
  text: string;
  isCustom?: boolean;
  order?: number;
  isFavorite?: boolean;
}

interface CopingStrategy {
  id: string;
  type: "exercise" | "custom";
  exerciseId?: string;
  label: string;
  duration?: number;
  category: "breathing" | "meditation" | "grounding" | "journaling" | "movement" | "custom";
  isFavorite?: boolean;
  order?: number;
}

interface TrustedContact {
  id: string;
  name: string;
  phone: string; // E.164 format
  relationship: "friend" | "family" | "partner" | "therapist" | "other";
  preferredMethod: "call" | "text";
  whatToSay?: string;
  isPrimary?: boolean;
  order?: number;
}

interface ProfessionalResource {
  id: string;
  type: "hotline" | "therapist" | "crisis-line" | "custom";
  name: string;
  phone?: string;
  url?: string;
  country?: string;
  notes?: string;
}
```

### Implementation Order

1. Create database migration
2. Create SafetyPlanService for API communication
3. Add SafetyPlan models to Core/Models.swift
4. Create SafetyPlanViewModel for business logic
5. Create SafetyPlanView and wizard components
6. Create CondensedSafetyPlanView for crisis mode
7. Create Edge Function manage-safety-plan
8. Integrate into CrisisResourcesView
9. Add to Home quick actions
10. Write unit tests

### Dependencies

- Supabase Swift SDK (existing)
- Existing CrisisResourcesView (for integration)
- Exercise library (for coping strategies)

---

## Part B: AI Coaching Modes

### Overview

Add "Reflect / Plan / Reframe" coaching modes to AI chat that produce structured, repeatable outcomes rather than open-ended conversation.

### Files to Modify

| File | Change Type | Description | Risk |
|------|-------------|-------------|------|
| `apps/ios/MindFriendApp/Features/Chat/ChatView.swift` | Modify | Add mode selector UI | Medium |
| `apps/ios/MindFriendApp/Core/Models.swift` | Modify | Add conversation mode types | Low |
| `apps/ios/MindFriendApp/Features/Chat/ChatViewModel.swift` | Modify | Add mode state management | Medium |
| `supabase/functions/chat/index.ts` | Modify | Add mode-aware AI responses | High |
| `apps/ios/MindFriendApp/Features/Home/HomeView.swift` | Modify | Add mode chip to conversation list | Low |

### Files to Create

| File | Purpose | Template/Pattern |
|------|---------|------------------|
| `apps/ios/MindFriendApp/Features/Chat/ModeSelectorView.swift` | Segmented control for mode selection | Custom UI component |
| `apps/ios/MindFriendApp/Features/Chat/PlanStepCardView.swift` | Card for plan step display | ExerciseCard.swift |
| `apps/ios/MindFriendApp/Features/Chat/ThoughtRecordFormView.swift` | Fillable thought record form | AssessmentView.swift |
| `apps/ios/MindFriendApp/Features/Chat/ReflectSummaryView.swift` | Reflection summary with journal prompt | InsightCard.swift |
| `apps/ios/MindFriendApp/Features/Chat/MessageBubbleView.swift` | Modified for structured content | Existing pattern |
| `apps/ios/MindFriendApp/Networking/Services/ConversationModeService.swift` | Mode persistence service | JournalService.swift |
| `apps/ios/MindFriendAppTests/CoachingModesTests.swift` | Mode functionality tests | ChatViewModelTests.swift |
| `supabase/functions/_shared/structured-outputs.ts` | Mode-specific AI prompt templates | crisis.ts |
| `supabase/functions/analyze-thought-record/index.ts` | Reframe analysis | analyze-journal/index.ts |

### Database Schema

**New Migration:** `supabase/migrations/20260415000001_conversation_modes.sql`

```sql
-- Conversation Modes Table
CREATE TABLE IF NOT EXISTS conversation_modes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    mode TEXT NOT NULL DEFAULT 'reflect',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(conversation_id)
);

-- RLS: User can only modify their own conversation modes
ALTER TABLE conversation_modes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own conversation modes"
    ON conversation_modes FOR ALL
    USING (auth.uid() IN (
        SELECT user_id FROM conversations WHERE id = conversation_id
    ));

-- Index for performance
CREATE INDEX idx_conversation_modes_conversation_id ON conversation_modes(conversation_id);

-- Thought Records Table (for Reframe mode)
CREATE TABLE IF NOT EXISTS thought_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    situation TEXT,
    automatic_thought TEXT,
    emotions JSONB NOT NULL DEFAULT '[]'::jsonb,
    evidence_for TEXT[] NOT NULL DEFAULT '{}',
    evidence_against TEXT[] NOT NULL DEFAULT '{}',
    alternative_thought TEXT,
    experiment_hypothesis TEXT,
    experiment_action TEXT,
    experiment_predicted_outcome TEXT,
    completed_fields TEXT[] NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- RLS for thought records
ALTER TABLE thought_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own thought records"
    ON thought_records FOR ALL
    USING (auth.uid() = user_id);

-- Index for user's thought records
CREATE INDEX idx_thought_records_user_id ON thought_records(user_id);
CREATE INDEX idx_thought_records_created_at ON thought_records(created_at DESC);

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_thought_record_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_thought_record_updated_at
    BEFORE UPDATE ON thought_records
    FOR EACH ROW
    EXECUTE FUNCTION update_thought_record_updated_at();

-- AI Suggested Quest Templates Table (for Plan mode)
CREATE TABLE IF NOT EXISTS ai_suggested_quests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    step_id TEXT NOT NULL,
    step_title TEXT NOT NULL,
    step_description TEXT,
    duration_min INTEGER NOT NULL,
    category TEXT NOT NULL,
    priority TEXT NOT NULL DEFAULT 'medium',
    was_selected BOOLEAN NOT NULL DEFAULT FALSE,
    was_scheduled BOOLEAN NOT NULL DEFAULT FALSE,
    scheduled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- RLS for AI suggested quests
ALTER TABLE ai_suggested_quests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own AI suggested quests"
    ON ai_suggested_quests FOR ALL
    USING (auth.uid() = user_id);

-- Index for performance
CREATE INDEX idx_ai_suggested_quests_user_id ON ai_suggested_quests(user_id);
CREATE INDEX idx_ai_suggested_quests_conversation_id ON ai_suggested_quests(conversation_id);
```

### API Contract Changes

**Chat Edge Function** modifications:

```typescript
// Extended Request
interface ChatRequest {
  conversationId: string;
  content: string;
  mode: "reflect" | "plan" | "reframe";  // NEW
  structured?: boolean;  // NEW - defaults to true when mode specified
}

// Extended Response
interface ChatResponse {
  userMessage: Message;
  assistantMessage: Message;
  structured?: {
    type: "reflect" | "plan" | "reframe";
    // Mode-specific output
    summary?: string;
    question?: string;
    journalPrompt?: {
      title: string;
      prompt: string;
      suggestedDurationMin: number;
    };
    steps?: PlanStep[];
    chosenStepId?: string | null;
    ifThenPlan?: {
      trigger: string;
      response: string;
    };
    thoughtRecord?: ThoughtRecordPartial;
    completionStatus?: "incomplete" | "partial" | "complete";
  };
  quotaUsed: number;
  quotaLimit: number;
}

interface PlanStep {
  id: string;
  title: string;
  description?: string;
  durationMin: number;
  category: "breath" | "reflect" | "action" | "connect" | "rest";
  priority: "high" | "medium" | "low";
}

interface ThoughtRecordPartial {
  situation?: string;
  automaticThought?: string;
  emotions?: { name: string; intensity: number }[];
  evidenceFor?: string[];
  evidenceAgainst?: string[];
  alternativeThought?: string;
  completedFields?: string[];
}
```

**New Endpoint:** `POST /functions/v1/set-conversation-mode`

```typescript
interface SetModeRequest {
  conversationId: string;
  mode: "reflect" | "plan" | "reframe";
}

interface SetModeResponse {
  success: boolean;
  mode: string;
  conversationId: string;
}
```

**New Endpoint:** `POST /functions/v1/save-thought-record`

```typescript
interface SaveThoughtRecordRequest {
  conversationId: string;
  situation?: string;
  automaticThought?: string;
  emotions: { name: string; intensity: number }[];
  evidenceFor?: string[];
  evidenceAgainst?: string[];
  alternativeThought?: string;
  experiment?: {
    hypothesis: string;
    action: string;
    predictedOutcome: string;
  };
}

interface SaveThoughtRecordResponse {
  success: boolean;
  thoughtRecordId: string;
  completionStatus: "incomplete" | "partial" | "complete";
}
```

### Implementation Order

1. Create database migration
2. Add mode types to Models.swift
3. Create ModeSelectorView component
4. Create ConversationModeService
5. Modify ChatView to include mode selector
6. Modify ChatViewModel to manage mode state
7. Create structured output views (PlanStepCardView, ThoughtRecordFormView, etc.)
8. Modify chat/index.ts for mode-aware AI responses
9. Create analyze-thought-record Edge Function
10. Add mode chip to conversation list in HomeView
11. Write unit tests

### Dependencies

- Existing ChatService (for message handling)
- Existing Conversation list (for mode display)
- AI chat infrastructure (chat Edge Function)
- Quest system (for Plan mode scheduling)

---

## Part C: Weekly Wellbeing Check + Circle Habits

### Overview

**Part A:** Weekly 30-60 second wellbeing measurement with trend charts and insights.

**Part B:** Circle habit mechanics with templates, recaps, and streak support nudges.

### Files to Modify

| File | Change Type | Description | Risk |
|------|-------------|-------------|------|
| `apps/ios/MindFriendApp/Features/Home/HomeView.swift` | Modify | Add weekly check card to home | Medium |
| `apps/ios/MindFriendApp/Core/Models.swift` | Modify | Add wellbeing check and circle template types | Low |
| `apps/ios/MindFriendApp/Features/Circles/CircleDetailView.swift` | Modify | Add template selector and recap display | Medium |
| `apps/ios/MindFriendApp/Features/Circles/CircleSettingsView.swift` | Modify | Add template management for admins | Low |
| `supabase/functions/chat/index.ts` | Modify | Update for plan mode quest scheduling | Medium |
| `apps/ios/MindFriendApp/Features/Insights/WeeklyInsightsView.swift` | Modify | Add wellbeing trends | Medium |

### Files to Create

| File | Purpose | Template/Pattern |
|------|---------|------------------|
| `apps/ios/MindFriendApp/Features/Wellbeing/WeeklyCheckCard.swift` | Home card for weekly check | RecoveryQuestBanner.swift |
| `apps/ios/MindFriendApp/Features/Wellbeing/WeeklyCheckView.swift` | Full check-in view | MoodCheckInView.swift |
| `apps/ios/MindFriendApp/Features/Wellbeing/WellbeingTrendsView.swift` | Trend chart view | WeeklyInsightsView.swift |
| `apps/ios/MindFriendApp/Features/Wellbeing/WeeklyCheckViewModel.swift` | Business logic for weekly check | MoodViewModel.swift |
| `apps/ios/MindFriendApp/Features/Circles/CheckInTemplateSelector.swift` | Template picker for check-ins | CategoryPickerView.swift |
| `apps/ios/MindFriendApp/Features/Circles/CircleRecapView.swift` | Weekly recap display | ShareCardSheet.swift |
| `apps/ios/MindFriendApp/Features/Circles/NudgeMemberSheet.swift` | Send nudge UI | SendHugButton.swift |
| `apps/ios/MindFriendApp/Features/Circles/TemplateManagementView.swift` | Admin template settings | SettingsView.swift |
| `apps/ios/MindFriendApp/Features/Circles/NudgeSettingsView.swift` | Nudge opt-in controls | PrivacySettingsView.swift |
| `apps/ios/MindFriendApp/Networking/Services/WeeklyCheckService.swift` | Weekly check API service | MoodService.swift |
| `apps/ios/MindFriendApp/Networking/Services/CircleHabitService.swift` | Circle habits API service | CircleService.swift |
| `apps/ios/MindFriendAppTests/WeeklyCheckTests.swift` | Weekly check unit tests | MoodViewModelTests.swift |
| `apps/ios/MindFriendAppTests/CircleHabitTests.swift` | Circle habit tests | RitualServiceTests.swift |
| `supabase/functions/weekly-check/index.ts` | Weekly check Edge Function | generate-insights/index.ts |
| `supabase/functions/weekly-check/test.ts` | Edge Function tests | send-notification/test.ts |
| `supabase/functions/circle-templates/index.ts` | Template management | validate-invite-code/index.ts |
| `supabase/functions/circle-recap/index.ts` | Weekly recap generation | generate-weekly-summary/index.ts |
| `supabase/functions/send-circle-nudge/index.ts` | Send nudge Edge Function | send-notification/index.ts |
| `supabase/functions/send-circle-nudge/test.ts` | Edge Function tests | send-notification/test.ts |

### Database Schema

**New Migration:** `supabase/migrations/20260415000002_weekly_wellbeing_circles.sql`

```sql
-- ============================================
-- Weekly Wellbeing Checks
-- ============================================
CREATE TABLE IF NOT EXISTS weekly_wellbeing_checks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    week_start DATE NOT NULL,
    stress INT NOT NULL CHECK (stress BETWEEN 0 AND 10),
    sleep_quality INT NOT NULL CHECK (sleep_quality BETWEEN 0 AND 10),
    energy INT NOT NULL CHECK (energy BETWEEN 0 AND 10),
    connection INT NOT NULL CHECK (connection BETWEEN 0 AND 10),
    focus INT NOT NULL CHECK (focus BETWEEN 0 AND 10),
    note TEXT,
    tags TEXT[],
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_user_week UNIQUE (user_id, week_start)
);

-- RLS: Only user can read/write
ALTER TABLE weekly_wellbeing_checks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own weekly checks"
    ON weekly_wellbeing_checks FOR ALL
    USING (auth.uid() = user_id);

-- Indexes
CREATE INDEX idx_weekly_wellbeing_user_week ON weekly_wellbeing_checks(user_id, week_start DESC);
CREATE INDEX idx_weekly_wellbeing_created_at ON weekly_wellbeing_checks(created_at DESC);

-- ============================================
-- Circle Templates
-- ============================================
CREATE TABLE IF NOT EXISTS circle_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    template_type TEXT NOT NULL, -- 'win_worry_need', 'energy_sentence', 'gratitude_intention'
    is_active BOOLEAN DEFAULT true,
    display_order INT DEFAULT 0,
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE circle_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Circle admins can manage templates"
    ON circle_templates FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM circles
            WHERE id = circle_templates.circle_id
            AND created_by = auth.uid()
        )
    );

CREATE POLICY "Circle members can view templates"
    ON circle_templates FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_id = circle_templates.circle_id
            AND user_id = auth.uid()
        )
    );

-- Index
CREATE INDEX idx_circle_templates_circle_id ON circle_templates(circle_id);

-- ============================================
-- Circle Nudges
-- ============================================
CREATE TABLE IF NOT EXISTS circle_nudges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES auth.users(id),
    recipient_id UUID NOT NULL REFERENCES auth.users(id),
    nudge_type TEXT DEFAULT 'hug',
    message_preview TEXT NOT NULL,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT no_self_nudge CHECK (sender_id != recipient_id)
);

-- RLS
ALTER TABLE circle_nudges ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own nudges"
    ON circle_nudges FOR SELECT
    USING (auth.uid() = recipient_id OR auth.uid() = sender_id);

CREATE POLICY "Circle members can send nudges"
    ON circle_nudges FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_id = circle_nudges.circle_id
            AND user_id = auth.uid()
        )
        AND sender_id = auth.uid()
        AND sender_id != recipient_id
    );

CREATE POLICY "Users can update own nudges (mark read)"
    ON circle_nudges FOR UPDATE
    USING (auth.uid() = recipient_id);

-- Indexes
CREATE INDEX idx_circle_nudges_recipient ON circle_nudges(recipient_id, is_read);
CREATE INDEX idx_circle_nudges_circle ON circle_nudges(circle_id, created_at DESC);

-- ============================================
-- Circle Nudge Settings (opt-in controls)
-- ============================================
CREATE TABLE IF NOT EXISTS circle_nudge_settings (
    circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    can_send BOOLEAN DEFAULT true,
    can_receive BOOLEAN DEFAULT true,
    muted_until TIMESTAMPTZ,
    UNIQUE (circle_id, user_id)
);

-- RLS
ALTER TABLE circle_nudge_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own nudge settings"
    ON circle_nudge_settings FOR ALL
    USING (auth.uid() = user_id);

-- ============================================
-- Circle Recaps
-- ============================================
CREATE TABLE IF NOT EXISTS circle_recaps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
    week_start DATE NOT NULL,
    check_in_count INT NOT NULL DEFAULT 0,
    check_in_change INT NOT NULL DEFAULT 0,
    average_mood DECIMAL(3,2),
    mood_change DECIMAL(3,2),
    top_tags JSONB NOT NULL DEFAULT '[]'::jsonb,
    posted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (circle_id, week_start)
);

-- RLS
ALTER TABLE circle_recaps ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Circle members can view recaps"
    ON circle_recaps FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM circle_members
            WHERE circle_id = circle_recaps.circle_id
            AND user_id = auth.uid()
        )
    );

-- Index
CREATE INDEX idx_circle_recaps_circle_week ON circle_recaps(circle_id, week_start DESC);

-- ============================================
-- Updated_at triggers
-- ============================================
CREATE OR REPLACE FUNCTION update_weekly_wellbeing_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_weekly_wellbeing_updated_at
    BEFORE UPDATE ON weekly_wellbeing_checks
    FOR EACH ROW
    EXECUTE FUNCTION update_weekly_wellbeing_updated_at();

CREATE OR REPLACE FUNCTION update_circle_templates_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_circle_templates_updated_at
    BEFORE UPDATE ON circle_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_circle_templates_updated_at();
```

### API Contracts

**Edge Function:** `POST /functions/v1/weekly-check`

```typescript
// Request
interface WeeklyCheckRequest {
  week_start: string; // "2026-01-19"
  stress: number; // 0-10
  sleep_quality: number; // 0-10
  energy: number; // 0-10
  connection: number; // 0-10
  focus: number; // 0-10
  note?: string;
  tags?: string[];
}

// Response
interface WeeklyCheckResponse {
  success: boolean;
  data: {
    id: string;
    week_start: string;
    trend: {
      stress_change: number | null;
      energy_change: number | null;
      sleep_change: number | null;
      connection_change: number | null;
      focus_change: number | null;
    };
    insight: string;
    suggestion?: {
      type: "exercise";
      id: string;
      title: string;
    };
  };
  error?: {
    code: string;
    message: string;
  };
}
```

**Edge Function:** `POST /functions/v1/circle-templates`

```typescript
// Request
interface CircleTemplatesRequest {
  operation: "get" | "create" | "update" | "delete";
  circle_id: string;
  templates?: {
    id?: string;
    template_type: "win_worry_need" | "energy_sentence" | "gratitude_intention";
    is_active: boolean;
    display_order: number;
  }[];
}

// Response
interface CircleTemplatesResponse {
  success: boolean;
  templates: {
    id: string;
    template_type: string;
    is_active: boolean;
    display_order: number;
  }[];
}
```

**Edge Function:** `POST /functions/v1/circle-recap`

```typescript
// Request (cron-triggered, no body needed)
interface CircleRecapRequest {
  circle_id: string;
  week_start: string;
}

// Response
interface CircleRecapResponse {
  success: boolean;
  recap: {
    id: string;
    circle_id: string;
    week_start: string;
    check_in_count: number;
    check_in_change: number;
    average_mood: number;
    mood_change: number;
    top_tags: { tag: string; count: number }[];
  };
}
```

**Edge Function:** `POST /functions/v1/send-circle-nudge`

```typescript
// Request
interface SendCircleNudgeRequest {
  circle_id: string;
  recipient_id: string;
  nudge_type: "hug" | "thinking_of_you" | "miss_you";
}

// Response
interface SendCircleNudgeResponse {
  success: boolean;
  nudge_id: string;
  error?: {
    code: string;
    message: string;
  };
}
```

### Implementation Order

#### Phase 1: Weekly Wellbeing Check

1. Create database migration
2. Add wellbeing types to Models.swift
3. Create WeeklyCheckService
4. Create WeeklyCheckViewModel
5. Create WeeklyCheckCard for home
6. Create WeeklyCheckView
7. Create WellbeingTrendsView
8. Create weekly-check Edge Function
9. Add to HomeView
10. Write unit tests

#### Phase 2: Circle Templates

1. Create circle templates tables (already in migration)
2. Create circle-templates Edge Function
3. Create TemplateManagementView
4. Create CheckInTemplateSelector
5. Modify CircleDetailView for template selection
6. Modify CircleSettingsView for template management
7. Write unit tests

#### Phase 3: Circle Recaps

1. Create circle_recaps table (already in migration)
2. Create circle-recap Edge Function
3. Create CircleRecapView
4. Add recap delivery to cron job
5. Write unit tests

#### Phase 4: Circle Nudges

1. Create circle_nudges and nudge_settings tables (already in migration)
2. Create send-circle-nudge Edge Function
3. Create NudgeMemberSheet
4. Create NudgeSettingsView
5. Modify SendHugButton to include nudge options
6. Write unit tests

### Dependencies

- Existing Circles feature (circle_members, circles tables)
- Existing HomeView (for weekly check card placement)
- Existing Exercise library (for suggestions)
- Cron job infrastructure (for weekly recap delivery)

---

## Implementation Order Summary

### Phase 1: Foundation (Safety Plan)
1. Create safety plan migration
2. Create SafetyPlanService
3. Create SafetyPlanViewModel
4. Add SafetyPlan models to Core/Models.swift
5. Create manage-safety-plan Edge Function

### Phase 2: Safety Plan UI
6. Create SafetyPlanView and wizard components
7. Create CondensedSafetyPlanView
8. Integrate into CrisisResourcesView
9. Add to Home quick actions

### Phase 3: AI Coaching Modes
10. Create conversation_modes migration
11. Create ConversationModeService
12. Modify ChatView/ViewModel for mode selector
13. Create structured output views
14. Modify chat/index.ts for mode-aware AI
15. Create analyze-thought-record Edge Function

### Phase 4: Weekly Wellbeing
16. Create weekly wellbeing migration
17. Create WeeklyCheckService
18. Create WeeklyCheckViewModel
19. Create WeeklyCheckCard and WeeklyCheckView
20. Create wellbeing trends view
21. Create weekly-check Edge Function

### Phase 5: Circle Habits
22. Create circle templates migration (combined)
23. Create circle-templates Edge Function
24. Create template management UI
25. Create circle-recap Edge Function
26. Create send-circle-nudge Edge Function
27. Create nudge UI components

### Phase 6: Integration & Testing
28. Add all features to HomeView
29. Write comprehensive unit tests
30. Run integration tests
31. Update progress documentation

---

## Test Strategy

### iOS Unit Tests

| Test File | Coverage Target | Key Test Cases |
|-----------|-----------------|----------------|
| SafetyPlanTests.swift | 100% | Plan CRUD, validation, offline caching |
| CoachingModesTests.swift | 100% | Mode switching, structured output parsing |
| WeeklyCheckTests.swift | 100% | Check submission, trend calculation |
| CircleHabitTests.swift | 100% | Templates, nudges, settings |

### Edge Function Tests

| Test File | Coverage Target | Key Test Cases |
|-----------|-----------------|----------------|
| manage-safety-plan/test.ts | 100% | CRUD operations, validation, RLS |
| weekly-check/test.ts | 100% | Submission, duplicate detection, trends |
| circle-templates/test.ts | 100% | Template CRUD, admin-only operations |
| circle-recap/test.ts | 100% | Recap generation, empty states |
| send-circle-nudge/test.ts | 100% | Nudge sending, rate limiting, settings |

### Integration Tests

| Test File | Components | Test Scenarios |
|-----------|------------|----------------|
| SafetyPlanIntegrationTests.swift | iOS + Edge Function | End-to-end plan creation, offline sync |
| CoachingModesIntegrationTests.swift | iOS + Chat Function | Mode persistence, structured output |
| WeeklyCheckIntegrationTests.swift | iOS + Edge Function | Full check flow, trend display |
| CircleHabitIntegrationTests.swift | iOS + Multiple Functions | Template -> Check-in -> Recap flow |

### Edge Cases to Test

| Scenario | Expected Behavior | Test Type |
|----------|-------------------|-----------|
| Safety plan offline access | Condensed view loads from cache | Integration |
| Invalid E.164 phone format | Validation error | Unit |
| Max 3 trusted contacts | Alert prevents 4th | Unit |
| Empty input to Plan mode | Clarification prompt | Integration |
| Reframe with 2 completed fields | Save disabled | Unit |
| First weekly check (no prior data) | Null trends | Integration |
| Duplicate weekly check submission | 409 error | Unit |
| Nudge rate limit reached | 429 error | Unit |
| Non-admin tries to configure templates | 403 error | Unit |
| Crisis during structured mode | Crisis template overrides mode | Integration |

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking existing chat functionality | Medium | High | Feature flag for mode selector; test thoroughly |
| Safety plan offline encryption | Low | Critical | Use iOS Data Protection Complete |
| AI prompt injection via structured output | Low | High | Validate all structured output server-side |
| Performance regression from additional queries | Medium | Medium | Add database indexes; monitor query times |
| User confusion about modes | Medium | Medium | First-time tooltip; clear mode descriptions |
| Calendar edge cases (week start) | Low | Medium | Use UTC dates; test timezone handling |
| Circle nudge spam | Medium | Medium | Rate limiting per sender; opt-in defaults |

---

## Dependencies Between Features

```
Safety Plan
    |
    +-- Depends on: CrisisResourcesView (existing)
    +-- Depends on: Exercise library (existing)
    |
    v
AI Coaching Modes
    |
    +-- Depends on: Chat infrastructure (existing)
    +-- Depends on: Safety Plan (for allowAiReference feature)
    +-- Depends on: Quest system (for Plan mode scheduling)
    |
    v
Weekly Wellbeing + Circle Habits
    |
    +-- Depends on: Circles feature (existing)
    +-- Depends on: Exercise library (existing)
    +-- Depends on: HomeView (existing)
    |
    +-- No cross-dependencies with Safety Plan or AI Modes
```

---

## Rollback Plan

If issues are discovered post-deploy:

1. **Safety Plan:**
   - Feature flag: `SAFETY_PLAN_ENABLED=false`
   - Rollback migration not needed (RLS protects data)
   - No schema changes that break existing features

2. **AI Coaching Modes:**
   - Feature flag: `AI_MODES_ENABLED=false`
   - Chat function degrades to existing behavior
   - Database tables safe to leave in place

3. **Weekly Wellbeing + Circle Habits:**
   - Feature flags: `WEEKLY_CHECK_ENABLED=false`, `CIRCLE_HABITS_ENABLED=false`
   - No impact on existing circle functionality
   - Database tables safe to leave in place

---

## Questions for Clarification

1. **Safety Plan Exercise Linking:** Should the safety plan link to the existing exercise library or use a filtered subset?
2. **AI Mode Default:** Should Reflect mode be the default for all new conversations?
3. **Weekly Check Timing:** Is Sunday 6PM local time the correct trigger, or should we use a configurable time?
4. **Circle Template Default:** Should all circles have all 3 templates active by default?
5. **Nudge Notification:** Should nudges send push notifications, or just in-app notifications?

---

## Verdict

**READY FOR IMPLEMENTATION**

This plan provides a clear path to implement the three features with:

- Minimal risk to existing functionality (feature flags, RLS)
- Clear component boundaries
- Comprehensive test coverage
- Defined error handling
- Rollback capability
- Logical implementation order (Safety Plan first, then AI Modes, then Weekly/Circle)
