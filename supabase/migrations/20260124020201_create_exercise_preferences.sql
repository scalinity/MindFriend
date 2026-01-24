-- Migration: Create exercise_generation_preferences table
-- Purpose: Store user preferences for personalized exercise generation
-- Author: dev-pipeline
-- Date: 2026-01-24

-- Create preferences table
CREATE TABLE IF NOT EXISTS exercise_generation_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Imagery and themes
  preferred_imagery TEXT[] DEFAULT ARRAY['nature', 'water']::TEXT[],
  avoid_themes TEXT[] DEFAULT ARRAY[]::TEXT[],

  -- Guidance preferences
  guidance_level TEXT DEFAULT 'moderate' CHECK (guidance_level IN ('minimal', 'moderate', 'detailed')),

  -- Voice preferences (reuse existing voice system)
  voice_preference TEXT DEFAULT 'warm',

  -- Duration preferences (in seconds)
  preferred_breathing_duration INTEGER DEFAULT 300,
  preferred_meditation_duration INTEGER DEFAULT 600,
  preferred_grounding_duration INTEGER DEFAULT 180,
  preferred_journaling_duration INTEGER DEFAULT 600,

  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Ensure one preference record per user
  UNIQUE(user_id)
);

-- Enable RLS
ALTER TABLE exercise_generation_preferences ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'exercise_generation_preferences'
    AND policyname = 'Users read own preferences'
  ) THEN
    CREATE POLICY "Users read own preferences"
      ON exercise_generation_preferences
      FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'exercise_generation_preferences'
    AND policyname = 'Users update own preferences'
  ) THEN
    CREATE POLICY "Users update own preferences"
      ON exercise_generation_preferences
      FOR UPDATE
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'exercise_generation_preferences'
    AND policyname = 'Users insert own preferences'
  ) THEN
    CREATE POLICY "Users insert own preferences"
      ON exercise_generation_preferences
      FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- Add index for user lookup
CREATE INDEX IF NOT EXISTS idx_exercise_gen_prefs_user
  ON exercise_generation_preferences(user_id);

-- Add comments
COMMENT ON TABLE exercise_generation_preferences IS 'User preferences for AI-generated exercise personalization (imagery, themes, guidance level, durations)';
COMMENT ON COLUMN exercise_generation_preferences.preferred_imagery IS 'Array of preferred imagery themes (e.g., ["nature", "ocean", "forest"])';
COMMENT ON COLUMN exercise_generation_preferences.avoid_themes IS 'Array of themes to avoid in generation';
COMMENT ON COLUMN exercise_generation_preferences.guidance_level IS 'Verbosity level: minimal (quiet spaces), moderate (balanced), detailed (step-by-step)';
