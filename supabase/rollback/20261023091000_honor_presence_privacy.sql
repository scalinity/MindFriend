-- Restore the exact connection policy. Keep Realtime unpublished before rollback:
-- the earlier policy does not respect show_presence.
BEGIN;
SET LOCAL search_path = '';
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'user_presence') THEN
    RAISE EXCEPTION 'Remove user_presence from Realtime before restoring its earlier visibility policy';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policy
    WHERE polrelid = 'public.user_presence'::regclass
      AND polname = 'Connections can view presence' AND polcmd = 'r'
      AND polpermissive
      AND polroles = ARRAY['authenticated'::regrole::oid]
      AND pg_catalog.pg_get_expr(polqual, polrelid) = 'public.can_view_connected_presence(user_id)') THEN
    RAISE EXCEPTION 'Unexpected presence privacy rollback baseline';
  END IF;
END;
$$;
ALTER POLICY "Connections can view presence" ON public.user_presence TO PUBLIC
  USING ((user_id IN (SELECT cm2.user_id
    FROM public.circle_members AS cm1
    JOIN public.circle_members AS cm2 ON cm1.circle_id = cm2.circle_id
    WHERE cm1.user_id = auth.uid()))
  OR (user_id IN (SELECT CASE WHEN br.inviter_id = auth.uid() THEN br.invitee_id ELSE br.inviter_id END
    FROM public.buddy_relationships AS br
    WHERE br.status = 'accepted' AND (br.inviter_id = auth.uid() OR br.invitee_id = auth.uid()))));
DROP FUNCTION public.can_view_connected_presence(uuid);
COMMIT;
