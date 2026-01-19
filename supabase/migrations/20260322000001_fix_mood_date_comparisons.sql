-- Fix "operator does not exist: date = text" error in mood-related functions
-- The moods.local_date column is DATE type, but queries were comparing it with TEXT
-- This migration fixes all such comparisons to use DATE = DATE

-- Fix calculate_mood_trend (no user_id parameter version)
CREATE OR REPLACE FUNCTION "public"."calculate_mood_trend"("p_days" integer DEFAULT 7)
RETURNS TABLE("trend" "text", "consecutive_low" integer, "avg_recent" double precision, "avg_previous" double precision, "today_mood" integer)
LANGUAGE "plpgsql" SECURITY DEFINER
SET "search_path" TO 'public'
AS $$
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

    -- Get today's mood (FIXED: use DATE = DATE comparison)
    SELECT mood_score INTO v_today_mood
    FROM moods
    WHERE user_id = v_user_id
        AND local_date = CURRENT_DATE
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
        SELECT m.local_date, m.mood_score,
               ROW_NUMBER() OVER (ORDER BY m.local_date DESC) as rn
        FROM moods m
        WHERE m.user_id = v_user_id
        ORDER BY m.local_date DESC
        LIMIT p_days
    )
    SELECT COUNT(*) INTO v_consecutive
    FROM (
        SELECT local_date, mood_score, rn,
               SUM(CASE WHEN mood_score > 2 THEN 1 ELSE 0 END) OVER (ORDER BY rn) as break_count
        FROM recent_moods
    ) sub
    WHERE break_count = 0 AND mood_score <= 2;

    -- Determine trend
    IF v_recent IS NULL OR v_previous IS NULL THEN
        v_trend := 'stable';
    ELSIF v_recent > v_previous + 0.5 THEN
        v_trend := 'improving';
    ELSIF v_recent < v_previous - 0.5 THEN
        v_trend := 'declining';
    ELSE
        v_trend := 'stable';
    END IF;

    RETURN QUERY SELECT v_trend, v_consecutive, v_recent, v_previous, v_today_mood;
END;
$$;

-- Fix calculate_mood_trend (with user_id parameter version)
CREATE OR REPLACE FUNCTION "public"."calculate_mood_trend"("p_user_id" "uuid", "p_days" integer DEFAULT 7)
RETURNS TABLE("trend" "text", "consecutive_low" integer, "avg_recent" double precision, "avg_previous" double precision, "today_mood" integer)
LANGUAGE "plpgsql" SECURITY DEFINER
SET "search_path" TO 'public'
AS $$
DECLARE
    v_recent FLOAT;
    v_previous FLOAT;
    v_consecutive INT := 0;
    v_today_mood INT;
    v_trend TEXT;
BEGIN
    -- Get today's mood (FIXED: use DATE = DATE comparison)
    SELECT mood_score INTO v_today_mood
    FROM moods
    WHERE user_id = p_user_id
        AND local_date = CURRENT_DATE
    LIMIT 1;

    -- Recent average (last N/2 days)
    SELECT AVG(mood_score)::FLOAT INTO v_recent
    FROM moods
    WHERE user_id = p_user_id
        AND created_at > NOW() - ((p_days / 2) || ' days')::INTERVAL;

    -- Previous average (N/2 to N days ago)
    SELECT AVG(mood_score)::FLOAT INTO v_previous
    FROM moods
    WHERE user_id = p_user_id
        AND created_at > NOW() - (p_days || ' days')::INTERVAL
        AND created_at <= NOW() - ((p_days / 2) || ' days')::INTERVAL;

    -- Count consecutive low mood days (mood <= 2)
    WITH recent_moods AS (
        SELECT m.local_date, m.mood_score,
               ROW_NUMBER() OVER (ORDER BY m.local_date DESC) as rn
        FROM moods m
        WHERE m.user_id = p_user_id
        ORDER BY m.local_date DESC
        LIMIT p_days
    )
    SELECT COUNT(*) INTO v_consecutive
    FROM (
        SELECT local_date, mood_score, rn,
               SUM(CASE WHEN mood_score > 2 THEN 1 ELSE 0 END) OVER (ORDER BY rn) as break_count
        FROM recent_moods
    ) sub
    WHERE break_count = 0 AND mood_score <= 2;

    -- Determine trend
    IF v_recent IS NULL OR v_previous IS NULL THEN
        v_trend := 'stable';
    ELSIF v_recent > v_previous + 0.5 THEN
        v_trend := 'improving';
    ELSIF v_recent < v_previous - 0.5 THEN
        v_trend := 'declining';
    ELSE
        v_trend := 'stable';
    END IF;

    RETURN QUERY SELECT v_trend, v_consecutive, v_recent, v_previous, v_today_mood;
END;
$$;

-- Fix get_home_context (no parameter version)
-- Note: We need to update the mood check to use DATE comparison
CREATE OR REPLACE FUNCTION "public"."get_home_context"()
RETURNS "jsonb"
LANGUAGE "plpgsql" SECURITY DEFINER
SET "search_path" TO 'public'
AS $$
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

    -- Check if quest completed today (FIXED: use TEXT comparison for quests.local_date which is TEXT)
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
            jsonb_build_object('type', 'gratitude', 'title', 'Gratitude', 'icon', 'sun.max.fill', 'priority', 2),
            jsonb_build_object('type', 'movement', 'title', 'Movement', 'icon', 'figure.walk', 'priority', 3)
        )
        ELSE jsonb_build_array(
            jsonb_build_object('type', 'quest', 'title', 'Daily Quest', 'icon', 'star.fill', 'priority', 1),
            jsonb_build_object('type', 'chat', 'title', 'Chat', 'icon', 'bubble.left.fill', 'priority', 2),
            jsonb_build_object('type', 'exercise', 'title', 'Exercise', 'icon', 'figure.mind.and.body', 'priority', 3)
        )
    END;

    -- Get recommended exercises based on mood
    SELECT COALESCE(
        jsonb_agg(jsonb_build_object(
            'id', e.id,
            'title', e.title,
            'type', e.type,
            'duration_minutes', e.duration_minutes
        )),
        '[]'::jsonb
    ) INTO v_recommended_exercises
    FROM (
        SELECT id, title, type, duration_minutes
        FROM exercises
        WHERE type = CASE v_mood_context
            WHEN 'low' THEN 'breathing'
            WHEN 'high' THEN 'movement'
            ELSE 'meditation'
        END
        ORDER BY RANDOM()
        LIMIT 3
    ) e;

    -- Build result
    v_result := jsonb_build_object(
        'mood_context', v_mood_context,
        'today_mood', v_today_mood,
        'mood_trend', v_mood_data.trend,
        'consecutive_low_days', v_mood_data.consecutive_low,
        'quest_completed', v_quest_done,
        'days_since_exercise', v_days_since_exercise,
        'days_since_circle', v_days_since_circle,
        'supportive_message', v_supportive_message,
        'show_crisis_support', v_show_crisis_support,
        'recommended_actions', v_recommended_actions,
        'recommended_exercises', v_recommended_exercises
    );

    RETURN v_result;
END;
$$;

-- Verify the fix by adding comments
COMMENT ON FUNCTION "public"."calculate_mood_trend"("p_days" integer) IS 'Calculate mood trend - fixed DATE comparison (moods.local_date is DATE type)';
COMMENT ON FUNCTION "public"."calculate_mood_trend"("p_user_id" "uuid", "p_days" integer) IS 'Calculate mood trend for user - fixed DATE comparison';
COMMENT ON FUNCTION "public"."get_home_context"() IS 'Get home context - fixed to use calculate_mood_trend with proper DATE comparisons';
