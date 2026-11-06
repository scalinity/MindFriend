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
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
SET LOCAL request.jwt.claim.role='authenticated';
DO $$ BEGIN
  IF NOT public.end_mentorship('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Synthetic completion') THEN
    RAISE EXCEPTION 'End was not confirmed';
  END IF;
  IF NOT EXISTS (SELECT FROM public.mentorship_matches WHERE id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
                 AND status='ended' AND ended_at IS NOT NULL AND end_reason='Synthetic completion') THEN
    RAISE EXCEPTION 'Relationship still active';
  END IF;
END $$;
SET LOCAL request.jwt.claim.sub='33333333-3333-4333-8333-333333333333';
DO $$ BEGIN
  BEGIN
    PERFORM public.end_mentorship('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Not authorized');
    RAISE EXCEPTION 'Nonparticipant end accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Match not found or not authorized' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK;
