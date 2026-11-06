-- Local-stack-only psql fixture; supply an existing synthetic auth user's UUID.
-- Run with -XqAt -v ON_ERROR_STOP=1 -v rate_limit_user_id=UUID and one phase flag:
--   -v prepare=1: clear the test endpoint and check ACL/invalid arguments.
--   -v request=1: run four separate connections concurrently; capture their stdout.
--                 Require exactly three "t" and one "f" results, no errors.
--   -v verify=1: check the stored count, denial and expired-window reset contract.
--   -v cleanup=1: remove only this synthetic user's test endpoint.
-- The request phase holds its transaction briefly so first-row inserts overlap.
\set ON_ERROR_STOP on
\if :{?rate_limit_user_id}
\else
  DO $$ BEGIN RAISE EXCEPTION 'rate_limit_user_id must identify a synthetic local user'; END $$;
\endif

SELECT set_config('mindfriend.rate_limit_test_user', :'rate_limit_user_id', false) AS configured \gset
SET lock_timeout = '15s';
SET statement_timeout = '20s';

\if :{?prepare}
DELETE FROM public.rate_limits
WHERE user_id = :'rate_limit_user_id'::uuid AND endpoint = 'restoration-rate-concurrency';

DO $$
DECLARE
  signature text := 'public.check_rate_limit(uuid,text,timestamptz,integer,integer)';
  test_user uuid := current_setting('mindfriend.rate_limit_test_user')::uuid;
  args record;
BEGIN
  IF has_function_privilege('anon', signature, 'EXECUTE')
     OR has_function_privilege('authenticated', signature, 'EXECUTE')
     OR NOT has_function_privilege('service_role', signature, 'EXECUTE') THEN
    RAISE EXCEPTION 'Rate limit RPC must be service-only';
  END IF;

  FOR args IN SELECT * FROM (VALUES
    (NULL::uuid, 'restoration-rate-concurrency', now(), 3, 60000),
    (test_user, NULL, now(), 3, 60000),
    (test_user, '  ', now(), 3, 60000),
    (test_user, 'restoration-rate-concurrency', NULL::timestamptz, 3, 60000),
    (test_user, 'restoration-rate-concurrency', 'infinity'::timestamptz, 3, 60000),
    (test_user, 'restoration-rate-concurrency', '-infinity'::timestamptz, 3, 60000),
    (test_user, 'restoration-rate-concurrency', now() + interval '1 minute', 3, 60000),
    (test_user, 'restoration-rate-concurrency', now(), NULL::integer, 60000),
    (test_user, 'restoration-rate-concurrency', now(), 0, 60000),
    (test_user, 'restoration-rate-concurrency', now(), -1, 60000),
    (test_user, 'restoration-rate-concurrency', now(), 3, NULL::integer),
    (test_user, 'restoration-rate-concurrency', now(), 3, 0),
    (test_user, 'restoration-rate-concurrency', now(), 3, -1)
  ) AS invalid(user_id, endpoint, window_start, max_requests, window_ms)
  LOOP
    BEGIN
      PERFORM * FROM public.check_rate_limit(args.user_id, args.endpoint,
        args.window_start, args.max_requests, args.window_ms);
      RAISE EXCEPTION 'Invalid rate limit arguments were accepted: %', args;
    EXCEPTION WHEN invalid_parameter_value THEN
      NULL;
    END;
  END LOOP;
END $$;
\endif

\if :{?request}
BEGIN;
SET LOCAL ROLE service_role;
SELECT allowed FROM public.check_rate_limit(:'rate_limit_user_id'::uuid,
  'restoration-rate-concurrency', now() - interval '1 minute', 3, 60000);
SELECT pg_sleep(0.05) AS held \gset
COMMIT;
\endif

\if :{?verify}
BEGIN;
DO $$
DECLARE
  test_user uuid := current_setting('mindfriend.rate_limit_test_user')::uuid;
  saved_count integer;
  result record;
  saved_start timestamptz;
BEGIN
  SELECT request_count, window_start INTO saved_count, saved_start
  FROM public.rate_limits
  WHERE user_id = test_user AND endpoint = 'restoration-rate-concurrency';
  IF saved_count IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'Concurrent burst stored %, expected 3', saved_count;
  END IF;
  SELECT * INTO result FROM public.check_rate_limit(test_user,
    'restoration-rate-concurrency', now() - interval '1 minute', 3, 60000);
  IF result.allowed IS DISTINCT FROM false OR result.remaining IS DISTINCT FROM 0
     OR result.reset_at IS DISTINCT FROM saved_start + interval '1 minute' THEN
    RAISE EXCEPTION 'Exhausted-window result changed: %', result;
  END IF;

  UPDATE public.rate_limits SET window_start = now() - interval '2 minutes'
  WHERE user_id = test_user AND endpoint = 'restoration-rate-concurrency';
  SELECT * INTO result FROM public.check_rate_limit(test_user,
    'restoration-rate-concurrency', now() - interval '1 minute', 3, 60000);
  IF result.allowed IS DISTINCT FROM true OR result.remaining IS DISTINCT FROM 2
     OR result.reset_at IS DISTINCT FROM now() + interval '1 minute' THEN
    RAISE EXCEPTION 'Expired-window reset result changed: %', result;
  END IF;
END $$;
ROLLBACK;
\endif

\if :{?cleanup}
DELETE FROM public.rate_limits
WHERE user_id = :'rate_limit_user_id'::uuid AND endpoint = 'restoration-rate-concurrency';
\endif
