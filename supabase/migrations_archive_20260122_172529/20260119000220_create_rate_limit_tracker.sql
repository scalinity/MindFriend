-- Migration: Create rate_limit_tracker table for couples mode rate limiting
-- Purpose: Track rate limit attempts for invite codes, appreciations, and failed attempts
-- Status: CRITICAL FIX - Required by couples-rate-limit.ts

CREATE TABLE IF NOT EXISTS rate_limit_tracker (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    action VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Composite index for efficient rate limit checks (sliding window)
CREATE INDEX IF NOT EXISTS idx_rate_limit_tracker_user_action_time 
ON rate_limit_tracker(user_id, action, created_at DESC);

-- Index for cleanup queries
CREATE INDEX IF NOT EXISTS idx_rate_limit_tracker_created 
ON rate_limit_tracker(created_at);

COMMENT ON TABLE rate_limit_tracker IS 'Tracks rate limit attempts for couples mode actions (invites, appreciations, failed attempts)';
COMMENT ON COLUMN rate_limit_tracker.action IS 'Action type: invite_code, failed_invite_attempt, appreciation, session_rating';
