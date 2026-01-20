# Daily/Weekly Summary Emails

> Personalized digest emails to re-engage users and celebrate progress.

**Priority:** P3 - Nice to Have
**Effort:** Low (1-2 weeks)
**Impact:** Re-engagement channel; user retention

**Version:** 2.0 (Revised)
**Last Updated:** 2026-01-19
**Status:** Ready for Implementation

---

## 1. Overview

### 1.1 What It Does

Automated personalized email summaries that:

- Send weekly wellness progress digests on Sundays
- Celebrate streak milestones (7/14/30/60/90/180/365 days)
- Re-engage lapsed users with gentle nudges (3/7/14 days inactive)
- Deliver monthly outcome report summaries
- Notify users of achievement unlocks

### 1.2 Why It Exists

- **Re-engagement:** Email is a proven retention channel for dormant users
- **Celebration:** Reinforce positive behaviors and progress milestones
- **Visibility:** Keep MindFriend top-of-mind between app sessions
- **Low Friction:** Passive engagement without requiring app open
- **Measurement:** Trackable metrics for feature optimization

### 1.3 Success Metrics

| Metric               | Target | Measurement                    |
| -------------------- | ------ | ------------------------------ |
| Email open rate      | 35%+   | Opens / Sent                   |
| Click-through rate   | 15%+   | Clicks / Opens                 |
| Re-engagement rate   | 10%+   | Lapsed users return within 48h |
| Unsubscribe rate     | <2%    | Unsubscribes / Sent            |
| Deliverability rate  | >95%   | Delivered / Sent               |
| Deep link conversion | 20%+   | App opens / Email clicks       |

---

## 2. Functional Requirements

### 2.1 Email Types

| Type               | Trigger                              | Frequency | Deep Link Destination               |
| ------------------ | ------------------------------------ | --------- | ----------------------------------- |
| Weekly Summary     | Sunday 9am user local time           | Weekly    | `/home` (Home tab)                  |
| Streak Celebration | 7/14/30/60/90/180/365-day streak hit | Event     | `/achievements` (Achievements view) |
| Achievement Unlock | Badge earned                         | Event     | `/achievements` (Achievements view) |
| Lapsed User Nudge  | 3/7/14 days inactive                 | Event     | `/quests` (Quest tab)               |
| Monthly Report     | 1st of month, 9am user local time    | Monthly   | `/profile/stats` (Stats dashboard)  |

**Delivery Window:** All emails respect user's `preferred_send_hour` (default: 9am) in their configured timezone.

### 2.2 Core Features

#### SE-01: Weekly Progress Summary Email

**Description:** Send personalized weekly digest to users every Sunday at their preferred time.

**Priority:** Must Have

**Acceptance Criteria:**

- **AC-1.1:** GIVEN user has `emails_enabled = true` AND `weekly_summary = true` AND completed at least 1 quest in past 7 days AND `preferred_send_hour` has passed in user's timezone
  WHEN weekly email cron job runs at Sunday 9am UTC
  THEN email is queued in `email_queue` with `scheduled_for` = next occurrence of (Sunday at `preferred_send_hour` in user's timezone, converted to UTC)
  AND `payload` contains: `quests_completed`, `moods_logged`, `exercise_minutes`, `badges_earned`, `avg_mood`, `current_streak`

- **AC-1.2:** GIVEN user has not completed any quests in past 7 days
  WHEN weekly email cron runs
  THEN no email is queued
  AND row inserted to `email_logs` with `status = 'skipped'` AND `skipped_reason = 'no_activity'`

- **AC-1.3:** GIVEN user has `emails_enabled = false` OR `weekly_summary = false`
  WHEN weekly email cron runs
  THEN no email is queued
  AND no log entry created

- **AC-1.4:** GIVEN email is queued
  WHEN queue processor runs AND current time >= `scheduled_for`
  THEN email is rendered from template, sent via Resend API, logged to `email_logs` with `message_id`

#### SE-02: Streak Milestone Celebrations

**Description:** Automatically celebrate when user hits 7, 14, 30, 60, 90, 180, or 365-day streaks.

**Priority:** Must Have

**Acceptance Criteria:**

- **AC-2.1:** GIVEN user completes quest AND `current_streak` = 7, 14, 30, 60, 90, 180, or 365
  WHEN quest completion transaction commits
  THEN email is queued in `email_queue` with `email_type = 'streak_celebration'` AND `payload.milestone = {current_streak}`
  AND `scheduled_for = NOW()`

- **AC-2.2:** GIVEN user has `streak_celebrations = false`
  WHEN streak milestone is reached
  THEN no email is queued

- **AC-2.3:** GIVEN user has already received streak email for this milestone (check `email_logs`)
  WHEN milestone logic runs
  THEN no duplicate email is queued

#### SE-03: Lapsed User Re-engagement

**Description:** Gentle nudge emails for users who haven't opened the app in 3, 7, or 14 days.

**Priority:** Must Have

**Acceptance Criteria:**

- **AC-3.1:** GIVEN user has not completed quest in past 3 days AND has not received lapsed email in past 3 days AND `lapsed_nudges = true`
  WHEN lapsed-user cron job runs (daily at 10am UTC)
  THEN email is queued with `email_type = 'lapsed_nudge'` AND `payload.days_inactive = 3`

- **AC-3.2:** GIVEN user has not completed quest in past 7 days AND has not received lapsed email in past 7 days
  WHEN lapsed-user cron runs
  THEN email is queued with `payload.days_inactive = 7` AND subject line adjusted to "We miss you"

- **AC-3.3:** GIVEN user has not completed quest in past 14 days AND has not received lapsed email in past 14 days
  WHEN lapsed-user cron runs
  THEN email is queued with `payload.days_inactive = 14` AND subject line adjusted to "It's been a while"

- **AC-3.4:** GIVEN user completes quest after receiving lapsed nudge
  WHEN next lapsed-user cron runs
  THEN no further lapsed emails are sent (resets timer)

#### SE-04: Email Preference Management

**Description:** Users can control which emails they receive via in-app settings and web unsubscribe page.

**Priority:** Must Have

**Acceptance Criteria:**

- **AC-4.1:** GIVEN user navigates to Settings → Notifications → Email Preferences
  WHEN screen loads
  THEN toggles are shown for: `emails_enabled` (master switch), `weekly_summary`, `streak_celebrations`, `achievement_notifications`, `lapsed_nudges`, `monthly_report`
  AND current state reflects `email_preferences` table

- **AC-4.2:** GIVEN user toggles `emails_enabled = false`
  WHEN save action completes
  THEN all individual type toggles are disabled (grayed out)
  AND no emails are queued for this user regardless of individual settings

- **AC-4.3:** GIVEN user selects preferred send time (hour picker)
  WHEN saved
  THEN `preferred_send_hour` is updated in `email_preferences`
  AND future scheduled emails use new time

- **AC-4.4:** GIVEN user selects timezone from picker (IANA timezone list)
  WHEN saved
  THEN `timezone` is updated in `email_preferences`
  AND future scheduled emails use new timezone for calculating `scheduled_for`

#### SE-05: Unsubscribe with One Click

**Description:** RFC 8058 compliant one-click unsubscribe via email header link.

**Priority:** Must Have

**Acceptance Criteria:**

- **AC-5.1:** GIVEN user receives any MindFriend email
  WHEN they click "Unsubscribe" link in email footer
  THEN they are redirected to `https://getmindfriend.app/unsubscribe?token={unsubscribe_token}`
  AND page shows confirmation: "You've been unsubscribed from MindFriend emails"
  AND `emails_enabled = false` is set in `email_preferences`
  AND `unsubscribed_at = NOW()` is recorded

- **AC-5.2:** GIVEN email client supports RFC 8058 one-click unsubscribe
  WHEN user clicks client's native unsubscribe button
  THEN POST request is sent to `List-Unsubscribe` URL
  AND backend sets `emails_enabled = false` without requiring page visit

- **AC-5.3:** GIVEN user has unsubscribed
  WHEN any cron job or trigger attempts to queue email
  THEN no email is queued
  AND `email_logs` entry created with `status = 'skipped', skipped_reason = 'unsubscribed'`

#### SE-06: Personalized Content Based on Activity

**Description:** Email content dynamically adjusts based on user's recent activity patterns.

**Priority:** Should Have

**Acceptance Criteria:**

- **AC-6.1:** GIVEN user completed 0 exercises in past week
  WHEN weekly summary email is rendered
  THEN "exercise_minutes" section shows "Try your first breathing exercise this week!"
  AND CTA button links to `/exercises` with `?category=breathing`

- **AC-6.2:** GIVEN user logged moods 5+ times in past week
  WHEN weekly summary email is rendered
  THEN "moods_logged" section shows celebratory message "Great job checking in daily!"
  AND includes mood trend graph (if available)

- **AC-6.3:** GIVEN user earned badge in past week
  WHEN weekly summary email is rendered
  THEN "badges_earned" section lists badge names with badge icons
  AND links to `/achievements`

#### SE-07: Achievement Notification Emails

**Description:** Instant email when user earns a badge.

**Priority:** Should Have

**Acceptance Criteria:**

- **AC-7.1:** GIVEN user earns badge AND `achievement_notifications = true`
  WHEN badge is inserted to `user_badges` table
  THEN email is queued with `email_type = 'achievement'` AND `payload.badge_id`, `payload.badge_name`, `payload.badge_description`
  AND `scheduled_for = NOW()`

- **AC-7.2:** GIVEN badge is "Getting Started" category
  WHEN achievement email is sent
  THEN subject line is "You earned your first MindFriend badge!"
  AND email includes onboarding tips

- **AC-7.3:** GIVEN badge is streak-related (e.g., "7-Day Warrior")
  WHEN achievement email is sent
  THEN email also includes current streak count and next milestone

#### SE-08: Monthly Wellness Report

**Description:** Comprehensive monthly summary with outcome tracking data.

**Priority:** Should Have

**Acceptance Criteria:**

- **AC-8.1:** GIVEN user has `monthly_report = true` AND completed at least 1 outcome assessment in past month
  WHEN monthly cron job runs on 1st at 9am UTC
  THEN email is queued with `email_type = 'monthly_report'` AND `payload` contains: `quests_completed_month`, `moods_logged_month`, `exercise_minutes_month`, `badges_earned_month`, `outcome_scores` (PHQ-9, GAD-7, etc.)
  AND `scheduled_for` = 1st of month at `preferred_send_hour` in user's timezone

- **AC-8.2:** GIVEN user has not completed any outcome assessments in past month
  WHEN monthly cron runs
  THEN email is still sent but shows "Complete your monthly check-in to track progress" CTA
  AND links to `/outcomes/assessments`

- **AC-8.3:** GIVEN user has outcome score improvement (e.g., PHQ-9 decreased by 3+ points)
  WHEN monthly email is rendered
  THEN email highlights improvement with encouraging message
  AND includes trend chart

#### SE-09: Deep Links to Specific App Sections

**Description:** Email CTAs open specific app screens via universal links.

**Priority:** Should Have

**Acceptance Criteria:**

- **AC-9.1:** GIVEN user clicks CTA button in email (e.g., "View Your Progress")
  WHEN clicked on iOS device with MindFriend installed
  THEN universal link `https://getmindfriend.app/[path]` opens app directly to target screen
  AND deep link is handled by `handleUniversalLink()` in `MindFriendApp.swift`

- **AC-9.2:** GIVEN user clicks CTA on device without MindFriend installed
  WHEN clicked
  THEN web fallback page is shown at `https://getmindfriend.app/[path]`
  AND page shows "Download MindFriend" CTA linking to App Store

- **AC-9.3:** GIVEN email includes deep link with tracking parameter (e.g., `?utm_source=email&utm_campaign=weekly_summary`)
  WHEN link is clicked
  THEN app logs analytics event `email_link_clicked` with campaign metadata

**Deep Link Mapping:**

| Email Type         | Primary CTA Deep Link        | Fallback Web Page                         |
| ------------------ | ---------------------------- | ----------------------------------------- |
| Weekly Summary     | `mindfriend://home`          | `https://getmindfriend.app/home`          |
| Streak Celebration | `mindfriend://achievements`  | `https://getmindfriend.app/achievements`  |
| Achievement Unlock | `mindfriend://achievements`  | `https://getmindfriend.app/achievements`  |
| Lapsed Nudge       | `mindfriend://quests`        | `https://getmindfriend.app/quests`        |
| Monthly Report     | `mindfriend://profile/stats` | `https://getmindfriend.app/profile/stats` |

#### SE-10: A/B Testing Subject Lines

**Description:** Run experiments on subject lines to optimize open rates.

**Priority:** Could Have

**Acceptance Criteria:**

- **AC-10.1:** GIVEN A/B test is configured in `email_ab_tests` table (variant A vs B)
  WHEN email is queued
  THEN user is randomly assigned variant (50/50 split)
  AND `variant` field in `email_logs` records assignment
  AND subject line uses variant's text

- **AC-10.2:** GIVEN A/B test has run for 7 days
  WHEN admin views test results dashboard
  THEN open rates and CTR are shown for each variant
  AND statistical significance is calculated (p-value < 0.05)

- **AC-10.3:** GIVEN variant B has statistically significant higher open rate
  WHEN admin clicks "Promote Winner"
  THEN variant B becomes default subject line
  AND test is marked as "completed"

---

## 3. Technical Requirements

### 3.1 Data Models

#### 3.1.1 Database Schema

```sql
-- =====================================================
-- Email Preferences Table
-- =====================================================
CREATE TABLE email_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,

    -- Global toggle
    emails_enabled BOOLEAN DEFAULT true,

    -- Individual email types
    weekly_summary BOOLEAN DEFAULT true,
    streak_celebrations BOOLEAN DEFAULT true,
    achievement_notifications BOOLEAN DEFAULT true,
    lapsed_nudges BOOLEAN DEFAULT true,
    monthly_report BOOLEAN DEFAULT true,

    -- Delivery settings
    preferred_send_hour INTEGER DEFAULT 9 CHECK (preferred_send_hour >= 0 AND preferred_send_hour <= 23),
    timezone TEXT DEFAULT 'America/New_York', -- IANA timezone

    -- RFC 8058 compliant unsubscribe token
    unsubscribe_token UUID DEFAULT gen_random_uuid() UNIQUE NOT NULL,

    -- Unsubscribe tracking
    unsubscribed_at TIMESTAMPTZ,
    unsubscribe_reason TEXT,

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_email_prefs_user ON email_preferences(user_id);
CREATE INDEX idx_email_prefs_token ON email_preferences(unsubscribe_token);

-- =====================================================
-- Email Queue Table (with retry support)
-- =====================================================
CREATE TABLE email_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Email metadata
    email_type TEXT NOT NULL, -- 'weekly_summary', 'streak_celebration', etc.
    scheduled_for TIMESTAMPTZ NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    template_version TEXT DEFAULT 'v1', -- Track template versioning

    -- Processing status
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'sent', 'failed')),
    processed_at TIMESTAMPTZ,
    error_message TEXT,

    -- Retry logic
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    next_retry_at TIMESTAMPTZ,

    -- Concurrency control (for SELECT FOR UPDATE SKIP LOCKED)
    locked_by TEXT, -- Worker ID processing this row
    locked_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_email_queue_pending ON email_queue(scheduled_for, status)
    WHERE status = 'pending';
CREATE INDEX idx_email_queue_retry ON email_queue(next_retry_at, retry_count)
    WHERE status = 'failed' AND retry_count < max_retries;
CREATE INDEX idx_email_queue_user ON email_queue(user_id, created_at DESC);

-- =====================================================
-- Email Logs Table
-- =====================================================
CREATE TABLE email_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Email details
    email_type TEXT NOT NULL,
    subject TEXT NOT NULL,
    sent_at TIMESTAMPTZ DEFAULT NOW(),

    -- Provider tracking
    message_id TEXT, -- Resend message ID
    template_version TEXT, -- Template version used at queue time

    -- Engagement tracking (via Resend webhooks)
    opened_at TIMESTAMPTZ,
    clicked_at TIMESTAMPTZ,
    click_url TEXT,
    bounced_at TIMESTAMPTZ,
    bounce_reason TEXT,

    -- Status tracking
    status TEXT DEFAULT 'sent' CHECK (status IN ('sent', 'delivered', 'opened', 'clicked', 'bounced', 'failed', 'skipped')),
    skipped_reason TEXT, -- e.g., 'no_activity', 'unsubscribed', 'rate_limited'

    -- A/B testing
    variant TEXT
);

CREATE INDEX idx_email_logs_user ON email_logs(user_id, sent_at DESC);
CREATE INDEX idx_email_logs_type ON email_logs(user_id, email_type, sent_at DESC);
CREATE INDEX idx_email_logs_message ON email_logs(message_id);

-- =====================================================
-- Dead Letter Queue (permanent failures)
-- =====================================================
CREATE TABLE email_dead_letter_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    original_queue_id UUID REFERENCES email_queue(id) ON DELETE SET NULL,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Email metadata
    email_type TEXT NOT NULL,
    scheduled_for TIMESTAMPTZ,
    payload JSONB,
    template_version TEXT,
    error_message TEXT,

    -- Failure tracking
    total_retries INTEGER,
    first_attempt_at TIMESTAMPTZ,
    final_attempt_at TIMESTAMPTZ DEFAULT NOW(),

    -- Manual review workflow
    requires_manual_review BOOLEAN DEFAULT true,
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES auth.users(id),
    resolution TEXT, -- 'retried', 'discarded', 'user_notified'
    resolution_notes TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_dlq_review ON email_dead_letter_queue(requires_manual_review, created_at)
    WHERE requires_manual_review = true;
CREATE INDEX idx_dlq_user ON email_dead_letter_queue(user_id, created_at DESC);

-- =====================================================
-- RLS Policies
-- =====================================================
ALTER TABLE email_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE email_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE email_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE email_dead_letter_queue ENABLE ROW LEVEL SECURITY;

-- Users manage their own preferences
CREATE POLICY "Users manage own email preferences"
    ON email_preferences FOR ALL USING (auth.uid() = user_id);

-- Users view their own email logs
CREATE POLICY "Users view own email logs"
    ON email_logs FOR SELECT USING (auth.uid() = user_id);

-- Users view their own DLQ entries (transparency)
CREATE POLICY "Users view own DLQ entries"
    ON email_dead_letter_queue FOR SELECT USING (auth.uid() = user_id);

-- Service role manages queue (bypass RLS for cron jobs)
CREATE POLICY "Service manages email queue"
    ON email_queue FOR ALL USING (true);

-- Service role manages DLQ
CREATE POLICY "Service manages DLQ"
    ON email_dead_letter_queue FOR ALL USING (true);
```

### 3.2 Initialization: Auto-Create Email Preferences on Signup

When a new user signs up, automatically create their email preferences with sensible defaults.

**Implementation:** Database trigger on `auth.users` insert.

```sql
-- =====================================================
-- Auto-initialize email preferences on user signup
-- =====================================================
CREATE OR REPLACE FUNCTION initialize_email_preferences()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO email_preferences (user_id, emails_enabled, weekly_summary, streak_celebrations, achievement_notifications, lapsed_nudges, monthly_report, preferred_send_hour, timezone)
    VALUES (
        NEW.id,
        true,  -- emails_enabled: default ON
        true,  -- weekly_summary: default ON
        true,  -- streak_celebrations: default ON
        true,  -- achievement_notifications: default ON
        true,  -- lapsed_nudges: default ON
        true,  -- monthly_report: default ON
        9,     -- preferred_send_hour: 9am
        'America/New_York' -- timezone: default US Eastern
    )
    ON CONFLICT (user_id) DO NOTHING; -- Prevent duplicate inserts

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trigger_initialize_email_preferences
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION initialize_email_preferences();
```

**Acceptance Criteria:**

- GIVEN new user signs up via Apple/Google/Email auth
  WHEN user record is inserted to `auth.users`
  THEN row is automatically created in `email_preferences` with default values
  AND user does NOT need to manually enable emails

### 3.3 Queue Processing (Concurrent-Safe)

Queue processor must handle concurrent workers without race conditions or duplicate sends.

**Implementation:** Use PostgreSQL's `SELECT FOR UPDATE SKIP LOCKED` to ensure only one worker processes each email.

```sql
-- =====================================================
-- Claim next batch of emails for processing
-- =====================================================
CREATE OR REPLACE FUNCTION claim_emails_for_processing(
    p_worker_id TEXT,
    p_batch_size INTEGER DEFAULT 10
)
RETURNS TABLE (
    queue_id UUID,
    user_id UUID,
    email_type TEXT,
    payload JSONB,
    template_version TEXT
) AS $$
BEGIN
    RETURN QUERY
    UPDATE email_queue
    SET status = 'processing',
        locked_by = p_worker_id,
        locked_at = NOW()
    WHERE id IN (
        SELECT id FROM email_queue
        WHERE status = 'pending'
          AND scheduled_for <= NOW()
        ORDER BY scheduled_for ASC
        LIMIT p_batch_size
        FOR UPDATE SKIP LOCKED -- Prevent race conditions
    )
    RETURNING
        email_queue.id AS queue_id,
        email_queue.user_id,
        email_queue.email_type,
        email_queue.payload,
        email_queue.template_version;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

**Worker Pseudocode:**

```typescript
// Edge Function: process-email-queue (runs every 5 minutes via cron)

const workerId = crypto.randomUUID(); // Unique worker ID
const batch = await supabase.rpc("claim_emails_for_processing", {
  p_worker_id: workerId,
  p_batch_size: 10,
});

for (const email of batch) {
  try {
    // Re-check preferences immediately before sending (Gap 8 fix)
    const { data: prefs } = await supabase
      .from("email_preferences")
      .select("emails_enabled, unsubscribed_at")
      .eq("user_id", email.user_id)
      .single();

    if (!prefs?.emails_enabled || prefs?.unsubscribed_at) {
      // User unsubscribed between queue time and send time
      await markEmailAsSkipped(email.queue_id, "unsubscribed");
      continue;
    }

    // Render template and send
    await sendEmailViaSendGrid(email);

    // Mark as sent
    await supabase
      .from("email_queue")
      .update({ status: "sent", processed_at: new Date().toISOString() })
      .eq("id", email.queue_id);
  } catch (error) {
    await handleEmailFailure(email.queue_id, error);
  }
}
```

**Acceptance Criteria:**

- **AC-3.3.1:** GIVEN 3 workers run concurrently
  WHEN all workers call `claim_emails_for_processing()`
  THEN each worker receives DIFFERENT emails (no overlap)
  AND no email is sent twice

- **AC-3.3.2:** GIVEN email is in "processing" state for >10 minutes (stuck worker)
  WHEN heartbeat monitor runs
  THEN email is reset to "pending" AND `locked_by` is cleared
  AND another worker can claim it

### 3.4 Unsubscribe Race Condition Prevention

Between queue time and send time, user may unsubscribe. Prevent sending email to users who unsubscribed mid-flight.

**Solution:** Re-check `emails_enabled` and `unsubscribed_at` immediately before calling Resend API (see 3.3 pseudocode above).

**Acceptance Criteria:**

- **AC-3.4.1:** GIVEN email is queued at T=0 AND user unsubscribes at T=30s AND email send starts at T=60s
  WHEN send logic runs
  THEN preferences are re-checked
  AND email is NOT sent
  AND status is set to "skipped" with `skipped_reason = 'unsubscribed'`

### 3.5 Naming Conventions: Standardize Timezone Field

**Decision:** Use `timezone` everywhere (not `user_timezone`, `userTimezone`, `tz`, etc.).

**Rationale:** Consistency reduces bugs and improves readability.

**Affected Fields:**

- `email_preferences.timezone` (database)
- `timezone` (Swift models, JSON payloads, function parameters)

**Acceptance Criteria:**

- **AC-3.5.1:** GIVEN developer searches codebase for timezone references
  WHEN searching for "timezone"
  THEN all database columns, Swift properties, and API payloads use `timezone`
  AND no instances of `user_timezone` or `userTimezone` exist (except in legacy migration comments)

### 3.6 Template Versioning

Track which template version was used when email was queued. Allows rollback if new template causes issues.

**Implementation:**

1. Add `template_version` column to `email_queue` and `email_logs`
2. Set version at queue time (e.g., "v1", "v2-subject-test")
3. Log version when email is sent

**Example:**

```typescript
await supabase.from("email_queue").insert({
  user_id: userId,
  email_type: "weekly_summary",
  scheduled_for: scheduledTime,
  payload: stats,
  template_version: "v2-hero-image", // Track template iteration
});
```

**Acceptance Criteria:**

- **AC-3.6.1:** GIVEN new template is deployed ("v2")
  WHEN emails are queued
  THEN `template_version = 'v2'` is recorded
  AND old emails still in queue use "v1"

- **AC-3.6.2:** GIVEN template "v2" has bug causing 50% bounce rate
  WHEN admin investigates via `email_logs`
  THEN can filter by `template_version = 'v2'`
  AND identify all affected users

### 3.7 Timezone Validation

Validate timezone values against IANA timezone database. Fallback to UTC if invalid.

**Implementation:** Validation function in Edge Functions.

```typescript
import { isValidTimezone } from "https://esm.sh/timezone-support@2";

export function validateTimezone(tz: string): string {
  if (isValidTimezone(tz)) {
    return tz;
  }
  console.error(`Invalid timezone: ${tz}, falling back to UTC`);
  return "UTC";
}
```

**Acceptance Criteria:**

- **AC-3.7.1:** GIVEN user selects valid IANA timezone (e.g., "America/New_York")
  WHEN saved to `email_preferences`
  THEN value is accepted

- **AC-3.7.2:** GIVEN user submits invalid timezone (e.g., "EST", "GMT+5", malicious input)
  WHEN validation runs
  THEN timezone is set to "UTC"
  AND error is logged

### 3.8 Template Rendering Error Handling

If template rendering fails (e.g., missing data, malformed JSON), catch error and move to DLQ instead of crashing worker.

**Implementation:**

```typescript
try {
  const html = renderTemplate(email.email_type, email.payload);
  await sendEmail(html);
} catch (error) {
  if (error instanceof TemplateRenderError) {
    // Move to DLQ immediately (don't retry template errors)
    await supabase.from("email_dead_letter_queue").insert({
      original_queue_id: email.queue_id,
      user_id: email.user_id,
      email_type: email.email_type,
      payload: email.payload,
      error_message: `Template render failed: ${error.message}`,
      total_retries: 0,
    });

    await supabase
      .from("email_queue")
      .update({ status: "failed", error_message: error.message })
      .eq("id", email.queue_id);
  } else {
    throw error; // Retry transient errors
  }
}
```

**Acceptance Criteria:**

- **AC-3.8.1:** GIVEN email payload is missing required field (e.g., `current_streak`)
  WHEN template rendering runs
  THEN `TemplateRenderError` is thrown
  AND email is moved to DLQ
  AND NOT retried (since template error is permanent)

### 3.9 Webhook Security: Verify Resend Signatures

Resend sends webhooks for email events (delivered, opened, clicked, bounced). Verify webhook signatures to prevent spoofing.

**Implementation:**

```typescript
import { Webhook } from "https://esm.sh/@svix/svix@1";

serve(async (req) => {
  const payload = await req.text();
  const headers = {
    "svix-id": req.headers.get("svix-id")!,
    "svix-timestamp": req.headers.get("svix-timestamp")!,
    "svix-signature": req.headers.get("svix-signature")!,
  };

  const webhook = new Webhook(Deno.env.get("RESEND_WEBHOOK_SECRET")!);

  let event;
  try {
    event = webhook.verify(payload, headers);
  } catch (error) {
    console.error("Webhook signature verification failed:", error);
    return new Response("Unauthorized", { status: 401 });
  }

  // Process verified webhook event
  await handleWebhookEvent(event);

  return new Response("OK", { status: 200 });
});
```

**Acceptance Criteria:**

- **AC-3.9.1:** GIVEN Resend sends webhook with valid signature
  WHEN webhook handler receives request
  THEN signature is verified
  AND event is processed

- **AC-3.9.2:** GIVEN attacker sends forged webhook (invalid signature)
  WHEN webhook handler receives request
  THEN signature verification fails
  AND 401 Unauthorized is returned
  AND event is NOT processed

### 3.10 Rate Limit Enforcement Location

Check rate limits BEFORE inserting to `email_queue`, not after. Prevents filling queue with emails that will be skipped.

**Old (Wrong):**

```typescript
// Insert to queue first
await supabase.from('email_queue').insert({ ... });

// Check rate limit during processing (wastes queue space)
if (!withinLimit) { skip(); }
```

**New (Correct):**

```typescript
// Check rate limit BEFORE queueing
const weeklyCount = await getEmailCountPast7Days(userId);
if (weeklyCount >= 10) {
    await supabase.from('email_logs').insert({
        user_id: userId,
        email_type: 'weekly_summary',
        status: 'skipped',
        skipped_reason: 'rate_limited_weekly_max_10'
    });
    return; // Don't queue
}

// Only queue if within limit
await supabase.from('email_queue').insert({ ... });
```

**Acceptance Criteria:**

- **AC-3.10.1:** GIVEN user has received 10 emails in past 7 days
  WHEN cron job attempts to queue 11th email
  THEN rate limit check runs BEFORE insert
  AND email is NOT queued
  AND `email_logs` entry created with `status = 'skipped', skipped_reason = 'rate_limited_weekly_max_10'`

---

## 4. Business Logic

### 4.1 Email Types (Detailed Specifications)

#### 4.1.1 Weekly Summary Email

**Trigger:** Every Sunday at user's `preferred_send_hour` in their `timezone`.

**Eligibility:**

- `emails_enabled = true`
- `weekly_summary = true`
- User completed at least 1 quest in past 7 days

**Content Sections:**

1. **Hero:** "Your week in review, {name}"
2. **Stats:** Quests completed, moods logged, exercise minutes, current streak
3. **Badges:** New badges earned this week (with icons)
4. **Mood Trend:** Average mood + emoji (😊 Great, 😐 Okay, 😔 Tough)
5. **CTA:** "Continue Your Streak" → Deep link to `/quests`

#### 4.1.2 Streak Celebration Email

**Trigger:** User completes quest AND `current_streak` reaches milestone (7, 14, 30, 60, 90, 180, 365 days).

**Eligibility:**

- `emails_enabled = true`
- `streak_celebrations = true`
- No duplicate email sent for this milestone (check `email_logs`)

**Content Sections:**

1. **Hero:** "🔥 {streak} Day Streak!"
2. **Celebration Message:** "You've shown up {streak} days in a row. That's incredible dedication."
3. **Stats:** Total quests completed, total mindfulness minutes
4. **Next Milestone:** "Your next milestone: {next_milestone} days"
5. **CTA:** "Keep It Going" → Deep link to `/quests`

#### 4.1.3 Achievement Unlock Email

**Trigger:** User earns badge (insert to `user_badges` table).

**Eligibility:**

- `emails_enabled = true`
- `achievement_notifications = true`

**Content Sections:**

1. **Hero:** Badge icon + "You earned a new badge!"
2. **Badge Details:** Badge name, description, rarity (if applicable)
3. **Progress:** "You've earned {total_badges} out of {total_possible} badges"
4. **CTA:** "View All Achievements" → Deep link to `/achievements`

#### 4.1.4 Lapsed User Nudge Email

**Trigger:** User has not completed quest in 3, 7, or 14 days.

**Eligibility:**

- `emails_enabled = true`
- `lapsed_nudges = true`
- Has not received lapsed email in past `N` days (where N = 3, 7, or 14)

**Content Variations:**

| Days Inactive | Subject Line                          | Tone       |
| ------------- | ------------------------------------- | ---------- |
| 3             | "We miss you! Here's today's quest"   | Friendly   |
| 7             | "It's been a week — ready to return?" | Gentle     |
| 14            | "We're here when you're ready"        | Supportive |

#### 4.1.5 Monthly Report Email

**Trigger:** 1st of every month at user's `preferred_send_hour` in their `timezone`.

**Eligibility:**

- `emails_enabled = true`
- `monthly_report = true`
- User completed at least 1 activity in past month (quest, mood, or exercise)

**Content Sections:**

1. **Hero:** "Your {Month} Wellness Report"
2. **Monthly Stats:** Quests completed, moods logged, exercise minutes, badges earned
3. **Outcome Tracking:** PHQ-9, GAD-7 scores (if available) with trend arrows
4. **Highlights:** "Best streak this month: {max_streak} days"
5. **CTA:** "Complete Your Monthly Check-In" → Deep link to `/outcomes/assessments`

### 4.2 Crisis User Email Policy

**Rule:** Users with recent crisis events (self-harm detected) are temporarily suppressed from ALL promotional emails for 14 days.

**Rationale:** Avoid sending cheerful "streak celebration" emails to users in acute crisis. Respect their emotional state.

**Implementation:**

```sql
-- Check if user has crisis event in past 14 days
CREATE OR REPLACE FUNCTION user_has_recent_crisis(p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM crisis_events
        WHERE user_id = p_user_id
          AND created_at > NOW() - INTERVAL '14 days'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

**Queue Logic:**

```typescript
// Before queueing any email, check crisis status
const { data: inCrisis } = await supabase.rpc("user_has_recent_crisis", {
  p_user_id: userId,
});

if (inCrisis) {
  await supabase.from("email_logs").insert({
    user_id: userId,
    email_type: emailType,
    status: "skipped",
    skipped_reason: "recent_crisis_event_14day_suppression",
  });
  return; // Don't queue
}
```

**Acceptance Criteria:**

- **AC-4.2.1:** GIVEN user had crisis event 5 days ago (self-harm keyword detected in chat)
  WHEN weekly summary cron attempts to queue email
  THEN email is NOT queued
  AND `email_logs` entry created with `status = 'skipped', skipped_reason = 'recent_crisis_event_14day_suppression'`

- **AC-4.2.2:** GIVEN user had crisis event 15 days ago (outside 14-day window)
  WHEN weekly summary cron runs
  THEN email IS queued normally (suppression period has ended)

---

## 5. Operations & Support

### 5.1 Dead Letter Queue Management

Emails that fail after 3 retries are moved to Dead Letter Queue (DLQ) for manual review.

**Process:**

1. **Alert:** Slack notification when new entry added to DLQ (via Supabase webhook)
2. **Investigate:** Support engineer views DLQ entry in admin dashboard
3. **Decide:** Choose resolution:
   - **Retry:** Fix root cause (e.g., template bug), then manually requeue
   - **Discard:** Invalid email address, user deleted account
   - **Notify User:** Send fallback notification via in-app push
4. **Resolve:** Mark as `requires_manual_review = false` and log `resolution`

**Admin Dashboard Query:**

```sql
SELECT
    id,
    user_id,
    email_type,
    error_message,
    total_retries,
    final_attempt_at,
    requires_manual_review
FROM email_dead_letter_queue
WHERE requires_manual_review = true
ORDER BY created_at DESC;
```

**Runbook Reference:** See `docs/runbooks.md` → "Email DLQ Manual Review Process"

### 5.2 Rate Limiting Strategy

**Limit:** Maximum 10 emails per user per 7-day rolling window.

**Rationale:** Prevent spam perception while allowing weekly summary + occasional event emails.

**Enforcement:** Check count of emails sent in past 7 days BEFORE queuing (see Section 3.10).

**Query:**

```sql
SELECT COUNT(*) FROM email_logs
WHERE user_id = $1
  AND sent_at > NOW() - INTERVAL '7 days'
  AND status IN ('sent', 'delivered', 'opened', 'clicked');
```

**Behavior When Limit Exceeded:**

```typescript
const emailCount = await getEmailCountPast7Days(userId);

if (emailCount >= 10) {
  await supabase.from("email_logs").insert({
    user_id: userId,
    email_type: "weekly_summary",
    status: "skipped",
    skipped_reason: "rate_limited_weekly_max_10",
  });
  return; // Don't queue
}
```

### 5.3 Email Preferences Management

Users can manage email preferences via:

1. **In-app Settings** (`ProfileView` → Email Preferences)
2. **Web Unsubscribe Page** (`https://getmindfriend.app/unsubscribe?token={token}`)

**In-App Settings UI (iOS):**

```swift
struct EmailPreferencesView: View {
    @State private var emailsEnabled: Bool = true
    @State private var weeklySummary: Bool = true
    @State private var streakCelebrations: Bool = true
    @State private var achievementNotifications: Bool = true
    @State private var lapsedNudges: Bool = true
    @State private var monthlyReport: Bool = true
    @State private var preferredSendHour: Int = 9
    @State private var timezone: String = "America/New_York"
    @State private var showTimezonePicker: Bool = false

    var body: some View {
        Form {
            Section(header: Text("Email Notifications")) {
                Toggle("Enable Emails", isOn: $emailsEnabled)
                    .tint(.blue)
                    .onChange(of: emailsEnabled) { _ in savePreferences() }

                if emailsEnabled {
                    Toggle("Weekly Summary", isOn: $weeklySummary)
                    Toggle("Streak Celebrations", isOn: $streakCelebrations)
                    Toggle("Achievement Notifications", isOn: $achievementNotifications)
                    Toggle("Lapsed User Nudges", isOn: $lapsedNudges)
                    Toggle("Monthly Report", isOn: $monthlyReport)
                }
            }

            Section(header: Text("Delivery Settings")) {
                Picker("Preferred Send Time", selection: $preferredSendHour) {
                    ForEach(0..<24) { hour in
                        Text(formatHour(hour)).tag(hour)
                    }
                }

                Button(action: { showTimezonePicker = true }) {
                    HStack {
                        Text("Timezone")
                        Spacer()
                        Text(timezone)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Email Preferences")
        .sheet(isPresented: $showTimezonePicker) {
            TimezoneSelectorView(selectedTimezone: $timezone)
        }
    }

    func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
        return formatter.string(from: date)
    }

    func savePreferences() {
        Task {
            await container.supabaseDataService.updateEmailPreferences(
                emailsEnabled: emailsEnabled,
                weeklySummary: weeklySummary,
                streakCelebrations: streakCelebrations,
                achievementNotifications: achievementNotifications,
                lapsedNudges: lapsedNudges,
                monthlyReport: monthlyReport,
                preferredSendHour: preferredSendHour,
                timezone: timezone
            )
        }
    }
}

struct TimezoneSelectorView: View {
    @Binding var selectedTimezone: String
    @Environment(\.dismiss) var dismiss
    @State private var searchText: String = "" // FIX: Gap 7 - Add @State

    let timezones = TimeZone.knownTimeZoneIdentifiers

    var filteredTimezones: [String] {
        if searchText.isEmpty {
            return timezones
        }
        return timezones.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationView {
            List(filteredTimezones, id: \.self) { tz in
                Button(action: {
                    selectedTimezone = tz
                    dismiss()
                }) {
                    HStack {
                        Text(tz)
                        Spacer()
                        if tz == selectedTimezone {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Select Timezone")
            .searchable(text: $searchText, prompt: "Search timezones")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
```

**Web Unsubscribe Page:**

```html
<!-- https://getmindfriend.app/unsubscribe.html -->
<!DOCTYPE html>
<html>
  <head>
    <title>Unsubscribe from MindFriend Emails</title>
    <style>
      body {
        font-family: -apple-system, sans-serif;
        max-width: 600px;
        margin: 50px auto;
        padding: 20px;
      }
      .success {
        color: green;
      }
      .error {
        color: red;
      }
    </style>
  </head>
  <body>
    <h1>Unsubscribe from MindFriend Emails</h1>
    <div id="result"></div>

    <script>
      const params = new URLSearchParams(window.location.search);
      const token = params.get("token");

      if (!token) {
        document.getElementById("result").innerHTML =
          '<p class="error">Invalid unsubscribe link.</p>';
      } else {
        // Call Edge Function to unsubscribe
        fetch("https://<supabase-url>/functions/v1/unsubscribe", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ token }),
        })
          .then((res) => res.json())
          .then((data) => {
            if (data.success) {
              document.getElementById("result").innerHTML = `
                        <p class="success">You've been unsubscribed from all MindFriend emails.</p>
                        <p>You can re-enable emails anytime in the app settings.</p>
                    `;
            } else {
              document.getElementById("result").innerHTML =
                '<p class="error">Unable to unsubscribe. Please contact support.</p>';
            }
          });
      }
    </script>
  </body>
</html>
```

---

## 6. Testing & Preview

### 6.1 Email Preview Edge Function

**Purpose:** Allow developers/QA to preview email templates with sample data without sending emails.

**Endpoint:** `POST /functions/v1/preview-email-template`

**Implementation:**

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { renderTemplate } from "../_shared/email-templates.ts";

serve(async (req) => {
  const { email_type, sample_data } = await req.json();

  const { html, text, subject } = renderTemplate(email_type, sample_data);

  return new Response(JSON.stringify({ html, text, subject }), {
    headers: { "Content-Type": "application/json" },
  });
});
```

### 6.2 Sample Emails for Testing

Maintain sample data for QA testing before rollout.

### 6.3 Acceptance Test Scenarios

| Test ID | Scenario                                              | Expected Result                                         |
| ------- | ----------------------------------------------------- | ------------------------------------------------------- |
| AT-01   | User completes 7-day streak                           | Streak celebration email queued with milestone=7        |
| AT-02   | User completes 0 quests in past week                  | Weekly summary NOT queued, skipped_reason='no_activity' |
| AT-03   | User unsubscribes mid-flight (between queue and send) | Email NOT sent, status='skipped', reason='unsubscribed' |
| AT-04   | User receives 10 emails in past 7 days                | 11th email NOT queued, rate_limited                     |
| AT-05   | User has crisis event 5 days ago                      | All promotional emails skipped for 14 days              |
| AT-06   | Email fails 3 times (SMTP timeout)                    | Email moved to DLQ, manual review required              |
| AT-07   | User updates timezone from EST to PST                 | Next scheduled email uses PST for delivery time         |
| AT-08   | Template rendering fails (missing data)               | Email moved to DLQ immediately (no retries)             |
| AT-09   | Webhook received with invalid signature               | Webhook rejected with 401 Unauthorized                  |
| AT-10   | User clicks deep link in email                        | App opens to correct screen (e.g., /achievements)       |

---

## 7. Edge Cases

### 7.1 Timezone Edge Cases

| Scenario                                 | Handling                                                         |
| ---------------------------------------- | ---------------------------------------------------------------- |
| User timezone is invalid (e.g., "EST")   | Fallback to UTC, log error                                       |
| User timezone changed after email queued | Email still sent at originally scheduled UTC time                |
| Daylight Saving Time transition          | PostgreSQL `AT TIME ZONE` handles automatically (IANA timezones) |

### 7.2 Unsubscribe Edge Cases

| Scenario                                 | Handling                                                 |
| ---------------------------------------- | -------------------------------------------------------- |
| User unsubscribes during email send      | Re-check preferences before Resend API call              |
| User clicks unsubscribe, then re-enables | Re-enabling sets `unsubscribed_at = NULL`, emails resume |
| Token is leaked/guessed                  | Low risk: UUID (128-bit entropy)                         |

### 7.3 Rate Limit Edge Cases

| Scenario                                       | Handling                                                |
| ---------------------------------------------- | ------------------------------------------------------- |
| 10 emails sent, oldest is exactly 7 days ago   | Oldest email is INCLUDED in count (use `>=` 7 days ago) |
| User receives 5 emails in one day (badge spam) | Still within 10/week limit, allowed                     |

### 7.4 Queue Processing Edge Cases

| Scenario                      | Handling                                                            |
| ----------------------------- | ------------------------------------------------------------------- |
| Worker crashes mid-send       | Email stuck in "processing", heartbeat monitor resets after 10 mins |
| Email scheduled for past time | Send immediately (condition: `scheduled_for <= NOW()`)              |

### 7.5 Template Rendering Edge Cases

| Scenario                                      | Handling                       |
| --------------------------------------------- | ------------------------------ |
| Missing required field (e.g., `name` is NULL) | Use fallback: "Friend"         |
| Invalid JSON in `payload` column              | Catch parse error, move to DLQ |

### 7.6 Crisis User Edge Cases

| Scenario                                    | Handling                                               |
| ------------------------------------------- | ------------------------------------------------------ |
| Crisis event recorded, user completes quest | Suppress emails for full 14 days                       |
| Crisis event on day 13 of suppression       | Suppression window resets to 14 days from latest event |

---

## 8. Deployment & Rollout

### 8.1 Phase 1: Database Migration

Apply all schema migrations from Section 3.1.1.

### 8.2 Phase 2: Edge Functions Deployment

Deploy all email-related Edge Functions.

### 8.3 Phase 3: Cron Jobs Setup

Configure cron schedules for weekly/monthly/daily email functions.

### 8.4 Phase 4: iOS App UI

Add Email Preferences screen to Settings.

### 8.5 Phase 5: Template Design & QA

Design and test HTML email templates.

### 8.6 Phase 6: Soft Launch (Beta)

Enable for internal team, monitor metrics.

### 8.7 Phase 7: Full Rollout

Enable for all users, announce feature.

---

## 9. Success Criteria & Metrics

### 9.1 Launch Criteria

- ✅ All 10 requirements implemented and tested
- ✅ Deliverability rate >95%
- ✅ Unsubscribe rate <2%
- ✅ Zero duplicate emails sent
- ✅ DLQ process documented
- ✅ Deep links tested on iOS

### 9.2 Success Metrics (Post-Launch)

**Week 1:**

- 1,000+ weekly summary emails sent
- Open rate: 30%+
- CTR: 12%+
- Unsubscribe rate: <2%

**Week 4:**

- Re-engagement rate: 8%+ (lapsed users return)
- 500+ streak celebration emails
- 200+ achievement emails

**Month 3:**

- Monthly report adoption: 50%+
- Email-driven sessions: 5%+
- DLQ manual reviews: <10/week

---

**END OF SPECIFICATION**

**Document Metadata:**

- **Version:** 2.0
- **Status:** READY FOR IMPLEMENTATION
- **All 18 Gaps Addressed:** ✅
