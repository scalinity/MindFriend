BEGIN;
DROP POLICY "Lookup invitation by code" ON public.family_invitations;
DROP POLICY "org_invites_public_validate" ON public.organization_invites;
REVOKE ALL ON public.family_invitations, public.organization_invites FROM PUBLIC, anon;

-- The recipient policy needs the current, verified Auth email without granting
-- clients access to auth.users. This function can only return its caller's email.
CREATE FUNCTION public.current_verified_invitation_email() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $$
  SELECT lower(u.email)::text FROM auth.users u
  WHERE u.id = auth.uid() AND u.email_confirmed_at IS NOT NULL
$$;
REVOKE ALL ON FUNCTION public.current_verified_invitation_email() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_verified_invitation_email() TO authenticated;

-- Avoid the family_groups/family_members policy cycle while exposing only an
-- authorization decision for the current principal, never another user's role.
CREATE FUNCTION public.can_manage_family_invitations(p_family_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $$
  SELECT EXISTS (SELECT 1 FROM public.family_groups fg
    WHERE fg.id = p_family_id AND fg.admin_user_id = auth.uid())
$$;
REVOKE ALL ON FUNCTION public.can_manage_family_invitations(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_manage_family_invitations(uuid) TO authenticated;

ALTER POLICY "Family admins can read their invitations" ON public.family_invitations
TO authenticated
USING (
  public.can_manage_family_invitations(family_id)
  OR lower(email) = (SELECT public.current_verified_invitation_email())
);
ALTER POLICY "Admin manages invitations" ON public.family_invitations TO authenticated
USING (public.can_manage_family_invitations(family_id))
WITH CHECK (public.can_manage_family_invitations(family_id));
ALTER POLICY "Family admins can create invitations" ON public.family_invitations TO authenticated
WITH CHECK (public.can_manage_family_invitations(family_id));
ALTER POLICY "Family admins can update invitations" ON public.family_invitations TO authenticated
USING (public.can_manage_family_invitations(family_id))
WITH CHECK (public.can_manage_family_invitations(family_id));
ALTER POLICY "org_invites_admins_read" ON public.organization_invites TO authenticated;
ALTER POLICY "org_invites_admins_insert" ON public.organization_invites TO authenticated;
ALTER POLICY "org_invites_admins_update" ON public.organization_invites TO authenticated;

-- Code validation/acceptance remains in existing service handlers, with an exact
-- supplied-code filter and expiry, recipient and remaining-use checks.
COMMIT;
