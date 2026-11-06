BEGIN;
INSERT INTO auth.users(id) VALUES ('11111111-1111-4111-8111-111111111111'), ('22222222-2222-4222-8222-222222222222');
-- Model a historical row that existed before observation timestamps were introduced.
ALTER TABLE public.moods DISABLE TRIGGER stamp_mood_observation;
INSERT INTO public.moods(id,user_id,local_date,mood_score,observed_at)
VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','2026-10-30',4,NULL);
ALTER TABLE public.moods ENABLE TRIGGER stamp_mood_observation;
INSERT INTO public.quest_templates(id,title,description) VALUES
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','Companion fixture quest','Synthetic test');
INSERT INTO public.exercises(id,title,description,type,duration_minutes) VALUES
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','Companion fixture exercise','Synthetic test','breathing',1);
INSERT INTO public.quests(id,user_id,template_id,local_date)
VALUES ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','11111111-1111-4111-8111-111111111111','cccccccc-cccc-4ccc-8ccc-cccccccccccc','2026-11-01');
INSERT INTO public.exercise_sessions(id,user_id,exercise_id,completed_at) VALUES
 ('30000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','2026-11-02T04:59:00Z'),
 ('30000000-0000-4000-8000-000000000002','11111111-1111-4111-8111-111111111111','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','2026-11-02T05:01:00Z'),
 ('30000000-0000-4000-8000-000000000003','22222222-2222-4222-8222-222222222222','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','2026-11-01T18:00:00Z');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE
  owner uuid := auth.uid();
  action jsonb := jsonb_build_object('event_id','10000000-0000-4000-8000-000000000001','owner_id',auth.uid(),
    'kind','mood','observed_at','2026-11-01T14:00:00.123-05:00','local_date','2026-11-01','time_zone','America/New_York','mood_score',3);
  result jsonb;
  replay jsonb;
  count_before bigint;
BEGIN
  result := public.ingest_companion_action(action);
  replay := public.ingest_companion_action(action);
  ASSERT result = replay AND result->>'status' = 'applied', 'Exact replay must return the exact receipt';
  ASSERT (SELECT count(*) FROM public.moods WHERE local_date='2026-11-01') = 1, 'One daily row';
  ASSERT (SELECT count(*) FROM public.companion_actions) = 1, 'One action per event ID';
  BEGIN
    PERFORM public.ingest_companion_action(action || '{"mood_score":5}'::jsonb);
    RAISE EXCEPTION 'Changed replay was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.ingest_companion_action(action || '{"owner_id":"22222222-2222-4222-8222-222222222222"}'::jsonb);
    RAISE EXCEPTION 'Wrong account was accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;

  result := public.ingest_companion_action(action || '{"event_id":"10000000-0000-4000-8000-000000000002","observed_at":"2026-11-01T13:00:00-05:00","mood_score":1}'::jsonb);
  ASSERT result->>'status'='preserved_newer', 'An older offline mood cannot replace a newer check-in';
  ASSERT (SELECT mood_score FROM public.moods WHERE local_date='2026-11-01')=3;
  result := public.ingest_companion_action(action || '{"event_id":"10000000-0000-4000-8000-000000000003","observed_at":"2026-11-01T15:00:00-05:00","mood_score":5}'::jsonb);
  ASSERT result->>'status'='applied';
  ASSERT (SELECT mood_score FROM public.moods WHERE local_date='2026-11-01')=5;
  UPDATE public.moods SET mood_score=4, note='Keep the current app note' WHERE local_date='2026-11-01';
  result := public.ingest_companion_action(action || '{"event_id":"10000000-0000-4000-8000-000000000004","observed_at":"2026-11-01T16:00:00-05:00","mood_score":1}'::jsonb);
  ASSERT result->>'status'='preserved_newer', 'Normal app writes establish an observation time';
  ASSERT (SELECT mood_score=4 AND note='Keep the current app note' FROM public.moods WHERE local_date='2026-11-01');
  result := public.ingest_companion_action(action || '{"event_id":"10000000-0000-4000-8000-000000000005","observed_at":"2026-10-30T14:00:00-04:00","local_date":"2026-10-30","mood_score":1}'::jsonb);
  ASSERT result->>'status'='preserved_existing', 'Unknown historical ordering stays explicit';
  ASSERT (SELECT observed_at IS NULL AND mood_score=4 FROM public.moods WHERE local_date='2026-10-30');

  count_before := (SELECT count(*) FROM public.companion_actions);
  BEGIN
    PERFORM public.ingest_companion_action(action || '{"event_id":"10000000-0000-4000-8000-000000000006","local_date":"2026-11-02"}'::jsonb);
    RAISE EXCEPTION 'Mismatched local date was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  ASSERT (SELECT count(*) FROM public.companion_actions)=count_before, 'Rejected action leaves no receipt';
  BEGIN
    PERFORM public.ingest_companion_action((action - 'mood_score') || '{"event_id":"10000000-0000-4000-8000-000000000007","kind":"quest","quest_id":"dddddddd-dddd-4ddd-8ddd-dddddddddddd"}'::jsonb);
    RAISE EXCEPTION 'Unknown quest was accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  ASSERT (SELECT count(*) FROM public.companion_actions)=count_before, 'Failed effect rolls back receipt';
  result := public.ingest_companion_action((action - 'mood_score') || '{"event_id":"10000000-0000-4000-8000-000000000008","kind":"quest","quest_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}'::jsonb);
  ASSERT result->>'status'='applied';
  ASSERT (SELECT status='completed' FROM public.quests WHERE id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  result := public.ingest_companion_action((action - 'mood_score') || '{"event_id":"10000000-0000-4000-8000-000000000009","kind":"breathing","breathing_cycles":4}'::jsonb);
  ASSERT (public.get_companion_day_summary('2026-11-01','America/New_York')->>'breathing_count')::int=1;
  ASSERT (public.get_companion_day_summary('2026-11-01','America/New_York')->>'today_exercise_count')::int=1, '25-hour local day includes late evening only';
  ASSERT (public.get_companion_day_summary('2026-11-01','America/New_York')->>'weekly_exercise_count')::int=2, 'App and Watch exercise completions counted; other account and next day excluded';
  PERFORM public.ingest_companion_action((action - 'mood_score') || '{"event_id":"10000000-0000-4000-8000-000000000009","kind":"breathing","breathing_cycles":4}'::jsonb);
  ASSERT (public.get_companion_day_summary('2026-11-01','America/New_York')->>'breathing_count')::int=1, 'Breathing retry must not increment count';
  BEGIN
    UPDATE public.companion_actions SET status='applied';
    RAISE EXCEPTION 'Client receipt writes were accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END;
$$;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $$ BEGIN
  ASSERT (SELECT count(*) FROM public.companion_actions)=0, 'Another account cannot read action history';
  ASSERT (public.get_companion_day_summary('2026-11-01','America/New_York')->>'breathing_count')::int=0;
END; $$;
RESET ROLE;
ROLLBACK;
