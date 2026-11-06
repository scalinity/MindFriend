-- Restore categories already emitted by the existing notification handlers.
-- No recipients, permissions, schedules or historical rows are changed.
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '15s';
DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.notification_history'::regclass
      AND conname = 'notification_history_notification_type_check'
      AND contype = 'c' AND convalidated
      AND pg_catalog.md5(pg_catalog.pg_get_constraintdef(oid)) = 'cb844af11929b6cfc9104a1b1bb45ca6'
  ) THEN
    RAISE EXCEPTION 'Notification category constraint differs from the audited baseline';
  END IF;
END;
$migration$;

ALTER TABLE public.notification_history
  DROP CONSTRAINT notification_history_notification_type_check,
  ADD CONSTRAINT notification_history_notification_type_check
  CHECK (notification_type = ANY (ARRAY[
    'circle_activity',
    'hug',
    'streak_risk',
    'weekly_summary',
    'challenge',
    'family_member_joined',
    'together_invitation',
    'family_alert',
    'family_challenge_progress',
    'parental_consent_request',
    'shield_used',
    'shield_reset',
    'recovery_available',
    'reengagement_gentle',
    'reengagement_social',
    'reengagement_progress',
    'reengagement_fresh_start',
    'proactive_mood_decline',
    'proactive_streak_risk',
    'proactive_milestone',
    'proactive_reengagement',
    'proactive_pattern_insight',
    'assessment_reminder',
    'buddy_encouragement',
    'couples_exercise_invite',
    'agent_action'
  ]::text[]));

COMMIT;
