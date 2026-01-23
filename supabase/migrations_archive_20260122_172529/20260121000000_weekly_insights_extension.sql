-- Weekly Insights Extension Migration
-- Extends weekly_summaries for AI-powered insights feature
-- See: specs/06-weekly-insights.md

-- =============================================================================
-- MARK: - Quest Templates (recreating if missing from initial schema)
-- =============================================================================

CREATE TABLE IF NOT EXISTS quest_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL CHECK (type IN ('breathing', 'walk', 'journal', 'focus', 'gratitude', 'stretch')),
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  estimated_minutes INT NOT NULL,
  difficulty TEXT NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard')),
  tags TEXT[] NOT NULL DEFAULT '{}',
  instructions JSONB NOT NULL DEFAULT '[]',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE quest_templates ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'quest_templates' AND policyname = 'Anyone can view quest templates'
  ) THEN
    CREATE POLICY "Anyone can view quest templates" ON quest_templates
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Quests (recreating if missing from initial schema)
-- =============================================================================

CREATE TABLE IF NOT EXISTS quests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  template_id UUID NOT NULL REFERENCES quest_templates(id),
  local_date TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'assigned' CHECK (status IN ('assigned', 'completed', 'skipped')),
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, local_date)
);

CREATE INDEX IF NOT EXISTS idx_quests_user_date ON quests(user_id, local_date);

ALTER TABLE quests ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'quests' AND policyname = 'Users can view own quests'
  ) THEN
    CREATE POLICY "Users can view own quests" ON quests
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'quests' AND policyname = 'Users can update own quests'
  ) THEN
    CREATE POLICY "Users can update own quests" ON quests
      FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'quests' AND policyname = 'Users can insert own quests'
  ) THEN
    CREATE POLICY "Users can insert own quests" ON quests
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Moods (recreating if missing from initial schema)
-- =============================================================================

CREATE TABLE IF NOT EXISTS moods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  local_date TEXT NOT NULL,
  mood_score INT NOT NULL CHECK (mood_score BETWEEN 1 AND 5),
  anxiety_score INT CHECK (anxiety_score BETWEEN 1 AND 5),
  energy_score INT CHECK (energy_score BETWEEN 1 AND 5),
  note TEXT,
  source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'post_quest', 'post_exercise')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_moods_user_date ON moods(user_id, local_date DESC);

ALTER TABLE moods ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'moods' AND policyname = 'Users can view own moods'
  ) THEN
    CREATE POLICY "Users can view own moods" ON moods
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'moods' AND policyname = 'Users can insert own moods'
  ) THEN
    CREATE POLICY "Users can insert own moods" ON moods
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'moods' AND policyname = 'Users can update own moods'
  ) THEN
    CREATE POLICY "Users can update own moods" ON moods
      FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Exercises (recreating if missing from initial schema)
-- =============================================================================

CREATE TABLE IF NOT EXISTS exercises (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL CHECK (type IN ('breathing', 'meditation', 'grounding', 'journaling', 'movement')),
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  duration_seconds INT NOT NULL,
  content_kind TEXT NOT NULL CHECK (content_kind IN ('text', 'audio', 'guided')),
  content_text TEXT,
  audio_url TEXT,
  premium_only BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE exercises ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'exercises' AND policyname = 'Anyone can view exercises'
  ) THEN
    CREATE POLICY "Anyone can view exercises" ON exercises
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Exercise Sessions (recreating if missing from initial schema)
-- =============================================================================

CREATE TABLE IF NOT EXISTS exercise_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  exercise_id UUID NOT NULL REFERENCES exercises(id),
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at TIMESTAMPTZ,
  completed BOOLEAN NOT NULL DEFAULT false,
  rating INT CHECK (rating BETWEEN 1 AND 5),
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Ensure created_at column exists (may be missing from older schema)
ALTER TABLE exercise_sessions ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_exercise_sessions_user ON exercise_sessions(user_id, created_at DESC);

ALTER TABLE exercise_sessions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'exercise_sessions' AND policyname = 'Users can view own sessions'
  ) THEN
    CREATE POLICY "Users can view own sessions" ON exercise_sessions
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'exercise_sessions' AND policyname = 'Users can insert own sessions'
  ) THEN
    CREATE POLICY "Users can insert own sessions" ON exercise_sessions
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'exercise_sessions' AND policyname = 'Users can update own sessions'
  ) THEN
    CREATE POLICY "Users can update own sessions" ON exercise_sessions
      FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Extend Weekly Summaries Table
-- =============================================================================

-- Add mood detail columns
ALTER TABLE weekly_summaries ADD COLUMN IF NOT EXISTS mood_min INT;
ALTER TABLE weekly_summaries ADD COLUMN IF NOT EXISTS mood_max INT;
ALTER TABLE weekly_summaries ADD COLUMN IF NOT EXISTS mood_by_day JSONB DEFAULT '{}'::jsonb;

-- Add extended activity metrics
ALTER TABLE weekly_summaries ADD COLUMN IF NOT EXISTS circle_checkin_count INT DEFAULT 0;
ALTER TABLE weekly_summaries ADD COLUMN IF NOT EXISTS exercise_minutes INT DEFAULT 0;

-- Add AI insights columns
ALTER TABLE weekly_summaries ADD COLUMN IF NOT EXISTS patterns_detected JSONB DEFAULT '[]'::jsonb;
ALTER TABLE weekly_summaries ADD COLUMN IF NOT EXISTS ai_insight TEXT;
ALTER TABLE weekly_summaries ADD COLUMN IF NOT EXISTS ai_recommendations JSONB DEFAULT '[]'::jsonb;

-- Update mood_trend CHECK constraint to include 'insufficient_data'
-- First drop the existing constraint, then add the new one
ALTER TABLE weekly_summaries DROP CONSTRAINT IF EXISTS weekly_summaries_mood_trend_check;
ALTER TABLE weekly_summaries ADD CONSTRAINT weekly_summaries_mood_trend_check
  CHECK (mood_trend IN ('improving', 'stable', 'declining', 'insufficient_data'));

COMMENT ON COLUMN weekly_summaries.mood_min IS 'Minimum mood score for the week (1-5)';
COMMENT ON COLUMN weekly_summaries.mood_max IS 'Maximum mood score for the week (1-5)';
COMMENT ON COLUMN weekly_summaries.mood_by_day IS 'Average mood by day of week: {"mon": 3.5, "tue": 4.0, ...}';
COMMENT ON COLUMN weekly_summaries.circle_checkin_count IS 'Number of circle check-ins posted this week';
COMMENT ON COLUMN weekly_summaries.exercise_minutes IS 'Total exercise minutes this week';
COMMENT ON COLUMN weekly_summaries.patterns_detected IS 'Detected patterns: [{"type": "time", "description": "...", "confidence": 0.8}]';
COMMENT ON COLUMN weekly_summaries.ai_insight IS 'AI-generated personalized insight (2-3 sentences)';
COMMENT ON COLUMN weekly_summaries.ai_recommendations IS 'AI recommendations: [{"title": "...", "reason": "..."}]';

-- =============================================================================
-- MARK: - Enhanced Calculate Weekly Stats Function
-- Returns extended metrics for insights
-- =============================================================================

CREATE OR REPLACE FUNCTION public.calculate_weekly_stats_extended(p_user_id UUID)
RETURNS TABLE(
  checkin_count INT,
  quest_count INT,
  exercise_count INT,
  avg_mood FLOAT,
  mood_trend TEXT,
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
  v_this_week_avg FLOAT;
  v_prev_week_avg FLOAT;
  v_trend TEXT;
  v_mood_min INT;
  v_mood_max INT;
  v_mood_by_day JSONB;
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

  -- Calculate mood metrics
  SELECT
    AVG(mood_score),
    MIN(mood_score)::int,
    MAX(mood_score)::int
  INTO v_this_week_avg, v_mood_min, v_mood_max
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

  -- Calculate previous week's average mood for trend
  SELECT AVG(mood_score) INTO v_prev_week_avg
  FROM moods
  WHERE user_id = p_user_id
    AND created_at >= v_prev_week_start
    AND created_at < v_week_start;

  -- Determine trend (require at least 3 moods for meaningful trend)
  IF v_checkin_count < 3 THEN
    v_trend := 'insufficient_data';
  ELSIF v_this_week_avg IS NULL OR v_prev_week_avg IS NULL THEN
    v_trend := 'stable';
  ELSIF v_this_week_avg > v_prev_week_avg + 0.5 THEN
    v_trend := 'improving';
  ELSIF v_this_week_avg < v_prev_week_avg - 0.5 THEN
    v_trend := 'declining';
  ELSE
    v_trend := 'stable';
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
    v_this_week_avg,
    v_trend,
    v_mood_min,
    v_mood_max,
    COALESCE(v_mood_by_day, '{}'::jsonb),
    v_circle_count,
    v_exercise_mins;
END;
$$;

COMMENT ON FUNCTION public.calculate_weekly_stats_extended IS 'Calculate extended weekly stats for insights (mood details, patterns, activity breakdown)';

-- =============================================================================
-- MARK: - Get Historical Moods for Pattern Detection
-- Returns mood data with context for pattern analysis
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_moods_for_pattern_analysis(
  p_user_id UUID,
  p_weeks INT DEFAULT 4
)
RETURNS TABLE(
  mood_score INT,
  created_at TIMESTAMPTZ,
  day_of_week INT,
  hour_of_day INT,
  source TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    m.mood_score,
    m.created_at,
    EXTRACT(DOW FROM m.created_at)::int as day_of_week,
    EXTRACT(HOUR FROM m.created_at)::int as hour_of_day,
    m.source
  FROM moods m
  WHERE m.user_id = p_user_id
    AND m.created_at >= NOW() - (p_weeks || ' weeks')::interval
  ORDER BY m.created_at DESC;
END;
$$;

COMMENT ON FUNCTION public.get_moods_for_pattern_analysis IS 'Get mood history with temporal metadata for pattern detection';

-- =============================================================================
-- MARK: - Get Exercise Activity Correlation Data
-- Returns exercise sessions with mood data for correlation analysis
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_exercise_mood_correlation(
  p_user_id UUID,
  p_weeks INT DEFAULT 4
)
RETURNS TABLE(
  exercise_type TEXT,
  exercise_date DATE,
  mood_before FLOAT,
  mood_after FLOAT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    e.type as exercise_type,
    es.created_at::date as exercise_date,
    (
      SELECT AVG(m.mood_score)::float
      FROM moods m
      WHERE m.user_id = p_user_id
        AND m.created_at >= es.created_at - INTERVAL '4 hours'
        AND m.created_at < es.created_at
    ) as mood_before,
    (
      SELECT AVG(m.mood_score)::float
      FROM moods m
      WHERE m.user_id = p_user_id
        AND m.created_at > es.ended_at
        AND m.created_at <= es.ended_at + INTERVAL '4 hours'
    ) as mood_after
  FROM exercise_sessions es
  JOIN exercises e ON e.id = es.exercise_id
  WHERE es.user_id = p_user_id
    AND es.completed = true
    AND es.created_at >= NOW() - (p_weeks || ' weeks')::interval
  ORDER BY es.created_at DESC;
END;
$$;

COMMENT ON FUNCTION public.get_exercise_mood_correlation IS 'Get exercise sessions with before/after mood for correlation analysis';
