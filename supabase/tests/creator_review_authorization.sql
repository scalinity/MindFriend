\ir support/authz_fixture.sql
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
SELECT pg_temp.authz_denied($q$INSERT INTO public.creators(user_id,display_name,status) VALUES (auth.uid(),'Synthetic','approved')$q$);
INSERT INTO public.creators(user_id,display_name) VALUES (auth.uid(),'Synthetic');
UPDATE public.creators SET bio='Editable profile' WHERE user_id=auth.uid();
SELECT pg_temp.authz_denied($q$UPDATE public.creators SET status='approved',verification_level='expert',payout_enabled=true,tax_info_complete=true WHERE user_id=auth.uid()$q$);
SELECT pg_temp.authz_denied($q$UPDATE public.creators SET stripe_account_id='forged-account' WHERE user_id=auth.uid()$q$);
SELECT pg_temp.authz_denied($q$INSERT INTO public.creator_content(creator_id,content_type,format,title,category,status)
  SELECT id,'meditation','audio','Forged publication','mindfulness','published' FROM public.creators WHERE user_id=auth.uid()$q$);
INSERT INTO public.creator_content(creator_id,content_type,format,title,category,status)
  SELECT id,'meditation','audio','Draft','mindfulness','draft' FROM public.creators WHERE user_id=auth.uid();
UPDATE public.creator_content SET title='Editable draft';
SELECT pg_temp.authz_denied($q$UPDATE public.creator_content SET status='published',published_at=now()$q$);
SELECT pg_temp.authz_denied($q$UPDATE public.creator_content SET reviewed_at=now(),is_featured=true,play_count=1000$q$);
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.authz_claims(NULL);
UPDATE public.creators SET status='approved',verification_level='verified',payout_enabled=true;
UPDATE public.creator_content SET status='submitted',submitted_at=now();
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
SELECT pg_temp.authz_denied($q$UPDATE public.creator_content SET title='Changed during review'$q$);
RESET ROLE;
SET LOCAL ROLE service_role;
UPDATE public.creator_content SET status='needs_changes',reviewed_at=now();
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
UPDATE public.creator_content SET title='Revised returned draft';
SELECT pg_temp.authz_assert((SELECT status='draft' AND submitted_at IS NULL AND reviewed_at IS NULL FROM public.creator_content),'returned draft requires fresh review');
RESET ROLE;
SET LOCAL ROLE service_role;
UPDATE public.creator_content SET status='published',published_at=now();
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
SELECT pg_temp.authz_denied($q$UPDATE public.creator_content SET media_url='https://example.invalid/unreviewed'$q$);
SELECT pg_temp.authz_assert((SELECT status='published' FROM public.creator_content),'trusted publication retained');
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000002');
INSERT INTO public.creator_followers(creator_id,user_id) SELECT id,auth.uid() FROM public.creators;
INSERT INTO public.content_ratings(content_id,user_id,rating) SELECT id,auth.uid(),5 FROM public.creator_content;
RESET ROLE;
SELECT pg_temp.authz_assert((SELECT follower_count=1 AND content_count=1 FROM public.creators),'trusted counters remain functional');
SELECT pg_temp.authz_assert((SELECT rating_count=1 AND average_rating=5 FROM public.creator_content),'trusted rating aggregate retained');
ROLLBACK;
\echo 'PASS creator review authorization'
