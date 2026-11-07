\ir support/authz_fixture.sql

UPDATE auth.users SET email_confirmed_at=now()
WHERE id='f0200000-0000-4000-8000-000000000002';
INSERT INTO public.family_groups(id,admin_user_id,name) VALUES
 ('f0220000-0000-4000-8000-000000000001','f0200000-0000-4000-8000-000000000001','Synthetic family');
INSERT INTO public.family_invitations(family_id,email,invite_code,intended_birth_date) VALUES
 ('f0220000-0000-4000-8000-000000000001','AUTHZ-2@example.invalid','SYNTH-FAMILY-2','2015-01-01'),
 ('f0220000-0000-4000-8000-000000000001','authz-3@example.invalid','SYNTH-FAMILY-3','2016-01-01');
INSERT INTO public.organizations(id,name,billing_email) VALUES
 ('f0220000-0000-4000-8000-000000000002','Synthetic organization','authz-1@example.invalid');
INSERT INTO public.organization_admins(id,organization_id,user_id) VALUES
 ('f0220000-0000-4000-8000-000000000003','f0220000-0000-4000-8000-000000000002','f0200000-0000-4000-8000-000000000001');
INSERT INTO public.organization_invites(organization_id,created_by_admin_id,invite_code) VALUES
 ('f0220000-0000-4000-8000-000000000002','f0220000-0000-4000-8000-000000000003','SYNTH-ORG');

SET LOCAL ROLE anon;
SELECT pg_temp.authz_claims(NULL);
SELECT pg_temp.authz_denied('SELECT * FROM public.family_invitations');
SELECT pg_temp.authz_denied('SELECT * FROM public.organization_invites');
SELECT pg_temp.authz_denied('SELECT public.current_verified_invitation_email()');

SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims(NULL);
SELECT pg_temp.authz_assert((SELECT count(*)=0 FROM public.family_invitations), 'Missing identity cannot list invitations');
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000003');
SELECT pg_temp.authz_assert((SELECT count(*)=0 FROM public.family_invitations), 'Unverified recipient cannot list invitations');
SELECT pg_temp.authz_assert((SELECT count(*)=0 FROM public.organization_invites), 'Unrelated account cannot list organization codes');
-- User-editable metadata must not supply a recipient identity.
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f0200000-0000-4000-8000-000000000003',
 'role','authenticated','email','authz-2@example.invalid','user_metadata',jsonb_build_object('email','authz-2@example.invalid'))::text,true);
SELECT pg_temp.authz_assert((SELECT count(*)=0 FROM public.family_invitations), 'Token email does not override current verified Auth identity');
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000002');
SELECT pg_temp.authz_assert((SELECT count(*)=1 AND min(invite_code)='SYNTH-FAMILY-2'
 FROM public.family_invitations), 'Verified recipient sees only own invitation');
WITH changed AS (UPDATE public.family_invitations SET intended_role='parent' RETURNING id)
SELECT pg_temp.authz_assert(count(*)=0, 'Recipient cannot change invitation authority') FROM changed;
SELECT pg_temp.authz_assert((SELECT count(*)=0 FROM public.organization_invites), 'Recipient cannot list organization codes');
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
SELECT pg_temp.authz_assert((SELECT count(*)=2 FROM public.family_invitations), 'Family administrator sees managed invitations');
SELECT pg_temp.authz_assert((SELECT count(*)=1 FROM public.organization_invites), 'Organization administrator sees managed invitations');
INSERT INTO public.family_invitations(family_id,email,invite_code) VALUES
 ('f0220000-0000-4000-8000-000000000001','extra@example.invalid','SYNTH-FAMILY-EXTRA');
WITH changed AS (UPDATE public.family_invitations SET status='declined'
 WHERE invite_code='SYNTH-FAMILY-EXTRA' RETURNING id)
SELECT pg_temp.authz_assert(count(*)=1, 'Administrator can manage own invitations') FROM changed;

SET LOCAL ROLE service_role;
SELECT pg_temp.authz_claims(NULL);
SELECT pg_temp.authz_assert((SELECT count(*)=1 FROM public.family_invitations
 WHERE invite_code='SYNTH-FAMILY-2'), 'Service exact-code family lookup works');
SELECT pg_temp.authz_assert((SELECT count(*)=1 FROM public.organization_invites
 WHERE invite_code='SYNTH-ORG'), 'Service exact-code organization lookup works');
ROLLBACK;
\echo PASS invitation reader authorization
