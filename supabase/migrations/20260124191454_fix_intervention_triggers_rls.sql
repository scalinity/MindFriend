-- Fix RLS Policies for intervention_triggers
-- Issue: Users cannot manage their own triggers (INSERT/UPDATE/DELETE policies missing)
-- This breaks calendar trigger configuration from iOS app
-- Created: 2026-01-24

-- Add missing INSERT policy for users
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'intervention_triggers'
    AND policyname = 'Users can insert own triggers'
  ) THEN
    CREATE POLICY "Users can insert own triggers"
        ON intervention_triggers FOR INSERT
        WITH CHECK (auth.uid() = user_id);
    RAISE NOTICE 'Added INSERT policy for intervention_triggers';
  END IF;
END $$;

-- Add missing UPDATE policy for users
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'intervention_triggers'
    AND policyname = 'Users can update own triggers'
  ) THEN
    CREATE POLICY "Users can update own triggers"
        ON intervention_triggers FOR UPDATE
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id);
    RAISE NOTICE 'Added UPDATE policy for intervention_triggers';
  END IF;
END $$;

-- Add missing DELETE policy for users
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'intervention_triggers'
    AND policyname = 'Users can delete own triggers'
  ) THEN
    CREATE POLICY "Users can delete own triggers"
        ON intervention_triggers FOR DELETE
        USING (auth.uid() = user_id);
    RAISE NOTICE 'Added DELETE policy for intervention_triggers';
  END IF;
END $$;

-- Log successful fix
DO $$
BEGIN
  RAISE NOTICE 'RLS policies for intervention_triggers fixed - users can now manage their own triggers';
END $$;
