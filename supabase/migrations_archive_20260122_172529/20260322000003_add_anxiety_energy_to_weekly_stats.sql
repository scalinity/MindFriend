-- Migration: Add anxiety and energy tracking to weekly stats
-- Extends calculate_weekly_stats_extended to include anxiety_score and energy_score from moods

-- =============================================================================
-- MARK: - Update calculate_weekly_stats_extended Function
-- Now includes avg_anxiety, avg_energy, and their trends
-- =============================================================================

-- Drop the old function since we're changing return type
DROP FUNCTION IF EXISTS public.calculate_weekly_stats_extended(UUID);

CREATE OR REPLACE FUNCTION public.calculate_weekly_stats_extended(p_user_id UUID)
RETURNS TABLE(
  checkin_count INT,
  quest_count INT,
  exercise_count INT,
  avg_mood FLOAT,
  avg_anxiety FLOAT,
  avg_energy FLOAT,
  mood_trend TEXT,
  anxiety_trend TEXT,
  energy_trend TEXT,
  mood_min INT,
  mood_max INT,
  mood_by_day JSONB,
  circle_checkin_count INT,
  exercise_minutes INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_week_start TIMESTAMPTZ;
  v_prev_week_start TIMESTAMPTZ;
  -- This week's averages
  v_this_week_mood_avg FLOAT;
  v_this_week_anxiety_avg FLOAT;
  v_this_week_energy_avg FLOAT;
  -- Previous week's averages
  v_prev_week_mood_avg FLOAT;
  v_prev_week_anxiety_avg FLOAT;
  v_prev_week_energy_avg FLOAT;
  -- Trends
  v_mood_trend TEXT;
  v_anxiety_trend TEXT;
  v_energy_trend TEXT;
  -- Mood details
  v_mood_min INT;
  v_mood_max INT;
  v_mood_by_day JSONB;
  -- Counts
  v_checkin_count INT;
  v_quest_count INT;
  v_exercise_count INT;
  v_circle_count INT;
  v_exercise_mins INT;
BEGIN
  -- Get start of current week (Monday)
  v_week_start := date_trunc('week', NOW());
  v_prev_week_start := v_week_start - INTERVAL '7 days';

  -- Count mood checkins this week
  SELECT COUNT(*)::int INTO v_checkin_count
  FROM moods
  WHERE user_id = p_user_id
    AND created_at >= v_week_start;

  -- Calculate this week's mood, anxiety, and energy metrics
  SELECT
    AVG(mood_score),
    AVG(anxiety_score),
    AVG(energy_score),
    MIN(mood_score)::int,
    MAX(mood_score)::int
  INTO v_this_week_mood_avg, v_this_week_anxiety_avg, v_this_week_energy_avg, v_mood_min, v_mood_max
  FROM moods
  WHERE user_id = p_user_id
    AND created_at >= v_week_start;

  -- Calculate mood by day of week
  SELECT jsonb_object_agg(
    LOWER(day_name),
    ROUND(day_avg::numeric, 1)
  ) INTO v_mood_by_day
  FROM (
    SELECT
      TO_CHAR(created_at, 'Dy') as day_name,
      AVG(mood_score) as day_avg
    FROM moods
    WHERE user_id = p_user_id
      AND created_at >= v_week_start
    GROUP BY TO_CHAR(created_at, 'Dy'), EXTRACT(DOW FROM created_at)
    ORDER BY EXTRACT(DOW FROM created_at)
  ) daily_moods;

  -- Calculate previous week's averages for trends
  SELECT
    AVG(mood_score),
    AVG(anxiety_score),
    AVG(energy_score)
  INTO v_prev_week_mood_avg, v_prev_week_anxiety_avg, v_prev_week_energy_avg
  FROM moods
  WHERE user_id = p_user_id
    AND created_at >= v_prev_week_start
    AND created_at < v_week_start;

  -- Determine mood trend (require at least 3 moods for meaningful trend)
  IF v_checkin_count < 3 THEN
    v_mood_trend := 'insufficient_data';
  ELSIF v_this_week_mood_avg IS NULL OR v_prev_week_mood_avg IS NULL THEN
    v_mood_trend := 'stable';
  ELSIF v_this_week_mood_avg > v_prev_week_mood_avg + 0.5 THEN
    v_mood_trend := 'improving';
  ELSIF v_this_week_mood_avg < v_prev_week_mood_avg - 0.5 THEN
    v_mood_trend := 'declining';
  ELSE
    v_mood_trend := 'stable';
  END IF;

  -- Determine anxiety trend (lower anxiety is "improving")
  IF v_checkin_count < 3 THEN
    v_anxiety_trend := 'insufficient_data';
  ELSIF v_this_week_anxiety_avg IS NULL OR v_prev_week_anxiety_avg IS NULL THEN
    v_anxiety_trend := 'stable';
  ELSIF v_this_week_anxiety_avg < v_prev_week_anxiety_avg - 0.5 THEN
    v_anxiety_trend := 'improving';  -- Lower anxiety is better
  ELSIF v_this_week_anxiety_avg > v_prev_week_anxiety_avg + 0.5 THEN
    v_anxiety_trend := 'declining';  -- Higher anxiety is worse
  ELSE
    v_anxiety_trend := 'stable';
  END IF;

  -- Determine energy trend (higher energy is "improving")
  IF v_checkin_count < 3 THEN
    v_energy_trend := 'insufficient_data';
  ELSIF v_this_week_energy_avg IS NULL OR v_prev_week_energy_avg IS NULL THEN
    v_energy_trend := 'stable';
  ELSIF v_this_week_energy_avg > v_prev_week_energy_avg + 0.5 THEN
    v_energy_trend := 'improving';
  ELSIF v_this_week_energy_avg < v_prev_week_energy_avg - 0.5 THEN
    v_energy_trend := 'declining';
  ELSE
    v_energy_trend := 'stable';
  END IF;

  -- Count completed quests
  SELECT COUNT(*)::int INTO v_quest_count
  FROM quests
  WHERE user_id = p_user_id
    AND status = 'completed'
    AND completed_at >= v_week_start;

  -- Count exercises and total minutes
  SELECT
    COUNT(*)::int,
    COALESCE(SUM(EXTRACT(EPOCH FROM (ended_at - started_at)) / 60)::int, 0)
  INTO v_exercise_count, v_exercise_mins
  FROM exercise_sessions
  WHERE user_id = p_user_id
    AND created_at >= v_week_start
    AND completed = true;

  -- Count circle check-ins
  SELECT COUNT(*)::int INTO v_circle_count
  FROM circle_posts
  WHERE user_id = p_user_id
    AND kind = 'checkin'
    AND created_at >= v_week_start;

  RETURN QUERY SELECT
    v_checkin_count,
    v_quest_count,
    v_exercise_count,
    v_this_week_mood_avg,
    v_this_week_anxiety_avg,
    v_this_week_energy_avg,
    v_mood_trend,
    v_anxiety_trend,
    v_energy_trend,
    v_mood_min,
    v_mood_max,
    COALESCE(v_mood_by_day, '{}'::jsonb),
    v_circle_count,
    v_exercise_mins;
END;
$$;

COMMENT ON FUNCTION public.calculate_weekly_stats_extended IS 'Calculate extended weekly stats including mood, anxiety, energy averages and trends';
