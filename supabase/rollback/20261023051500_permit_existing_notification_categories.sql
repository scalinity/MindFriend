-- Stop producers of the added categories before rollback.
-- If history uses an added category this transaction fails and retains the
-- expanded constraint. Never delete or remap notification history to force it.
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '15s';
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
    'parental_consent_request'
  ]::text[]));

COMMIT;
