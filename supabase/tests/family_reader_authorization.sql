\ir support/authz_fixture.sql

INSERT INTO public.family_groups(id,admin_user_id,name) VALUES
 ('f0240000-0000-4000-8000-000000000001','f0200000-0000-4000-8000-000000000001','Family one'),
 ('f0240000-0000-4000-8000-000000000002','f0200000-0000-4000-8000-000000000003','Family two');
INSERT INTO public.family_members(family_id,user_id,role,status) VALUES
 ('f0240000-0000-4000-8000-000000000001','f0200000-0000-4000-8000-000000000001','admin','active'),
 ('f0240000-0000-4000-8000-000000000001','f0200000-0000-4000-8000-000000000002','child','active'),
 ('f0240000-0000-4000-8000-000000000002','f0200000-0000-4000-8000-000000000003','admin','active'),
 ('f0240000-0000-4000-8000-000000000002','f0200000-0000-4000-8000-000000000002','child','removed');

SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
SELECT pg_temp.authz_assert((SELECT count(*)=1 FROM public.family_groups), 'Admin reads own group without recursion');
SELECT pg_temp.authz_assert((SELECT count(*)=2 FROM public.family_members), 'Admin reads own family members');
WITH changed AS (UPDATE public.family_groups SET name='Managed family'
 WHERE id='f0240000-0000-4000-8000-000000000001' RETURNING id)
SELECT pg_temp.authz_assert(count(*)=1, 'Admin retains group management') FROM changed;
WITH changed AS (UPDATE public.family_members SET nickname='Managed nickname'
 WHERE family_id='f0240000-0000-4000-8000-000000000001' AND user_id='f0200000-0000-4000-8000-000000000002' RETURNING id)
SELECT pg_temp.authz_assert(count(*)=1, 'Admin retains member management') FROM changed;

SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000002');
SELECT pg_temp.authz_assert((SELECT count(*)=1 AND min(id::text)='f0240000-0000-4000-8000-000000000001'
 FROM public.family_groups), 'Active member reads only joined group');
SELECT pg_temp.authz_assert((SELECT count(*)=2 FROM public.family_members
 WHERE family_id='f0240000-0000-4000-8000-000000000001'), 'Member reads own family peers');
SELECT pg_temp.authz_assert((SELECT count(*)=1 AND bool_and(user_id=auth.uid()) FROM public.family_members
 WHERE family_id='f0240000-0000-4000-8000-000000000002'), 'Removed member retains own row without access to peers');
WITH changed AS (UPDATE public.family_members SET role='admin' WHERE user_id=auth.uid() RETURNING id)
SELECT pg_temp.authz_assert(count(*)=0, 'Child cannot promote own membership') FROM changed;
WITH changed AS (UPDATE public.family_groups SET admin_user_id=auth.uid() RETURNING id)
SELECT pg_temp.authz_assert(count(*)=0, 'Member cannot take group ownership') FROM changed;
SELECT pg_temp.authz_denied($q$INSERT INTO public.family_members(family_id,user_id,role,status)
 VALUES ('f0240000-0000-4000-8000-000000000001','f0200000-0000-4000-8000-000000000003','parent','active')$q$);

SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000003');
SELECT pg_temp.authz_assert((SELECT count(*)=1 AND min(id::text)='f0240000-0000-4000-8000-000000000002'
 FROM public.family_groups), 'Other administrator cannot read unrelated family');
SELECT pg_temp.authz_assert((SELECT count(*)=2 FROM public.family_members), 'Other administrator sees only own members');
SELECT pg_temp.authz_claims(NULL);
SELECT pg_temp.authz_assert((SELECT count(*)=0 FROM public.family_groups), 'Missing principal cannot read groups');
SELECT pg_temp.authz_assert((SELECT count(*)=0 FROM public.family_members), 'Missing principal cannot read memberships');
SET LOCAL ROLE anon;
SELECT pg_temp.authz_claims(NULL);
SELECT pg_temp.authz_assert((SELECT count(*)=0 FROM public.family_groups), 'Anonymous cannot read groups');
SELECT pg_temp.authz_assert((SELECT count(*)=0 FROM public.family_members), 'Anonymous cannot read memberships');

SET LOCAL ROLE service_role;
SELECT pg_temp.authz_claims(NULL);
SELECT pg_temp.authz_assert((SELECT count(*)=2 FROM public.family_groups), 'Service retains group operations');
SELECT pg_temp.authz_assert((SELECT count(*)=4 FROM public.family_members), 'Service retains membership operations');
ROLLBACK;
\echo PASS family reader and management authorization
