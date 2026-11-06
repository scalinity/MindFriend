-- All iOS reporting goes through the authenticated flag-content handler.
-- Protect its owner/rate/escalation checks from direct-table insert bypass.
BEGIN;
SET LOCAL lock_timeout = '3s';
DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy
    WHERE polrelid = 'public.gen_content_flags'::regclass
      AND polname = 'Users can flag gen content'
      AND polcmd = 'a' AND polpermissive
      AND polroles = ARRAY[0]::oid[]
      AND pg_catalog.pg_get_expr(polwithcheck,polrelid) = 'true'
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_policy
    WHERE polrelid = 'public.gen_content_flags'::regclass
      AND polname = 'Service role inserts content reports'
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.aclexplode((
      SELECT relacl FROM pg_catalog.pg_class WHERE oid='public.gen_content_flags'::regclass
    )) WHERE grantee=0 AND privilege_type='INSERT'
  ) THEN
    RAISE EXCEPTION 'Content-report insert policy/grants differ from audited baseline';
  END IF;
END;
$migration$;
ALTER POLICY "Users can flag gen content" ON public.gen_content_flags
  TO service_role WITH CHECK (true);
ALTER POLICY "Users can flag gen content" ON public.gen_content_flags
  RENAME TO "Service role inserts content reports";
REVOKE INSERT ON public.gen_content_flags FROM PUBLIC, anon, authenticated;
GRANT INSERT ON public.gen_content_flags TO service_role;
COMMIT;
