-- Migration: Fix weekly_stories RLS and add missing DELETE policy
-- Ensure RLS is enabled and all CRUD policies exist
-- Timestamp: 2026-01-23 08:00:00

-- ================================================================
-- 1. Ensure RLS is enabled on weekly_stories
-- ================================================================

ALTER TABLE weekly_stories ENABLE ROW LEVEL SECURITY;

-- ================================================================
-- 2. Verify existing policies and add missing DELETE policy
-- ================================================================

-- Users can delete their own stories
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'weekly_stories'
    AND policyname = 'Users can delete own stories'
  ) THEN
    CREATE POLICY "Users can delete own stories"
      ON weekly_stories FOR DELETE
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- ================================================================
-- 3. Verification
-- ================================================================

-- Verify RLS is enabled
DO $$
DECLARE
  rls_enabled BOOLEAN;
BEGIN
  SELECT relrowsecurity INTO rls_enabled
  FROM pg_class
  WHERE relname = 'weekly_stories';

  IF NOT rls_enabled THEN
    RAISE EXCEPTION 'Migration failed: RLS not enabled on weekly_stories';
  END IF;

  -- Verify all required policies exist
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'weekly_stories' AND policyname = 'Users can read own stories'
  ) THEN
    RAISE EXCEPTION 'Migration failed: SELECT policy missing on weekly_stories';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'weekly_stories' AND policyname = 'Users can insert own stories'
  ) THEN
    RAISE EXCEPTION 'Migration failed: INSERT policy missing on weekly_stories';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'weekly_stories' AND policyname = 'Users can update own story ratings'
  ) THEN
    RAISE EXCEPTION 'Migration failed: UPDATE policy missing on weekly_stories';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'weekly_stories' AND policyname = 'Users can delete own stories'
  ) THEN
    RAISE EXCEPTION 'Migration failed: DELETE policy missing on weekly_stories';
  END IF;

  RAISE NOTICE 'Migration successful: RLS enabled, all CRUD policies verified on weekly_stories';
END $$;
