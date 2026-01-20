# Recovery Mode UX

## Step 1: Feature Analysis

### Core purpose and value proposition
- Reduce cognitive load and pressure when a user is in a low-energy or high-stress period.
- Provide a gentler interface that prioritizes support, short actions, and safety.

### Target users and use cases
- Users showing a negative mood trend or low energy streak.
- Users who self-identify as needing a lighter experience.

### Dependencies / prerequisites
- Mood history and weekly summaries.
- User settings (quiet hours, notifications).
- Crisis flow and resources (must remain available).

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Recovery Mode UX
- **Description:** A temporary, low-friction app experience triggered by mood trends or user choice. It simplifies the home surface, reduces prompts, and offers short, supportive actions.
- **Business justification and user value:** Improves retention during difficult periods by reducing overwhelm and guilt, increasing user trust.

### 2. Functional Requirements

#### FR1: Trigger and exit recovery mode
- User stories:
  - As a user, I want Recovery Mode to turn on automatically when I am struggling.
  - As a user, I want to exit Recovery Mode when I feel ready.
- Acceptance criteria:
  - Recovery Mode can be activated automatically based on mood trend rules.
  - Users can enable or disable Recovery Mode manually in settings.
  - A clear exit action is provided on the Home screen.

#### FR2: Simplified home experience
- User stories:
  - As a user, I want fewer choices so I can act without thinking too much.
- Acceptance criteria:
  - Home shows at most three actions: quick check-in, coping kit, and a short quest or exercise.
  - Streak and achievement messaging is softened and non-pressuring.
  - Any upsell messaging is hidden while Recovery Mode is active.

#### FR3: Gentle notifications
- User stories:
  - As a user, I want fewer notifications during recovery so I feel supported, not pressured.
- Acceptance criteria:
  - Notification frequency is reduced by at least 50 percent while Recovery Mode is active.
  - Notifications are not sent during quiet hours.

### 3. Technical Specifications

#### Architecture and system design considerations
- Recovery mode state is stored server-side to keep behavior consistent across devices.
- Trigger evaluation runs in a Supabase Edge Function and updates user state.

#### Data models and schemas (proposed)
- `user_settings` additions:
  - `recovery_mode_enabled` (bool)
  - `recovery_mode_triggered_at` (timestamptz, nullable)
  - `recovery_mode_source` (text: auto | manual)

#### API endpoints / interfaces
- Edge Function `evaluate-recovery-mode` (POST)
  - Input: `{ userId, moodWindowDays }`
  - Output: `{ recoveryModeEnabled, reason }`
- Data service update: `updateRecoveryMode(enabled: Bool, source: String)`

#### Integration points with existing systems
- Home view uses recovery mode state to switch layout.
- Notification scheduling respects recovery mode state.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions
- Recovery banner at top of Home with a calm explanation and an exit button.
- Compact action stack with three large buttons.
- Muted color palette and reduced visual density in Recovery Mode.

#### User flow diagram (text)
1. Mood trend detected or user toggles Recovery Mode.
2. Home switches to Recovery Mode layout.
3. User completes a small action or coping kit.
4. User exits Recovery Mode manually or after a fixed period.

#### Accessibility requirements
- Dynamic Type supported for all Recovery Mode cards.
- VoiceOver labels for the Recovery Mode banner and exit action.

### 5. Edge Cases and Error Handling
- If automatic trigger fails, leave current mode unchanged and log error.
- Recovery Mode should never block crisis resources.
- If mood data is missing, do not auto-enable.

### 6. Testing Requirements
- Unit tests: trigger rules, home layout selection, notification throttling.
- Integration tests: setting updates and server evaluation.
- UAT: enter recovery mode, verify UI, exit, and confirm normal UI returns.

### 7. Implementation Notes
- Use conservative thresholds to avoid false positives.
- Store a short rationale string for user transparency.
- Provide a minimum duration (for example, 24 hours) to prevent rapid toggling.
