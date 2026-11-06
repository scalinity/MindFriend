\ir support/authz_fixture.sql
CREATE TEMP TABLE queue_calls(statement text);
INSERT INTO queue_calls VALUES
  ('SELECT * FROM public.email_queue'),
  ('SELECT * FROM public.email_dead_letter_queue'),
  ($q$INSERT INTO public.email_queue(user_id,email_type,scheduled_for,payload) VALUES ('f0200000-0000-4000-8000-000000000002','synthetic',now(),'{}')$q$),
  ($q$INSERT INTO public.email_dead_letter_queue(user_id,email_type,payload) VALUES ('f0200000-0000-4000-8000-000000000002','synthetic','{}')$q$),
  ($q$UPDATE public.email_queue SET payload='{"forged":true}'$q$),
  ($q$UPDATE public.email_dead_letter_queue SET payload='{"forged":true}'$q$),
  ('DELETE FROM public.email_queue'),
  ('DELETE FROM public.email_dead_letter_queue');
GRANT SELECT ON queue_calls TO anon, authenticated;
SET LOCAL ROLE service_role;
SELECT pg_temp.authz_claims(NULL);
INSERT INTO public.email_queue(user_id,email_type,scheduled_for,payload) VALUES
  ('f0200000-0000-4000-8000-000000000002','synthetic',now(),'{"private":true}');
INSERT INTO public.email_dead_letter_queue(user_id,email_type,payload) VALUES
  ('f0200000-0000-4000-8000-000000000002','synthetic','{"private":true}');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT pg_temp.authz_claims(NULL);
DO $$ DECLARE item record; BEGIN
  FOR item IN SELECT * FROM queue_calls LOOP PERFORM pg_temp.authz_denied(item.statement); END LOOP;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
DO $$ DECLARE item record; BEGIN
  FOR item IN SELECT * FROM queue_calls LOOP PERFORM pg_temp.authz_denied(item.statement); END LOOP;
END $$;
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.authz_claims(NULL);
SELECT pg_temp.authz_assert((SELECT count(*)=1 FROM public.email_queue),'service queue read');
SELECT pg_temp.authz_assert((SELECT count(*)=1 FROM public.email_dead_letter_queue),'service DLQ read');
UPDATE public.email_queue SET status='processed';
UPDATE public.email_dead_letter_queue SET requires_manual_review=false;
DELETE FROM public.email_queue;
DELETE FROM public.email_dead_letter_queue;
SELECT pg_temp.authz_assert((SELECT count(*)=0 FROM public.email_queue),'service queue delete');
SELECT pg_temp.authz_assert((SELECT count(*)=0 FROM public.email_dead_letter_queue),'service DLQ delete');
RESET ROLE;
ROLLBACK;
\echo 'PASS email queue authorization'
