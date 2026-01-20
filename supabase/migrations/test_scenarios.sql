-- Test Scenarios for Email System P0 Fixes
-- Execute these to verify the fixes work correctly

-- ============================================================================
-- Test 1: Pagination at Scale (O(n²) → O(n))
-- ============================================================================
-- This is tested at the application level (TypeScript), not SQL
-- Expected: For 10K users, should process in 10 batches of 1K users each
-- Verification: Check logs for "Processing batch: 1-1000", "1001-2000", etc.
-- Pass: 10 batch iterations
-- Fail: 10K individual iterations

-- ============================================================================
-- Test 2: TOCTOU Race - Atomic Rate Limit Check
-- ============================================================================
-- Setup: Create test user and simulate concurrent rate limit checks

DO $$
DECLARE
  v_test_user_id UUID := '00000000-0000-0000-0000-000000000001';
  v_email_log JSONB;
  v_result1 JSONB;
  v_result2 JSONB;
  v_count INT;
BEGIN
  -- Clean up previous test data
  DELETE FROM email_logs WHERE user_id = v_test_user_id;

  -- Insert 9 sent emails (1 below rate limit of 10)
  FOR i IN 1..9 LOOP
    INSERT INTO email_logs (user_id, email_type, status, sent_at, created_at)
    VALUES (
      v_test_user_id,
      'test_email',
      'sent',
      NOW() - INTERVAL '1 day',
      NOW()
    );
  END LOOP;

  -- Build email log JSONB payload
  v_email_log := jsonb_build_object(
    'user_id', v_test_user_id::TEXT,
    'email_type', 'test_concurrent',
    'template_version', 'v1',
    'message_id', 'test-msg-1',
    'status', 'sent',
    'sent_at', NOW()::TEXT,
    'created_at', NOW()::TEXT
  );

  -- Simulate Worker 1 checking rate limit
  SELECT insert_email_log_with_rate_limit_check(v_test_user_id, v_email_log)
  INTO v_result1;

  -- Simulate Worker 2 checking rate limit immediately after
  v_email_log := jsonb_set(v_email_log, '{message_id}', '"test-msg-2"');
  SELECT insert_email_log_with_rate_limit_check(v_test_user_id, v_email_log)
  INTO v_result2;

  -- Count total sent emails
  SELECT COUNT(*) INTO v_count
  FROM email_logs
  WHERE user_id = v_test_user_id AND status = 'sent';

  -- Results
  RAISE NOTICE 'Worker 1 result: %', v_result1;
  RAISE NOTICE 'Worker 2 result: %', v_result2;
  RAISE NOTICE 'Total sent emails: % (expected: 11, max allowed: 10)', v_count;

  -- EXPECTED BEHAVIOR:
  -- Both workers should pass because they're sequential (not truly concurrent)
  -- Total count should be 11 (9 + 2)
  -- withinLimit should be true for first worker (9 < 10), true for second (10 < 10 is false but it already inserted)

  -- ACTUAL ISSUE: This RPC doesn't prevent the 11th email from being sent!
  -- The function checks BEFORE inserting, so if count=10, withinLimit=false but email is STILL inserted

  IF v_count > 10 THEN
    RAISE NOTICE '❌ FAIL: Rate limit exceeded! % emails sent (max 10)', v_count;
  ELSE
    RAISE NOTICE '✓ PASS: Rate limit enforced, % emails sent', v_count;
  END IF;

  -- Clean up
  DELETE FROM email_logs WHERE user_id = v_test_user_id;
END $$;

-- ============================================================================
-- Test 3: Timing-Safe Validation
-- ============================================================================
-- This is tested at the application level (TypeScript), not SQL
-- The timingSafeEqual function should take the same time regardless of where the mismatch is
-- Manual verification: Use a timing attack tool to measure response times for different secret values

-- ============================================================================
-- Test 4: Error Sanitization
-- ============================================================================
-- This is tested at the application level (TypeScript), not SQL
-- Verification: Trigger an error with UUID/email in it, check logs for [REDACTED-*]

-- ============================================================================
-- CRITICAL BUG FOUND: TOCTOU Race Fix is Broken
-- ============================================================================
-- Problem: The RPC function checks rate limit BEFORE inserting, but always inserts
-- Line 24 in migration: v_within_limit := v_count < 10;
-- Lines 27-43: INSERT happens regardless of v_within_limit value
--
-- The function returns withinLimit=false, but still inserts the email log!
-- Application code must check the returned `withinLimit` field and NOT send the email if false
--
-- Let's verify if the application actually checks this field...
-- Searching for `withinLimit` usage in send-email function...
