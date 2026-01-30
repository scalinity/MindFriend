-- Allow users to update their own memory fragments
-- Previously there was a "Deny direct user updates" policy that blocked all updates

-- Drop the deny policy
DROP POLICY IF EXISTS "Deny direct user updates" ON "public"."memory_fragments";

-- Create policy allowing users to update their own memories
CREATE POLICY "Users can update own memories" ON "public"."memory_fragments"
  FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
