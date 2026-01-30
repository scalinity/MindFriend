-- Add composite index for quest completion queries (CA3 Performance recommendation)
-- This ensures O(log n) lookups for user quest history queries

CREATE INDEX IF NOT EXISTS idx_quests_user_completed
ON quests (user_id, completed_at)
WHERE completed_at IS NOT NULL;

-- Add index on user_stats for faster lookups during trigger execution
CREATE INDEX IF NOT EXISTS idx_user_stats_user_id
ON user_stats (user_id);

COMMENT ON INDEX idx_quests_user_completed IS
  'Composite index for efficient quest completion queries by user. Added 2026-01-30 per CA3 performance audit.';
