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
-- Optimizes: SELECT * FROM moods WHERE user_id = ? AND logged_at >= ? AND logged_at <= ? ORDER BY logged_at DESC
CREATE INDEX IF NOT EXISTS idx_moods_user_logged
    ON moods(user_id, logged_at DESC);

COMMENT ON INDEX idx_moods_user_logged IS 'Optimizes capacity calculation mood data queries (3-day range)';

-- Index for sleep log queries (fetchSleepData)
-- Optimizes: SELECT * FROM sleep_logs WHERE user_id = ? AND logged_at >= ? AND logged_at <= ? ORDER BY logged_at DESC
CREATE INDEX IF NOT EXISTS idx_sleep_logs_user_logged
    ON sleep_logs(user_id, logged_at DESC);

COMMENT ON INDEX idx_sleep_logs_user_logged IS 'Optimizes capacity calculation sleep data queries (7-day range)';

-- Index for quest completion queries (fetchCompletionData - recent quests)
-- Optimizes: SELECT completed FROM quests WHERE user_id = ? AND assigned_date >= ? AND assigned_date <= ? ORDER BY assigned_date DESC
CREATE INDEX IF NOT EXISTS idx_quests_user_assigned
    ON quests(user_id, assigned_date DESC);

COMMENT ON INDEX idx_quests_user_assigned IS 'Optimizes recent quest completion rate queries';

-- Index for quest completion queries (fetchCompletionData - total completed)
-- Optimizes: SELECT COUNT(*) FROM quests WHERE user_id = ? AND completed = true
CREATE INDEX IF NOT EXISTS idx_quests_user_completed
    ON quests(user_id, completed);

COMMENT ON INDEX idx_quests_user_completed IS 'Optimizes total completed quest count queries';

-- Analyze tables to update query planner statistics
ANALYZE moods;
ANALYZE sleep_logs;
ANALYZE quests;
ANALYZE user_capacity;
