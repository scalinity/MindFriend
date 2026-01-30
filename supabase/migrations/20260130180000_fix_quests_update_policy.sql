-- Migration: Fix quests UPDATE RLS policy
-- Issue: UPDATE policy was missing WITH CHECK clause, causing quest completion
-- updates to silently fail. The USING clause allows selecting rows for update,
-- but WITHOUT the WITH CHECK clause, the update was not being persisted.

-- Drop the existing broken policy
DROP POLICY IF EXISTS "Users can update own quests" ON "public"."quests";

-- Create fixed policy with both USING and WITH CHECK clauses
CREATE POLICY "Users can update own quests" ON "public"."quests"
FOR UPDATE
USING (("auth"."uid"() = "user_id"))
WITH CHECK (("auth"."uid"() = "user_id"));

-- Add comment documenting the fix
COMMENT ON POLICY "Users can update own quests" ON "public"."quests" IS
'Allow users to update their own quests. Both USING (for row selection) and
WITH CHECK (for validating new values) are required for UPDATE to persist.';
