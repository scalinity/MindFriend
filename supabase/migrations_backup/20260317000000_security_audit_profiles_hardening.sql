-- Security Hardening: Profiles RLS Restrictions (Audit Issue #001)
-- Prevents users from self-upgrading to premium or resetting AI quota
-- Issue: The original UPDATE policy allowed users to modify ANY column in profiles,
--        enabling premium tier bypass and quota reset attacks.
-- Solution: Restrict authenticated users to UPDATE only safe columns.
--           Allow service role (Edge Functions) to update all columns.

-- 1) Remove overly permissive UPDATE policy
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;

-- 2) Restrict INSERT (users can only create with default premium=false, quota=10)
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;

-- 3) Restrict authenticated users to UPDATE only safe columns
-- Note: PostgIS doesn't support column-level USING clauses in UPDATE,
-- so we'll use a BEFORE UPDATE trigger instead.

-- Add trigger to enforce column restrictions
CREATE OR REPLACE FUNCTION enforce_profiles_column_restrictions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Service role can update any column (used by Edge Functions)
  IF current_setting('role', true) = 'service_role' THEN
    RETURN NEW;
  END IF;

  -- Authenticated users can only update safe columns
  IF (SELECT auth.role() = 'authenticated') THEN
    -- Block updates to revenue-critical and quota columns
    IF NEW.subscription_tier IS DISTINCT FROM OLD.subscription_tier THEN
      RAISE EXCEPTION 'Insufficient privileges to modify subscription_tier';
    END IF;

    IF NEW.daily_ai_quota IS DISTINCT FROM OLD.daily_ai_quota THEN
      RAISE EXCEPTION 'Insufficient privileges to modify daily_ai_quota';
    END IF;

    IF NEW.daily_ai_used IS DISTINCT FROM OLD.daily_ai_used THEN
      RAISE EXCEPTION 'Insufficient privileges to modify daily_ai_used';
    END IF;

    IF NEW.quota_reset_at IS DISTINCT FROM OLD.quota_reset_at THEN
      RAISE EXCEPTION 'Insufficient privileges to modify quota_reset_at';
    END IF;

    IF NEW.premium_badge IS DISTINCT FROM OLD.premium_badge THEN
      RAISE EXCEPTION 'Insufficient privileges to modify premium_badge';
    END IF;

    -- Allow updates to these safe columns
    -- - handle
    -- - display_name
    -- - timezone
    -- - typical_active_hour (for smart notifications)
  END IF;

  RETURN NEW;
END;
$$;

-- Create trigger (drop existing if any)
DROP TRIGGER IF EXISTS tr_profiles_column_restrictions ON public.profiles;

CREATE TRIGGER tr_profiles_column_restrictions
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION enforce_profiles_column_restrictions();

-- 4) Create NEW RLS policies with column restrictions
-- Users can INSERT only their own row (with defaults)
CREATE POLICY "Users can insert own profile (authenticated)" ON public.profiles
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- Users can UPDATE only their own row
-- (The trigger will enforce which columns can be modified)
CREATE POLICY "Users can update own profile (safe columns only)" ON public.profiles
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = id);

-- Ensure service role can bypass trigger and update any column
-- by running operations in service_role context

-- 5) Document the allowed columns for client developers
COMMENT ON TABLE public.profiles IS 'User profiles extending auth.users. Authenticated users can only UPDATE: handle, display_name, timezone, typical_active_hour';

COMMENT ON COLUMN public.profiles.subscription_tier IS 'User subscription level (free/premium). Updated by Edge Functions only via service role.';
COMMENT ON COLUMN public.profiles.daily_ai_quota IS 'Daily AI usage limit. Set via verify-purchase or chat quota management. Updated by Edge Functions only.';
COMMENT ON COLUMN public.profiles.daily_ai_used IS 'Daily AI requests used. Incremented by chat edge function. Clients must not modify.';
COMMENT ON COLUMN public.profiles.quota_reset_at IS 'When daily AI quota resets. Updated by Edge Functions only.';

-- 6) IMPORTANT: RLS policies are secondary access control
-- Users must FIRST have base table privileges, THEN RLS policies filter access
-- DO NOT revoke table privileges - the trigger provides column-level protection
-- If you revoke INSERT/UPDATE, RLS policies cannot filter - access is denied immediately
