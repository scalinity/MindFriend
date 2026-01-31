-- Migration: Optimize get_home_context RPC performance
-- Issue: App hang (2-3s) caused by slow sequential queries in get_home_context
-- Root causes:
--   1. 7 sequential queries instead of parallel CTEs
--   2. ORDER BY RANDOM() for exercise selection (full table scan)
--   3. Missing indexes for exercise_sessions.completed_at, circle_posts.created_at

-- =====================================================
-- STEP 1: Add missing indexes for the slow queries
-- =====================================================

-- Index for exercise_sessions - optimizes days_since_exercise calculation
-- Covers (user_id, completed_at) for the MAX aggregation
CREATE INDEX IF NOT EXISTS idx_exercise_sessions_user_completed
ON exercise_sessions(user_id, completed_at DESC)
WHERE completed_at IS NOT NULL;

COMMENT ON INDEX idx_exercise_sessions_user_completed IS
  'Optimizes get_home_context days_since_exercise calculation';

-- Index for circle_posts - optimizes days_since_circle_checkin calculation
-- Uses created_at instead of posted_at (which doesn't exist)
CREATE INDEX IF NOT EXISTS idx_circle_posts_user_created
ON circle_posts(user_id, created_at DESC);

COMMENT ON INDEX idx_circle_posts_user_created IS
  'Optimizes get_home_context days_since_circle_checkin calculation';

-- Composite index for quests - optimizes quest_completed_today check
CREATE INDEX IF NOT EXISTS idx_quests_user_date_status
ON quests(user_id, local_date, status)
WHERE status = 'completed';

COMMENT ON INDEX idx_quests_user_date_status IS
  'Optimizes get_home_context quest_completed_today check with partial index';

-- Index for moods with mood_score for low mood calculation
CREATE INDEX IF NOT EXISTS idx_moods_user_created_score
ON moods(user_id, created_at DESC, mood_score);

COMMENT ON INDEX idx_moods_user_created_score IS
  'Optimizes mood trend and low mood days calculations in get_home_context';

-- =====================================================
-- STEP 2: Replace get_home_context with optimized version
-- Uses single CTE-based query instead of sequential queries
-- Replaces ORDER BY RANDOM() with faster modulo-based selection
-- =====================================================

CREATE OR REPLACE FUNCTION public.get_home_context(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_result JSONB;
BEGIN
    -- SECURITY CHECK: Prevent IDOR - caller must be the user or service_role
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;
    IF v_caller_id != p_user_id AND (SELECT auth.role()) != 'service_role' THEN
        RAISE EXCEPTION 'Access denied: cannot view another user''s home context';
    END IF;

    -- Single CTE-based query for all home context data
    -- This executes as parallel subqueries instead of sequential
    WITH
    -- Get today's mood (uses index on user_id, local_date)
    today_mood AS (
        SELECT mood_score
        FROM moods
        WHERE user_id = p_user_id
          AND local_date = CURRENT_DATE::TEXT
        ORDER BY created_at DESC
        LIMIT 1
    ),

    -- Calculate mood trend using a single scan with conditional aggregation
    mood_stats AS (
        SELECT
            AVG(CASE WHEN created_at > NOW() - INTERVAL '3 days' THEN mood_score END) AS recent_avg,
            AVG(CASE WHEN created_at <= NOW() - INTERVAL '3 days' AND created_at > NOW() - INTERVAL '7 days' THEN mood_score END) AS older_avg
        FROM moods
        WHERE user_id = p_user_id
          AND created_at > NOW() - INTERVAL '7 days'
    ),

    -- Count low mood days in single pass
    low_mood_count AS (
        SELECT COUNT(DISTINCT local_date) AS cnt
        FROM moods
        WHERE user_id = p_user_id
          AND created_at > NOW() - INTERVAL '7 days'
          AND mood_score <= 2
    ),

    -- Days since last exercise (uses partial index)
    exercise_days AS (
        SELECT COALESCE(
            (CURRENT_DATE - MAX(completed_at)::date)::INT,
            999
        ) AS days
        FROM exercise_sessions
        WHERE user_id = p_user_id
          AND completed_at IS NOT NULL
    ),

    -- Days since last circle check-in
    circle_days AS (
        SELECT COALESCE(
            (CURRENT_DATE - MAX(created_at)::date)::INT,
            999
        ) AS days
        FROM circle_posts
        WHERE user_id = p_user_id
    ),

    -- Quest completed today (uses partial index on status='completed')
    quest_status AS (
        SELECT EXISTS(
            SELECT 1 FROM quests
            WHERE user_id = p_user_id
              AND local_date = CURRENT_DATE::TEXT
              AND status = 'completed'
        ) AS done
    ),

    -- Get exercise recommendations WITHOUT ORDER BY RANDOM()
    -- Uses hashtext for deterministic daily rotation (UUIDs cannot be cast to int)
    -- This is O(n) scan with LIMIT, not O(n log n) sort
    recommended_exercises AS (
        SELECT ARRAY_AGG(e.id) AS ids
        FROM today_mood tm
        CROSS JOIN LATERAL (
            SELECT id
            FROM exercises
            WHERE NOT is_premium
              AND (
                -- For NULL/normal/high mood, allow all types
                -- For low mood (score <= 2), only breathing/grounding
                tm.mood_score IS NULL
                OR tm.mood_score > 2
                OR type IN ('breathing', 'grounding')
              )
            -- Deterministic daily rotation using hashtext (safe for UUIDs)
            ORDER BY hashtext(id::text || EXTRACT(DOY FROM CURRENT_DATE)::text)
            LIMIT 3
        ) e
    ),

    -- Aggregate all results
    context_data AS (
        SELECT
            tm.mood_score AS today_mood,
            CASE
                WHEN ms.recent_avg IS NULL OR ms.older_avg IS NULL THEN 'unknown'
                WHEN ms.recent_avg > ms.older_avg THEN 'improving'
                WHEN ms.recent_avg < ms.older_avg THEN 'declining'
                ELSE 'stable'
            END AS mood_trend,
            COALESCE(lmc.cnt, 0)::INT AS low_mood_days,
            COALESCE(ed.days, 999) AS days_since_exercise,
            COALESCE(cd.days, 999) AS days_since_circle,
            COALESCE(qs.done, false) AS quest_done,
            CASE
                WHEN tm.mood_score IS NULL THEN 'neutral'
                WHEN tm.mood_score <= 2 THEN 'low'
                WHEN tm.mood_score >= 4 THEN 'high'
                ELSE 'neutral'
            END AS mood_context,
            COALESCE(lmc.cnt, 0) >= 3 AS show_crisis,
            re.ids AS exercise_ids
        FROM today_mood tm
        FULL JOIN mood_stats ms ON true
        FULL JOIN low_mood_count lmc ON true
        FULL JOIN exercise_days ed ON true
        FULL JOIN circle_days cd ON true
        FULL JOIN quest_status qs ON true
        FULL JOIN recommended_exercises re ON true
    )
    SELECT jsonb_build_object(
        'today_mood', cd.today_mood,
        'mood_trend', cd.mood_trend,
        'consecutive_low_mood_days', cd.low_mood_days,
        'days_since_exercise', cd.days_since_exercise,
        'days_since_circle_checkin', cd.days_since_circle,
        'quest_completed_today', cd.quest_done,
        'mood_context', cd.mood_context,
        'show_crisis_support', cd.show_crisis,
        'supportive_message', CASE
            WHEN cd.mood_context = 'low' THEN 'It''s okay to have tough days. We''re here for you.'
            WHEN cd.mood_context = 'high' THEN 'Great to see you''re doing well!'
            ELSE 'How are you feeling today?'
        END,
        'recommended_actions', (
            SELECT COALESCE(jsonb_agg(action ORDER BY priority), '[]'::jsonb)
            FROM (
                SELECT jsonb_build_object('type', 'quest', 'title', 'Complete your daily quest', 'priority', 1) AS action, 1 AS priority
                WHERE NOT cd.quest_done
                UNION ALL
                SELECT jsonb_build_object('type', 'exercise', 'title', 'Try a quick exercise', 'priority', 2), 2
                WHERE cd.days_since_exercise > 2
                UNION ALL
                SELECT jsonb_build_object('type', 'circle', 'title', 'Check in with your circle', 'priority', 3), 3
                WHERE cd.days_since_circle > 3
            ) actions
        ),
        'recommended_exercise_ids', COALESCE(cd.exercise_ids, ARRAY[]::uuid[])
    ) INTO v_result
    FROM context_data cd;

    RETURN COALESCE(v_result, jsonb_build_object(
        'today_mood', NULL,
        'mood_trend', 'stable',
        'consecutive_low_mood_days', 0,
        'days_since_exercise', 999,
        'days_since_circle_checkin', 999,
        'quest_completed_today', false,
        'mood_context', 'neutral',
        'show_crisis_support', false,
        'supportive_message', 'How are you feeling today?',
        'recommended_actions', '[]'::jsonb,
        'recommended_exercise_ids', ARRAY[]::uuid[]
    ));
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.get_home_context(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_home_context(uuid) TO service_role;

-- =====================================================
-- STEP 3: Add overloaded version that uses auth.uid()
-- This allows calling without p_user_id parameter
-- =====================================================

CREATE OR REPLACE FUNCTION public.get_home_context()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    RETURN public.get_home_context(v_user_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_home_context() TO authenticated;

COMMENT ON FUNCTION public.get_home_context() IS
  'Optimized home context RPC - uses parallel CTEs instead of sequential queries';
COMMENT ON FUNCTION public.get_home_context(uuid) IS
  'Optimized home context RPC with explicit user_id parameter';

-- =====================================================
-- STEP 4: Analyze tables to update statistics for optimizer
-- =====================================================

ANALYZE moods;
ANALYZE exercise_sessions;
ANALYZE circle_posts;
ANALYZE quests;
ANALYZE exercises;
