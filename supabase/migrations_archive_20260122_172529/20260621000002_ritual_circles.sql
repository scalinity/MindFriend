-- Ritual Circles Migration
-- Synchronized 3-5 minute rituals with shared timer, prompts, and recap posts

-- ============================================================================
-- TABLES
-- ============================================================================

-- Main rituals table
CREATE TABLE IF NOT EXISTS circle_rituals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 60),
  ritual_type TEXT NOT NULL CHECK (ritual_type IN ('gratitude', 'grounding', 'wins', 'breathing')),
  scheduled_for TIMESTAMPTZ NOT NULL,
  duration_seconds INT NOT NULL CHECK (duration_seconds BETWEEN 180 AND 300),
  status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'active', 'completed', 'cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

-- Attendance tracking (no unique constraint to allow rejoin tracking)
CREATE TABLE IF NOT EXISTS circle_ritual_attendees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ritual_id UUID NOT NULL REFERENCES circle_rituals(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  left_at TIMESTAMPTZ,
  UNIQUE(ritual_id, user_id)
);

-- Post-ritual reflections
CREATE TABLE IF NOT EXISTS circle_ritual_reflections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ritual_id UUID NOT NULL REFERENCES circle_rituals(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body_text TEXT NOT NULL CHECK (char_length(body_text) BETWEEN 1 AND 140),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(ritual_id, user_id)
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_circle_rituals_circle_scheduled
  ON circle_rituals(circle_id, scheduled_for DESC);

CREATE INDEX IF NOT EXISTS idx_circle_rituals_status
  ON circle_rituals(status, scheduled_for)
  WHERE status IN ('scheduled', 'active');

CREATE INDEX IF NOT EXISTS idx_ritual_attendees_ritual
  ON circle_ritual_attendees(ritual_id, joined_at);

CREATE INDEX IF NOT EXISTS idx_ritual_attendees_user
  ON circle_ritual_attendees(user_id);

CREATE INDEX IF NOT EXISTS idx_ritual_reflections_ritual
  ON circle_ritual_reflections(ritual_id, created_at);

-- ============================================================================
-- ENABLE RLS
-- ============================================================================

ALTER TABLE circle_rituals ENABLE ROW LEVEL SECURITY;
ALTER TABLE circle_ritual_attendees ENABLE ROW LEVEL SECURITY;
ALTER TABLE circle_ritual_reflections ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- RLS POLICIES: circle_rituals
-- ============================================================================

-- Circle members can view rituals in their circles
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'circle_rituals'
    AND policyname = 'Members can view circle rituals'
  ) THEN
    CREATE POLICY "Members can view circle rituals" ON circle_rituals
      FOR SELECT USING (
        EXISTS (
          SELECT 1 FROM circle_members
          WHERE circle_members.circle_id = circle_rituals.circle_id
            AND circle_members.user_id = auth.uid()
        )
      );
  END IF;
END $$;

-- Circle members can create rituals
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'circle_rituals'
    AND policyname = 'Members can create rituals'
  ) THEN
    CREATE POLICY "Members can create rituals" ON circle_rituals
      FOR INSERT WITH CHECK (
        auth.uid() = created_by AND
        EXISTS (
          SELECT 1 FROM circle_members
          WHERE circle_members.circle_id = circle_rituals.circle_id
            AND circle_members.user_id = auth.uid()
        )
      );
  END IF;
END $$;

-- Creators can update their own rituals (for status changes)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'circle_rituals'
    AND policyname = 'Creators can update own rituals'
  ) THEN
    CREATE POLICY "Creators can update own rituals" ON circle_rituals
      FOR UPDATE USING (auth.uid() = created_by);
  END IF;
END $$;

-- ============================================================================
-- RLS POLICIES: circle_ritual_attendees
-- ============================================================================

-- Circle members can view attendance for rituals in their circles
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'circle_ritual_attendees'
    AND policyname = 'Members can view ritual attendance'
  ) THEN
    CREATE POLICY "Members can view ritual attendance" ON circle_ritual_attendees
      FOR SELECT USING (
        EXISTS (
          SELECT 1 FROM circle_rituals r
          JOIN circle_members m ON m.circle_id = r.circle_id
          WHERE r.id = circle_ritual_attendees.ritual_id
            AND m.user_id = auth.uid()
        )
      );
  END IF;
END $$;

-- Users can create their own attendance records (must be circle member)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'circle_ritual_attendees'
    AND policyname = 'Users can join rituals'
  ) THEN
    CREATE POLICY "Users can join rituals" ON circle_ritual_attendees
      FOR INSERT WITH CHECK (
        auth.uid() = user_id AND
        EXISTS (
          SELECT 1 FROM circle_rituals r
          JOIN circle_members m ON m.circle_id = r.circle_id
          WHERE r.id = circle_ritual_attendees.ritual_id
            AND m.user_id = auth.uid()
        )
      );
  END IF;
END $$;

-- Users can update their own attendance (set left_at)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'circle_ritual_attendees'
    AND policyname = 'Users can leave rituals'
  ) THEN
    CREATE POLICY "Users can leave rituals" ON circle_ritual_attendees
      FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END $$;

-- ============================================================================
-- RLS POLICIES: circle_ritual_reflections
-- ============================================================================

-- Circle members can view reflections for rituals in their circles
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'circle_ritual_reflections'
    AND policyname = 'Members can view reflections'
  ) THEN
    CREATE POLICY "Members can view reflections" ON circle_ritual_reflections
      FOR SELECT USING (
        EXISTS (
          SELECT 1 FROM circle_rituals r
          JOIN circle_members m ON m.circle_id = r.circle_id
          WHERE r.id = circle_ritual_reflections.ritual_id
            AND m.user_id = auth.uid()
        )
      );
  END IF;
END $$;

-- Users can create their own reflections (must have attended the ritual)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'circle_ritual_reflections'
    AND policyname = 'Users can add reflections'
  ) THEN
    CREATE POLICY "Users can add reflections" ON circle_ritual_reflections
      FOR INSERT WITH CHECK (
        auth.uid() = user_id AND
        EXISTS (
          SELECT 1 FROM circle_ritual_attendees a
          WHERE a.ritual_id = circle_ritual_reflections.ritual_id
            AND a.user_id = auth.uid()
        )
      );
  END IF;
END $$;

-- ============================================================================
-- EXTEND circle_posts FOR RECAP
-- ============================================================================

-- Add ritual_id column to circle_posts for linking recap posts
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'circle_posts'
    AND column_name = 'ritual_id'
  ) THEN
    ALTER TABLE circle_posts ADD COLUMN ritual_id UUID REFERENCES circle_rituals(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Index for fetching recap posts by ritual
CREATE INDEX IF NOT EXISTS idx_circle_posts_ritual
  ON circle_posts(ritual_id)
  WHERE ritual_id IS NOT NULL;

-- Update circle_posts kind check constraint to include 'ritual_recap'
-- First drop the existing constraint if it exists
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'circle_posts_kind_check'
    AND table_name = 'circle_posts'
  ) THEN
    ALTER TABLE circle_posts DROP CONSTRAINT circle_posts_kind_check;
  END IF;
END $$;

-- Add updated constraint including ritual_recap
ALTER TABLE circle_posts
  ADD CONSTRAINT circle_posts_kind_check
  CHECK (kind IN ('checkin', 'milestone', 'ritual_recap'));

-- ============================================================================
-- HELPER FUNCTION: Check if user is circle member
-- ============================================================================

CREATE OR REPLACE FUNCTION is_circle_member(p_circle_id UUID, p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM circle_members
    WHERE circle_id = p_circle_id
      AND user_id = p_user_id
  );
END;
$$;

-- ============================================================================
-- HELPER FUNCTION: Get ritual with current step info
-- ============================================================================

CREATE OR REPLACE FUNCTION get_ritual_current_step(
  p_ritual_id UUID,
  p_ritual_type TEXT,
  p_scheduled_for TIMESTAMPTZ,
  p_duration_seconds INT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_elapsed_seconds INT;
  v_step_duration INT;
  v_step_count INT;
  v_current_step INT;
  v_time_remaining INT;
BEGIN
  -- Calculate elapsed time
  v_elapsed_seconds := GREATEST(0, EXTRACT(EPOCH FROM (NOW() - p_scheduled_for))::INT);

  -- Determine step configuration based on ritual type
  CASE p_ritual_type
    WHEN 'gratitude' THEN v_step_duration := 60; v_step_count := 3;
    WHEN 'grounding' THEN v_step_duration := 45; v_step_count := 4;
    WHEN 'wins' THEN v_step_duration := 60; v_step_count := 3;
    WHEN 'breathing' THEN v_step_duration := 36; v_step_count := 5;
    ELSE v_step_duration := 60; v_step_count := 3;
  END CASE;

  -- Calculate current step (0-indexed, capped at last step)
  v_current_step := LEAST(v_elapsed_seconds / v_step_duration, v_step_count - 1);

  -- Calculate time remaining in current step
  v_time_remaining := v_step_duration - (v_elapsed_seconds % v_step_duration);

  -- If ritual has completed
  IF v_elapsed_seconds >= p_duration_seconds THEN
    RETURN json_build_object(
      'completed', true,
      'stepIndex', v_step_count - 1,
      'timeRemaining', 0
    );
  END IF;

  RETURN json_build_object(
    'completed', false,
    'stepIndex', v_current_step,
    'timeRemaining', v_time_remaining,
    'totalElapsed', v_elapsed_seconds
  );
END;
$$;
