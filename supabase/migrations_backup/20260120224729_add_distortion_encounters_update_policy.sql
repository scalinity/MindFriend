-- Add missing UPDATE policy for distortion_encounters table
-- This allows the service role to update encounter records (e.g., marking reframe_accepted)
-- Note: Table is created in a later migration (20260701000004_cognitive_coach_schema.sql)

DO $$
BEGIN
  -- Only create policies if the table exists
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public'
    AND table_name = 'distortion_encounters'
  ) THEN
    -- Drop policy if it exists (for idempotency)
    IF EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public'
      AND tablename = 'distortion_encounters'
      AND policyname = 'Service role can update encounters'
    ) THEN
      DROP POLICY "Service role can update encounters" ON distortion_encounters;
    END IF;

    -- Allow service role to update distortion encounters
    CREATE POLICY "Service role can update encounters"
      ON distortion_encounters
      FOR UPDATE
      TO service_role
      USING (true)
      WITH CHECK (true);

    -- Drop user policy if it exists
    IF EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public'
      AND tablename = 'distortion_encounters'
      AND policyname = 'Users can update own encounters'
    ) THEN
      DROP POLICY "Users can update own encounters" ON distortion_encounters;
    END IF;

    -- Allow users to update their own encounters
    CREATE POLICY "Users can update own encounters"
      ON distortion_encounters
      FOR UPDATE
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;
