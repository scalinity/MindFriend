# Structured Therapeutic Programs (CBT/DBT/ACT)

> Evidence-based clinical programs that differentiate MindFriend as a serious mental health tool, not just a wellness app.

**Priority:** P0 - Critical
**Effort:** High (8-10 weeks)
**Impact:** Clinical credibility, enterprise market access, higher price justification

---

## 1. Overview

### 1.1 What It Does

Multi-week structured programs based on proven therapeutic modalities (CBT, DBT, ACT) with:

- Interactive workbook-style exercises
- Standardized clinical assessments (PHQ-9, GAD-7)
- Progress tracking with measurable outcomes
- Certificate of completion
- Optional therapist review integration

### 1.2 Why It Exists

- **Market Gap:** MindFriend has generic "Programs" but NO clinical methodology
- **Clinical Credibility:** Insurance/employers require evidence-based approaches
- **Competitor Landscape:**
  - Woebot has FDA-cleared digital therapeutic
  - Wysa has peer-reviewed CBT outcomes
  - MindFriend has opportunity to match or exceed
- **User Demand:** People seeking mental health support want proven methods

### 1.3 Success Metrics

| Metric                  | Target                 | Measurement         |
| ----------------------- | ---------------------- | ------------------- |
| Program enrollment rate | 30% of active users    | Enrollment / MAU    |
| Program completion rate | 50%+                   | Completed / Started |
| PHQ-9/GAD-7 improvement | -3 points average      | Pre/post assessment |
| User satisfaction       | 4.5+ stars             | Post-program survey |
| Enterprise adoption     | 10+ deals in 12 months | Sales tracking      |

---

## 2. User Stories

### 2.1 Primary Users

| Persona                | Need                    | Story                                                                                                                                   |
| ---------------------- | ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| **Anxiety Sufferer**   | Proven techniques       | "As someone with anxiety, I want to learn CBT skills in a structured way so I can manage my symptoms long-term."                        |
| **Depression Fighter** | Step-by-step guidance   | "As someone with depression, I want a program that guides me through evidence-based activities so I don't have to figure it out alone." |
| **Self-Improver**      | Deeper tools            | "As someone wanting to grow, I want programs based on real psychology so I know I'm not wasting time on fluff."                         |
| **Enterprise Admin**   | Measurable outcomes     | "As an HR manager, I want employees to access clinically-validated programs so we can demonstrate ROI on wellness spending."            |
| **Therapist**          | Between-session support | "As a therapist, I want to recommend MindFriend programs to my clients for homework support."                                           |

### 2.2 Program Journey

```
Discovery
    │
    ▼
┌───────────────────┐
│ Programs Library  │
│ • Browse by goal  │
│ • See methodology │
│ • Check duration  │
└───────────────────┘
    │ Select program
    ▼
┌───────────────────┐
│ Program Preview   │
│ • What you'll do  │
│ • Who it's for    │
│ • Evidence base   │
│ • Time commitment │
└───────────────────┘
    │ Enroll
    ▼
┌───────────────────┐
│ Pre-Assessment    │
│ • PHQ-9 or GAD-7  │
│ • Baseline setup  │
└───────────────────┘
    │
    ▼
┌───────────────────┐
│ Daily Modules     │──▶ Repeat for program duration
│ • Psychoeducation │
│ • Exercise/Tool   │
│ • Reflection      │
│ • Practice task   │
└───────────────────┘
    │ (Weekly)
    ▼
┌───────────────────┐
│ Weekly Check-in   │
│ • Mini-assessment │
│ • Progress review │
│ • AI coaching     │
└───────────────────┘
    │ Program end
    ▼
┌───────────────────┐
│ Post-Assessment   │
│ • PHQ-9 or GAD-7  │
│ • Improvement?    │
└───────────────────┘
    │
    ▼
┌───────────────────┐
│ Completion        │
│ • Certificate     │
│ • Shareable badge │
│ • Recommendations │
└───────────────────┘
```

---

## 3. Functional Requirements

### 3.1 Program Library

| ID    | Requirement                                                    | Priority |
| ----- | -------------------------------------------------------------- | -------- |
| PL-01 | Display all available programs with filtering                  | Must     |
| PL-02 | Filter by: methodology (CBT/DBT/ACT), duration, goal           | Must     |
| PL-03 | Show program difficulty level (Beginner/Intermediate/Advanced) | Should   |
| PL-04 | Display evidence badges (e.g., "Based on CBT principles")      | Must     |
| PL-05 | Show user ratings and completion count                         | Should   |
| PL-06 | Indicate premium-only programs                                 | Must     |
| PL-07 | Personalized "Recommended for You" based on mood data          | Should   |

### 3.2 Program Content Structure

| ID    | Requirement                                               | Priority |
| ----- | --------------------------------------------------------- | -------- |
| PC-01 | Programs have 7, 14, 21, or 28 day durations              | Must     |
| PC-02 | Each day has 1-3 modules (15-30 min total)                | Must     |
| PC-03 | Modules include: video, text, interactive exercise, audio | Must     |
| PC-04 | Daily practice task assigned (real-world homework)        | Must     |
| PC-05 | Weekly reflection/check-in required                       | Should   |
| PC-06 | Progress saved if user pauses program                     | Must     |
| PC-07 | Catch-up mode if user falls behind                        | Should   |

### 3.3 Clinical Assessments

| ID    | Requirement                                            | Priority |
| ----- | ------------------------------------------------------ | -------- |
| CA-01 | Administer PHQ-9 (depression) at program start and end | Must     |
| CA-02 | Administer GAD-7 (anxiety) at program start and end    | Must     |
| CA-03 | Weekly mini-check (2-4 questions) during program       | Should   |
| CA-04 | Display score interpretation with clinical ranges      | Must     |
| CA-05 | Track score changes over time with visualization       | Must     |
| CA-06 | Flag significant score increases for safety review     | Must     |
| CA-07 | Store assessment data securely with RLS                | Must     |

### 3.4 Interactive Exercises

| ID    | Requirement                                                         | Priority |
| ----- | ------------------------------------------------------------------- | -------- |
| IE-01 | CBT Thought Record (capture thought → feeling → evidence → reframe) | Must     |
| IE-02 | Behavioral Activation planner (schedule activities)                 | Must     |
| IE-03 | DBT emotion regulation worksheet                                    | Must     |
| IE-04 | ACT values clarification exercise                                   | Must     |
| IE-05 | Worry time scheduling tool                                          | Should   |
| IE-06 | Gratitude journal (structured)                                      | Must     |
| IE-07 | Body scan guided exercise                                           | Must     |
| IE-08 | Progressive muscle relaxation                                       | Should   |
| IE-09 | Socratic questioning prompts                                        | Should   |
| IE-10 | Exposure hierarchy builder                                          | Should   |

### 3.5 Progress & Outcomes

| ID    | Requirement                                    | Priority |
| ----- | ---------------------------------------------- | -------- |
| PO-01 | Show daily/weekly progress within program      | Must     |
| PO-02 | Generate completion certificate (PDF)          | Must     |
| PO-03 | Award badge/achievement on completion          | Must     |
| PO-04 | Show pre/post assessment comparison            | Must     |
| PO-05 | Export progress report (for therapist sharing) | Should   |
| PO-06 | Maintain access to completed program materials | Must     |
| PO-07 | Award significant XP for program completion    | Must     |

### 3.6 AI Integration

| ID    | Requirement                                                    | Priority |
| ----- | -------------------------------------------------------------- | -------- |
| AI-01 | AI coach provides encouragement during program                 | Should   |
| AI-02 | AI reviews thought records and offers alternative perspectives | Should   |
| AI-03 | AI adapts daily content based on check-in responses            | Could    |
| AI-04 | AI summarizes weekly progress                                  | Should   |
| AI-05 | AI never provides clinical diagnosis or medication advice      | Must     |

---

## 4. Technical Requirements

### 4.1 Data Models

```sql
-- Therapeutic methodologies
CREATE TYPE therapy_methodology AS ENUM ('cbt', 'dbt', 'act', 'mbct', 'mixed');

-- Program definitions
CREATE TABLE therapeutic_programs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    subtitle TEXT,
    description TEXT NOT NULL,
    methodology therapy_methodology NOT NULL,
    duration_days INTEGER NOT NULL CHECK (duration_days IN (7, 14, 21, 28)),
    difficulty TEXT CHECK (difficulty IN ('beginner', 'intermediate', 'advanced')),
    target_condition TEXT[], -- ['anxiety', 'depression', 'stress']
    evidence_summary TEXT, -- Brief description of research backing
    evidence_url TEXT, -- Link to research
    is_premium BOOLEAN DEFAULT false,
    thumbnail_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Program modules (daily content)
CREATE TABLE program_modules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    program_id UUID NOT NULL REFERENCES therapeutic_programs(id) ON DELETE CASCADE,
    day_number INTEGER NOT NULL,
    module_order INTEGER NOT NULL DEFAULT 1, -- For multiple modules per day
    title TEXT NOT NULL,
    content_type TEXT CHECK (content_type IN ('video', 'text', 'audio', 'exercise', 'reflection')),
    content_body TEXT, -- Markdown or JSON for exercises
    duration_minutes INTEGER NOT NULL,
    exercise_type TEXT, -- 'thought_record', 'values_clarification', etc.
    practice_task TEXT, -- Real-world homework
    UNIQUE(program_id, day_number, module_order)
);

-- User program enrollments
CREATE TABLE program_enrollments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    program_id UUID NOT NULL REFERENCES therapeutic_programs(id),
    enrolled_at TIMESTAMPTZ DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    status TEXT DEFAULT 'enrolled' CHECK (status IN ('enrolled', 'active', 'paused', 'completed', 'abandoned')),
    current_day INTEGER DEFAULT 0,
    pre_assessment_id UUID,
    post_assessment_id UUID,
    UNIQUE(user_id, program_id, enrolled_at)
);

-- Daily progress tracking
CREATE TABLE program_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    enrollment_id UUID NOT NULL REFERENCES program_enrollments(id) ON DELETE CASCADE,
    module_id UUID NOT NULL REFERENCES program_modules(id),
    completed_at TIMESTAMPTZ DEFAULT NOW(),
    time_spent_seconds INTEGER,
    exercise_data JSONB, -- Stores thought records, values, etc.
    reflection_notes TEXT,
    practice_task_completed BOOLEAN DEFAULT false
);

-- Clinical assessments
CREATE TABLE clinical_assessments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    assessment_type TEXT NOT NULL CHECK (assessment_type IN ('phq9', 'gad7', 'who5', 'pcl5')),
    enrollment_id UUID REFERENCES program_enrollments(id), -- Optional link to program
    assessment_point TEXT CHECK (assessment_point IN ('pre', 'weekly', 'post', 'standalone')),
    responses JSONB NOT NULL, -- [{question_id, response_value}]
    total_score INTEGER NOT NULL,
    severity TEXT, -- 'minimal', 'mild', 'moderate', 'moderately_severe', 'severe'
    administered_at TIMESTAMPTZ DEFAULT NOW(),
    flagged_for_review BOOLEAN DEFAULT false
);

-- Thought records (CBT core exercise)
CREATE TABLE thought_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    enrollment_id UUID REFERENCES program_enrollments(id),
    situation TEXT NOT NULL, -- What happened
    automatic_thought TEXT NOT NULL, -- Initial thought
    emotions JSONB NOT NULL, -- [{emotion, intensity_0_100}]
    evidence_for TEXT, -- Evidence supporting the thought
    evidence_against TEXT, -- Evidence against the thought
    cognitive_distortion TEXT[], -- ['catastrophizing', 'black_and_white', etc.]
    balanced_thought TEXT, -- Reframed thought
    new_emotion_intensity INTEGER, -- 0-100
    ai_feedback TEXT, -- AI-generated perspective
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- DBT Emotion regulation logs
CREATE TABLE emotion_regulation_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    enrollment_id UUID REFERENCES program_enrollments(id),
    triggering_event TEXT NOT NULL,
    vulnerability_factors TEXT[], -- PLEASE skills check
    emotion TEXT NOT NULL,
    intensity_before INTEGER CHECK (intensity_before BETWEEN 0 AND 100),
    skill_used TEXT NOT NULL, -- 'opposite_action', 'check_the_facts', 'TIPP', etc.
    skill_steps TEXT, -- What user did
    intensity_after INTEGER CHECK (intensity_after BETWEEN 0 AND 100),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ACT Values clarification
CREATE TABLE values_assessments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    enrollment_id UUID REFERENCES program_enrollments(id),
    life_domain TEXT NOT NULL, -- 'relationships', 'work', 'health', etc.
    importance_rating INTEGER CHECK (importance_rating BETWEEN 1 AND 10),
    current_alignment INTEGER CHECK (current_alignment BETWEEN 1 AND 10),
    committed_actions TEXT[], -- Specific actions to take
    barriers TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Program certificates
CREATE TABLE program_certificates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    enrollment_id UUID NOT NULL REFERENCES program_enrollments(id),
    program_id UUID NOT NULL REFERENCES therapeutic_programs(id),
    issued_at TIMESTAMPTZ DEFAULT NOW(),
    certificate_url TEXT, -- Generated PDF URL
    pre_score INTEGER,
    post_score INTEGER,
    improvement INTEGER, -- post - pre (positive = improvement)
    UNIQUE(enrollment_id)
);

-- RLS Policies
ALTER TABLE therapeutic_programs ENABLE ROW LEVEL SECURITY;
ALTER TABLE program_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE program_enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE program_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE clinical_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE thought_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE emotion_regulation_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE values_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE program_certificates ENABLE ROW LEVEL SECURITY;

-- Programs and modules are readable by all authenticated users
CREATE POLICY "Programs readable by authenticated"
    ON therapeutic_programs FOR SELECT
    USING (auth.role() = 'authenticated');

CREATE POLICY "Modules readable by authenticated"
    ON program_modules FOR SELECT
    USING (auth.role() = 'authenticated');

-- User data policies
CREATE POLICY "Users manage own enrollments"
    ON program_enrollments FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users manage own progress"
    ON program_progress FOR ALL
    USING (enrollment_id IN (
        SELECT id FROM program_enrollments WHERE user_id = auth.uid()
    ));

CREATE POLICY "Users manage own assessments"
    ON clinical_assessments FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users manage own thought records"
    ON thought_records FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users manage own emotion logs"
    ON emotion_regulation_logs FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users manage own values"
    ON values_assessments FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users view own certificates"
    ON program_certificates FOR SELECT
    USING (auth.uid() = user_id);
```

### 4.2 Swift Models

```swift
// MARK: - Therapeutic Program Models

enum TherapyMethodology: String, Codable, CaseIterable {
    case cbt = "cbt"
    case dbt = "dbt"
    case act = "act"
    case mbct = "mbct"
    case mixed = "mixed"

    var displayName: String {
        switch self {
        case .cbt: return "Cognitive Behavioral Therapy"
        case .dbt: return "Dialectical Behavior Therapy"
        case .act: return "Acceptance & Commitment Therapy"
        case .mbct: return "Mindfulness-Based CBT"
        case .mixed: return "Integrated Approach"
        }
    }

    var shortName: String {
        rawValue.uppercased()
    }
}

enum ProgramDifficulty: String, Codable {
    case beginner
    case intermediate
    case advanced
}

struct TherapeuticProgram: Identifiable, Codable {
    let id: UUID
    let title: String
    let subtitle: String?
    let description: String
    let methodology: TherapyMethodology
    let durationDays: Int
    let difficulty: ProgramDifficulty
    let targetConditions: [String]
    let evidenceSummary: String?
    let evidenceUrl: URL?
    let isPremium: Bool
    let thumbnailUrl: URL?
}

struct ProgramModule: Identifiable, Codable {
    let id: UUID
    let programId: UUID
    let dayNumber: Int
    let moduleOrder: Int
    let title: String
    let contentType: ModuleContentType
    let contentBody: String // Markdown or JSON
    let durationMinutes: Int
    let exerciseType: ExerciseType?
    let practiceTask: String?

    enum ModuleContentType: String, Codable {
        case video, text, audio, exercise, reflection
    }

    enum ExerciseType: String, Codable {
        case thoughtRecord = "thought_record"
        case behavioralActivation = "behavioral_activation"
        case emotionRegulation = "emotion_regulation"
        case valuesClarification = "values_clarification"
        case gratitude
        case bodyScan = "body_scan"
        case exposureHierarchy = "exposure_hierarchy"
    }
}

struct ProgramEnrollment: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let programId: UUID
    let enrolledAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var status: EnrollmentStatus
    var currentDay: Int

    enum EnrollmentStatus: String, Codable {
        case enrolled, active, paused, completed, abandoned
    }
}

// MARK: - Clinical Assessments

enum AssessmentType: String, Codable {
    case phq9
    case gad7
    case who5
    case pcl5

    var title: String {
        switch self {
        case .phq9: return "PHQ-9 Depression Screening"
        case .gad7: return "GAD-7 Anxiety Screening"
        case .who5: return "WHO-5 Well-Being Index"
        case .pcl5: return "PCL-5 PTSD Screening"
        }
    }

    var questions: [AssessmentQuestion] {
        switch self {
        case .phq9: return PHQ9Questions.all
        case .gad7: return GAD7Questions.all
        case .who5: return WHO5Questions.all
        case .pcl5: return PCL5Questions.all
        }
    }
}

struct AssessmentQuestion: Identifiable {
    let id: Int
    let text: String
    let options: [AssessmentOption]
}

struct AssessmentOption {
    let value: Int
    let label: String
}

struct ClinicalAssessment: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let assessmentType: AssessmentType
    let enrollmentId: UUID?
    let assessmentPoint: AssessmentPoint
    let responses: [AssessmentResponse]
    let totalScore: Int
    let severity: Severity
    let administeredAt: Date
    let flaggedForReview: Bool

    enum AssessmentPoint: String, Codable {
        case pre, weekly, post, standalone
    }

    struct AssessmentResponse: Codable {
        let questionId: Int
        let responseValue: Int
    }

    enum Severity: String, Codable {
        case minimal
        case mild
        case moderate
        case moderatelySevere = "moderately_severe"
        case severe
    }
}

// MARK: - CBT Thought Record

struct ThoughtRecord: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let enrollmentId: UUID?
    var situation: String
    var automaticThought: String
    var emotions: [EmotionEntry]
    var evidenceFor: String?
    var evidenceAgainst: String?
    var cognitiveDistortions: [CognitiveDistortion]
    var balancedThought: String?
    var newEmotionIntensity: Int?
    var aiFeedback: String?
    let createdAt: Date

    struct EmotionEntry: Codable {
        let emotion: String
        var intensity: Int // 0-100
    }

    enum CognitiveDistortion: String, Codable, CaseIterable {
        case allOrNothing = "all_or_nothing"
        case overgeneralization
        case mentalFilter = "mental_filter"
        case disqualifyingPositive = "disqualifying_positive"
        case jumpingToConclusions = "jumping_to_conclusions"
        case magnification
        case emotionalReasoning = "emotional_reasoning"
        case shouldStatements = "should_statements"
        case labeling
        case personalization

        var displayName: String {
            switch self {
            case .allOrNothing: return "All-or-Nothing Thinking"
            case .overgeneralization: return "Overgeneralization"
            case .mentalFilter: return "Mental Filter"
            case .disqualifyingPositive: return "Disqualifying the Positive"
            case .jumpingToConclusions: return "Jumping to Conclusions"
            case .magnification: return "Magnification/Minimization"
            case .emotionalReasoning: return "Emotional Reasoning"
            case .shouldStatements: return "Should Statements"
            case .labeling: return "Labeling"
            case .personalization: return "Personalization"
            }
        }

        var description: String {
            // ... descriptions for each
        }
    }
}

// MARK: - ACT Values

struct ValuesAssessment: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let enrollmentId: UUID?
    let lifeDomain: LifeDomain
    var importanceRating: Int // 1-10
    var currentAlignment: Int // 1-10
    var committedActions: [String]
    var barriers: String?
    let createdAt: Date

    enum LifeDomain: String, Codable, CaseIterable {
        case relationships
        case family
        case parenting
        case friendships
        case work
        case education
        case recreation
        case spirituality
        case citizenship
        case health

        var displayName: String {
            rawValue.capitalized
        }
    }

    var alignmentGap: Int {
        importanceRating - currentAlignment
    }
}
```

### 4.3 API Contracts

#### Get Available Programs

```typescript
// GET /rest/v1/therapeutic_programs?select=*&order=created_at.desc
// Headers: Authorization: Bearer <jwt>

// Response
[
  {
    id: "uuid",
    title: "7-Day Anxiety Relief",
    subtitle: "CBT techniques for managing worry",
    description: "...",
    methodology: "cbt",
    duration_days: 7,
    difficulty: "beginner",
    target_conditions: ["anxiety", "worry", "stress"],
    evidence_summary: "Based on CBT protocols shown effective in 200+ studies",
    is_premium: false,
    thumbnail_url: "...",
  },
];
```

#### Enroll in Program

```typescript
// POST /rest/v1/program_enrollments
// Headers: Authorization: Bearer <jwt>

// Request
{
    "program_id": "uuid"
}

// Response: 201 Created with enrollment object
```

#### Submit Assessment

```typescript
// Edge Function: submit-assessment
// POST /functions/v1/submit-assessment

// Request
{
    "assessment_type": "phq9",
    "enrollment_id": "uuid", // optional
    "assessment_point": "pre",
    "responses": [
        {"question_id": 1, "response_value": 2},
        {"question_id": 2, "response_value": 1},
        // ... all 9 questions
    ]
}

// Response
{
    "id": "uuid",
    "total_score": 12,
    "severity": "moderate",
    "interpretation": "Your score suggests moderate depression symptoms. This program can help you develop skills to manage these feelings.",
    "flagged_for_review": false,
    "recommendations": [
        "Consider speaking with a mental health professional",
        "This program includes skills specifically designed for your needs"
    ]
}
```

#### Submit Thought Record

```typescript
// POST /rest/v1/thought_records
// Headers: Authorization: Bearer <jwt>

// Request
{
    "enrollment_id": "uuid",
    "situation": "Boss criticized my work in front of the team",
    "automatic_thought": "I'm terrible at my job and everyone thinks I'm incompetent",
    "emotions": [
        {"emotion": "shame", "intensity": 85},
        {"emotion": "anxiety", "intensity": 70}
    ],
    "evidence_for": "He did point out mistakes I made",
    "evidence_against": "I got a positive review last quarter. Other team members have been criticized too.",
    "cognitive_distortions": ["overgeneralization", "jumping_to_conclusions"],
    "balanced_thought": "I made some mistakes on this project, but that doesn't mean I'm bad at my job overall. One criticism doesn't define my worth.",
    "new_emotion_intensity": 45
}

// Response: 201 Created
// AI feedback generated asynchronously and added to record
```

#### Get Program Progress

```typescript
// Edge Function: get-program-progress
// POST /functions/v1/get-program-progress

// Request
{
    "enrollment_id": "uuid"
}

// Response
{
    "enrollment": { /* enrollment object */ },
    "program": { /* program object */ },
    "days_completed": 5,
    "total_days": 7,
    "completion_percentage": 71,
    "current_day_modules": [ /* today's modules */ ],
    "completed_modules": [ /* with completion timestamps */ ],
    "assessments": {
        "pre": { "score": 15, "severity": "moderate" },
        "weekly": [ { "score": 12, "severity": "mild" } ]
    },
    "thought_records_count": 8,
    "practice_tasks_completed": 4,
    "streak_days": 5,
    "next_module": { /* next uncompleted module */ }
}
```

### 4.4 Edge Functions

```typescript
// supabase/functions/analyze-thought-record/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const authHeader = req.headers.get("Authorization")!;
  const {
    data: { user },
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

  if (!user) {
    return new Response("Unauthorized", { status: 401 });
  }

  const { thought_record_id } = await req.json();

  // Fetch the thought record
  const { data: record } = await supabase
    .from("thought_records")
    .select("*")
    .eq("id", thought_record_id)
    .eq("user_id", user.id)
    .single();

  if (!record) {
    return new Response("Not found", { status: 404 });
  }

  // Generate AI feedback using Grok
  const feedback = await generateThoughtRecordFeedback(record);

  // Update record with feedback
  await supabase
    .from("thought_records")
    .update({ ai_feedback: feedback })
    .eq("id", thought_record_id);

  return new Response(JSON.stringify({ feedback }), {
    headers: { "Content-Type": "application/json" },
  });
});

async function generateThoughtRecordFeedback(record: any): Promise<string> {
  const prompt = `You are a supportive CBT coach. A user has completed a thought record:

Situation: ${record.situation}
Automatic Thought: ${record.automatic_thought}
Emotions: ${record.emotions.map((e) => `${e.emotion} (${e.intensity}%)`).join(", ")}
Evidence For: ${record.evidence_for || "Not provided"}
Evidence Against: ${record.evidence_against || "Not provided"}
Cognitive Distortions Identified: ${record.cognitive_distortions?.join(", ") || "None identified"}
Balanced Thought: ${record.balanced_thought || "Not yet completed"}
New Emotion Intensity: ${record.new_emotion_intensity ?? "Not rated"}

Provide brief, warm, encouraging feedback (2-3 sentences) that:
1. Validates their effort in examining their thoughts
2. Gently offers an additional perspective they might not have considered
3. Encourages continued practice

Do NOT diagnose or provide clinical advice. Keep response under 100 words.`;

  const response = await fetch("https://api.x.ai/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${Deno.env.get("XAI_API_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "grok-beta",
      messages: [{ role: "user", content: prompt }],
      max_tokens: 150,
    }),
  });

  const data = await response.json();
  return data.choices[0].message.content;
}
```

---

## 5. UI/UX Specifications

### 5.1 Programs Library

```
┌─────────────────────────────────┐
│ Programs                   🔍    │
├─────────────────────────────────┤
│                                 │
│ Recommended for You             │
│ ┌─────────────────────────────┐ │
│ │ 🧠 7-Day Anxiety Relief     │ │
│ │ CBT • 7 days • Beginner     │ │
│ │ ████████░░ 80% match        │ │
│ │                [Explore →]  │ │
│ └─────────────────────────────┘ │
│                                 │
│ Filter: [All ▼] [CBT ▼] [7d ▼] │
│                                 │
│ All Programs                    │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 🎯 21-Day Depression Reset  │ │
│ │ CBT • 21 days • Intermediate│ │
│ │ ⭐ 4.8 (234 completions)    │ │
│ │ 🔬 Evidence-based           │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 💚 DBT Skills for Emotions  │ │
│ │ DBT • 14 days • Intermediate│ │
│ │ ⭐ 4.7 (156 completions)    │ │
│ │ 👑 Premium                  │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 🌱 ACT: Living Your Values  │ │
│ │ ACT • 14 days • Beginner    │ │
│ │ ⭐ 4.9 (89 completions)     │ │
│ └─────────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

### 5.2 Program Detail

```
┌─────────────────────────────────┐
│ ←                          ⋮   │
├─────────────────────────────────┤
│                                 │
│ ┌─────────────────────────────┐ │
│ │         🧠                  │ │
│ │    Program Artwork          │ │
│ └─────────────────────────────┘ │
│                                 │
│ 7-Day Anxiety Relief            │
│ CBT techniques for managing     │
│ worry and anxious thoughts      │
│                                 │
│ ┌────┐ ┌────┐ ┌────┐ ┌────┐    │
│ │ 7  │ │15m │ │CBT │ │Beg │    │
│ │days│ │/day│ │    │ │    │    │
│ └────┘ └────┘ └────┘ └────┘    │
│                                 │
│ ─────────────────────────────── │
│                                 │
│ What You'll Learn               │
│ • Identify anxious thought      │
│   patterns                      │
│ • Challenge catastrophic        │
│   thinking                      │
│ • Build a worry management      │
│   toolkit                       │
│                                 │
│ ─────────────────────────────── │
│                                 │
│ 🔬 Evidence Base                │
│ Based on CBT protocols with     │
│ demonstrated effectiveness in   │
│ randomized controlled trials.   │
│ [Learn more →]                  │
│                                 │
│ ─────────────────────────────── │
│                                 │
│ Program Structure               │
│ □ Day 1: Understanding Anxiety  │
│ □ Day 2: Thought Awareness      │
│ □ Day 3: The Thought Record     │
│ □ Day 4: Cognitive Distortions  │
│ □ Day 5: Challenging Thoughts   │
│ □ Day 6: Behavioral Experiments │
│ □ Day 7: Your Anxiety Toolkit   │
│                                 │
│ ─────────────────────────────── │
│                                 │
│   [Start Program]               │
│   Includes pre-assessment       │
│                                 │
└─────────────────────────────────┘
```

### 5.3 Assessment Screen

```
┌─────────────────────────────────┐
│ PHQ-9 Assessment           1/9  │
├─────────────────────────────────┤
│                                 │
│ Over the last 2 weeks, how      │
│ often have you been bothered    │
│ by the following?               │
│                                 │
│ ─────────────────────────────── │
│                                 │
│ Little interest or pleasure     │
│ in doing things                 │
│                                 │
│ ○ Not at all                    │
│ ○ Several days                  │
│ ○ More than half the days       │
│ ● Nearly every day              │
│                                 │
│                                 │
│                                 │
│                                 │
│                                 │
│                                 │
│ ━━━━━━━━━━━●━━━━━━━━━━━━━━━━━━ │
│ Progress: 1 of 9                │
│                                 │
│           [Next →]              │
│                                 │
└─────────────────────────────────┘
```

### 5.4 Thought Record Exercise

```
┌─────────────────────────────────┐
│ ← Thought Record           💾   │
├─────────────────────────────────┤
│                                 │
│ Step 1 of 6                     │
│ ━━━━●━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                 │
│ Describe the Situation          │
│                                 │
│ What happened? Where were you?  │
│ Who was involved?               │
│                                 │
│ ┌─────────────────────────────┐ │
│ │                             │ │
│ │ Boss criticized my work in  │ │
│ │ front of the team during    │ │
│ │ today's meeting...          │ │
│ │                             │ │
│ │                             │ │
│ └─────────────────────────────┘ │
│                                 │
│ 💡 Tip: Be specific about       │
│ what happened, not how you      │
│ felt about it.                  │
│                                 │
│                                 │
│                                 │
│ [Back]              [Next →]    │
│                                 │
└─────────────────────────────────┘
```

### 5.5 Progress Dashboard

```
┌─────────────────────────────────┐
│ ← Program Progress              │
├─────────────────────────────────┤
│                                 │
│ 7-Day Anxiety Relief            │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ Day 5 of 7                  │ │
│ │ ████████████████░░░░ 71%   │ │
│ │ 🔥 5-day streak             │ │
│ └─────────────────────────────┘ │
│                                 │
│ Today's Modules                 │
│ ┌─────────────────────────────┐ │
│ │ ✓ Day 5: Challenging Thoughts│
│ │   Video • 8 min • Completed │ │
│ ├─────────────────────────────┤ │
│ │ → Thought Record Practice   │ │
│ │   Exercise • 10 min         │ │
│ │   [Continue →]              │ │
│ ├─────────────────────────────┤ │
│ │ □ Daily Reflection          │ │
│ │   Reflection • 5 min        │ │
│ └─────────────────────────────┘ │
│                                 │
│ Your Progress                   │
│ ┌─────────────────────────────┐ │
│ │ 📊 Assessment Scores        │ │
│ │ Pre: 15 (moderate)          │ │
│ │ Week 1: 12 (mild) ↓ -3      │ │
│ │                             │ │
│ │ 📝 8 Thought Records        │ │
│ │ ✓ 4/5 Practice Tasks Done   │ │
│ └─────────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

---

## 6. Acceptance Criteria

### 6.1 Program Discovery

- [ ] User can browse all available programs
- [ ] User can filter programs by methodology, duration, difficulty
- [ ] Premium programs show lock icon for free users
- [ ] Evidence badge displays for clinically-validated programs
- [ ] Personalized recommendations appear based on mood history

### 6.2 Enrollment & Assessment

- [ ] User can enroll in a program
- [ ] Pre-assessment (PHQ-9 or GAD-7) is required before starting
- [ ] Assessment score and interpretation are displayed
- [ ] High scores (severe range) trigger safety flag
- [ ] User can pause and resume enrollment

### 6.3 Daily Modules

- [ ] User sees today's modules on program dashboard
- [ ] User can complete modules in order
- [ ] Module progress is saved in real-time
- [ ] Practice tasks are tracked separately
- [ ] Catch-up mode allows completing missed days

### 6.4 Interactive Exercises

- [ ] Thought Record guides user through all 6 steps
- [ ] Cognitive distortions are selectable with explanations
- [ ] AI feedback is generated after thought record completion
- [ ] Values assessment covers all life domains
- [ ] Exercise data is saved and retrievable

### 6.5 Progress & Completion

- [ ] Progress bar shows completion percentage
- [ ] Post-assessment administered on final day
- [ ] Pre/post comparison displayed
- [ ] Certificate generated upon completion
- [ ] Achievement badge awarded
- [ ] XP (500+) awarded for program completion

---

## 7. Edge Cases & Error Handling

| Scenario                         | Behavior                                                                 |
| -------------------------------- | ------------------------------------------------------------------------ |
| User misses a day                | Show catch-up prompt; allow completing previous day                      |
| User abandons program            | After 7 days inactive, mark as "paused"; send re-engagement notification |
| Assessment score spikes severely | Flag for review; show crisis resources; suggest professional help        |
| User starts second program       | Allow multiple concurrent enrollments (warn about workload)              |
| Content not loading              | Show cached module if available; clear error with retry                  |
| AI feedback fails                | Show generic encouragement; retry in background                          |
| User disputes AI feedback        | Allow flagging; log for review                                           |

---

## 8. Security Considerations

| Area              | Requirement                                                  |
| ----------------- | ------------------------------------------------------------ |
| Assessment Data   | Encrypted at rest; RLS enforced; no third-party sharing      |
| Thought Records   | Highly sensitive; never used for AI training without consent |
| Clinical Scores   | Not shared with enterprise admins (only aggregate)           |
| Export            | User can export all data; HIPAA-ready architecture           |
| Therapist Sharing | Explicit consent required; revocable                         |
| Safety Flags      | Only accessible to designated safety reviewers               |

---

## 9. Performance Requirements

| Metric                 | Target                    |
| ---------------------- | ------------------------- |
| Module load time       | < 2 seconds               |
| Assessment submission  | < 1 second                |
| AI feedback generation | < 5 seconds               |
| Progress sync          | Real-time (optimistic UI) |
| Certificate generation | < 10 seconds              |
| Program library load   | < 1 second (paginated)    |

---

## 10. Dependencies

### 10.1 Internal

| Dependency           | Reason                   |
| -------------------- | ------------------------ |
| Achievement Service  | XP and badge awards      |
| AI Chat Service      | Thought record feedback  |
| Notification Manager | Program reminders        |
| PDF Generation       | Certificates             |
| Insights Module      | Assessment trend display |

### 10.2 External

| Dependency            | Reason                     |
| --------------------- | -------------------------- |
| Clinical Consultation | Program content validation |
| Legal Review          | HIPAA/privacy compliance   |
| Content Production    | Video/audio modules        |

---

## 11. Launch Programs (MVP)

| Program              | Methodology | Duration | Target             |
| -------------------- | ----------- | -------- | ------------------ |
| 7-Day Anxiety Relief | CBT         | 7 days   | Anxiety            |
| 14-Day Mood Boost    | CBT         | 14 days  | Depression         |
| DBT Skills Starter   | DBT         | 14 days  | Emotion regulation |
| Living Your Values   | ACT         | 7 days   | Purpose/meaning    |
| Stress Less          | Mixed       | 7 days   | Stress             |

---

## 12. Rollout Plan

### Phase 1: Foundation (Week 1-3)

- Database schema and migrations
- Program and module CRUD
- Basic enrollment flow

### Phase 2: Assessments (Week 4-5)

- PHQ-9 and GAD-7 implementation
- Score calculation and interpretation
- Safety flagging system

### Phase 3: Exercises (Week 6-8)

- Thought Record interactive exercise
- Values clarification exercise
- AI feedback integration

### Phase 4: Progress (Week 9-10)

- Progress dashboard
- Certificate generation
- Achievement integration
- Post-program recommendations
