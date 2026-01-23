-- Force fix for quota function - drop all versions and recreate
-- This ensures we completely replace the old function

-- Drop ALL versions of the function (regardless of signature)
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT oid::regprocedure::text as proc_sig
        FROM pg_proc
        WHERE proname = 'check_and_increment_ai_quota'
    ) LOOP
        EXECUTE 'DROP FUNCTION ' || r.proc_sig;
        RAISE NOTICE 'Dropped function: %', r.proc_sig;
    END LOOP;
END $$;

-- Recreate the function with NULL check protection
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
    RAISE NOTICE 'Profile missing for user %, creating...', p_user_id;
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

    RAISE NOTICE 'Profile created successfully for user %', p_user_id;
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

COMMENT ON FUNCTION check_and_increment_ai_quota IS 'Atomically checks and increments AI quota. Auto-creates missing profiles. (Force-fixed version)';

-- Verify the function was created
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'check_and_increment_ai_quota') THEN
        RAISE NOTICE 'SUCCESS: check_and_increment_ai_quota function exists';
    ELSE
        RAISE EXCEPTION 'FAILED: check_and_increment_ai_quota function not found';
    END IF;
END $$;
