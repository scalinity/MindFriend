-- Migration: Extend weekly_stories with personalization features
-- Add user rating, favorite functionality, and narrative preferences table
-- Timestamp: 2026-01-23 07:00:00

-- ================================================================
-- 1. Extend weekly_stories table
-- ================================================================

-- Add user rating column (-1 for thumbs down, 1 for thumbs up, NULL for no rating)
ALTER TABLE weekly_stories
  ADD COLUMN IF NOT EXISTS user_rating INT CHECK (user_rating IN (-1, 1));

-- Add favorite flag
ALTER TABLE weekly_stories
  ADD COLUMN IF NOT EXISTS is_favorite BOOLEAN NOT NULL DEFAULT false;

-- Create index for favorites filter (only index favorited stories for performance)
CREATE INDEX IF NOT EXISTS idx_weekly_stories_is_favorite
  ON weekly_stories(user_id, is_favorite)
  WHERE is_favorite = true;

-- Create index for chronological ordering
CREATE INDEX IF NOT EXISTS idx_weekly_stories_week_start
  ON weekly_stories(user_id, week_start DESC);

COMMENT ON COLUMN weekly_stories.user_rating IS 'User feedback: -1 (thumbs down), 1 (thumbs up), NULL (no rating)';
COMMENT ON COLUMN weekly_stories.is_favorite IS 'Whether user has marked this story as favorite for quick access';

-- ================================================================
-- 2. Create narrative_preferences table
-- ================================================================

CREATE TABLE IF NOT EXISTS narrative_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Tone: warm (encouraging), professional (objective), playful (lighthearted)
  preferred_tone VARCHAR(32) NOT NULL DEFAULT 'warm' CHECK (preferred_tone IN ('warm', 'professional', 'playful')),

  -- Length: brief (2-3 cards), standard (3-5 cards), detailed (5-7 cards)
  preferred_length VARCHAR(32) NOT NULL DEFAULT 'standard' CHECK (preferred_length IN ('brief', 'standard', 'detailed')),

  -- Whether to include metrics (mood trends, quest counts) in narrative
  include_metrics BOOLEAN NOT NULL DEFAULT true,

  -- Future: generation frequency (weekly, biweekly, monthly)
  generation_frequency VARCHAR(32) NOT NULL DEFAULT 'weekly' CHECK (generation_frequency IN ('weekly', 'biweekly', 'monthly')),

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE narrative_preferences IS 'User personalization settings for weekly story generation';
COMMENT ON COLUMN narrative_preferences.preferred_tone IS 'Writing style: warm, professional, or playful';
COMMENT ON COLUMN narrative_preferences.preferred_length IS 'Story detail level: brief (2-3 cards), standard (3-5), detailed (5-7)';
COMMENT ON COLUMN narrative_preferences.include_metrics IS 'Whether to include quantitative data in narrative cards';

-- ================================================================
-- 3. Row Level Security (RLS) Policies
-- ================================================================

ALTER TABLE narrative_preferences ENABLE ROW LEVEL SECURITY;

-- Users can read their own preferences
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'narrative_preferences'
    AND policyname = 'Users can read own preferences'
  ) THEN
    CREATE POLICY "Users can read own preferences"
      ON narrative_preferences FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- Users can insert their own preferences
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'narrative_preferences'
    AND policyname = 'Users can insert own preferences'
  ) THEN
    CREATE POLICY "Users can insert own preferences"
      ON narrative_preferences FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- Users can update their own preferences
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'narrative_preferences'
    AND policyname = 'Users can update own preferences'
  ) THEN
    CREATE POLICY "Users can update own preferences"
      ON narrative_preferences FOR UPDATE
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- Allow users to update rating/favorite on their own weekly stories
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'weekly_stories'
    AND policyname = 'Users can update own story ratings'
  ) THEN
    CREATE POLICY "Users can update own story ratings"
      ON weekly_stories FOR UPDATE
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- ================================================================
-- 4. Triggers for updated_at
-- ================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_narrative_preferences_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger on narrative_preferences
DROP TRIGGER IF EXISTS trigger_narrative_preferences_updated_at ON narrative_preferences;
CREATE TRIGGER trigger_narrative_preferences_updated_at
  BEFORE UPDATE ON narrative_preferences
  FOR EACH ROW
  EXECUTE FUNCTION update_narrative_preferences_updated_at();

-- ================================================================
-- 5. Verification
-- ================================================================

-- Verify columns exist
DO $$
BEGIN
  -- Check user_rating column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'weekly_stories' AND column_name = 'user_rating'
  ) THEN
    RAISE EXCEPTION 'Migration failed: user_rating column not added to weekly_stories';
  END IF;

  -- Check is_favorite column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'weekly_stories' AND column_name = 'is_favorite'
  ) THEN
    RAISE EXCEPTION 'Migration failed: is_favorite column not added to weekly_stories';
  END IF;

  -- Check narrative_preferences table
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'narrative_preferences'
  ) THEN
    RAISE EXCEPTION 'Migration failed: narrative_preferences table not created';
  END IF;

  RAISE NOTICE 'Migration successful: weekly_stories extended, narrative_preferences created';
END $$;
