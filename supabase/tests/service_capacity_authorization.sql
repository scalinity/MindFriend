\ir support/authz_fixture.sql

SET LOCAL ROLE anon;
SELECT pg_temp.authz_claims(NULL);
SELECT pg_temp.authz_denied($q$SELECT public.check_capacity_rate_limit('f0200000-0000-4000-8000-000000000001',60000,2)$q$);
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
SELECT pg_temp.authz_denied($q$SELECT public.check_capacity_rate_limit('f0200000-0000-4000-8000-000000000001',60000,2)$q$);
SELECT set_config('request.jwt.claim.role','service_role',true),
 set_config('request.jwt.claims','{"role":"service_role"}',true);
SELECT pg_temp.authz_denied($q$SELECT public.check_capacity_rate_limit('f0200000-0000-4000-8000-000000000001',60000,2)$q$);

SET LOCAL ROLE service_role;
SELECT pg_temp.authz_claims(NULL);
SELECT pg_temp.authz_denied('SELECT public.check_capacity_rate_limit(NULL,60000,2)');
SELECT pg_temp.authz_assert((public.check_capacity_rate_limit('f0200000-0000-4000-8000-000000000001',60000,2)->>'remaining')::integer=1,
 'Service first request works without a subject');
SELECT pg_temp.authz_assert((public.check_capacity_rate_limit('f0200000-0000-4000-8000-000000000001',60000,2)->>'remaining')::integer=0,
 'Service consumes the last request');
SELECT pg_temp.authz_assert(NOT (public.check_capacity_rate_limit('f0200000-0000-4000-8000-000000000001',60000,2)->>'allowed')::boolean,
 'Service still enforces quota');
UPDATE public.capacity_rate_limits SET window_start=now()-interval '2 minutes'
 WHERE user_id='f0200000-0000-4000-8000-000000000001';
SELECT pg_temp.authz_assert((public.check_capacity_rate_limit('f0200000-0000-4000-8000-000000000001',60000,2)->>'allowed')::boolean,
 'Expired window permits a new request');
ROLLBACK;
\echo PASS service capacity authorization
