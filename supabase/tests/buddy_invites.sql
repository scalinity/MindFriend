-- Synthetic rollback fixture: a buddy code links both people, and the response is a set of
-- rows (PostgREST sends a set as a JSON array, which every released client decodes).
BEGIN;

INSERT INTO public.supported_languages(code,name,native_name,is_active) VALUES ('en','English','English',true) ON CONFLICT DO NOTHING;
INSERT INTO public.level_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO public.skill_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
SET LOCAL statement_timeout = '20s';
INSERT INTO auth.users(id, email, raw_user_meta_data) VALUES
 ('17500000-0000-4000-8000-000000000001', 'inviter@example.invalid', '{}'),
 ('17500000-0000-4000-8000-000000000002', 'invitee@example.invalid', '{}');
INSERT INTO public.profiles(id) VALUES
 ('17500000-0000-4000-8000-000000000001'), ('17500000-0000-4000-8000-000000000002') ON CONFLICT(id) DO NOTHING;

-- The 1.x flow: the app's row, and the function's second row when the email's case differed.
INSERT INTO public.buddy_relationships(id, inviter_id, invite_code, invite_method, invitee_contact, status, expires_at) VALUES
 ('17500000-0000-4000-8000-0000000000a1', '17500000-0000-4000-8000-000000000001', 'AAA111', 'email', 'Dad@Example.com', 'pending', now() + interval '30 days'),
 ('17500000-0000-4000-8000-0000000000a2', '17500000-0000-4000-8000-000000000001', 'BBB222', 'email', 'dad@example.com', 'pending', now() + interval '30 days');

DO $$
DECLARE accepted public.buddy_relationships; returned integer; members integer;
BEGIN
  IF NOT (SELECT proretset FROM pg_proc WHERE oid = 'public.accept_buddy_invite(text,uuid)'::regprocedure) THEN
    RAISE EXCEPTION 'accept_buddy_invite returns one composite, which PostgREST sends as an object';
  END IF;

  PERFORM set_config('request.jwt.claims', '{"sub":"17500000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  PERFORM set_config('request.jwt.claim.sub', '17500000-0000-4000-8000-000000000002', true);
  SELECT count(*) INTO returned FROM public.accept_buddy_invite('aaa111', '17500000-0000-4000-8000-000000000002');
  IF returned <> 1 THEN RAISE EXCEPTION 'Expected one accepted row, got %', returned; END IF;

  SELECT * INTO accepted FROM public.buddy_relationships WHERE id = '17500000-0000-4000-8000-0000000000a1';
  IF accepted.status <> 'accepted' OR accepted.invitee_id <> '17500000-0000-4000-8000-000000000002' THEN
    RAISE EXCEPTION 'Invite was not accepted: % %', accepted.status, accepted.invitee_id;
  END IF;
  SELECT count(*) INTO members FROM public.circle_members WHERE circle_id = accepted.buddy_circle_id
    AND user_id IN ('17500000-0000-4000-8000-000000000001', '17500000-0000-4000-8000-000000000002');
  IF members <> 2 THEN RAISE EXCEPTION 'Both people should share the buddy circle, got %', members; END IF;

  IF (SELECT status FROM public.buddy_relationships WHERE id = '17500000-0000-4000-8000-0000000000a2') <> 'expired' THEN
    RAISE EXCEPTION 'The duplicate invite to the same contact should expire';
  END IF;
END $$;

ROLLBACK;
