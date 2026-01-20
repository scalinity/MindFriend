-- Migration: Quest Arcs System
-- Description: Multi-week quest sequencing with themed journeys, milestones, and adaptive difficulty
-- Spec: docs/specs/quest-arcs-formal-spec.md

-- =============================================================================
-- MARK: - Quest Arcs Table (Arc Definitions)
-- =============================================================================

CREATE TABLE IF NOT EXISTS quest_arcs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('stress', 'sleep', 'confidence', 'focus', 'resilience')),
  duration_days INT NOT NULL CHECK (duration_days BETWEEN 7 AND 90),
  difficulty_level TEXT NOT NULL CHECK (difficulty_level IN ('easy', 'medium', 'hard')),
  is_premium BOOLEAN NOT NULL DEFAULT false,
  milestone_days INT[] NOT NULL DEFAULT '{}',
  icon_name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  is_active BOOLEAN NOT NULL DEFAULT true
);

CREATE INDEX IF NOT EXISTS idx_quest_arcs_category ON quest_arcs(category) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_quest_arcs_premium ON quest_arcs(is_premium) WHERE is_active = true;

-- =============================================================================
-- MARK: - Quest Arc Steps Table (Daily Quest Sequence)
-- =============================================================================

CREATE TABLE IF NOT EXISTS quest_arc_steps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  arc_id UUID NOT NULL REFERENCES quest_arcs(id) ON DELETE CASCADE,
  day_number INT NOT NULL CHECK (day_number >= 1),
  quest_template_id UUID NOT NULL REFERENCES quest_templates(id) ON DELETE RESTRICT,
  custom_title TEXT CHECK (LENGTH(custom_title) <= 500),
  custom_description TEXT CHECK (LENGTH(custom_description) <= 500),
  is_milestone BOOLEAN NOT NULL DEFAULT false,
  milestone_xp_bonus INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE(arc_id, day_number)
);

CREATE INDEX IF NOT EXISTS idx_quest_arc_steps_lookup ON quest_arc_steps(arc_id, day_number);
CREATE INDEX IF NOT EXISTS idx_quest_arc_steps_milestones ON quest_arc_steps(arc_id) WHERE is_milestone = true;
-- Optimize step counting queries (prevents N+1 in get-quest-arcs)
CREATE INDEX IF NOT EXISTS idx_quest_arc_steps_arc_id ON quest_arc_steps(arc_id);

-- =============================================================================
-- MARK: - User Quest Arcs Table (User Enrollments)
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_quest_arcs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  arc_id UUID NOT NULL REFERENCES quest_arcs(id) ON DELETE CASCADE,
  current_day INT NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'completed', 'abandoned')),
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  paused_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  abandoned_at TIMESTAMPTZ,
  last_quest_completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Immutable snapshots for stability (prevents retroactive changes affecting active arcs)
  snapshot_duration_days INT NOT NULL,
  snapshot_milestone_days INT[] NOT NULL
);

-- Enforce one active arc per user (partial unique index)
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_quest_arcs_one_active
  ON user_quest_arcs(user_id)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_user_quest_arcs_lookup ON user_quest_arcs(user_id, status);
-- Covering index for active arc queries with arc join (optimizes getActiveArc)
CREATE INDEX IF NOT EXISTS idx_user_quest_arcs_active_with_arc
  ON user_quest_arcs(user_id, arc_id)
  WHERE status = 'active';

-- =============================================================================
-- MARK: - Modify Quests Table (Add Arc Tracking)
-- =============================================================================

ALTER TABLE quests ADD COLUMN IF NOT EXISTS arc_user_id UUID REFERENCES user_quest_arcs(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_quests_arc_user ON quests(arc_user_id) WHERE arc_user_id IS NOT NULL;

-- =============================================================================
-- MARK: - Row Level Security Policies
-- =============================================================================

ALTER TABLE quest_arcs ENABLE ROW LEVEL SECURITY;
ALTER TABLE quest_arc_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_quest_arcs ENABLE ROW LEVEL SECURITY;

-- All authenticated users can view active arcs
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Users can view active arcs' AND tablename = 'quest_arcs'
  ) THEN
    CREATE POLICY "Users can view active arcs" ON quest_arcs
      FOR SELECT TO authenticated
      USING (is_active = true);
  END IF;
END $$;

-- All authenticated users can view arc steps
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Users can view arc steps' AND tablename = 'quest_arc_steps'
  ) THEN
    CREATE POLICY "Users can view arc steps" ON quest_arc_steps
      FOR SELECT TO authenticated
      USING (true);
  END IF;
END $$;

-- Users can only view their own arc enrollments
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Users can view own arc enrollments' AND tablename = 'user_quest_arcs'
  ) THEN
    CREATE POLICY "Users can view own arc enrollments" ON user_quest_arcs
      FOR SELECT TO authenticated
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- Users can insert their own enrollments
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Users can start arcs' AND tablename = 'user_quest_arcs'
  ) THEN
    CREATE POLICY "Users can start arcs" ON user_quest_arcs
      FOR INSERT TO authenticated
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- Users can update their own enrollments
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Users can update own arc enrollments' AND tablename = 'user_quest_arcs'
  ) THEN
    CREATE POLICY "Users can update own arc enrollments" ON user_quest_arcs
      FOR UPDATE TO authenticated
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Database Functions (RPCs)
-- =============================================================================

-- Function: Increment arc day after quest completion
CREATE OR REPLACE FUNCTION increment_arc_day(p_user_arc_id UUID)
RETURNS void AS $$
DECLARE
  v_arc_duration INT;
  v_current_day INT;
BEGIN
  -- Get current state using snapshot
  SELECT ua.current_day, ua.snapshot_duration_days
  INTO v_current_day, v_arc_duration
  FROM user_quest_arcs ua
  WHERE ua.id = p_user_arc_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'User arc enrollment not found';
  END IF;

  -- Increment day
  UPDATE user_quest_arcs
  SET current_day = current_day + 1,
      last_quest_completed_at = NOW(),
      -- Mark completed if final day (use = for exact match to prevent off-by-one)
      status = CASE
        WHEN v_current_day + 1 = v_arc_duration THEN 'completed'
        ELSE status
      END,
      completed_at = CASE
        WHEN v_current_day + 1 = v_arc_duration THEN NOW()
        ELSE completed_at
      END
  WHERE id = p_user_arc_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Get arc step for user (next quest in sequence)
CREATE OR REPLACE FUNCTION get_arc_step_for_user(p_user_id UUID)
RETURNS TABLE (
  quest_template_id UUID,
  custom_title TEXT,
  custom_description TEXT,
  is_milestone BOOLEAN,
  milestone_xp_bonus INT,
  day_number INT,
  user_arc_id UUID
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    qas.quest_template_id,
    qas.custom_title,
    qas.custom_description,
    qas.is_milestone,
    qas.milestone_xp_bonus,
    qas.day_number,
    uqa.id as user_arc_id
  FROM user_quest_arcs uqa
  JOIN quest_arc_steps qas ON qas.arc_id = uqa.arc_id
    AND qas.day_number = uqa.current_day + 1
  WHERE uqa.user_id = p_user_id
    AND uqa.status = 'active'
  LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Get step counts for multiple arcs (prevents N+1 query)
CREATE OR REPLACE FUNCTION get_arc_step_counts(arc_ids UUID[])
RETURNS TABLE (arc_id UUID, step_count BIGINT) AS $$
BEGIN
  RETURN QUERY
  SELECT qas.arc_id, COUNT(*)::BIGINT
  FROM quest_arc_steps qas
  WHERE qas.arc_id = ANY(arc_ids)
  GROUP BY qas.arc_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION increment_arc_day(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_arc_step_for_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_arc_step_counts(UUID[]) TO authenticated;

-- =============================================================================
-- MARK: - Seed Data (Initial Arcs)
-- =============================================================================

DO $$
DECLARE
  v_arc_sleep_better UUID;
  v_arc_stress_reset UUID;
  v_arc_confidence UUID;
  v_arc_focus UUID;
  v_arc_resilience UUID;
  v_template_breathing UUID;
  v_template_journal UUID;
  v_template_meditation UUID;
  v_template_walk UUID;
BEGIN
  -- Get some quest template IDs (fallback to any if specific ones don't exist)
  -- Categories in quest_templates: mindfulness, gratitude, social, reflection, physical, creative
  SELECT id INTO v_template_breathing FROM quest_templates WHERE category = 'mindfulness' AND is_active = true LIMIT 1;
  SELECT id INTO v_template_journal FROM quest_templates WHERE category = 'reflection' AND is_active = true LIMIT 1;
  SELECT id INTO v_template_meditation FROM quest_templates WHERE category = 'mindfulness' AND is_active = true OFFSET 1 LIMIT 1;
  SELECT id INTO v_template_walk FROM quest_templates WHERE category = 'physical' AND is_active = true LIMIT 1;

  -- If no templates found, skip seeding
  IF v_template_breathing IS NULL OR v_template_journal IS NULL THEN
    RAISE NOTICE 'Quest templates not found, skipping arc seed data';
    RETURN;
  END IF;

  -- Arc 1: Sleep Better (14 days, free)
  INSERT INTO quest_arcs (title, description, category, duration_days, difficulty_level, is_premium, milestone_days, icon_name)
  VALUES (
    'Sleep Better',
    'Establish healthy sleep patterns through breathing, meditation, and evening routines',
    'sleep',
    14,
    'easy',
    false,
    ARRAY[3, 7, 14],
    'moon.zzz.fill'
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_arc_sleep_better;

  -- Arc 2: Stress Reset (7 days, free)
  INSERT INTO quest_arcs (title, description, category, duration_days, difficulty_level, is_premium, milestone_days, icon_name)
  VALUES (
    'Stress Reset',
    'Quick wins to reduce stress and build resilience in just one week',
    'stress',
    7,
    'easy',
    false,
    ARRAY[3, 7],
    'brain.head.profile'
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_arc_stress_reset;

  -- Arc 3: Confidence Builder (21 days, premium)
  INSERT INTO quest_arcs (title, description, category, duration_days, difficulty_level, is_premium, milestone_days, icon_name)
  VALUES (
    'Confidence Builder',
    'Build lasting self-confidence through daily practice and reflection',
    'confidence',
    21,
    'medium',
    true,
    ARRAY[7, 14, 21],
    'star.fill'
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_arc_confidence;

  -- Arc 4: Focus Mastery (14 days, premium)
  INSERT INTO quest_arcs (title, description, category, duration_days, difficulty_level, is_premium, milestone_days, icon_name)
  VALUES (
    'Focus Mastery',
    'Train your attention and eliminate distractions for deep work',
    'focus',
    14,
    'medium',
    true,
    ARRAY[5, 10, 14],
    'scope'
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_arc_focus;

  -- Arc 5: Build Resilience (28 days, premium)
  INSERT INTO quest_arcs (title, description, category, duration_days, difficulty_level, is_premium, milestone_days, icon_name)
  VALUES (
    'Build Resilience',
    'Develop mental toughness and bounce back stronger from challenges',
    'resilience',
    28,
    'hard',
    true,
    ARRAY[7, 14, 21, 28],
    'shield.fill'
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_arc_resilience;

  -- Only seed steps if we got valid arc IDs
  IF v_arc_sleep_better IS NOT NULL THEN
    -- Seed steps for Sleep Better arc (14 days)
    -- Day 1-3: Foundation
    INSERT INTO quest_arc_steps (arc_id, day_number, quest_template_id, custom_title, is_milestone)
    VALUES
      (v_arc_sleep_better, 1, v_template_breathing, 'Evening Wind-Down Breathing', false),
      (v_arc_sleep_better, 2, v_template_journal, 'Sleep Journal: Identify Patterns', false),
      (v_arc_sleep_better, 3, v_template_breathing, 'Milestone: 3 Days of Better Sleep', true)
    ON CONFLICT DO NOTHING;

    -- Day 4-7: Building habits
    INSERT INTO quest_arc_steps (arc_id, day_number, quest_template_id, custom_title, is_milestone, milestone_xp_bonus)
    VALUES
      (v_arc_sleep_better, 4, COALESCE(v_template_meditation, v_template_breathing), 'Pre-Sleep Meditation', false, 0),
      (v_arc_sleep_better, 5, v_template_breathing, 'Progressive Muscle Relaxation', false, 0),
      (v_arc_sleep_better, 6, v_template_journal, 'Sleep Gratitude Practice', false, 0),
      (v_arc_sleep_better, 7, v_template_breathing, 'Week 1 Complete!', true, 50)
    ON CONFLICT DO NOTHING;

    -- Day 8-14: Refinement
    INSERT INTO quest_arc_steps (arc_id, day_number, quest_template_id, custom_title, is_milestone, milestone_xp_bonus)
    VALUES
      (v_arc_sleep_better, 8, COALESCE(v_template_meditation, v_template_breathing), 'Body Scan for Sleep', false, 0),
      (v_arc_sleep_better, 9, v_template_breathing, '4-7-8 Breathing Technique', false, 0),
      (v_arc_sleep_better, 10, v_template_journal, 'Sleep Progress Check-In', false, 0),
      (v_arc_sleep_better, 11, COALESCE(v_template_meditation, v_template_breathing), 'Guided Sleep Visualization', false, 0),
      (v_arc_sleep_better, 12, v_template_breathing, 'Evening Routine Refinement', false, 0),
      (v_arc_sleep_better, 13, v_template_journal, 'Celebrate Sleep Wins', false, 0),
      (v_arc_sleep_better, 14, v_template_breathing, 'Sleep Better Arc Complete!', true, 100)
    ON CONFLICT DO NOTHING;
  END IF;

  IF v_arc_stress_reset IS NOT NULL THEN
    -- Seed steps for Stress Reset arc (7 days)
    INSERT INTO quest_arc_steps (arc_id, day_number, quest_template_id, custom_title, is_milestone, milestone_xp_bonus)
    VALUES
      (v_arc_stress_reset, 1, v_template_breathing, 'Calm Your Nervous System', false, 0),
      (v_arc_stress_reset, 2, COALESCE(v_template_walk, v_template_breathing), 'Movement for Stress Release', false, 0),
      (v_arc_stress_reset, 3, v_template_journal, 'Stress Triggers Awareness', true, 30),
      (v_arc_stress_reset, 4, v_template_breathing, 'Box Breathing for Calm', false, 0),
      (v_arc_stress_reset, 5, COALESCE(v_template_meditation, v_template_breathing), 'Mindful Stress Reset', false, 0),
      (v_arc_stress_reset, 6, v_template_journal, 'Build Your Stress Toolkit', false, 0),
      (v_arc_stress_reset, 7, v_template_breathing, 'Stress Reset Complete!', true, 75)
    ON CONFLICT DO NOTHING;
  END IF;

  RAISE NOTICE 'Quest arcs seeded successfully';
END $$;

-- =============================================================================
-- MARK: - End of Migration
-- =============================================================================
