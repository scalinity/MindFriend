-- Compatible first subset of 20261022224831_narrow_sql_authorization.sql.
-- Close cron-secret exposure before credential configuration and keep moderator
-- authority in server-controlled JWT metadata. No user rows are changed.
BEGIN;
SET LOCAL lock_timeout = '3s';
DO $preflight$
BEGIN
  IF (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n
      ON n.oid=p.pronamespace WHERE n.nspname='public'
      AND p.proname IN ('get_cron_secret','is_moderator')) <> 2
    OR (SELECT md5(pg_catalog.pg_get_functiondef('public.get_cron_secret()'::regprocedure)))
       IS DISTINCT FROM 'f98336180ef5601fa8c848e451b27f0b'
    OR (SELECT md5(pg_catalog.pg_get_functiondef('public.is_moderator()'::regprocedure)))
       IS DISTINCT FROM 'cabbf0bb3cb11572a0ea218fb6a3b555'
  THEN RAISE EXCEPTION 'Audited RPC definitions changed; inspect before deployment';
  END IF;
END;
$preflight$;
REVOKE EXECUTE ON FUNCTION public.get_cron_secret() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_cron_secret() TO service_role;
ALTER FUNCTION public.get_cron_secret() SET search_path TO pg_catalog, public, pg_temp;

CREATE OR REPLACE FUNCTION public.is_moderator()
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER COST 10
 SET search_path TO pg_catalog, public, pg_temp
AS $function$
BEGIN
    RETURN COALESCE(
        (SELECT (auth.jwt() -> 'app_metadata' ->> 'role') = 'moderator'),
        false
    );
END;
$function$;

COMMIT;
