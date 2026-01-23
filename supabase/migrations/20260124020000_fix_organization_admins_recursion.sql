-- Fix infinite recursion in organization_admins RLS policies
-- The issue: policies on organization_admins query organization_admins, creating infinite loops
-- Solution: Use security definer functions that bypass RLS to check admin status

-- Drop existing problematic policies
DROP POLICY IF EXISTS "org_admins_read_own_org" ON public.organization_admins;
DROP POLICY IF EXISTS "org_admins_insert_manage_admins" ON public.organization_admins;
DROP POLICY IF EXISTS "org_admins_delete_manage_admins" ON public.organization_admins;

-- Create security definer function to check if user is admin (bypasses RLS)
CREATE OR REPLACE FUNCTION public.is_organization_admin(org_id UUID, check_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.organization_admins
    WHERE organization_id = org_id
      AND user_id = check_user_id
      AND role = 'admin'
  );
END;
$$;

-- Create security definer function to check if user belongs to org (any role)
CREATE OR REPLACE FUNCTION public.is_organization_member(org_id UUID, check_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.organization_admins
    WHERE organization_id = org_id
      AND user_id = check_user_id
  );
END;
$$;

-- Recreate policies using security definer functions (no recursion)
CREATE POLICY "org_admins_read_own_org"
  ON public.organization_admins
  FOR SELECT
  USING (is_organization_member(organization_id, auth.uid()));

CREATE POLICY "org_admins_insert_manage_admins"
  ON public.organization_admins
  FOR INSERT
  WITH CHECK (is_organization_admin(organization_id, auth.uid()));

CREATE POLICY "org_admins_update_manage_admins"
  ON public.organization_admins
  FOR UPDATE
  USING (is_organization_admin(organization_id, auth.uid()))
  WITH CHECK (is_organization_admin(organization_id, auth.uid()));

CREATE POLICY "org_admins_delete_manage_admins"
  ON public.organization_admins
  FOR DELETE
  USING (is_organization_admin(organization_id, auth.uid()));

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.is_organization_admin(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_organization_member(UUID, UUID) TO authenticated;

-- Add helpful comment
COMMENT ON FUNCTION public.is_organization_admin IS 'Security definer function to check admin status without triggering RLS recursion';
COMMENT ON FUNCTION public.is_organization_member IS 'Security definer function to check org membership without triggering RLS recursion';
