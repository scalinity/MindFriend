# F015: Life Transition Pathways

## Overview

### Summary

Specialized guided programs for major life transitions (job change, relationship changes, grief, parenthood, retirement) with phase-appropriate content, exercises, and companion support.

### Business Value

- Addresses high-value moments when users need support most
- Long-form engagement programs (4-12 weeks)
- Premium subscription driver with specialized content

### User Benefit

- Structured support during vulnerable life moments
- Feeling understood during specific challenges
- Progressive guidance that evolves with their journey

### Dependencies

- F004: Companion Memory Enhancement (for transition context awareness)
- F013: AI-Generated Exercises (for personalized transition exercises)

---

## Requirements

### Functional Requirements

| ID     | Requirement                                                                              | Priority    |
| ------ | ---------------------------------------------------------------------------------------- | ----------- |
| FR-001 | Curated transition programs (job change, breakup, grief, new parent, retirement, moving) | Must Have   |
| FR-002 | Multi-week structured pathway with phases (acknowledge, process, adapt, thrive)          | Must Have   |
| FR-003 | Daily check-ins tailored to current transition phase                                     | Must Have   |
| FR-004 | Phase-appropriate exercises and resources                                                | Must Have   |
| FR-005 | AI companion awareness of active transition for contextual support                       | Must Have   |
| FR-006 | Progress tracking through transition milestones                                          | Should Have |
| FR-007 | Optional journaling prompts specific to transition type                                  | Should Have |
| FR-008 | Community support groups for shared transitions                                          | Could Have  |
| FR-009 | Emergency resources for crisis moments within transitions                                | Must Have   |
| FR-010 | Graduation celebration upon pathway completion                                           | Should Have |

### Non-Functional Requirements

| ID      | Requirement                | Target                    |
| ------- | -------------------------- | ------------------------- |
| NFR-001 | Pathway content loading    | < 1s                      |
| NFR-002 | Phase progression accuracy | User-validated milestones |
| NFR-003 | Content sensitivity        | Clinically reviewed       |
| NFR-004 | Offline access             | Core content available    |

### Acceptance Criteria

```gherkin
Feature: Life Transition Pathways

Scenario: Starting a transition pathway
  Given user selects "Job Loss" transition
  When onboarding flow completes
  Then personalized 8-week pathway should be created
  And current phase should be set to "Acknowledge"
  And daily check-ins should be scheduled
  And AI companion should be informed of transition context

Scenario: Phase progression
  Given user is in week 3 of "Breakup Recovery" pathway
  And user has completed phase 1 milestones
  When user indicates readiness to progress
  Then phase should advance to "Process"
  And new phase-appropriate content should unlock
  And celebration message should appear

Scenario: Contextual AI support during transition
  Given user has active "Grief" transition pathway
  When user opens chat with AI companion
  Then companion should acknowledge the transition context
  And responses should be sensitive to grief stage
  And relevant resources should be suggested when appropriate

Scenario: Crisis within transition
  Given user is in "Divorce" pathway
  When user expresses crisis-level distress
  Then crisis resources should immediately appear
  And pathway should offer "take a break" option
  And check-in frequency should be offered to adjust
```

---

## Technical Design

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    iOS Application                       │
├─────────────────────────────────────────────────────────┤
│  TransitionService                                      │
│  ├── Pathway enrollment and management                  │
│  ├── Phase progression logic                            │
│  ├── Daily content delivery                             │
│  └── Milestone tracking                                 │
├─────────────────────────────────────────────────────────┤
│  TransitionViews                                        │
│  ├── PathwaySelectionView                               │
│  ├── PathwayDashboardView                               │
│  ├── DailyCheckInView                                   │
│  └── PhaseContentView                                   │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│              Supabase Edge Functions                     │
├─────────────────────────────────────────────────────────┤
│  enroll-pathway                                         │
│  ├── Create user pathway record                         │
│  ├── Initialize phase and milestones                    │
│  └── Update companion context                           │
├─────────────────────────────────────────────────────────┤
│  get-daily-content                                      │
│  └── Phase-appropriate content selection                │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                  PostgreSQL Tables                       │
├─────────────────────────────────────────────────────────┤
│  transition_pathways │ user_pathways │ pathway_progress │
└─────────────────────────────────────────────────────────┘
```

### Data Models

#### Database Schema

```sql
-- Transition pathway definitions
CREATE TABLE transition_pathways (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL CHECK (category IN (
        'career', 'relationship', 'loss', 'family', 'health', 'life_stage'
    )),
    duration_weeks INTEGER NOT NULL,
    phases JSONB NOT NULL, -- Array of phase definitions
    is_premium BOOLEAN NOT NULL DEFAULT true,
    icon_name TEXT NOT NULL,
    color TEXT NOT NULL,
    crisis_resources JSONB, -- Transition-specific crisis info
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Pathway phases content
CREATE TABLE pathway_phases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pathway_id UUID NOT NULL REFERENCES transition_pathways(id) ON DELETE CASCADE,
    phase_number INTEGER NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    duration_days INTEGER NOT NULL,
    objectives TEXT[] NOT NULL,
    daily_themes JSONB NOT NULL, -- Day-by-day theme content
    exercises TEXT[] NOT NULL, -- Exercise IDs or keys
    journal_prompts TEXT[] NOT NULL,
    milestones JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(pathway_id, phase_number)
);

-- User pathway enrollments
CREATE TABLE user_pathways (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    pathway_id UUID NOT NULL REFERENCES transition_pathways(id),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    current_phase INTEGER NOT NULL DEFAULT 1,
    current_day INTEGER NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN (
        'active', 'paused', 'completed', 'abandoned'
    )),
    paused_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    personalization JSONB DEFAULT '{}', -- User-specific customizations
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, pathway_id, status) -- One active pathway per type
);

-- Daily progress and check-ins
CREATE TABLE pathway_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_pathway_id UUID NOT NULL REFERENCES user_pathways(id) ON DELETE CASCADE,
    day_number INTEGER NOT NULL,
    phase_number INTEGER NOT NULL,
    check_in_completed BOOLEAN NOT NULL DEFAULT false,
    check_in_data JSONB, -- Mood, notes, responses
    exercises_completed TEXT[] DEFAULT ARRAY[],
    journal_entry TEXT,
    milestones_achieved TEXT[] DEFAULT ARRAY[],
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_pathway_id, day_number)
);

-- Pathway milestones
CREATE TABLE pathway_milestones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_pathway_id UUID NOT NULL REFERENCES user_pathways(id) ON DELETE CASCADE,
    milestone_key TEXT NOT NULL,
    achieved_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    phase_number INTEGER NOT NULL,
    celebration_shown BOOLEAN NOT NULL DEFAULT false,
    UNIQUE(user_pathway_id, milestone_key)
);

-- Indexes
CREATE INDEX idx_transition_pathways_category ON transition_pathways(category);
CREATE INDEX idx_user_pathways_user ON user_pathways(user_id);
CREATE INDEX idx_user_pathways_active ON user_pathways(user_id, status) WHERE status = 'active';
CREATE INDEX idx_pathway_progress_user ON pathway_progress(user_pathway_id, day_number);
CREATE INDEX idx_pathway_milestones_user ON pathway_milestones(user_pathway_id);

-- RLS Policies
ALTER TABLE transition_pathways ENABLE ROW LEVEL SECURITY;
ALTER TABLE pathway_phases ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_pathways ENABLE ROW LEVEL SECURITY;
ALTER TABLE pathway_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE pathway_milestones ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view pathways" ON transition_pathways
    FOR SELECT USING (true);

CREATE POLICY "Anyone can view phases" ON pathway_phases
    FOR SELECT USING (true);

CREATE POLICY "Users can manage own pathways" ON user_pathways
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own progress" ON pathway_progress
    FOR ALL USING (
        user_pathway_id IN (
            SELECT id FROM user_pathways WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Users can view own milestones" ON pathway_milestones
    FOR ALL USING (
        user_pathway_id IN (
            SELECT id FROM user_pathways WHERE user_id = auth.uid()
        )
    );
```

#### Pathway Seed Data

```sql
-- Job Loss / Career Transition
INSERT INTO transition_pathways (key, name, description, category, duration_weeks, phases, icon_name, color, crisis_resources) VALUES
('job_loss', 'Career Transition', 'Navigate job loss or career change with structured support', 'career', 8,
 '[
   {"number": 1, "name": "Acknowledge", "focus": "Processing the change and initial emotions"},
   {"number": 2, "name": "Stabilize", "focus": "Creating routine and self-care foundation"},
   {"number": 3, "name": "Reflect", "focus": "Understanding what you want next"},
   {"number": 4, "name": "Rebuild", "focus": "Taking action toward your goals"}
 ]',
 'briefcase.fill', '#5C6BC0',
 '{"hotline": "211", "resources": ["unemployment_benefits", "career_counseling"]}');

-- Relationship Ending
INSERT INTO transition_pathways (key, name, description, category, duration_weeks, phases, icon_name, color) VALUES
('breakup', 'Relationship Ending', 'Heal and grow after a breakup or divorce', 'relationship', 10,
 '[
   {"number": 1, "name": "Acknowledge", "focus": "Allowing yourself to feel"},
   {"number": 2, "name": "Grieve", "focus": "Processing loss and memories"},
   {"number": 3, "name": "Rediscover", "focus": "Reconnecting with yourself"},
   {"number": 4, "name": "Grow", "focus": "Building your new chapter"}
 ]',
 'heart.slash.fill', '#EC407A');

-- Grief and Loss
INSERT INTO transition_pathways (key, name, description, category, duration_weeks, phases, icon_name, color, crisis_resources) VALUES
('grief', 'Grief Journey', 'Compassionate support through loss of a loved one', 'loss', 12,
 '[
   {"number": 1, "name": "Shock", "focus": "Gentle support through initial grief"},
   {"number": 2, "name": "Feel", "focus": "Space for all emotions"},
   {"number": 3, "name": "Remember", "focus": "Honoring memories and connection"},
   {"number": 4, "name": "Adapt", "focus": "Finding a new normal"}
 ]',
 'leaf.fill', '#78909C',
 '{"hotline": "988", "resources": ["grief_counseling", "support_groups"]}');

-- New Parent
INSERT INTO transition_pathways (key, name, description, category, duration_weeks, phases, icon_name, color) VALUES
('new_parent', 'New Parent Journey', 'Support through the transition to parenthood', 'family', 12,
 '[
   {"number": 1, "name": "Adjust", "focus": "Adapting to your new reality"},
   {"number": 2, "name": "Bond", "focus": "Building connection and confidence"},
   {"number": 3, "name": "Balance", "focus": "Finding your rhythm"},
   {"number": 4, "name": "Thrive", "focus": "Growing into your role"}
 ]',
 'figure.and.child.holdinghands', '#66BB6A');

-- Major Move / Relocation
INSERT INTO transition_pathways (key, name, description, category, duration_weeks, phases, icon_name, color) VALUES
('relocation', 'New Beginnings', 'Navigate a major move or relocation', 'life_stage', 6,
 '[
   {"number": 1, "name": "Farewell", "focus": "Honoring what you''re leaving"},
   {"number": 2, "name": "Settle", "focus": "Creating comfort in the new"},
   {"number": 3, "name": "Explore", "focus": "Discovering your new environment"},
   {"number": 4, "name": "Root", "focus": "Building community and belonging"}
 ]',
 'house.fill', '#42A5F5');

-- Health Diagnosis
INSERT INTO transition_pathways (key, name, description, category, duration_weeks, phases, icon_name, color, crisis_resources) VALUES
('health_diagnosis', 'Health Journey', 'Support through a new health diagnosis', 'health', 8,
 '[
   {"number": 1, "name": "Process", "focus": "Understanding and accepting"},
   {"number": 2, "name": "Learn", "focus": "Building knowledge and support"},
   {"number": 3, "name": "Adapt", "focus": "Adjusting your life"},
   {"number": 4, "name": "Live", "focus": "Moving forward with purpose"}
 ]',
 'heart.text.square.fill', '#EF5350',
 '{"hotline": "988", "resources": ["patient_advocacy", "support_groups"]}');
```

#### Swift Models

```swift
// MARK: - Transition Pathway Models

struct TransitionPathway: Codable, Identifiable {
    let id: UUID
    let key: String
    let name: String
    let description: String
    let category: PathwayCategory
    let durationWeeks: Int
    let phases: [PathwayPhaseOverview]
    let isPremium: Bool
    let iconName: String
    let color: String
    let crisisResources: CrisisResources?
}

enum PathwayCategory: String, Codable, CaseIterable {
    case career
    case relationship
    case loss
    case family
    case health
    case lifeStage = "life_stage"

    var displayName: String {
        switch self {
        case .career: return "Career"
        case .relationship: return "Relationships"
        case .loss: return "Loss & Grief"
        case .family: return "Family"
        case .health: return "Health"
        case .lifeStage: return "Life Changes"
        }
    }
}

struct PathwayPhaseOverview: Codable {
    let number: Int
    let name: String
    let focus: String
}

struct CrisisResources: Codable {
    let hotline: String?
    let resources: [String]?
}

struct PathwayPhase: Codable, Identifiable {
    let id: UUID
    let pathwayId: UUID
    let phaseNumber: Int
    let name: String
    let description: String
    let durationDays: Int
    let objectives: [String]
    let dailyThemes: [DailyTheme]
    let exercises: [String]
    let journalPrompts: [String]
    let milestones: [PhaseMilestone]
}

struct DailyTheme: Codable {
    let day: Int
    let title: String
    let message: String
    let focusArea: String
}

struct PhaseMilestone: Codable {
    let key: String
    let name: String
    let description: String
    let criteria: String
}

struct UserPathway: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let pathwayId: UUID
    let startedAt: Date
    var currentPhase: Int
    var currentDay: Int
    var status: PathwayStatus
    var pausedAt: Date?
    var completedAt: Date?
    let personalization: PathwayPersonalization

    // Joined
    var pathway: TransitionPathway?
    var progress: [PathwayProgress]?

    var totalDays: Int {
        (pathway?.durationWeeks ?? 8) * 7
    }

    var progressPercentage: Double {
        Double(currentDay) / Double(totalDays)
    }

    var currentPhaseName: String {
        pathway?.phases.first { $0.number == currentPhase }?.name ?? "Phase \(currentPhase)"
    }
}

enum PathwayStatus: String, Codable {
    case active
    case paused
    case completed
    case abandoned
}

struct PathwayPersonalization: Codable {
    var transitionDate: Date?
    var specificContext: String?
    var supportPeople: [String]?
    var goals: [String]?
}

struct PathwayProgress: Codable, Identifiable {
    let id: UUID
    let userPathwayId: UUID
    let dayNumber: Int
    let phaseNumber: Int
    var checkInCompleted: Bool
    var checkInData: CheckInData?
    var exercisesCompleted: [String]
    var journalEntry: String?
    var milestonesAchieved: [String]
    let createdAt: Date
}

struct CheckInData: Codable {
    let mood: Int
    let energy: Int
    let notes: String?
    let responses: [String: String]?
}

struct PathwayMilestone: Codable, Identifiable {
    let id: UUID
    let userPathwayId: UUID
    let milestoneKey: String
    let achievedAt: Date
    let phaseNumber: Int
    var celebrationShown: Bool
}

// MARK: - Daily Content

struct DailyPathwayContent {
    let dayNumber: Int
    let phaseNumber: Int
    let theme: DailyTheme
    let checkInPrompt: String
    let exercises: [Exercise]
    let journalPrompt: String?
    let affirmation: String
    let milestone: PhaseMilestone?
}
```

### API Contracts

#### Enroll in Pathway

```
POST /functions/v1/enroll-pathway

Request:
{
  "pathwayKey": "job_loss",
  "personalization": {
    "transitionDate": "2024-01-10",
    "specificContext": "Laid off after 5 years",
    "goals": ["Find new job", "Maintain mental health"]
  }
}

Response 201:
{
  "userPathway": {
    "id": "uuid",
    "pathwayId": "uuid",
    "currentPhase": 1,
    "currentDay": 1,
    "status": "active"
  },
  "todayContent": {
    "theme": {
      "title": "Acknowledging the Change",
      "message": "Today we begin by simply being present with what has happened..."
    },
    "checkInPrompt": "How are you feeling today?",
    "exercises": [...]
  }
}
```

#### Get Daily Content

```
GET /functions/v1/get-pathway-content?userPathwayId={id}

Response 200:
{
  "dayNumber": 5,
  "phaseNumber": 1,
  "theme": {
    "title": "Self-Compassion",
    "message": "It's okay to not be okay right now...",
    "focusArea": "emotional_support"
  },
  "checkInPrompt": "What emotions came up for you yesterday?",
  "exercises": [
    {
      "id": "uuid",
      "name": "Grief Release Breathing",
      "type": "breathing",
      "duration": 300
    }
  ],
  "journalPrompt": "Write a letter to your past self about this change...",
  "affirmation": "I am allowed to take the time I need to heal.",
  "upcomingMilestone": {
    "key": "first_week_complete",
    "name": "First Week Complete",
    "daysAway": 2
  }
}
```

#### Complete Check-In

```
POST /rest/v1/pathway_progress

Request:
{
  "user_pathway_id": "uuid",
  "day_number": 5,
  "phase_number": 1,
  "check_in_completed": true,
  "check_in_data": {
    "mood": 4,
    "energy": 3,
    "notes": "Feeling a bit better today"
  },
  "exercises_completed": ["grief_breathing"],
  "journal_entry": "Dear past me..."
}
```

#### Advance Phase

```
POST /functions/v1/advance-pathway-phase

Request:
{
  "userPathwayId": "uuid"
}

Response 200:
{
  "success": true,
  "newPhase": 2,
  "phaseName": "Stabilize",
  "celebration": {
    "title": "Phase 1 Complete!",
    "message": "You've completed the Acknowledge phase...",
    "milestones": ["acknowledge_complete"]
  }
}
```

---

## Implementation Details

### Step-by-Step Approach

1. **Pathway Content Creation**
   - Define 6 core transition types
   - Create 4 phases per pathway
   - Write daily themes and content
   - Curate exercises per phase

2. **Enrollment Flow**
   - Pathway selection UI
   - Personalization questionnaire
   - Companion context update
   - Initial content delivery

3. **Daily Experience**
   - Morning check-in notification
   - Phase-appropriate content
   - Exercise recommendations
   - Journal prompts

4. **Phase Progression**
   - Milestone tracking
   - User-confirmed advancement
   - Celebration moments
   - Content unlocking

5. **Companion Integration**
   - Update companion context on enrollment
   - Transition-aware responses
   - Crisis detection enhancement

### File Structure

```
apps/ios/MindFriendApp/
├── Features/
│   └── Transitions/
│       ├── TransitionService.swift
│       ├── Views/
│       │   ├── PathwaySelectionView.swift
│       │   ├── PathwayOnboardingFlow.swift
│       │   ├── PathwayDashboardView.swift
│       │   ├── DailyTransitionView.swift
│       │   ├── PhaseProgressView.swift
│       │   └── PathwayCompletionView.swift
│       └── Components/
│           ├── PhaseCard.swift
│           ├── MilestoneTracker.swift
│           └── TransitionCheckIn.swift
│
supabase/
├── functions/
│   ├── enroll-pathway/
│   ├── get-pathway-content/
│   └── advance-pathway-phase/
├── migrations/
│   └── YYYYMMDD_transition_pathways.sql
```

### Key Algorithms

#### Daily Content Selection (TypeScript)

```typescript
async function getDailyPathwayContent(
  supabase: SupabaseClient,
  userPathwayId: string,
): Promise<DailyPathwayContent> {
  // Get user pathway with pathway details
  const { data: userPathway } = await supabase
    .from("user_pathways")
    .select("*, pathway:transition_pathways(*)")
    .eq("id", userPathwayId)
    .single();

  if (!userPathway) {
    throw new Error("Pathway not found");
  }

  // Get current phase details
  const { data: phase } = await supabase
    .from("pathway_phases")
    .select("*")
    .eq("pathway_id", userPathway.pathway_id)
    .eq("phase_number", userPathway.current_phase)
    .single();

  // Calculate day within phase
  const dayInPhase = calculateDayInPhase(
    userPathway.current_day,
    userPathway.current_phase,
    userPathway.pathway.phases,
  );

  // Get daily theme
  const dailyTheme =
    phase.daily_themes[dayInPhase - 1] ||
    generateDefaultTheme(phase, dayInPhase);

  // Select exercises appropriate for this phase
  const exercises = await selectPhaseExercises(
    supabase,
    phase.exercises,
    userPathway.personalization,
  );

  // Get journal prompt (rotate through available)
  const journalPrompt =
    phase.journal_prompts[(dayInPhase - 1) % phase.journal_prompts.length];

  // Check for upcoming milestone
  const upcomingMilestone = findUpcomingMilestone(
    phase.milestones,
    userPathway.current_day,
    phase.duration_days,
  );

  // Generate affirmation based on phase and personalization
  const affirmation = await generateAffirmation(
    userPathway.pathway.key,
    phase.name,
    userPathway.personalization,
  );

  return {
    dayNumber: userPathway.current_day,
    phaseNumber: userPathway.current_phase,
    theme: dailyTheme,
    checkInPrompt: generateCheckInPrompt(phase, dayInPhase),
    exercises,
    journalPrompt,
    affirmation,
    upcomingMilestone,
  };
}

function generateCheckInPrompt(
  phase: PathwayPhase,
  dayInPhase: number,
): string {
  const prompts: Record<string, string[]> = {
    Acknowledge: [
      "How are you feeling today?",
      "What emotions have come up since yesterday?",
      "How did you sleep last night?",
      "What's one small thing you did for yourself today?",
    ],
    Process: [
      "What came up for you in reflection yesterday?",
      "How is your body feeling today?",
      "What support do you need right now?",
      "What are you grateful for despite everything?",
    ],
    Adapt: [
      "What small step forward did you take?",
      "How are you adjusting to the changes?",
      "What new routine is helping you?",
      "What challenge can you release today?",
    ],
    Thrive: [
      "What are you proud of?",
      "How has your perspective shifted?",
      "What excites you about the future?",
      "How will you celebrate your growth?",
    ],
  };

  const phasePrompts = prompts[phase.name] || prompts["Acknowledge"];
  return phasePrompts[(dayInPhase - 1) % phasePrompts.length];
}

async function updateCompanionContext(
  supabase: SupabaseClient,
  userId: string,
  pathway: TransitionPathway,
  personalization: PathwayPersonalization,
): Promise<void> {
  // Add to companion memories
  await supabase.from("companion_memories").insert({
    user_id: userId,
    category: "life_event",
    content:
      `User is going through: ${pathway.name}. ` +
      `Context: ${personalization.specificContext || "Not specified"}. ` +
      `Started: ${new Date().toISOString().split("T")[0]}. ` +
      `Goals: ${personalization.goals?.join(", ") || "Not specified"}.`,
    importance: 0.95,
    expires_at: null, // Permanent until pathway completes
  });

  // Update active transition flag
  await supabase
    .from("profiles")
    .update({
      active_transition: pathway.key,
      updated_at: new Date().toISOString(),
    })
    .eq("id", userId);
}
```

---

## Dependencies

### Internal Dependencies

- **F004 Companion Memory**: For transition context in AI conversations
- **F013 AI-Generated Exercises**: For personalized transition exercises
- **Exercise library**: For curated phase-appropriate exercises

### External Dependencies

- None specific

### Infrastructure Requirements

- Content management for pathway materials
- Daily notification scheduling

---

## Edge Cases & Error Handling

| Scenario                                           | Handling                                                    |
| -------------------------------------------------- | ----------------------------------------------------------- |
| User enrolls in second pathway                     | Allow multiple if different categories; warn if same        |
| User pauses pathway for 30+ days                   | Offer restart or resume with adjustment                     |
| User in crisis during pathway                      | Immediately show crisis resources; pause pathway optionally |
| Phase milestones not met but user wants to advance | Allow with acknowledgment that revisiting is okay           |
| Pathway content not loaded                         | Cache essential content locally                             |
| User completes pathway early                       | Celebrate and offer continued resources                     |
| User abandons pathway                              | Check in after 7 days; offer support                        |
| Transition anniversary approaches                  | Send gentle acknowledgment notification                     |

---

## Testing Requirements

### Unit Tests

```swift
// TransitionServiceTests.swift

func testPhaseProgression() async throws {
    let service = TransitionService(supabase: mockSupabase)
    mockSupabase.setUserPathway(phase: 1, day: 14)

    let result = try await service.advancePhase(userPathwayId: testId)

    XCTAssertEqual(result.newPhase, 2)
    XCTAssertNotNil(result.celebration)
}

func testDayWithinPhaseCalculation() {
    let service = TransitionService(supabase: mockSupabase)

    // Day 15 overall, phase 2 starts at day 15
    let dayInPhase = service.calculateDayInPhase(
        overallDay: 17,
        currentPhase: 2,
        phases: mockPhases
    )

    XCTAssertEqual(dayInPhase, 3)
}

func testCheckInPromptRotation() {
    let phase = MockData.acknowledgePhase

    let day1Prompt = generateCheckInPrompt(phase, dayInPhase: 1)
    let day5Prompt = generateCheckInPrompt(phase, dayInPhase: 5)

    // Day 5 should rotate back to first prompt (4 prompts total)
    XCTAssertEqual(day1Prompt, day5Prompt)
}

func testMilestoneDetection() {
    let milestones = [
        PhaseMilestone(key: "week_1", criteria: "day >= 7"),
        PhaseMilestone(key: "week_2", criteria: "day >= 14")
    ]

    let upcoming = findUpcomingMilestone(milestones, currentDay: 5, totalDays: 14)

    XCTAssertEqual(upcoming?.key, "week_1")
}
```

### Integration Tests

```typescript
// supabase/functions/enroll-pathway/test.ts

Deno.test("enrollment creates user pathway and updates context", async () => {
  const userId = await createTestUser();

  const result = await invokeFunction(
    "enroll-pathway",
    {
      pathwayKey: "job_loss",
      personalization: {
        transitionDate: "2024-01-10",
        specificContext: "Layoff",
      },
    },
    userId,
  );

  assertExists(result.userPathway);
  assertEquals(result.userPathway.currentPhase, 1);
  assertEquals(result.userPathway.currentDay, 1);

  // Check companion context was updated
  const { data: memories } = await supabase
    .from("companion_memories")
    .select("*")
    .eq("user_id", userId)
    .eq("category", "life_event");

  assert(memories.length > 0);
  assert(memories[0].content.includes("job_loss"));
});

Deno.test("daily content matches current phase", async () => {
  const userId = await createTestUser();
  const { userPathway } = await enrollInPathway(userId, "grief");

  // Advance to phase 2
  await advanceToPhase(userPathway.id, 2, 20);

  const content = await invokeFunction(
    "get-pathway-content",
    {
      userPathwayId: userPathway.id,
    },
    userId,
  );

  assertEquals(content.phaseNumber, 2);
  // Phase 2 of grief is "Feel"
  assert(
    content.theme.focusArea.includes("emotion") ||
      content.theme.focusArea.includes("feel"),
  );
});
```
