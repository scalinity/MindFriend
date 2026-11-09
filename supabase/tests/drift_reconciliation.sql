-- Regressions for 20261106000000_reconcile_production_drift.sql. Run after the full migration
-- chain in an empty disposable restoration_synthetic database. Synthetic rows only; rolls back.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database() <> 'restoration_synthetic' OR EXISTS (SELECT FROM auth.users) THEN
    RAISE EXCEPTION 'Requires empty restoration_synthetic fixture';
  END IF;
END $$;
INSERT INTO auth.users(id,aud,role,email,raw_user_meta_data,created_at,updated_at) VALUES
 ('d1000000-0000-4000-8000-000000000001','authenticated','authenticated','drift-mentee@example.invalid','{}',now(),now()),
 ('d1000000-0000-4000-8000-000000000002','authenticated','authenticated','drift-mentor@example.invalid','{}',now(),now()),
 ('d1000000-0000-4000-8000-000000000003','authenticated','authenticated','drift-other@example.invalid','{}',now(),now());
INSERT INTO public.mentorship_matches(id,mentor_id,mentee_id,status,mentor_alias,mentee_alias) VALUES
 ('d2000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000002','d1000000-0000-4000-8000-000000000001','pending','Synthetic mentor','Synthetic mentee'),
 ('d2000000-0000-4000-8000-000000000002','d1000000-0000-4000-8000-000000000002','d1000000-0000-4000-8000-000000000001','active','Synthetic mentor','Synthetic mentee');

-- Anonymous callers cannot read another user's dashboard (fail closed on a null uid).
SET LOCAL ROLE anon;
DO $$ BEGIN
  PERFORM public.get_social_vitality_dashboard('d1000000-0000-4000-8000-000000000001');
  RAISE EXCEPTION 'Anonymous dashboard read accepted';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='d1000000-0000-4000-8000-000000000001';
SET LOCAL request.jwt.claim.role='authenticated';
-- Service-only functions are not callable by clients.
DO $$ BEGIN
  PERFORM public.get_prediction_features('d1000000-0000-4000-8000-000000000003');
  RAISE EXCEPTION 'Client called get_prediction_features';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
-- A mentee cannot accept, rewrite mentor fields, or delete the pending request.
DO $$ BEGIN
  BEGIN
    UPDATE public.mentorship_matches SET status='active' WHERE id='d2000000-0000-4000-8000-000000000001';
    RAISE EXCEPTION 'Mentee accepted their own request';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    UPDATE public.mentorship_matches SET mentor_response='Forged' WHERE id='d2000000-0000-4000-8000-000000000001';
    RAISE EXCEPTION 'Mentee wrote the mentor response';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  DELETE FROM public.mentorship_matches WHERE id='d2000000-0000-4000-8000-000000000001';
  IF FOUND THEN RAISE EXCEPTION 'Mentee deleted the pending request'; END IF;
  DELETE FROM public.mentorship_matches WHERE id='d2000000-0000-4000-8000-000000000002';
  IF FOUND THEN RAISE EXCEPTION 'Participant deleted an active mentorship'; END IF;
END $$;
-- Direct inserts are rate limited: the sixth message within a minute is refused.
DO $$ DECLARE i int; BEGIN
  FOR i IN 1..5 LOOP
    INSERT INTO public.mentorship_messages(match_id,sender_id,content)
    VALUES ('d2000000-0000-4000-8000-000000000002',auth.uid(),'Synthetic message '||i);
  END LOOP;
  BEGIN
    INSERT INTO public.mentorship_messages(match_id,sender_id,content)
    VALUES ('d2000000-0000-4000-8000-000000000002',auth.uid(),'Synthetic message 6');
    RAISE EXCEPTION 'Rate limit bypassed by a direct insert';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
-- The recipient may mark read; nobody may change a message's id or content.
SET LOCAL request.jwt.claim.sub='d1000000-0000-4000-8000-000000000002';
DO $$ DECLARE target uuid := (SELECT id FROM public.mentorship_messages LIMIT 1); BEGIN
  UPDATE public.mentorship_messages SET read_at=now() WHERE id=target;
  IF NOT FOUND THEN RAISE EXCEPTION 'Recipient could not mark read'; END IF;
  BEGIN
    UPDATE public.mentorship_messages SET id=gen_random_uuid() WHERE id=target;
    RAISE EXCEPTION 'Message id changed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    UPDATE public.mentorship_messages SET content='Rewritten' WHERE id=target;
    RAISE EXCEPTION 'Message content changed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
-- The mentor accepts the pending request and can decline (delete) only while it is pending.
DO $$ BEGIN
  UPDATE public.mentorship_matches SET status='active' WHERE id='d2000000-0000-4000-8000-000000000001';
  IF NOT FOUND THEN RAISE EXCEPTION 'Mentor could not accept'; END IF;
  DELETE FROM public.mentorship_matches WHERE id='d2000000-0000-4000-8000-000000000001';
  IF FOUND THEN RAISE EXCEPTION 'Mentor deleted an accepted mentorship'; END IF;
END $$;
-- Either participant may end an active mentorship; a closed one stays closed.
SET LOCAL request.jwt.claim.sub='d1000000-0000-4000-8000-000000000001';
DO $$ BEGIN
  UPDATE public.mentorship_matches SET status='completed', ended_at=now(), end_reason='Synthetic end'
  WHERE id='d2000000-0000-4000-8000-000000000002';
  IF NOT FOUND THEN RAISE EXCEPTION 'Participant could not end the mentorship'; END IF;
  BEGIN
    UPDATE public.mentorship_matches SET status='active' WHERE id='d2000000-0000-4000-8000-000000000002';
    RAISE EXCEPTION 'Closed mentorship reopened';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;

-- The prediction feature query runs against the real columns.
SET LOCAL ROLE service_role;
DO $$ BEGIN
  IF public.get_prediction_features('d1000000-0000-4000-8000-000000000001') IS NULL THEN
    RAISE EXCEPTION 'Prediction features returned nothing';
  END IF;
END $$;
RESET ROLE;
-- A valid 6-10 mood is saved even when a prediction is pending for that day.
INSERT INTO public.mood_predictions(user_id,predicted_for,predicted_mood,confidence)
VALUES ('d1000000-0000-4000-8000-000000000003',current_date,7,0.5);
INSERT INTO public.moods(user_id,mood_score,local_date) VALUES ('d1000000-0000-4000-8000-000000000003',8,current_date);
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM public.moods WHERE user_id='d1000000-0000-4000-8000-000000000003' AND mood_score=8) THEN
    RAISE EXCEPTION 'Mood rejected by prediction bookkeeping';
  END IF;
  IF (SELECT actual_mood FROM public.mood_predictions WHERE user_id='d1000000-0000-4000-8000-000000000003') <> 10 THEN
    RAISE EXCEPTION 'Prediction actual mood not clamped to the 1-10 range';
  END IF;
END $$;
ROLLBACK;
