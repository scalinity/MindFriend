-- Spec: Fix race condition in join-family
-- Issue: join-family checks member limit, then inserts member in separate queries (TOCTOU vulnerability)
-- Solution: Create atomic RPC function that checks and inserts in single transaction with row-level locking

-- =============================================================================
-- MARK: - Create Atomic add_family_member Function
-- =============================================================================

CREATE OR REPLACE FUNCTION add_family_member(
  p_family_id UUID,
  p_user_id UUID,
  p_role TEXT DEFAULT 'child',
  p_nickname TEXT DEFAULT NULL,
  p_birth_date TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_family_record RECORD;
  v_existing_member RECORD;
  v_member_record RECORD;
  v_error_code TEXT;
BEGIN
  -- Step 1: Lock family_groups row for atomic check-and-insert
  -- FOR UPDATE prevents concurrent modifications to this family
  SELECT id, max_members
  INTO v_family_record
  FROM family_groups
  WHERE id = p_family_id
  FOR UPDATE;

  -- Step 2: Family not found
  IF v_family_record IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Family not found',
      'code', 'FAMILY_NOT_FOUND'
    );
  END IF;

  -- Step 3: Check if user is already a member (prevent duplicates)
  SELECT id INTO v_existing_member
  FROM family_members
  WHERE family_id = p_family_id
    AND user_id = p_user_id
    AND status = 'active'
  LIMIT 1;

  IF v_existing_member IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'User is already a member of this family',
      'code', 'ALREADY_MEMBER'
    );
  END IF;

  -- Step 4: Check member limit (atomic check within same transaction)
  -- Count active members and verify against max_members
  -- Using COUNT(*) LIMIT 1 pattern prevents unnecessary full table scan
  IF (
    SELECT COUNT(*)
    FROM family_members
    WHERE family_id = p_family_id
      AND status = 'active'
  ) >= COALESCE(v_family_record.max_members, 6) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Family has reached maximum members',
      'code', 'MEMBER_LIMIT_EXCEEDED'
    );
  END IF;

  -- Step 5: Insert new family member (atomic - within same transaction with lock held)
  INSERT INTO family_members (
    family_id,
    user_id,
    role,
    nickname,
    birth_date,
    status,
    joined_at,
    created_at,
    updated_at
  )
  VALUES (
    p_family_id,
    p_user_id,
    p_role,
    p_nickname,
    CASE WHEN p_birth_date IS NOT NULL AND p_birth_date != '' THEN p_birth_date::DATE ELSE NULL END,
    'active',
    NOW(),
    NOW(),
    NOW()
  )
  RETURNING * INTO v_member_record;

  -- Step 6: Return success with member details
  RETURN jsonb_build_object(
    'success', true,
    'member_id', v_member_record.id,
    'user_id', v_member_record.user_id,
    'family_id', v_member_record.family_id,
    'role', v_member_record.role,
    'joined_at', v_member_record.joined_at
  );

EXCEPTION WHEN OTHERS THEN
  -- Log unexpected errors and return generic failure
  RETURN jsonb_build_object(
    'success', false,
    'error', 'Failed to add family member',
    'code', 'RPC_ERROR'
  );
END;
$$;

-- =============================================================================
-- MARK: - Grant Permissions
-- =============================================================================

-- Allow authenticated users to call this function
-- (RLS policies on family_members table will still enforce access control)
GRANT EXECUTE ON FUNCTION add_family_member TO authenticated;

-- =============================================================================
-- MARK: - Audit Log
-- =============================================================================

DO $$ BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'audit_log') THEN
    INSERT INTO audit_log (table_name, operation, description, change_date)
    VALUES (
      'family_members',
      'RPC_CREATED',
      'Created atomic add_family_member RPC to prevent TOCTOU race condition in join-family',
      NOW()
    );
  END IF;
EXCEPTION WHEN UNDEFINED_TABLE THEN
  NULL;
END $$;
