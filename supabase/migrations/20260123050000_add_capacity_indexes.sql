-- =====================================================
-- Migration: Add Performance Indexes for Capacity Calculation
-- Description: Optimizes queries used in calculate-capacity Edge Function
-- Date: 2026-01-23
-- =====================================================

-- Index for capacity cache lookups (user_id, local_date)
-- Optimizes: SELECT * FROM user_capacity WHERE user_id = ? AND local_date = ?
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_capacity_user_date
    ON user_capacity(user_id, local_date);

COMMENT ON INDEX idx_user_capacity_user_date IS 'Optimizes capacity cache lookups (one row per user per day)';

-- Index for mood queries (fetchMoodData)
-- Optimizes: SELECT * FROM moods WHERE user_id = ? AND created_at >= ? AND created_at <= ? ORDER BY created_at DESC
CREATE INDEX IF NOT EXISTS idx_moods_user_created
    ON moods(user_id, created_at DESC);

COMMENT ON INDEX idx_moods_user_created IS 'Optimizes capacity calculation mood data queries (3-day range)';

-- Index for sleep session queries (fetchSleepData)
-- Optimizes: SELECT * FROM sleep_sessions WHERE user_id = ? ORDER BY created_at DESC
CREATE INDEX IF NOT EXISTS idx_sleep_sessions_user_created
    ON sleep_sessions(user_id, created_at DESC);

COMMENT ON INDEX idx_sleep_sessions_user_created IS 'Optimizes capacity calculation sleep data queries';

-- Index for quest completion queries (recent quests by date)
-- Optimizes: SELECT * FROM quests WHERE user_id = ? AND local_date >= ? ORDER BY local_date DESC
CREATE INDEX IF NOT EXISTS idx_quests_user_local_date
    ON quests(user_id, local_date DESC);

COMMENT ON INDEX idx_quests_user_local_date IS 'Optimizes recent quest queries by date';

-- Index for quest completion queries (by status)
-- Optimizes: SELECT COUNT(*) FROM quests WHERE user_id = ? AND status = 'completed'
CREATE INDEX IF NOT EXISTS idx_quests_user_status
    ON quests(user_id, status);

COMMENT ON INDEX idx_quests_user_status IS 'Optimizes quest status queries';

-- Analyze tables to update query planner statistics
ANALYZE moods;
ANALYZE sleep_sessions;
ANALYZE quests;
ANALYZE user_capacity;
