-- Migration: 20260220000000_structured_programs.sql
-- Description: Add structured programs & wellness journeys feature
-- Spec: docs/specs/02-structured-programs.md

-- =============================================================================
-- MARK: - Program Definitions Table
-- =============================================================================

CREATE TABLE IF NOT EXISTS programs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug TEXT UNIQUE NOT NULL,  -- e.g., "21-day-anxiety-reset"
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  duration_days INT NOT NULL CHECK (duration_days BETWEEN 1 AND 90),
  category TEXT NOT NULL CHECK (category IN ('anxiety', 'sleep', 'focus', 'stress', 'mindfulness', 'gratitude', 'intro', 'custom')),
  difficulty TEXT NOT NULL DEFAULT 'beginner' CHECK (difficulty IN ('beginner', 'intermediate', 'advanced')),
  premium_only BOOLEAN NOT NULL DEFAULT FALSE,
  learning_objectives JSONB NOT NULL DEFAULT '[]',
  tags TEXT[] NOT NULL DEFAULT '{}',
  cover_image_url TEXT,
  estimated_daily_minutes INT NOT NULL DEFAULT 15,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- MARK: - Program Days Table
-- =============================================================================

CREATE TABLE IF NOT EXISTS program_days (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  program_id UUID NOT NULL REFERENCES programs(id) ON DELETE CASCADE,
  day_number INT NOT NULL CHECK (day_number > 0),
  title TEXT NOT NULL,
  theme TEXT,
  content JSONB NOT NULL,  -- Array of content blocks
  completion_criteria JSONB NOT NULL DEFAULT '{"required": [], "optional": []}',
  is_rest_day BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(program_id, day_number)
);

-- =============================================================================
-- MARK: - Program Enrollments Table
-- =============================================================================

CREATE TABLE IF NOT EXISTS program_enrollments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  program_id UUID NOT NULL REFERENCES programs(id),
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'paused', 'completed', 'abandoned')),
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  current_day INT NOT NULL DEFAULT 1,
  paused_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  abandoned_at TIMESTAMPTZ,
  preferred_time_local TIME NOT NULL DEFAULT '09:00:00',
  skips_used INT NOT NULL DEFAULT 0,
  skips_allowed INT NOT NULL DEFAULT 2,
  streak_days INT NOT NULL DEFAULT 0,
  longest_streak INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- MARK: - Program Day Progress Table
-- =============================================================================

CREATE TABLE IF NOT EXISTS program_day_progress (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  enrollment_id UUID NOT NULL REFERENCES program_enrollments(id) ON DELETE CASCADE,
  day_number INT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'in_progress', 'completed', 'skipped')),
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  content_completed JSONB NOT NULL DEFAULT '{}',  -- {"learn": true, "practice": true, ...}
  reflection_response TEXT,
  apply_report TEXT,
  exercise_session_id UUID REFERENCES exercise_sessions(id),
  mood_before INT CHECK (mood_before BETWEEN 1 AND 5),
  mood_after INT CHECK (mood_after BETWEEN 1 AND 5),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(enrollment_id, day_number)
);

-- =============================================================================
-- MARK: - Program Certificates Table
-- =============================================================================

CREATE TABLE IF NOT EXISTS program_certificates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  program_id UUID NOT NULL REFERENCES programs(id),
  enrollment_id UUID NOT NULL REFERENCES program_enrollments(id),
  certificate_number TEXT UNIQUE NOT NULL,  -- e.g., "MF-2026-001234"
  completion_stats JSONB NOT NULL,  -- {days_completed, streak_best, skips_used, ...}
  issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  shared_to_circle BOOLEAN NOT NULL DEFAULT FALSE,
  shared_externally BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE(enrollment_id)
);

-- =============================================================================
-- MARK: - Indexes
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_programs_category ON programs(category) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_programs_premium ON programs(premium_only) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_programs_sort ON programs(sort_order, created_at);
CREATE INDEX IF NOT EXISTS idx_program_days_program ON program_days(program_id, day_number);
CREATE INDEX IF NOT EXISTS idx_enrollments_user_status ON program_enrollments(user_id, status);
CREATE INDEX IF NOT EXISTS idx_enrollments_active ON program_enrollments(user_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_enrollments_program ON program_enrollments(program_id, status);
CREATE INDEX IF NOT EXISTS idx_day_progress_enrollment ON program_day_progress(enrollment_id, day_number);
CREATE INDEX IF NOT EXISTS idx_certificates_user ON program_certificates(user_id, issued_at DESC);

-- =============================================================================
-- MARK: - Row Level Security
-- =============================================================================

ALTER TABLE programs ENABLE ROW LEVEL SECURITY;
ALTER TABLE program_days ENABLE ROW LEVEL SECURITY;
ALTER TABLE program_enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE program_day_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE program_certificates ENABLE ROW LEVEL SECURITY;

-- Programs readable by all authenticated users
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'programs' AND policyname = 'Programs are readable by authenticated users') THEN
    CREATE POLICY "Programs are readable by authenticated users" ON programs
      FOR SELECT TO authenticated USING (is_active = TRUE);
  END IF;
END $$;

-- Program days are readable by all authenticated users
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'program_days' AND policyname = 'Program days are readable by authenticated users') THEN
    CREATE POLICY "Program days are readable by authenticated users" ON program_days
      FOR SELECT TO authenticated USING (TRUE);
  END IF;
END $$;

-- Enrollments are user-scoped
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'program_enrollments' AND policyname = 'Users can view own enrollments') THEN
    CREATE POLICY "Users can view own enrollments" ON program_enrollments
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'program_enrollments' AND policyname = 'Users can insert own enrollments') THEN
    CREATE POLICY "Users can insert own enrollments" ON program_enrollments
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'program_enrollments' AND policyname = 'Users can update own enrollments') THEN
    CREATE POLICY "Users can update own enrollments" ON program_enrollments
      FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END $$;

-- Day progress is user-scoped via enrollment join
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'program_day_progress' AND policyname = 'Users can view own day progress') THEN
    CREATE POLICY "Users can view own day progress" ON program_day_progress
      FOR SELECT USING (
        enrollment_id IN (SELECT id FROM program_enrollments WHERE user_id = auth.uid())
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'program_day_progress' AND policyname = 'Users can insert own day progress') THEN
    CREATE POLICY "Users can insert own day progress" ON program_day_progress
      FOR INSERT WITH CHECK (
        enrollment_id IN (SELECT id FROM program_enrollments WHERE user_id = auth.uid())
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'program_day_progress' AND policyname = 'Users can update own day progress') THEN
    CREATE POLICY "Users can update own day progress" ON program_day_progress
      FOR UPDATE USING (
        enrollment_id IN (SELECT id FROM program_enrollments WHERE user_id = auth.uid())
      );
  END IF;
END $$;

-- Certificates are user-scoped
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'program_certificates' AND policyname = 'Users can view own certificates') THEN
    CREATE POLICY "Users can view own certificates" ON program_certificates
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Certificate Sequence
-- =============================================================================

CREATE SEQUENCE IF NOT EXISTS certificate_seq START 1;

-- =============================================================================
-- MARK: - Update celebration_events to support program_complete type
-- =============================================================================

-- Need to update the CHECK constraint to include 'program_complete'
-- First drop old constraint (idempotent)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'celebration_events_celebration_type_check'
  ) THEN
    ALTER TABLE celebration_events
      DROP CONSTRAINT celebration_events_celebration_type_check;
  END IF;
END $$;

-- Add new constraint with program_complete
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'celebration_events_celebration_type_check'
  ) THEN
    ALTER TABLE celebration_events
      ADD CONSTRAINT celebration_events_celebration_type_check
      CHECK (celebration_type IN (
        'streak_milestone', 'level_up', 'badge_unlock',
        'quest_milestone', 'exercise_milestone', 'program_complete'
      ));
  END IF;
END $$;

-- Add program_complete share card template
INSERT INTO share_card_templates (template_type, background_color, accent_color, icon_name, message_template)
VALUES ('program_complete', '#9B59B6', '#FFFFFF', 'checkmark.seal.fill', 'Completed the {value} program on MindFriend! 🎓')
ON CONFLICT (template_type) DO UPDATE SET
  background_color = EXCLUDED.background_color,
  accent_color = EXCLUDED.accent_color,
  icon_name = EXCLUDED.icon_name,
  message_template = EXCLUDED.message_template;

-- =============================================================================
-- MARK: - Database Functions
-- =============================================================================

-- Function: Enroll user in program
-- SECURITY: Uses auth.uid() directly to prevent IDOR attacks
CREATE OR REPLACE FUNCTION enroll_in_program(
  p_program_id UUID,
  p_preferred_time TIME DEFAULT '09:00:00'
)
RETURNS UUID AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_enrollment_id UUID;
  v_is_premium BOOLEAN;
  v_program_premium BOOLEAN;
  v_has_active BOOLEAN;
BEGIN
  -- Ensure user is authenticated
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Check if user has premium (if program requires it)
  SELECT COALESCE(subscription_tier = 'premium', FALSE) INTO v_is_premium
  FROM profiles WHERE id = v_user_id;

  SELECT premium_only INTO v_program_premium
  FROM programs WHERE id = p_program_id AND is_active = TRUE;

  IF v_program_premium IS NULL THEN
    RAISE EXCEPTION 'Program not found or inactive';
  END IF;

  IF v_program_premium AND NOT COALESCE(v_is_premium, FALSE) THEN
    RAISE EXCEPTION 'Premium subscription required for this program';
  END IF;

  -- Check for existing active enrollment (only one active at a time)
  SELECT EXISTS(
    SELECT 1 FROM program_enrollments
    WHERE user_id = v_user_id AND status = 'active'
  ) INTO v_has_active;

  IF v_has_active THEN
    RAISE EXCEPTION 'Already enrolled in an active program. Complete or pause current program first.';
  END IF;

  -- Create enrollment
  INSERT INTO program_enrollments (
    user_id, program_id, preferred_time_local
  ) VALUES (
    v_user_id, p_program_id, p_preferred_time
  ) RETURNING id INTO v_enrollment_id;

  -- Create day 1 progress entry
  INSERT INTO program_day_progress (enrollment_id, day_number, status)
  VALUES (v_enrollment_id, 1, 'pending');

  RETURN v_enrollment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Complete a program day
-- SECURITY: Validates enrollment ownership via auth.uid()
CREATE OR REPLACE FUNCTION complete_program_day(
  p_enrollment_id UUID,
  p_day_number INT,
  p_content_completed JSONB,
  p_reflection_response TEXT DEFAULT NULL,
  p_apply_report TEXT DEFAULT NULL,
  p_exercise_session_id UUID DEFAULT NULL,
  p_mood_before INT DEFAULT NULL,
  p_mood_after INT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_enrollment program_enrollments%ROWTYPE;
  v_program programs%ROWTYPE;
  v_day program_days%ROWTYPE;
  v_required_completed BOOLEAN;
  v_is_program_complete BOOLEAN;
  v_certificate_number TEXT;
  v_result JSONB;
BEGIN
  -- Ensure user is authenticated
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Get enrollment and verify ownership
  SELECT * INTO v_enrollment FROM program_enrollments
  WHERE id = p_enrollment_id AND user_id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enrollment not found or access denied';
  END IF;

  IF v_enrollment.status != 'active' THEN
    RAISE EXCEPTION 'Enrollment is not active';
  END IF;

  -- Get program and day
  SELECT * INTO v_program FROM programs WHERE id = v_enrollment.program_id;
  SELECT * INTO v_day FROM program_days
  WHERE program_id = v_program.id AND day_number = p_day_number;

  IF v_day IS NULL THEN
    RAISE EXCEPTION 'Day % not found in program', p_day_number;
  END IF;

  -- Check required content is completed
  SELECT COALESCE(
    (SELECT bool_and(p_content_completed ? req)
     FROM jsonb_array_elements_text(v_day.completion_criteria->'required') req),
    TRUE
  ) INTO v_required_completed;

  IF NOT v_required_completed THEN
    RAISE EXCEPTION 'Required content not completed';
  END IF;

  -- Update or insert day progress
  INSERT INTO program_day_progress (
    enrollment_id, day_number, status, started_at, completed_at,
    content_completed, reflection_response, apply_report,
    exercise_session_id, mood_before, mood_after
  ) VALUES (
    p_enrollment_id, p_day_number, 'completed', NOW(), NOW(),
    p_content_completed, p_reflection_response, p_apply_report,
    p_exercise_session_id, p_mood_before, p_mood_after
  )
  ON CONFLICT (enrollment_id, day_number)
  DO UPDATE SET
    status = 'completed',
    completed_at = NOW(),
    content_completed = p_content_completed,
    reflection_response = COALESCE(p_reflection_response, program_day_progress.reflection_response),
    apply_report = COALESCE(p_apply_report, program_day_progress.apply_report),
    exercise_session_id = COALESCE(p_exercise_session_id, program_day_progress.exercise_session_id),
    mood_before = COALESCE(p_mood_before, program_day_progress.mood_before),
    mood_after = COALESCE(p_mood_after, program_day_progress.mood_after),
    updated_at = NOW();

  -- Update enrollment streak and current day
  UPDATE program_enrollments SET
    streak_days = streak_days + 1,
    longest_streak = GREATEST(longest_streak, streak_days + 1),
    current_day = LEAST(current_day + 1, v_program.duration_days),
    updated_at = NOW()
  WHERE id = p_enrollment_id
  RETURNING * INTO v_enrollment;

  -- Check if program is complete
  v_is_program_complete := (p_day_number >= v_program.duration_days);

  IF v_is_program_complete THEN
    -- Mark enrollment complete
    UPDATE program_enrollments SET
      status = 'completed',
      completed_at = NOW()
    WHERE id = p_enrollment_id;

    -- Generate certificate number
    v_certificate_number := 'MF-' || TO_CHAR(NOW(), 'YYYY') || '-' || LPAD(NEXTVAL('certificate_seq')::TEXT, 6, '0');

    -- Create certificate
    INSERT INTO program_certificates (
      user_id, program_id, enrollment_id, certificate_number, completion_stats
    ) VALUES (
      v_user_id, v_program.id, p_enrollment_id, v_certificate_number,
      jsonb_build_object(
        'days_completed', v_program.duration_days,
        'streak_best', v_enrollment.longest_streak,
        'skips_used', v_enrollment.skips_used,
        'program_title', v_program.title
      )
    );

    -- Create celebration event for program completion
    INSERT INTO celebration_events (
      user_id, celebration_type, value, shown_at
    ) VALUES (
      v_user_id, 'program_complete', v_program.duration_days, NULL
    );

    -- Award XP (200 for program completion)
    -- Note: award_xp function may not exist yet, wrap in exception handler
    BEGIN
      PERFORM award_xp(v_user_id, 200, 'program_completion', v_program.category);
    EXCEPTION WHEN undefined_function THEN
      -- award_xp not defined yet, skip silently
      NULL;
    END;
  ELSE
    -- Create next day progress entry
    INSERT INTO program_day_progress (enrollment_id, day_number, status)
    VALUES (p_enrollment_id, p_day_number + 1, 'pending')
    ON CONFLICT DO NOTHING;
  END IF;

  v_result := jsonb_build_object(
    'day_completed', p_day_number,
    'program_complete', v_is_program_complete,
    'next_day', CASE WHEN v_is_program_complete THEN NULL ELSE p_day_number + 1 END,
    'streak', v_enrollment.streak_days,
    'certificate_number', CASE WHEN v_is_program_complete THEN v_certificate_number ELSE NULL END
  );

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Skip a program day
-- SECURITY: Validates enrollment ownership via auth.uid()
CREATE OR REPLACE FUNCTION skip_program_day(
  p_enrollment_id UUID,
  p_day_number INT
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_enrollment program_enrollments%ROWTYPE;
  v_program programs%ROWTYPE;
BEGIN
  -- Ensure user is authenticated
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Get enrollment and verify ownership
  SELECT * INTO v_enrollment FROM program_enrollments
  WHERE id = p_enrollment_id AND user_id = v_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enrollment not found or access denied';
  END IF;

  IF v_enrollment.status != 'active' THEN
    RAISE EXCEPTION 'Enrollment is not active';
  END IF;

  IF v_enrollment.skips_used >= v_enrollment.skips_allowed THEN
    RAISE EXCEPTION 'No skips remaining';
  END IF;

  -- Get program
  SELECT * INTO v_program FROM programs WHERE id = v_enrollment.program_id;

  -- Mark day as skipped
  INSERT INTO program_day_progress (
    enrollment_id, day_number, status, completed_at
  ) VALUES (
    p_enrollment_id, p_day_number, 'skipped', NOW()
  )
  ON CONFLICT (enrollment_id, day_number)
  DO UPDATE SET
    status = 'skipped',
    completed_at = NOW(),
    updated_at = NOW();

  -- Update enrollment
  UPDATE program_enrollments SET
    skips_used = skips_used + 1,
    current_day = LEAST(current_day + 1, v_program.duration_days),
    streak_days = 0,  -- Reset streak on skip
    updated_at = NOW()
  WHERE id = p_enrollment_id
  RETURNING * INTO v_enrollment;

  -- Create next day progress entry
  INSERT INTO program_day_progress (enrollment_id, day_number, status)
  VALUES (p_enrollment_id, p_day_number + 1, 'pending')
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object(
    'day_skipped', p_day_number,
    'skips_remaining', v_enrollment.skips_allowed - v_enrollment.skips_used,
    'next_day', p_day_number + 1
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Pause enrollment
-- SECURITY: Validates ownership via auth.uid()
CREATE OR REPLACE FUNCTION pause_program_enrollment(
  p_enrollment_id UUID
)
RETURNS VOID AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  UPDATE program_enrollments SET
    status = 'paused',
    paused_at = NOW(),
    updated_at = NOW()
  WHERE id = p_enrollment_id
    AND user_id = v_user_id
    AND status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enrollment not found, not owned by user, or not active';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Resume enrollment
-- SECURITY: Validates ownership via auth.uid()
CREATE OR REPLACE FUNCTION resume_program_enrollment(
  p_enrollment_id UUID
)
RETURNS VOID AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_has_other_active BOOLEAN;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Check if user has another active enrollment
  SELECT EXISTS(
    SELECT 1 FROM program_enrollments
    WHERE user_id = v_user_id
      AND status = 'active'
      AND id != p_enrollment_id
  ) INTO v_has_other_active;

  IF v_has_other_active THEN
    RAISE EXCEPTION 'Cannot resume: another program is already active';
  END IF;

  UPDATE program_enrollments SET
    status = 'active',
    paused_at = NULL,
    streak_days = 0,  -- Reset streak after pause
    updated_at = NOW()
  WHERE id = p_enrollment_id
    AND user_id = v_user_id
    AND status = 'paused';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enrollment not found, not owned by user, or not paused';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Abandon enrollment
-- SECURITY: Validates ownership via auth.uid()
CREATE OR REPLACE FUNCTION abandon_program_enrollment(
  p_enrollment_id UUID
)
RETURNS VOID AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  UPDATE program_enrollments SET
    status = 'abandoned',
    abandoned_at = NOW(),
    updated_at = NOW()
  WHERE id = p_enrollment_id
    AND user_id = v_user_id
    AND status IN ('active', 'paused');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Enrollment not found, not owned by user, or already completed/abandoned';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Get user's program stats
-- SECURITY: Uses auth.uid() directly
CREATE OR REPLACE FUNCTION get_user_program_stats()
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_result JSONB;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT jsonb_build_object(
    'programs_completed', (SELECT COUNT(*) FROM program_enrollments WHERE user_id = v_user_id AND status = 'completed'),
    'programs_active', (SELECT COUNT(*) FROM program_enrollments WHERE user_id = v_user_id AND status = 'active'),
    'programs_paused', (SELECT COUNT(*) FROM program_enrollments WHERE user_id = v_user_id AND status = 'paused'),
    'total_days_completed', (
      SELECT COALESCE(SUM(pdp.day_number), 0)
      FROM program_day_progress pdp
      JOIN program_enrollments pe ON pe.id = pdp.enrollment_id
      WHERE pe.user_id = v_user_id AND pdp.status = 'completed'
    ),
    'certificates_earned', (SELECT COUNT(*) FROM program_certificates WHERE user_id = v_user_id)
  ) INTO v_result;

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- MARK: - Seed Initial Programs
-- =============================================================================

-- 7-Day Welcome Journey (Free)
INSERT INTO programs (slug, title, description, duration_days, category, difficulty, premium_only, learning_objectives, tags, estimated_daily_minutes, sort_order)
VALUES (
  'welcome-journey',
  '7-Day Welcome Journey',
  'Get started with MindFriend and build your wellness foundation. This introductory program guides you through all the key features while establishing healthy daily habits.',
  7,
  'intro',
  'beginner',
  FALSE,
  '["Learn how to use MindFriend effectively", "Establish a daily wellness routine", "Understand your baseline mood patterns", "Try your first exercises and quests", "Connect with your wellness community"]'::jsonb,
  ARRAY['getting-started', 'habits', 'beginner'],
  10,
  1
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  learning_objectives = EXCLUDED.learning_objectives;

-- 7-Day Gratitude Practice (Free)
INSERT INTO programs (slug, title, description, duration_days, category, difficulty, premium_only, learning_objectives, tags, estimated_daily_minutes, sort_order)
VALUES (
  'gratitude-practice',
  '7-Day Gratitude Practice',
  'Transform your perspective through the power of gratitude. This week-long journey helps you develop a sustainable gratitude practice that can shift your mindset.',
  7,
  'gratitude',
  'beginner',
  FALSE,
  '["Understand the science behind gratitude", "Build a daily gratitude habit", "Notice more positive aspects of your life", "Express appreciation meaningfully", "Create lasting mindset shifts"]'::jsonb,
  ARRAY['gratitude', 'mindset', 'beginner', 'journaling'],
  10,
  2
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  learning_objectives = EXCLUDED.learning_objectives;

-- 14-Day Mindfulness Foundations (Free intro)
INSERT INTO programs (slug, title, description, duration_days, category, difficulty, premium_only, learning_objectives, tags, estimated_daily_minutes, sort_order)
VALUES (
  'mindfulness-foundations',
  '14-Day Mindfulness Foundations',
  'Build a solid foundation in mindfulness practice. Learn the fundamentals of present-moment awareness and develop a meditation practice that fits your lifestyle.',
  14,
  'mindfulness',
  'beginner',
  FALSE,
  '["Master basic meditation techniques", "Cultivate present-moment awareness", "Understand the mind-body connection", "Handle distractions skillfully", "Integrate mindfulness into daily activities"]'::jsonb,
  ARRAY['mindfulness', 'meditation', 'beginner', 'awareness'],
  15,
  3
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  learning_objectives = EXCLUDED.learning_objectives;

-- 21-Day Anxiety Reset (Premium)
INSERT INTO programs (slug, title, description, duration_days, category, difficulty, premium_only, learning_objectives, tags, estimated_daily_minutes, sort_order)
VALUES (
  '21-day-anxiety-reset',
  '21-Day Anxiety Reset',
  'A comprehensive program to understand, manage, and reduce anxiety. Using evidence-based CBT techniques, breathing exercises, and grounding practices, you''ll build a toolkit for lasting calm.',
  21,
  'anxiety',
  'beginner',
  TRUE,
  '["Understand your anxiety triggers and patterns", "Master calming breathing techniques", "Learn effective grounding exercises", "Apply CBT thought challenging skills", "Build a personalized anxiety management toolkit"]'::jsonb,
  ARRAY['anxiety', 'cbt', 'breathing', 'grounding', 'calm'],
  15,
  4
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  learning_objectives = EXCLUDED.learning_objectives;

-- 14-Day Sleep Transformation (Premium)
INSERT INTO programs (slug, title, description, duration_days, category, difficulty, premium_only, learning_objectives, tags, estimated_daily_minutes, sort_order)
VALUES (
  'sleep-transformation',
  '14-Day Sleep Transformation',
  'Reset your sleep patterns and wake up refreshed. This program addresses sleep hygiene, wind-down routines, and relaxation techniques for better rest.',
  14,
  'sleep',
  'beginner',
  TRUE,
  '["Optimize your sleep environment", "Establish consistent sleep-wake times", "Create an effective wind-down routine", "Manage racing thoughts at bedtime", "Track and understand your sleep patterns"]'::jsonb,
  ARRAY['sleep', 'rest', 'relaxation', 'night-routine'],
  12,
  5
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  learning_objectives = EXCLUDED.learning_objectives;

-- 14-Day Focus Mastery (Premium)
INSERT INTO programs (slug, title, description, duration_days, category, difficulty, premium_only, learning_objectives, tags, estimated_daily_minutes, sort_order)
VALUES (
  'focus-mastery',
  '14-Day Focus Mastery',
  'Sharpen your attention and master deep work. Learn techniques to minimize distractions, build concentration, and achieve flow states more consistently.',
  14,
  'focus',
  'intermediate',
  TRUE,
  '["Understand attention and distraction mechanisms", "Build your focus muscle gradually", "Design an optimal work environment", "Use timeboxing and pomodoro techniques", "Achieve flow states on demand"]'::jsonb,
  ARRAY['focus', 'attention', 'productivity', 'deep-work'],
  15,
  6
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  learning_objectives = EXCLUDED.learning_objectives;

-- 21-Day Stress Resilience (Premium)
INSERT INTO programs (slug, title, description, duration_days, category, difficulty, premium_only, learning_objectives, tags, estimated_daily_minutes, sort_order)
VALUES (
  'stress-resilience',
  '21-Day Stress Resilience',
  'Build unshakeable resilience to life''s challenges. This comprehensive program combines stress management techniques, coping strategies, and recovery practices.',
  21,
  'stress',
  'intermediate',
  TRUE,
  '["Recognize early stress warning signs", "Develop multiple coping strategies", "Build physical and mental resilience", "Create stress recovery routines", "Maintain calm under pressure"]'::jsonb,
  ARRAY['stress', 'resilience', 'coping', 'recovery'],
  15,
  7
)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title,
  description = EXCLUDED.description,
  learning_objectives = EXCLUDED.learning_objectives;

-- =============================================================================
-- MARK: - Seed Program Days for Welcome Journey (Day 1-7)
-- =============================================================================

-- Get the welcome-journey program ID and create days
DO $$
DECLARE
  v_program_id UUID;
BEGIN
  SELECT id INTO v_program_id FROM programs WHERE slug = 'welcome-journey';

  IF v_program_id IS NOT NULL THEN
    -- Day 1
    INSERT INTO program_days (program_id, day_number, title, theme, content, completion_criteria)
    VALUES (
      v_program_id, 1,
      'Welcome to Your Journey',
      'Getting Started',
      '[
        {"type": "learn", "title": "Welcome to MindFriend", "body": "MindFriend is your personal wellness companion, designed to help you build sustainable mental wellness habits. Over the next 7 days, you''ll explore the core features and start building routines that work for you.\n\nToday is about getting oriented and taking your first steps. There''s no pressure to be perfect—just show up and be curious.", "duration_minutes": 3},
        {"type": "check_in", "title": "Your First Mood Check", "body": "Let''s establish your baseline. How are you feeling right now?"},
        {"type": "apply", "challenge": "Explore the Home tab and notice all the different features available to you. What catches your interest most?", "report_back": true}
      ]'::jsonb,
      '{"required": ["check_in"], "optional": ["learn", "apply"]}'::jsonb
    )
    ON CONFLICT (program_id, day_number) DO UPDATE SET
      title = EXCLUDED.title,
      content = EXCLUDED.content;

    -- Day 2
    INSERT INTO program_days (program_id, day_number, title, theme, content, completion_criteria)
    VALUES (
      v_program_id, 2,
      'Understanding Your Moods',
      'Self-Awareness',
      '[
        {"type": "learn", "title": "Why Track Your Mood?", "body": "Mood tracking is more than just recording how you feel—it''s about building self-awareness. Over time, you''ll start to notice patterns: what times of day you feel best, what activities boost your mood, and what triggers might bring you down.\n\nThis awareness is the foundation for making positive changes.", "duration_minutes": 3},
        {"type": "check_in", "title": "Morning Check-In", "body": "Take a moment to notice your current state."},
        {"type": "reflect", "prompt": "Think about yesterday. What was one moment you felt good, and one moment you felt challenged? What was happening in each situation?", "min_words": 30}
      ]'::jsonb,
      '{"required": ["check_in"], "optional": ["learn", "reflect"]}'::jsonb
    )
    ON CONFLICT (program_id, day_number) DO UPDATE SET
      title = EXCLUDED.title,
      content = EXCLUDED.content;

    -- Day 3
    INSERT INTO program_days (program_id, day_number, title, theme, content, completion_criteria)
    VALUES (
      v_program_id, 3,
      'Your First Exercise',
      'Practice',
      '[
        {"type": "learn", "title": "The Power of Pause", "body": "Our exercise library contains evidence-based techniques for managing stress, anxiety, and other challenges. Each exercise is designed to be done in just a few minutes.\n\nThe key isn''t perfection—it''s consistency. Even 5 minutes of practice can make a difference.", "duration_minutes": 2},
        {"type": "practice", "exercise_id": null, "intro": "Today, try a simple breathing exercise. It takes just 5 minutes and can reset your nervous system."},
        {"type": "reflect", "prompt": "How did you feel before and after the exercise? Notice any changes, even subtle ones.", "min_words": 20}
      ]'::jsonb,
      '{"required": ["practice"], "optional": ["learn", "reflect"]}'::jsonb
    )
    ON CONFLICT (program_id, day_number) DO UPDATE SET
      title = EXCLUDED.title,
      content = EXCLUDED.content;

    -- Day 4
    INSERT INTO program_days (program_id, day_number, title, theme, content, completion_criteria)
    VALUES (
      v_program_id, 4,
      'Daily Quests',
      'Habit Building',
      '[
        {"type": "learn", "title": "Small Steps, Big Changes", "body": "Daily quests are simple wellness activities assigned each day. They''re designed to be achievable—not overwhelming. Completing quests builds your streak and earns rewards.\n\nThe magic is in consistency. A 5-minute quest done daily beats an hour-long session done once a week.", "duration_minutes": 2},
        {"type": "check_in", "title": "Mid-Week Check", "body": "How are you feeling about the journey so far?"},
        {"type": "apply", "challenge": "Complete today''s daily quest from your home screen. Notice how it feels to check off that accomplishment.", "report_back": true}
      ]'::jsonb,
      '{"required": ["apply"], "optional": ["learn", "check_in"]}'::jsonb
    )
    ON CONFLICT (program_id, day_number) DO UPDATE SET
      title = EXCLUDED.title,
      content = EXCLUDED.content;

    -- Day 5
    INSERT INTO program_days (program_id, day_number, title, theme, content, completion_criteria)
    VALUES (
      v_program_id, 5,
      'Meet Your AI Companion',
      'Support',
      '[
        {"type": "learn", "title": "Your Personal Wellness Guide", "body": "The MindFriend AI is available whenever you need to talk, vent, or work through something. It''s trained to be supportive, non-judgmental, and helpful—like a wise friend who''s always available.\n\nYou can chat about anything: daily stresses, big decisions, or just to reflect on your day.", "duration_minutes": 3},
        {"type": "apply", "challenge": "Start a conversation with the AI. You could share how your week has been going, ask for advice on something, or just say hello.", "report_back": true},
        {"type": "reflect", "prompt": "What did you talk about? How did it feel to express yourself?", "min_words": 20}
      ]'::jsonb,
      '{"required": ["apply"], "optional": ["learn", "reflect"]}'::jsonb
    )
    ON CONFLICT (program_id, day_number) DO UPDATE SET
      title = EXCLUDED.title,
      content = EXCLUDED.content;

    -- Day 6
    INSERT INTO program_days (program_id, day_number, title, theme, content, completion_criteria)
    VALUES (
      v_program_id, 6,
      'Your Wellness Circle',
      'Community',
      '[
        {"type": "learn", "title": "Better Together", "body": "Wellness is easier when you''re not alone. Circles let you connect with friends, family, or others on the same journey. You can share check-ins, celebrate wins, and support each other through challenges.\n\nEven small gestures—like reacting to someone''s achievement—can make a big difference.", "duration_minutes": 3},
        {"type": "check_in", "title": "Connection Check", "body": "How connected do you feel to others in your wellness journey?"},
        {"type": "apply", "challenge": "Explore the Circles tab. If you have a circle, post a check-in. If not, consider inviting someone close to you.", "report_back": true}
      ]'::jsonb,
      '{"required": ["check_in"], "optional": ["learn", "apply"]}'::jsonb
    )
    ON CONFLICT (program_id, day_number) DO UPDATE SET
      title = EXCLUDED.title,
      content = EXCLUDED.content;

    -- Day 7
    INSERT INTO program_days (program_id, day_number, title, theme, content, completion_criteria)
    VALUES (
      v_program_id, 7,
      'Your Wellness Plan',
      'Looking Forward',
      '[
        {"type": "learn", "title": "Congratulations!", "body": "You''ve completed your Welcome Journey! Over the past week, you''ve explored mood tracking, exercises, quests, AI support, and community. You now have a foundation for your ongoing wellness practice.\n\nThe journey doesn''t end here—it''s just beginning. Consider your next steps: What features resonated most? What would you like to explore deeper?", "duration_minutes": 3},
        {"type": "reflect", "prompt": "Looking back at this week: What surprised you? What did you learn about yourself? What habit or practice do you want to continue?", "min_words": 50},
        {"type": "apply", "challenge": "Set an intention for your ongoing wellness journey. What one thing will you commit to doing regularly?", "report_back": true}
      ]'::jsonb,
      '{"required": ["reflect"], "optional": ["learn", "apply"]}'::jsonb
    )
    ON CONFLICT (program_id, day_number) DO UPDATE SET
      title = EXCLUDED.title,
      content = EXCLUDED.content;
  END IF;
END $$;

-- =============================================================================
-- MARK: - Seed Program Days for Gratitude Practice (Day 1-7)
-- =============================================================================

DO $$
DECLARE
  v_program_id UUID;
BEGIN
  SELECT id INTO v_program_id FROM programs WHERE slug = 'gratitude-practice';

  IF v_program_id IS NOT NULL THEN
    -- Day 1
    INSERT INTO program_days (program_id, day_number, title, theme, content, completion_criteria)
    VALUES (
      v_program_id, 1,
      'The Science of Gratitude',
      'Foundation',
      '[
        {"type": "learn", "title": "Why Gratitude Works", "body": "Research shows that practicing gratitude can increase happiness, reduce depression, improve sleep, and even strengthen your immune system. It literally rewires your brain to notice more positive aspects of life.\n\nThe key is consistency—even just a few minutes daily can create lasting changes.", "duration_minutes": 3},
        {"type": "check_in", "title": "Starting Point", "body": "Rate your current overall life satisfaction."},
        {"type": "reflect", "prompt": "Write down three things you''re grateful for today. They can be big or small—anything that brings you a sense of appreciation.", "min_words": 30}
      ]'::jsonb,
      '{"required": ["reflect"], "optional": ["learn", "check_in"]}'::jsonb
    )
    ON CONFLICT (program_id, day_number) DO UPDATE SET
      title = EXCLUDED.title,
      content = EXCLUDED.content;

    -- Day 2-7 (abbreviated for migration size)
    INSERT INTO program_days (program_id, day_number, title, theme, content, completion_criteria)
    VALUES
    (v_program_id, 2, 'Noticing the Small Things', 'Awareness',
     '[{"type": "learn", "title": "Hidden Blessings", "body": "Often we take the small things for granted—running water, a comfortable bed, a text from a friend. Today, practice noticing these hidden blessings.", "duration_minutes": 2}, {"type": "reflect", "prompt": "List 5 small things in your daily routine that you usually overlook but can be grateful for.", "min_words": 30}]'::jsonb,
     '{"required": ["reflect"], "optional": ["learn"]}'::jsonb),
    (v_program_id, 3, 'Grateful for People', 'Relationships',
     '[{"type": "learn", "title": "People in Your Life", "body": "The people around us—family, friends, even strangers who help—are often our greatest sources of joy. Today, focus gratitude on the humans in your life.", "duration_minutes": 2}, {"type": "reflect", "prompt": "Think of someone who has positively impacted your life. What specifically are you grateful for about them?", "min_words": 40}, {"type": "apply", "challenge": "Send a thank-you message to someone you appreciate. It doesn''t have to be long—just genuine.", "report_back": true}]'::jsonb,
     '{"required": ["reflect"], "optional": ["learn", "apply"]}'::jsonb),
    (v_program_id, 4, 'Challenges as Teachers', 'Perspective',
     '[{"type": "learn", "title": "Finding Silver Linings", "body": "Advanced gratitude practice includes finding gratitude even in challenges. Difficulties can teach us resilience, reveal our strengths, or lead to unexpected opportunities.", "duration_minutes": 3}, {"type": "reflect", "prompt": "Think of a past challenge that taught you something valuable. What are you grateful for about that experience?", "min_words": 50}]'::jsonb,
     '{"required": ["reflect"], "optional": ["learn"]}'::jsonb),
    (v_program_id, 5, 'Body Gratitude', 'Physical',
     '[{"type": "learn", "title": "Your Amazing Body", "body": "Our bodies work constantly for us—beating hearts, breathing lungs, healing wounds. Today, direct gratitude toward your physical self.", "duration_minutes": 2}, {"type": "practice", "exercise_id": null, "intro": "Do a brief body scan meditation, thanking each part of your body."}, {"type": "reflect", "prompt": "What does your body do for you that you''re grateful for?", "min_words": 30}]'::jsonb,
     '{"required": ["reflect"], "optional": ["learn", "practice"]}'::jsonb),
    (v_program_id, 6, 'Gratitude Letter', 'Expression',
     '[{"type": "learn", "title": "The Power of Expression", "body": "Writing a gratitude letter is one of the most powerful gratitude exercises. It combines reflection with expression, deepening the positive impact.", "duration_minutes": 2}, {"type": "reflect", "prompt": "Write a gratitude letter to someone important in your life. Tell them specifically why you appreciate them and how they''ve impacted you.", "min_words": 100}]'::jsonb,
     '{"required": ["reflect"], "optional": ["learn"]}'::jsonb),
    (v_program_id, 7, 'Making It a Habit', 'Integration',
     '[{"type": "learn", "title": "Sustaining Gratitude", "body": "You''ve completed your gratitude journey! The key now is making it sustainable. Choose a simple daily practice you can maintain.", "duration_minutes": 3}, {"type": "reflect", "prompt": "Reflect on this week. What did you learn about yourself? What gratitude practice will you continue?", "min_words": 50}, {"type": "check_in", "title": "Final Check", "body": "Rate your current overall life satisfaction compared to when you started."}]'::jsonb,
     '{"required": ["reflect"], "optional": ["learn", "check_in"]}'::jsonb)
    ON CONFLICT (program_id, day_number) DO UPDATE SET
      title = EXCLUDED.title,
      content = EXCLUDED.content;
  END IF;
END $$;

-- Note: Additional program days for premium programs would be added similarly
-- Keeping migration concise by only seeding free programs fully

COMMIT;
