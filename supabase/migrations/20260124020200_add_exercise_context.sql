-- Migration: Add exercise personalization columns to generated_content
-- Purpose: Support context-aware generation, favorites, and user ratings
-- Author: dev-pipeline
-- Date: 2026-01-24

-- Add new columns to existing generated_content table
ALTER TABLE generated_content
  ADD COLUMN IF NOT EXISTS generation_context JSONB DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS is_favorite BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS user_rating INTEGER CHECK (user_rating BETWEEN 1 AND 5);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_generated_content_favorites
  ON generated_content(user_id, is_favorite)
  WHERE is_favorite = TRUE;

CREATE INDEX IF NOT EXISTS idx_generated_content_context
  ON generated_content USING GIN (generation_context);

CREATE INDEX IF NOT EXISTS idx_generated_content_rating
  ON generated_content(user_id, user_rating)
  WHERE user_rating IS NOT NULL;

-- Add comments for documentation
COMMENT ON COLUMN generated_content.generation_context IS 'JSONB context captured during generation: {mood, recentExercises, timeOfDay, preferences}';
COMMENT ON COLUMN generated_content.is_favorite IS 'User-marked favorite for quick access in saved exercises library';
COMMENT ON COLUMN generated_content.user_rating IS 'User rating (1-5 stars) after completing exercise, used for personalization feedback loop';
