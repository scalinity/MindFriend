-- Included by authorization regressions; all synthetic rows roll back.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_user <> 'supabase_admin' OR current_database() NOT LIKE '%_synthetic'
    OR EXISTS (SELECT 1 FROM auth.users) OR EXISTS (SELECT 1 FROM public.profiles) THEN
    RAISE EXCEPTION 'Requires an empty disposable synthetic database as supabase_admin';
  END IF;
END $$;

CREATE FUNCTION pg_temp.authz_assert(ok boolean, label text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
  IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %', label; END IF;
END $$;
CREATE FUNCTION pg_temp.authz_denied(statement text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER AS $$ BEGIN
  BEGIN
    EXECUTE statement;
  EXCEPTION WHEN insufficient_privilege THEN RETURN;
  END;
  RAISE EXCEPTION 'Expected access denial: %', statement;
END $$;
CREATE FUNCTION pg_temp.authz_claims(principal uuid) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
  PERFORM set_config('request.jwt.claim.sub', COALESCE(principal::text, ''), true);
  PERFORM set_config('request.jwt.claim.role', current_setting('role'), true);
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub', principal, 'role', current_setting('role'), 'app_metadata', '{}'::jsonb)::text, true);
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT USAGE ON SCHEMA %I TO anon, authenticated, service_role',
    (SELECT nspname FROM pg_namespace WHERE oid=pg_my_temp_schema()));
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.authz_assert(boolean,text), pg_temp.authz_denied(text),
  pg_temp.authz_claims(uuid) TO anon, authenticated, service_role;

INSERT INTO auth.users(id, email, raw_app_meta_data, raw_user_meta_data)
SELECT ('f0200000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  'authz-'||n||'@example.invalid', '{}', '{}' FROM generate_series(1,3) n;
INSERT INTO public.profiles(id,email,display_name,handle,timezone)
SELECT id,email,'Synthetic account','authz_'||right(id::text,1),'UTC' FROM auth.users
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.user_stats(user_id) SELECT id FROM auth.users ON CONFLICT (user_id) DO NOTHING;
