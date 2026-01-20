-- Migration: weekly_stories
-- Purpose: Store generated story cards for weekly progress recaps
-- Feature: Progress Stories (07-progress-stories-spec.md)

-- Create weekly_stories table
CREATE TABLE IF NOT EXISTS weekly_stories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  week_start DATE NOT NULL, -- Must be a Monday (YYYY-MM-DD)
  cards JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT unique_user_week UNIQUE(user_id, week_start)
);

-- Add table comment
COMMENT ON TABLE weekly_stories IS 'Visual story cards generated from weekly summaries for progress recaps';
COMMENT ON COLUMN weekly_stories.cards IS 'Array of story card objects: [{"type": "streak", "variant": "celebration", "data": {...}}]';
COMMENT ON COLUMN weekly_stories.week_start IS 'Monday of the week (ISO week start)';

-- Enable Row Level Security
ALTER TABLE weekly_stories ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
    AND tablename = 'weekly_stories'
    AND policyname = 'Users can read own stories'
  ) THEN
    CREATE POLICY "Users can read own stories" ON weekly_stories
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
    AND tablename = 'weekly_stories'
    AND policyname = 'Users can insert own stories'
  ) THEN
    CREATE POLICY "Users can insert own stories" ON weekly_stories
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
    AND tablename = 'weekly_stories'
    AND policyname = 'Users can update own stories'
  ) THEN
    CREATE POLICY "Users can update own stories" ON weekly_stories
      FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END $$;

-- Service role policy for Edge Functions
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
    AND tablename = 'weekly_stories'
    AND policyname = 'Service role has full access'
  ) THEN
    CREATE POLICY "Service role has full access" ON weekly_stories
      FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');
  END IF;
END $$;

-- Performance index for efficient user/week lookups
CREATE INDEX IF NOT EXISTS idx_weekly_stories_user_week
  ON weekly_stories(user_id, week_start DESC);

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_weekly_stories_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_weekly_stories_updated_at ON weekly_stories;
CREATE TRIGGER trigger_weekly_stories_updated_at
  BEFORE UPDATE ON weekly_stories
  FOR EACH ROW
  EXECUTE FUNCTION update_weekly_stories_updated_at();

-- Add story post type to circle_posts if it exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'circle_post_kind'
  ) THEN
    -- Check if 'story' value exists
    IF NOT EXISTS (
      SELECT 1 FROM pg_enum
      WHERE enumlabel = 'story'
      AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'circle_post_kind')
    ) THEN
      ALTER TYPE circle_post_kind ADD VALUE IF NOT EXISTS 'story';
    END IF;
  END IF;
END $$;

-- Add story_image_url to circle_posts if not exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'circle_posts'
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
      AND table_name = 'circle_posts'
      AND column_name = 'story_image_url'
    ) THEN
      ALTER TABLE circle_posts ADD COLUMN story_image_url TEXT;
      COMMENT ON COLUMN circle_posts.story_image_url IS 'URL to story card image in Supabase Storage (for story posts)';
    END IF;
  END IF;
END $$;
