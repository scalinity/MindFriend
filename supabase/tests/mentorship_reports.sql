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
DO $$ DECLARE report_id uuid; BEGIN
  report_id := public.report_mentorship_issue('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '22222222-2222-4222-8222-222222222222','boundary_violation','Synthetic concern');
  IF NOT EXISTS (SELECT FROM public.mentorship_reports WHERE id=report_id
      AND reporter_id=auth.uid() AND reported_id='22222222-2222-4222-8222-222222222222'
      AND reason='boundary_violation' AND status='pending' AND description='Synthetic concern') THEN
    RAISE EXCEPTION 'Report was not persisted with correct identities';
  END IF;
  BEGIN
    PERFORM public.report_mentorship_issue('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',auth.uid(),'other','');
    RAISE EXCEPTION 'Self report accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Cannot report yourself' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.report_mentorship_issue('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      '33333333-3333-4333-8333-333333333333','other','');
    RAISE EXCEPTION 'Unrelated subject accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Reported user is not a participant in this mentorship' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.report_mentorship_issue('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      '22222222-2222-4222-8222-222222222222','Boundary violations','');
    RAISE EXCEPTION 'Display label accepted as database reason';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;
SET LOCAL request.jwt.claim.sub='33333333-3333-4333-8333-333333333333';
DO $$ BEGIN
  BEGIN
    PERFORM public.report_mentorship_issue('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      '22222222-2222-4222-8222-222222222222','other','');
    RAISE EXCEPTION 'Nonparticipant report accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'You are not a participant in this mentorship' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK;
