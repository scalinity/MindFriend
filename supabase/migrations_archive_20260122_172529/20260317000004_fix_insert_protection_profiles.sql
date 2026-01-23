-- Security Hardening: Add INSERT Protection for Profiles (Audit Issue #4)
-- Severity: P1 - Revenue Bypass / Premium Tier Bypass
--
-- Problem: The UPDATE trigger protects against quota/tier modifications, but INSERT operations
--          have NO protection. A malicious user could INSERT a profile row with
--          subscription_tier='premium', daily_ai_quota='999' directly, bypassing payment verification.
--
-- Solution: Create BEFORE INSERT trigger to enforce same column restrictions as UPDATE
--           Both INSERT and UPDATE must set default values for protected columns

CREATE OR REPLACE FUNCTION enforce_profiles_insert_defaults()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only apply restrictions to authenticated users creating their own profiles
  -- Service role and admin operations bypass this
  IF (SELECT auth.role() = 'authenticated') THEN
    -- Force default values for revenue-critical columns
    -- These can only be set by Edge Functions/service role after purchase verification
    NEW.subscription_tier := 'free';
    NEW.daily_ai_quota := 10;        -- Free tier default
    NEW.daily_ai_used := 0;
    NEW.quota_reset_at := NOW();
    NEW.premium_badge := FALSE;
  END IF;

  RETURN NEW;
END;
$$;

-- Create BEFORE INSERT trigger on profiles table
DROP TRIGGER IF EXISTS tr_profiles_insert_defaults ON public.profiles;

CREATE TRIGGER tr_profiles_insert_defaults
BEFORE INSERT ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION enforce_profiles_insert_defaults();

-- Document the protection
COMMENT ON FUNCTION enforce_profiles_insert_defaults() IS
  'Enforce INSERT defaults: users cannot set subscription_tier, quota, premium_badge when creating profiles. Service role can override.';

COMMENT ON TRIGGER tr_profiles_insert_defaults ON profiles IS
  'Ensures authenticated users cannot create premium profiles without payment verification (audit issue #4)';
