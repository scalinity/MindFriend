# Action Autopilot (Mood to Plan + Calendar)

## Step 1: Feature Analysis

### Core purpose and value proposition
- Turn mood logs and weekly insights into a short, actionable plan that reduces decision fatigue.
- Increase follow-through by scheduling plans into the user’s real day and respecting quiet hours.

### Target users and use cases
- Users who want guidance immediately after a mood check-in.
- Users who need gentle structure during low-energy days.
- Premium users seeking a more personalized, proactive experience.

### Dependencies / prerequisites
- Mood check-in data, weekly summary data, quest templates, exercise library.
- Quiet hours preferences and push notification infrastructure.
- iOS EventKit permission flow for calendar scheduling.
- Supabase Edge Functions for AI plan generation (no AI calls from client).

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Action Autopilot
- **Description:** Generates a 5-15 minute micro-plan after key triggers (mood check-in, weekly summary, or manual request) and optionally schedules it into the user’s calendar with reminders. Plans are lightweight, editable, and aligned to the user’s preferences.
- **Business justification and user value:** Converts insight into action, improving retention and daily engagement while providing a premium-feeling concierge experience.

### 2. Functional Requirements

#### FR1: Generate an action plan from user signals
- User stories:
  - As a user, I want a plan right after a mood check-in so that I can take action while motivation is high.
  - As a user, I want plans tailored to my preferences so that they feel relevant and achievable.
- Acceptance criteria:
  - A plan can be generated from mood check-in, weekly summary, or a manual “Generate Plan” button.
  - The plan contains 2-4 items totaling 5-15 minutes by default.
  - Plans can include quests, exercises, or a short AI chat prompt.
  - If AI generation fails, a deterministic fallback plan is produced.

#### FR2: Allow plan customization
- User stories:
  - As a user, I want to swap an item so that the plan fits my day.
  - As a user, I want a “quick plan” option when I have limited time.
- Acceptance criteria:
  - Users can swap or remove any plan item before scheduling.
  - Users can choose Quick (5-8 min) or Standard (10-15 min) plans.
  - Users can regenerate a plan once per day.

#### FR3: Schedule plan with reminders
- User stories:
  - As a user, I want to schedule my plan so that it fits into my calendar.
  - As a user, I want reminders that respect my quiet hours.
- Acceptance criteria:
  - Scheduling uses EventKit with explicit permission prompts.
  - Reminders are created as local notifications if calendar permission is denied.
  - Scheduled times are adjusted to avoid quiet hours.
  - The user can cancel a scheduled plan at any time.

#### FR4: Track completion and feedback
- User stories:
  - As a user, I want to mark items complete so I can see progress.
  - As a user, I want to rate a plan so future plans improve.
- Acceptance criteria:
  - Each plan item can be marked complete or skipped.
  - A completion summary is shown after the last item.
  - Optional feedback (thumbs up/down) is saved.

### 3. Technical Specifications

#### Architecture and system design considerations
- Plan generation runs in a Supabase Edge Function and returns a structured plan object.
- Scheduling and reminders live on-device (EventKit + UNUserNotificationCenter) with quiet hours applied from user settings.

#### Data models and schemas (proposed)
- `action_plans`
  - `id` (uuid, pk)
  - `user_id` (uuid, fk)
  - `source_type` (text: mood_checkin | weekly_summary | manual)
  - `created_at` (timestamptz)
  - `scheduled_for` (timestamptz, nullable)
  - `timezone` (text)
  - `status` (text: draft | scheduled | completed | cancelled)
- `action_plan_items`
  - `id` (uuid, pk)
  - `plan_id` (uuid, fk)
  - `item_type` (text: quest | exercise | chat)
  - `reference_id` (uuid, nullable)
  - `title` (text)
  - `duration_minutes` (int)
  - `sort_order` (int)
  - `completed_at` (timestamptz, nullable)
- `action_plan_feedback`
  - `id` (uuid, pk)
  - `plan_id` (uuid, fk)
  - `rating` (int, nullable)
  - `notes` (text, nullable)

#### API endpoints / interfaces
- Edge Function `generate-action-plan` (POST)
  - Input: `{ sourceType, moodContextId?, weeklySummaryId?, planSize, timezone }`
  - Output: `{ plan, items[] }`
- Edge Function `record-action-plan` (POST)
  - Input: `{ planId, status, itemsCompleted[], feedback? }`

#### Integration points with existing systems
- Trigger from `MoodCheckInView` and weekly summary screen.
- Uses quest templates and exercise library data.
- Uses quiet hours stored in `user_settings`.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions
- Post check-in: show a bottom sheet with “Your Action Plan” and a time estimate.
- Home: “Today’s Plan” card showing progress (0/3, 2/3).
- Edit screen: list of plan items with swap and remove actions.
- Scheduling sheet: time picker with quiet hours warning.

#### User flow diagram (text)
1. User completes mood check-in.
2. Action plan sheet appears with Quick/Standard options.
3. User edits items and taps “Schedule” or “Start Now.”
4. App schedules calendar/reminders and returns to Home.
5. User completes items and sees a completion summary.

#### Accessibility requirements
- Support Dynamic Type for all plan text and buttons.
- VoiceOver labels for time pickers and plan items.
- Minimum 44x44 touch targets.

### 5. Edge Cases and Error Handling
- If calendar permission is denied, use local notifications and explain the fallback.
- If quiet hours block the selected time, auto-shift to the next available slot and notify user.
- If plan generation fails, show a friendly error and use a predefined fallback plan.

### 6. Testing Requirements
- Unit tests: plan generation rules, quiet hours adjustment logic, fallback plan creation.
- Integration tests: Edge Function response structure, Supabase insert/update of plan records.
- UAT: create plan after mood check-in, edit items, schedule, complete, and rate.

### 7. Implementation Notes
- Start with a deterministic plan generator and layer in AI for personalization.
- Cache recommended plan items to avoid repeated AI calls.
- Keep plan structure compatible with existing quest and exercise data models.
- Ensure RLS policies restrict access to the user’s own plans.
