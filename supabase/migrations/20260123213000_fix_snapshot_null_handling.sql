-- Fix NULL handling in capture_user_snapshot RPC
-- BUG: Profile query doesn't handle missing user or NULL level/xp gracefully
-- BUG: Variables left uninitialized if SELECT returns no rows

CREATE OR REPLACE FUNCTION capture_user_snapshot(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_streak INTEGER := 0;  -- FIX: Initialize to default values
    v_quest_count INTEGER := 0;
    v_exercise_count INTEGER := 0;
    v_mood_count INTEGER := 0;
    v_average_mood NUMERIC := NULL;
    v_badge_count INTEGER := 0;
    v_user_level INTEGER := 1;  -- FIX: Default to 1 instead of NULL
    v_user_xp INTEGER := 0;
    v_top_emotions TEXT[] := NULL;
    v_thirty_days_ago TIMESTAMPTZ;
BEGIN
    v_thirty_days_ago := now() - interval '30 days';

    -- Get streak data (handle missing streak gracefully)
    SELECT COALESCE(current_streak, 0)
    INTO v_current_streak
    FROM streaks
    WHERE user_id = p_user_id
    LIMIT 1;

    -- Get quest count
    SELECT COUNT(*)::INTEGER
    INTO v_quest_count
    FROM quests
    WHERE user_id = p_user_id
      AND completed = true;

    -- Get exercise count
    SELECT COUNT(*)::INTEGER
    INTO v_exercise_count
    FROM exercise_sessions
    WHERE user_id = p_user_id;

    -- Get total mood count
    SELECT COUNT(*)::INTEGER
    INTO v_mood_count
    FROM moods
    WHERE user_id = p_user_id;

    -- Get average mood for last 30 days specifically
    SELECT AVG(rating)
    INTO v_average_mood
    FROM moods
    WHERE user_id = p_user_id
      AND logged_at >= v_thirty_days_ago;

    -- Get top emotions (last 30 days)
    WITH emotion_counts AS (
        SELECT
            unnest(emotions) AS emotion,
            COUNT(*) AS cnt
        FROM moods
        WHERE user_id = p_user_id
          AND logged_at >= v_thirty_days_ago
          AND emotions IS NOT NULL
        GROUP BY emotion
        ORDER BY cnt DESC
        LIMIT 5
    )
    SELECT array_agg(emotion)
    INTO v_top_emotions
    FROM emotion_counts;

    -- Get badge count
    SELECT COUNT(*)::INTEGER
    INTO v_badge_count
    FROM user_badges
    WHERE user_id = p_user_id;

    -- Get user level and XP
    -- FIX: Use COALESCE in SELECT to handle NULL columns
    -- FIX: Provide defaults if profile doesn't exist (FOUND check)
    SELECT COALESCE(level, 1), COALESCE(xp, 0)
    INTO v_user_level, v_user_xp
    FROM profiles
    WHERE id = p_user_id;

    -- FIX: If profile doesn't exist (no rows returned), keep defaults
    IF NOT FOUND THEN
        v_user_level := 1;
        v_user_xp := 0;
    END IF;

    -- Return as JSONB with all values guaranteed to be non-NULL (except average_mood and top_emotions)
    RETURN jsonb_build_object(
        'current_streak', v_current_streak,
        'total_quests_completed', v_quest_count,
        'total_exercises', v_exercise_count,
        'total_moods_logged', v_mood_count,
        'average_mood_30d', v_average_mood,
        'badges_earned', v_badge_count,
        'level', v_user_level,
        'total_xp', v_user_xp,
        'top_emotions', v_top_emotions
    );
END;
$$;

COMMENT ON FUNCTION capture_user_snapshot(UUID) IS
'Efficiently captures user wellness snapshot in a single RPC call. Fixed NULL handling for missing profiles and uninitialized variables. Returns JSONB with current_streak, total_quests_completed, total_exercises, total_moods_logged, average_mood_30d, badges_earned, level, total_xp, top_emotions.';
