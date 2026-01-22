-- MindFriend Rehearsal Cleanup Job Scheduling
-- Purpose: Schedule automated cleanup for expired sessions and old records
-- Created: 2026-01-22
-- GDPR Compliance: Ensures data retention policies are enforced

-- Enable pg_cron extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Schedule job to abandon expired sessions every 15 minutes
-- Converts active sessions that have exceeded 2-hour timeout to 'abandoned' status
SELECT cron.schedule(
  'abandon-expired-rehearsal-sessions',
  '*/15 * * * *',  -- Every 15 minutes
  'SELECT abandon_expired_rehearsal_sessions();'
);

-- Schedule job to delete old archived sessions daily at 2 AM
-- Deletes sessions older than 90 days (GDPR data minimization requirement)
-- Only affects sessions with status: completed, abandoned, or crisis_ended
SELECT cron.schedule(
  'delete-old-rehearsal-sessions',
  '0 2 * * *',  -- Daily at 2:00 AM UTC
  'SELECT delete_old_rehearsal_sessions();'
);

-- Log cleanup schedule information
COMMENT ON FUNCTION abandon_expired_rehearsal_sessions() IS
'Automatically called via pg_cron every 15 minutes to abandon expired rehearsal sessions';

COMMENT ON FUNCTION delete_old_rehearsal_sessions() IS
'Automatically called via pg_cron daily at 2 AM to enforce 90-day retention policy';
