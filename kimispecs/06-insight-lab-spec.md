# Insight Lab Experiments

## Step 1: Feature Analysis

### Core purpose and value proposition
- Help users learn which habits improve mood or energy by running short experiments.
- Turn wellness into measurable, motivating insights.

### Target users and use cases
- Data-curious users who want to test routines (morning journaling vs evening).
- Users seeking evidence of improvement over 7 days.

### Dependencies / prerequisites
- Mood and quest history data.
- Weekly summary or outcome tracking data.
- Notification scheduling for reminders.

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Insight Lab
- **Description:** Users run 7-day experiments comparing a chosen routine and receive a simple outcome report highlighting mood and energy changes.
- **Business justification and user value:** Creates a unique, science-backed experience that boosts engagement and perceived efficacy.

### 2. Functional Requirements

#### FR1: Start an experiment
- User stories:
  - As a user, I want to choose an experiment so I can test a habit.
- Acceptance criteria:
  - Experiments have a name, duration (7 days), and a specific action.
  - Only one active experiment at a time.

#### FR2: Track adherence and outcomes
- User stories:
  - As a user, I want reminders so I remember the experiment action.
  - As a user, I want to see how my mood changed during the experiment.
- Acceptance criteria:
  - Daily adherence is tracked (done or skipped).
  - Mood and energy are compared to a baseline week.

#### FR3: Experiment report
- User stories:
  - As a user, I want a summary report so I understand results.
- Acceptance criteria:
  - Report includes adherence rate, mood delta, and a recommended next step.
  - Report can be saved or shared.

### 3. Technical Specifications

#### Architecture and system design considerations
- Experiment logic is driven by a server-side schedule and simple analytics queries.

#### Data models and schemas (proposed)
- `insight_experiments`
  - `id` (uuid, pk)
  - `user_id` (uuid, fk)
  - `title` (text)
  - `action_type` (text)
  - `started_at` (timestamptz)
  - `ended_at` (timestamptz, nullable)
  - `status` (text: active | completed | cancelled)
- `insight_experiment_days`
  - `id` (uuid, pk)
  - `experiment_id` (uuid, fk)
  - `day_index` (int)
  - `completed` (bool)
  - `mood_score` (int, nullable)
  - `energy_score` (int, nullable)

#### API endpoints / interfaces
- Edge Function `start-insight-experiment` (POST)
- Edge Function `record-experiment-day` (POST)
- Edge Function `generate-experiment-report` (POST)

#### Integration points with existing systems
- Uses mood check-in data.
- Uses notification scheduling to send experiment reminders.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions
- Experiment catalog with a simple list of 5-7 curated experiments.
- Daily check-in card with a single “Done” action.
- Report card with clear metrics and next steps.

#### User flow diagram (text)
1. User selects experiment.
2. Daily reminders and “Done” tracking.
3. Report generated after day 7.

#### Accessibility requirements
- Dynamic Type for all experiment labels.
- VoiceOver support for report metrics.

### 5. Edge Cases and Error Handling
- If baseline data is missing, show a reduced report without comparisons.
- If user misses multiple days, allow early exit.

### 6. Testing Requirements
- Unit tests: adherence tracking, report generation.
- Integration tests: experiment CRUD endpoints.
- UAT: start experiment, log days, see report.

### 7. Implementation Notes
- Use small, curated experiment set to start.
- Keep report language encouraging and non-judgmental.
