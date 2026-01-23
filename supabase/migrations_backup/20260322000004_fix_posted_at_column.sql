-- Migration: Fix posted_at column reference in get_home_context
-- The circle_posts table uses created_at, not posted_at

-- Fix get_home_context function to use created_at instead of posted_at
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

    -- Calculate days since last exercise (use EPOCH for accuracy)
    SELECT COALESCE(
        FLOOR(EXTRACT(EPOCH FROM NOW() - MAX(completed_at)) / 86400)::INT,
        999
    ) INTO v_days_since_exercise
    FROM exercise_sessions
    WHERE user_id = v_user_id;

    -- Calculate days since last circle check-in (FIXED: use created_at, not posted_at)
    SELECT COALESCE(
        FLOOR(EXTRACT(EPOCH FROM NOW() - MAX(created_at)) / 86400)::INT,
        999
    ) INTO v_days_since_circle
    FROM circle_posts
    WHERE user_id = v_user_id;

    -- Check if quest completed today (use TEXT comparison for quests.local_date which is TEXT)
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
            'duration_seconds', e.duration_seconds
        ) ORDER BY RANDOM()),
        '[]'::jsonb
    ) INTO v_recommended_exercises
    FROM (
        SELECT id, title, type, duration_seconds
        FROM exercises
        WHERE
            CASE v_mood_context
                WHEN 'low' THEN type IN ('breathing', 'meditation', 'grounding')
                WHEN 'high' THEN type IN ('movement', 'journaling', 'gratitude')
                ELSE type IN ('breathing', 'meditation', 'movement')
            END
            AND premium_only = FALSE
        LIMIT 3
    ) e;

    -- Build final result
    v_result := jsonb_build_object(
        'moodContext', v_mood_context,
        'todayMood', v_today_mood,
        'moodTrend', v_mood_data.trend,
        'consecutiveLowDays', COALESCE(v_mood_data.consecutive_low, 0),
        'daysSinceExercise', v_days_since_exercise,
        'daysSinceCircle', v_days_since_circle,
        'questDone', v_quest_done,
        'supportiveMessage', v_supportive_message,
        'recommendedActions', v_recommended_actions,
        'recommendedExercises', v_recommended_exercises,
        'showCrisisSupport', v_show_crisis_support
    );

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION get_home_context() IS 'Get personalized home screen context based on mood and activity patterns (fixed column reference)';

-- =============================================================================
-- Fix enforce_profiles_column_restrictions trigger function
-- Issue: The SELECT wrapper around auth.role() can cause "argument of AND must not return a set" error
-- =============================================================================

CREATE OR REPLACE FUNCTION enforce_profiles_column_restrictions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Service role can update any column (used by Edge Functions)
  IF current_setting('role', true) = 'service_role' THEN
    RETURN NEW;
  END IF;

  -- Authenticated users can only update safe columns
  -- FIXED: Remove SELECT wrapper that caused "argument of AND must not return a set" error
  IF auth.role() = 'authenticated' THEN
    -- Block updates to revenue-critical and quota columns
    IF NEW.subscription_tier IS DISTINCT FROM OLD.subscription_tier THEN
      RAISE EXCEPTION 'Insufficient privileges to modify subscription_tier';
    END IF;

    IF NEW.daily_ai_quota IS DISTINCT FROM OLD.daily_ai_quota THEN
      RAISE EXCEPTION 'Insufficient privileges to modify daily_ai_quota';
    END IF;

    IF NEW.daily_ai_used IS DISTINCT FROM OLD.daily_ai_used THEN
      RAISE EXCEPTION 'Insufficient privileges to modify daily_ai_used';
    END IF;

    IF NEW.quota_reset_at IS DISTINCT FROM OLD.quota_reset_at THEN
      RAISE EXCEPTION 'Insufficient privileges to modify quota_reset_at';
    END IF;

    IF NEW.premium_badge IS DISTINCT FROM OLD.premium_badge THEN
      RAISE EXCEPTION 'Insufficient privileges to modify premium_badge';
    END IF;

    -- Allow updates to these safe columns
    -- - handle
    -- - display_name
    -- - timezone
    -- - typical_active_hour (for smart notifications)
    -- - last_session_at, session_count, last_absence_days (for re-engagement tracking)
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION enforce_profiles_column_restrictions() IS 'Trigger function to restrict profile updates to safe columns for authenticated users (fixed auth.role() check)';
