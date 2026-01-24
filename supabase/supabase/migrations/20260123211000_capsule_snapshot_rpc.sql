-- Efficient snapshot capture using single RPC call
-- Fixes N+1 query problem (was 8 separate queries per snapshot)

CREATE OR REPLACE FUNCTION capture_user_snapshot(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_streak INTEGER;
    v_quest_count INTEGER;
    v_exercise_count INTEGER;
    v_mood_count INTEGER;
    v_average_mood NUMERIC;
    v_badge_count INTEGER;
    v_user_level INTEGER;
    v_user_xp INTEGER;
    v_top_emotions TEXT[];
    v_thirty_days_ago TIMESTAMPTZ;
BEGIN
    v_thirty_days_ago := now() - interval '30 days';

    -- Get streak data
    SELECT current_streak
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

    -- Get mood stats (count and average for last 30 days)
    SELECT
        COUNT(*)::INTEGER,
        AVG(rating)
    INTO v_mood_count, v_average_mood
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
    SELECT level, xp
    INTO v_user_level, v_user_xp
    FROM profiles
    WHERE id = p_user_id;

    -- Return as JSONB
    RETURN jsonb_build_object(
        'current_streak', COALESCE(v_current_streak, 0),
        'total_quests_completed', COALESCE(v_quest_count, 0),
        'total_exercises', COALESCE(v_exercise_count, 0),
        'total_moods_logged', COALESCE(v_mood_count, 0),
        'average_mood_30d', v_average_mood,
        'badges_earned', COALESCE(v_badge_count, 0),
        'level', COALESCE(v_user_level, 1),
        'total_xp', COALESCE(v_user_xp, 0),
        'top_emotions', v_top_emotions
    );
END;
$$;

COMMENT ON FUNCTION capture_user_snapshot(UUID) IS
'Efficiently captures user wellness snapshot in a single RPC call. Returns JSONB with current_streak, total_quests_completed, total_exercises, total_moods_logged, average_mood_30d, badges_earned, level, total_xp, top_emotions.';

-- Create index to optimize snapshot queries
CREATE INDEX IF NOT EXISTS idx_moods_user_logged_at ON moods(user_id, logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_quests_user_completed ON quests(user_id, completed) WHERE completed = true;
CREATE INDEX IF NOT EXISTS idx_exercise_sessions_user ON exercise_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_badges_user ON user_badges(user_id);
