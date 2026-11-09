-- AC-04 / AC-30. Run only in the empty, owned, network-free support_acceptance_synthetic database
-- after the current migration chain. Synthetic records only; no provider or production traffic.
\set ON_ERROR_STOP on
DO $$ BEGIN
 IF current_database() <> 'support_acceptance_synthetic' OR EXISTS(SELECT FROM auth.users) THEN
  RAISE EXCEPTION 'Requires the empty disposable acceptance database';
 END IF;
END $$;
INSERT INTO public.supported_languages(code,name,native_name,is_active) VALUES('en','English','English',true) ON CONFLICT DO NOTHING;
INSERT INTO public.level_thresholds(level,xp_required,title) VALUES(1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO public.skill_thresholds(level,xp_required,title) VALUES(1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO auth.users(id,aud,role,email) VALUES('ac040000-0000-4000-8000-000000000001','authenticated','authenticated','acceptance@example.invalid');
INSERT INTO auth.users(id,aud,role,email) VALUES('ac040000-0000-4000-8000-000000000009','authenticated','authenticated','forged-completion@example.invalid');
INSERT INTO public.user_stats(user_id) VALUES('ac040000-0000-4000-8000-000000000001') ON CONFLICT DO NOTHING;
INSERT INTO public.conversations(id,user_id,title) VALUES('ac040000-0000-4000-8000-000000000002','ac040000-0000-4000-8000-000000000001','Synthetic original conversation');
CREATE SCHEMA support_acceptance_test;
GRANT USAGE ON SCHEMA support_acceptance_test TO authenticated,service_role;
CREATE TABLE support_acceptance_test.values(key text PRIMARY KEY, value jsonb);
GRANT SELECT,INSERT,UPDATE ON support_acceptance_test.values TO authenticated,service_role;
SET ROLE authenticated;
SET request.jwt.claim.sub='ac040000-0000-4000-8000-000000000001';
SET request.jwt.claims='{"sub":"ac040000-0000-4000-8000-000000000001","role":"authenticated"}';
DO $$
DECLARE sid constant uuid:='ac040000-0000-4000-8000-000000000003'; aid constant uuid:='ac040000-0000-4000-8000-000000000004';
 create_op jsonb; start_op jsonb; finish_op jsonb; r jsonb; canonical uuid; i int;
BEGIN
 create_op:=jsonb_build_object('schema_version',1,'operation_id','ac040000-0000-4000-8000-000000000005','session_id',sid,
  'expected_revision',NULL,'kind','create','payload',jsonb_build_object('title','Synthetic grounding','context_scope','conversation_only',
  'conversation_id','ac040000-0000-4000-8000-000000000002'));
 FOR i IN 1..100 LOOP
  r:=public.support_apply_mutation(create_op);
  IF r->>'ok'<>'true' OR (r->>'revision')::int<>1 OR (i>1 AND r->>'replayed'<>'true') THEN RAISE EXCEPTION 'create replay %: %',i,r; END IF;
 END LOOP;
 IF public.support_apply_mutation(jsonb_set(create_op,'{payload,title}','"Changed identity payload"'))->>'code'<>'OPERATION_ID_REUSED' THEN
  RAISE EXCEPTION 'changed payload under same create id was accepted'; END IF;
 start_op:=jsonb_build_object('schema_version',1,'operation_id','ac040000-0000-4000-8000-000000000006','session_id',sid,
  'expected_revision',1,'kind','start_activity','payload',jsonb_build_object('activity_id',aid,'template_key','ground_present_v1'));
 FOR i IN 1..100 LOOP
  r:=public.support_apply_mutation(start_op);
  IF r->>'ok'<>'true' OR (r->>'revision')::int<>2 OR (i>1 AND r->>'replayed'<>'true') THEN RAISE EXCEPTION 'start replay %: %',i,r; END IF;
 END LOOP;
 -- B must not finish A's support activity or bypass it through the canonical completion/reward APIs.
 SELECT canonical_ref_id INTO canonical FROM public.support_activities WHERE id=aid;
 PERFORM set_config('request.jwt.claim.sub','ac040000-0000-4000-8000-000000000009',false);
 PERFORM set_config('request.jwt.claims','{"sub":"ac040000-0000-4000-8000-000000000009","role":"authenticated"}',false);
 r:=public.support_apply_mutation(jsonb_build_object('schema_version',1,'operation_id',gen_random_uuid(),'session_id',sid,
   'expected_revision',2,'kind','finish_activity','payload',jsonb_build_object('activity_id',aid,'outcome','completed','active_ms',60000)));
 IF r->>'code' IS DISTINCT FROM 'NOT_FOUND' THEN RAISE EXCEPTION 'forged owner completion accepted: %',r; END IF;
 BEGIN
   PERFORM public.complete_exercise_session(canonical);
   RAISE EXCEPTION 'forged canonical completion accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
   PERFORM public.award_exercise_session_xp(canonical);
   RAISE EXCEPTION 'forged canonical reward accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub','ac040000-0000-4000-8000-000000000001',false);
 PERFORM set_config('request.jwt.claims','{"sub":"ac040000-0000-4000-8000-000000000001","role":"authenticated"}',false);
 IF (SELECT status FROM public.support_activities WHERE id=aid)<>'in_progress'
    OR (SELECT completed FROM public.exercise_sessions WHERE id=canonical)
    OR (SELECT xp_total FROM public.user_stats WHERE user_id=auth.uid())<>0 THEN
   RAISE EXCEPTION 'forged completion changed the original owner state'; END IF;
 IF public.support_apply_mutation(jsonb_set(start_op,'{payload,template_key}','"untangle_thought_v1"'))->>'code'<>'OPERATION_ID_REUSED' THEN
   RAISE EXCEPTION 'changed start payload under same id was accepted'; END IF;
 finish_op:=jsonb_build_object('schema_version',1,'operation_id','ac040000-0000-4000-8000-000000000007','session_id',sid,
  'expected_revision',2,'kind','finish_activity','payload',jsonb_build_object('activity_id',aid,'outcome','completed','active_ms',60000));
 FOR i IN 1..100 LOOP
  r:=public.support_apply_mutation(finish_op);
  IF r->>'ok'<>'true' OR (r->>'revision')::int<>3 OR (i>1 AND r->>'replayed'<>'true') THEN RAISE EXCEPTION 'finish replay %: %',i,r; END IF;
 END LOOP;
 IF public.support_apply_mutation(jsonb_set(finish_op,'{payload,active_ms}','61000'))->>'code'<>'OPERATION_ID_REUSED' THEN
  RAISE EXCEPTION 'changed finish payload under same id was accepted'; END IF;
 SELECT canonical_ref_id INTO canonical FROM public.support_activities WHERE id=aid;
 INSERT INTO support_acceptance_test.values VALUES('canonical',to_jsonb(canonical));
END $$;
RESET ROLE;
DO $$ BEGIN
 IF (SELECT count(*) FROM public.exercise_sessions WHERE user_id='ac040000-0000-4000-8000-000000000001')<>1
 OR (SELECT count(*) FROM public.exercise_sessions WHERE user_id='ac040000-0000-4000-8000-000000000001' AND completed AND xp_awarded_at IS NOT NULL)<>1
 OR (SELECT count(*) FROM public.support_session_events WHERE support_session_id='ac040000-0000-4000-8000-000000000003' AND kind='activity_completed')<>1
 OR (SELECT xp_total FROM public.user_stats WHERE user_id='ac040000-0000-4000-8000-000000000001')<>30 THEN
  RAISE EXCEPTION '100 replays duplicated canonical start, completion, event or XP'; END IF;
END $$;
INSERT INTO public.chat_requests(user_id,request_id,conversation_id,content_hash)
 VALUES('ac040000-0000-4000-8000-000000000001','ac040000-0000-4000-8000-000000000008','ac040000-0000-4000-8000-000000000002','synthetic-claim');
INSERT INTO support_acceptance_test.values VALUES('chat_args',jsonb_build_object('user_id','ac040000-0000-4000-8000-000000000001',
 'request_id','ac040000-0000-4000-8000-000000000008','conversation_id','ac040000-0000-4000-8000-000000000002',
 'support_session_id','ac040000-0000-4000-8000-000000000003','assistant_content','Synthetic one confirmed reply','content_hash','synthetic-claim',
 'privacy_revision',public.support_ensure_privacy_state('ac040000-0000-4000-8000-000000000001'),'scope','conversation_only',
 'provider_vendor','openai','provider_model','gpt-6-luna','route_version','synthetic','response',jsonb_build_object('synthetic',true),
 'response_status',200,'sources',jsonb_build_array(jsonb_build_object('kind','safety_policy','id','00000000-0000-0000-0000-000000000001','revision',1))));
SET ROLE service_role;
DO $$ DECLARE args jsonb; r jsonb; first_id text; i int;
BEGIN
 SELECT value INTO args FROM support_acceptance_test.values WHERE key='chat_args';
 FOR i IN 1..100 LOOP
  r:=public.support_confirm_chat_turn(args);
  IF i=1 THEN first_id:=r->>'message_id'; END IF;
  IF r->>'ok'<>'true' OR r->>'message_id' IS DISTINCT FROM first_id OR (i>1 AND r->>'replayed'<>'true') THEN RAISE EXCEPTION 'chat replay %: %',i,r; END IF;
 END LOOP;
 IF public.support_confirm_chat_turn(jsonb_set(args,'{content_hash}','"changed"'))->>'code'<>'OPERATION_ID_REUSED' THEN
  RAISE EXCEPTION 'changed chat identity accepted'; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF (SELECT count(*) FROM public.messages WHERE conversation_id='ac040000-0000-4000-8000-000000000002' AND role='assistant')<>1
 OR (SELECT count(*) FROM public.support_context_receipts WHERE request_id='ac040000-0000-4000-8000-000000000008')<>1 THEN
  RAISE EXCEPTION '100 confirms duplicated assistant row or receipt'; END IF;
END $$;
-- A single transaction deliberately gives all 125 new rows the same timestamp; cursor id breaks ties.
BEGIN;
INSERT INTO public.conversations(id,user_id,title,created_at)
 SELECT gen_random_uuid(),'ac040000-0000-4000-8000-000000000001','Synthetic history '||n,
  CASE WHEN n<=122 THEN timestamptz '2026-11-01 05:30:00+00' ELSE NULL END FROM generate_series(1,125) n;
SET LOCAL ROLE authenticated;
DO $$ DECLARE c record; r jsonb;
BEGIN
 FOR c IN SELECT id,title FROM public.conversations WHERE user_id='ac040000-0000-4000-8000-000000000001'
 AND id<>'ac040000-0000-4000-8000-000000000002' LOOP
  r:=public.support_apply_mutation(jsonb_build_object('schema_version',1,'operation_id',gen_random_uuid(),'session_id',gen_random_uuid(),
   'expected_revision',NULL,'kind','create','payload',jsonb_build_object('title',c.title,'conversation_id',c.id,'context_scope','conversation_only')));
  IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'history session fixture: %',r; END IF;
 END LOOP;
END $$;
COMMIT;
SET ROLE authenticated;
DO $$ DECLARE page jsonb; cur jsonb:=NULL; ids uuid[]:='{}'; expected uuid[]; item jsonb; loops int:=0;
BEGIN
 LOOP
  page:=public.support_list_sessions(50,(cur->>'updated_at')::timestamptz,(cur->>'id')::uuid,NULL,'desc',false);
  IF page->>'ok'<>'true' THEN RAISE EXCEPTION 'history list failed: %',page; END IF;
  FOR item IN SELECT * FROM jsonb_array_elements(page->'items') LOOP
   IF (item->>'id')::uuid=ANY(ids) THEN RAISE EXCEPTION 'cursor repeated a session'; END IF;
   ids:=array_append(ids,(item->>'id')::uuid);
  END LOOP;
  IF page->'next_cursor'='null'::jsonb OR page->'next_cursor' IS NULL THEN EXIT; END IF;
  IF page->'next_cursor'=cur THEN RAISE EXCEPTION 'cursor did not advance'; END IF;
  cur:=page->'next_cursor'; loops:=loops+1;
  IF loops>4 THEN RAISE EXCEPTION 'history did not terminate'; END IF;
 END LOOP;
 SELECT array_agg(id ORDER BY updated_at DESC,id DESC) INTO expected FROM public.support_work_sessions
 WHERE user_id='ac040000-0000-4000-8000-000000000001' AND status<>'deleted';
 IF cardinality(ids)<>126 OR ids IS DISTINCT FROM expected THEN RAISE EXCEPTION 'history omitted or reordered tied dates'; END IF;
END $$;
RESET ROLE;
SELECT 'PASS: 100 exact create/start/finish/chat-confirm replays, changed payload rejection, one completion/30 XP, and 126 cursor-listed sessions with tied dates' AS result;
-- Content-free summaries expose saved/finished work even when the selected activity differs.
SET ROLE authenticated;
DO $$ DECLARE sid uuid; step_id uuid:=gen_random_uuid(); other_id uuid:=gen_random_uuid(); r jsonb;
BEGIN
 SELECT id INTO sid FROM public.support_work_sessions WHERE user_id=auth.uid() AND title='Synthetic history 1';
 r:=public.support_apply_mutation(jsonb_build_object('schema_version',1,'operation_id',gen_random_uuid(),'session_id',sid,
  'expected_revision',1,'kind','start_activity','payload',jsonb_build_object('activity_id',step_id,'template_key','choose_step_v1')));
 IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'saved-step start: %',r; END IF;
 r:=public.support_apply_mutation(jsonb_build_object('schema_version',1,'operation_id',gen_random_uuid(),'session_id',sid,
  'expected_revision',2,'kind','checkpoint_activity','payload',jsonb_build_object('activity_id',step_id,'pause',true,'active_ms',0,
   'checkpoint',jsonb_build_object('version',1,'template_version',1,'step',jsonb_build_object('action_text','Synthetic older saved step','state','saved')))));
 IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'saved-step checkpoint: %',r; END IF;
 r:=public.support_apply_mutation(jsonb_build_object('schema_version',1,'operation_id',gen_random_uuid(),'session_id',sid,
  'expected_revision',3,'kind','start_activity','payload',jsonb_build_object('activity_id',other_id,'template_key','untangle_thought_v1')));
 IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'different selected activity: %',r; END IF;
 INSERT INTO support_acceptance_test.values VALUES('saved_step_session',to_jsonb(sid));
END $$;
RESET ROLE;
DO $$ DECLARE s jsonb; sid uuid;
BEGIN
 SELECT (value#>>'{}')::uuid INTO sid FROM support_acceptance_test.values WHERE key='saved_step_session';
 s:=public.support_session_summary('ac040000-0000-4000-8000-000000000001',sid);
 IF s->>'saved_step_count'<>'1' OR s->>'activity_count'<>'2' OR s#>>'{selected_activity,template_key}'<>'untangle_thought_v1'
 OR s::text LIKE '%Synthetic older saved step%' THEN RAISE EXCEPTION 'content-free saved history metadata: %',s; END IF;
 s:=public.support_session_summary('ac040000-0000-4000-8000-000000000001','ac040000-0000-4000-8000-000000000003');
 IF s->>'activity_count'<>'1' OR jsonb_array_length(s->'canonical_references')<>1
 OR s#>>'{canonical_references,0,kind}'<>'exercise_session' THEN RAISE EXCEPTION 'completed canonical reference absent: %',s; END IF;
 IF has_function_privilege('authenticated','public.support_session_summary(uuid,uuid)','EXECUTE')
 OR has_function_privilege('anon','public.support_session_summary(uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'private helper exposed'; END IF;
END $$;
SELECT 'PASS: cloud-only saved-step/activity counts and canonical references, with no answer text or new helper grant' AS result;

-- Exercise the actual list RPC and the metadata boundaries used by a newly signed-in device.
DO $$ DECLARE p record; empty_id uuid; s jsonb;
BEGIN
 SELECT * INTO p FROM pg_proc WHERE oid='public.support_session_summary(uuid,uuid)'::regprocedure;
 IF p.prosecdef OR p.provolatile<>'s' OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog, public, pg_temp']::text[] THEN
  RAISE EXCEPTION 'private summary function execution properties changed'; END IF;
 IF has_function_privilege('service_role',p.oid,'EXECUTE')
 OR EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) WHERE grantee=0 AND privilege_type='EXECUTE') THEN
  RAISE EXCEPTION 'private helper execution exposed'; END IF;
 SELECT id INTO empty_id FROM public.support_work_sessions WHERE title='Synthetic history 2';
 s:=public.support_session_summary('ac040000-0000-4000-8000-000000000001',empty_id);
 IF s->>'activity_count'<>'0' OR s->>'saved_step_count'<>'0' OR s->'canonical_references'<>'[]'::jsonb THEN
  RAISE EXCEPTION 'empty session metadata must be known zeros: %',s; END IF;
 IF public.support_session_summary('ac040000-0000-4000-8000-000000000099',empty_id) IS NOT NULL THEN
  RAISE EXCEPTION 'private helper accepted a different owner'; END IF;
END $$;
SET ROLE authenticated;
DO $$ DECLARE sid uuid; step_id uuid:=gen_random_uuid(); saved_session uuid; old_step uuid; r jsonb; item jsonb; found boolean:=false;
BEGIN
 SELECT id INTO sid FROM public.support_work_sessions WHERE user_id=auth.uid() AND title='Synthetic history 3';
 r:=public.support_apply_mutation(jsonb_build_object('schema_version',1,'operation_id',gen_random_uuid(),'session_id',sid,
  'expected_revision',1,'kind','start_activity','payload',jsonb_build_object('activity_id',step_id,'template_key','choose_step_v1')));
 IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'selected step start: %',r; END IF;
 r:=public.support_apply_mutation(jsonb_build_object('schema_version',1,'operation_id',gen_random_uuid(),'session_id',sid,
  'expected_revision',2,'kind','checkpoint_activity','payload',jsonb_build_object('activity_id',step_id,'pause',true,'active_ms',0,
   'checkpoint',jsonb_build_object('version',1,'template_version',1,'step',jsonb_build_object('action_text','Synthetic selected saved step','state','saved')))));
 IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'selected step save: %',r; END IF;
 r:=public.support_list_sessions(100,NULL,NULL,NULL,'desc',false);
 FOR item IN SELECT * FROM jsonb_array_elements(r->'items') LOOP
  IF item->>'id'=sid::text THEN
   found:=true;
   IF item->>'activity_count'<>'1' OR item->>'saved_step_count'<>'1' OR item->'canonical_references'<>'[]'::jsonb
   OR item#>>'{selected_activity,id}'<>step_id::text OR item::text LIKE '%Synthetic selected saved step%' THEN
    RAISE EXCEPTION 'selected saved step missing or text leaked through list RPC: %',item; END IF;
  END IF;
 END LOOP;
 IF NOT found THEN RAISE EXCEPTION 'list RPC omitted newly changed session'; END IF;
 SELECT (value#>>'{}')::uuid INTO saved_session FROM support_acceptance_test.values WHERE key='saved_step_session';
 SELECT id INTO old_step FROM public.support_activities WHERE support_session_id=saved_session AND kind='next_step';
 r:=public.support_apply_mutation(jsonb_build_object('schema_version',1,'operation_id',gen_random_uuid(),'session_id',saved_session,
  'expected_revision',4,'kind','discard_activity_answers','payload',jsonb_build_object('activity_id',old_step)));
 IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'discard saved step: %',r; END IF;
 -- Discarding a completed canonical activity removes notes, never the canonical identity.
 r:=public.support_apply_mutation(jsonb_build_object('schema_version',1,'operation_id',gen_random_uuid(),
  'session_id','ac040000-0000-4000-8000-000000000003','expected_revision',3,'kind','discard_activity_answers',
  'payload',jsonb_build_object('activity_id','ac040000-0000-4000-8000-000000000004')));
 IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'discard completed canonical answers: %',r; END IF;
 SELECT id INTO sid FROM public.support_work_sessions WHERE user_id=auth.uid() AND title='Synthetic history 4';
 r:=public.support_apply_mutation(jsonb_build_object('schema_version',1,'operation_id',gen_random_uuid(),'session_id',sid,
  'expected_revision',1,'kind','delete_session','payload','{}'::jsonb));
 IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'metadata delete: %',r; END IF;
 INSERT INTO support_acceptance_test.values VALUES('deleted_metadata_session',to_jsonb(sid));
END $$;
RESET ROLE;
DO $$ DECLARE sid uuid; s jsonb;
BEGIN
 SELECT (value#>>'{}')::uuid INTO sid FROM support_acceptance_test.values WHERE key='saved_step_session';
 s:=public.support_session_summary('ac040000-0000-4000-8000-000000000001',sid);
 IF s->>'saved_step_count'<>'0' OR s->>'activity_count'<>'2' OR s::text LIKE '%Synthetic older saved step%' THEN
  RAISE EXCEPTION 'discard did not remove saved-step metadata/text: %',s; END IF;
 s:=public.support_session_summary('ac040000-0000-4000-8000-000000000001','ac040000-0000-4000-8000-000000000003');
 IF s->>'activity_count'<>'1' OR jsonb_array_length(s->'canonical_references')<>1 THEN
  RAISE EXCEPTION 'discard removed canonical history identity: %',s; END IF;
 SELECT (value#>>'{}')::uuid INTO sid FROM support_acceptance_test.values WHERE key='deleted_metadata_session';
 s:=public.support_session_summary('ac040000-0000-4000-8000-000000000001',sid);
 IF s->>'status'<>'deleted' OR s->>'activity_count'<>'0' OR s->>'saved_step_count'<>'0' OR s->'canonical_references'<>'[]'::jsonb THEN
  RAISE EXCEPTION 'deleted tombstone exposed stale metadata: %',s; END IF;
END $$;
BEGIN;
INSERT INTO auth.users(id,aud,role,email) VALUES('ac040000-0000-4000-8000-000000000099','authenticated','authenticated','history-other@example.invalid');
INSERT INTO public.user_stats(user_id) VALUES('ac040000-0000-4000-8000-000000000099') ON CONFLICT DO NOTHING;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='ac040000-0000-4000-8000-000000000099';
SET LOCAL request.jwt.claims='{"sub":"ac040000-0000-4000-8000-000000000099","role":"authenticated"}';
DO $$ DECLARE r jsonb; sid uuid:='ac049900-0000-4000-8000-000000000001'; aid uuid:='ac049900-0000-4000-8000-000000000002'; step_id uuid:='ac049900-0000-4000-8000-000000000003';
BEGIN
 r:=public.support_apply_mutation(jsonb_build_object('schema_version',1,'operation_id',gen_random_uuid(),'session_id',sid,
  'expected_revision',NULL,'kind','create','payload',jsonb_build_object('title','Other-owner history','context_scope','conversation_only')));
 IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'other-owner create: %',r; END IF;
 r:=public.support_apply_mutation(jsonb_build_object('schema_version',1,'operation_id',gen_random_uuid(),'session_id',sid,
  'expected_revision',1,'kind','start_activity','payload',jsonb_build_object('activity_id',aid,'template_key','ground_present_v1')));
 IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'other-owner start: %',r; END IF;
 r:=public.support_apply_mutation(jsonb_build_object('schema_version',1,'operation_id',gen_random_uuid(),'session_id',sid,
  'expected_revision',2,'kind','finish_activity','payload',jsonb_build_object('activity_id',aid,'outcome','completed','active_ms',60000)));
 IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'other-owner finish: %',r; END IF;
 r:=public.support_apply_mutation(jsonb_build_object('schema_version',1,'operation_id',gen_random_uuid(),'session_id',sid,
  'expected_revision',3,'kind','start_activity','payload',jsonb_build_object('activity_id',step_id,'template_key','choose_step_v1')));
 IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'other-owner step: %',r; END IF;
 r:=public.support_apply_mutation(jsonb_build_object('schema_version',1,'operation_id',gen_random_uuid(),'session_id',sid,
  'expected_revision',4,'kind','checkpoint_activity','payload',jsonb_build_object('activity_id',step_id,'pause',true,'active_ms',0,
   'checkpoint',jsonb_build_object('version',1,'template_version',1,'step',jsonb_build_object('action_text','Other-owner saved step','state','saved')))));
 IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'other-owner saved step: %',r; END IF;
 r:=public.support_list_sessions(100,NULL,NULL,NULL,'desc',true);
 IF r->>'ok'<>'true' OR jsonb_array_length(r->'items')<>1 OR r#>>'{items,0,id}'<>sid::text
 OR r#>>'{items,0,saved_step_count}'<>'1' OR jsonb_array_length(r#>'{items,0,canonical_references}')<>1 THEN
  RAISE EXCEPTION 'cross-owner list leaked or omitted meaningful metadata: %',r; END IF;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='ac040000-0000-4000-8000-000000000001';
SET LOCAL request.jwt.claims='{"sub":"ac040000-0000-4000-8000-000000000001","role":"authenticated"}';
DO $$ DECLARE r jsonb;
BEGIN
 r:=public.support_list_sessions(100,NULL,NULL,NULL,'desc',true);
 IF r->>'ok'<>'true' OR EXISTS(SELECT FROM jsonb_array_elements(r->'items') x WHERE x->>'id'='ac049900-0000-4000-8000-000000000001') THEN
  RAISE EXCEPTION 'original-owner list exposed the other owner: %',r; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF public.support_session_summary('ac040000-0000-4000-8000-000000000001','ac049900-0000-4000-8000-000000000001') IS NOT NULL THEN
  RAISE EXCEPTION 'private summary helper exposed another owner'; END IF;
END $$;
COMMIT;
RESET request.jwt.claim.sub;
RESET request.jwt.claims;
SELECT 'PASS: actual history RPC, selected/previous saved step, discard/canonical identity, tombstone, empty, ownership and private function properties' AS result;
