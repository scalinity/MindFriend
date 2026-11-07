\ir support/authz_fixture.sql
INSERT INTO public.circles(id,name,invite_code,owner_id,max_members) VALUES
  ('f0200000-0000-4000-9000-000000000001','Synthetic circle','AUTHZCIRCLE','f0200000-0000-4000-8000-000000000001',2);
INSERT INTO public.circle_rituals(id,circle_id,created_by,title,ritual_type,scheduled_for,duration_seconds)
VALUES ('f0200000-0000-4000-9000-000000000002','f0200000-0000-4000-9000-000000000001',
  'f0200000-0000-4000-8000-000000000001','Synthetic ritual','breathing',now(),180);
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
-- Preserve circle creation's default member role for its actual owner.
INSERT INTO public.circle_members(circle_id,user_id) VALUES
  ('f0200000-0000-4000-9000-000000000001','f0200000-0000-4000-8000-000000000001');
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000002');
SELECT pg_temp.authz_denied($q$INSERT INTO public.circle_members(circle_id,user_id,role) VALUES
  ('f0200000-0000-4000-9000-000000000001','f0200000-0000-4000-8000-000000000002','member')$q$);
SELECT pg_temp.authz_denied($q$INSERT INTO public.circle_members(circle_id,user_id,role) VALUES
  ('f0200000-0000-4000-9000-000000000001','f0200000-0000-4000-8000-000000000002','owner')$q$);
SELECT pg_temp.authz_denied($q$INSERT INTO public.circle_ritual_attendees(ritual_id,user_id) VALUES
  ('f0200000-0000-4000-9000-000000000002','f0200000-0000-4000-8000-000000000002')$q$);
SELECT pg_temp.authz_denied($q$INSERT INTO public.circle_ritual_reflections(ritual_id,user_id,body_text) VALUES
  ('f0200000-0000-4000-9000-000000000002','f0200000-0000-4000-8000-000000000002','forged')$q$);
SELECT pg_temp.authz_assert((SELECT NOT success FROM public.join_circle_by_invite_code('WRONG')),'wrong code rejected');
SELECT pg_temp.authz_assert((SELECT success FROM public.join_circle_by_invite_code(' authzcircle ')),'valid code admitted');
SELECT pg_temp.authz_assert((SELECT role='member' FROM public.circle_members WHERE user_id=auth.uid()),'invite does not grant owner role');
INSERT INTO public.circle_ritual_attendees(ritual_id,user_id) VALUES
  ('f0200000-0000-4000-9000-000000000002','f0200000-0000-4000-8000-000000000002');
SELECT pg_temp.authz_denied($q$UPDATE public.circle_ritual_attendees SET ritual_id=gen_random_uuid() WHERE user_id=auth.uid()$q$);
UPDATE public.circle_ritual_attendees SET left_at=now() WHERE user_id=auth.uid();
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000003');
SELECT pg_temp.authz_assert((SELECT NOT success FROM public.join_circle_by_invite_code('AUTHZCIRCLE')),'full circle rejects third participant');
RESET ROLE;
UPDATE public.circle_rituals SET status='completed' WHERE id='f0200000-0000-4000-9000-000000000002';
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000002');
INSERT INTO public.circle_ritual_reflections(ritual_id,user_id,body_text) VALUES
  ('f0200000-0000-4000-9000-000000000002','f0200000-0000-4000-8000-000000000002','Valid reflection');
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
SELECT pg_temp.authz_denied($q$INSERT INTO public.circle_ritual_reflections(ritual_id,user_id,body_text) VALUES
  ('f0200000-0000-4000-9000-000000000002','f0200000-0000-4000-8000-000000000001','Not an attendee')$q$);
RESET ROLE;
ROLLBACK;
\echo 'PASS circle admission authorization'
