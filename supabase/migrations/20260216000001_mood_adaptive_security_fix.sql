-- Migration: Security Fix for Mood-Adaptive Home
-- Fixes CRITICAL IDOR vulnerability and other issues:
-- 1. CRITICAL: Add auth.uid() validation to RPC functions
-- 2. MEDIUM: Fix EXTRACT(DAY) precision for long intervals
-- 3. LOW: Add DELETE policy for user_home_context
-- 4. LOW: Add SET search_path = public to SECURITY DEFINER functions

-- ============================================================================
-- 1. Add DELETE Policy (GDPR compliance)
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'user_home_context'
        AND policyname = 'Users can delete own home context'
    ) THEN
        CREATE POLICY "Users can delete own home context"
            ON user_home_context FOR DELETE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================================================
-- 2. Secure Calculate Mood Trend Function
-- SECURITY FIX: Uses auth.uid() directly, validates authentication
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_mood_trend(
    p_days INT DEFAULT 7
)
RETURNS TABLE (
    trend TEXT,
    consecutive_low INT,
    avg_recent FLOAT,
    avg_previous FLOAT,
    today_mood INT
) AS $$
DECLARE
    v_user_id UUID;
    v_recent FLOAT;
    v_previous FLOAT;
    v_consecutive INT := 0;
    v_today_mood INT;
    v_trend TEXT;
BEGIN
    -- SECURITY: Get authenticated user ID (no user-controlled parameter)
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Get today's mood
    SELECT mood_score INTO v_today_mood
    FROM moods
    WHERE user_id = v_user_id
        AND local_date = TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD')
    LIMIT 1;

    -- Recent average (last N/2 days)
    SELECT AVG(mood_score)::FLOAT INTO v_recent
    FROM moods
    WHERE user_id = v_user_id
        AND created_at > NOW() - ((p_days / 2) || ' days')::INTERVAL;

    -- Previous average (N/2 to N days ago)
    SELECT AVG(mood_score)::FLOAT INTO v_previous
    FROM moods
    WHERE user_id = v_user_id
        AND created_at > NOW() - (p_days || ' days')::INTERVAL
        AND created_at <= NOW() - ((p_days / 2) || ' days')::INTERVAL;

    -- Count consecutive low mood days (mood <= 2)
    -- Start from most recent and count backwards
    WITH recent_moods AS (
        SELECT local_date, mood_score,
               ROW_NUMBER() OVER (ORDER BY local_date DESC) as rn
        FROM moods
        WHERE user_id = v_user_id
        ORDER BY local_date DESC
        LIMIT p_days
    )
    SELECT COUNT(*) INTO v_consecutive
    FROM (
        SELECT local_date, mood_score, rn,
               rn - ROW_NUMBER() OVER (ORDER BY local_date DESC) as grp
        FROM recent_moods
        WHERE mood_score <= 2
    ) grouped
    WHERE grp = 0;  -- Only count the first continuous group from today

    -- Determine trend
    v_trend := CASE
        WHEN v_recent IS NULL OR v_previous IS NULL THEN 'unknown'
        WHEN v_recent > v_previous + 0.5 THEN 'improving'
        WHEN v_recent < v_previous - 0.5 THEN 'declining'
        ELSE 'stable'
    END;

    -- Return results
    trend := v_trend;
    consecutive_low := COALESCE(v_consecutive, 0);
    avg_recent := v_recent;
    avg_previous := v_previous;
    today_mood := v_today_mood;

    RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================================
-- 3. Secure Get Home Context RPC
-- SECURITY FIX: Uses auth.uid() directly, validates authentication
-- FIX: Uses EXTRACT(EPOCH...) for accurate day counting
-- ============================================================================

CREATE OR REPLACE FUNCTION get_home_context()
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_result JSONB;
    v_mood_data RECORD;
    v_today_mood INT;
    v_days_since_exercise INT;
    v_days_since_circle INT;
    v_quest_done BOOLEAN;
    v_mood_context TEXT;
    v_supportive_message TEXT;
    v_recommended_actions JSONB;
    v_recommended_exercises JSONB;
    v_show_crisis_support BOOLEAN;
BEGIN
    -- SECURITY: Get authenticated user ID (no user-controlled parameter)
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Get mood trend data
    SELECT * INTO v_mood_data
    FROM calculate_mood_trend(7);

    v_today_mood := v_mood_data.today_mood;

    -- Calculate days since last exercise (FIXED: use EPOCH for accuracy)
    SELECT COALESCE(
        FLOOR(EXTRACT(EPOCH FROM NOW() - MAX(completed_at)) / 86400)::INT,
        999
    ) INTO v_days_since_exercise
    FROM exercise_sessions
    WHERE user_id = v_user_id;

    -- Calculate days since last circle check-in (FIXED: use EPOCH for accuracy)
    SELECT COALESCE(
        FLOOR(EXTRACT(EPOCH FROM NOW() - MAX(posted_at)) / 86400)::INT,
        999
    ) INTO v_days_since_circle
    FROM circle_posts
    WHERE user_id = v_user_id;

    -- Check if quest completed today
    SELECT EXISTS(
        SELECT 1 FROM quests
        WHERE user_id = v_user_id
            AND local_date = TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD')
            AND status = 'completed'
    ) INTO v_quest_done;

    -- Determine mood context (low, neutral, high)
    v_mood_context := CASE
        WHEN v_today_mood IS NULL THEN 'neutral'
        WHEN v_today_mood <= 2 THEN 'low'
        WHEN v_today_mood >= 4 THEN 'high'
        ELSE 'neutral'
    END;

    -- Determine if we should show crisis support
    v_show_crisis_support := (v_mood_data.consecutive_low >= 2) OR (COALESCE(v_today_mood, 3) <= 1);

    -- Build supportive message based on context
    v_supportive_message := CASE
        WHEN v_mood_data.consecutive_low >= 3 THEN
            'You''ve had a few tough days. Remember, it''s okay to seek support. We''re here for you.'
        WHEN v_mood_data.consecutive_low >= 2 THEN
            'It''s okay to have hard days. Would you like to talk or try something calming?'
        WHEN COALESCE(v_today_mood, 3) <= 1 THEN
            'We''re here for you. Take it one moment at a time.'
        WHEN v_mood_data.trend = 'declining' THEN
            'We noticed things might feel heavier lately. Small steps count.'
        WHEN COALESCE(v_today_mood, 3) >= 4 THEN
            'You''re radiating positivity today!'
        ELSE NULL
    END;

    -- Build recommended actions based on mood context and activity
    v_recommended_actions := CASE v_mood_context
        WHEN 'low' THEN jsonb_build_array(
            jsonb_build_object('type', 'chat', 'title', 'Talk to AI', 'icon', 'bubble.left.fill', 'priority', 1),
            jsonb_build_object('type', 'breathing', 'title', 'Calm Breathing', 'icon', 'wind', 'priority', 2),
            jsonb_build_object('type', 'circle', 'title', 'Reach Out', 'icon', 'heart.fill', 'priority', 3)
        )
        WHEN 'high' THEN jsonb_build_array(
            jsonb_build_object('type', 'share', 'title', 'Share Joy', 'icon', 'heart.circle.fill', 'priority', 1),
            jsonb_build_object('type', 'celebrate', 'title', 'Try Challenge', 'icon', 'star.fill', 'priority', 2),
            jsonb_build_object('type', 'exercise', 'title', 'Explore New', 'icon', 'sparkles', 'priority', 3)
        )
        ELSE -- neutral: time-based and activity-based
            jsonb_build_array(
                jsonb_build_object('type', 'exercise', 'title', 'Quick Exercise', 'icon', 'figure.mind.and.body', 'priority', 1),
                CASE WHEN v_days_since_exercise >= 2 THEN
                    jsonb_build_object('type', 'exercise', 'title', 'Move', 'icon', 'figure.walk', 'priority', 2)
                ELSE
                    jsonb_build_object('type', 'breathing', 'title', 'Breathe', 'icon', 'wind', 'priority', 2)
                END,
                CASE WHEN v_days_since_circle >= 3 THEN
                    jsonb_build_object('type', 'circle', 'title', 'Check In', 'icon', 'person.2.fill', 'priority', 3)
                ELSE
                    jsonb_build_object('type', 'quest', 'title', 'Quest', 'icon', 'star.fill', 'priority', 3)
                END
            )
    END;

    -- Get recommended exercises based on mood and time
    WITH recommended AS (
        SELECT id
        FROM exercises
        WHERE is_premium = false  -- Free exercises only for recommendations
        AND type IN (
            CASE
                WHEN COALESCE(v_today_mood, 3) <= 2 THEN 'breathing'
                WHEN COALESCE(v_today_mood, 3) >= 4 THEN 'movement'
                ELSE 'meditation'
            END,
            CASE
                WHEN COALESCE(v_today_mood, 3) <= 2 THEN 'grounding'
                ELSE 'breathing'
            END
        )
        ORDER BY RANDOM()
        LIMIT 5
    )
    SELECT COALESCE(jsonb_agg(id), '[]'::jsonb) INTO v_recommended_exercises
    FROM recommended;

    -- Build final result
    v_result := jsonb_build_object(
        'today_mood', v_today_mood,
        'mood_trend', v_mood_data.trend,
        'consecutive_low_mood_days', COALESCE(v_mood_data.consecutive_low, 0),
        'days_since_exercise', LEAST(v_days_since_exercise, 999),
        'days_since_circle_checkin', LEAST(v_days_since_circle, 999),
        'quest_completed_today', v_quest_done,
        'mood_context', v_mood_context,
        'show_crisis_support', v_show_crisis_support,
        'supportive_message', v_supportive_message,
        'recommended_actions', v_recommended_actions,
        'recommended_exercise_ids', v_recommended_exercises
    );

    -- Cache the result (upsert)
    INSERT INTO user_home_context (
        user_id,
        context_date,
        today_mood,
        mood_trend,
        consecutive_low_mood_days,
        days_since_exercise,
        days_since_circle_checkin,
        quest_completed_today,
        recommended_exercise_ids,
        recommended_actions,
        supportive_message,
        generated_at
    ) VALUES (
        v_user_id,
        CURRENT_DATE,
        v_today_mood,
        v_mood_data.trend,
        COALESCE(v_mood_data.consecutive_low, 0),
        v_days_since_exercise,
        v_days_since_circle,
        v_quest_done,
        v_recommended_exercises,
        v_recommended_actions,
        v_supportive_message,
        NOW()
    )
    ON CONFLICT (user_id, context_date) DO UPDATE SET
        today_mood = EXCLUDED.today_mood,
        mood_trend = EXCLUDED.mood_trend,
        consecutive_low_mood_days = EXCLUDED.consecutive_low_mood_days,
        days_since_exercise = EXCLUDED.days_since_exercise,
        days_since_circle_checkin = EXCLUDED.days_since_circle_checkin,
        quest_completed_today = EXCLUDED.quest_completed_today,
        recommended_exercise_ids = EXCLUDED.recommended_exercise_ids,
        recommended_actions = EXCLUDED.recommended_actions,
        supportive_message = EXCLUDED.supportive_message,
        generated_at = NOW();

    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
