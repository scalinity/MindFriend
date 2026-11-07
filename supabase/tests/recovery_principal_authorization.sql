\ir support/authz_fixture.sql
CREATE TEMP TABLE recovery_calls(statement text);
INSERT INTO recovery_calls VALUES
  ($q$SELECT * FROM public.get_shield_status('f0200000-0000-4000-8000-000000000002')$q$),
  ($q$SELECT * FROM public.start_recovery_quest('f0200000-0000-4000-8000-000000000002')$q$),
  ($q$SELECT * FROM public.complete_recovery_quest('f0200000-0000-4000-8000-000000000002',gen_random_uuid())$q$),
  ($q$SELECT * FROM public.fail_recovery_quest('f0200000-0000-4000-8000-000000000002',gen_random_uuid())$q$);
GRANT SELECT ON recovery_calls TO anon, authenticated;
UPDATE public.user_stats SET recovery_quest_available=true,
  recovery_quest_expires_at=now()+interval '1 day', recovery_attempts_remaining=2,
  recovery_attempts_max=2, streak_before_break=10;
INSERT INTO public.quest_templates(title,description,estimated_minutes)
VALUES ('Synthetic recovery','Synthetic recovery instructions',10);

SET LOCAL ROLE anon;
SELECT pg_temp.authz_claims(NULL);
DO $$ DECLARE item record; BEGIN
  FOR item IN SELECT * FROM recovery_calls LOOP PERFORM pg_temp.authz_denied(item.statement); END LOOP;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims(NULL);
DO $$ DECLARE item record; BEGIN
  FOR item IN SELECT * FROM recovery_calls LOOP PERFORM pg_temp.authz_denied(item.statement); END LOOP;
END $$;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
DO $$ DECLARE item record; BEGIN
  FOR item IN SELECT * FROM recovery_calls LOOP PERFORM pg_temp.authz_denied(item.statement); END LOOP;
END $$;
SELECT pg_temp.authz_assert((SELECT recovery_quest_available FROM public.get_shield_status('f0200000-0000-4000-8000-000000000001')), 'owner shield read');
DO $$ DECLARE attempt uuid; started boolean; completed boolean; BEGIN
  SELECT attempt_id,success INTO attempt,started FROM public.start_recovery_quest('f0200000-0000-4000-8000-000000000001');
  PERFORM pg_temp.authz_assert(started AND attempt IS NOT NULL,'owner recovery start');
  SELECT success INTO completed FROM public.complete_recovery_quest('f0200000-0000-4000-8000-000000000001',attempt);
  PERFORM pg_temp.authz_assert(completed,'owner recovery completion');
END $$;
RESET ROLE;
SELECT pg_temp.authz_assert((SELECT current_streak_days=10 FROM public.user_stats WHERE user_id='f0200000-0000-4000-8000-000000000001'), 'owner streak restored');

SET LOCAL ROLE service_role;
SELECT pg_temp.authz_claims(NULL);
SELECT * FROM public.get_shield_status('f0200000-0000-4000-8000-000000000002');
DO $$ DECLARE attempt uuid; started boolean; failed boolean; BEGIN
  SELECT attempt_id,success INTO attempt,started FROM public.start_recovery_quest('f0200000-0000-4000-8000-000000000002');
  PERFORM pg_temp.authz_assert(started AND attempt IS NOT NULL,'service recovery start');
  SELECT success INTO failed FROM public.fail_recovery_quest('f0200000-0000-4000-8000-000000000002',attempt);
  PERFORM pg_temp.authz_assert(failed,'service recovery failure');
END $$;
RESET ROLE;
ROLLBACK;
\echo 'PASS recovery principal authorization'
