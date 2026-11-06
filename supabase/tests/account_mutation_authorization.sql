\ir support/authz_fixture.sql
CREATE TEMP TABLE mutation_cases(statement text);
INSERT INTO mutation_cases VALUES
  ($q$SELECT * FROM public.award_xp('f0200000-0000-4000-8000-000000000002',10,'synthetic',NULL)$q$),
  ($q$SELECT * FROM public.perform_fresh_start('f0200000-0000-4000-8000-000000000002')$q$),
  ($q$SELECT * FROM public.accept_buddy_invite('AUTHZBUDDY','f0200000-0000-4000-8000-000000000002')$q$),
  ($q$SELECT public.enroll_user_in_pathway('f0200000-0000-4000-8000-000000000002',gen_random_uuid(),'{}','forged')$q$),
  ($q$SELECT * FROM public.upsert_strategy_vote(gen_random_uuid(),'f0200000-0000-4000-8000-000000000002','helpful')$q$);
GRANT SELECT ON mutation_cases TO anon, authenticated;
INSERT INTO public.buddy_relationships(inviter_id,invite_code)
VALUES ('f0200000-0000-4000-8000-000000000002','AUTHZBUDDY');

SET LOCAL ROLE anon;
SELECT pg_temp.authz_claims(NULL);
DO $$ DECLARE item record; BEGIN
  FOR item IN SELECT * FROM mutation_cases LOOP PERFORM pg_temp.authz_denied(item.statement); END LOOP;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims(NULL);
DO $$ DECLARE item record; BEGIN
  FOR item IN SELECT * FROM mutation_cases LOOP PERFORM pg_temp.authz_denied(item.statement); END LOOP;
END $$;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
DO $$ DECLARE item record; BEGIN
  FOR item IN SELECT * FROM mutation_cases LOOP PERFORM pg_temp.authz_denied(item.statement); END LOOP;
END $$;
RESET ROLE;
SELECT pg_temp.authz_assert((SELECT xp_total=0 FROM public.user_stats WHERE user_id='f0200000-0000-4000-8000-000000000002'), 'rejected calls leave victim stats unchanged');
SET LOCAL ROLE authenticated;
SELECT * FROM public.award_xp('f0200000-0000-4000-8000-000000000001',10,'synthetic',NULL);
SELECT * FROM public.perform_fresh_start('f0200000-0000-4000-8000-000000000001');
SELECT public.accept_buddy_invite('AUTHZBUDDY','f0200000-0000-4000-8000-000000000001');
RESET ROLE;
SELECT pg_temp.authz_assert((SELECT xp_total=10 FROM public.user_stats WHERE user_id='f0200000-0000-4000-8000-000000000001'), 'owner XP award persisted');
SELECT pg_temp.authz_assert((SELECT xp_total=100 FROM public.user_stats WHERE user_id='f0200000-0000-4000-8000-000000000002'), 'valid invitation grants fixed inviter reward');
SELECT pg_temp.authz_assert((SELECT status='accepted' AND invitee_id='f0200000-0000-4000-8000-000000000001' FROM public.buddy_relationships WHERE invite_code='AUTHZBUDDY'), 'invite accepted by caller only');
SELECT pg_temp.authz_assert((SELECT count(*)=2 FROM public.circle_members), 'accepted buddy membership preserved');
SELECT pg_temp.authz_assert((SELECT max_members=2 FROM public.circles), 'buddy capacity preserved');
SELECT pg_temp.authz_assert(has_function_privilege('service_role','public.enroll_user_in_pathway(uuid,uuid,jsonb,text)','execute')
  AND has_function_privilege('service_role','public.upsert_strategy_vote(uuid,uuid,text)','execute'), 'validated service RPC grants retained');
SET LOCAL ROLE service_role;
SELECT pg_temp.authz_claims(NULL);
SELECT * FROM public.award_xp('f0200000-0000-4000-8000-000000000003',10,'synthetic',NULL);
SELECT * FROM public.perform_fresh_start('f0200000-0000-4000-8000-000000000003');
RESET ROLE;
ROLLBACK;
\echo 'PASS account mutation authorization'
