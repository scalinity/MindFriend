-- Migration: Add composite index for voice_sessions
-- Improves query performance for end_voice_session RPC which looks up sessions by id + user_id

-- Composite index on (user_id, started_at) for efficient session queries
-- Covers the common query pattern: find recent sessions for a user
CREATE INDEX IF NOT EXISTS idx_voice_sessions_user_started
    ON voice_sessions(user_id, started_at DESC);

-- Index on ended_at to support queries for orphaned sessions (ended_at IS NULL)
CREATE INDEX IF NOT EXISTS idx_voice_sessions_ended_at
    ON voice_sessions(ended_at)
    WHERE ended_at IS NULL;
