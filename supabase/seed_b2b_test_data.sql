-- B2B Test Data Seeding Script
-- Creates test organizations, admins, and invite codes for Phase 1 tests

-- ============================================================================
-- 1. Create test user (if not exists)
-- ============================================================================
-- Note: Supabase Auth users must be created via the API, not SQL
-- This will be handled by the test setup

-- ============================================================================
-- 2. Create test organizations
-- ============================================================================

INSERT INTO organizations (id, name, plan, seat_count, max_seats, billing_email, seats_used, status)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'Test Organization 1', 'business', 10, 100, 'billing@test1.com', 0, 'active'),
  ('00000000-0000-0000-0000-000000000002', 'Test Organization 2', 'business', 5, 100, 'billing@test2.com', 0, 'active'),
  ('00000000-0000-0000-0000-000000000003', 'Full Organization', 'business', 5, 100, 'billing@fullorg.com', 5, 'active'),
  ('00000000-0000-0000-0000-000000000004', 'Seat Count Test Org', 'business', 10, 100, 'billing@seattest.com', 2, 'active')
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  seat_count = EXCLUDED.seat_count,
  seats_used = EXCLUDED.seats_used;

-- ============================================================================
-- 3. Create test admin
-- ============================================================================
-- First, get or create a test admin user ID

DO $$
DECLARE
  v_admin_id UUID;
BEGIN
  -- Try to get existing test user
  SELECT id INTO v_admin_id FROM auth.users WHERE email = 'test@example.com' LIMIT 1;

  -- If no user exists, use a placeholder (admin creation will be skipped)
  IF v_admin_id IS NULL THEN
    v_admin_id := '00000000-0000-0000-0000-000000000099';
    RAISE NOTICE 'Test user not found, using placeholder admin ID';
  END IF;

  -- Create admins (will fail silently if user doesn't exist)
  BEGIN
    INSERT INTO organization_admins (id, organization_id, user_id, role)
    VALUES
      ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', v_admin_id, 'admin'),
      ('00000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-000000000002', v_admin_id, 'admin'),
      ('00000000-0000-0000-0000-000000000013', '00000000-0000-0000-0000-000000000003', v_admin_id, 'admin'),
      ('00000000-0000-0000-0000-000000000014', '00000000-0000-0000-0000-000000000004', v_admin_id, 'admin')
    ON CONFLICT (organization_id, user_id) DO NOTHING;
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'Skipping admin creation - test user not found';
  END;
END $$;

-- ============================================================================
-- 4. Create test invite codes
-- ============================================================================

DO $$
BEGIN
  -- Create invite codes (will use admin IDs that may or may not exist)
  BEGIN
    INSERT INTO organization_invites (invite_code, organization_id, max_uses, uses_count, expires_at, is_active, created_by_admin_id)
    VALUES
      -- Valid code for basic validation test
      ('VALIDCODE123', '00000000-0000-0000-0000-000000000001', 100, 0, NOW() + INTERVAL '30 days', true, '00000000-0000-0000-0000-000000000011'),

      -- Expired code
      ('EXPIREDCODE', '00000000-0000-0000-0000-000000000001', 100, 0, NOW() - INTERVAL '1 day', true, '00000000-0000-0000-0000-000000000011'),

      -- Max uses exceeded
      ('MAXEDOUTCODE', '00000000-0000-0000-0000-000000000001', 5, 5, NOW() + INTERVAL '30 days', true, '00000000-0000-0000-0000-000000000011'),

      -- Counter test code
      ('COUNTERCODE', '00000000-0000-0000-0000-000000000001', 100, 10, NOW() + INTERVAL '30 days', true, '00000000-0000-0000-0000-000000000011'),

      -- Deactivated code
      ('DEACTIVATED', '00000000-0000-0000-0000-000000000001', 100, 0, NOW() + INTERVAL '30 days', false, '00000000-0000-0000-0000-000000000011'),

      -- Join organization test codes
      ('JOINTEST123', '00000000-0000-0000-0000-000000000002', 100, 0, NOW() + INTERVAL '30 days', true, '00000000-0000-0000-0000-000000000012'),
      ('PREMIUMTEST', '00000000-0000-0000-0000-000000000002', 100, 0, NOW() + INTERVAL '30 days', true, '00000000-0000-0000-0000-000000000012'),
      ('DUPLICATETEST', '00000000-0000-0000-0000-000000000002', 100, 0, NOW() + INTERVAL '30 days', true, '00000000-0000-0000-0000-000000000012'),
      ('LINKTEST123', '00000000-0000-0000-0000-000000000002', 100, 0, NOW() + INTERVAL '30 days', true, '00000000-0000-0000-0000-000000000012'),
      ('AUDITLOGTEST', '00000000-0000-0000-0000-000000000002', 100, 0, NOW() + INTERVAL '30 days', true, '00000000-0000-0000-0000-000000000012'),
      ('SEATCOUNTTEST', '00000000-0000-0000-0000-000000000004', 100, 0, NOW() + INTERVAL '30 days', true, '00000000-0000-0000-0000-000000000014'),

      -- Full organization (seat limit reached)
      ('FULLORGCODE', '00000000-0000-0000-0000-000000000003', 100, 0, NOW() + INTERVAL '30 days', true, '00000000-0000-0000-0000-000000000013')
    ON CONFLICT (invite_code) DO UPDATE SET
      uses_count = EXCLUDED.uses_count,
      expires_at = EXCLUDED.expires_at,
      is_active = EXCLUDED.is_active;
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'Skipping invite code creation - admin records not found';
  END;
END $$;

-- ============================================================================
-- COMPLETION
-- ============================================================================

SELECT 'Test data seeding complete!' AS message;
