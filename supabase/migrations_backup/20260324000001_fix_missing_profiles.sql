-- Fix Missing Profiles - Systemic Solution
-- Prevents chat failures when user profiles don't exist
-- Addresses root cause: handle_new_user() trigger may not always fire or profiles may be missing

-- 1. Helper function to create missing profile with defaults
CREATE OR REPLACE FUNCTION ensure_profile_exists(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_email TEXT;
  v_user_metadata JSONB;
  random_handle TEXT;
BEGIN
  -- Check if profile already exists
  IF EXISTS (SELECT 1 FROM profiles WHERE id = p_user_id) THEN
    RETURN;
  END IF;

  -- Get user info from auth.users
  SELECT email, raw_user_meta_data
  INTO v_user_email, v_user_metadata
  FROM auth.users
  WHERE id = p_user_id;

  -- If user doesn't exist in auth.users, we can't create profile
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User % does not exist in auth.users', p_user_id;
  END IF;

  -- Generate random handle
  random_handle := 'user_' || substr(md5(random()::text), 1, 8);

  -- Create profile with defaults
  INSERT INTO profiles (
    id,
    handle,
    display_name,
    email,
    daily_ai_used,
    daily_ai_quota,
    quota_reset_at
  )
  VALUES (
    p_user_id,
    random_handle,
    COALESCE(v_user_metadata->>'full_name', 'MindFriend User'),
    v_user_email,
    0,  -- Start with 0 quota used
    10, -- Default free tier quota
    NOW() -- Reset time is now
  );

  -- Create settings if missing
  INSERT INTO user_settings (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  -- Create stats if missing
  INSERT INTO user_stats (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  -- Log this for monitoring
  RAISE NOTICE 'Created missing profile for user %', p_user_id;
END;
$$;

COMMENT ON FUNCTION ensure_profile_exists IS 'Creates profile, settings, and stats if missing - defensive fallback';

-- 2. Update check_and_increment_ai_quota to handle missing profiles
-- Drop first to avoid "cannot change return type" error
DROP FUNCTION IF EXISTS check_and_increment_ai_quota(UUID, BOOLEAN);

CREATE FUNCTION check_and_increment_ai_quota(
  p_user_id UUID,
  p_is_premium BOOLEAN DEFAULT FALSE
)
RETURNS TABLE(
  allowed BOOLEAN,
  quota_used INT,
  quota_limit INT,
  was_reset BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_quota_used INT;
  v_quota_limit INT;
  v_quota_reset_at TIMESTAMPTZ;
  v_was_reset BOOLEAN := FALSE;
BEGIN
  -- Lock the row to prevent concurrent updates
  SELECT daily_ai_used, daily_ai_quota, quota_reset_at
  INTO v_quota_used, v_quota_limit, v_quota_reset_at
  FROM profiles
  WHERE id = p_user_id
  FOR UPDATE;

  -- CRITICAL FIX: Handle missing profile
  IF v_quota_used IS NULL OR v_quota_limit IS NULL OR v_quota_reset_at IS NULL THEN
    -- Profile doesn't exist or is incomplete - create it
    PERFORM ensure_profile_exists(p_user_id);

    -- Re-fetch the newly created profile
    SELECT daily_ai_used, daily_ai_quota, quota_reset_at
    INTO v_quota_used, v_quota_limit, v_quota_reset_at
    FROM profiles
    WHERE id = p_user_id
    FOR UPDATE;

    -- If still NULL, something is very wrong
    IF v_quota_used IS NULL THEN
      RAISE EXCEPTION 'Failed to create profile for user %', p_user_id;
    END IF;
  END IF;

  -- Check if quota needs reset (new day)
  IF DATE(v_quota_reset_at) < CURRENT_DATE THEN
    v_quota_used := 0;
    v_was_reset := TRUE;
    UPDATE profiles
    SET daily_ai_used = 0, quota_reset_at = NOW()
    WHERE id = p_user_id;
  END IF;

  -- Premium users always allowed
  IF p_is_premium THEN
    -- Increment but don't check limit
    UPDATE profiles
    SET daily_ai_used = v_quota_used + 1
    WHERE id = p_user_id;

    RETURN QUERY SELECT TRUE, v_quota_used + 1, -1, v_was_reset;
    RETURN;
  END IF;

  -- Check quota for free users
  IF v_quota_used >= v_quota_limit THEN
    -- Quota exceeded, don't increment
    RETURN QUERY SELECT FALSE, v_quota_used, v_quota_limit, v_was_reset;
    RETURN;
  END IF;

  -- Atomically increment quota
  UPDATE profiles
  SET daily_ai_used = v_quota_used + 1
  WHERE id = p_user_id;

  RETURN QUERY SELECT TRUE, v_quota_used + 1, v_quota_limit, v_was_reset;
END;
$$;

COMMENT ON FUNCTION check_and_increment_ai_quota IS 'Atomically checks and increments AI quota. Auto-creates missing profiles.';

-- 3. Verify and re-enable the trigger (in case it was disabled)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 4. Backfill any existing users who are missing profiles
DO $$
DECLARE
  missing_user RECORD;
  fixed_count INT := 0;
BEGIN
  -- Find users in auth.users who don't have profiles
  FOR missing_user IN
    SELECT au.id, au.email, au.raw_user_meta_data
    FROM auth.users au
    LEFT JOIN profiles p ON au.id = p.id
    WHERE p.id IS NULL
  LOOP
    -- Create missing profile
    PERFORM ensure_profile_exists(missing_user.id);
    fixed_count := fixed_count + 1;
  END LOOP;

  IF fixed_count > 0 THEN
    RAISE NOTICE 'Backfilled % missing profiles', fixed_count;
  ELSE
    RAISE NOTICE 'No missing profiles found - all users have profiles';
  END IF;
END $$;
