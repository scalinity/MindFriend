-- Migration: Fix infinite recursion in circle_members RLS policy
-- Problem: The "View circle members" policy queries circle_members to check access,
--          causing infinite recursion when PostgreSQL evaluates the policy.
-- Solution: Use a SECURITY DEFINER function that bypasses RLS to check membership.

-- Step 1: Create helper function to check circle membership (bypasses RLS)
CREATE OR REPLACE FUNCTION public.is_circle_member(check_circle_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM circle_members
    WHERE circle_id = check_circle_id
    AND user_id = auth.uid()
  );
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.is_circle_member(uuid) TO authenticated;

-- Step 2: Drop the problematic policies
DROP POLICY IF EXISTS "View circle members" ON public.circle_members;
DROP POLICY IF EXISTS "Circle members can view circle" ON public.circles;

-- Step 3: Recreate circle_members SELECT policy without recursion
-- Users can view members of circles they belong to
CREATE POLICY "Members can view circle members" ON public.circle_members
FOR SELECT USING (
  -- Can always see own membership
  auth.uid() = user_id
  OR
  -- Can see other members if user is in the same circle (via helper function)
  public.is_circle_member(circle_id)
);

-- Step 4: Recreate circles SELECT policy using helper function
CREATE POLICY "Circle members can view circle" ON public.circles
FOR SELECT USING (
  -- Owner can always view
  auth.uid() = owner_id
  OR
  -- Members can view circles they belong to
  public.is_circle_member(id)
);

-- Step 5: Fix circle_posts policies if they have similar issues
DROP POLICY IF EXISTS "Circle members can view posts" ON public.circle_posts;
DROP POLICY IF EXISTS "Circle members can post" ON public.circle_posts;

CREATE POLICY "Circle members can view posts" ON public.circle_posts
FOR SELECT USING (
  public.is_circle_member(circle_id)
);

CREATE POLICY "Circle members can post" ON public.circle_posts
FOR INSERT WITH CHECK (
  auth.uid() = user_id
  AND public.is_circle_member(circle_id)
);
