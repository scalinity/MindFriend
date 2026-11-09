-- Support session contract test. NOT EXECUTED by its author.
-- DISPOSABLE LOCAL DATABASE ONLY, with the full migration chain through
-- 20261106230200_support_memory_context.sql applied. Synthetic users only; run as a
-- superuser/owner role (it switches to authenticated/service_role itself) and expect it
-- to leave the database dirty - drop the database afterwards. Fixture inserts into
-- auth.users / user_stats / exercises use minimal columns and may need adjusting to the
-- selected schema; adjust the FIXTURE block, not the assertions.
\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION pg_temp.eq(actual anyelement, expected anyelement, label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF actual IS DISTINCT FROM expected THEN
    RAISE EXCEPTION 'FAIL %: got %, want %', label, actual, expected;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', u::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, false);
  EXECUTE 'SET ROLE authenticated';
END $$;

-- ===================== FIXTURE =====================
RESET ROLE;
INSERT INTO auth.users (id, aud, role, email) VALUES
  ('aaaaaaaa-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'a@example.invalid'),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'b@example.invalid');
INSERT INTO public.user_stats (user_id) VALUES
  ('aaaaaaaa-0000-4000-8000-000000000001'), ('bbbbbbbb-0000-4000-8000-000000000002');
INSERT INTO public.exercises (id, title, description, type, duration_minutes)
  SELECT 'eeeeeeee-0000-4000-8000-000000000001', 'Synthetic grounding', 'synthetic', (enum_range(NULL::public.exercise_type))[1], 2;
INSERT INTO public.exercises (id, title, description, type, duration_minutes)
  SELECT 'eeeeeeee-0000-4000-8000-000000000002', 'Unrelated exercise', 'synthetic', (enum_range(NULL::public.exercise_type))[1], 5;
INSERT INTO public.conversations (id, user_id) VALUES
  ('cccccccc-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001'),
  ('cccccccc-0000-4000-8000-000000000002', 'bbbbbbbb-0000-4000-8000-000000000002');

-- ===================== S09: new domain does not touch Peer Support =====================
SELECT pg_temp.eq((SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'support_sessions' AND column_name IN ('seeker_id', 'listener_id'))::int, 2, 'Peer Support support_sessions untouched');
SELECT pg_temp.eq(to_regclass('public.support_work_sessions') IS NOT NULL, true, 'new domain table exists');
SELECT pg_temp.eq((SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'support_work_sessions' AND column_name = 'seeker_id')::int, 0, 'no Peer Support columns on new table');
SELECT pg_temp.eq(to_regprocedure('public.get_my_active_sessions()') IS NOT NULL OR to_regproc('public.get_my_active_sessions') IS NOT NULL, true, 'get_my_active_sessions still present');

-- ===================== OWNERSHIP / RLS =====================
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000001","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":null,"kind":"create","payload":{"title":"Work email","context_scope":"personalized","conversation_id":"cccccccc-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'ok', 'true', 'create ok');

-- forged attach of another user's conversation
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000002","session_id":"51000000-0000-4000-8000-000000000002","expected_revision":null,"kind":"create","payload":{"conversation_id":"cccccccc-0000-4000-8000-000000000002"}}'::jsonb)) ->> 'code', 'NOT_FOUND', 'forged conversation attach is NOT_FOUND');

-- direct writes are not possible for authenticated
DO $$ BEGIN
  BEGIN UPDATE public.support_work_sessions SET title = 'hijack'; RAISE EXCEPTION 'direct update unexpectedly allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN INSERT INTO public.support_work_sessions (id, user_id) VALUES (gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-000000000001'); RAISE EXCEPTION 'direct insert unexpectedly allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;

SELECT pg_temp.as_user('bbbbbbbb-0000-4000-8000-000000000002');
SELECT pg_temp.eq((public.support_get_session('51000000-0000-4000-8000-000000000001')) ->> 'code', 'NOT_FOUND', 'B cannot read A session');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"20000000-0000-4000-8000-000000000001","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":1,"kind":"update_session","payload":{"title":"x"}}'::jsonb)) ->> 'code', 'NOT_FOUND', 'B cannot mutate A session');
SELECT pg_temp.eq(jsonb_array_length(public.support_list_sessions() -> 'items'), 0, 'B list is empty');
SELECT pg_temp.eq((SELECT count(*) FROM public.support_work_sessions)::int, 0, 'RLS hides A rows from B');

RESET ROLE;
SET ROLE anon;
DO $$ BEGIN
  PERFORM public.support_apply_mutation('{}'::jsonb);
  RAISE EXCEPTION 'anon call unexpectedly allowed';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
RESET ROLE;

-- ===================== REPLAY / CAS =====================
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
-- same op id, new stale expected_revision, same payload => confirmed replay, no mutation
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000001","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":null,"kind":"create","payload":{"title":"Work email","context_scope":"personalized","conversation_id":"cccccccc-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'replayed', 'true', 'create replay');
-- same op id, different payload => OPERATION_ID_REUSED
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000001","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":null,"kind":"create","payload":{"title":"Different"}}'::jsonb)) ->> 'code', 'OPERATION_ID_REUSED', 'changed payload rejected');
-- accepted mutation bumps revision by exactly one; replay with stale revision returns the same revision
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000003","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":1,"kind":"update_session","payload":{"title":"Renamed"}}'::jsonb)) ->> 'revision', '2', 'revision +1');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000003","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":1,"kind":"update_session","payload":{"title":"Renamed"}}'::jsonb)) ->> 'revision', '2', 'replay keeps revision');
-- stale expected_revision on a NEW op id => REVISION_CONFLICT with snapshot
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000004","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":1,"kind":"update_session","payload":{"title":"Stale"}}'::jsonb)) ->> 'code', 'REVISION_CONFLICT', 'stale CAS');
-- semantic no-op
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000005","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":2,"kind":"update_session","payload":{"title":"Renamed"}}'::jsonb)) ->> 'no_op', 'true', 'no-op');
SELECT pg_temp.eq((SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000001'), 2::bigint, 'no-op did not bump');

-- ===================== LAZY ATTACHMENT =====================
-- A local-practice session (no conversation) attaches an owned conversation once.
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000040","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":null,"kind":"create","payload":{"title":"Local practice"}}'::jsonb)) ->> 'ok', 'true', 'create unattached');
RESET ROLE;
INSERT INTO public.conversations (id, user_id) VALUES ('cccccccc-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000041","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":1,"kind":"update_session","payload":{"conversation_id":"cccccccc-0000-4000-8000-000000000002"}}'::jsonb)) ->> 'code', 'NOT_FOUND', 'cannot attach another user conversation');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000042","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":1,"kind":"update_session","payload":{"conversation_id":"cccccccc-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'code', 'INVALID_PAYLOAD', 'one session per conversation');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000043","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":1,"kind":"update_session","payload":{"conversation_id":"cccccccc-0000-4000-8000-000000000003"}}'::jsonb)) ->> 'ok', 'true', 'attach new owned conversation');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000044","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":2,"kind":"update_session","payload":{"conversation_id":"cccccccc-0000-4000-8000-000000000003"}}'::jsonb)) ->> 'no_op', 'true', 'same attachment is a no-op');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000045","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":2,"kind":"update_session","payload":{"conversation_id":"cccccccc-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'code', 'INVALID_PAYLOAD', 'existing attachment is immutable');

-- ===================== NEXT STEP SEMANTICS =====================
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000010","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":2,"kind":"start_activity","payload":{"activity_id":"a1000000-0000-4000-8000-000000000001","template_key":"choose_step_v1"}}'::jsonb)) ->> 'ok', 'true', 'start step');
-- empty text cannot be saved for later
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000011","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":3,"kind":"checkpoint_activity","payload":{"activity_id":"a1000000-0000-4000-8000-000000000001","checkpoint":{"version":1,"template_version":1,"step":{"action_text":"  ","state":"saved"}},"active_ms":10,"pause":true}}'::jsonb)) ->> 'code', 'INVALID_PAYLOAD', 'empty step rejected');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000012","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":3,"kind":"checkpoint_activity","payload":{"activity_id":"a1000000-0000-4000-8000-000000000001","checkpoint":{"version":1,"template_version":1,"step":{"action_text":"Write the subject line","state":"saved"}},"active_ms":10,"pause":true}}'::jsonb)) ->> 'ok', 'true', 'save for later');
-- self-reported done, twice (different op ids) => one completion event
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000013","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":4,"kind":"start_activity","payload":{"activity_id":"a1000000-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'ok', 'true', 'resume');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000014","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":5,"kind":"finish_activity","payload":{"activity_id":"a1000000-0000-4000-8000-000000000001","outcome":"completed","result":{"step":{"action_text":"Write the subject line","state":"self_reported_done"}}}}'::jsonb)) ->> 'ok', 'true', 'I did it');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000015","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":6,"kind":"finish_activity","payload":{"activity_id":"a1000000-0000-4000-8000-000000000001","outcome":"completed","result":{"step":{"action_text":"Write the subject line","state":"self_reported_done"}}}}'::jsonb)) ->> 'no_op', 'true', 'second completion is a no-op');
SELECT pg_temp.eq((SELECT count(*) FROM public.support_session_events WHERE kind = 'activity_completed')::int, 1, 'exactly one completion event');
-- a stale checkpoint never moves a completed activity backward
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000016","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":6,"kind":"checkpoint_activity","payload":{"activity_id":"a1000000-0000-4000-8000-000000000001","checkpoint":{"version":1,"template_version":1},"active_ms":99}}'::jsonb)) ->> 'no_op', 'true', 'no backward move');

-- ===================== GROUNDING: SERVER MAPPING IS THE ONLY AUTHORITY (S01) =====================
-- Unmapped template: a supplied exercise id must NOT become the mapping.
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000018","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":6,"kind":"start_activity","payload":{"activity_id":"a2000000-0000-4000-8000-000000000009","template_key":"ground_present_v1","exercise_id":"eeeeeeee-0000-4000-8000-000000000002"}}'::jsonb)) ->> 'code', 'CONTENT_UNAVAILABLE', 'unmapped template rejects a supplied exercise id');
RESET ROLE;
UPDATE public.support_template_catalog SET exercise_id = 'eeeeeeee-0000-4000-8000-000000000001' WHERE template_key = 'ground_present_v1';
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000019","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":6,"kind":"start_activity","payload":{"activity_id":"a2000000-0000-4000-8000-000000000008","template_key":"ground_present_v1","exercise_id":"eeeeeeee-0000-4000-8000-000000000002"}}'::jsonb)) ->> 'code', 'CONTENT_UNAVAILABLE', 'mismatched exercise id rejected');

-- ===================== GROUNDING: ONE CANONICAL COMPLETION + XP =====================
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000020","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":6,"kind":"start_activity","payload":{"activity_id":"a2000000-0000-4000-8000-000000000001","template_key":"ground_present_v1","exercise_id":"eeeeeeee-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'ok', 'true', 'start grounding');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000021","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":7,"kind":"finish_activity","payload":{"activity_id":"a2000000-0000-4000-8000-000000000001","outcome":"completed","active_ms":60000}}'::jsonb)) -> 'xp' ->> 'amount', '30', 'xp awarded once');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000022","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":8,"kind":"finish_activity","payload":{"activity_id":"a2000000-0000-4000-8000-000000000001","outcome":"completed"}}'::jsonb)) ->> 'no_op', 'true', 'repeat completion no-op');
SELECT pg_temp.eq((SELECT count(*) FROM public.exercise_sessions WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001' AND completed)::int, 1, 'one completed exercise session');
SELECT pg_temp.eq((SELECT count(*) FROM public.exercise_sessions WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001' AND xp_awarded_at IS NOT NULL)::int, 1, 'one xp award');
-- a stopped grounding never completes or rewards
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000023","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":8,"kind":"start_activity","payload":{"activity_id":"a2000000-0000-4000-8000-000000000002","template_key":"ground_present_v1","exercise_id":"eeeeeeee-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'ok', 'true', 'start second grounding');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000024","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":9,"kind":"finish_activity","payload":{"activity_id":"a2000000-0000-4000-8000-000000000002","outcome":"stopped","reason":"skipped_all"}}'::jsonb)) ->> 'ok', 'true', 'stop skipped_all');
SELECT pg_temp.eq((SELECT count(*) FROM public.exercise_sessions WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001' AND completed)::int, 1, 'stopped did not complete');

-- ===================== DISCARD =====================
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000030","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":10,"kind":"start_activity","payload":{"activity_id":"a3000000-0000-4000-8000-000000000001","template_key":"untangle_thought_v1"}}'::jsonb)) ->> 'ok', 'true', 'start untangle');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000031","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":11,"kind":"finish_activity","payload":{"activity_id":"a3000000-0000-4000-8000-000000000001","outcome":"completed","checkpoint":{"version":1,"template_version":1,"responses":{"on_mind":"PRIVATE-ANSWER"}}}}'::jsonb)) ->> 'ok', 'true', 'finish with exact final checkpoint');
SELECT pg_temp.eq((SELECT checkpoint -> 'responses' ->> 'on_mind' FROM public.support_activities WHERE id = 'a3000000-0000-4000-8000-000000000001'), 'PRIVATE-ANSWER', 'final checkpoint stored');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000032","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":12,"kind":"record_reflection","payload":{"activity_id":"a3000000-0000-4000-8000-000000000001","outcome":"not_sure","note":"PRIVATE-NOTE"}}'::jsonb)) ->> 'ok', 'true', 'reflect');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000033","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":13,"kind":"discard_activity_answers","payload":{"activity_id":"a3000000-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'ok', 'true', 'discard');
SELECT pg_temp.eq((SELECT count(*) FROM public.support_activities WHERE id = 'a3000000-0000-4000-8000-000000000001' AND (checkpoint::text LIKE '%PRIVATE%' OR result::text LIKE '%PRIVATE%' OR reflection::text LIKE '%PRIVATE%'))::int, 0, 'no private text remains');
SELECT pg_temp.eq((SELECT status FROM public.support_activities WHERE id = 'a3000000-0000-4000-8000-000000000001'), 'completed', 'terminal status preserved');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000034","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":14,"kind":"discard_activity_answers","payload":{"activity_id":"a3000000-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'no_op', 'true', 'discard idempotent');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000035","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":14,"kind":"record_reflection","payload":{"activity_id":"a3000000-0000-4000-8000-000000000001","outcome":"helpful","note":"PRIVATE-LATE"}}'::jsonb)) ->> 'no_op', 'true', 'late reflection refused');
SELECT pg_temp.eq((SELECT count(*) FROM public.support_activities WHERE reflection::text LIKE '%PRIVATE-LATE%')::int, 0, 'late note not stored');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000036","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":14,"kind":"start_activity","payload":{"activity_id":"a3000000-0000-4000-8000-000000000002","template_key":"untangle_thought_v1"}}'::jsonb)) ->> 'ok', 'true', 'start second untangle');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000037","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":15,"kind":"discard_activity_answers","payload":{"activity_id":"a3000000-0000-4000-8000-000000000002"}}'::jsonb)) ->> 'ok', 'true', 'discard active');
SELECT pg_temp.eq((SELECT stop_reason FROM public.support_activities WHERE id = 'a3000000-0000-4000-8000-000000000002'), 'discarded', 'active discard stops');

-- ===================== PRIVACY / MEMORY / CONFIRMATION =====================
RESET ROLE;
INSERT INTO public.companion_memory (id, user_id, category, content) VALUES
  ('d0000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'boundaries', 'synthetic boundary');
-- legacy insert cannot fabricate approval/provenance
INSERT INTO public.companion_memory (id, user_id, category, content, origin, source_message_id, approved_from_fragment_id)
  VALUES ('d0000000-0000-4000-8000-000000000009', 'aaaaaaaa-0000-4000-8000-000000000001', 'preferences', 'forged', 'approved_candidate', gen_random_uuid(), gen_random_uuid());
SELECT pg_temp.eq((SELECT origin FROM public.companion_memory WHERE id = 'd0000000-0000-4000-8000-000000000009'), 'user_authored', 'forged origin reset');
SELECT pg_temp.eq((SELECT source_message_id IS NULL AND approved_from_fragment_id IS NULL FROM public.companion_memory WHERE id = 'd0000000-0000-4000-8000-000000000009'), true, 'forged provenance cleared');
DELETE FROM public.companion_memory WHERE id = 'd0000000-0000-4000-8000-000000000009';

-- Canonical request claims are SEEDED (the real chat function inserts them first).
INSERT INTO public.chat_requests (user_id, request_id, conversation_id, content_hash) VALUES
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001', 'hash-1'),
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000002', 'cccccccc-0000-4000-8000-000000000001', 'hash-2');
SET ROLE service_role;
-- S06: no claim -> NOT_FOUND; wrong hash -> OPERATION_ID_REUSED; missing terminal data -> INVALID_PAYLOAD
SELECT pg_temp.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-0000000000ff',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'x', 'content_hash', 'h', 'privacy_revision', 1,
  'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r', 'response', '{"ok":true}'::jsonb, 'response_status', 200))) ->> 'code', 'NOT_FOUND', 'missing claim');
SELECT pg_temp.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000001',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'x', 'content_hash', 'WRONG', 'privacy_revision', 1,
  'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r', 'response', '{"ok":true}'::jsonb, 'response_status', 200))) ->> 'code', 'OPERATION_ID_REUSED', 'mismatched content hash');
SELECT pg_temp.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000001',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'x', 'content_hash', 'hash-1', 'privacy_revision', 1,
  'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r'))) ->> 'code', 'INVALID_PAYLOAD', 'missing terminal response');
-- stale source revision (memory is at revision 1; claim revision 9) cannot confirm
SELECT pg_temp.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000001',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'x', 'content_hash', 'hash-1', 'privacy_revision', 1,
  'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r', 'response', '{"ok":true}'::jsonb, 'response_status', 200,
  'sources', jsonb_build_array(jsonb_build_object('kind', 'companion_memory', 'id', 'd0000000-0000-4000-8000-000000000001', 'revision', 9))))) ->> 'code', 'PRIVACY_REVISION_STALE', 'stale source revision');
-- success: message + receipt + terminal response in one transaction
SELECT pg_temp.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000001',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'support_session_id', '51000000-0000-4000-8000-000000000001',
  'assistant_content', 'second reply', 'content_origin', 'model', 'content_hash', 'hash-1', 'privacy_revision', 1, 'scope', 'personalized',
  'provider_vendor', 'openai', 'provider_model', 'synthetic-model', 'route_version', 'test-1',
  'response', '{"ok":true}'::jsonb, 'response_status', 200,
  'sources', jsonb_build_array(jsonb_build_object('kind', 'companion_memory', 'id', 'd0000000-0000-4000-8000-000000000001', 'revision', 1))))) ->> 'ok', 'true', 'confirm ok');
SELECT pg_temp.eq((SELECT response_status FROM public.chat_requests WHERE request_id = 'b1000000-0000-4000-8000-000000000001'), 200, 'terminal receipt saved atomically');
SELECT pg_temp.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000001',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'second reply', 'content_origin', 'model',
  'content_hash', 'hash-1', 'privacy_revision', 1, 'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'synthetic-model',
  'route_version', 'test-1', 'response', '{"ok":true}'::jsonb, 'response_status', 200))) ->> 'replayed', 'true', 'confirm replay');
RESET ROLE;

-- S08: stale correction conflicts; fresh one succeeds and bumps revision
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"30000000-0000-4000-8000-000000000010","kind":"memory_edit","payload":{"memory_id":"d0000000-0000-4000-8000-000000000001","content":"edited boundary","expected_revision":1}}'::jsonb)) ->> 'ok', 'true', 'edit rev1');
SELECT pg_temp.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"30000000-0000-4000-8000-000000000011","kind":"memory_edit","payload":{"memory_id":"d0000000-0000-4000-8000-000000000001","content":"older queued edit","expected_revision":1}}'::jsonb)) ->> 'code', 'REVISION_CONFLICT', 'stale correction');
RESET ROLE;
SELECT pg_temp.eq((SELECT revision FROM public.companion_memory WHERE id = 'd0000000-0000-4000-8000-000000000001'), 2, 'revision 2');
-- the assistant turn that cited revision 1 left future context (AC-06) and privacy bumped
SELECT pg_temp.eq((SELECT count(*) FROM public.support_suppressions s JOIN public.support_context_receipts r ON r.assistant_message_id = s.ref_id
                   WHERE s.kind = 'message' AND r.request_id = 'b1000000-0000-4000-8000-000000000001')::int, 1, 'old-revision turn suppressed');
SELECT pg_temp.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 2::bigint, 'edit bumped privacy');
-- S05: LEGACY endpoint style edit (direct UPDATE) goes through the same invariant
UPDATE public.companion_memory SET content = 'legacy edit' WHERE id = 'd0000000-0000-4000-8000-000000000001';
SELECT pg_temp.eq((SELECT revision FROM public.companion_memory WHERE id = 'd0000000-0000-4000-8000-000000000001'), 3, 'legacy edit bumps revision');
SELECT pg_temp.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 3::bigint, 'legacy edit bumps privacy');
-- confirmation prepared against the old privacy revision cannot land (interleaved legacy edit)
SET ROLE service_role;
SELECT pg_temp.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000002',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'late reply', 'content_origin', 'model', 'content_hash', 'hash-2',
  'privacy_revision', 1, 'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r',
  'response', '{"ok":true}'::jsonb, 'response_status', 200))) ->> 'code', 'PRIVACY_REVISION_STALE', 'stale privacy confirm rejected');
RESET ROLE;
-- fabricated approval on a fragment is reset; legacy soft delete forgets
INSERT INTO public.memory_fragments (id, user_id, fragment_type, key, value, review_state, approved_at, promoted_memory_id)
  VALUES ('f1000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'fact', 'k1', 'fragment fact', 'promoted', now(), gen_random_uuid());
SELECT pg_temp.eq((SELECT review_state FROM public.memory_fragments WHERE id = 'f1000000-0000-4000-8000-000000000001'), 'legacy_review', 'fabricated promotion reset');
UPDATE public.memory_fragments SET review_state = 'promoted', promoted_memory_id = gen_random_uuid() WHERE id = 'f1000000-0000-4000-8000-000000000001';
SELECT pg_temp.eq((SELECT review_state FROM public.memory_fragments WHERE id = 'f1000000-0000-4000-8000-000000000001'), 'legacy_review', 'fabricated promotion update reset');
UPDATE public.companion_memory SET deleted_at = now() WHERE id = 'd0000000-0000-4000-8000-000000000001';
SELECT pg_temp.eq((SELECT content FROM public.companion_memory WHERE id = 'd0000000-0000-4000-8000-000000000001'), '[removed]', 'soft delete removes plaintext');
SELECT pg_temp.eq((SELECT count(*) FROM public.support_suppressions WHERE kind = 'memory' AND ref_id = 'd0000000-0000-4000-8000-000000000001')::int, 1, 'soft delete suppresses');

-- S02/S07: approve a candidate sourced from a suppressed-able turn, then forget the ORIGINAL fragment id
INSERT INTO public.messages (id, conversation_id, role, content) VALUES
  ('f0000000-0000-4000-8000-000000000002', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'turn that states a fact');
INSERT INTO public.memory_fragments (id, user_id, fragment_type, key, value, review_state, source_message_id)
  VALUES ('f1000000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001', 'fact', 'k2', 'derived fact', 'pending', 'f0000000-0000-4000-8000-000000000002');
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"30000000-0000-4000-8000-000000000020","kind":"candidate_approve","payload":{"fragment_id":"f1000000-0000-4000-8000-000000000002"}}'::jsonb)) ->> 'ok', 'true', 'approve');
SELECT pg_temp.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"30000000-0000-4000-8000-000000000021","kind":"memory_forget","payload":{"fragment_id":"f1000000-0000-4000-8000-000000000002"}}'::jsonb)) ->> 'ok', 'true', 'forget by original fragment id (another device)');
RESET ROLE;
SELECT pg_temp.eq((SELECT count(*) FROM public.companion_memory WHERE approved_from_fragment_id = 'f1000000-0000-4000-8000-000000000002')::int, 0, 'canonical memory forgotten with its promoted fragment');
SET ROLE service_role;
SELECT pg_temp.eq(jsonb_array_length(public.support_context_sources('aaaaaaaa-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001', 20, true) -> 'memories'), 0, 'no forgotten memory in context');
SELECT pg_temp.eq(jsonb_array_length(public.support_context_sources('aaaaaaaa-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001', 20, false) -> 'memories'), 0, 'conversation-only reads no memory');
RESET ROLE;

-- S03: legacy fragment (conversation-level provenance) forgotten -> reopening that conversation yields no history
INSERT INTO public.memory_fragments (id, user_id, fragment_type, key, value, source_conversation_id)
  VALUES ('f1000000-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001', 'fact', 'k3', 'legacy fact', 'cccccccc-0000-4000-8000-000000000003');
INSERT INTO public.messages (id, conversation_id, role, content) VALUES
  ('f0000000-0000-4000-8000-000000000003', 'cccccccc-0000-4000-8000-000000000003', 'user', 'old transcript');
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"30000000-0000-4000-8000-000000000030","kind":"memory_forget","payload":{"fragment_id":"f1000000-0000-4000-8000-000000000003"}}'::jsonb)) ->> 'conversation_scope_excluded', 'true', 'legacy forget reports conversation scope');
RESET ROLE;
SET ROLE service_role;
SELECT pg_temp.eq(jsonb_array_length(public.support_context_sources('aaaaaaaa-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000003', 20, true) -> 'history'), 0, 'suppressed conversation contributes no history');
RESET ROLE;

-- S04: assemble -> discard -> confirm with the old activity revision is refused
-- (activity a3...01 was discarded earlier; its context_revision moved on)
INSERT INTO public.chat_requests (user_id, request_id, conversation_id, content_hash) VALUES
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000003', 'cccccccc-0000-4000-8000-000000000001', 'hash-3');
SET ROLE service_role;
SELECT pg_temp.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000003',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'used discarded text', 'content_hash', 'hash-3',
  'privacy_revision', (SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'),
  'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r', 'response', '{"ok":true}'::jsonb, 'response_status', 200,
  'sources', jsonb_build_array(jsonb_build_object('kind', 'activity_result', 'id', 'a3000000-0000-4000-8000-000000000001', 'revision', 1))))) ->> 'code', 'PRIVACY_REVISION_STALE', 'discarded activity cannot confirm');
RESET ROLE;


-- ===================== S02-R1: suppression DOMINATES later checkpoint/finish and advances CAS =====================
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"50000000-0000-4000-8000-000000000001","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":2,"kind":"start_activity","payload":{"activity_id":"a4000000-0000-4000-8000-000000000001","template_key":"untangle_thought_v1"}}'::jsonb)) ->> 'revision', '3', 'start derived activity');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"50000000-0000-4000-8000-000000000002","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":3,"kind":"checkpoint_activity","payload":{"activity_id":"a4000000-0000-4000-8000-000000000001","checkpoint":{"version":1,"template_version":1,"responses":{"on_mind":"PRIVATE-DERIVED"}},"active_ms":5}}'::jsonb)) ->> 'revision', '4', 'checkpoint with answers');
RESET ROLE;
INSERT INTO public.messages (id, conversation_id, role, content) VALUES
  ('f0000000-0000-4000-8000-000000000005', 'cccccccc-0000-4000-8000-000000000003', 'assistant', 'turn that proposed the activity');
INSERT INTO public.support_proposals (id, user_id, support_session_id, request_id, message_id, template_key, reason_code, privacy_revision, status, accepted_activity_id, expires_at)
  VALUES ('b9000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000010',
          'b9000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000005', 'untangle_thought_v1', 'general_option', 1, 'accepted',
          'a4000000-0000-4000-8000-000000000001', now() + interval '1 day');
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
-- user excludes the proposing turn; closure marks the accepted activity suppressed and scrubs it
SELECT pg_temp.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"50000000-0000-4000-8000-000000000003","kind":"suppress_source","payload":{"source_kind":"message","id":"f0000000-0000-4000-8000-000000000005"}}'::jsonb)) ->> 'ok', 'true', 'suppress proposing turn');
RESET ROLE;
SELECT pg_temp.eq((SELECT status || '/' || stop_reason FROM public.support_activities WHERE id = 'a4000000-0000-4000-8000-000000000001'), 'stopped/discarded', 'unfinished derived activity stopped');
SELECT pg_temp.eq((SELECT count(*) FROM public.support_activities WHERE id = 'a4000000-0000-4000-8000-000000000001' AND (checkpoint IS NOT NULL OR result::text LIKE '%PRIVATE%'))::int, 0, 'derived activity content scrubbed');
SELECT pg_temp.eq((SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000010'), 5::bigint, 'session revision advanced by suppression');
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
-- an old prepared attempt (expected revision 4) fails CAS
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"50000000-0000-4000-8000-000000000004","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":4,"kind":"checkpoint_activity","payload":{"activity_id":"a4000000-0000-4000-8000-000000000001","checkpoint":{"version":1,"template_version":1,"responses":{"on_mind":"PRIVATE-RESTORED"}},"active_ms":9}}'::jsonb)) ->> 'code', 'REVISION_CONFLICT', 'stale checkpoint fails CAS');
-- even a freshly rebased attempt cannot restore content
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"50000000-0000-4000-8000-000000000005","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":5,"kind":"checkpoint_activity","payload":{"activity_id":"a4000000-0000-4000-8000-000000000001","checkpoint":{"version":1,"template_version":1,"responses":{"on_mind":"PRIVATE-RESTORED"}},"active_ms":9}}'::jsonb)) ->> 'reason', 'activity_discarded', 'rebased checkpoint refused');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"50000000-0000-4000-8000-000000000006","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":5,"kind":"finish_activity","payload":{"activity_id":"a4000000-0000-4000-8000-000000000001","outcome":"completed","checkpoint":{"version":1,"template_version":1,"responses":{"on_mind":"PRIVATE-RESTORED"}}}}'::jsonb)) ->> 'reason', 'activity_discarded', 'rebased finish refused');
RESET ROLE;
SELECT pg_temp.eq((SELECT count(*) FROM public.support_activities WHERE checkpoint::text LIKE '%PRIVATE-RESTORED%' OR result::text LIKE '%PRIVATE-RESTORED%')::int, 0, 'no restored answers anywhere');

-- ===================== S03-R1: message-only provenance resolves through messages.conversation_id =====================
-- Conversation C3 is already suppressed (legacy fragment forget above). Shape under test:
-- source_message_id set, source_conversation_id NULL.
SELECT set_config('support.memory_rpc', 'on', false);
INSERT INTO public.companion_memory (id, user_id, category, content, origin, source_message_id, source_conversation_id)
  VALUES ('d0000000-0000-4000-8000-000000000031', 'aaaaaaaa-0000-4000-8000-000000000001', 'preferences', 'message-only provenance memory',
          'approved_candidate', 'f0000000-0000-4000-8000-000000000003', NULL);
SELECT set_config('support.memory_rpc', 'off', false);
INSERT INTO public.companion_memory (id, user_id, category, content)
  VALUES ('d0000000-0000-4000-8000-000000000032', 'aaaaaaaa-0000-4000-8000-000000000001', 'preferences', 'clean memory');
INSERT INTO public.memory_fragments (id, user_id, fragment_type, key, value, review_state, source_message_id, source_conversation_id)
  VALUES ('f1000000-0000-4000-8000-000000000031', 'aaaaaaaa-0000-4000-8000-000000000001', 'fact', 'k31', 'message-only candidate', 'pending',
          'f0000000-0000-4000-8000-000000000003', NULL);
SET ROLE service_role;
SELECT pg_temp.eq((SELECT count(*) FROM jsonb_array_elements(public.support_context_sources('aaaaaaaa-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001', 20, true) -> 'memories') m
                   WHERE m ->> 'id' = 'd0000000-0000-4000-8000-000000000031')::int, 0, 'message-only provenance memory excluded from context');
SELECT pg_temp.eq((SELECT count(*) FROM jsonb_array_elements(public.support_context_sources('aaaaaaaa-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001', 20, true) -> 'memories') m
                   WHERE m ->> 'id' = 'd0000000-0000-4000-8000-000000000032')::int, 1, 'clean memory still included');
RESET ROLE;
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq((SELECT count(*) FROM jsonb_array_elements(public.support_list_memory() -> 'candidates') c WHERE c ->> 'id' = 'f1000000-0000-4000-8000-000000000031')::int, 0, 'message-only candidate not offered for review');
SELECT pg_temp.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"50000000-0000-4000-8000-000000000010","kind":"candidate_approve","payload":{"fragment_id":"f1000000-0000-4000-8000-000000000031"}}'::jsonb)) ->> 'code', 'CONTENT_UNAVAILABLE', 'cannot approve message-only candidate of a suppressed conversation');
RESET ROLE;

-- ===================== S05-R1: any new ACTIVE memory advances the privacy revision =====================
INSERT INTO public.chat_requests (user_id, request_id, conversation_id, content_hash) VALUES
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000004', 'cccccccc-0000-4000-8000-000000000001', 'hash-4'),
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000005', 'cccccccc-0000-4000-8000-000000000001', 'hash-5');
CREATE TEMP TABLE s05 AS SELECT privacy_revision AS before_rev FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001';
-- legacy create of an eligible boundary
INSERT INTO public.companion_memory (id, user_id, category, content) VALUES
  ('d0000000-0000-4000-8000-000000000041', 'aaaaaaaa-0000-4000-8000-000000000001', 'boundaries', 'new boundary after request started');
SELECT pg_temp.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') > (SELECT before_rev FROM s05), true, 'legacy insert advanced privacy revision');
SET ROLE service_role;
SELECT pg_temp.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000004',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'built before the boundary', 'content_hash', 'hash-4',
  'privacy_revision', (SELECT before_rev FROM s05), 'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r',
  'response', '{"ok":true}'::jsonb, 'response_status', 200))) ->> 'code', 'PRIVACY_REVISION_STALE', 'request prepared before the boundary cannot confirm');
RESET ROLE;
-- approval path
INSERT INTO public.memory_fragments (id, user_id, fragment_type, key, value, review_state)
  VALUES ('f1000000-0000-4000-8000-000000000041', 'aaaaaaaa-0000-4000-8000-000000000001', 'preference', 'k41', 'approved later', 'pending');
CREATE TEMP TABLE s05b AS SELECT privacy_revision AS before_rev FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001';
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"50000000-0000-4000-8000-000000000011","kind":"candidate_approve","payload":{"fragment_id":"f1000000-0000-4000-8000-000000000041"}}'::jsonb)) ->> 'ok', 'true', 'approve fresh candidate');
RESET ROLE;
SELECT pg_temp.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') > (SELECT before_rev FROM s05b), true, 'approval advanced privacy revision');
SET ROLE service_role;
SELECT pg_temp.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000005',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'built before the approval', 'content_hash', 'hash-5',
  'privacy_revision', (SELECT before_rev FROM s05b), 'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r',
  'response', '{"ok":true}'::jsonb, 'response_status', 200))) ->> 'code', 'PRIVACY_REVISION_STALE', 'request prepared before approval cannot confirm');
RESET ROLE;

-- ===================== S06-R1 (partial): transaction-generated ids are stored with the response =====================
-- Rendering the final client response from them is the chat integration's job (M4).
SELECT pg_temp.eq((SELECT response -> 'support_confirmed' ->> 'message_id' IS NOT NULL FROM public.chat_requests WHERE request_id = 'b1000000-0000-4000-8000-000000000001'), true, 'confirmed ids stored with the terminal response');

\echo 'support_session.sql: all assertions passed (NOT EXECUTED by its author)'
