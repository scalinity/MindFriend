-- Connections receive presence only while its owner explicitly shares it.
-- This changes no publication membership and preserves the owner's own-row policy.
BEGIN;
SET LOCAL search_path = '';

-- Refuse a different SELECT-policy baseline rather than leave another permissive
-- policy able to bypass the preference. Expressions come from the schema-only backup.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class
    WHERE oid = 'public.user_presence'::regclass AND relrowsecurity)
    OR (SELECT count(*) FROM pg_catalog.pg_policy
      WHERE polrelid = 'public.user_presence'::regclass AND polcmd IN ('r', '*')) <> 2
    OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy
      WHERE polrelid = 'public.user_presence'::regclass
        AND polname = 'Users can view own presence' AND polcmd = 'r'
        AND polpermissive AND polroles = ARRAY[0::oid]
        AND pg_catalog.pg_get_expr(polqual, polrelid) = '(auth.uid() = user_id)')
    OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy
      WHERE polrelid = 'public.user_presence'::regclass
        AND polname = 'Connections can view presence' AND polcmd = 'r'
        AND polpermissive AND polroles = ARRAY[0::oid]
        AND pg_catalog.pg_get_expr(polqual, polrelid) = $expected$((user_id IN ( SELECT cm2.user_id
   FROM (public.circle_members cm1
     JOIN public.circle_members cm2 ON ((cm1.circle_id = cm2.circle_id)))
  WHERE (cm1.user_id = auth.uid()))) OR (user_id IN ( SELECT
        CASE
            WHEN (br.inviter_id = auth.uid()) THEN br.invitee_id
            ELSE br.inviter_id
        END AS inviter_id
   FROM public.buddy_relationships br
  WHERE ((br.status = 'accepted'::text) AND ((br.inviter_id = auth.uid()) OR (br.invitee_id = auth.uid()))))))$expected$)
    OR pg_catalog.to_regprocedure('public.can_view_connected_presence(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'Unexpected presence privacy baseline';
  END IF;
END;
$$;

-- Other users' settings are private under RLS. Evaluate only this visibility
-- decision as the owner; direct calls still require the caller's real connection.
CREATE FUNCTION public.can_view_connected_presence(p_user_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT auth.uid() IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.user_settings AS settings
      WHERE settings.user_id = p_user_id AND settings.show_presence IS TRUE)
    AND (
      EXISTS (SELECT 1 FROM public.circle_members AS caller
        JOIN public.circle_members AS connection ON connection.circle_id = caller.circle_id
        WHERE caller.user_id = auth.uid() AND connection.user_id = p_user_id)
      OR EXISTS (SELECT 1 FROM public.buddy_relationships AS buddy
        WHERE buddy.status = 'accepted' AND (
          (buddy.inviter_id = auth.uid() AND buddy.invitee_id = p_user_id)
          OR (buddy.invitee_id = auth.uid() AND buddy.inviter_id = p_user_id)
        ))
    );
$$;
REVOKE ALL ON FUNCTION public.can_view_connected_presence(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_view_connected_presence(uuid) TO authenticated, service_role;

ALTER POLICY "Connections can view presence" ON public.user_presence
  TO authenticated USING (public.can_view_connected_presence(user_id));
COMMENT ON FUNCTION public.can_view_connected_presence(uuid) IS
  'True only for a current circle connection or accepted buddy whose current show_presence is explicitly true. Does not expose other settings or authorize unrelated users.';
COMMIT;
