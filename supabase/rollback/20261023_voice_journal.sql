-- Apply only after stopping new journal requests and reverting analyze-voice-journal.
-- If also reverting sponsored entitlements, apply that rollback first: it recreates
-- this quota helper. Reverting it afterward would restore the removed function.
-- Existing submitted provider calls are not cancelled by this schema rollback.
-- Keep creative_quota_usage, creative_works and all existing claims/reservations.
-- No CASCADE: unexpected database dependencies must stop the transaction.
BEGIN;
DROP FUNCTION IF EXISTS public.reserve_voice_journal_quota(uuid, integer);
COMMIT;
