-- Migration: is_handle_available RPC
-- Issue #009: Handle Availability Check
-- SECURITY DEFINER allows checking handle availability without exposing profile data

CREATE OR REPLACE FUNCTION is_handle_available(p_handle TEXT, p_exclude_user_id UUID DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  -- Normalize handle to lowercase
  p_handle := LOWER(TRIM(p_handle));

  -- Validate handle format (letters, numbers, underscores, 3-30 chars)
  IF NOT (p_handle ~ '^[a-z0-9_]{3,30}$') THEN
    -- Invalid format returns false (not available)
    RETURN FALSE;
  END IF;

  -- Check if handle exists (excluding specified user if provided)
  IF p_exclude_user_id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_count
    FROM profiles
    WHERE handle = p_handle AND id != p_exclude_user_id;
  ELSE
    SELECT COUNT(*) INTO v_count
    FROM profiles
    WHERE handle = p_handle;
  END IF;

  -- Return true if no matches (handle is available)
  RETURN v_count = 0;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION is_handle_available(TEXT, UUID) TO authenticated;
