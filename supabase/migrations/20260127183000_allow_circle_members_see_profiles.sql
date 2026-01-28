-- Allow circle members to see profiles of other members in their circles
-- This is needed for the circle detail view to show member names

CREATE POLICY "Circle members can view fellow members profiles"
ON profiles
FOR SELECT
USING (
    -- User can see their own profile
    auth.uid() = id
    OR
    -- User can see profiles of members in circles they belong to
    EXISTS (
        SELECT 1 FROM circle_members cm1
        JOIN circle_members cm2 ON cm1.circle_id = cm2.circle_id
        WHERE cm1.user_id = auth.uid()
          AND cm2.user_id = profiles.id
    )
);

-- Drop the old restrictive policies (they're now covered by the new policy)
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;
DROP POLICY IF EXISTS "profiles_users_read_own" ON profiles;
