-- Migration: Add performance indexes for common query patterns
-- Issue: Missing indexes cause full table scans on filtered queries

-- Mood queries by user and date range (used heavily in mood history, weekly summaries)
CREATE INDEX IF NOT EXISTS idx_moods_user_date
ON moods(user_id, local_date DESC);

-- Conversation queries (user's recent conversations)
CREATE INDEX IF NOT EXISTS idx_conversations_user_updated
ON conversations(user_id, updated_at DESC);

-- Message queries by conversation (chat history)
CREATE INDEX IF NOT EXISTS idx_messages_conversation_created
ON messages(conversation_id, created_at ASC);

-- Exercise session queries by user (progress tracking)
CREATE INDEX IF NOT EXISTS idx_exercise_sessions_user
ON exercise_sessions(user_id, started_at DESC);

-- Quest queries by user and date (daily quest lookup)
CREATE INDEX IF NOT EXISTS idx_quests_user_date
ON quests(user_id, local_date DESC);

-- Add comment documenting the indexes
COMMENT ON INDEX idx_moods_user_date IS 'Optimizes mood history queries with date range filters';
COMMENT ON INDEX idx_conversations_user_updated IS 'Optimizes conversation list ordered by recent activity';
COMMENT ON INDEX idx_messages_conversation_created IS 'Optimizes chat history pagination';
COMMENT ON INDEX idx_exercise_sessions_user IS 'Optimizes exercise progress tracking queries';
COMMENT ON INDEX idx_quests_user_date IS 'Optimizes daily quest lookups and history';
