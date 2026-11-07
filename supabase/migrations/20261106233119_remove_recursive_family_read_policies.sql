BEGIN;
-- Group and member policies cannot query each other through RLS. This bounded
-- lookup returns only the current principal's access to the supplied family.
CREATE FUNCTION public.can_read_family(p_family_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $$
  SELECT EXISTS (SELECT 1 FROM public.family_groups fg
    WHERE fg.id=p_family_id AND fg.admin_user_id=auth.uid())
  OR EXISTS (SELECT 1 FROM public.family_members fm
    WHERE fm.family_id=p_family_id AND fm.user_id=auth.uid() AND fm.status='active')
$$;
REVOKE ALL ON FUNCTION public.can_read_family(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_read_family(uuid) TO authenticated;

ALTER POLICY "Members can view family group" ON public.family_groups TO authenticated
USING (public.can_read_family(id));
ALTER POLICY "View family members" ON public.family_members TO authenticated
USING (public.can_read_family(family_id));
ALTER POLICY "View own membership" ON public.family_members TO authenticated;
ALTER POLICY "Admin manages family group" ON public.family_groups TO authenticated;
ALTER POLICY "Admin manages family members" ON public.family_members TO authenticated;
COMMIT;
