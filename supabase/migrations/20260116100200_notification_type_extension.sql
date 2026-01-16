-- Spec 11: Family Wellness - Extend notification_history CHECK constraint
-- Adds family wellness notification types to support Edge Functions

-- Current notification types: circle_activity, hug, streak_risk, weekly_summary, challenge
-- Need to add: family_member_joined, together_invitation, family_alert, family_challenge_progress, parental_consent_request

-- Drop and recreate the CHECK constraint with extended notification types
ALTER TABLE notification_history
DROP CONSTRAINT IF EXISTS notification_history_notification_type_check;

ALTER TABLE notification_history
ADD CONSTRAINT notification_history_notification_type_check
  CHECK (notification_type IN (
    -- Existing notification types
    'circle_activity', 'hug', 'streak_risk', 'weekly_summary', 'challenge',
    -- New family wellness notification types
    'family_member_joined', 'together_invitation', 'family_alert',
    'family_challenge_progress', 'parental_consent_request'
  ));
