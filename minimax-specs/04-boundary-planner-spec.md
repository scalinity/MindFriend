# Boundary & Needs Planner

**Priority:** #4 (Implementation Roadmap)
**Scores:** Delight 8/10 | Differentiation 7/10 | Feasibility High | Revenue Medium

## Step 1: Feature Analysis

### Core purpose and value proposition
- Transform vague discomfort about boundaries into concrete, actionable plans.
- Guide users through identifying needs, drafting boundary statements, and practicing conversations.
- Provide practical "life tool" functionality beyond emotional support.

### Target users and use cases
- Users who struggle to say no or set limits with others.
- Users in difficult relationships (work, family, friendships) who need scripts.
- Users who know they need boundaries but don't know how to articulate them.

### Dependencies / prerequisites
- Conversation Rehearsal Studio integration (for practice).
- User profile with relationship context (optional).
- Exercise library for follow-up activities.

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Boundary & Needs Planner
- **Description:** A guided tool that helps users clarify their needs, define boundaries, and generate personalized scripts for difficult conversations. Includes practice prompts and follow-up activities to reinforce boundary-setting skills.
- **Business justification and user value:** Practical utility that converts vague stress into concrete next steps. Positions MindFriend as a "life tool," not just emotional support.

### 2. Functional Requirements

#### FR1: Needs Assessment
- User stories:
  - As a user, I want to explore what I actually need in a situation.
  - As a user, I want to identify which needs aren't being met.
- Acceptance criteria:
  - Guided questionnaire exploring: physical needs, emotional needs, time needs, relationship needs.
  - Visual priority matrix: "Most important to me" vs "Currently unmet."
  - Reflection prompts: "When did I feel most respected?"
  - Ability to save assessment results.

#### FR2: Boundary Definition
- User stories:
  - As a user, I want to clearly define what my boundary is.
  - As a user, I want to understand why this boundary matters to me.
- Acceptance criteria:
  - Boundary type selection: time boundaries, emotional boundaries, digital boundaries, physical boundaries, financial boundaries.
  - "My boundary is..." statement builder with examples.
  - "Why this matters to me" reflection.
  - Stakeholder identification: Who does this boundary affect?
  - Impact assessment: How might this change things?

#### FR3: Script Generation
- User stories:
  - As a user, I want ready-to-use phrases for setting boundaries.
  - As a user, I want scripts that feel authentic to my voice.
- Acceptance criteria:
  - Template library organized by scenario type.
  - Input fields for customization: relationship type, situation, desired outcome.
  - Multiple variations: direct, gentle, assertive.
  - "Make it mine" editing with suggestions.
  - Audio option for hearing the script read aloud.

#### FR4: Practice Mode
- User stories:
  - As a user, I want to practice saying my boundary out loud.
  - As a user, I want feedback on how my boundary sounds.
- Acceptance criteria:
  - Integration with Conversation Rehearsal Studio.
  - Solo practice mode: Repeat script with voice recording.
  - "Does this feel right?" self-assessment after practice.
  - Export script to Notes or share with trusted person.

#### FR5: Follow-Up Activities
- User stories:
  - As a user, I want reminders to check in after setting a boundary.
  - As a user, I want activities that reinforce my boundary-setting skills.
- Acceptance criteria:
  - 24-hour follow-up check-in: "How did it go?"
  - Celebration prompt for successful boundaries.
  - "Next step" suggestions if boundary wasn't respected.
  - Skill-building exercises for common challenges.

### 3. Technical Specifications

#### Architecture and system design considerations
- Guided flow with state persistence.
- Template system for script generation.
- Integration with existing rehearsal functionality.
- Calendar integration for follow-up reminders.

#### Data models and schemas (proposed)

```sql
-- Needs assessments
CREATE TABLE needs_assessments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    assessment_type TEXT NOT NULL,  -- 'work', 'relationships', 'family', 'friends'
    responses JSONB NOT NULL,  -- Full assessment responses
    top_needs TEXT[],  -- Priority needs identified
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Defined boundaries
CREATE TABLE defined_boundaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    needs_assessment_id UUID REFERENCES needs_assessments(id),
    boundary_type TEXT NOT NULL,  -- 'time', 'emotional', 'digital', 'physical', 'financial'
    statement_text TEXT NOT NULL,
    why_matters TEXT,
    stakeholder TEXT,  -- 'partner', 'parent', 'friend', 'colleague', etc.
    expected_impact TEXT,
    status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'ready', 'practiced', 'set', 'adjusted')),
    scripts JSONB,  -- Generated script variations
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Boundary follow-ups
CREATE TABLE boundary_follow_ups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    boundary_id UUID REFERENCES defined_boundaries(id) ON DELETE CASCADE,
    check_in_at TIMESTAMPTZ NOT NULL,
    outcome TEXT,  -- 'successful', 'partially_successful', 'challenged', 'ignored'
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
    template_variation TEXT NOT NULL,  -- 'direct', 'gentle', 'assertive', 'collaborative'
    template_text TEXT NOT NULL,
    tone_description TEXT,
    example_context TEXT
);
```

#### API endpoints / interfaces

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/functions/v1/create-assessment` | POST | Start new needs assessment |
| `/functions/v1/get-assessment` | GET | Retrieve assessment results |
| `/functions/v1/generate-boundary` | POST | Generate boundary statement |
| `/functions/v1/generate-scripts` | POST | Generate script variations |
| `/functions/v1/save-boundary` | POST | Save defined boundary |
| `/functions/v1/list-boundaries` | GET | List all user's boundaries |
| `/functions/v1/schedule-followup` | POST | Schedule follow-up check-in |
| `/functions/v1/record-outcome` | POST | Record boundary outcome |
| `/functions/v1/get-templates` | GET | Retrieve script templates |

#### Integration points with existing systems
- **Conversation Rehearsal:** Practice boundary scripts.
- **Calendar:** Schedule follow-up reminders.
- **Exercises:** Follow-up skill-building activities.
- **Chat:** Reference boundaries in conversation.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions

**Needs Assessment Flow**
```
┌─────────────────────────────────────────────────┐
│  What Do You Need?                              │
│  Step 1 of 4                                    │
├─────────────────────────────────────────────────┤
│                                                 │
│  💭 Reflect on this question:                   │
│                                                 │
│  "When do you feel most drained in your        │
│   relationships?"                              │
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │ ○ When I can't say no                      ││
│  │ ○ When my boundaries are ignored           ││
│  │ ○ When I feel unappreciated                ││
│  │ ○ When there's too much conflict           ││
│  │ ○ Other: [____________]                    ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  [← Back]                    [Next →]          │
└─────────────────────────────────────────────────┘
```

**Priority Matrix**
```
┌─────────────────────────────────────────────────┐
│  Your Priority Matrix                           │
├─────────────────────────────────────────────────┤
│                                                 │
│  Which needs are most important to you?        │
│  Which needs are currently not being met?      │
│                                                 │
│       Not Important      Important             │
│           ┌───────────────────┐                │
│           │                   │                │
│    ┌──────│───────┬───────────┤                │
│    │      │       │           │                │
│    │  1   │   2   │     3     │   ← Currently  │
│    │      │       │           │     Met        │
│    ├──────┼───────┼───────────┤                │
│    │      │       │           │                │
│    │  4   │   5   │     6     │   ← Unmet      │
│    │      │       │           │                │
│    └──────┴───────┴───────────┘                │
│           │                                   │
│           │                                   │
│      Currently Met                         Important│
│                                                 │
│  Tap areas to explore needs in each quadrant.  │
└─────────────────────────────────────────────────┘
```

**Boundary Definition**
```
┌─────────────────────────────────────────────────┐
│  Define Your Boundary                           │
├─────────────────────────────────────────────────┤
│                                                 │
│  Boundary Type:                                 │
│  ┌─────────────────────────────────────────┐   │
│  │ [Time] [Emotional] [Digital] [Physical] │   │
│  │        [Financial] [Other]              │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  My boundary is:                                │
│  ┌─────────────────────────────────────────────┐│
│  │                                             ││
│  │  [I need to stop working at 6pm every day  ││
│  │   so I can be present for dinner with my   ││
│  │   family.]                                 ││
│  │                                             ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  Why this matters to me:                        │
│  ┌─────────────────────────────────────────────┐│
│  │ [My mental health improves when I have    ││
│  │  time to recharge.]                       ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  Who does this affect?                          │
│  ┌─────────────────────────────────────────┐   │
│  │ [My manager]                             │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│                         [Continue →]           │
└─────────────────────────────────────────────────┘
```

**Script Generation**
```
┌─────────────────────────────────────────────────┐
│  Your Boundary Scripts                          │
├─────────────────────────────────────────────────┤
│  For: "I need to stop working at 6pm"          │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ 💬 Direct                                 │ │
│  │                                           │ │
│  │ "I appreciate the work we do together,   │ │
│  │  but I'm going to stop taking calls after│ │
│  │  6pm so I can be present with my family. │ │
│  │  If something urgent comes up, you can   │ │
│  │  text me and I'll address it the next    │ │
│  │  morning."                               │ │
│  │                                           │ │
│  │  [Copy]  [Practice]  [Edit]              │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │ 💬 Collaborative                          │ │
│  │                                           │ │
│  │ "I want to be effective in my role while │ │
│  │  also maintaining balance.Can we agree   │ │
│  │  that 6pm is my cutoff time, unless it's │ │
│  │  a true emergency?"                      │ │
│  │                                           │ │
│  │  [Copy]  [Practice]  [Edit]              │ │
│  └───────────────────────────────────────────┘ │
│                                                 │
│  [Generate More Variations]                     │
└─────────────────────────────────────────────────┘
```

**Follow-Up Dashboard**
```
┌─────────────────────────────────────────────────┐
│  Boundary Check-In                              │
├─────────────────────────────────────────────────┤
│                                                 │
│  "I need to stop working at 6pm"                │
│  Set 2 days ago                                 │
│                                                 │
│  How did it go?                                 │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐           │
│  │  ✅     │ │  ⚠️     │ │  ❌     │           │
│  │ Success │ │Partial  │ │Needs    │           │
│  └─────────┘ └─────────┘ └─────────┘           │
│                                                 │
│  ┌─────────────────────────────────────────────┐│
│  │ 📝 Notes                                   ││
│  │ "My manager was understanding. We had a   ││
│  │  quick check-in about expectations."      ││
│  └─────────────────────────────────────────────┘│
│                                                 │
│  🎯 Next Step                                  │
│  "Ask for a follow-up meeting next week to    │
│   discuss how the new boundary is working."    │
│                                                 │
│  [Complete Check-In]  [Adjust Boundary]        │
└─────────────────────────────────────────────────┘
```

#### User flow diagram (text)

1. **First-time user:**
   - Launches planner → Selects assessment type → Completes needs exploration → Identifies priority → Defines boundary → Generates scripts → Practices → Saves.

2. **Returning user:**
   - Opens planner → Views existing boundaries → Adds new boundary or updates existing → Practices → Sets follow-up.

3. **After boundary setting:**
   - Receives notification for follow-up → Checks in on outcome → Adjusts or celebrates → Tracks progress over time.

#### Accessibility requirements
- All text inputs support VoiceOver.
- Clear focus states for all interactive elements.
- Sufficient touch targets (44x44pt minimum).
- Haptic feedback for milestone completion.

### 5. Edge Cases and Error Handling

| Scenario | Handling |
|----------|----------|
| User abandons assessment midway | Save progress; resume later option |
| Script generation fails | Fallback to manual template selection |
| Boundary too vague | Prompt for clarification with examples |
| User reports boundary violation | Offer crisis resources; suggest reflection |
| Follow-up missed | Gentle reminder; reschedule option |

### 6. Testing Requirements

#### Unit tests
- Assessment scoring logic.
- Script template population.
- Follow-up scheduling logic.
- Boundary status state transitions.

#### Integration tests
- End-to-end boundary creation flow.
- Rehearsal integration.
- Calendar reminder delivery.
- Analytics tracking.

#### UAT scenarios
- Complete needs assessment → Define boundary → Generate scripts.
- Practice script → Feel confident → Set follow-up.
- Miss follow-up → Receive reminder → Complete check-in.
- Mark boundary as successful → Celebrate → Track progress.

### 7. Implementation Notes

#### Suggested implementation approach
- **Phase 1:** Needs assessment + basic boundary definition + script templates.
- **Phase 2:** Script generation + practice integration.
- **Phase 3:** Follow-up system + progress tracking.
- **Phase 4:** Advanced features (relationship context, skill-building).

#### Potential challenges and mitigations
- **Challenge:** Users struggle to identify needs. **Mitigation:** Use concrete examples and multiple question approaches.
- **Challenge:** Scripts feel generic. **Mitigation:** Allow extensive customization and personal editing.
- **Challenge:** Users don't follow through. **Mitigation:** Strong follow-up system with notifications.

#### Performance considerations
- Assessment data cached for quick resumption.
- Script templates pre-loaded locally.
- Follow-up reminders use local notifications.
- Progress data aggregated client-side.

## Appendix A: Boundary Types & Scenarios

| Type | Common Scenarios | Example Boundary |
|------|------------------|------------------|
| Time | Overwork, overcommitment | "I won't check email after 8pm." |
| Emotional | Taking on others' emotions | "I can listen and support without absorbing your stress." |
| Digital | Always-on expectation | "I don't respond to messages on weekends." |
| Physical | Personal space, touch | "I need personal space when I'm overwhelmed." |
| Financial | Lending money, expectations | "I can't lend money, but I can help brainstorm solutions." |
| Relational | Friendships, partnerships | "I need 24-hour notice before visiting." |

## Step 3: Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Boundary completion rate | 60% of started assessments | Completed assessments / started |
| Script usage rate | 50% of boundaries have scripts | Boundaries with scripts / total |
| Practice conversion | 30% practice their scripts | Practice sessions / scripts |
| Follow-up completion | 70% complete first follow-up | Completed follow-ups / scheduled |
| Boundary success rate | 60% report positive outcomes | "Successful" outcomes / responses |
| Return rate | 40% create multiple boundaries | Multiple boundary users / unique users |
