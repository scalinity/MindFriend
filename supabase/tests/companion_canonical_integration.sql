\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database() <> 'restoration_synthetic' OR EXISTS (SELECT FROM auth.users) THEN
    RAISE EXCEPTION 'Requires the empty owned restoration_synthetic database';
  END IF;
END $$;
INSERT INTO public.supported_languages(code,name,native_name,is_active) VALUES ('en','English','English',true) ON CONFLICT DO NOTHING;
INSERT INTO public.level_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO public.skill_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO auth.users(id,aud,role,email,raw_user_meta_data,created_at,updated_at) VALUES
 ('f0800000-0000-4000-8000-000000000001','authenticated','authenticated','cross-a@example.invalid','{}',now(),now()),
 ('f0800000-0000-4000-8000-000000000002','authenticated','authenticated','cross-b@example.invalid','{}',now(),now());
INSERT INTO public.quest_templates(id,title,description) VALUES ('f0800000-0000-4000-8000-000000000010','Cross-path quest','Synthetic');
INSERT INTO public.quests(id,user_id,template_id,local_date,status,assigned_at)
SELECT ('f0800000-0000-4000-8000-' || lpad((20+n)::text,12,'0'))::uuid,
 'f0800000-0000-4000-8000-000000000001','f0800000-0000-4000-8000-000000000010',
 (current_date-n)::text,'assigned',(current_date-n)::timestamptz FROM generate_series(1,2) n;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.role = 'authenticated';
SET LOCAL request.jwt.claim.sub = 'f0800000-0000-4000-8000-000000000001';
DO $$
DECLARE
 owner uuid := auth.uid(); day date; older timestamptz; newer timestamptz;
 watch jsonb; phone jsonb; reply jsonb; i integer; before_xp integer;
 quest uuid; receipt jsonb;
BEGIN
 FOR i IN 1..4 LOOP
  day := current_date - i;
  older := day::timestamptz + interval '12 hours'; newer := day::timestamptz + interval '13 hours';
  watch := jsonb_build_object('event_id',('f0800000-0000-4000-8000-' || lpad((100+i)::text,12,'0'))::uuid,
   'owner_id',owner,'kind','mood','observed_at',CASE WHEN i IN (1,4) THEN older ELSE newer END,
   'local_date',day,'time_zone','UTC','mood_score',5);
  phone := jsonb_build_object('schema_version',1,'mood_score',4,'note','Synthetic phone note',
   'recorded_at_ms',(extract(epoch FROM CASE WHEN i IN (1,4) THEN newer ELSE older END)*1000)::bigint,'local_date',day);
  SELECT xp_total INTO before_xp FROM public.user_stats WHERE user_id=owner;
  IF i IN (1,3) THEN
   PERFORM public.ingest_companion_action(watch);
   reply := public.sync_offline_mutation(owner,('f0800000-0000-4000-8000-' || lpad((200+i)::text,12,'0'))::uuid,'mood',phone);
   ASSERT reply->'result'->>'outcome'=CASE WHEN i=1 THEN 'updated' ELSE 'kept_existing' END;
  ELSE
   PERFORM public.sync_offline_mutation(owner,('f0800000-0000-4000-8000-' || lpad((200+i)::text,12,'0'))::uuid,'mood',phone);
   reply := public.ingest_companion_action(watch);
   ASSERT reply->>'status'=CASE WHEN i=2 THEN 'applied' ELSE 'preserved_newer' END;
  END IF;
  ASSERT (SELECT last_event_at=newer AND observed_at=newer AND mood_score=CASE WHEN i IN (1,4) THEN 4 ELSE 5 END
   FROM public.moods WHERE user_id=owner AND local_date=day), 'Original event time must win across both paths';
  ASSERT (SELECT xp_total=before_xp+10 FROM public.user_stats WHERE user_id=owner), 'One daily mood reward across phone and companion';
  IF i=2 THEN
   ASSERT (SELECT note='Synthetic phone note' FROM public.moods WHERE user_id=owner AND local_date=day), 'Watch score must preserve phone note';
  END IF;
  PERFORM public.ingest_companion_action(watch);
  ASSERT (SELECT xp_total=before_xp+10 FROM public.user_stats WHERE user_id=owner), 'Companion replay cannot pay again';
 END LOOP;
 FOR i IN 1..2 LOOP
  day := current_date-i; quest := ('f0800000-0000-4000-8000-' || lpad((20+i)::text,12,'0'))::uuid;
  watch := jsonb_build_object('event_id',('f0800000-0000-4000-8000-' || lpad((300+i)::text,12,'0'))::uuid,
   'owner_id',owner,'kind','quest','quest_id',quest,'observed_at',day::timestamptz+interval '14 hours',
   'local_date',day,'time_zone','UTC');
  SELECT xp_total INTO before_xp FROM public.user_stats WHERE user_id=owner;
  IF i=1 THEN
   receipt := public.ingest_companion_action(watch);
   reply := public.complete_quest_with_reward(owner,quest,'Synthetic later reflection',4);
   ASSERT (reply->>'xp_awarded')::integer=0;
  ELSE
   reply := public.complete_quest_with_reward(owner,quest,'Synthetic first reflection',4);
   ASSERT (reply->>'xp_awarded')::integer=50;
   receipt := public.ingest_companion_action(watch);
  END IF;
  ASSERT receipt->>'status'='applied';
  ASSERT (SELECT xp_total=before_xp+50 FROM public.user_stats WHERE user_id=owner), 'Exactly one quest reward across both writers';
  ASSERT (SELECT status='completed' AND reflection_note IS NOT NULL AND rating=4 FROM public.quests WHERE id=quest), 'Completion and reflection retained';
  ASSERT public.ingest_companion_action(watch)=receipt, 'Exact replay keeps receipt';
  ASSERT (SELECT xp_total=before_xp+50 FROM public.user_stats WHERE user_id=owner), 'Quest replay cannot pay twice';
 END LOOP;
END $$;
RESET ROLE;
DO $$ BEGIN
 ASSERT (SELECT xp_total=0 FROM public.user_stats WHERE user_id='f0800000-0000-4000-8000-000000000002'), 'Other owner remains unchanged';
END $$;
ROLLBACK;
