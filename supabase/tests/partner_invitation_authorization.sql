\ir support/authz_fixture.sql

SET LOCAL ROLE anon;
SELECT pg_temp.authz_claims(NULL);
SELECT pg_temp.authz_denied($q$SELECT public.accept_partner_invite('f0200000-0000-4000-8000-000000000002','synthetic')$q$);
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
SELECT pg_temp.authz_denied($q$SELECT public.accept_partner_invite('f0200000-0000-4000-8000-000000000001','synthetic')$q$);
SELECT pg_temp.authz_denied($q$INSERT INTO public.partner_links(user_id_1,created_by,status)
 VALUES ('f0200000-0000-4000-8000-000000000002','f0200000-0000-4000-8000-000000000001','pending')$q$);

SET LOCAL ROLE service_role;
SELECT pg_temp.authz_claims(NULL);
SELECT pg_temp.authz_denied($q$SELECT public.accept_partner_invite(NULL,'synthetic')$q$);
DO $$
DECLARE
  low_id uuid := 'f0200000-0000-4000-8000-000000000001';
  high_id uuid := 'f0200000-0000-4000-8000-000000000002';
  other_id uuid := 'f0200000-0000-4000-8000-000000000003';
  inviter uuid;
  acceptor uuid;
  link_id uuid;
  result jsonb;
BEGIN
  PERFORM pg_temp.authz_assert(public.accept_partner_invite(high_id,'absent')->>'code'='NOT_FOUND', 'Unknown code rejected');
  FOREACH inviter IN ARRAY ARRAY[low_id,high_id] LOOP
    acceptor := CASE WHEN inviter=low_id THEN high_id ELSE low_id END;
    INSERT INTO public.partner_links(user_id_1,user_id_2,created_by,status,invite_code_hash,
      user_1_share_mood,user_1_share_exercises,user_2_share_mood,user_2_share_exercises)
    VALUES(inviter,NULL,inviter,'pending','synthetic-'||inviter,true,true,true,true)
    RETURNING id INTO link_id;
    PERFORM pg_temp.authz_assert(public.accept_partner_invite(inviter,'synthetic-'||inviter)->>'code'='SELF_INVITE', 'Self acceptance denied');
    result := public.accept_partner_invite(acceptor,'synthetic-'||inviter);
    PERFORM pg_temp.authz_assert((result->>'success')::boolean, 'Valid invitation accepted in both UUID orders');
    PERFORM pg_temp.authz_assert((result->>'partner_id')::uuid=inviter, 'Response identifies inviter after sorting');
    PERFORM pg_temp.authz_assert((SELECT user_id_1=low_id AND user_id_2=high_id AND status='active'
      AND created_by=inviter AND activated_at IS NOT NULL
      AND user_1_share_mood=(inviter=low_id) AND user_1_share_exercises=(inviter=low_id)
      AND user_2_share_mood=(inviter=high_id) AND user_2_share_exercises=(inviter=high_id)
      FROM public.partner_links WHERE id=link_id), 'Sorted identities preserve inviter consent and invitee starts private');
    PERFORM pg_temp.authz_assert(public.accept_partner_invite(acceptor,'synthetic-'||inviter)->>'code'='ALREADY_ACCEPTED', 'Replay rejected');
    INSERT INTO public.partner_links(user_id_1,created_by,status,invite_code_hash)
      VALUES(other_id,other_id,'pending','synthetic-other-'||inviter);
    PERFORM pg_temp.authz_assert(public.accept_partner_invite(acceptor,'synthetic-other-'||inviter)->>'code'='ACTIVE_PARTNERSHIP', 'Already partnered acceptor rejected');
    INSERT INTO public.partner_links(user_id_1,created_by,status,invite_code_hash)
      VALUES(inviter,inviter,'pending','synthetic-inviter-'||inviter);
    PERFORM pg_temp.authz_assert(public.accept_partner_invite(other_id,'synthetic-inviter-'||inviter)->>'code'='ACTIVE_PARTNERSHIP', 'Already partnered inviter rejected');
    DELETE FROM public.partner_links;
  END LOOP;
  INSERT INTO public.partner_links(user_id_1,created_by,status,invite_code_hash,expires_at)
    VALUES(low_id,low_id,'pending','synthetic-expired',now()-interval '1 second');
  PERFORM pg_temp.authz_assert(public.accept_partner_invite(high_id,'synthetic-expired')->>'code'='EXPIRED', 'Expired invitation rejected');
  PERFORM pg_temp.authz_assert((SELECT count(*)=1 FROM public.partner_links WHERE status='pending' AND user_id_2 IS NULL), 'Invalid acceptance leaves invitation unchanged');
END $$;
ROLLBACK;
\echo PASS partner invitation authorization and directional consent
