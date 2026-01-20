# Proactive Coping Kits

## Step 1: Feature Analysis

### Core purpose and value proposition
- Provide instant, low-friction support bundles for anxious or low-energy moments.
- Reduce time-to-relief by bundling micro-actions in a single tap.

### Target users and use cases
- Users experiencing acute stress or anxiety.
- Users who want quick, guided support without browsing.

### Dependencies / prerequisites
- Exercise library and quest templates.
- Chat entry point for guided support.
- Home view surface for quick access.

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Coping Kits
- **Description:** One-tap bundles containing a short exercise, a grounding prompt, and an optional chat check-in. Kits are tailored by context (stress, sleep, low energy).
- **Business justification and user value:** Delivers immediate relief, increasing perceived efficacy and daily engagement.

### 2. Functional Requirements

#### FR1: Kit selection and launch
- User stories:
  - As a user, I want to launch a coping kit instantly so I can calm down quickly.
- Acceptance criteria:
  - Kits are accessible from Home and Chat.
  - Each kit contains 2-3 steps totaling 3-8 minutes.

#### FR2: Kit personalization
- User stories:
  - As a user, I want kits to match my situation so they feel relevant.
- Acceptance criteria:
  - Kits are labeled by context (stress, overwhelm, sleep, energy).
  - Kits can be pinned for quick access.

#### FR3: Completion and feedback
- User stories:
  - As a user, I want to finish a kit and feel closure.
- Acceptance criteria:
  - A simple completion summary appears after the last step.
  - Optional thumbs up/down feedback is collected.

### 3. Technical Specifications

#### Architecture and system design considerations
- Kits are stored as predefined templates with references to exercises and prompts.

#### Data models and schemas (proposed)
- `coping_kits`
  - `id` (uuid, pk)
  - `title` (text)
  - `context_tag` (text)
  - `steps` (jsonb)
  - `is_premium` (bool)
- `user_coping_kits`
  - `id` (uuid, pk)
  - `user_id` (uuid, fk)
  - `kit_id` (uuid, fk)
  - `pinned` (bool)
  - `last_used_at` (timestamptz)

#### API endpoints / interfaces
- Edge Function `get-coping-kits` (GET)
- Edge Function `track-coping-kit` (POST)

#### Integration points with existing systems
- Exercise sessions and quests for steps.
- Chat for optional final reflection.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions
- Home “Coping Kit” card with 3 quick options.
- Kit detail screen showing steps and time estimate.
- Completion screen with supportive message.

#### User flow diagram (text)
1. User taps a kit.
2. Completes 2-3 steps.
3. Sees completion summary.

#### Accessibility requirements
- Dynamic Type for step descriptions.
- VoiceOver labels for kit steps.

### 5. Edge Cases and Error Handling
- If a kit step references missing content, fallback to a generic breathing step.
- If the user exits mid-kit, allow resume later.

### 6. Testing Requirements
- Unit tests: kit template parsing, pinned kit persistence.
- Integration tests: kit usage tracking and exercise session creation.
- UAT: launch kit, complete steps, save feedback.

### 7. Implementation Notes
- Start with 4-5 curated kits.
- Keep total time under 8 minutes for most kits.
