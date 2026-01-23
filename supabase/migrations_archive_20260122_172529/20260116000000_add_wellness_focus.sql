-- Migration: Add wellness focus and onboarding tracking to profiles
-- Purpose: Support personalized onboarding flow with wellness quiz

-- Add wellness focus column (user's primary wellness goal)
-- NOT NULL with default ensures all users have a valid value
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS wellness_focus TEXT
  NOT NULL
  DEFAULT 'general'
  CHECK (wellness_focus IN ('anxiety', 'stress', 'loneliness', 'productivity', 'general'));

-- Add onboarding completion timestamp
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS onboarding_completed_at TIMESTAMPTZ;

-- Add index on wellness_focus for analytics and filtering queries
CREATE INDEX IF NOT EXISTS idx_profiles_wellness_focus ON profiles(wellness_focus);

-- Add index on onboarding_completed_at for filtering users by onboarding status
CREATE INDEX IF NOT EXISTS idx_profiles_onboarding_completed_at ON profiles(onboarding_completed_at)
  WHERE onboarding_completed_at IS NOT NULL;

-- Gentle migration: Mark existing users as having completed onboarding
-- This prevents existing users from seeing the new onboarding flow
-- Note: New users created during migration will correctly have NULL (need onboarding)
UPDATE profiles
SET onboarding_completed_at = created_at
WHERE onboarding_completed_at IS NULL
  AND created_at < NOW() - INTERVAL '1 minute';  -- Only backfill users created before migration

-- Add comments for documentation
COMMENT ON COLUMN profiles.wellness_focus IS 'Primary wellness goal selected during onboarding: anxiety, stress, loneliness, productivity, or general';
COMMENT ON COLUMN profiles.onboarding_completed_at IS 'Timestamp when user completed the onboarding flow. NULL means onboarding not yet completed.';
