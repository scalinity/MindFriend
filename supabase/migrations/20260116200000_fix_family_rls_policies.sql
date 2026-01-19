-- Spec: Audit Issue Fix - Restrict overly permissive INSERT policies
-- Issue: family_activity_summaries and family_alerts had INSERT policies with `WITH CHECK (true)`,
-- allowing any authenticated user to insert data that should only be created by the system
-- Fix: Remove overly permissive INSERT policies (service role bypasses RLS anyway)
-- and add proper membership-based access controls

-- =============================================================================
-- MARK: - family_activity_summaries Policy Fixes
-- =============================================================================

-- Remove overly permissive INSERT policy
-- Service role doesn't need this - it bypasses RLS anyway
DO $$ BEGIN
  DROP POLICY IF EXISTS "System can insert summaries" ON family_activity_summaries;
EXCEPTION WHEN UNDEFINED_OBJECT THEN
  NULL;
END $$;

-- Add proper INSERT policy: only family members can insert (though in practice,
-- this should only be used by service role/cron functions)
-- Members are identified by being in family_members table with active status
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'family_activity_summaries'
      AND policyname = 'Family members can insert summaries'
  ) THEN
    CREATE POLICY "Family members can insert summaries"
      ON family_activity_summaries FOR INSERT
      WITH CHECK (
        family_id IN (
          SELECT DISTINCT family_id
          FROM family_members
          WHERE user_id = auth.uid()
            AND status = 'active'
        )
      );
  END IF;
END $$;

-- =============================================================================
-- MARK: - family_alerts Policy Fixes
-- =============================================================================

-- Remove overly permissive INSERT policy
-- This allowed any authenticated user to create alerts
DO $$ BEGIN
  DROP POLICY IF EXISTS "System can insert alerts" ON family_alerts;
EXCEPTION WHEN UNDEFINED_OBJECT THEN
  NULL;
END $$;

-- Add proper INSERT policy: only the parent receiving the alert (for_parent_id)
-- and service role can insert alerts for that parent
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'family_alerts'
      AND policyname = 'Parents can receive alerts for themselves'
  ) THEN
    CREATE POLICY "Parents can receive alerts for themselves"
      ON family_alerts FOR INSERT
      WITH CHECK (
        -- Only allow inserts where the alert is for the current user
        -- (In practice, service role bypasses RLS, so this is for human users)
        for_parent_id = auth.uid()
      );
  END IF;
END $$;

-- =============================================================================
-- MARK: - Audit Log
-- =============================================================================

-- Log this security fix
DO $$ BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'audit_log') THEN
    INSERT INTO audit_log (table_name, operation, description, change_date)
    VALUES (
      'family_activity_summaries',
      'POLICY_FIXED',
      'Removed overly permissive INSERT policy (WITH CHECK true)',
      NOW()
    );

    INSERT INTO audit_log (table_name, operation, description, change_date)
    VALUES (
      'family_alerts',
      'POLICY_FIXED',
      'Removed overly permissive INSERT policy (WITH CHECK true)',
      NOW()
    );
  END IF;
EXCEPTION WHEN UNDEFINED_TABLE THEN
  NULL;
END $$;
