-- Free Tier Quota Reduction: 20 -> 5 messages/day
-- This migration reduces the daily AI chat quota for free users to drive conversions.
-- No grandfather clause - applies to ALL existing free users.

-- Update default for new users
ALTER TABLE profiles ALTER COLUMN daily_ai_quota SET DEFAULT 5;

-- Update the trigger function to enforce 5 for free tier on insert
-- IMPORTANT: Preserves all original defaults, only changes quota from 10 to 5
CREATE OR REPLACE FUNCTION enforce_profiles_insert_defaults()
RETURNS TRIGGER AS $$
BEGIN
  -- Only apply restrictions to authenticated users creating their own profiles
  -- Service role and admin operations bypass this
  IF (SELECT COALESCE(auth.role(), 'unknown') = 'authenticated') THEN
    -- Force default values for revenue-critical columns
    -- These can only be set by Edge Functions/service role after purchase verification
    NEW.subscription_tier := 'free';
    NEW.daily_ai_quota := 5;  -- Updated from 10 to 5 for revenue optimization
    NEW.daily_ai_used := 0;
    NEW.quota_reset_at := NOW();
    NEW.premium_badge := FALSE;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

-- Apply to ALL existing free users (no grandfather clause)
-- This is intentional to drive conversions
UPDATE profiles
SET daily_ai_quota = 5
WHERE subscription_tier = 'free'
  AND daily_ai_quota > 5;

-- Also update users with NULL subscription_tier (default to free)
UPDATE profiles
SET daily_ai_quota = 5
WHERE subscription_tier IS NULL
  AND daily_ai_quota > 5;
