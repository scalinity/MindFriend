-- Audit Fixes Migration
-- Addresses findings from 2026-01-14 codebase audit

-- H3: Document user_badges as service-role only
-- The user_badges table intentionally only has a SELECT policy because:
-- 1. Badges are awarded server-side by Edge Functions using service role
-- 2. This prevents users from giving themselves badges
-- 3. This is a security feature, not a bug
COMMENT ON TABLE user_badges IS 'Badge assignments are managed server-side only via service role. Users can SELECT their badges but cannot INSERT/UPDATE/DELETE directly.';

-- M7: Add GIN index on notification_history.metadata for rate limiting queries
-- This optimizes the senderId lookup used in rate limiting
CREATE INDEX IF NOT EXISTS idx_notification_history_metadata_gin 
ON notification_history USING GIN (metadata);

-- Also add a specific index for senderId lookups
CREATE INDEX IF NOT EXISTS idx_notification_history_sender_id 
ON notification_history ((metadata->>'senderId'));

-- L1: Document trigger_content column in crisis_events for PII protection
-- The trigger_content column should only store the matched keyword pattern, not actual user content
COMMENT ON COLUMN crisis_events.trigger_content IS 'The crisis keyword pattern that was detected. Should NOT contain actual user content for privacy protection - only the matched keyword.';
