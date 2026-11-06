\ir support/authz_fixture.sql

INSERT INTO public.partner_links(id,user_id_1,user_id_2,created_by,status)
VALUES ('f0210000-0000-4000-8000-000000000001',
 'f0200000-0000-4000-8000-000000000001',
 'f0200000-0000-4000-8000-000000000002',
 'f0200000-0000-4000-8000-000000000001','active');

SET LOCAL ROLE anon;
SELECT pg_temp.authz_claims(NULL);
SELECT pg_temp.authz_denied('UPDATE public.partner_links SET user_2_share_mood=true');
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
SELECT pg_temp.authz_assert((SELECT count(*)=1 FROM public.partner_links), 'Participant reads own link');
SELECT pg_temp.authz_denied('UPDATE public.partner_links SET user_2_share_mood=true');
SELECT pg_temp.authz_denied('UPDATE public.partner_links SET user_1_share_mood=true');
SELECT pg_temp.authz_denied($q$UPDATE public.partner_links SET user_id_2='f0200000-0000-4000-8000-000000000003'$q$);
SELECT pg_temp.authz_denied($q$UPDATE public.partner_links SET status='ended'$q$);
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000003');
SELECT pg_temp.authz_assert((SELECT count(*)=0 FROM public.partner_links), 'Outsider cannot read partnership');

SET LOCAL ROLE service_role;
SELECT pg_temp.authz_claims(NULL);
UPDATE public.partner_links SET user_1_share_mood=true
WHERE id='f0210000-0000-4000-8000-000000000001';
SELECT pg_temp.authz_assert((SELECT user_1_share_mood AND NOT user_2_share_mood
 FROM public.partner_links), 'Service updates selected consent only');
UPDATE public.partner_links SET status='ended',ended_at=now()
WHERE id='f0210000-0000-4000-8000-000000000001';
SELECT pg_temp.authz_assert((SELECT status='ended' AND ended_at IS NOT NULL
 FROM public.partner_links), 'Service can unlink');
ROLLBACK;
\echo PASS partnership update authorization
