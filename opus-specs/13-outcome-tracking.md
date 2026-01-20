# Outcome Tracking & Clinical Validation

> Measure real mental health outcomes with validated assessments and progress tracking.

**Priority:** P2 - Enhancement
**Effort:** Medium (4-5 weeks)
**Impact:** Clinical credibility; outcomes data for marketing & research

---

## 1. Overview

### 1.1 What It Does

A comprehensive outcome measurement system featuring:

- Periodic validated assessments (PHQ-9, GAD-7, WHO-5, PSS-10)
- Automatic scheduling and reminders
- Progress visualization over time
- Exportable clinical reports
- Research-grade data collection

### 1.2 Why It Exists

- **Clinical Credibility:** Validated assessments prove real impact
- **User Motivation:** Seeing progress reinforces engagement
- **Marketing Claims:** "85% of users report reduced anxiety" backed by data
- **Research Partnerships:** Enables academic collaboration
- **Insurance/Employer Sales:** Demonstrable ROI for B2B

### 1.3 Success Metrics

| Metric                | Target        | Measurement          |
| --------------------- | ------------- | -------------------- |
| Assessment completion | 70%+ prompted | Completed / Reminded |
| Score improvement     | 30%+ improve  | Baseline vs 8-week   |
| Report exports        | 10% of users  | Export actions       |
| Therapist shares      | 5% of users   | Share-with-therapist |

---

## 2. Functional Requirements

### 2.1 Assessment Types

| Assessment | Full Name                           | Questions | Measures          | Frequency |
| ---------- | ----------------------------------- | --------- | ----------------- | --------- |
| PHQ-9      | Patient Health Questionnaire        | 9         | Depression        | Bi-weekly |
| GAD-7      | Generalized Anxiety Disorder        | 7         | Anxiety           | Bi-weekly |
| WHO-5      | WHO Well-Being Index                | 5         | Well-being        | Weekly    |
| PSS-10     | Perceived Stress Scale              | 10        | Stress            | Monthly   |
| WEMWBS     | Warwick-Edinburgh Mental Well-being | 14        | Mental well-being | Monthly   |

### 2.2 Core Features

| ID    | Requirement                      | Priority |
| ----- | -------------------------------- | -------- |
| OT-01 | Complete validated assessments   | Must     |
| OT-02 | Automated assessment scheduling  | Must     |
| OT-03 | Progress charts over time        | Must     |
| OT-04 | Score interpretation with ranges | Must     |
| OT-05 | Reminders for due assessments    | Must     |
| OT-06 | Baseline vs current comparison   | Must     |
| OT-07 | Export PDF report                | Should   |
| OT-08 | Share report with therapist      | Should   |
| OT-09 | Goal setting based on scores     | Should   |
| OT-10 | Correlate scores with app usage  | Could    |

### 2.3 Assessment Flow

| ID    | Requirement                        | Priority |
| ----- | ---------------------------------- | -------- |
| AF-01 | Clear progress indicator           | Must     |
| AF-02 | One question per screen            | Must     |
| AF-03 | Back button without losing answers | Must     |
| AF-04 | Skip assessment option             | Must     |
| AF-05 | Immediate score after completion   | Must     |
| AF-06 | Interpretation text                | Must     |
| AF-07 | Suggested actions based on score   | Should   |

---

## 3. Technical Requirements

### 3.1 Data Models

```sql
-- Assessment definitions
CREATE TABLE assessment_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE, -- 'PHQ9', 'GAD7', 'WHO5', etc.
    name TEXT NOT NULL,
    description TEXT,
    questions JSONB NOT NULL, -- Array of question objects
    scoring_ranges JSONB NOT NULL, -- Score interpretation ranges
    frequency_days INTEGER NOT NULL, -- How often to prompt
    is_active BOOLEAN DEFAULT true
);

-- User assessment responses
CREATE TABLE assessment_responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    assessment_type_id UUID NOT NULL REFERENCES assessment_types(id),

    -- Responses
    answers JSONB NOT NULL, -- {question_id: answer_value}
    total_score INTEGER NOT NULL,
    severity_level TEXT, -- 'minimal', 'mild', 'moderate', 'severe'

    -- Context
    is_baseline BOOLEAN DEFAULT false,
    notes TEXT,

    completed_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT valid_severity CHECK (
        severity_level IN ('minimal', 'mild', 'moderate', 'moderately_severe', 'severe')
    )
);

-- Assessment schedule
CREATE TABLE assessment_schedule (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    assessment_type_id UUID NOT NULL REFERENCES assessment_types(id),

    next_due_at TIMESTAMPTZ NOT NULL,
    last_completed_at TIMESTAMPTZ,
    reminder_sent BOOLEAN DEFAULT false,

    -- User preferences
    enabled BOOLEAN DEFAULT true,
    custom_frequency_days INTEGER, -- Override default

    UNIQUE(user_id, assessment_type_id)
);

-- Progress goals
CREATE TABLE outcome_goals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    assessment_type_id UUID NOT NULL REFERENCES assessment_types(id),

    target_score INTEGER NOT NULL,
    target_date DATE,
    baseline_score INTEGER NOT NULL,
    baseline_date DATE NOT NULL,

    achieved BOOLEAN DEFAULT false,
    achieved_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE assessment_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE assessment_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE assessment_schedule ENABLE ROW LEVEL SECURITY;
ALTER TABLE outcome_goals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Assessment types readable by all"
    ON assessment_types FOR SELECT
    USING (auth.role() = 'authenticated' AND is_active = true);

CREATE POLICY "Users manage own responses"
    ON assessment_responses FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users manage own schedule"
    ON assessment_schedule FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users manage own goals"
    ON outcome_goals FOR ALL
    USING (auth.uid() = user_id);

-- Indexes
CREATE INDEX idx_responses_user_date ON assessment_responses(user_id, completed_at DESC);
CREATE INDEX idx_schedule_due ON assessment_schedule(next_due_at) WHERE enabled = true;
```

### 3.2 Assessment Questions Data

```sql
-- PHQ-9 Example
INSERT INTO assessment_types (code, name, description, questions, scoring_ranges, frequency_days) VALUES (
    'PHQ9',
    'Patient Health Questionnaire-9',
    'A validated screening tool for depression severity',
    '[
        {"id": 1, "text": "Little interest or pleasure in doing things"},
        {"id": 2, "text": "Feeling down, depressed, or hopeless"},
        {"id": 3, "text": "Trouble falling or staying asleep, or sleeping too much"},
        {"id": 4, "text": "Feeling tired or having little energy"},
        {"id": 5, "text": "Poor appetite or overeating"},
        {"id": 6, "text": "Feeling bad about yourself - or that you are a failure"},
        {"id": 7, "text": "Trouble concentrating on things"},
        {"id": 8, "text": "Moving or speaking slowly, or being fidgety/restless"},
        {"id": 9, "text": "Thoughts that you would be better off dead or hurting yourself"}
    ]'::jsonb,
    '[
        {"min": 0, "max": 4, "level": "minimal", "label": "Minimal Depression"},
        {"min": 5, "max": 9, "level": "mild", "label": "Mild Depression"},
        {"min": 10, "max": 14, "level": "moderate", "label": "Moderate Depression"},
        {"min": 15, "max": 19, "level": "moderately_severe", "label": "Moderately Severe Depression"},
        {"min": 20, "max": 27, "level": "severe", "label": "Severe Depression"}
    ]'::jsonb,
    14
);

-- GAD-7 Example
INSERT INTO assessment_types (code, name, description, questions, scoring_ranges, frequency_days) VALUES (
    'GAD7',
    'Generalized Anxiety Disorder-7',
    'A validated screening tool for anxiety severity',
    '[
        {"id": 1, "text": "Feeling nervous, anxious, or on edge"},
        {"id": 2, "text": "Not being able to stop or control worrying"},
        {"id": 3, "text": "Worrying too much about different things"},
        {"id": 4, "text": "Trouble relaxing"},
        {"id": 5, "text": "Being so restless that it is hard to sit still"},
        {"id": 6, "text": "Becoming easily annoyed or irritable"},
        {"id": 7, "text": "Feeling afraid, as if something awful might happen"}
    ]'::jsonb,
    '[
        {"min": 0, "max": 4, "level": "minimal", "label": "Minimal Anxiety"},
        {"min": 5, "max": 9, "level": "mild", "label": "Mild Anxiety"},
        {"min": 10, "max": 14, "level": "moderate", "label": "Moderate Anxiety"},
        {"min": 15, "max": 21, "level": "severe", "label": "Severe Anxiety"}
    ]'::jsonb,
    14
);
```

### 3.3 Swift Models

```swift
struct AssessmentType: Codable, Identifiable {
    let id: UUID
    let code: String
    let name: String
    let description: String?
    let questions: [AssessmentQuestion]
    let scoringRanges: [ScoringRange]
    let frequencyDays: Int
}

struct AssessmentQuestion: Codable, Identifiable {
    let id: Int
    let text: String
}

struct ScoringRange: Codable {
    let min: Int
    let max: Int
    let level: SeverityLevel
    let label: String
}

enum SeverityLevel: String, Codable, CaseIterable {
    case minimal
    case mild
    case moderate
    case moderatelySevere = "moderately_severe"
    case severe

    var color: Color {
        switch self {
        case .minimal: return .green
        case .mild: return .yellow
        case .moderate: return .orange
        case .moderatelySevere: return .red.opacity(0.7)
        case .severe: return .red
        }
    }
}

struct AssessmentResponse: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let assessmentTypeId: UUID
    let answers: [Int: Int] // questionId: answerValue (0-3)
    let totalScore: Int
    let severityLevel: SeverityLevel
    let isBaseline: Bool
    let notes: String?
    let completedAt: Date
}

struct AssessmentSchedule: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let assessmentTypeId: UUID
    let nextDueAt: Date
    let lastCompletedAt: Date?
    let reminderSent: Bool
    let enabled: Bool
    let customFrequencyDays: Int?
}

struct OutcomeGoal: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let assessmentTypeId: UUID
    let targetScore: Int
    let targetDate: Date?
    let baselineScore: Int
    let baselineDate: Date
    let achieved: Bool
    let achievedAt: Date?
}
```

### 3.4 Outcome Tracking Service

```swift
@MainActor
class OutcomeTrackingService: ObservableObject {
    private let supabase: SupabaseClient

    @Published var assessmentTypes: [AssessmentType] = []
    @Published var dueAssessments: [AssessmentSchedule] = []
    @Published var recentResponses: [AssessmentResponse] = []

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Fetch Assessment Types

    func fetchAssessmentTypes() async throws {
        let types: [AssessmentType] = try await supabase
            .from("assessment_types")
            .select()
            .eq("is_active", value: true)
            .execute()
            .value

        assessmentTypes = types
    }

    // MARK: - Check Due Assessments

    func fetchDueAssessments() async throws {
        let userId = try await supabase.auth.session.user.id

        let schedules: [AssessmentSchedule] = try await supabase
            .from("assessment_schedule")
            .select()
            .eq("user_id", value: userId)
            .eq("enabled", value: true)
            .lte("next_due_at", value: Date().ISO8601Format())
            .execute()
            .value

        dueAssessments = schedules
    }

    // MARK: - Submit Assessment

    func submitAssessment(
        typeId: UUID,
        answers: [Int: Int],
        notes: String? = nil
    ) async throws -> AssessmentResponse {
        let userId = try await supabase.auth.session.user.id

        guard let assessmentType = assessmentTypes.first(where: { $0.id == typeId }) else {
            throw OutcomeError.assessmentTypeNotFound
        }

        // Calculate score
        let totalScore = answers.values.reduce(0, +)

        // Determine severity
        let severity = assessmentType.scoringRanges.first { range in
            totalScore >= range.min && totalScore <= range.max
        }?.level ?? .minimal

        // Check if this is baseline (first assessment of this type)
        let existingCount: Int = try await supabase
            .from("assessment_responses")
            .select("id", head: true, count: .exact)
            .eq("user_id", value: userId)
            .eq("assessment_type_id", value: typeId)
            .execute()
            .count ?? 0

        let isBaseline = existingCount == 0

        // Insert response
        let response: AssessmentResponse = try await supabase
            .from("assessment_responses")
            .insert([
                "user_id": userId.uuidString,
                "assessment_type_id": typeId.uuidString,
                "answers": answers,
                "total_score": totalScore,
                "severity_level": severity.rawValue,
                "is_baseline": isBaseline,
                "notes": notes as Any
            ])
            .select()
            .single()
            .execute()
            .value

        // Update schedule
        let nextDue = Date().addingTimeInterval(
            TimeInterval(assessmentType.frequencyDays * 24 * 60 * 60)
        )

        try await supabase
            .from("assessment_schedule")
            .upsert([
                "user_id": userId.uuidString,
                "assessment_type_id": typeId.uuidString,
                "next_due_at": nextDue.ISO8601Format(),
                "last_completed_at": Date().ISO8601Format(),
                "reminder_sent": false
            ])
            .execute()

        // Check goal achievement
        await checkGoalAchievement(typeId: typeId, score: totalScore)

        return response
    }

    // MARK: - Progress Data

    func fetchProgressData(
        typeId: UUID,
        dateRange: ClosedRange<Date>? = nil
    ) async throws -> [AssessmentResponse] {
        let userId = try await supabase.auth.session.user.id

        var query = supabase
            .from("assessment_responses")
            .select()
            .eq("user_id", value: userId)
            .eq("assessment_type_id", value: typeId)
            .order("completed_at", ascending: true)

        if let range = dateRange {
            query = query
                .gte("completed_at", value: range.lowerBound.ISO8601Format())
                .lte("completed_at", value: range.upperBound.ISO8601Format())
        }

        return try await query.execute().value
    }

    // MARK: - Goals

    func setGoal(typeId: UUID, targetScore: Int, targetDate: Date?) async throws {
        let userId = try await supabase.auth.session.user.id

        // Get baseline
        guard let baseline: AssessmentResponse = try await supabase
            .from("assessment_responses")
            .select()
            .eq("user_id", value: userId)
            .eq("assessment_type_id", value: typeId)
            .eq("is_baseline", value: true)
            .single()
            .execute()
            .value else {
            throw OutcomeError.noBaseline
        }

        try await supabase
            .from("outcome_goals")
            .insert([
                "user_id": userId.uuidString,
                "assessment_type_id": typeId.uuidString,
                "target_score": targetScore,
                "target_date": targetDate?.ISO8601Format() as Any,
                "baseline_score": baseline.totalScore,
                "baseline_date": baseline.completedAt.ISO8601Format()
            ])
            .execute()
    }

    private func checkGoalAchievement(typeId: UUID, score: Int) async {
        // Check if user hit their goal
        do {
            let userId = try await supabase.auth.session.user.id

            let goals: [OutcomeGoal] = try await supabase
                .from("outcome_goals")
                .select()
                .eq("user_id", value: userId)
                .eq("assessment_type_id", value: typeId)
                .eq("achieved", value: false)
                .execute()
                .value

            for goal in goals {
                if score <= goal.targetScore {
                    try await supabase
                        .from("outcome_goals")
                        .update(["achieved": true, "achieved_at": Date().ISO8601Format()])
                        .eq("id", value: goal.id)
                        .execute()
                }
            }
        } catch {
            print("Error checking goals: \(error)")
        }
    }

    // MARK: - Report Generation

    func generateReport() async throws -> OutcomeReport {
        let userId = try await supabase.auth.session.user.id

        var assessmentData: [String: AssessmentProgress] = [:]

        for type in assessmentTypes {
            let responses = try await fetchProgressData(typeId: type.id)

            guard let baseline = responses.first,
                  let latest = responses.last else { continue }

            let change = latest.totalScore - baseline.totalScore
            let percentChange = baseline.totalScore > 0
                ? Double(change) / Double(baseline.totalScore) * 100
                : 0

            assessmentData[type.code] = AssessmentProgress(
                assessmentType: type,
                baseline: baseline,
                latest: latest,
                allResponses: responses,
                scoreChange: change,
                percentChange: percentChange
            )
        }

        return OutcomeReport(
            userId: userId,
            generatedAt: Date(),
            assessmentProgress: assessmentData
        )
    }
}

struct AssessmentProgress {
    let assessmentType: AssessmentType
    let baseline: AssessmentResponse
    let latest: AssessmentResponse
    let allResponses: [AssessmentResponse]
    let scoreChange: Int
    let percentChange: Double

    var isImproved: Bool {
        // Lower scores are better for PHQ-9, GAD-7
        return scoreChange < 0
    }
}

struct OutcomeReport {
    let userId: UUID
    let generatedAt: Date
    let assessmentProgress: [String: AssessmentProgress]
}

enum OutcomeError: Error {
    case assessmentTypeNotFound
    case noBaseline
}
```

---

## 4. UI/UX Specifications

### 4.1 Assessment Home

```
┌─────────────────────────────────┐
│ Outcomes                    ⚙️   │
├─────────────────────────────────┤
│                                 │
│ Due Now                         │
│ ┌─────────────────────────────┐ │
│ │ 📋 PHQ-9 Depression Check   │ │
│ │ Takes ~2 minutes            │ │
│ │                [Start →]    │ │
│ └─────────────────────────────┘ │
│                                 │
│ Your Progress                   │
│                                 │
│ Depression (PHQ-9)              │
│ ┌─────────────────────────────┐ │
│ │  15 ──●                     │ │
│ │      ╲                      │ │
│ │  10 ──●──●                  │ │
│ │          ╲                  │ │
│ │   5 ──────●──●              │ │
│ │  Jan  Feb  Mar  Apr  May    │ │
│ │                             │ │
│ │ ↓ 10 pts improved           │ │
│ └─────────────────────────────┘ │
│                                 │
│ Anxiety (GAD-7)                 │
│ ┌─────────────────────────────┐ │
│ │ ↓ 6 pts • Mild → Minimal    │ │
│ │             [View Details →]│ │
│ └─────────────────────────────┘ │
│                                 │
│ [📄 Generate Report]            │
│                                 │
└─────────────────────────────────┘
```

### 4.2 Assessment Flow

```
┌─────────────────────────────────┐
│ ← PHQ-9                    3/9  │
├─────────────────────────────────┤
│                                 │
│ Over the last 2 weeks, how      │
│ often have you been bothered    │
│ by:                             │
│                                 │
│ "Feeling down, depressed,       │
│  or hopeless"                   │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ ○ Not at all         (0)    │ │
│ ├─────────────────────────────┤ │
│ │ ○ Several days       (1)    │ │
│ ├─────────────────────────────┤ │
│ │ ● More than half     (2)    │ │
│ ├─────────────────────────────┤ │
│ │ ○ Nearly every day   (3)    │ │
│ └─────────────────────────────┘ │
│                                 │
│          [← Back]  [Next →]     │
│                                 │
└─────────────────────────────────┘
```

### 4.3 Results Screen

```
┌─────────────────────────────────┐
│ Your PHQ-9 Results              │
├─────────────────────────────────┤
│                                 │
│            ┌─────────┐          │
│            │   8     │          │
│            │  ━━━━━  │          │
│            │  Mild   │          │
│            └─────────┘          │
│                                 │
│ Your score indicates mild       │
│ depression symptoms.            │
│                                 │
│ Progress from Baseline          │
│ ┌─────────────────────────────┐ │
│ │ Feb 1: 15 (Moderate)        │ │
│ │        ↓                    │ │
│ │ Today:  8 (Mild)            │ │
│ │                             │ │
│ │     ↓ 7 points improved     │ │
│ └─────────────────────────────┘ │
│                                 │
│ Recommended Actions             │
│ • Continue daily mood tracking  │
│ • Try the CBT thought journal   │
│ • Consider talking to someone   │
│                                 │
│ [Set Improvement Goal]          │
│ [Share with Therapist]          │
│                                 │
│           [Done]                │
│                                 │
└─────────────────────────────────┘
```

---

## 5. Acceptance Criteria

- [ ] Users can complete PHQ-9 and GAD-7 assessments
- [ ] Scores are calculated correctly
- [ ] Severity levels are displayed with proper colors
- [ ] Progress charts show all historical scores
- [ ] Baseline comparison is shown
- [ ] Due assessments trigger reminders
- [ ] Users can set improvement goals
- [ ] PDF reports can be generated
- [ ] Question 9 (self-harm) triggers appropriate response

---

## 6. Edge Cases & Error Handling

| Scenario                      | Handling                          |
| ----------------------------- | --------------------------------- |
| User exits mid-assessment     | Save progress, allow resume       |
| PHQ-9 Q9 scored 1+            | Show crisis resources immediately |
| Score worsens significantly   | Suggest professional support      |
| No baseline available         | First assessment becomes baseline |
| Assessment skipped repeatedly | Adjust reminder frequency         |

---

## 7. Rollout Plan

### Phase 1 (Week 1-2)

- Assessment data model
- PHQ-9 and GAD-7 implementation
- Basic scoring and results

### Phase 2 (Week 3-4)

- Progress visualization
- Scheduling and reminders
- Goal setting

### Phase 3 (Week 5)

- Report generation
- Therapist sharing
- WHO-5 and PSS-10 additions
