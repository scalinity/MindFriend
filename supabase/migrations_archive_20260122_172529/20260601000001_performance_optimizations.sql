-- =============================================================================
-- Performance Optimizations Migration
-- Addresses 766 performance issues flagged by Supabase Performance Advisor
-- =============================================================================
--
-- Analysis summary:
-- - Most "issues" are unused indexes (not harmful but waste space)
-- - Some tables have high sequential scan counts
-- - Dashboard/system queries account for most slow query time
-- - Application queries are generally efficient
--
-- This migration:
-- 1. Adds strategic indexes for high-traffic tables
-- 2. Updates table statistics with ANALYZE
-- 3. Sets function costs for better query planning
-- =============================================================================

-- =============================================================================
-- PART 1: Add indexes for tables with high sequential scan rates
-- =============================================================================

-- quests table: 344 seq scans, 30 rows
-- Common query pattern: WHERE user_id = ? AND local_date = ? AND status = ?
CREATE INDEX IF NOT EXISTS idx_quests_user_status
ON quests(user_id, status)
WHERE status IN ('assigned', 'in_progress');

-- user_stats table: 255 seq scans (but only 1 row, so seq scan is fine)
-- No index needed - sequential scan on 1 row is optimal

-- moods table: 238 seq scans, 31 rows
-- Common query pattern: WHERE user_id = ? ORDER BY created_at DESC
CREATE INDEX IF NOT EXISTS idx_moods_user_created
ON moods(user_id, created_at DESC);

-- weekly_summaries table: 124 seq scans
-- Common query pattern: WHERE user_id = ? AND week_start = ?
CREATE INDEX IF NOT EXISTS idx_weekly_summaries_user_week
ON weekly_summaries(user_id, week_start DESC);

-- buddy_relationships table: 100 seq scans (0 rows, not needed yet)
-- Skip - no data

-- quest_templates table: 106 seq scans, 68 rows
-- Common query pattern: WHERE is_active = true AND category = ?
CREATE INDEX IF NOT EXISTS idx_quest_templates_active_category
ON quest_templates(category)
WHERE is_active = true;

-- programs table: 59 seq scans
-- Common query pattern: WHERE is_active = true
CREATE INDEX IF NOT EXISTS idx_programs_active
ON programs(is_active)
WHERE is_active = true;

-- subscriptions table: 62 seq scans (0 rows)
-- Common query pattern: WHERE user_id = ? AND status = 'active'
CREATE INDEX IF NOT EXISTS idx_subscriptions_user_active
ON subscriptions(user_id)
WHERE status = 'active';

-- memory_fragments table: 48 seq scans (1 row)
-- Already has good indexes

-- program_enrollments table: 40 seq scans
-- Common query pattern: WHERE user_id = ? AND status = 'active'
-- Already has idx_enrollments_user_status

-- =============================================================================
-- PART 2: Add composite indexes for common JOIN patterns
-- =============================================================================

-- circles + circle_members JOIN optimization
CREATE INDEX IF NOT EXISTS idx_circle_members_user_circle
ON circle_members(user_id, circle_id);

-- exercise_sessions: optimize by user and date
CREATE INDEX IF NOT EXISTS idx_exercise_sessions_user_completed
ON exercise_sessions(user_id, completed_at DESC);

-- conversations: optimize by user and recent
-- Note: already has idx_conversations_user which covers this pattern
-- Skipping duplicate index

-- messages: optimize by conversation and time
CREATE INDEX IF NOT EXISTS idx_messages_conversation_time
ON messages(conversation_id, created_at DESC);

-- circle_posts: optimize by circle and time
-- Note: already has idx_circle_posts_circle which covers this pattern
-- Skipping duplicate index

-- =============================================================================
-- PART 3: Update statistics on high-traffic tables
-- =============================================================================

ANALYZE profiles;
ANALYZE quests;
ANALYZE moods;
ANALYZE user_stats;
ANALYZE quest_templates;
ANALYZE exercises;
ANALYZE conversations;
ANALYZE messages;
ANALYZE circles;
ANALYZE circle_members;
ANALYZE circle_posts;
ANALYZE subscriptions;
ANALYZE exercise_sessions;
ANALYZE programs;
ANALYZE program_enrollments;
ANALYZE badges_v2;
ANALYZE weekly_summaries;
ANALYZE memory_fragments;
ANALYZE user_settings;

-- =============================================================================
-- PART 4: Set appropriate function costs for query planner
-- =============================================================================

-- Set function costs only if they exist (to handle partial schema states)
DO $$
BEGIN
    -- High-cost functions (complex logic, multiple queries)
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_home_context') THEN
        EXECUTE 'ALTER FUNCTION get_home_context(UUID) COST 1000';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'calculate_mood_trend') THEN
        EXECUTE 'ALTER FUNCTION calculate_mood_trend(UUID, INT) COST 500';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'assign_daily_quest') THEN
        EXECUTE 'ALTER FUNCTION assign_daily_quest(UUID) COST 500';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'check_streak_protection') THEN
        EXECUTE 'ALTER FUNCTION check_streak_protection(UUID) COST 300';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_weighted_quest_for_user') THEN
        EXECUTE 'ALTER FUNCTION get_weighted_quest_for_user(UUID, TEXT) COST 500';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'generate_quest_alternatives') THEN
        EXECUTE 'ALTER FUNCTION generate_quest_alternatives(UUID, DATE) COST 500';
    END IF;

    -- Medium-cost functions
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_shield_status') THEN
        EXECUTE 'ALTER FUNCTION get_shield_status(UUID) COST 100';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'is_moderator') THEN
        EXECUTE 'ALTER FUNCTION is_moderator() COST 10';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'is_partner_linked') THEN
        EXECUTE 'ALTER FUNCTION is_partner_linked(UUID) COST 50';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_partner_id') THEN
        EXECUTE 'ALTER FUNCTION get_partner_id(UUID) COST 50';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'is_family_member') THEN
        EXECUTE 'ALTER FUNCTION is_family_member(UUID, UUID) COST 50';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'is_family_parent') THEN
        EXECUTE 'ALTER FUNCTION is_family_parent(UUID, UUID) COST 50';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'user_has_premium') THEN
        EXECUTE 'ALTER FUNCTION user_has_premium(UUID) COST 50';
    END IF;

    -- Low-cost functions (simple lookups)
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'generate_anonymous_name') THEN
        EXECUTE 'ALTER FUNCTION generate_anonymous_name() COST 10';
    END IF;
END $$;

-- =============================================================================
-- PART 5: Remove clearly unused indexes (OPTIONAL - commented out for safety)
-- =============================================================================

-- These indexes have 0 usage but might be needed for future features.
-- Uncomment to remove if disk space is a concern.

-- DROP INDEX CONCURRENTLY IF EXISTS idx_journal_prompts_mood;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_micro_templates_context;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_audio_tracks_tags;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_sleep_content_active;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_live_sessions_active;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_audio_tracks_duration;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_voice_sessions_started_at;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_programs_premium;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_crisis_resources_country;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_journal_prompts_premium;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_published_exercises;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_sleep_content_type;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_habit_templates_category;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_voice_sessions_user_id;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_micro_templates_type;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_sleep_content_premium;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_routine_templates_type;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_engagement_states_state;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_audio_tracks_narrator;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_engagement_states_last_activity;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_badges_v2_seasonal;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_sleep_content_category;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_audio_collections_active;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_live_sessions_scheduled;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_couples_exercises_status;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_therapist_profiles_specialties;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_crisis_resources_default;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_crisis_resources_country_lang;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_listeners_specializations;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_soundscape_sounds_category_active;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_soundscape_sounds_category;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_sleep_content_type_category;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_audio_tracks_featured;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_coping_kits_context;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_audio_tracks_category;
-- DROP INDEX CONCURRENTLY IF EXISTS idx_micro_templates_active;

-- =============================================================================
-- PART 6: Enable pg_stat_statements for future query monitoring
-- =============================================================================

-- pg_stat_statements is already enabled on Supabase by default
-- This is informational only

-- =============================================================================
-- MIGRATION COMPLETE
-- =============================================================================
--
-- Expected improvements:
-- - Faster lookups on quests, moods, weekly_summaries
-- - Better query planning with updated statistics
-- - More accurate cost estimates for function calls
--
-- Note: The 766 "performance issues" include many that are:
-- - Unused indexes (not harmful, just not used yet)
-- - Tables without explicit PRIMARY KEY (system tables)
-- - Functions without COST (now fixed for key functions)
-- - Dashboard/metadata queries (outside our control)
--
-- Real application performance should be monitored via:
-- - Supabase Dashboard > Performance
-- - pg_stat_statements for query analysis
-- =============================================================================
