\set ON_ERROR_STOP on
BEGIN;
-- Synthetic-only fixture: never run against a database containing account data.
DO $$ BEGIN
  IF current_database() <> 'restoration_synthetic' OR EXISTS (SELECT FROM auth.users) THEN
    RAISE EXCEPTION 'This test requires the empty restoration_synthetic database';
  END IF;
END $$;

INSERT INTO public.supported_languages(code,name,native_name,is_active)
VALUES ('en','English','English',true) ON CONFLICT DO NOTHING;
INSERT INTO public.level_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO public.skill_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO auth.users (id,aud,role,email,raw_user_meta_data,created_at,updated_at) VALUES
 ('11111111-1111-4111-8111-111111111111','authenticated','authenticated','receipts-a@example.invalid','{}',now(),now()),
 ('22222222-2222-4222-8222-222222222222','authenticated','authenticated','receipts-b@example.invalid','{}',now(),now()),
 ('33333333-3333-4333-8333-333333333333','authenticated','authenticated','receipts-c@example.invalid','{}',now(),now());
INSERT INTO public.exercises (id,type,title,description,duration_seconds,duration_minutes) VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','breathing','Synthetic breathing','Synthetic exercise',60,1);
INSERT INTO public.quest_templates (id,title,description) VALUES
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1','Synthetic quest','Synthetic');
INSERT INTO public.quests (id,user_id,template_id,local_date,status) VALUES
 ('f0000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1','2026-11-01','assigned'),
 ('f0000000-0000-4000-8000-000000000002','11111111-1111-4111-8111-111111111111','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1','2026-11-02','skipped'),
 ('f0000000-0000-4000-8000-0000000000b1','22222222-2222-4222-8222-222222222222','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1','2026-11-01','assigned'),
 ('f0000000-0000-4000-8000-000000000003','11111111-1111-4111-8111-111111111111','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1','2026-11-03','assigned'),
 ('f0000000-0000-4000-8000-0000000000c1','33333333-3333-4333-8333-333333333333','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1','2026-10-10','assigned'),
 ('f0000000-0000-4000-8000-0000000000c2','33333333-3333-4333-8333-333333333333','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1','2026-10-11','assigned'),
 ('f0000000-0000-4000-8000-0000000000c3','33333333-3333-4333-8333-333333333333','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1','2026-10-12','assigned'),
 ('f0000000-0000-4000-8000-0000000000c4','33333333-3333-4333-8333-333333333333','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1','2026-10-13','assigned');
-- Real challenge so the actual exercise-insert trigger is exercised (OR06).
INSERT INTO public.challenges (id,title,description,challenge_type,target_value,created_by,exercise_type,starts_at,ends_at) VALUES
 ('c0000000-0000-4000-8000-000000000001','Synthetic minutes','Synthetic','minutes',10,'33333333-3333-4333-8333-333333333333','breathing',now()-interval '1 day',now()+interval '1 day');
INSERT INTO public.challenge_participants (challenge_id,user_id) VALUES
 ('c0000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111');

-- Test helpers (rolled back with the transaction).
CREATE FUNCTION public.t_ms(delta_seconds integer DEFAULT 0) RETURNS bigint LANGUAGE sql STABLE AS
$$ SELECT (extract(epoch FROM now()) * 1000)::bigint + delta_seconds::bigint * 1000 $$;
CREATE FUNCTION public.t_call(op uuid, kind text, payload jsonb, owner uuid DEFAULT auth.uid()) RETURNS jsonb LANGUAGE sql AS
$$ SELECT public.sync_offline_mutation(owner, op, kind, payload) $$;
-- Run a call and require a specific SQLSTATE and message tag.
CREATE FUNCTION public.t_expect(op uuid, kind text, payload jsonb, state text, tag text, owner uuid DEFAULT auth.uid())
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.sync_offline_mutation(owner, op, kind, payload);
  RAISE EXCEPTION 'Expected % (%) but the call succeeded', tag, state;
EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE <> state OR position(tag IN SQLERRM) <> 1 THEN
    RAISE EXCEPTION 'Expected % / % but got % / %', state, tag, SQLSTATE, SQLERRM;
  END IF;
END $$;
GRANT EXECUTE ON FUNCTION public.t_ms(integer), public.t_call(uuid,text,jsonb,uuid),
  public.t_expect(uuid,text,jsonb,text,text,uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- Privileges: anonymous cannot call; helpers and the table are not API-writable.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE anon;
DO $$ BEGIN
  IF has_function_privilege('public.sync_offline_mutation(uuid,uuid,text,jsonb)','execute') THEN
    RAISE EXCEPTION 'Anonymous role can execute sync_offline_mutation';
  END IF;
  IF has_function_privilege('public.save_mood_checkin(date,integer,integer,integer,text)','execute')
     OR has_function_privilege('public.complete_quest_with_reward(uuid,text,integer)','execute') THEN
    RAISE EXCEPTION 'Anonymous role can execute the atomic reward RPCs';
  END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  IF NOT has_function_privilege('public.sync_offline_mutation(uuid,uuid,text,jsonb)','execute') THEN
    RAISE EXCEPTION 'Authenticated role cannot execute sync_offline_mutation';
  END IF;
  IF NOT has_function_privilege('public.save_mood_checkin(date,integer,integer,integer,text)','execute')
     OR NOT has_function_privilege('public.complete_quest_with_reward(uuid,text,integer)','execute') THEN
    RAISE EXCEPTION 'Authenticated role cannot execute the atomic reward RPCs';
  END IF;
  IF has_function_privilege('public.apply_mood_checkin(uuid,date,integer,integer,integer,text,timestamptz)','execute')
     OR has_function_privilege('public.apply_quest_completion(uuid,uuid,timestamptz,text,integer)','execute')
     OR has_function_privilege('public.offline_mutation_int(jsonb,text,boolean,bigint,bigint)','execute')
     OR has_table_privilege('public.offline_mutation_receipts','insert')
     OR has_table_privilege('public.offline_mutation_receipts','update')
     OR has_table_privilege('public.offline_mutation_receipts','delete') THEN
    RAISE EXCEPTION 'Internal helper or receipt table writes exposed to API roles';
  END IF;
END $$;

-- No authenticated subject -> AUTH_REQUIRED.
SET LOCAL request.jwt.claim.role='authenticated';
DO $$ BEGIN
  PERFORM public.t_expect('00000000-0000-4000-8000-000000000001','mood',
    jsonb_build_object('schema_version',1,'mood_score',5,'recorded_at_ms',public.t_ms(-60)),
    '42501','AUTH_REQUIRED','11111111-1111-4111-8111-111111111111');
END $$;

SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';

-- ---------------------------------------------------------------------------
-- Owner pinning and payload validation (nothing is written for any of these).
-- ---------------------------------------------------------------------------
DO $$ DECLARE ok jsonb := jsonb_build_object('schema_version',1,'mood_score',5,'recorded_at_ms',public.t_ms(-60));
BEGIN
  PERFORM public.t_expect('00000000-0000-4000-8000-000000000002','mood',ok,'42501','OWNER_MISMATCH','22222222-2222-4222-8222-222222222222');
  PERFORM public.t_expect('00000000-0000-4000-8000-000000000003','mood',ok || '{"mood_score":0}','22023','INVALID_PAYLOAD');
  PERFORM public.t_expect('00000000-0000-4000-8000-000000000003','mood',ok || '{"mood_score":11}','22023','INVALID_PAYLOAD');
  PERFORM public.t_expect('00000000-0000-4000-8000-000000000003','mood',ok || '{"mood_score":5.5}','22023','INVALID_PAYLOAD');
  PERFORM public.t_expect('00000000-0000-4000-8000-000000000003','mood',ok || '{"anxiety_score":0}','22023','INVALID_PAYLOAD');
  PERFORM public.t_expect('00000000-0000-4000-8000-000000000003','mood',ok || '{"energy_score":11}','22023','INVALID_PAYLOAD');
  PERFORM public.t_expect('00000000-0000-4000-8000-000000000003','mood',ok || jsonb_build_object('note',repeat('x',4001)),'22023','INVALID_PAYLOAD');
  PERFORM public.t_expect('00000000-0000-4000-8000-000000000003','mood',ok || '{"unexpected":1}','22023','INVALID_PAYLOAD');
  PERFORM public.t_expect('00000000-0000-4000-8000-000000000003','mood',ok || '{"schema_version":2}','22023','INVALID_PAYLOAD');
  PERFORM public.t_expect('00000000-0000-4000-8000-000000000003','mood',ok || jsonb_build_object('recorded_at_ms',public.t_ms(3600)),'22023','INVALID_PAYLOAD');
  PERFORM public.t_expect('00000000-0000-4000-8000-000000000003','mood',ok || jsonb_build_object('recorded_at_ms',public.t_ms(-86400*500)),'22023','INVALID_PAYLOAD');
  PERFORM public.t_expect('00000000-0000-4000-8000-000000000003','mystery',ok,'22023','INVALID_PAYLOAD');
  PERFORM public.t_expect('00000000-0000-4000-8000-000000000003','exercise',
    jsonb_build_object('schema_version',1,'exercise_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','duration_seconds',0,'completed_at_ms',public.t_ms(-60)),
    '22023','INVALID_PAYLOAD');
  PERFORM public.t_expect('00000000-0000-4000-8000-000000000003','exercise',
    jsonb_build_object('schema_version',1,'exercise_id','not-a-uuid','duration_seconds',60,'completed_at_ms',public.t_ms(-60)),
    '22023','INVALID_PAYLOAD');
  IF EXISTS (SELECT 1 FROM public.offline_mutation_receipts) OR EXISTS (SELECT 1 FROM public.moods) THEN
    RAISE EXCEPTION 'A rejected call left a receipt or a mood';
  END IF;
END $$;

-- Direct writes to the receipt table are refused for the API role.
DO $$ BEGIN
  BEGIN
    INSERT INTO public.offline_mutation_receipts(user_id,operation_id,kind,payload_hash)
    VALUES (auth.uid(),'00000000-0000-4000-8000-0000000000ff','mood',repeat('0',64));
    RAISE EXCEPTION 'Direct receipt insert accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;

-- ---------------------------------------------------------------------------
-- Mood: replay, 100 samples, changed payload/kind, content-free receipt.
-- ---------------------------------------------------------------------------
DO $$ DECLARE
  op uuid := '10000000-0000-4000-8000-000000000001';
  p jsonb := jsonb_build_object('schema_version',1,'mood_score',6,'anxiety_score',3,'energy_score',7,
                                'note','Synthetic private note',
                                'recorded_at_ms',(extract(epoch FROM date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC')*1000)::bigint - 86400000 + 10000);
  res1 jsonb; res2 jsonb; i integer; xp_before integer;
BEGIN
  SELECT xp_total INTO xp_before FROM public.user_stats WHERE user_id = auth.uid();
  res1 := public.t_call(op,'mood',p);
  IF (res1->>'replayed')::boolean OR res1->'result'->>'outcome' <> 'created' OR (res1->'result'->>'xp_awarded')::integer <> 10 THEN
    RAISE EXCEPTION 'First mood sync was not a rewarded creation: %', res1;
  END IF;
  FOR i IN 1..100 LOOP
    res2 := public.t_call(op,'mood',p);
    IF NOT (res2->>'replayed')::boolean OR res2->'result' <> res1->'result'
       OR res2->>'target_id' <> res1->>'target_id' OR res2->>'payload_hash' <> res1->>'payload_hash'
       OR res2->>'created_at' <> res1->>'created_at' THEN
      RAISE EXCEPTION 'Replay % did not return the exact canonical receipt', i;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM public.moods) <> 1 OR (SELECT count(*) FROM public.offline_mutation_receipts) <> 1 THEN
    RAISE EXCEPTION '100 replays created more than one mood or receipt';
  END IF;
  IF (SELECT xp_total FROM public.user_stats WHERE user_id = auth.uid()) <> xp_before + 10 THEN
    RAISE EXCEPTION 'Offline mood creation did not pay the canonical 10 XP exactly once';
  END IF;
  -- Same operation, changed semantic payload / changed kind -> conflict, state unchanged.
  PERFORM public.t_expect(op,'mood',p || '{"mood_score":7}','MF409','IDEMPOTENCY_CONFLICT');
  PERFORM public.t_expect(op,'mood',p || '{"note":"Changed"}','MF409','IDEMPOTENCY_CONFLICT');
  PERFORM public.t_expect(op,'quest',jsonb_build_object('schema_version',1,'quest_id','f0000000-0000-4000-8000-000000000001','completed_at_ms',public.t_ms(-5)),
    'MF409','IDEMPOTENCY_CONFLICT');
  IF (SELECT mood_score FROM public.moods) <> 6 OR (SELECT note FROM public.moods) <> 'Synthetic private note' THEN
    RAISE EXCEPTION 'A conflicting call changed the stored mood';
  END IF;
  -- Receipt is content-free: no note text, hash and IDs only.
  IF EXISTS (SELECT 1 FROM public.offline_mutation_receipts r
              WHERE position('Synthetic private note' IN r.result::text || r.payload_hash || r.kind) > 0)
     OR EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='offline_mutation_receipts' AND column_name IN ('note','payload')) THEN
    RAISE EXCEPTION 'Receipt duplicated private content';
  END IF;
END $$;

-- OR01 ordering: initial 10s, newer 30s, delayed 20s must retain the 30s value;
-- a live edit (any writer) advances the same ordering field so late offline data
-- cannot overwrite it. Uses yesterday (UTC) so no event is clamped to "now".
RESET ROLE;
DELETE FROM public.moods;
DELETE FROM public.offline_mutation_receipts;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
DO $$ DECLARE
  base_ms bigint := (extract(epoch FROM date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC')*1000)::bigint - 86400000;
  r jsonb; xp_before integer;
BEGIN
  SELECT xp_total INTO xp_before FROM public.user_stats WHERE user_id = auth.uid();
  r := public.t_call('10000000-0000-4000-8000-000000000011','mood', jsonb_build_object('schema_version',1,'mood_score',4,'recorded_at_ms',base_ms + 10000));
  IF r->'result'->>'outcome' <> 'created' THEN RAISE EXCEPTION 'initial 10s not created: %', r; END IF;
  r := public.t_call('10000000-0000-4000-8000-000000000012','mood', jsonb_build_object('schema_version',1,'mood_score',8,'recorded_at_ms',base_ms + 30000));
  IF r->'result'->>'outcome' <> 'updated' OR (r->'result'->>'xp_awarded')::integer <> 0 THEN RAISE EXCEPTION 'newer 30s not an unpaid update: %', r; END IF;
  r := public.t_call('10000000-0000-4000-8000-000000000013','mood', jsonb_build_object('schema_version',1,'mood_score',9,'recorded_at_ms',base_ms + 20000));
  IF r->'result'->>'outcome' <> 'kept_existing' OR (SELECT mood_score FROM public.moods) <> 8
     OR (SELECT last_event_at FROM public.moods) <> to_timestamp((base_ms + 30000) / 1000.0) THEN
    RAISE EXCEPTION 'delayed 20s overwrote the newer 30s event: %', r;
  END IF;
  IF (SELECT count(*) FROM public.moods) <> 1 OR (SELECT xp_total FROM public.user_stats WHERE user_id = auth.uid()) <> xp_before + 10 THEN
    RAISE EXCEPTION 'Update or kept events changed row count or paid XP again';
  END IF;

  -- A live edit by an older writer (plain UPDATE) advances the ordering field to now().
  UPDATE public.moods SET mood_score = 3 WHERE user_id = auth.uid();
  IF (SELECT last_event_at FROM public.moods) < now() - interval '1 minute' THEN
    RAISE EXCEPTION 'A live edit did not advance the canonical ordering time';
  END IF;
  r := public.t_call('10000000-0000-4000-8000-000000000014','mood', jsonb_build_object('schema_version',1,'mood_score',9,'recorded_at_ms',base_ms + 40000));
  IF r->'result'->>'outcome' <> 'kept_existing' OR (SELECT mood_score FROM public.moods) <> 3 THEN
    RAISE EXCEPTION 'A delayed offline entry overwrote a live edit: %', r;
  END IF;
  -- A no-content update (for example a background touch) does not advance it.
  UPDATE public.moods SET source = 'manual' WHERE user_id = auth.uid();
END $$;

-- Online/offline reward shapes for mood days (OR03): offline-first then online, online-first then offline.
RESET ROLE;
DELETE FROM public.moods;
DELETE FROM public.offline_mutation_receipts;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
DO $$ DECLARE
  base_ms bigint := (extract(epoch FROM date_trunc('day', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC')*1000)::bigint;
  day1 date := (now() AT TIME ZONE 'UTC')::date - 2;
  day2 date := (now() AT TIME ZONE 'UTC')::date - 3;
  r jsonb; xp_before integer;
BEGIN
  SELECT xp_total INTO xp_before FROM public.user_stats WHERE user_id = auth.uid();
  -- offline first (day1), then a stale online save for the same day pays nothing.
  r := public.t_call('10000000-0000-4000-8000-000000000021','mood',
        jsonb_build_object('schema_version',1,'mood_score',5,'recorded_at_ms',base_ms - 2*86400000 + 10000));
  IF (r->'result'->>'xp_awarded')::integer <> 10 THEN RAISE EXCEPTION 'offline-first creation unpaid: %', r; END IF;
  r := public.save_mood_checkin(day1, 6, NULL, NULL, NULL);
  IF r->>'outcome' <> 'updated' OR (r->>'xp_awarded')::integer <> 0 THEN RAISE EXCEPTION 'online after offline paid again: %', r; END IF;
  -- online first (day2), then the offline entry for the same day pays nothing and never overwrites.
  r := public.save_mood_checkin(day2, 7, 2, 3, 'Synthetic online note');
  IF r->>'outcome' <> 'created' OR (r->>'xp_awarded')::integer <> 10 THEN RAISE EXCEPTION 'online creation unpaid: %', r; END IF;
  r := public.t_call('10000000-0000-4000-8000-000000000022','mood',
        jsonb_build_object('schema_version',1,'mood_score',1,'recorded_at_ms',base_ms - 3*86400000 + 10000));
  IF r->'result'->>'outcome' <> 'kept_existing' OR (r->'result'->>'xp_awarded')::integer <> 0
     OR (SELECT mood_score FROM public.moods WHERE local_date = day2) <> 7 THEN
    RAISE EXCEPTION 'offline after online paid or overwrote: %', r;
  END IF;
  -- repeated online saves in the same moment are idempotent for XP
  r := public.save_mood_checkin(day2, 7, 2, 3, 'Synthetic online note');
  IF (r->>'xp_awarded')::integer <> 0 THEN RAISE EXCEPTION 'repeat online save paid: %', r; END IF;
  IF (SELECT xp_total FROM public.user_stats WHERE user_id = auth.uid()) <> xp_before + 20 THEN
    RAISE EXCEPTION 'Mood XP is not exactly 10 per new day';
  END IF;
  -- invalid online input
  BEGIN PERFORM public.save_mood_checkin(day2, 11, NULL, NULL, NULL); RAISE EXCEPTION 'bad score accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;

-- ---------------------------------------------------------------------------
-- Quest: real quest row, reward once per transition, forged/unsuitable refs.
-- ---------------------------------------------------------------------------
DO $$ DECLARE
  op uuid := '20000000-0000-4000-8000-000000000001';
  p jsonb := jsonb_build_object('schema_version',1,'quest_id','f0000000-0000-4000-8000-000000000001','completed_at_ms',public.t_ms(-120));
  xp_before integer; res1 jsonb; res2 jsonb; i integer;
BEGIN
  SELECT xp_total INTO xp_before FROM public.user_stats WHERE user_id = auth.uid();
  -- Forged / other-owner / skipped references are refused and change nothing.
  PERFORM public.t_expect('20000000-0000-4000-8000-0000000000f1','quest',
    jsonb_build_object('schema_version',1,'quest_id','f0000000-0000-4000-8000-0000000000b1','completed_at_ms',public.t_ms(-120)),'42501','NOT_FOUND');
  PERFORM public.t_expect('20000000-0000-4000-8000-0000000000f2','quest',
    jsonb_build_object('schema_version',1,'quest_id','99999999-9999-4999-8999-999999999999','completed_at_ms',public.t_ms(-120)),'42501','NOT_FOUND');
  PERFORM public.t_expect('20000000-0000-4000-8000-0000000000f3','quest',
    jsonb_build_object('schema_version',1,'quest_id','f0000000-0000-4000-8000-000000000002','completed_at_ms',public.t_ms(-120)),'22023','STATE_REJECTED');

  res1 := public.t_call(op,'quest',p);
  IF res1->'result'->>'outcome' <> 'completed' OR (res1->'result'->>'xp_awarded')::integer <> 50 THEN
    RAISE EXCEPTION 'Quest completion/reward wrong: %', res1;
  END IF;
  FOR i IN 1..100 LOOP
    res2 := public.t_call(op,'quest',p);
    IF NOT (res2->>'replayed')::boolean OR res2->'result' <> res1->'result' THEN
      RAISE EXCEPTION 'Quest replay % changed the receipt', i;
    END IF;
  END LOOP;
  IF (SELECT xp_total FROM public.user_stats WHERE user_id = auth.uid()) <> xp_before + 50
     OR (SELECT total_quests_completed FROM public.user_stats WHERE user_id = auth.uid()) <> 1
     OR (SELECT status FROM public.quests WHERE id='f0000000-0000-4000-8000-000000000001') <> 'completed' THEN
    RAISE EXCEPTION '100 quest replays changed XP, count or status beyond one completion';
  END IF;
  -- A different operation for an already completed quest never pays twice.
  res2 := public.t_call('20000000-0000-4000-8000-000000000002','quest',p);
  IF res2->'result'->>'outcome' <> 'already_completed' OR (res2->'result'->>'xp_awarded')::integer <> 0
     OR (SELECT xp_total FROM public.user_stats WHERE user_id = auth.uid()) <> xp_before + 50 THEN
    RAISE EXCEPTION 'A second operation for a completed quest was rewarded: %', res2;
  END IF;
  PERFORM public.t_expect(op,'quest',p || jsonb_build_object('completed_at_ms',public.t_ms(-30)),'MF409','IDEMPOTENCY_CONFLICT');
END $$;

-- ---------------------------------------------------------------------------
-- OR05: one atomic completion+reward for both routes, in either order.
-- (True concurrency needs two sessions; run it from the disposable-DB harness.
--  Here both orders are exercised with DIFFERENT identities: an offline operation
--  ID and the online call, which carries no operation ID at all.)
-- ---------------------------------------------------------------------------
DO $$ DECLARE r jsonb; xp_before integer; total_before integer;
BEGIN
  SELECT xp_total, total_quests_completed INTO xp_before, total_before FROM public.user_stats WHERE user_id = auth.uid();
  -- offline-first (quest 1 completed above) then the online helper
  r := public.complete_quest_with_reward('f0000000-0000-4000-8000-000000000001','Synthetic reflection',4);
  IF r->>'outcome' <> 'already_completed' OR (r->>'xp_awarded')::integer <> 0 THEN
    RAISE EXCEPTION 'Online helper paid a quest already completed offline: %', r;
  END IF;
  -- online-first (quest 3), then an offline operation for the same quest
  r := public.complete_quest_with_reward('f0000000-0000-4000-8000-000000000003','Synthetic reflection',4);
  IF r->>'outcome' <> 'completed' OR (r->>'xp_awarded')::integer <> 50 THEN
    RAISE EXCEPTION 'Online helper did not pay the quest reward once: %', r;
  END IF;
  IF (SELECT reflection_note FROM public.quests WHERE id='f0000000-0000-4000-8000-000000000003') <> 'Synthetic reflection'
     OR (SELECT rating FROM public.quests WHERE id='f0000000-0000-4000-8000-000000000003') <> 4 THEN
    RAISE EXCEPTION 'Online helper lost the reflection or rating';
  END IF;
  r := public.t_call('20000000-0000-4000-8000-000000000031','quest',
        jsonb_build_object('schema_version',1,'quest_id','f0000000-0000-4000-8000-000000000003','completed_at_ms',public.t_ms(-60)));
  IF r->'result'->>'outcome' <> 'already_completed' OR (r->'result'->>'xp_awarded')::integer <> 0 THEN
    RAISE EXCEPTION 'Offline sync paid a quest already completed online: %', r;
  END IF;
  -- repeated online calls
  r := public.complete_quest_with_reward('f0000000-0000-4000-8000-000000000003',NULL,NULL);
  IF (r->>'xp_awarded')::integer <> 0 THEN RAISE EXCEPTION 'Repeated online completion paid again'; END IF;
  IF (SELECT xp_total FROM public.user_stats WHERE user_id = auth.uid()) <> xp_before + 50
     OR (SELECT total_quests_completed FROM public.user_stats WHERE user_id = auth.uid()) <> total_before + 1 THEN
    RAISE EXCEPTION 'Quest XP or completion count is not exactly one transition';
  END IF;
  -- forged / skipped / invalid input to the online helper
  BEGIN PERFORM public.complete_quest_with_reward('f0000000-0000-4000-8000-0000000000b1'); RAISE EXCEPTION 'cross-owner accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.complete_quest_with_reward('f0000000-0000-4000-8000-000000000002'); RAISE EXCEPTION 'skipped accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN PERFORM public.complete_quest_with_reward('f0000000-0000-4000-8000-000000000003',NULL,9); RAISE EXCEPTION 'bad rating accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;

-- ---------------------------------------------------------------------------
-- OR02: out-of-order quest dates (owner C): 12th first, 10th late, 11th fills the gap.
-- Completion counts exactly once each; last_quest_date never moves backward.
-- ---------------------------------------------------------------------------
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='33333333-3333-4333-8333-333333333333';
DO $$ DECLARE r jsonb; st record;
BEGIN
  r := public.complete_quest_with_reward('f0000000-0000-4000-8000-0000000000c3');
  SELECT * INTO st FROM public.user_stats WHERE user_id = auth.uid();
  IF st.current_streak_days <> 1 OR st.last_quest_date::date <> date '2026-10-12' OR st.total_quests_completed <> 1 THEN
    RAISE EXCEPTION 'first (12th) completion wrong: %', to_jsonb(st);
  END IF;
  r := public.t_call('20000000-0000-4000-8000-000000000041','quest',
        jsonb_build_object('schema_version',1,'quest_id','f0000000-0000-4000-8000-0000000000c1','completed_at_ms',public.t_ms(-60)));
  SELECT * INTO st FROM public.user_stats WHERE user_id = auth.uid();
  IF st.current_streak_days <> 1 OR st.last_quest_date::date <> date '2026-10-12' OR st.total_quests_completed <> 2 THEN
    RAISE EXCEPTION 'delayed older (10th) quest moved last_quest_date or reset the streak: %', to_jsonb(st);
  END IF;
  r := public.t_call('20000000-0000-4000-8000-000000000042','quest',
        jsonb_build_object('schema_version',1,'quest_id','f0000000-0000-4000-8000-0000000000c2','completed_at_ms',public.t_ms(-50)));
  SELECT * INTO st FROM public.user_stats WHERE user_id = auth.uid();
  IF st.current_streak_days <> 3 OR st.longest_streak_days <> 3 OR st.last_quest_date::date <> date '2026-10-12'
     OR st.total_quests_completed <> 3 THEN
    RAISE EXCEPTION 'gap-filling (11th) did not connect the 10th-12th streak: %', to_jsonb(st);
  END IF;
  -- Replaying the late operation changes nothing; the next in-order day extends the streak.
  PERFORM public.t_call('20000000-0000-4000-8000-000000000042','quest',
        jsonb_build_object('schema_version',1,'quest_id','f0000000-0000-4000-8000-0000000000c2','completed_at_ms',public.t_ms(-50)));
  PERFORM public.complete_quest_with_reward('f0000000-0000-4000-8000-0000000000c4');
  SELECT * INTO st FROM public.user_stats WHERE user_id = auth.uid();
  IF st.current_streak_days <> 4 OR st.last_quest_date::date <> date '2026-10-13' OR st.total_quests_completed <> 4
     OR st.xp_total <> 200 THEN
    RAISE EXCEPTION 'in-order day after backfill or replay wrong: %', to_jsonb(st);
  END IF;
END $$;
-- A shield-protected streak larger than any quest run is never reduced by a late quest.
RESET ROLE;
UPDATE public.user_stats SET current_streak_days = 9, longest_streak_days = 9 WHERE user_id = '33333333-3333-4333-8333-333333333333';
INSERT INTO public.quests (id,user_id,template_id,local_date,status) VALUES
 ('f0000000-0000-4000-8000-0000000000c5','33333333-3333-4333-8333-333333333333','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1','2026-10-01','assigned');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='33333333-3333-4333-8333-333333333333';
DO $$ BEGIN
  PERFORM public.complete_quest_with_reward('f0000000-0000-4000-8000-0000000000c5');
  IF (SELECT current_streak_days FROM public.user_stats WHERE user_id = auth.uid()) <> 9
     OR (SELECT last_quest_date::date FROM public.user_stats WHERE user_id = auth.uid()) <> date '2026-10-13' THEN
    RAISE EXCEPTION 'A late old quest reduced a protected streak or moved last_quest_date';
  END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';

-- ---------------------------------------------------------------------------
-- Exercise: one real canonical session per operation, 30 XP once.
-- ---------------------------------------------------------------------------
DO $$ DECLARE
  op uuid := '30000000-0000-4000-8000-000000000001';
  p jsonb := jsonb_build_object('schema_version',1,'exercise_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','duration_seconds',90,'completed_at_ms',public.t_ms(-300));
  xp_before integer; res1 jsonb; res2 jsonb; i integer; amount_again integer; sid uuid;
BEGIN
  SELECT xp_total INTO xp_before FROM public.user_stats WHERE user_id = auth.uid();
  -- Forged catalog ID: refused, no session, no receipt, no XP.
  PERFORM public.t_expect('30000000-0000-4000-8000-0000000000f1','exercise',
    p || '{"exercise_id":"99999999-9999-4999-8999-999999999999"}','42501','NOT_FOUND');
  IF EXISTS (SELECT 1 FROM public.exercise_sessions) OR (SELECT xp_total FROM public.user_stats WHERE user_id = auth.uid()) <> xp_before THEN
    RAISE EXCEPTION 'A forged exercise created a session or paid XP';
  END IF;

  res1 := public.t_call(op,'exercise',p);
  sid := (res1->>'target_id')::uuid;
  IF res1->'result'->>'outcome' <> 'completed' OR (res1->'result'->>'xp_awarded')::integer <> 30 THEN
    RAISE EXCEPTION 'Exercise completion/reward wrong: %', res1;
  END IF;
  FOR i IN 1..100 LOOP
    res2 := public.t_call(op,'exercise',p);
    IF NOT (res2->>'replayed')::boolean OR res2->>'target_id' <> sid::text OR res2->'result' <> res1->'result' THEN
      RAISE EXCEPTION 'Exercise replay % did not return the same session/receipt', i;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM public.exercise_sessions WHERE user_id = auth.uid()) <> 1
     OR (SELECT completed_at FROM public.exercise_sessions WHERE id = sid) IS NULL
     OR (SELECT xp_awarded_at FROM public.exercise_sessions WHERE id = sid) IS NULL
     OR (SELECT xp_total FROM public.user_stats WHERE user_id = auth.uid()) <> xp_before + 30
     OR (SELECT total_exercises_completed FROM public.user_stats WHERE user_id = auth.uid()) <> 1
     OR (SELECT exercises_completed FROM public.skill_progress WHERE user_id = auth.uid() AND skill_type='breathing') <> 1 THEN
    RAISE EXCEPTION '100 exercise replays created more than one session, completion or 30 XP';
  END IF;
  -- OR06: the real exercise-insert trigger ran once for the one session and kept its behavior.
  IF (SELECT current_progress FROM public.challenge_participants
       WHERE challenge_id='c0000000-0000-4000-8000-000000000001' AND user_id = auth.uid()) <> 1 THEN
    RAISE EXCEPTION 'Challenge minutes progress did not advance exactly once through the real trigger';
  END IF;
  -- Duplicate XP claim on the same canonical session is the existing zero-pay path.
  SELECT amount INTO amount_again FROM public.award_exercise_session_xp(sid);
  IF amount_again <> 0 OR (SELECT xp_total FROM public.user_stats WHERE user_id = auth.uid()) <> xp_before + 30 THEN
    RAISE EXCEPTION 'Duplicate exercise XP award paid again';
  END IF;
  -- The recorded completion time is kept, not the sync time.
  IF (SELECT completed_at FROM public.exercise_sessions WHERE id = sid) >= now() - interval '200 seconds' THEN
    RAISE EXCEPTION 'Exercise completion time was replaced by sync time';
  END IF;
  PERFORM public.t_expect(op,'exercise',p || '{"duration_seconds":91}','MF409','IDEMPOTENCY_CONFLICT');
  -- A genuinely different completion is a different session and pays its own 30 XP.
  res2 := public.t_call('30000000-0000-4000-8000-000000000002','exercise',p);
  IF res2->>'target_id' = sid::text OR (SELECT xp_total FROM public.user_stats WHERE user_id = auth.uid()) <> xp_before + 60 THEN
    RAISE EXCEPTION 'A distinct operation reused the earlier session or paid wrongly';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Two owners: same operation UUID is independent, and neither can see the other's receipts.
-- ---------------------------------------------------------------------------
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='22222222-2222-4222-8222-222222222222';
DO $$ DECLARE r jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM public.offline_mutation_receipts) THEN
    RAISE EXCEPTION 'Receipts leaked across owners';
  END IF;
  -- B reuses A's operation UUID with different content: independent, no conflict.
  r := public.t_call('10000000-0000-4000-8000-000000000001','mood',
        jsonb_build_object('schema_version',1,'mood_score',2,'recorded_at_ms',public.t_ms(-60)));
  IF (r->>'replayed')::boolean THEN RAISE EXCEPTION 'Owner B replayed owner A receipt'; END IF;
  -- B cannot complete A's quest.
  PERFORM public.t_expect('20000000-0000-4000-8000-000000000009','quest',
    jsonb_build_object('schema_version',1,'quest_id','f0000000-0000-4000-8000-000000000002','completed_at_ms',public.t_ms(-60)),'42501','NOT_FOUND');
  IF (SELECT count(*) FROM public.offline_mutation_receipts) <> 1 THEN
    RAISE EXCEPTION 'Owner B sees or created unexpected receipts';
  END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
  IF (SELECT count(*) FROM public.moods WHERE user_id='22222222-2222-4222-8222-222222222222') <> 1
     OR (SELECT count(*) FROM public.moods WHERE user_id='11111111-1111-4111-8111-111111111111') <> 2
     OR (SELECT max(mood_score) FROM public.moods WHERE user_id='11111111-1111-4111-8111-111111111111' AND local_date = (now() AT TIME ZONE 'UTC')::date - 3) <> 7 THEN
    RAISE EXCEPTION 'Cross-owner mood effects detected';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Account deletion cascades receipts.
-- ---------------------------------------------------------------------------
DELETE FROM auth.users WHERE id = '11111111-1111-4111-8111-111111111111';
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.offline_mutation_receipts WHERE user_id='11111111-1111-4111-8111-111111111111') THEN
    RAISE EXCEPTION 'Receipts survived account deletion';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.offline_mutation_receipts WHERE user_id='22222222-2222-4222-8222-222222222222') THEN
    RAISE EXCEPTION 'Deleting one account removed another owner receipt';
  END IF;
END $$;
ROLLBACK;
\echo PASS: offline receipts - owner pinning, validation, 100x replay, conflicts, content-free, canonical quest/exercise rewards, isolation, cascade
