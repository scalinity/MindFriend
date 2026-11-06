-- Private readers require the actual account owner or circle membership.
BEGIN;

CREATE OR REPLACE FUNCTION "public"."calculate_mood_trend"("p_user_id" "uuid", "p_days" integer DEFAULT 7) RETURNS TABLE("trend" "text", "consecutive_low" integer, "avg_recent" double precision, "avg_previous" double precision, "today_mood" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER COST 500
    SET search_path TO pg_catalog, public, pg_temp
    AS $$
DECLARE
    v_recent FLOAT;
    v_previous FLOAT;
    v_consecutive INT := 0;
    v_today_mood INT;
    v_trend TEXT;
BEGIN

  IF p_user_id IS NULL OR (
    current_setting('role', true) IS DISTINCT FROM 'service_role'
    AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id)
  ) THEN
    RAISE EXCEPTION 'Account owner required' USING ERRCODE = '42501';
  END IF;
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
REVOKE ALL ON FUNCTION public.calculate_mood_trend(uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.calculate_mood_trend(uuid,integer) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION "public"."calculate_user_absence"("p_user_id" "uuid") RETURNS TABLE("absence_days" integer, "lapse_tier" "text", "hugs_received" integer, "circle_posts" integer, "friend_milestones" "jsonb")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET search_path TO pg_catalog, public, pg_temp
    AS $$
DECLARE
  v_last_session TIMESTAMPTZ;
  v_days INT;
  v_tier TEXT;
  v_hugs INT;
  v_posts INT;
  v_milestones JSONB;
BEGIN

  IF p_user_id IS NULL OR (
    current_setting('role', true) IS DISTINCT FROM 'service_role'
    AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id)
  ) THEN
    RAISE EXCEPTION 'Account owner required' USING ERRCODE = '42501';
  END IF;
  -- Get last session
  SELECT last_session_at INTO v_last_session FROM profiles WHERE id = p_user_id;

  -- Calculate days absent
  v_days := COALESCE(EXTRACT(DAY FROM NOW() - v_last_session)::INT, 0);

  -- Determine tier per spec
  v_tier := CASE
    WHEN v_days < 3 THEN 'active'
    WHEN v_days < 7 THEN 'brief_break'
    WHEN v_days < 14 THEN 'extended_break'
    WHEN v_days < 30 THEN 'long_absence'
    ELSE 'hiatus'
  END;

  -- Count hugs received since last session
  SELECT COUNT(*)::INT INTO v_hugs
  FROM circle_hugs
  WHERE recipient_id = p_user_id
    AND created_at > COALESCE(v_last_session, NOW() - INTERVAL '30 days');

  -- Count circle posts from others in user's circles
  SELECT COUNT(*)::INT INTO v_posts
  FROM circle_posts cp
  JOIN circle_members cm ON cm.circle_id = cp.circle_id
  WHERE cm.user_id = p_user_id
    AND cp.user_id != p_user_id
    AND cp.created_at > COALESCE(v_last_session, NOW() - INTERVAL '30 days');

  -- Get friend milestones (streak achievements, badges, etc.)
  SELECT COALESCE(json_agg(json_build_object(
    'name', p.display_name,
    'milestone', cp.body_text,
    'isStreak', CASE WHEN cp.body_text ILIKE '%streak%' THEN TRUE ELSE FALSE END
  )), '[]'::json)::jsonb INTO v_milestones
  FROM circle_posts cp
  JOIN profiles p ON p.id = cp.user_id
  JOIN circle_members cm ON cm.circle_id = cp.circle_id
  WHERE cm.user_id = p_user_id
    AND cp.kind = 'milestone'
    AND cp.user_id != p_user_id
    AND cp.created_at > COALESCE(v_last_session, NOW() - INTERVAL '30 days')
  LIMIT 5;

  -- Return the results
  RETURN QUERY SELECT v_days, v_tier, COALESCE(v_hugs, 0), COALESCE(v_posts, 0), COALESCE(v_milestones, '[]'::jsonb);
END;
$$;
REVOKE ALL ON FUNCTION public.calculate_user_absence(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.calculate_user_absence(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION "public"."calculate_weekly_stats"("p_user_id" "uuid") RETURNS TABLE("checkin_count" integer, "quest_count" integer, "exercise_count" integer, "avg_mood" double precision, "mood_trend" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET search_path TO pg_catalog, public, pg_temp
    AS $$
DECLARE
  v_week_start TIMESTAMPTZ;
  v_prev_week_start TIMESTAMPTZ;
  v_this_week_avg FLOAT;
  v_prev_week_avg FLOAT;
  v_trend TEXT;
BEGIN

  IF p_user_id IS NULL OR (
    current_setting('role', true) IS DISTINCT FROM 'service_role'
    AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id)
  ) THEN
    RAISE EXCEPTION 'Account owner required' USING ERRCODE = '42501';
  END IF;
  -- Get start of current week (Monday)
  v_week_start := date_trunc('week', NOW());
  v_prev_week_start := v_week_start - INTERVAL '7 days';

  -- Calculate this week's average mood
  SELECT AVG(mood_score) INTO v_this_week_avg
  FROM moods
  WHERE user_id = p_user_id
    AND created_at >= v_week_start;

  -- Calculate previous week's average mood for trend
  SELECT AVG(mood_score) INTO v_prev_week_avg
  FROM moods
  WHERE user_id = p_user_id
    AND created_at >= v_prev_week_start
    AND created_at < v_week_start;

  -- Determine trend
  IF v_this_week_avg IS NULL OR v_prev_week_avg IS NULL THEN
    v_trend := 'stable';
  ELSIF v_this_week_avg > v_prev_week_avg + 0.5 THEN
    v_trend := 'improving';
  ELSIF v_this_week_avg < v_prev_week_avg - 0.5 THEN
    v_trend := 'declining';
  ELSE
    v_trend := 'stable';
  END IF;

  RETURN QUERY
  SELECT
    (SELECT COUNT(*)::int FROM moods WHERE user_id = p_user_id AND created_at >= v_week_start),
    (SELECT COUNT(*)::int FROM quests WHERE user_id = p_user_id AND status = 'completed' AND completed_at >= v_week_start),
    (SELECT COUNT(*)::int FROM exercise_sessions WHERE user_id = p_user_id AND created_at >= v_week_start),
    v_this_week_avg,
    v_trend;
END;
$$;
REVOKE ALL ON FUNCTION public.calculate_weekly_stats(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.calculate_weekly_stats(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION "public"."get_buddy_widget_data"("p_user_id" "uuid") RETURNS TABLE("buddy_name" "text", "buddy_streak" integer, "buddy_id" "uuid", "relationship_id" "uuid", "has_completed_today" boolean, "needs_check_in" boolean, "last_encouragement_id" "uuid", "last_encouragement_type" "text", "last_encouragement_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET search_path TO pg_catalog, public, pg_temp
    AS $$
DECLARE
  v_buddy_id UUID;
  v_relationship_id UUID;
  v_buddy_name TEXT;
  v_buddy_streak INT;
  v_has_completed BOOLEAN;
  v_needs_checkin BOOLEAN;
  v_last_enc_id UUID;
  v_last_enc_type TEXT;
  v_last_enc_at TIMESTAMPTZ;
  v_today DATE := CURRENT_DATE;
  v_two_days_ago DATE := CURRENT_DATE - INTERVAL '2 days';
BEGIN

  IF p_user_id IS NULL OR (
    current_setting('role', true) IS DISTINCT FROM 'service_role'
    AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id)
  ) THEN
    RAISE EXCEPTION 'Account owner required' USING ERRCODE = '42501';
  END IF;
  -- Find first active buddy relationship
  SELECT
    br.id,
    CASE WHEN br.inviter_id = p_user_id THEN br.invitee_id ELSE br.inviter_id END
  INTO v_relationship_id, v_buddy_id
  FROM buddy_relationships br
  WHERE (br.inviter_id = p_user_id OR br.invitee_id = p_user_id)
    AND br.status = 'accepted'
  ORDER BY br.accepted_at DESC
  LIMIT 1;

  IF v_buddy_id IS NULL THEN
    RETURN;
  END IF;

  -- Get buddy profile
  SELECT display_name, COALESCE(current_streak_days, 0)
  INTO v_buddy_name, v_buddy_streak
  FROM profiles
  WHERE id = v_buddy_id;

  -- Check if buddy completed quest today
  SELECT EXISTS (
    SELECT 1 FROM quests
    WHERE user_id = v_buddy_id
      AND local_date = TO_CHAR(v_today, 'YYYY-MM-DD')
      AND status = 'completed'
  ) INTO v_has_completed;

  -- Check if buddy needs check-in (no activity in 2+ days)
  SELECT NOT EXISTS (
    SELECT 1 FROM quests
    WHERE user_id = v_buddy_id
      AND local_date >= TO_CHAR(v_two_days_ago, 'YYYY-MM-DD')
  ) INTO v_needs_checkin;

  -- Get last encouragement
  SELECT id, message_type, created_at
  INTO v_last_enc_id, v_last_enc_type, v_last_enc_at
  FROM buddy_encouragements
  WHERE buddy_relationship_id = v_relationship_id
  ORDER BY created_at DESC
  LIMIT 1;

  RETURN QUERY SELECT
    v_buddy_name,
    v_buddy_streak,
    v_buddy_id,
    v_relationship_id,
    v_has_completed,
    v_needs_checkin,
    v_last_enc_id,
    v_last_enc_type,
    v_last_enc_at;
END;
$$;
REVOKE ALL ON FUNCTION public.get_buddy_widget_data(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_buddy_widget_data(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION "public"."get_circle_presence"("p_circle_id" "uuid") RETURNS TABLE("user_id" "uuid", "display_name" "text", "status" "text", "last_seen_at" timestamp with time zone, "current_activity" "text", "is_online" boolean, "is_recently_active" boolean)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET search_path TO pg_catalog, public, pg_temp
    AS $$
BEGIN

  IF p_circle_id IS NULL OR (
    current_setting('role', true) IS DISTINCT FROM 'service_role'
    AND (auth.uid() IS NULL OR NOT EXISTS (
      SELECT 1 FROM public.circle_members AS caller
      WHERE caller.circle_id = p_circle_id AND caller.user_id = auth.uid()
    ))
  ) THEN
    RAISE EXCEPTION 'Circle membership required' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT
    up.user_id,
    p.display_name,
    up.status,
    up.last_seen_at,
    up.current_activity,
    (up.status = 'online' AND up.last_seen_at > NOW() - INTERVAL '2 minutes') AS is_online,
    (up.last_seen_at > NOW() - INTERVAL '15 minutes') AS is_recently_active
  FROM user_presence up
  JOIN profiles p ON p.id = up.user_id
  JOIN circle_members cm ON cm.user_id = up.user_id AND cm.circle_id = p_circle_id
  JOIN user_settings us ON us.user_id = up.user_id AND us.show_presence = TRUE
  WHERE up.last_seen_at > NOW() - INTERVAL '15 minutes'
  ORDER BY up.last_seen_at DESC;
END;
$$;
REVOKE ALL ON FUNCTION public.get_circle_presence(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_circle_presence(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION "public"."get_notification_engagement_stats"("p_user_id" "uuid") RETURNS TABLE("delivered" integer, "opened" integer, "completed" integer, "dismissed" integer, "engagement_rate" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET search_path TO pg_catalog, public, pg_temp
    AS $$
DECLARE
    v_week_start TIMESTAMPTZ;
BEGIN

  IF p_user_id IS NULL OR (
    current_setting('role', true) IS DISTINCT FROM 'service_role'
    AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id)
  ) THEN
    RAISE EXCEPTION 'Account owner required' USING ERRCODE = '42501';
  END IF;
    v_week_start := date_trunc('week', NOW());

    RETURN QUERY
    SELECT
        COUNT(*) FILTER (WHERE ne.actual_outcome = 'delivered')::int AS delivered,
        COUNT(*) FILTER (WHERE ne.actual_outcome = 'opened')::int AS opened,
        COUNT(*) FILTER (WHERE ne.actual_outcome = 'completed')::int AS completed,
        COUNT(*) FILTER (WHERE ne.actual_outcome = 'dismissed')::int AS dismissed,
        CASE
            WHEN COUNT(*) FILTER (WHERE ne.actual_outcome = 'delivered') > 0 THEN
                (COUNT(*) FILTER (WHERE ne.actual_outcome IN ('opened', 'completed'))::decimal /
                 COUNT(*) FILTER (WHERE ne.actual_outcome = 'delivered')::decimal)
            ELSE 0.0
        END AS engagement_rate
    FROM notification_engagement ne
    WHERE ne.user_id = p_user_id
        AND ne.created_at >= v_week_start;
END;
$$;
REVOKE ALL ON FUNCTION public.get_notification_engagement_stats(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_notification_engagement_stats(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION "public"."get_notification_training_data"("p_user_id" "uuid") RETURNS TABLE("notification_type" "text", "predicted_engagement" numeric, "actual_outcome" "text", "context_snapshot" "jsonb", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET search_path TO pg_catalog, public, pg_temp
    AS $$
BEGIN

  IF p_user_id IS NULL OR (
    current_setting('role', true) IS DISTINCT FROM 'service_role'
    AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id)
  ) THEN
    RAISE EXCEPTION 'Account owner required' USING ERRCODE = '42501';
  END IF;
    RETURN QUERY
    SELECT
        ne.notification_type,
        ne.predicted_engagement,
        ne.actual_outcome,
        ne.context_snapshot,
        ne.created_at
    FROM notification_engagement ne
    WHERE ne.user_id = p_user_id
        AND ne.created_at >= NOW() - INTERVAL '30 days'
        AND ne.actual_outcome IN ('opened', 'completed', 'dismissed', 'ignored')
    ORDER BY ne.created_at DESC;
END;
$$;
REVOKE ALL ON FUNCTION public.get_notification_training_data(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_notification_training_data(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION "public"."get_notification_training_data"("p_user_id" "uuid", "p_days" integer DEFAULT 30) RETURNS TABLE("notification_type" "text", "hour_of_day" integer, "day_of_week" integer, "is_weekend" boolean, "predicted_engagement" numeric, "actual_outcome" "text", "context_signals" "jsonb")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET search_path TO pg_catalog, public, pg_temp
    AS $$
BEGIN

  IF p_user_id IS NULL OR (
    current_setting('role', true) IS DISTINCT FROM 'service_role'
    AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id)
  ) THEN
    RAISE EXCEPTION 'Account owner required' USING ERRCODE = '42501';
  END IF;
    RETURN QUERY
    SELECT
        nee.notification_type::text,
        EXTRACT(HOUR FROM nee.created_at)::int AS hour_of_day,
        EXTRACT(DOW FROM nee.created_at)::int AS day_of_week,
        EXTRACT(DOW FROM nee.created_at) IN (0, 6) AS is_weekend,
        nee.predicted_engagement,
        nee.actual_outcome::text,
        COALESCE(nee.context_snapshot, '{}'::jsonb) AS context_signals
    FROM notification_engagement_events nee
    WHERE nee.user_id = p_user_id
      AND nee.created_at >= NOW() - INTERVAL '1 day' * p_days
      AND nee.actual_outcome IN ('opened', 'completed', 'dismissed', 'ignored')
    ORDER BY nee.created_at DESC;
END;
$$;
REVOKE ALL ON FUNCTION public.get_notification_training_data(uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_notification_training_data(uuid,integer) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION "public"."get_weekly_engagement_stats"("p_user_id" "uuid") RETURNS TABLE("delivered" integer, "opened" integer, "completed" integer, "dismissed" integer, "engagement_rate" numeric, "period_start" timestamp with time zone, "period_end" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET search_path TO pg_catalog, public, pg_temp
    AS $$
DECLARE
    v_week_start TIMESTAMPTZ;
    v_week_end TIMESTAMPTZ;
BEGIN

  IF p_user_id IS NULL OR (
    current_setting('role', true) IS DISTINCT FROM 'service_role'
    AND (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_user_id)
  ) THEN
    RAISE EXCEPTION 'Account owner required' USING ERRCODE = '42501';
  END IF;
    v_week_start := date_trunc('week', NOW());
    v_week_end := v_week_start + INTERVAL '7 days';

    RETURN QUERY
    SELECT
        COUNT(*)::int AS delivered,
        COUNT(*) FILTER (WHERE actual_outcome = 'opened')::int AS opened,
        COUNT(*) FILTER (WHERE actual_outcome = 'completed')::int AS completed,
        COUNT(*) FILTER (WHERE actual_outcome = 'dismissed')::int AS dismissed,
        CASE
            WHEN COUNT(*) FILTER (WHERE actual_outcome IN ('opened', 'completed')) > 0
            THEN COUNT(*) FILTER (WHERE actual_outcome IN ('opened', 'completed'))::decimal / COUNT(*)::decimal
            ELSE 0
        END AS engagement_rate,
        v_week_start,
        v_week_end
    FROM notification_engagement_events
    WHERE user_id = p_user_id
      AND created_at >= v_week_start
      AND created_at < v_week_end
      AND actual_outcome IN ('delivered', 'opened', 'completed', 'dismissed');
END;
$$;
REVOKE ALL ON FUNCTION public.get_weekly_engagement_stats(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_weekly_engagement_stats(uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.find_mood_decline_users(integer,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.find_mood_decline_users(integer,integer) TO service_role;
ALTER FUNCTION public.find_mood_decline_users(integer,integer) SET search_path TO pg_catalog, public, pg_temp;

REVOKE ALL ON FUNCTION public.calculate_weekly_stats_extended(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_weekly_stats_extended(uuid) TO service_role;
ALTER FUNCTION public.calculate_weekly_stats_extended(uuid) SET search_path TO pg_catalog, public, pg_temp;

REVOKE ALL ON FUNCTION public.calculate_mood_trend(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.calculate_mood_trend(integer) TO authenticated, service_role;

COMMIT;
