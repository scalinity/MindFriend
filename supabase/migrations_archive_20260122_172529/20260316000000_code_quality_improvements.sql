-- Code Quality and Security Improvements Migration
-- Addresses issues identified in codebase analysis (2026-01-16)

-- =============================================================================
-- P2-003: Document user_badges RLS intent with SQL comment
-- =============================================================================
-- The user_badges table only has SELECT policy by design.
-- Badge insertions and updates are managed exclusively via service role
-- in Edge Functions (verify-purchase, award-xp, complete-quest) to ensure
-- badges cannot be self-awarded by clients.

COMMENT ON TABLE user_badges IS 
  'User achievement badges. INSERT/UPDATE/DELETE operations require service role - badges are awarded programmatically by Edge Functions only.';

-- =============================================================================
-- P2-004: Add GIN index on notification_history.metadata for rate limit queries
-- =============================================================================
-- The send-notification function queries: filter("metadata->>'senderId'", "eq", userId)
-- Without an index, this performs a full table scan as notification_history grows.

-- Check if index already exists before creating
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE tablename = 'notification_history' 
    AND indexname = 'idx_notification_history_metadata_sender'
  ) THEN
    CREATE INDEX idx_notification_history_metadata_sender 
    ON notification_history USING GIN (metadata jsonb_path_ops);
  END IF;
END $$;

COMMENT ON INDEX idx_notification_history_metadata_sender IS 
  'GIN index on metadata JSONB for efficient rate limit queries filtering by senderId';

-- =============================================================================
-- P3-008: Drop deprecated trigger_content column from crisis_events
-- =============================================================================
-- The trigger_content column was deprecated in chat_security_hardening migration
-- for PII protection. It has been replaced by trigger_keyword which stores only
-- the detected keyword, not the user's actual message content.

ALTER TABLE crisis_events DROP COLUMN IF EXISTS trigger_content;

COMMENT ON TABLE crisis_events IS 
  'Crisis detection events. Stores trigger_keyword (the detected keyword) instead of user content for PII protection.';

-- =============================================================================
-- Additional Cleanup: Mark deprecated in-memory rate limiter in cors.ts
-- =============================================================================
-- Note: This is a TypeScript code change, not a database change.
-- The deprecated inMemoryRateLimit export in _shared/cors.ts should be marked @internal
-- or removed entirely. See P4-001 in the remediation plan.
