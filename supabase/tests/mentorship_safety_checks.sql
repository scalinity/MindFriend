\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database() <> 'restoration_synthetic' OR EXISTS (SELECT FROM auth.users) THEN
    RAISE EXCEPTION 'Requires empty restoration_synthetic fixture';
  END IF;
END $$;
INSERT INTO auth.users(id,aud,role,email,raw_user_meta_data,created_at,updated_at) VALUES
 ('11111111-1111-4111-8111-111111111111','authenticated','authenticated','mentee@example.invalid','{}',now(),now()),
 ('22222222-2222-4222-8222-222222222222','authenticated','authenticated','mentor@example.invalid','{}',now(),now()),
 ('33333333-3333-4333-8333-333333333333','authenticated','authenticated','outsider@example.invalid','{}',now(),now());
INSERT INTO public.mentorship_matches(id,mentor_id,mentee_id,status,mentor_alias,mentee_alias) VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','active','Synthetic mentor','Synthetic mentee');
INSERT INTO public.mentorship_messages(id,match_id,sender_id,content) VALUES
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','Synthetic critical'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','Synthetic safe'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','Synthetic failure');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims='{"role":"authenticated","sub":"11111111-1111-4111-8111-111111111111"}';
DO $$ BEGIN
  BEGIN
    PERFORM public.record_mentorship_safety_check('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','Synthetic critical',ARRAY['synthetic'],'critical');
    RAISE EXCEPTION 'Client could invoke privileged check';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM id FROM public.mentorship_escalations;
    RAISE EXCEPTION 'Client could read private escalation records';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;
-- Exercise the column guard independently of the existing participant UPDATE policy.
DO $$ BEGIN
  BEGIN
    UPDATE public.mentorship_messages SET safety_checked_at=now() WHERE id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1';
    RAISE EXCEPTION 'Client claims could bypass the checker';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
CREATE FUNCTION pg_temp.reject_synthetic_escalation() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
  IF NEW.message_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3' THEN RAISE EXCEPTION 'Synthetic persistence failure'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER synthetic_escalation_failure BEFORE INSERT ON public.mentorship_escalations
  FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_synthetic_escalation();
SET LOCAL ROLE service_role;
SET LOCAL request.jwt.claims='{"role":"service_role"}';
DO $$ BEGIN
  IF public.record_mentorship_safety_check('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','Old content',ARRAY['synthetic'],'critical') THEN
    RAISE EXCEPTION 'Stale analyzed content accepted';
  END IF;
  IF NOT public.record_mentorship_safety_check('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','Synthetic critical',ARRAY['Synthetic crisis signal'],'critical') THEN
    RAISE EXCEPTION 'Valid check not saved';
  END IF;
  IF public.record_mentorship_safety_check('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','Synthetic critical',ARRAY['Synthetic crisis signal'],'critical') THEN
    RAISE EXCEPTION 'Retry counted a duplicate check';
  END IF;
  IF NOT EXISTS (SELECT FROM public.mentorship_messages WHERE id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
    AND flagged AND safety_checked_at IS NOT NULL AND flag_reason='Synthetic crisis signal') THEN RAISE EXCEPTION 'Flag not persisted'; END IF;
  IF (SELECT count(*) FROM public.mentorship_escalations)<>1 OR NOT EXISTS (
    SELECT FROM public.mentorship_escalations WHERE message_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
      AND match_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' AND sender_id='11111111-1111-4111-8111-111111111111'
      AND severity='critical' AND status='pending' AND reasons=ARRAY['Synthetic crisis signal']) THEN
    RAISE EXCEPTION 'Escalation identity or idempotency failed';
  END IF;
  PERFORM public.record_mentorship_safety_check('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2','Synthetic safe',ARRAY[]::text[],'low');
  IF NOT EXISTS (SELECT FROM public.mentorship_messages WHERE id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2'
    AND NOT flagged AND safety_checked_at IS NOT NULL) THEN RAISE EXCEPTION 'Safe message never leaves the batch'; END IF;
  BEGIN
    PERFORM public.record_mentorship_safety_check('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3','Synthetic failure',ARRAY['Synthetic crisis signal'],'critical');
    RAISE EXCEPTION 'Synthetic escalation failure was swallowed';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Synthetic persistence failure' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT FROM public.mentorship_messages WHERE id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3'
    AND (flagged OR safety_checked_at IS NOT NULL)) THEN RAISE EXCEPTION 'Failed escalation incorrectly marked checked'; END IF;
END $$;
ROLLBACK;
