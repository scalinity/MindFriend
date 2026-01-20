-- Add missing UPDATE policy for distortion_encounters table
-- This allows the service role to update encounter records (e.g., marking reframe_accepted)

DO $$
BEGIN
  -- Drop policy if it exists (for idempotency)
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
    AND tablename = 'distortion_encounters'
    AND policyname = 'Service role can update encounters'
  ) THEN
    DROP POLICY "Service role can update encounters" ON distortion_encounters;
  END IF;
END $$;

-- Allow service role to update distortion encounters
-- This is needed when the Edge Function updates the encounter after user action
CREATE POLICY "Service role can update encounters"
  ON distortion_encounters
  FOR UPDATE
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Also add policy for users to update their own encounters (for future client-side updates)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
    AND tablename = 'distortion_encounters'
    AND policyname = 'Users can update own encounters'
  ) THEN
    DROP POLICY "Users can update own encounters" ON distortion_encounters;
  END IF;
END $$;

CREATE POLICY "Users can update own encounters"
  ON distortion_encounters
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
