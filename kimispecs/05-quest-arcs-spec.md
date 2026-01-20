# Quest Arcs and Programs

## Step 1: Feature Analysis

### Core purpose and value proposition
- Provide multi-week quest journeys aligned to outcomes (stress, sleep, confidence).
- Increase long-term retention by framing quests as a cohesive path.

### Target users and use cases
- Users seeking structured improvement over time.
- Premium users who want deeper, guided programs.

### Dependencies / prerequisites
- Quest templates, quest preference system, XP and streaks.
- Existing quest completion and reflection flow.

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Quest Arcs
- **Description:** Multi-week programs that sequence quests into a themed journey with milestones and adaptive difficulty.
- **Business justification and user value:** Adds meaning and direction, improving retention and premium conversion.

### 2. Functional Requirements

#### FR1: Create and manage arcs
- User stories:
  - As a user, I want to join an arc so I have a structured program.
  - As a user, I want to pause an arc when I need a break.
- Acceptance criteria:
  - Users can browse and start an arc from a catalog.
  - Only one active arc at a time.
  - Users can pause or exit an arc.

#### FR2: Arc-driven quest selection
- User stories:
  - As a user, I want daily quests to match my active arc.
- Acceptance criteria:
  - When an arc is active, primary quests are selected from the arc pool.
  - Quick and alternate variants still work.
  - Arc progress advances when a quest is completed.

#### FR3: Milestones and rewards
- User stories:
  - As a user, I want milestone rewards so I feel progress.
- Acceptance criteria:
  - Milestones trigger badges or bonus XP.
  - A milestone recap is posted to the user’s feed or shown as a celebration.

### 3. Technical Specifications

#### Architecture and system design considerations
- Arc logic should live in the quest assignment Edge Function to guarantee consistency.

#### Data models and schemas (proposed)
- `quest_arcs`
  - `id` (uuid, pk)
  - `title` (text)
  - `description` (text)
  - `duration_days` (int)
  - `category` (text)
  - `is_premium` (bool)
- `quest_arc_steps`
  - `id` (uuid, pk)
  - `arc_id` (uuid, fk)
  - `quest_template_id` (uuid, fk)
  - `day_number` (int)
- `user_quest_arcs`
  - `id` (uuid, pk)
  - `user_id` (uuid, fk)
  - `arc_id` (uuid, fk)
  - `started_at` (timestamptz)
  - `paused_at` (timestamptz, nullable)
  - `completed_at` (timestamptz, nullable)
  - `current_day` (int)

#### API endpoints / interfaces
- Edge Function `get-quest-arcs` (GET)
- Edge Function `start-quest-arc` (POST)
- Edge Function `pause-quest-arc` (POST)

#### Integration points with existing systems
- Quest assignment function selects arc steps when active.
- XP/badges system for milestone rewards.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions
- Arc catalog list with filters (goal, duration, premium).
- Arc detail page showing progress timeline.
- Home card showing current arc day and next quest.

#### User flow diagram (text)
1. User opens Arc catalog.
2. Starts an arc.
3. Daily quests follow arc schedule.
4. Milestones trigger celebrations.
5. Arc completes and shows recap.

#### Accessibility requirements
- Dynamic Type support for arc cards and timeline.
- VoiceOver labels for progress indicators.

### 5. Edge Cases and Error Handling
- If arc quest template is missing, fallback to normal quest selection.
- If user skips a day, arc day increments only on completion.

### 6. Testing Requirements
- Unit tests: arc progression, step selection, milestone triggers.
- Integration tests: arc start/pause/complete endpoints.
- UAT: start arc, complete quests, milestone reward.

### 7. Implementation Notes
- Start with a small set of curated arcs (3-5).
- Keep arc step selection deterministic for consistency.
- Use RLS to restrict arc progress to owner.
