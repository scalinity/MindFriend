\ir support/authz_fixture.sql
INSERT INTO public.forum_categories(id,name) VALUES ('f0200000-0000-4000-9000-000000000001','Synthetic');
INSERT INTO public.forum_boards(id,category_id,name) VALUES
  ('f0200000-0000-4000-9000-000000000002','f0200000-0000-4000-9000-000000000001','Synthetic');
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
INSERT INTO public.forum_threads(id,board_id,author_id,title,content,status,moderation_confidence,is_crisis,updated_at,created_at)
VALUES ('f0200000-0000-4000-9000-000000000003','f0200000-0000-4000-9000-000000000002',auth.uid(),
  'Synthetic','Original','approved',1,true,'2000-01-01','2099-01-01');
INSERT INTO public.forum_replies(id,thread_id,author_id,content,status,moderation_confidence,is_crisis)
VALUES ('f0200000-0000-4000-9000-000000000004','f0200000-0000-4000-9000-000000000003',auth.uid(),'Reply','approved',1,true);
SELECT pg_temp.authz_assert((SELECT status='pending' AND moderation_confidence IS NULL AND NOT is_crisis
  AND updated_at>'2000-01-01' AND created_at<'2099-01-01' FROM public.forum_threads),'client insertion cannot approve or forge time');
SELECT pg_temp.authz_assert((SELECT status='pending' AND moderation_confidence IS NULL AND NOT is_crisis FROM public.forum_replies),'reply insertion cannot approve');
SELECT pg_temp.authz_denied($q$UPDATE public.forum_threads SET status='approved'$q$);
SELECT pg_temp.authz_denied($q$UPDATE public.forum_replies SET moderation_confidence=1,is_crisis=true$q$);
SELECT pg_temp.authz_denied($q$UPDATE public.forum_threads SET created_at='2099-01-01'$q$);
RESET ROLE;
CREATE TEMP TABLE original_revisions AS SELECT id,updated_at FROM public.forum_threads;
GRANT SELECT ON original_revisions TO authenticated,service_role;
SET LOCAL ROLE service_role;
SELECT pg_temp.authz_claims(NULL);
UPDATE public.forum_threads SET status='approved',moderation_confidence=0.9,is_crisis=true;
UPDATE public.forum_replies SET status='approved',moderation_confidence=0.9;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
UPDATE public.forum_threads SET content='Edited',updated_at='2000-01-01';
UPDATE public.forum_replies SET content='Edited reply';
SELECT pg_temp.authz_assert((SELECT status='pending' AND moderation_confidence IS NULL AND NOT is_crisis
  AND updated_at>(SELECT updated_at FROM original_revisions) FROM public.forum_threads),'edited thread invalidates decision and advances revision');
SELECT pg_temp.authz_assert((SELECT status='pending' AND moderation_confidence IS NULL FROM public.forum_replies),'edited reply invalidates decision');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.authz_claims(NULL);
DO $$ DECLARE changed integer; BEGIN
  UPDATE public.forum_threads SET status='approved' WHERE id='f0200000-0000-4000-9000-000000000003'
    AND updated_at=(SELECT updated_at FROM original_revisions) AND status='pending';
  GET DIAGNOSTICS changed=ROW_COUNT;
  PERFORM pg_temp.authz_assert(changed=0,'stale moderation must not approve edited content');
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000002');
SELECT set_config('request.jwt.claims','{"sub":"f0200000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"role":"moderator"}}',true);
UPDATE public.forum_threads SET status='approved';
SELECT pg_temp.authz_assert((SELECT status='approved' FROM public.forum_threads),'trusted moderator review remains available');
RESET ROLE;
ROLLBACK;
\echo 'PASS forum moderation authorization'
