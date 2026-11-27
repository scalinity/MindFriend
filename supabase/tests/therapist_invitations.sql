-- Synthetic rollback fixture: therapist-invite stores only a SHA-256 hash of the invitation token,
-- therapist-accept finds the invitation by that hash and clears it, only the two parties can read
-- the row, and the raw token write of the old deployed copy (v26) is refused.
BEGIN;

INSERT INTO public.supported_languages(code,name,native_name,is_active) VALUES ('en','English','English',true) ON CONFLICT DO NOTHING;
INSERT INTO public.level_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO public.skill_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
SET LOCAL statement_timeout = '20s';
INSERT INTO auth.users(id, email, raw_user_meta_data) VALUES
 ('17600000-0000-4000-8000-000000000001', 'client@example.invalid', '{}'),
 ('17600000-0000-4000-8000-000000000002', 'therapist@example.invalid', '{}'),
 ('17600000-0000-4000-8000-000000000003', 'other@example.invalid', '{}');
INSERT INTO public.profiles(id) VALUES
 ('17600000-0000-4000-8000-000000000001'), ('17600000-0000-4000-8000-000000000002'),
 ('17600000-0000-4000-8000-000000000003') ON CONFLICT(id) DO NOTHING;
INSERT INTO public.therapist_accounts(id, user_id) VALUES
 ('17600000-0000-4000-8000-0000000000a1', '17600000-0000-4000-8000-000000000002');

-- therapist-invite's upsert, as the service role: the first invitation, then a new one after the
-- client revoked it. The second replaces the first hash on the same row.
SET LOCAL ROLE service_role;
INSERT INTO public.therapy_connections(client_id, therapist_id, status, invited_by, invitation_token_hash, invitation_expires_at, invited_at)
VALUES ('17600000-0000-4000-8000-000000000001', '17600000-0000-4000-8000-0000000000a1', 'pending', 'client',
        encode(sha256('synthetic-token-1'::bytea), 'hex'), now() + interval '7 days', now())
ON CONFLICT (client_id, therapist_id) DO UPDATE SET status = EXCLUDED.status, invited_by = EXCLUDED.invited_by,
  invitation_token_hash = EXCLUDED.invitation_token_hash, invitation_expires_at = EXCLUDED.invitation_expires_at,
  invited_at = EXCLUDED.invited_at;
UPDATE public.therapy_connections SET status = 'revoked', ended_at = now()
WHERE client_id = '17600000-0000-4000-8000-000000000001';
INSERT INTO public.therapy_connections(client_id, therapist_id, status, invited_by, invitation_token_hash, invitation_expires_at, invited_at)
VALUES ('17600000-0000-4000-8000-000000000001', '17600000-0000-4000-8000-0000000000a1', 'pending', 'client',
        encode(sha256('synthetic-token-2'::bytea), 'hex'), now() + interval '7 days', now())
ON CONFLICT (client_id, therapist_id) DO UPDATE SET status = EXCLUDED.status, invited_by = EXCLUDED.invited_by,
  invitation_token_hash = EXCLUDED.invitation_token_hash, invitation_expires_at = EXCLUDED.invitation_expires_at,
  invited_at = EXCLUDED.invited_at;

DO $$
DECLARE rows integer;
BEGIN
  SELECT count(*) INTO rows FROM public.therapy_connections
  WHERE client_id = '17600000-0000-4000-8000-000000000001' AND status = 'pending' AND invitation_token IS NULL
    AND invitation_token_hash = encode(sha256('synthetic-token-2'::bytea), 'hex');
  IF rows <> 1 THEN RAISE EXCEPTION 'Expected one pending invitation holding the second hash, got %', rows; END IF;

  -- The old deployed copy's write: the raw token itself.
  BEGIN
    INSERT INTO public.therapy_connections(client_id, therapist_id, status, invited_by, invitation_token, invitation_expires_at, invited_at)
    VALUES ('17600000-0000-4000-8000-000000000001', '17600000-0000-4000-8000-0000000000a1', 'pending', 'client',
            'synthetic-token-3', now() + interval '7 days', now())
    ON CONFLICT (client_id, therapist_id) DO UPDATE SET invitation_token = EXCLUDED.invitation_token;
    RAISE EXCEPTION 'A raw invitation token was stored';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;

-- Reads through RLS: the client and the therapist see the invitation, another person does not.
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$
DECLARE person text; visible integer; expected integer;
BEGIN
  FOREACH person IN ARRAY ARRAY['17600000-0000-4000-8000-000000000001', '17600000-0000-4000-8000-000000000002',
                                '17600000-0000-4000-8000-000000000003'] LOOP
    PERFORM set_config('request.jwt.claims', json_build_object('sub', person, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', person, true);
    SELECT count(*) INTO visible FROM public.therapy_connections WHERE invitation_token_hash IS NOT NULL;
    expected := CASE WHEN person LIKE '%3' THEN 0 ELSE 1 END;
    IF visible <> expected THEN
      RAISE EXCEPTION 'Person % sees % invitations', person, visible;
    END IF;
  END LOOP;
END $$;

-- therapist-accept, as the service role: the second token's hash matches, the first one's does not,
-- and acceptance clears the hash so the link cannot be used again.
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$
DECLARE matched integer;
BEGIN
  SELECT count(*) INTO matched FROM public.therapy_connections
  WHERE client_id = '17600000-0000-4000-8000-000000000001' AND therapist_id = '17600000-0000-4000-8000-0000000000a1'
    AND invitation_token_hash = encode(sha256('synthetic-token-1'::bytea), 'hex');
  IF matched <> 0 THEN RAISE EXCEPTION 'The replaced invitation still matches'; END IF;

  UPDATE public.therapy_connections SET status = 'active', connected_at = now(), invitation_token_hash = NULL,
    invitation_token = NULL, invitation_expires_at = NULL
  WHERE client_id = '17600000-0000-4000-8000-000000000001' AND therapist_id = '17600000-0000-4000-8000-0000000000a1'
    AND invitation_token_hash = encode(sha256('synthetic-token-2'::bytea), 'hex');
  GET DIAGNOSTICS matched = ROW_COUNT;
  IF matched <> 1 THEN RAISE EXCEPTION 'Acceptance updated % rows', matched; END IF;

  IF EXISTS (SELECT 1 FROM public.therapy_connections WHERE client_id = '17600000-0000-4000-8000-000000000001'
             AND (status <> 'active' OR invitation_token_hash IS NOT NULL)) THEN
    RAISE EXCEPTION 'The accepted connection kept its token hash or status';
  END IF;
END $$;

ROLLBACK;
