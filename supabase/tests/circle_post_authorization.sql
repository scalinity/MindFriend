\ir support/authz_fixture.sql
INSERT INTO public.circles(id,name,invite_code,owner_id) VALUES
  ('f0200000-0000-4000-9000-000000000001','Synthetic circle','AUTHZPOST','f0200000-0000-4000-8000-000000000001');
INSERT INTO public.circle_members(circle_id,user_id) VALUES
  ('f0200000-0000-4000-9000-000000000001','f0200000-0000-4000-8000-000000000001'),
  ('f0200000-0000-4000-9000-000000000001','f0200000-0000-4000-8000-000000000002');
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
SELECT pg_temp.authz_denied($q$INSERT INTO public.circle_posts(circle_id,user_id,body_text,local_date,post_type) VALUES
  ('f0200000-0000-4000-9000-000000000001','f0200000-0000-4000-8000-000000000002','Impersonated',current_date::text,'checkin')$q$);
INSERT INTO public.circle_posts(circle_id,user_id,body_text,local_date,post_type) VALUES
  ('f0200000-0000-4000-9000-000000000001','f0200000-0000-4000-8000-000000000001','Own post',current_date::text,'checkin');
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000003');
SELECT pg_temp.authz_denied($q$INSERT INTO public.circle_posts(circle_id,user_id,body_text,local_date,post_type) VALUES
  ('f0200000-0000-4000-9000-000000000001','f0200000-0000-4000-8000-000000000003','Outsider',current_date::text,'checkin')$q$);
RESET ROLE;
SELECT pg_temp.authz_assert((SELECT count(*)=1 FROM public.circle_posts WHERE body_text='Own post'),'only genuine author admitted');
ROLLBACK;
\echo 'PASS circle post authorization'
