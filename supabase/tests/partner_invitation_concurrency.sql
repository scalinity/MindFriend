-- Disposable *_synthetic database only, as supabase_admin, using psql -X
-- -v ON_ERROR_STOP=1. Phases: -v prepare=1 [ -v distinct_invites=1 ],
-- -v request=1 -v actor=UUID -v invite_hash=HASH [ -v hold=1 ],
-- -v verify=1, then -v cleanup=1. Start the hold request first, then the
-- contender while it sleeps; verify a Lock wait and exactly one success.
-- Same code: actors ...002 / ...003 with race-first.
-- Distinct codes: both actors ...002 with race-first / race-second.
\set ON_ERROR_STOP on
SET statement_timeout='20s';
SET lock_timeout='15s';
DO $$ BEGIN
  IF current_database() NOT LIKE '%_synthetic' OR current_user <> 'supabase_admin' THEN
    RAISE EXCEPTION 'Requires disposable synthetic database as supabase_admin';
  END IF;
END $$;

\if :{?prepare}
  \ir support/authz_fixture.sql
  INSERT INTO public.partner_links(user_id_1,created_by,invite_code_hash,status) VALUES
    ('f0200000-0000-4000-8000-000000000001','f0200000-0000-4000-8000-000000000001','race-first','pending');
  \if :{?distinct_invites}
    INSERT INTO public.partner_links(user_id_1,created_by,invite_code_hash,status) VALUES
      ('f0200000-0000-4000-8000-000000000003','f0200000-0000-4000-8000-000000000003','race-second','pending');
  \endif
  COMMIT;
\endif

\if :{?request}
  BEGIN;
  SET LOCAL ROLE service_role;
  SELECT public.accept_partner_invite(:'actor'::uuid,:'invite_hash');
  \if :{?hold}
    SELECT pg_sleep(3);
  \endif
  COMMIT;
\endif

\if :{?verify}
  DO $$ BEGIN
    IF (SELECT count(*) FROM public.partner_links WHERE status='active') <> 1
      OR EXISTS (SELECT participant FROM (
        SELECT user_id_1 AS participant FROM public.partner_links WHERE status='active'
        UNION ALL SELECT user_id_2 FROM public.partner_links WHERE status='active'
      ) participants GROUP BY participant HAVING count(*)>1) THEN
      RAISE EXCEPTION 'Concurrent acceptance created conflicting active partnerships';
    END IF;
  END $$;
\endif

\if :{?cleanup}
  DELETE FROM auth.users WHERE id IN (
    'f0200000-0000-4000-8000-000000000001',
    'f0200000-0000-4000-8000-000000000002',
    'f0200000-0000-4000-8000-000000000003'
  ) AND email LIKE 'authz-%@example.invalid';
  DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM auth.users) OR EXISTS (SELECT 1 FROM public.partner_links) THEN
      RAISE EXCEPTION 'Synthetic race cleanup incomplete';
    END IF;
  END $$;
\endif
