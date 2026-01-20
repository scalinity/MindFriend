# Boundary & Needs Planner - Formal Technical Specification

**Version:** 1.0
**Status:** Ready for Implementation
**Last Updated:** 2026-01-20

## 1. Overview

**Feature Name:** Boundary & Needs Planner
**Description:** Guided tool to help users clarify needs, define boundaries, and generate personalized scripts with practice prompts.
**Business Value:** Converts vague stress into concrete next steps, positioning MindFriend as a practical "life tool."

## 2. Database Schema

### 2.1 Tables

```sql
-- Needs Assessments
CREATE TABLE needs_assessments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    assessment_type TEXT NOT NULL CHECK (assessment_type IN ('work', 'relationships', 'family', 'friends')),
    responses JSONB NOT NULL,
    top_needs TEXT[],
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Defined Boundaries
CREATE TABLE defined_boundaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    needs_assessment_id UUID REFERENCES needs_assessments(id),
    boundary_type TEXT NOT NULL CHECK (boundary_type IN ('time', 'emotional', 'digital', 'physical', 'financial')),
    statement_text TEXT NOT NULL CHECK (char_length(statement_text) >= 10),
    why_matters TEXT,
    stakeholder TEXT,
    expected_impact TEXT,
    status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'ready', 'practiced', 'set', 'adjusted', 'archived')),
    scripts JSONB,
    practice_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Boundary Follow-Ups
CREATE TABLE boundary_follow_ups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    boundary_id UUID REFERENCES defined_boundaries(id) ON DELETE CASCADE NOT NULL,
    check_in_at TIMESTAMPTZ NOT NULL,
    outcome TEXT CHECK (outcome IN ('successful', 'partially_successful', 'challenged', 'ignored')),
    notes TEXT,
    user_reflection TEXT,
    next_action TEXT,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Script Templates
CREATE TABLE boundary_script_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    boundary_type TEXT NOT NULL,
    relationship_type TEXT NOT NULL,
    template_variation TEXT NOT NULL CHECK (template_variation IN ('direct', 'gentle', 'assertive', 'collaborative')),
    template_text TEXT NOT NULL,
    tone_description TEXT,
    example_context TEXT,
    locale TEXT NOT NULL DEFAULT 'en' CHECK (locale IN ('en', 'es', 'pt')),
    is_premium BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Indexes for Performance
CREATE INDEX idx_needs_assessments_user_created ON needs_assessments(user_id, created_at DESC);
CREATE INDEX idx_defined_boundaries_user_created ON defined_boundaries(user_id, created_at DESC);
CREATE INDEX idx_defined_boundaries_status ON defined_boundaries(user_id, status);
CREATE INDEX idx_boundary_follow_ups_boundary ON boundary_follow_ups(boundary_id);
CREATE INDEX idx_boundary_follow_ups_pending ON boundary_follow_ups(check_in_at) WHERE completed_at IS NULL;
CREATE INDEX idx_script_templates_lookup ON boundary_script_templates(boundary_type, relationship_type, locale);
CREATE INDEX idx_script_templates_premium ON boundary_script_templates(is_premium) WHERE is_premium = true;

-- Updated_at Triggers
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_needs_assessments_updated_at BEFORE UPDATE ON needs_assessments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_defined_boundaries_updated_at BEFORE UPDATE ON defined_boundaries
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
```

### 2.2 Row Level Security (RLS) Policies

```sql
-- Enable RLS
ALTER TABLE needs_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE defined_boundaries ENABLE ROW LEVEL SECURITY;
ALTER TABLE boundary_follow_ups ENABLE ROW LEVEL SECURITY;
ALTER TABLE boundary_script_templates ENABLE ROW LEVEL SECURITY;

-- needs_assessments policies
CREATE POLICY "Users can read own assessments"
    ON needs_assessments FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own assessments"
    ON needs_assessments FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own assessments"
    ON needs_assessments FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own assessments"
    ON needs_assessments FOR DELETE
    USING (auth.uid() = user_id);

-- defined_boundaries policies
CREATE POLICY "Users can read own boundaries"
    ON defined_boundaries FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own boundaries"
    ON defined_boundaries FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own boundaries"
    ON defined_boundaries FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own boundaries"
    ON defined_boundaries FOR DELETE
    USING (auth.uid() = user_id);

-- boundary_follow_ups policies
CREATE POLICY "Users can read follow-ups for own boundaries"
    ON boundary_follow_ups FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM defined_boundaries
        WHERE defined_boundaries.id = boundary_follow_ups.boundary_id
        AND defined_boundaries.user_id = auth.uid()
    ));

CREATE POLICY "Users can insert follow-ups for own boundaries"
    ON boundary_follow_ups FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM defined_boundaries
        WHERE defined_boundaries.id = boundary_follow_ups.boundary_id
        AND defined_boundaries.user_id = auth.uid()
    ));

CREATE POLICY "Users can update own boundary follow-ups"
    ON boundary_follow_ups FOR UPDATE
    USING (EXISTS (
        SELECT 1 FROM defined_boundaries
        WHERE defined_boundaries.id = boundary_follow_ups.boundary_id
        AND defined_boundaries.user_id = auth.uid()
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM defined_boundaries
        WHERE defined_boundaries.id = boundary_follow_ups.boundary_id
        AND defined_boundaries.user_id = auth.uid()
    ));

CREATE POLICY "Users can delete own boundary follow-ups"
    ON boundary_follow_ups FOR DELETE
    USING (EXISTS (
        SELECT 1 FROM defined_boundaries
        WHERE defined_boundaries.id = boundary_follow_ups.boundary_id
        AND defined_boundaries.user_id = auth.uid()
    ));

-- boundary_script_templates policies (read-only for all authenticated users)
CREATE POLICY "Authenticated users can read templates"
    ON boundary_script_templates FOR SELECT
    TO authenticated
    USING (true);
```

### 2.3 JSONB Schema Definitions

#### needs_assessments.responses

```json
{
  "step1_drain_triggers": ["string"],
  "step2_importance_ratings": {
    "personal_time": "high|medium|low",
    "emotional_safety": "high|medium|low",
    "respect": "high|medium|low",
    "autonomy": "high|medium|low"
  },
  "step3_currently_met": {
    "personal_time": "yes|no|sometimes",
    "emotional_safety": "yes|no|sometimes",
    "respect": "yes|no|sometimes",
    "autonomy": "yes|no|sometimes"
  },
  "step4_priority_needs": ["string"]
}
```

#### defined_boundaries.scripts

```json
[
  {
    "variation": "direct|gentle|assertive|collaborative",
    "text": "string",
    "tone_description": "string",
    "template_id": "uuid"
  }
]
```

## 3. API Endpoints

### 3.1 Create Assessment

**Endpoint:** `POST /functions/v1/create-assessment`
**Auth:** Required (JWT)

**Request:**

```json
{
  "assessmentType": "work|relationships|family|friends",
  "responses": {
    "step1_drain_triggers": ["string"],
    "step2_importance_ratings": {},
    "step3_currently_met": {},
    "step4_priority_needs": ["string"]
  }
}
```

**Response (200):**

```json
{
  "success": true,
  "assessmentId": "uuid",
  "topNeeds": ["string"],
  "recommendedBoundaries": [
    {
      "type": "time|emotional|digital|physical|financial",
      "suggestion": "string",
      "priority": "high|medium|low"
    }
  ]
}
```

**Business Logic:**

**Top Needs Calculation Algorithm:**

1. For each need key in `step2_importance_ratings`:
   - Calculate gap_score using matrix:
     ```
     importance="high"   + currently_met="no"        → gap_score=9
     importance="high"   + currently_met="sometimes" → gap_score=7
     importance="high"   + currently_met="yes"       → gap_score=3
     importance="medium" + currently_met="no"        → gap_score=6
     importance="medium" + currently_met="sometimes" → gap_score=4
     importance="medium" + currently_met="yes"       → gap_score=2
     importance="low"    + currently_met="no"        → gap_score=3
     importance="low"    + currently_met="sometimes" → gap_score=2
     importance="low"    + currently_met="yes"       → gap_score=1
     ```
2. Sort needs by gap_score DESC
3. Return top 3 needs (or all needs with gap_score >= 6)
4. Break ties alphabetically

**Recommended Boundaries Generation:**
Based on `assessment_type` and `top_needs`, suggest boundaries:

| Assessment Type | Top Need           | Boundary Type | Priority |
| --------------- | ------------------ | ------------- | -------- |
| work            | personal_time      | time          | high     |
| work            | autonomy           | emotional     | high     |
| work            | respect            | emotional     | medium   |
| relationships   | emotional_safety   | emotional     | high     |
| relationships   | respect            | emotional     | high     |
| relationships   | personal_space     | physical      | medium   |
| family          | personal_time      | time          | high     |
| family          | autonomy           | emotional     | high     |
| family          | boundaries         | physical      | medium   |
| friends         | personal_time      | time          | medium   |
| friends         | emotional_safety   | emotional     | high     |
| friends         | digital_boundaries | digital       | low      |

Return up to 3 recommendations, prioritized by: priority level → gap_score

**Errors:**

- 400: Invalid assessment_type or missing responses
- 401: Unauthorized
- 500: Database error

### 3.2 Generate Boundary

**Endpoint:** `POST /functions/v1/generate-boundary`
**Auth:** Required (JWT)

**Request:**

```json
{
  "assessmentId": "uuid", // optional
  "boundaryType": "time|emotional|digital|physical|financial",
  "statement": "string",
  "whyMatters": "string",
  "stakeholder": "string" // optional
}
```

**Response (200):**

```json
{
  "success": true,
  "boundary": {
    "id": "uuid",
    "type": "string",
    "statement": "string",
    "whyMatters": "string",
    "stakeholder": "string",
    "expectedImpact": "string",
    "status": "draft"
  },
  "nextSteps": ["string"]
}
```

**Validation:**

- statement: 10-500 characters
- whyMatters: 10-500 characters

**Errors:**

- 400: Validation failed
- 402: Free tier limit reached (3 boundaries max)
- 401: Unauthorized
- 500: Database error

### 3.3 Generate Scripts

**Endpoint:** `POST /functions/v1/generate-scripts`
**Auth:** Required (JWT)

**Request:**

```json
{
  "boundaryId": "uuid",
  "relationshipType": "manager|colleague|partner|parent|friend|other",
  "variations": ["direct", "gentle", "assertive", "collaborative"]
}
```

**Response (200):**

```json
{
  "success": true,
  "scripts": [
    {
      "variation": "direct",
      "script": "string",
      "toneDescription": "string",
      "tips": ["string"]
    }
  ],
  "practicePrompts": ["string"]
}
```

**Business Logic:**

1. Fetch boundary from database
2. Query `boundary_script_templates` for matches:
   - WHERE boundary_type = boundary.boundary_type
   - AND relationship_type = request.relationshipType
   - AND locale = user.locale (default 'en')
   - AND (is_premium = false OR user.subscription_tier = 'premium')
3. For each variation requested:
   - Find template with matching variation
   - If not found, fallback to relationship_type = 'other'
   - Replace placeholders using placeholder specification (see below)
4. Update boundary.scripts JSONB
5. Return generated scripts

**Placeholder Specification:**

| Placeholder        | Source                            | Required | Fallback Value                |
| ------------------ | --------------------------------- | -------- | ----------------------------- |
| `[boundary]`       | `statement_text`                  | Yes      | (error if missing)            |
| `[why_matters]`    | `why_matters`                     | No       | "maintain healthy boundaries" |
| `[stakeholder]`    | `stakeholder`                     | No       | "the other person"            |
| `[contact_method]` | `user_settings.preferred_contact` | No       | "text message"                |

**Placeholder Replacement Algorithm:**

1. For each placeholder in template_text
2. Lookup value from source column
3. If value is null/empty and required = Yes: return 500 error "Template requires missing field"
4. If value is null/empty and required = No: use fallback value
5. Replace `[placeholder]` with actual value

**Errors:**

- 400: Invalid boundaryId or relationshipType
- 404: Boundary not found
- 401: Unauthorized
- 500: Template not found or database error

### 3.4 Save Boundary

**Endpoint:** `POST /functions/v1/save-boundary`
**Auth:** Required (JWT)

**Request:**

```json
{
  "boundaryId": "uuid",
  "status": "draft|ready|practiced|set|adjusted|archived"
}
```

**Response (200):**

```json
{
  "success": true,
  "boundary": {
    "id": "uuid",
    "status": "string",
    "updatedAt": "ISO8601"
  }
}
```

**State Transitions:**

- draft → ready (when scripts generated)
- ready → practiced (when practice_count >= 3)
- practiced → set (user marks as set)
- set → adjusted (user edits boundary)
- any → archived (user deletes)

**Enforcement Mechanism:**

State transitions are validated in the Edge Function (NOT database constraint) to allow flexible business logic.

**Validation Logic:**

```typescript
function validateTransition(
  currentStatus: string,
  newStatus: string,
  boundary: Boundary,
): boolean {
  // Allow archiving from any state
  if (newStatus === "archived") return true;

  // Draft → Ready: requires scripts
  if (currentStatus === "draft" && newStatus === "ready") {
    return boundary.scripts !== null && boundary.scripts.length > 0;
  }

  // Ready → Practiced: requires practice_count >= 3
  if (currentStatus === "ready" && newStatus === "practiced") {
    return boundary.practice_count >= 3;
  }

  // Practiced → Set: always allowed (user action)
  if (currentStatus === "practiced" && newStatus === "set") {
    return true;
  }

  // Set → Adjusted: always allowed (user edits)
  if (currentStatus === "set" && newStatus === "adjusted") {
    return true;
  }

  // Adjusted → Set: always allowed (user re-sets)
  if (currentStatus === "adjusted" && newStatus === "set") {
    return true;
  }

  // All other transitions are invalid
  return false;
}
```

If validation fails, return 400 error:

```json
{
  "error": "Invalid state transition",
  "current": "draft",
  "requested": "set",
  "allowed": ["ready", "archived"],
  "reason": "Scripts must be generated before marking as ready"
}
```

**Errors:**

- 400: Invalid status transition (see validation logic above)
- 404: Boundary not found
- 401: Unauthorized
- 500: Database error

### 3.5 List Boundaries

**Endpoint:** `GET /functions/v1/list-boundaries?status=all&limit=20&offset=0`
**Auth:** Required (JWT)

**Response (200):**

```json
{
  "success": true,
  "boundaries": [
    {
      "id": "uuid",
      "boundaryType": "string",
      "statementText": "string",
      "status": "string",
      "practiceCount": 0,
      "createdAt": "ISO8601",
      "updatedAt": "ISO8601",
      "hasFollowUp": false
    }
  ],
  "total": 0,
  "limit": 20,
  "offset": 0
}
```

**Errors:**

- 401: Unauthorized
- 500: Database error

### 3.6 Schedule Follow-Up

**Endpoint:** `POST /functions/v1/schedule-followup`
**Auth:** Required (JWT)

**Request:**

```json
{
  "boundaryId": "uuid",
  "checkInAt": "ISO8601" // default: +24 hours from now
}
```

**Response (200):**

```json
{
  "success": true,
  "followUpId": "uuid",
  "reminderSet": true
}
```

**Business Logic:**

1. Insert into boundary_follow_ups
2. Schedule local notification for check_in_at time

**Errors:**

- 400: Invalid checkInAt (must be future)
- 404: Boundary not found
- 401: Unauthorized
- 500: Database error

### 3.7 Record Outcome

**Endpoint:** `POST /functions/v1/record-outcome`
**Auth:** Required (JWT)

**Request:**

```json
{
  "followUpId": "uuid",
  "outcome": "successful|partially_successful|challenged|ignored",
  "notes": "string", // optional
  "reflection": "string", // optional
  "nextAction": "string" // optional
}
```

**Response (200):**

```json
{
  "success": true,
  "boundaryUpdated": {
    "id": "uuid",
    "status": "set|adjusted"
  },
  "encouragement": "string",
  "suggestions": ["string"]
}
```

**Business Logic:**

1. Update follow-up with outcome and completed_at
2. If outcome = 'successful' or 'partially_successful': status remains 'set'
3. If outcome = 'challenged' or 'ignored': suggest adjusting boundary
4. Generate encouragement message based on outcome

**Errors:**

- 404: Follow-up not found
- 401: Unauthorized
- 500: Database error

### 3.8 Get Assessment

**Endpoint:** `GET /functions/v1/get-assessment/:assessmentId`
**Auth:** Required (JWT)

**Response (200):**

```json
{
  "success": true,
  "assessment": {
    "id": "uuid",
    "assessmentType": "string",
    "responses": {},
    "topNeeds": ["string"],
    "createdAt": "ISO8601"
  }
}
```

**Errors:**

- 404: Assessment not found
- 401: Unauthorized
- 500: Database error

### 3.9 Get Templates

**Endpoint:** `GET /functions/v1/get-templates?boundaryType=time&relationshipType=manager&locale=en`
**Auth:** Required (JWT)

**Response (200):**

```json
{
  "success": true,
  "templates": [
    {
      "id": "uuid",
      "variation": "direct",
      "templateText": "string",
      "toneDescription": "string",
      "exampleContext": "string",
      "isPremium": false
    }
  ]
}
```

**Errors:**

- 401: Unauthorized
- 500: Database error

## 4. iOS Implementation

### 4.1 Views Required

| View                           | Purpose                                    |
| ------------------------------ | ------------------------------------------ |
| `NeedsAssessmentView.swift`    | Multi-step guided questionnaire            |
| `PriorityMatrixView.swift`     | Visual needs prioritization (display-only) |
| `BoundaryDefinitionView.swift` | Boundary statement builder                 |
| `ScriptGeneratorView.swift`    | Template selection and customization       |
| `BoundaryPracticeView.swift`   | Integration with Conversation Rehearsal    |
| `BoundaryFollowUpView.swift`   | Check-in and outcome recording             |
| `BoundariesListView.swift`     | List all boundaries with filters           |

### 4.2 Models

```swift
struct NeedsAssessment: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let assessmentType: AssessmentType
    let responses: AssessmentResponses
    let topNeeds: [String]
    let createdAt: Date
    let updatedAt: Date
}

enum AssessmentType: String, Codable {
    case work, relationships, family, friends
}

struct AssessmentResponses: Codable {
    let step1DrainTriggers: [String]
    let step2ImportanceRatings: [String: ImportanceLevel]
    let step3CurrentlyMet: [String: MetLevel]
    let step4PriorityNeeds: [String]
}

struct DefinedBoundary: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let needsAssessmentId: UUID?
    let boundaryType: BoundaryType
    let statementText: String
    let whyMatters: String?
    let stakeholder: String?
    let expectedImpact: String?
    var status: BoundaryStatus
    let scripts: [BoundaryScript]?
    let practiceCount: Int
    let createdAt: Date
    let updatedAt: Date
}

enum BoundaryType: String, Codable, CaseIterable {
    case time, emotional, digital, physical, financial
}

enum BoundaryStatus: String, Codable {
    case draft, ready, practiced, set, adjusted, archived
}

struct BoundaryScript: Codable {
    let variation: ScriptVariation
    let text: String
    let toneDescription: String
    let templateId: UUID?
}

enum ScriptVariation: String, Codable {
    case direct, gentle, assertive, collaborative
}

struct BoundaryFollowUp: Codable, Identifiable {
    let id: UUID
    let boundaryId: UUID
    let checkInAt: Date
    var outcome: FollowUpOutcome?
    var notes: String?
    var userReflection: String?
    var nextAction: String?
    var completedAt: Date?
    let createdAt: Date
}

enum FollowUpOutcome: String, Codable {
    case successful, partiallySuccessful, challenged, ignored
}
```

### 4.3 Conversation Rehearsal Integration

**Integration Approach:** Loose coupling via custom scenario creation

**Flow:**

1. User taps "Practice" on a boundary script
2. iOS app creates `CustomScenario` object:
   ```swift
   struct CustomScenario {
       let title: String  // "Practice: [boundary type]"
       let context: String  // boundary.statementText
       let userRole: String  // "You (setting boundary)"
       let otherRole: String  // boundary.stakeholder or "The other person"
       let script: String  // selected script.text
       let sourceFeature: String  // "boundary_planner"
       let sourceId: UUID  // boundary.id
   }
   ```
3. Navigate to `ConversationRehearsalView(scenario: customScenario)`
4. Rehearsal view uses AI to simulate stakeholder response
5. On dismiss, callback increments boundary.practice_count
6. If practice_count >= 3, status transitions draft → practiced

**Data Model Addition:**

```sql
-- Add to existing custom_scenarios table
ALTER TABLE custom_scenarios
ADD COLUMN IF NOT EXISTS source_feature TEXT,
ADD COLUMN IF NOT EXISTS source_id UUID;

CREATE INDEX idx_custom_scenarios_source ON custom_scenarios(source_feature, source_id);
```

**Practice Count Synchronization:**

**Source of Truth:** `defined_boundaries.practice_count` column (persisted, indexed)

**Synchronization Mechanism:** Database trigger on `custom_scenarios` table

```sql
-- Trigger function to increment practice count
CREATE OR REPLACE FUNCTION increment_boundary_practice_count()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.source_feature = 'boundary_planner' THEN
        UPDATE defined_boundaries
        SET practice_count = practice_count + 1,
            updated_at = NOW()
        WHERE id = NEW.source_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger on custom_scenarios INSERT
CREATE TRIGGER sync_boundary_practice_count
AFTER INSERT ON custom_scenarios
FOR EACH ROW
WHEN (NEW.source_feature = 'boundary_planner')
EXECUTE FUNCTION increment_boundary_practice_count();
```

**iOS Query (Reading):**

```swift
// Simple read from defined_boundaries.practice_count column
let boundary = try await supabase
    .from("defined_boundaries")
    .select()
    .eq("id", boundaryId)
    .single()
    .execute()
    .value

let practiceCount = boundary.practiceCount  // Already incremented by trigger
```

**Status Transition Logic:**

When `practice_count >= 3` and current status is `ready`, Edge Function `/save-boundary` automatically transitions to `practiced` status.

## 5. Localization

### 5.1 LocalizedStringKey Identifiers

**Navigation & Titles (3 strings)**

- `boundary_planner.title` = "Boundary Planner"
- `boundary_planner.subtitle` = "Define clear boundaries and practice conversations"
- `boundary_planner.tab_title` = "Boundaries"

**Assessment Flow (14 strings)**

- `assessment.title` = "What Do You Need?"
- `assessment.step_indicator` = "Step %d of 4"
- `assessment.step1.title` = "Reflect on this question:"
- `assessment.step1.question` = "When do you feel most drained in your relationships?"
- `assessment.step1.option_cant_say_no` = "When I can't say no"
- `assessment.step1.option_boundaries_ignored` = "When my boundaries are ignored"
- `assessment.step1.option_unappreciated` = "When I feel unappreciated"
- `assessment.step1.option_conflict` = "When there's too much conflict"
- `assessment.step1.option_other` = "Other:"
- `assessment.step2.title` = "Rate Importance"
- `assessment.step3.title` = "Currently Met?"
- `assessment.step4.title` = "Priority Needs"
- `assessment.button_back` = "Back"
- `assessment.button_next` = "Next"

**Priority Matrix (8 strings)**

- `matrix.title` = "Your Priority Matrix"
- `matrix.subtitle` = "Which needs are most important to you? Which needs are currently not being met?"
- `matrix.axis_importance` = "Importance"
- `matrix.axis_currently_met` = "Currently Met"
- `matrix.label_not_important` = "Not Important"
- `matrix.label_important` = "Important"
- `matrix.label_met` = "Met"
- `matrix.label_unmet` = "Unmet"

**Boundary Definition (15 strings)**

- `definition.title` = "Define Your Boundary"
- `definition.type_label` = "Boundary Type:"
- `definition.type_time` = "Time"
- `definition.type_emotional` = "Emotional"
- `definition.type_digital` = "Digital"
- `definition.type_physical` = "Physical"
- `definition.type_financial` = "Financial"
- `definition.type_other` = "Other"
- `definition.statement_label` = "My boundary is:"
- `definition.statement_placeholder` = "I need to..."
- `definition.why_label` = "Why this matters to me:"
- `definition.why_placeholder` = "This is important because..."
- `definition.stakeholder_label` = "Who does this affect?"
- `definition.stakeholder_placeholder` = "e.g., My manager"
- `definition.button_continue` = "Continue"

**Scripts (11 strings)**

- `scripts.title` = "Your Boundary Scripts"
- `scripts.subtitle_for` = "For: \"%@\""
- `scripts.variation_direct` = "Direct"
- `scripts.variation_gentle` = "Gentle"
- `scripts.variation_assertive` = "Assertive"
- `scripts.variation_collaborative` = "Collaborative"
- `scripts.button_copy` = "Copy"
- `scripts.button_practice` = "Practice"
- `scripts.button_edit` = "Edit"
- `scripts.button_generate_more` = "Generate More Variations"
- `scripts.practice_prompt_prefix` = "Practice saying:"

**Status (6 strings)**

- `status.draft` = "Draft"
- `status.ready` = "Ready"
- `status.practiced` = "Practiced"
- `status.set` = "Set"
- `status.adjusted` = "Adjusted"
- `status.archived` = "Archived"

**Follow-Up (8 strings)**

- `followup.title` = "Boundary Check-In"
- `followup.set_ago` = "Set %@ ago"
- `followup.question` = "How did it go?"
- `followup.outcome_success` = "Success"
- `followup.outcome_partial` = "Partial"
- `followup.outcome_needs_work` = "Needs Work"
- `followup.notes_label` = "Notes"
- `followup.next_step_label` = "Next Step"

**List & Actions (7 strings)**

- `list.title` = "My Boundaries"
- `list.filter_all` = "All"
- `list.filter_active` = "Active"
- `list.empty_state` = "No boundaries yet. Start by creating your first boundary."
- `list.button_new` = "New Boundary"
- `list.practice_count` = "Practiced %d times"
- `list.has_followup` = "Check-in scheduled"

**Errors (3 strings)**

- `error.free_tier_limit` = "You've reached the free tier limit of 3 boundaries. Upgrade to Premium for unlimited boundaries."
- `error.generation_failed` = "We couldn't generate scripts right now. Try selecting a template manually."
- `error.network_error` = "Please check your connection and try again."

**Total: 75 LocalizedStringKey identifiers**

### 5.2 Template Localization

Script templates in `boundary_script_templates` table must exist for each supported locale:

- English (en): 45 templates (15 types × 3 variations)
- Spanish (es): 45 templates
- Portuguese (pt): 45 templates

**Total seed data: 135 template records**

## 6. State Machine

### 6.1 Boundary Status Transitions

```
draft → ready → practiced → set → adjusted
  ↓                                    ↓
archived ←──────────────────────────────
```

**Transition Rules:**

| From      | To        | Trigger             | Validation             |
| --------- | --------- | ------------------- | ---------------------- |
| draft     | ready     | Scripts generated   | scripts JSONB not null |
| ready     | practiced | Practice count >= 3 | practice_count >= 3    |
| practiced | set       | User marks set      | User action            |
| set       | adjusted  | User edits boundary | statement_text changed |
| adjusted  | set       | User re-sets        | User action            |
| any       | archived  | User deletes        | User action            |

**No backward transitions allowed** (except adjusted → set).

## 7. Edge Cases & Error Handling

| Scenario                                       | Handling                                            |
| ---------------------------------------------- | --------------------------------------------------- |
| Assessment abandoned mid-way                   | Save progress in responses JSONB; resume option     |
| Script generation fails                        | Fallback to manual template selection from library  |
| Boundary statement too vague (< 10 chars)      | Validation error with examples                      |
| User reports violation (outcome='ignored')     | Offer crisis resources; suggest reflection exercise |
| Follow-up missed                               | Gentle reminder notification; reschedule option     |
| Free tier limit (3 boundaries)                 | Show paywall with upgrade CTA                       |
| Network error during save                      | Local cache; retry on reconnect                     |
| Template not found for locale                  | Fallback to 'en' templates                          |
| User deletes boundary with scheduled follow-up | Cascade delete follow-up; cancel notification       |

## 8. Testing Requirements

### 8.1 Unit Tests

- Assessment scoring logic (top_needs calculation)
- Script template matching algorithm
- Follow-up scheduling logic
- Boundary status state machine transitions
- RLS policy enforcement (user can't access other users' data)

### 8.2 Integration Tests

- End-to-end boundary creation flow
- Conversation Rehearsal integration (practice count increment)
- Local notification scheduling and delivery
- Tier limit enforcement (free vs premium)
- Multi-locale template retrieval

### 8.3 Success Criteria (from original spec)

| Metric                   | Target | Measurement                         |
| ------------------------ | ------ | ----------------------------------- |
| Boundary completion rate | 60%    | Completed assessments / started     |
| Script usage rate        | 50%    | Boundaries with scripts / total     |
| Practice conversion      | 30%    | Practice sessions / scripts         |
| Follow-up completion     | 70%    | Completed follow-ups / scheduled    |
| Boundary success rate    | 60%    | "Successful" outcomes / responses   |
| Return rate              | 40%    | Multi-boundary users / unique users |

## 9. Implementation Checklist

**Phase 1: Database & Backend (Est: 4-6 hours)**

- [ ] Create migration with 4 tables, RLS policies, indexes, triggers
- [ ] Seed boundary_script_templates with 45 English templates
- [ ] Implement 9 Edge Functions with request validation
- [ ] Add script template matching algorithm
- [ ] Add tier limit check (3 boundaries for free tier)

**Phase 2: iOS Core Views (Est: 8-10 hours)**

- [ ] Implement NeedsAssessmentView with 4-step flow
- [ ] Implement PriorityMatrixView (display-only)
- [ ] Implement BoundaryDefinitionView with validation
- [ ] Implement ScriptGeneratorView with template selection
- [ ] Implement BoundariesListView with filters

**Phase 3: Integration & Advanced (Est: 4-6 hours)**

- [ ] Integrate Conversation Rehearsal (custom scenarios)
- [ ] Implement practice count tracking
- [ ] Implement BoundaryFollowUpView
- [ ] Add local notification scheduling
- [ ] Implement tier limit paywall

**Phase 4: Localization (Est: 3-4 hours)**

- [ ] Add 75 LocalizedStringKey strings to Localizable.xcstrings
- [ ] Translate to Spanish and Portuguese
- [ ] Seed Spanish and Portuguese script templates (90 additional records)
- [ ] Test locale switching

**Phase 5: Testing & Polish (Est: 3-4 hours)**

- [ ] Write unit tests for state machine and business logic
- [ ] Write integration tests for end-to-end flows
- [ ] Manual UAT testing
- [ ] Accessibility audit (VoiceOver, Dynamic Type)
- [ ] Performance testing (< 300ms endpoint latency)

**Total Estimated Effort: 22-30 hours**

---

## Appendix: Seed Data Examples

### Sample Script Template (English - Direct - Time Boundary)

```sql
INSERT INTO boundary_script_templates (
    boundary_type,
    relationship_type,
    template_variation,
    template_text,
    tone_description,
    example_context,
    locale,
    is_premium
) VALUES (
    'time',
    'manager',
    'direct',
    'I appreciate the work we do together, but I need to [boundary] so I can [why_matters]. If something urgent comes up, you can reach me via [contact_method] and I'll address it the next morning.',
    'Clear and professional while maintaining warmth',
    'Setting work-life boundaries with a supervisor',
    'en',
    false
);
```

### Sample Assessment Response

```json
{
  "step1_drain_triggers": [
    "When I can't say no",
    "When my boundaries are ignored"
  ],
  "step2_importance_ratings": {
    "personal_time": "high",
    "emotional_safety": "high",
    "respect": "medium",
    "autonomy": "high"
  },
  "step3_currently_met": {
    "personal_time": "no",
    "emotional_safety": "sometimes",
    "respect": "yes",
    "autonomy": "no"
  },
  "step4_priority_needs": ["personal_time", "autonomy", "emotional_safety"]
}
```

---

**END OF FORMAL SPECIFICATION**

**Status:** READY FOR IMPLEMENTATION
**Next Step:** Deploy architect agent for implementation plan
