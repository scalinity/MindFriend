\ir support/authz_fixture.sql
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
SELECT pg_temp.authz_denied($q$INSERT INTO public.therapist_accounts(user_id,is_verified) VALUES (auth.uid(),true)$q$);
SELECT pg_temp.authz_denied($q$INSERT INTO public.listeners(user_id,status,certification_passed) VALUES (auth.uid(),'active',true)$q$);
INSERT INTO public.therapist_accounts(user_id,practice_name,license_number,license_state)
VALUES (auth.uid(),'Synthetic practice','synthetic-license','NY');
INSERT INTO public.listeners(user_id,display_name,bio) VALUES (auth.uid(),'Synthetic listener','Profile');
SELECT pg_temp.authz_denied($q$UPDATE public.therapist_accounts SET is_verified=true,license_verified_at=now() WHERE user_id=auth.uid()$q$);
SELECT pg_temp.authz_denied($q$UPDATE public.listeners SET status='active',certification_passed=true,certification_score=100 WHERE user_id=auth.uid()$q$);
SELECT pg_temp.authz_denied($q$UPDATE public.listeners SET is_available=true WHERE user_id=auth.uid()$q$);
UPDATE public.therapist_accounts SET practice_name='Updated practice' WHERE user_id=auth.uid();
UPDATE public.listeners SET bio='Updated bio' WHERE user_id=auth.uid();
SELECT pg_temp.authz_assert(public.start_listener_training(),'validated training transition retained');
RESET ROLE;
SELECT pg_temp.authz_assert((SELECT status='training' AND training_started_at IS NOT NULL FROM public.listeners),'training state persisted');
SET LOCAL ROLE service_role;
SELECT pg_temp.authz_claims(NULL);
UPDATE public.therapist_accounts SET is_verified=true,license_verified_at=now();
UPDATE public.listeners SET status='active',certification_passed=true,certification_score=100;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
SELECT pg_temp.authz_assert(public.toggle_listener_availability(true),'validated active-listener availability retained');
UPDATE public.therapist_accounts SET license_number='changed-license' WHERE user_id=auth.uid();
SELECT pg_temp.authz_assert((SELECT NOT is_verified AND license_verified_at IS NULL FROM public.therapist_accounts WHERE user_id=auth.uid()),'changed license invalidates old verification');
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000002');
DO $$ DECLARE changed integer; BEGIN
  UPDATE public.listeners SET bio='Cross-account edit' WHERE user_id='f0200000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS changed=ROW_COUNT;
  PERFORM pg_temp.authz_assert(changed=0,'profile edit ownership retained');
END $$;
RESET ROLE;
ROLLBACK;
\echo 'PASS verification field authorization'
