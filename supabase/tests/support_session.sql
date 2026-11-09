-- Support session contract test. NOT EXECUTED by its author.
-- DISPOSABLE LOCAL DATABASE ONLY, with the full migration chain through
-- 20261106230200_support_memory_context.sql applied. Synthetic users only; run as a
-- superuser/owner role (it switches to authenticated/service_role itself) and expect it
-- to leave the database dirty - drop the database afterwards. Fixture inserts into
-- auth.users / user_stats / exercises use minimal columns and may need adjusting to the
-- selected schema; adjust the FIXTURE block, not the assertions.
\set ON_ERROR_STOP on

-- Scratch schema: the helpers and captured values live in REAL (non-temporary) objects with
-- explicit grants, because the test switches to authenticated/service_role, which have no
-- access to objects in the creator's session-private temporary schema.
CREATE SCHEMA IF NOT EXISTS support_test;
GRANT USAGE ON SCHEMA support_test TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION support_test.eq(actual anyelement, expected anyelement, label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF actual IS DISTINCT FROM expected THEN
    RAISE EXCEPTION 'FAIL %: got %, want %', label, actual, expected;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION support_test.as_user(u uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', u::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, false);
  EXECUTE 'SET ROLE authenticated';
END $$;

-- ===================== FIXTURE =====================
RESET ROLE;
INSERT INTO public.supported_languages(code,name,native_name,is_active) VALUES('en','English','English',true) ON CONFLICT DO NOTHING;
INSERT INTO public.level_thresholds(level,xp_required,title) VALUES(1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO public.skill_thresholds(level,xp_required,title) VALUES(1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
-- The catalog fixture independently validates the real mapping. Stage the unmapped case for S01.
UPDATE public.support_template_catalog SET exercise_id=NULL WHERE template_key='ground_present_v1';

INSERT INTO auth.users (id, aud, role, email) VALUES
  ('aaaaaaaa-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'a@example.invalid'),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'b@example.invalid');
INSERT INTO public.user_stats (user_id) VALUES
  ('aaaaaaaa-0000-4000-8000-000000000001'), ('bbbbbbbb-0000-4000-8000-000000000002') ON CONFLICT DO NOTHING;
INSERT INTO public.exercises (id, title, description, type, duration_minutes)
  SELECT 'eeeeeeee-0000-4000-8000-000000000001', 'Synthetic grounding', 'synthetic', (enum_range(NULL::public.exercise_type))[1], 2;
INSERT INTO public.exercises (id, title, description, type, duration_minutes)
  SELECT 'eeeeeeee-0000-4000-8000-000000000002', 'Unrelated exercise', 'synthetic', (enum_range(NULL::public.exercise_type))[1], 5;
INSERT INTO public.conversations (id, user_id) VALUES
  ('cccccccc-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001'),
  ('cccccccc-0000-4000-8000-000000000002', 'bbbbbbbb-0000-4000-8000-000000000002');

-- ===================== S09: new domain does not touch Peer Support =====================
SELECT support_test.eq((SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'support_sessions' AND column_name IN ('seeker_id', 'listener_id'))::int, 2, 'Peer Support support_sessions untouched');
SELECT support_test.eq(to_regclass('public.support_work_sessions') IS NOT NULL, true, 'new domain table exists');
SELECT support_test.eq((SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'support_work_sessions' AND column_name = 'seeker_id')::int, 0, 'no Peer Support columns on new table');
SELECT support_test.eq(to_regprocedure('public.get_my_active_sessions()') IS NOT NULL OR to_regproc('public.get_my_active_sessions') IS NOT NULL, true, 'get_my_active_sessions still present');

-- ===================== OWNERSHIP / RLS =====================
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000001","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":null,"kind":"create","payload":{"title":"Work email","context_scope":"personalized","conversation_id":"cccccccc-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'ok', 'true', 'create ok');

-- forged attach of another user's conversation
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000002","session_id":"51000000-0000-4000-8000-000000000002","expected_revision":null,"kind":"create","payload":{"conversation_id":"cccccccc-0000-4000-8000-000000000002"}}'::jsonb)) ->> 'code', 'NOT_FOUND', 'forged conversation attach is NOT_FOUND');

-- direct writes are not possible for authenticated
DO $$ BEGIN
  BEGIN UPDATE public.support_work_sessions SET title = 'hijack'; RAISE EXCEPTION 'direct update unexpectedly allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN INSERT INTO public.support_work_sessions (id, user_id) VALUES (gen_random_uuid(), 'aaaaaaaa-0000-4000-8000-000000000001'); RAISE EXCEPTION 'direct insert unexpectedly allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;

SELECT support_test.as_user('bbbbbbbb-0000-4000-8000-000000000002');
SELECT support_test.eq((public.support_get_session('51000000-0000-4000-8000-000000000001')) ->> 'code', 'NOT_FOUND', 'B cannot read A session');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"20000000-0000-4000-8000-000000000001","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":1,"kind":"update_session","payload":{"title":"x"}}'::jsonb)) ->> 'code', 'NOT_FOUND', 'B cannot mutate A session');
SELECT support_test.eq(jsonb_array_length(public.support_list_sessions() -> 'items'), 0, 'B list is empty');
SELECT support_test.eq((SELECT count(*) FROM public.support_work_sessions)::int, 0, 'RLS hides A rows from B');

RESET ROLE;
SET ROLE anon;
DO $$ BEGIN
  PERFORM public.support_apply_mutation('{}'::jsonb);
  RAISE EXCEPTION 'anon call unexpectedly allowed';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
RESET ROLE;

-- ===================== REPLAY / CAS =====================
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
-- same op id, new stale expected_revision, same payload => confirmed replay, no mutation
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000001","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":null,"kind":"create","payload":{"title":"Work email","context_scope":"personalized","conversation_id":"cccccccc-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'replayed', 'true', 'create replay');
-- same op id, different payload => OPERATION_ID_REUSED
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000001","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":null,"kind":"create","payload":{"title":"Different"}}'::jsonb)) ->> 'code', 'OPERATION_ID_REUSED', 'changed payload rejected');
-- accepted mutation bumps revision by exactly one; replay with stale revision returns the same revision
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000003","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":1,"kind":"update_session","payload":{"title":"Renamed"}}'::jsonb)) ->> 'revision', '2', 'revision +1');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000003","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":1,"kind":"update_session","payload":{"title":"Renamed"}}'::jsonb)) ->> 'revision', '2', 'replay keeps revision');
-- stale expected_revision on a NEW op id => REVISION_CONFLICT with snapshot
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000004","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":1,"kind":"update_session","payload":{"title":"Stale"}}'::jsonb)) ->> 'code', 'REVISION_CONFLICT', 'stale CAS');
-- semantic no-op
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000005","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":2,"kind":"update_session","payload":{"title":"Renamed"}}'::jsonb)) ->> 'no_op', 'true', 'no-op');
SELECT support_test.eq((SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000001'), 2::bigint, 'no-op did not bump');

-- ===================== LAZY ATTACHMENT =====================
-- A local-practice session (no conversation) attaches an owned conversation once.
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000040","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":null,"kind":"create","payload":{"title":"Local practice"}}'::jsonb)) ->> 'ok', 'true', 'create unattached');
RESET ROLE;
INSERT INTO public.conversations (id, user_id) VALUES ('cccccccc-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000041","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":1,"kind":"update_session","payload":{"conversation_id":"cccccccc-0000-4000-8000-000000000002"}}'::jsonb)) ->> 'code', 'NOT_FOUND', 'cannot attach another user conversation');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000042","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":1,"kind":"update_session","payload":{"conversation_id":"cccccccc-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'code', 'INVALID_PAYLOAD', 'one session per conversation');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000043","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":1,"kind":"update_session","payload":{"conversation_id":"cccccccc-0000-4000-8000-000000000003"}}'::jsonb)) ->> 'ok', 'true', 'attach new owned conversation');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000044","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":2,"kind":"update_session","payload":{"conversation_id":"cccccccc-0000-4000-8000-000000000003"}}'::jsonb)) ->> 'no_op', 'true', 'same attachment is a no-op');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000045","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":2,"kind":"update_session","payload":{"conversation_id":"cccccccc-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'code', 'INVALID_PAYLOAD', 'existing attachment is immutable');

-- ===================== NEXT STEP SEMANTICS =====================
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000010","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":2,"kind":"start_activity","payload":{"activity_id":"a1000000-0000-4000-8000-000000000001","template_key":"choose_step_v1"}}'::jsonb)) ->> 'ok', 'true', 'start step');
-- empty text cannot be saved for later
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000011","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":3,"kind":"checkpoint_activity","payload":{"activity_id":"a1000000-0000-4000-8000-000000000001","checkpoint":{"version":1,"template_version":1,"step":{"action_text":"  ","state":"saved"}},"active_ms":10,"pause":true}}'::jsonb)) ->> 'code', 'INVALID_PAYLOAD', 'empty step rejected');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000012","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":3,"kind":"checkpoint_activity","payload":{"activity_id":"a1000000-0000-4000-8000-000000000001","checkpoint":{"version":1,"template_version":1,"step":{"action_text":"Write the subject line","state":"saved"}},"active_ms":10,"pause":true}}'::jsonb)) ->> 'ok', 'true', 'save for later');
-- self-reported done, twice (different op ids) => one completion event
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000013","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":4,"kind":"start_activity","payload":{"activity_id":"a1000000-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'ok', 'true', 'resume');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000014","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":5,"kind":"finish_activity","payload":{"activity_id":"a1000000-0000-4000-8000-000000000001","outcome":"completed","result":{"step":{"action_text":"Write the subject line","state":"self_reported_done"}}}}'::jsonb)) ->> 'ok', 'true', 'I did it');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000015","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":6,"kind":"finish_activity","payload":{"activity_id":"a1000000-0000-4000-8000-000000000001","outcome":"completed","result":{"step":{"action_text":"Write the subject line","state":"self_reported_done"}}}}'::jsonb)) ->> 'no_op', 'true', 'second completion is a no-op');
SELECT support_test.eq((SELECT count(*) FROM public.support_session_events WHERE kind = 'activity_completed')::int, 1, 'exactly one completion event');
-- a stale checkpoint never moves a completed activity backward
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000016","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":6,"kind":"checkpoint_activity","payload":{"activity_id":"a1000000-0000-4000-8000-000000000001","checkpoint":{"version":1,"template_version":1},"active_ms":99}}'::jsonb)) ->> 'no_op', 'true', 'no backward move');

-- ===================== GROUNDING: SERVER MAPPING IS THE ONLY AUTHORITY (S01) =====================
-- Unmapped template: a supplied exercise id must NOT become the mapping.
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000018","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":6,"kind":"start_activity","payload":{"activity_id":"a2000000-0000-4000-8000-000000000009","template_key":"ground_present_v1","exercise_id":"eeeeeeee-0000-4000-8000-000000000002"}}'::jsonb)) ->> 'code', 'CONTENT_UNAVAILABLE', 'unmapped template rejects a supplied exercise id');
RESET ROLE;
UPDATE public.support_template_catalog SET exercise_id = 'eeeeeeee-0000-4000-8000-000000000001' WHERE template_key = 'ground_present_v1';
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000019","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":6,"kind":"start_activity","payload":{"activity_id":"a2000000-0000-4000-8000-000000000008","template_key":"ground_present_v1","exercise_id":"eeeeeeee-0000-4000-8000-000000000002"}}'::jsonb)) ->> 'code', 'CONTENT_UNAVAILABLE', 'mismatched exercise id rejected');

-- ===================== GROUNDING: ONE CANONICAL COMPLETION + XP =====================
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000020","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":6,"kind":"start_activity","payload":{"activity_id":"a2000000-0000-4000-8000-000000000001","template_key":"ground_present_v1","exercise_id":"eeeeeeee-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'ok', 'true', 'start grounding');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000021","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":7,"kind":"finish_activity","payload":{"activity_id":"a2000000-0000-4000-8000-000000000001","outcome":"completed","active_ms":60000}}'::jsonb)) -> 'xp' ->> 'amount', '30', 'xp awarded once');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000022","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":8,"kind":"finish_activity","payload":{"activity_id":"a2000000-0000-4000-8000-000000000001","outcome":"completed"}}'::jsonb)) ->> 'no_op', 'true', 'repeat completion no-op');
SELECT support_test.eq((SELECT count(*) FROM public.exercise_sessions WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001' AND completed)::int, 1, 'one completed exercise session');
SELECT support_test.eq((SELECT count(*) FROM public.exercise_sessions WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001' AND xp_awarded_at IS NOT NULL)::int, 1, 'one xp award');
-- a stopped grounding never completes or rewards
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000023","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":8,"kind":"start_activity","payload":{"activity_id":"a2000000-0000-4000-8000-000000000002","template_key":"ground_present_v1","exercise_id":"eeeeeeee-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'ok', 'true', 'start second grounding');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000024","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":9,"kind":"finish_activity","payload":{"activity_id":"a2000000-0000-4000-8000-000000000002","outcome":"stopped","reason":"skipped_all"}}'::jsonb)) ->> 'ok', 'true', 'stop skipped_all');
SELECT support_test.eq((SELECT count(*) FROM public.exercise_sessions WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001' AND completed)::int, 1, 'stopped did not complete');

-- ===================== DISCARD =====================
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000030","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":10,"kind":"start_activity","payload":{"activity_id":"a3000000-0000-4000-8000-000000000001","template_key":"untangle_thought_v1"}}'::jsonb)) ->> 'ok', 'true', 'start untangle');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000031","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":11,"kind":"finish_activity","payload":{"activity_id":"a3000000-0000-4000-8000-000000000001","outcome":"completed","checkpoint":{"version":1,"template_version":1,"responses":{"on_mind":"PRIVATE-ANSWER"}}}}'::jsonb)) ->> 'ok', 'true', 'finish with exact final checkpoint');
SELECT support_test.eq((SELECT checkpoint -> 'responses' ->> 'on_mind' FROM public.support_activities WHERE id = 'a3000000-0000-4000-8000-000000000001'), 'PRIVATE-ANSWER', 'final checkpoint stored');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000032","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":12,"kind":"record_reflection","payload":{"activity_id":"a3000000-0000-4000-8000-000000000001","outcome":"not_sure","note":"PRIVATE-NOTE"}}'::jsonb)) ->> 'ok', 'true', 'reflect');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000033","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":13,"kind":"discard_activity_answers","payload":{"activity_id":"a3000000-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'ok', 'true', 'discard');
SELECT support_test.eq((SELECT count(*) FROM public.support_activities WHERE id = 'a3000000-0000-4000-8000-000000000001' AND (checkpoint::text LIKE '%PRIVATE%' OR result::text LIKE '%PRIVATE%' OR reflection::text LIKE '%PRIVATE%'))::int, 0, 'no private text remains');
SELECT support_test.eq((SELECT status FROM public.support_activities WHERE id = 'a3000000-0000-4000-8000-000000000001'), 'completed', 'terminal status preserved');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000034","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":14,"kind":"discard_activity_answers","payload":{"activity_id":"a3000000-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'no_op', 'true', 'discard idempotent');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000035","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":14,"kind":"record_reflection","payload":{"activity_id":"a3000000-0000-4000-8000-000000000001","outcome":"helpful","note":"PRIVATE-LATE"}}'::jsonb)) ->> 'no_op', 'true', 'late reflection refused');
SELECT support_test.eq((SELECT count(*) FROM public.support_activities WHERE reflection::text LIKE '%PRIVATE-LATE%')::int, 0, 'late note not stored');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000036","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":14,"kind":"start_activity","payload":{"activity_id":"a3000000-0000-4000-8000-000000000002","template_key":"untangle_thought_v1"}}'::jsonb)) ->> 'ok', 'true', 'start second untangle');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-000000000037","session_id":"51000000-0000-4000-8000-000000000001","expected_revision":15,"kind":"discard_activity_answers","payload":{"activity_id":"a3000000-0000-4000-8000-000000000002"}}'::jsonb)) ->> 'ok', 'true', 'discard active');
SELECT support_test.eq((SELECT stop_reason FROM public.support_activities WHERE id = 'a3000000-0000-4000-8000-000000000002'), 'discarded', 'active discard stops');

-- ===================== PRIVACY / MEMORY / CONFIRMATION =====================
RESET ROLE;
INSERT INTO public.companion_memory (id, user_id, category, content) VALUES
  ('d0000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'boundaries', 'synthetic boundary');
-- legacy insert cannot fabricate approval/provenance
INSERT INTO public.companion_memory (id, user_id, category, content, origin, source_message_id, approved_from_fragment_id)
  VALUES ('d0000000-0000-4000-8000-000000000009', 'aaaaaaaa-0000-4000-8000-000000000001', 'preferences', 'forged', 'approved_candidate', gen_random_uuid(), gen_random_uuid());
SELECT support_test.eq((SELECT origin FROM public.companion_memory WHERE id = 'd0000000-0000-4000-8000-000000000009'), 'user_authored', 'forged origin reset');
SELECT support_test.eq((SELECT source_message_id IS NULL AND approved_from_fragment_id IS NULL FROM public.companion_memory WHERE id = 'd0000000-0000-4000-8000-000000000009'), true, 'forged provenance cleared');
DELETE FROM public.companion_memory WHERE id = 'd0000000-0000-4000-8000-000000000009';

-- Capture the current privacy revision after earlier discard and memory insert/delete operations.
CREATE TABLE support_test.initial_privacy AS SELECT privacy_revision FROM public.support_privacy_state WHERE user_id='aaaaaaaa-0000-4000-8000-000000000001';
GRANT SELECT ON support_test.initial_privacy TO authenticated, service_role;

-- Canonical request claims are SEEDED (the real chat function inserts them first).
INSERT INTO public.chat_requests (user_id, request_id, conversation_id, content_hash) VALUES
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001', 'hash-1'),
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000002', 'cccccccc-0000-4000-8000-000000000001', 'hash-2');
SET ROLE service_role;
-- S06: no claim -> NOT_FOUND; wrong hash -> OPERATION_ID_REUSED; missing terminal data -> INVALID_PAYLOAD
SELECT support_test.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-0000000000ff',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'x', 'content_hash', 'h', 'privacy_revision', (SELECT privacy_revision FROM support_test.initial_privacy),
  'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r', 'response', '{"ok":true}'::jsonb, 'response_status', 200))) ->> 'code', 'NOT_FOUND', 'missing claim');
SELECT support_test.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000001',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'x', 'content_hash', 'WRONG', 'privacy_revision', (SELECT privacy_revision FROM support_test.initial_privacy),
  'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r', 'response', '{"ok":true}'::jsonb, 'response_status', 200))) ->> 'code', 'OPERATION_ID_REUSED', 'mismatched content hash');
SELECT support_test.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000001',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'x', 'content_hash', 'hash-1', 'privacy_revision', (SELECT privacy_revision FROM support_test.initial_privacy),
  'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r'))) ->> 'code', 'INVALID_PAYLOAD', 'missing terminal response');
-- stale source revision (memory is at revision 1; claim revision 9) cannot confirm
SELECT support_test.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000001',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'x', 'content_hash', 'hash-1', 'privacy_revision', (SELECT privacy_revision FROM support_test.initial_privacy),
  'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r', 'response', '{"ok":true}'::jsonb, 'response_status', 200,
  'sources', jsonb_build_array(jsonb_build_object('kind', 'companion_memory', 'id', 'd0000000-0000-4000-8000-000000000001', 'revision', 9))))) ->> 'code', 'PRIVACY_REVISION_STALE', 'stale source revision');
-- success: message + receipt + terminal response in one transaction
SELECT support_test.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000001',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'support_session_id', '51000000-0000-4000-8000-000000000001',
  'assistant_content', 'second reply', 'content_origin', 'model', 'content_hash', 'hash-1', 'privacy_revision', (SELECT privacy_revision FROM support_test.initial_privacy), 'scope', 'personalized',
  'provider_vendor', 'openai', 'provider_model', 'synthetic-model', 'route_version', 'test-1',
  'response', '{"ok":true}'::jsonb, 'response_status', 200,
  'sources', jsonb_build_array(jsonb_build_object('kind', 'companion_memory', 'id', 'd0000000-0000-4000-8000-000000000001', 'revision', 1))))) ->> 'ok', 'true', 'confirm ok');
SELECT support_test.eq((SELECT response_status FROM public.chat_requests WHERE request_id = 'b1000000-0000-4000-8000-000000000001'), 200, 'terminal receipt saved atomically');
SELECT support_test.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000001',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'second reply', 'content_origin', 'model',
  'content_hash', 'hash-1', 'privacy_revision', (SELECT privacy_revision FROM support_test.initial_privacy), 'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'synthetic-model',
  'route_version', 'test-1', 'response', '{"ok":true}'::jsonb, 'response_status', 200))) ->> 'replayed', 'true', 'confirm replay');
RESET ROLE;

-- S08: stale correction conflicts; fresh one succeeds and bumps revision
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"30000000-0000-4000-8000-000000000010","kind":"memory_edit","payload":{"memory_id":"d0000000-0000-4000-8000-000000000001","content":"edited boundary","expected_revision":1}}'::jsonb)) ->> 'ok', 'true', 'edit rev1');
SELECT support_test.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"30000000-0000-4000-8000-000000000011","kind":"memory_edit","payload":{"memory_id":"d0000000-0000-4000-8000-000000000001","content":"older queued edit","expected_revision":1}}'::jsonb)) ->> 'code', 'REVISION_CONFLICT', 'stale correction');
RESET ROLE;
SELECT support_test.eq((SELECT revision FROM public.companion_memory WHERE id = 'd0000000-0000-4000-8000-000000000001'), 2, 'revision 2');
-- the assistant turn that cited revision 1 left future context (AC-06) and privacy bumped
SELECT support_test.eq((SELECT count(*) FROM public.support_suppressions s JOIN public.support_context_receipts r ON r.assistant_message_id = s.ref_id
                   WHERE s.kind = 'message' AND r.request_id = 'b1000000-0000-4000-8000-000000000001')::int, 1, 'old-revision turn suppressed');
SELECT support_test.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'), (SELECT privacy_revision+1 FROM support_test.initial_privacy), 'edit bumped privacy');
-- S05: LEGACY endpoint style edit (direct UPDATE) goes through the same invariant
UPDATE public.companion_memory SET content = 'legacy edit' WHERE id = 'd0000000-0000-4000-8000-000000000001';
SELECT support_test.eq((SELECT revision FROM public.companion_memory WHERE id = 'd0000000-0000-4000-8000-000000000001'), 3, 'legacy edit bumps revision');
SELECT support_test.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'), (SELECT privacy_revision+2 FROM support_test.initial_privacy), 'legacy edit bumps privacy');
-- confirmation prepared against the old privacy revision cannot land (interleaved legacy edit)
SET ROLE service_role;
SELECT support_test.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000002',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'late reply', 'content_origin', 'model', 'content_hash', 'hash-2',
  'privacy_revision', 1, 'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r',
  'response', '{"ok":true}'::jsonb, 'response_status', 200))) ->> 'code', 'PRIVACY_REVISION_STALE', 'stale privacy confirm rejected');
RESET ROLE;
-- fabricated approval on a fragment is reset; legacy soft delete forgets
INSERT INTO public.memory_fragments (id, user_id, fragment_type, key, value, review_state, approved_at, promoted_memory_id)
  VALUES ('f1000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'fact', 'k1', 'fragment fact', 'promoted', now(), gen_random_uuid());
SELECT support_test.eq((SELECT review_state FROM public.memory_fragments WHERE id = 'f1000000-0000-4000-8000-000000000001'), 'legacy_review', 'fabricated promotion reset');
UPDATE public.memory_fragments SET review_state = 'promoted', promoted_memory_id = gen_random_uuid() WHERE id = 'f1000000-0000-4000-8000-000000000001';
SELECT support_test.eq((SELECT review_state FROM public.memory_fragments WHERE id = 'f1000000-0000-4000-8000-000000000001'), 'legacy_review', 'fabricated promotion update reset');
UPDATE public.companion_memory SET deleted_at = now() WHERE id = 'd0000000-0000-4000-8000-000000000001';
SELECT support_test.eq((SELECT content FROM public.companion_memory WHERE id = 'd0000000-0000-4000-8000-000000000001'), '[removed]', 'soft delete removes plaintext');
SELECT support_test.eq((SELECT count(*) FROM public.support_suppressions WHERE kind = 'memory' AND ref_id = 'd0000000-0000-4000-8000-000000000001')::int, 1, 'soft delete suppresses');

-- S02/S07: approve a candidate sourced from a suppressed-able turn, then forget the ORIGINAL fragment id
INSERT INTO public.messages (id, conversation_id, role, content) VALUES
  ('f0000000-0000-4000-8000-000000000002', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'turn that states a fact');
INSERT INTO public.memory_fragments (id, user_id, fragment_type, key, value, review_state, source_message_id)
  VALUES ('f1000000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001', 'fact', 'k2', 'derived fact', 'pending', 'f0000000-0000-4000-8000-000000000002');
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"30000000-0000-4000-8000-000000000020","kind":"candidate_approve","payload":{"fragment_id":"f1000000-0000-4000-8000-000000000002"}}'::jsonb)) ->> 'ok', 'true', 'approve');
SELECT support_test.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"30000000-0000-4000-8000-000000000021","kind":"memory_forget","payload":{"fragment_id":"f1000000-0000-4000-8000-000000000002"}}'::jsonb)) ->> 'ok', 'true', 'forget by original fragment id (another device)');
RESET ROLE;
SELECT support_test.eq((SELECT count(*) FROM public.companion_memory WHERE approved_from_fragment_id = 'f1000000-0000-4000-8000-000000000002')::int, 0, 'canonical memory forgotten with its promoted fragment');
SET ROLE service_role;
SELECT support_test.eq(jsonb_array_length(public.support_context_sources('aaaaaaaa-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001', 20, true) -> 'memories'), 0, 'no forgotten memory in context');
SELECT support_test.eq(jsonb_array_length(public.support_context_sources('aaaaaaaa-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001', 20, false) -> 'memories'), 0, 'conversation-only reads no memory');
RESET ROLE;

-- S03: legacy fragment (conversation-level provenance) forgotten -> reopening that conversation yields no history
INSERT INTO public.memory_fragments (id, user_id, fragment_type, key, value, source_conversation_id)
  VALUES ('f1000000-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001', 'fact', 'k3', 'legacy fact', 'cccccccc-0000-4000-8000-000000000003');
INSERT INTO public.messages (id, conversation_id, role, content) VALUES
  ('f0000000-0000-4000-8000-000000000003', 'cccccccc-0000-4000-8000-000000000003', 'user', 'old transcript');
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"30000000-0000-4000-8000-000000000030","kind":"memory_forget","payload":{"fragment_id":"f1000000-0000-4000-8000-000000000003"}}'::jsonb)) ->> 'conversation_scope_excluded', 'true', 'legacy forget reports conversation scope');
RESET ROLE;
SET ROLE service_role;
SELECT support_test.eq(jsonb_array_length(public.support_context_sources('aaaaaaaa-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000003', 20, true) -> 'history'), 0, 'suppressed conversation contributes no history');
RESET ROLE;

-- S04: assemble -> discard -> confirm with the old activity revision is refused
-- (activity a3...01 was discarded earlier; its context_revision moved on)
INSERT INTO public.chat_requests (user_id, request_id, conversation_id, content_hash) VALUES
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000003', 'cccccccc-0000-4000-8000-000000000001', 'hash-3');
SET ROLE service_role;
SELECT support_test.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000003',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'used discarded text', 'content_hash', 'hash-3',
  'privacy_revision', (SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'),
  'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r', 'response', '{"ok":true}'::jsonb, 'response_status', 200,
  'sources', jsonb_build_array(jsonb_build_object('kind', 'activity_result', 'id', 'a3000000-0000-4000-8000-000000000001', 'revision', 1))))) ->> 'code', 'PRIVACY_REVISION_STALE', 'discarded activity cannot confirm');
RESET ROLE;


-- ===================== S02-R1: suppression DOMINATES later checkpoint/finish and advances CAS =====================
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"50000000-0000-4000-8000-000000000001","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":2,"kind":"start_activity","payload":{"activity_id":"a4000000-0000-4000-8000-000000000001","template_key":"untangle_thought_v1"}}'::jsonb)) ->> 'revision', '3', 'start derived activity');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"50000000-0000-4000-8000-000000000002","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":3,"kind":"checkpoint_activity","payload":{"activity_id":"a4000000-0000-4000-8000-000000000001","checkpoint":{"version":1,"template_version":1,"responses":{"on_mind":"PRIVATE-DERIVED"}},"active_ms":5}}'::jsonb)) ->> 'revision', '4', 'checkpoint with answers');
RESET ROLE;
INSERT INTO public.messages (id, conversation_id, role, content) VALUES
  ('f0000000-0000-4000-8000-000000000005', 'cccccccc-0000-4000-8000-000000000003', 'assistant', 'turn that proposed the activity');
INSERT INTO public.support_proposals (id, user_id, support_session_id, request_id, message_id, template_key, reason_code, privacy_revision, status, accepted_activity_id, expires_at)
  VALUES ('b9000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000010',
          'b9000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000005', 'untangle_thought_v1', 'general_option', 1, 'accepted',
          'a4000000-0000-4000-8000-000000000001', now() + interval '1 day');
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
-- user excludes the proposing turn; closure marks the accepted activity suppressed and scrubs it
SELECT support_test.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"50000000-0000-4000-8000-000000000003","kind":"suppress_source","payload":{"source_kind":"message","id":"f0000000-0000-4000-8000-000000000005"}}'::jsonb)) ->> 'ok', 'true', 'suppress proposing turn');
RESET ROLE;
SELECT support_test.eq((SELECT status || '/' || stop_reason FROM public.support_activities WHERE id = 'a4000000-0000-4000-8000-000000000001'), 'stopped/discarded', 'unfinished derived activity stopped');
SELECT support_test.eq((SELECT count(*) FROM public.support_activities WHERE id = 'a4000000-0000-4000-8000-000000000001' AND (checkpoint IS NOT NULL OR result::text LIKE '%PRIVATE%'))::int, 0, 'derived activity content scrubbed');
SELECT support_test.eq((SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000010'), 5::bigint, 'session revision advanced by suppression');
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
-- an old prepared attempt (expected revision 4) fails CAS
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"50000000-0000-4000-8000-000000000004","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":4,"kind":"checkpoint_activity","payload":{"activity_id":"a4000000-0000-4000-8000-000000000001","checkpoint":{"version":1,"template_version":1,"responses":{"on_mind":"PRIVATE-RESTORED"}},"active_ms":9}}'::jsonb)) ->> 'code', 'REVISION_CONFLICT', 'stale checkpoint fails CAS');
-- even a freshly rebased attempt cannot restore content
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"50000000-0000-4000-8000-000000000005","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":5,"kind":"checkpoint_activity","payload":{"activity_id":"a4000000-0000-4000-8000-000000000001","checkpoint":{"version":1,"template_version":1,"responses":{"on_mind":"PRIVATE-RESTORED"}},"active_ms":9}}'::jsonb)) ->> 'reason', 'activity_discarded', 'rebased checkpoint refused');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"50000000-0000-4000-8000-000000000006","session_id":"51000000-0000-4000-8000-000000000010","expected_revision":5,"kind":"finish_activity","payload":{"activity_id":"a4000000-0000-4000-8000-000000000001","outcome":"completed","checkpoint":{"version":1,"template_version":1,"responses":{"on_mind":"PRIVATE-RESTORED"}}}}'::jsonb)) ->> 'reason', 'activity_discarded', 'rebased finish refused');
RESET ROLE;
SELECT support_test.eq((SELECT count(*) FROM public.support_activities WHERE checkpoint::text LIKE '%PRIVATE-RESTORED%' OR result::text LIKE '%PRIVATE-RESTORED%')::int, 0, 'no restored answers anywhere');

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
SELECT support_test.eq((SELECT count(*) FROM jsonb_array_elements(public.support_context_sources('aaaaaaaa-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001', 20, true) -> 'memories') m
                   WHERE m ->> 'id' = 'd0000000-0000-4000-8000-000000000031')::int, 0, 'message-only provenance memory excluded from context');
SELECT support_test.eq((SELECT count(*) FROM jsonb_array_elements(public.support_context_sources('aaaaaaaa-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001', 20, true) -> 'memories') m
                   WHERE m ->> 'id' = 'd0000000-0000-4000-8000-000000000032')::int, 1, 'clean memory still included');
RESET ROLE;
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((SELECT count(*) FROM jsonb_array_elements(public.support_list_memory() -> 'candidates') c WHERE c ->> 'id' = 'f1000000-0000-4000-8000-000000000031')::int, 0, 'message-only candidate not offered for review');
SELECT support_test.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"50000000-0000-4000-8000-000000000010","kind":"candidate_approve","payload":{"fragment_id":"f1000000-0000-4000-8000-000000000031"}}'::jsonb)) ->> 'code', 'CONTENT_UNAVAILABLE', 'cannot approve message-only candidate of a suppressed conversation');
RESET ROLE;

-- ===================== S05-R1: any new ACTIVE memory advances the privacy revision =====================
INSERT INTO public.chat_requests (user_id, request_id, conversation_id, content_hash) VALUES
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000004', 'cccccccc-0000-4000-8000-000000000001', 'hash-4'),
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000005', 'cccccccc-0000-4000-8000-000000000001', 'hash-5');
CREATE TABLE support_test.s05 AS SELECT privacy_revision AS before_rev FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001';
GRANT SELECT ON support_test.s05 TO authenticated, service_role;
-- legacy create of an eligible boundary
INSERT INTO public.companion_memory (id, user_id, category, content) VALUES
  ('d0000000-0000-4000-8000-000000000041', 'aaaaaaaa-0000-4000-8000-000000000001', 'boundaries', 'new boundary after request started');
SELECT support_test.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') > (SELECT before_rev FROM support_test.s05), true, 'legacy insert advanced privacy revision');
SET ROLE service_role;
SELECT support_test.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000004',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'built before the boundary', 'content_hash', 'hash-4',
  'privacy_revision', (SELECT before_rev FROM support_test.s05), 'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r',
  'response', '{"ok":true}'::jsonb, 'response_status', 200))) ->> 'code', 'PRIVACY_REVISION_STALE', 'request prepared before the boundary cannot confirm');
RESET ROLE;
-- approval path
INSERT INTO public.memory_fragments (id, user_id, fragment_type, key, value, review_state)
  VALUES ('f1000000-0000-4000-8000-000000000041', 'aaaaaaaa-0000-4000-8000-000000000001', 'preference', 'k41', 'approved later', 'pending');
CREATE TABLE support_test.s05b AS SELECT privacy_revision AS before_rev FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001';
GRANT SELECT ON support_test.s05b TO authenticated, service_role;
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"50000000-0000-4000-8000-000000000011","kind":"candidate_approve","payload":{"fragment_id":"f1000000-0000-4000-8000-000000000041"}}'::jsonb)) ->> 'ok', 'true', 'approve fresh candidate');
RESET ROLE;
SELECT support_test.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') > (SELECT before_rev FROM support_test.s05b), true, 'approval advanced privacy revision');
SET ROLE service_role;
SELECT support_test.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000005',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'built before the approval', 'content_hash', 'hash-5',
  'privacy_revision', (SELECT before_rev FROM support_test.s05b), 'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r',
  'response', '{"ok":true}'::jsonb, 'response_status', 200))) ->> 'code', 'PRIVACY_REVISION_STALE', 'request prepared before approval cannot confirm');
RESET ROLE;

-- ===================== S06-R1 (partial): transaction-generated ids are stored with the response =====================
-- Rendering the final client response from them is the chat integration's job (M4).
SELECT support_test.eq((SELECT response -> 'support_confirmed' ->> 'message_id' IS NOT NULL FROM public.chat_requests WHERE request_id = 'b1000000-0000-4000-8000-000000000001'), true, 'confirmed ids stored with the terminal response');


-- ===================== ROUND 4 FIXTURES (all NOT EXECUTED) =====================
-- ---- S02-R2: cross-session transitive discard advances EVERY affected session once ----
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"60000000-0000-4000-8000-000000000001","session_id":"51000000-0000-4000-8000-000000000020","expected_revision":null,"kind":"create","payload":{"title":"X"}}'::jsonb)) ->> 'ok', 'true', 'create X');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"60000000-0000-4000-8000-000000000002","session_id":"51000000-0000-4000-8000-000000000021","expected_revision":null,"kind":"create","payload":{"title":"Y"}}'::jsonb)) ->> 'ok', 'true', 'create Y');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"60000000-0000-4000-8000-000000000003","session_id":"51000000-0000-4000-8000-000000000020","expected_revision":1,"kind":"start_activity","payload":{"activity_id":"a5000000-0000-4000-8000-000000000001","template_key":"untangle_thought_v1"}}'::jsonb)) ->> 'revision', '2', 'start A in X');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"60000000-0000-4000-8000-000000000004","session_id":"51000000-0000-4000-8000-000000000021","expected_revision":1,"kind":"start_activity","payload":{"activity_id":"a5000000-0000-4000-8000-000000000002","template_key":"untangle_thought_v1"}}'::jsonb)) ->> 'revision', '2', 'start C in Y');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"60000000-0000-4000-8000-000000000005","session_id":"51000000-0000-4000-8000-000000000021","expected_revision":2,"kind":"checkpoint_activity","payload":{"activity_id":"a5000000-0000-4000-8000-000000000002","checkpoint":{"version":1,"template_version":1,"responses":{"on_mind":"PRIVATE-Y"}},"active_ms":3}}'::jsonb)) ->> 'revision', '3', 'checkpoint C');
RESET ROLE;
-- chain: activity A feeds assistant message B (receipt cites A); B's proposal was accepted as activity C in Y
INSERT INTO public.messages (id, conversation_id, role, content) VALUES
  ('f0000000-0000-4000-8000-000000000020', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'turn B');
INSERT INTO public.support_context_receipts (id, user_id, request_id, support_session_id, conversation_id, assistant_message_id, privacy_revision, scope, provider_vendor, provider_model, route_version)
  VALUES ('e0000000-0000-4000-8000-000000000020', 'aaaaaaaa-0000-4000-8000-000000000001', 'b2000000-0000-4000-8000-000000000020', '51000000-0000-4000-8000-000000000020',
          'cccccccc-0000-4000-8000-000000000001', 'f0000000-0000-4000-8000-000000000020', 1, 'personalized', 'openai', 'm', 'r');
INSERT INTO public.support_context_receipt_sources (receipt_id, user_id, source_kind, source_id, source_revision)
  VALUES ('e0000000-0000-4000-8000-000000000020', 'aaaaaaaa-0000-4000-8000-000000000001', 'activity_result', 'a5000000-0000-4000-8000-000000000001', 1);
INSERT INTO public.support_proposals (id, user_id, support_session_id, request_id, message_id, template_key, reason_code, privacy_revision, status, accepted_activity_id, expires_at)
  VALUES ('b9000000-0000-4000-8000-000000000020', 'aaaaaaaa-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000021',
          'b2000000-0000-4000-8000-000000000020', 'f0000000-0000-4000-8000-000000000020', 'untangle_thought_v1', 'general_option', 1, 'accepted',
          'a5000000-0000-4000-8000-000000000002', now() + interval '1 day');
CREATE TABLE support_test.r4 AS SELECT now() AS t0,
  (SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000020') AS x_rev,
  (SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000021') AS y_rev;
GRANT SELECT ON support_test.r4 TO authenticated, service_role;
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"60000000-0000-4000-8000-000000000006","session_id":"51000000-0000-4000-8000-000000000020","expected_revision":2,"kind":"discard_activity_answers","payload":{"activity_id":"a5000000-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'revision', '3', 'origin session advanced exactly once');
RESET ROLE;
SELECT support_test.eq((SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000020'), 3::bigint, 'X not double-bumped');
SELECT support_test.eq((SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000021') > (SELECT y_rev FROM support_test.r4), true, 'dependent session Y advanced');
SELECT support_test.eq((SELECT updated_at > (SELECT t0 FROM support_test.r4) FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000021'), true, 'Y updated_at advanced');
SELECT support_test.eq((SELECT status || '/' || stop_reason FROM public.support_activities WHERE id = 'a5000000-0000-4000-8000-000000000002'), 'stopped/discarded', 'C stopped');
SELECT support_test.eq((SELECT count(*) FROM public.support_activities WHERE id = 'a5000000-0000-4000-8000-000000000002' AND (checkpoint IS NOT NULL OR content_scrubbed_at IS NULL))::int, 0, 'C scrubbed with server marker');
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((SELECT count(*) FROM jsonb_array_elements(public.support_list_sessions(100, (SELECT t0 FROM support_test.r4), '00000000-0000-0000-0000-000000000000', NULL, 'asc', true) -> 'items') i
                   WHERE i ->> 'id' = '51000000-0000-4000-8000-000000000021')::int, 1, 'Y visible in incremental sync');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"60000000-0000-4000-8000-000000000007","session_id":"51000000-0000-4000-8000-000000000021","expected_revision":3,"kind":"checkpoint_activity","payload":{"activity_id":"a5000000-0000-4000-8000-000000000002","checkpoint":{"version":1,"template_version":1},"active_ms":9}}'::jsonb)) ->> 'code', 'REVISION_CONFLICT', 'Y prepared attempt fails CAS');
RESET ROLE;

-- ---- S02-R3: client-supplied result.discarded is never erasure proof ----
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"60000000-0000-4000-8000-000000000010","session_id":"51000000-0000-4000-8000-000000000020","expected_revision":3,"kind":"start_activity","payload":{"activity_id":"a6000000-0000-4000-8000-000000000001","template_key":"untangle_thought_v1"}}'::jsonb)) ->> 'ok', 'true', 'start reserved-key probe');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"60000000-0000-4000-8000-000000000011","session_id":"51000000-0000-4000-8000-000000000020","expected_revision":4,"kind":"finish_activity","payload":{"activity_id":"a6000000-0000-4000-8000-000000000001","outcome":"completed","result":{"discarded":true,"private":"x"}}}'::jsonb)) ->> 'code', 'INVALID_PAYLOAD', 'result.discarded is reserved');
RESET ROLE;
-- Previously ACCEPTED legacy shapes (inserted directly): marker true + private data, and a wrong-type marker.
INSERT INTO public.support_activities (id, user_id, support_session_id, template_key, template_version, kind, status, checkpoint, result, active_ms, last_changed_revision, finished_at) VALUES
  ('a6000000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000020', 'untangle_thought_v1', 1, 'untangle', 'completed',
   '{"version":1,"responses":{"on_mind":"PRIVATE-T"}}', '{"discarded":true,"private":"retained"}', 0, 1, now()),
  ('a6000000-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000020', 'untangle_thought_v1', 1, 'untangle', 'completed',
   '{"version":1,"responses":{"on_mind":"PRIVATE-U"}}', '{"discarded":"bad"}', 0, 1, now());
INSERT INTO public.messages (id, conversation_id, role, content) VALUES
  ('f0000000-0000-4000-8000-000000000030', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'turn M7');
INSERT INTO public.support_proposals (id, user_id, support_session_id, request_id, message_id, template_key, reason_code, privacy_revision, status, accepted_activity_id, expires_at) VALUES
  ('b9000000-0000-4000-8000-000000000031', 'aaaaaaaa-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000020', 'b9000000-0000-4000-8000-000000000041', 'f0000000-0000-4000-8000-000000000030', 'untangle_thought_v1', 'general_option', 1, 'accepted', 'a6000000-0000-4000-8000-000000000002', now() + interval '1 day'),
  ('b9000000-0000-4000-8000-000000000032', 'aaaaaaaa-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000020', 'b9000000-0000-4000-8000-000000000042', 'f0000000-0000-4000-8000-000000000030', 'untangle_thought_v1', 'general_option', 1, 'accepted', 'a6000000-0000-4000-8000-000000000003', now() + interval '1 day'),
  ('b9000000-0000-4000-8000-000000000033', 'aaaaaaaa-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000001', 'b9000000-0000-4000-8000-000000000043', 'f0000000-0000-4000-8000-000000000030', 'ground_present_v1', 'general_option', 1, 'accepted', 'a2000000-0000-4000-8000-000000000001', now() + interval '1 day');
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"60000000-0000-4000-8000-000000000012","kind":"suppress_source","payload":{"source_kind":"message","id":"f0000000-0000-4000-8000-000000000030"}}'::jsonb)) ->> 'ok', 'true', 'Forget must not fail on previously accepted malformed markers');
RESET ROLE;
SELECT support_test.eq((SELECT count(*) FROM public.support_activities WHERE id IN ('a6000000-0000-4000-8000-000000000002', 'a6000000-0000-4000-8000-000000000003')
                   AND (checkpoint IS NOT NULL OR result::text LIKE '%PRIVATE%' OR result::text LIKE '%retained%' OR content_scrubbed_at IS NULL))::int, 0, 'content removed regardless of client marker');
SELECT support_test.eq((SELECT completed AND xp_awarded_at IS NOT NULL FROM public.exercise_sessions WHERE id = (SELECT canonical_ref_id FROM public.support_activities WHERE id = 'a2000000-0000-4000-8000-000000000001')), true, 'canonical completion/XP preserved');
SELECT support_test.eq((SELECT status FROM public.support_activities WHERE id = 'a2000000-0000-4000-8000-000000000001'), 'completed', 'completed status preserved');

-- ---- S03-R2: legacy conversation Forget -> accepted activity whose proposing receipt has NO message source ----
INSERT INTO public.conversations (id, user_id) VALUES ('cccccccc-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-000000000001');
INSERT INTO public.messages (id, conversation_id, role, content) VALUES
  ('f0000000-0000-4000-8000-000000000040', 'cccccccc-0000-4000-8000-000000000004', 'assistant', 'proposing turn in C4');
INSERT INTO public.support_context_receipts (id, user_id, request_id, support_session_id, conversation_id, assistant_message_id, privacy_revision, scope, provider_vendor, provider_model, route_version)
  VALUES ('e0000000-0000-4000-8000-000000000040', 'aaaaaaaa-0000-4000-8000-000000000001', 'b2000000-0000-4000-8000-000000000040', '51000000-0000-4000-8000-000000000020',
          'cccccccc-0000-4000-8000-000000000004', 'f0000000-0000-4000-8000-000000000040', 1, 'conversation_only', 'openai', 'm', 'r');
INSERT INTO public.support_context_receipt_sources (receipt_id, user_id, source_kind, source_id, source_revision)
  VALUES ('e0000000-0000-4000-8000-000000000040', 'aaaaaaaa-0000-4000-8000-000000000001', 'safety_policy', '00000000-0000-0000-0000-000000000001', 1);
INSERT INTO public.support_activities (id, user_id, support_session_id, template_key, template_version, kind, status, checkpoint, active_ms, last_changed_revision) VALUES
  ('a7000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000020', 'untangle_thought_v1', 1, 'untangle', 'paused',
   '{"version":1,"responses":{"on_mind":"PRIVATE-C4"}}', 0, 1);
INSERT INTO public.support_proposals (id, user_id, support_session_id, request_id, message_id, template_key, reason_code, privacy_revision, status, accepted_activity_id, expires_at)
  VALUES ('b9000000-0000-4000-8000-000000000051', 'aaaaaaaa-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000020', 'b9000000-0000-4000-8000-000000000052',
          'f0000000-0000-4000-8000-000000000040', 'untangle_thought_v1', 'general_option', 1, 'accepted', 'a7000000-0000-4000-8000-000000000001', now() + interval '1 day');
INSERT INTO public.memory_fragments (id, user_id, fragment_type, key, value, source_conversation_id)
  VALUES ('f1000000-0000-4000-8000-000000000051', 'aaaaaaaa-0000-4000-8000-000000000001', 'fact', 'k51', 'legacy fact C4', 'cccccccc-0000-4000-8000-000000000004');
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"60000000-0000-4000-8000-000000000020","kind":"memory_forget","payload":{"fragment_id":"f1000000-0000-4000-8000-000000000051"}}'::jsonb)) ->> 'conversation_scope_excluded', 'true', 'legacy forget suppresses C4');
RESET ROLE;
SELECT support_test.eq((SELECT count(*) FROM public.support_suppressions WHERE kind = 'activity' AND ref_id = 'a7000000-0000-4000-8000-000000000001')::int, 1, 'accepted activity from suppressed conversation is suppressed');
SELECT support_test.eq((SELECT status || '/' || (checkpoint IS NULL)::text || '/' || (content_scrubbed_at IS NOT NULL)::text FROM public.support_activities WHERE id = 'a7000000-0000-4000-8000-000000000001'), 'stopped/true/true', 'activity scrubbed and stopped');
SELECT support_test.eq((SELECT count(*) FROM public.messages WHERE id = 'f0000000-0000-4000-8000-000000000040')::int, 1, 'historical message stays visible');

-- ---- S05-R2: time passing alone invalidates confirmation and proposal acceptance ----
INSERT INTO public.companion_memory (id, user_id, category, content) VALUES
  ('d0000000-0000-4000-8000-000000000061', 'aaaaaaaa-0000-4000-8000-000000000001', 'preferences', 'short-lived preference');
UPDATE public.companion_memory SET expires_at = now() + interval '1 second' WHERE id = 'd0000000-0000-4000-8000-000000000061';
INSERT INTO public.companion_memory (id, user_id, category, content) VALUES
  ('d0000000-0000-4000-8000-000000000062', 'aaaaaaaa-0000-4000-8000-000000000001', 'life_context', 'old life context');
SELECT set_config('support.memory_rpc', 'on', false);
UPDATE public.companion_memory SET confirmed_at = now() - interval '100 days' WHERE id = 'd0000000-0000-4000-8000-000000000062';
SELECT set_config('support.memory_rpc', 'off', false);
-- A valid otherwise-current receipt makes this case exercise the expired named basis.
INSERT INTO public.support_context_receipts (id, user_id, request_id, support_session_id, conversation_id,
  privacy_revision, scope, provider_vendor, provider_model, route_version)
SELECT 'e0000000-0000-4000-8000-000000000061', 'aaaaaaaa-0000-4000-8000-000000000001',
  'b9000000-0000-4000-8000-000000000062', '51000000-0000-4000-8000-000000000010',
  'cccccccc-0000-4000-8000-000000000001', privacy_revision, 'personalized', 'openai', 'm', 'r'
FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001';
INSERT INTO public.support_context_receipt_sources (receipt_id, user_id, source_kind, source_id, source_revision)
VALUES ('e0000000-0000-4000-8000-000000000061', 'aaaaaaaa-0000-4000-8000-000000000001',
  'safety_policy', '00000000-0000-0000-0000-000000000001', 1);
INSERT INTO public.support_proposals (id, user_id, support_session_id, request_id, template_key, reason_code, basis_kind, basis_ref, privacy_revision, status, expires_at)
  VALUES ('b9000000-0000-4000-8000-000000000061', 'aaaaaaaa-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000010', 'b9000000-0000-4000-8000-000000000062',
          'choose_step_v1', 'approved_preference', 'companion_memory', 'd0000000-0000-4000-8000-000000000061',
          (SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 'offered', now() + interval '1 day');
INSERT INTO public.chat_requests (user_id, request_id, conversation_id, content_hash) VALUES
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000006', 'cccccccc-0000-4000-8000-000000000001', 'hash-6'),
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000007', 'cccccccc-0000-4000-8000-000000000001', 'hash-7');
SELECT pg_sleep(1.5);   -- the expires_at deadline passes; no row is modified
SET ROLE service_role;
SELECT support_test.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000006',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'built while eligible', 'content_hash', 'hash-6',
  'privacy_revision', (SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'),
  'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r', 'response', '{"ok":true}'::jsonb, 'response_status', 200,
  'sources', jsonb_build_array(jsonb_build_object('kind', 'companion_memory', 'id', 'd0000000-0000-4000-8000-000000000061',
     'revision', (SELECT revision FROM public.companion_memory WHERE id = 'd0000000-0000-4000-8000-000000000061')))))) ->> 'code', 'PRIVACY_REVISION_STALE', 'expired memory cannot confirm');
SELECT support_test.eq((public.support_confirm_chat_turn(jsonb_build_object(
  'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', 'b1000000-0000-4000-8000-000000000007',
  'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'built while eligible', 'content_hash', 'hash-7',
  'privacy_revision', (SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'),
  'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r', 'response', '{"ok":true}'::jsonb, 'response_status', 200,
  'sources', jsonb_build_array(jsonb_build_object('kind', 'companion_memory', 'id', 'd0000000-0000-4000-8000-000000000062',
     'revision', (SELECT revision FROM public.companion_memory WHERE id = 'd0000000-0000-4000-8000-000000000062')))))) ->> 'code', 'PRIVACY_REVISION_STALE', 'default 90-day life-context review blocks confirm');
RESET ROLE;
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', '60000000-0000-4000-8000-0000000000c1',
  'session_id', '51000000-0000-4000-8000-000000000010', 'expected_revision', (SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000010'),
  'kind', 'accept_proposal', 'payload', jsonb_build_object('proposal_id', 'b9000000-0000-4000-8000-000000000061', 'activity_id', 'a8000000-0000-4000-8000-000000000001')))) ->> 'code', 'PROPOSAL_EXPIRED', 'proposal with time-expired basis cannot be accepted');
RESET ROLE;

-- ---- S11: default seven-day candidate expiry applies to approval even when candidate_expires_at is NULL ----
INSERT INTO public.memory_fragments (id, user_id, fragment_type, key, value, review_state, created_at)
  VALUES ('f1000000-0000-4000-8000-000000000071', 'aaaaaaaa-0000-4000-8000-000000000001', 'fact', 'k71', 'stale pending candidate', 'pending', now() - interval '8 days');
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"60000000-0000-4000-8000-000000000030","kind":"candidate_approve","payload":{"fragment_id":"f1000000-0000-4000-8000-000000000071"}}'::jsonb)) ->> 'code', 'CONTENT_UNAVAILABLE', 'expired pending candidate (NULL expiry) cannot be approved before cleanup runs');
RESET ROLE;


-- ===================== ROUND 5 FIXTURES (all NOT EXECUTED) =====================
-- ---- the write mutex helper is not exposed to API roles ----
SET ROLE authenticated;
DO $$ BEGIN
  PERFORM public.support_acquire_write_mutex();
  RAISE EXCEPTION 'mutex helper unexpectedly callable by authenticated';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
RESET ROLE;
SET ROLE anon;
DO $$ BEGIN
  PERFORM public.support_acquire_write_mutex();
  RAISE EXCEPTION 'mutex helper unexpectedly callable by anon';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
RESET ROLE;

-- ---- S10-R2: a promoted fragment is provenance only; no writer can restore its content ----
INSERT INTO public.memory_fragments (id, user_id, fragment_type, key, value, review_state, source_message_id)
  VALUES ('f1000000-0000-4000-8000-000000000081', 'aaaaaaaa-0000-4000-8000-000000000001', 'fact', 'k81', 'plaintext to be promoted', 'pending', 'f0000000-0000-4000-8000-000000000002');
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"70000000-0000-4000-8000-000000000001","kind":"candidate_approve","payload":{"fragment_id":"f1000000-0000-4000-8000-000000000081"}}'::jsonb)) ->> 'ok', 'false', 'candidate from an already-suppressed source cannot be approved');
RESET ROLE;
-- fresh unsuppressed source for the staged promotion
INSERT INTO public.messages (id, conversation_id, role, content) VALUES
  ('f0000000-0000-4000-8000-000000000082', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'clean turn');
INSERT INTO public.memory_fragments (id, user_id, fragment_type, key, value, review_state, source_message_id)
  VALUES ('f1000000-0000-4000-8000-000000000082', 'aaaaaaaa-0000-4000-8000-000000000001', 'preference', 'k82', 'promote me', 'pending', 'f0000000-0000-4000-8000-000000000082');
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"70000000-0000-4000-8000-000000000002","kind":"candidate_approve","payload":{"fragment_id":"f1000000-0000-4000-8000-000000000082"}}'::jsonb)) ->> 'ok', 'true', 'approve staged fragment');
-- repeated approval of the already-promoted fragment is a clean no-op (no unrelated row locks taken)
SELECT support_test.eq((public.support_memory_mutate('{"schema_version":1,"operation_id":"70000000-0000-4000-8000-000000000003","kind":"candidate_approve","payload":{"fragment_id":"f1000000-0000-4000-8000-000000000082"}}'::jsonb)) ->> 'no_op', 'true', 'repeat approval no-op');
RESET ROLE;
-- a queued LEGACY edit tries to put plaintext back on the promoted fragment
UPDATE public.memory_fragments SET value = 'queued old plaintext' WHERE id = 'f1000000-0000-4000-8000-000000000082';
SELECT support_test.eq((SELECT value FROM public.memory_fragments WHERE id = 'f1000000-0000-4000-8000-000000000082'), '', 'promoted fragment stays blank under legacy update');
-- Forget the canonical memory, then the legacy edit "completes afterwards"
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_memory_mutate(jsonb_build_object('schema_version', 1, 'operation_id', '70000000-0000-4000-8000-000000000004', 'kind', 'memory_forget',
  'payload', jsonb_build_object('memory_id', (SELECT promoted_memory_id FROM public.memory_fragments WHERE id = 'f1000000-0000-4000-8000-000000000082'))))) ->> 'ok', 'true', 'forget canonical memory');
RESET ROLE;
UPDATE public.memory_fragments SET value = 'late legacy restoration' WHERE id = 'f1000000-0000-4000-8000-000000000082';
SELECT support_test.eq((SELECT value || '/' || review_state FROM public.memory_fragments WHERE id = 'f1000000-0000-4000-8000-000000000082'), '/dismissed', 'late legacy edit cannot restore content after Forget');
-- a legacy writer inserting a candidate from the acknowledged-suppressed source is blanked
INSERT INTO public.memory_fragments (id, user_id, fragment_type, key, value, review_state, source_message_id)
  VALUES ('f1000000-0000-4000-8000-000000000083', 'aaaaaaaa-0000-4000-8000-000000000001', 'fact', 'k83', 'resurrected plaintext', 'pending', 'f0000000-0000-4000-8000-000000000082');
SELECT support_test.eq((SELECT value || '/' || review_state FROM public.memory_fragments WHERE id = 'f1000000-0000-4000-8000-000000000083'), '/dismissed', 'insert from a suppressed source is blanked');

-- ---- S11 / boundary consistency: listing, approval and cleanup agree on the 7-day deadline ----
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((SELECT count(*) FROM jsonb_array_elements(public.support_list_memory() -> 'candidates') c WHERE c ->> 'id' = 'f1000000-0000-4000-8000-000000000071')::int, 0, 'list hides the expired NULL-expiry candidate');
RESET ROLE;
SET ROLE service_role;
SELECT support_test.eq(public.support_expire_candidates() >= 1, true, 'cleanup expires it');
RESET ROLE;
SELECT support_test.eq((SELECT review_state || '/' || value FROM public.memory_fragments WHERE id = 'f1000000-0000-4000-8000-000000000071'), 'expired/', 'expired candidate content removed');

-- ===================== ROUND 6: message content revision (M4-R03) (NOT EXECUTED) =====================
CREATE OR REPLACE FUNCTION support_test.confirm_msg(p_req uuid, p_hash text, p_msg uuid, p_rev bigint) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  r := public.support_confirm_chat_turn(jsonb_build_object(
    'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', p_req,
    'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'reply', 'content_hash', p_hash,
    'privacy_revision', (SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'),
    'scope', 'conversation_only', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r',
    'response', '{"ok":true}'::jsonb, 'response_status', 200,
    'sources', jsonb_build_array(jsonb_build_object('kind', 'message', 'id', p_msg, 'revision', p_rev))));
  RETURN CASE WHEN (r ->> 'ok') = 'true' THEN 'ok' ELSE r ->> 'code' END;
END $$;
GRANT EXECUTE ON FUNCTION support_test.confirm_msg(uuid, text, uuid, bigint) TO service_role;

INSERT INTO public.messages (id, conversation_id, role, content) VALUES
  ('f0000000-0000-4000-8000-0000000000a1', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'v1 wording'),
  ('f0000000-0000-4000-8000-0000000000a2', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'role will change'),
  ('f0000000-0000-4000-8000-0000000000a3', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'will move'),
  ('f0000000-0000-4000-8000-0000000000a4', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'will be deleted'),
  ('f0000000-0000-4000-8000-0000000000a5', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'stays unchanged');
INSERT INTO public.chat_requests (user_id, request_id, conversation_id, content_hash) VALUES
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001', 'hm-1'),
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000002', 'cccccccc-0000-4000-8000-000000000001', 'hm-2'),
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000003', 'cccccccc-0000-4000-8000-000000000001', 'hm-3'),
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000004', 'cccccccc-0000-4000-8000-000000000001', 'hm-4'),
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000006', 'cccccccc-0000-4000-8000-000000000001', 'hm-6');

-- server-owned version: default 0, no spoofing, no bump without a real change
SELECT support_test.eq((SELECT content_revision FROM public.messages WHERE id = 'f0000000-0000-4000-8000-0000000000a1'), 0::bigint, 'stored default is 0');
UPDATE public.messages SET content_revision = 99 WHERE id = 'f0000000-0000-4000-8000-0000000000a1';
SELECT support_test.eq((SELECT content_revision FROM public.messages WHERE id = 'f0000000-0000-4000-8000-0000000000a1'), 0::bigint, 'legacy write cannot spoof the version');
UPDATE public.messages SET content = content WHERE id = 'f0000000-0000-4000-8000-0000000000a1';
SELECT support_test.eq((SELECT content_revision FROM public.messages WHERE id = 'f0000000-0000-4000-8000-0000000000a1'), 0::bigint, 'no-op update does not bump');

-- apply-rewrite shape: in-place content change keeps id and the privacy revision; version advances
CREATE TABLE IF NOT EXISTS support_test.r6 (privacy_rev bigint);
GRANT SELECT ON support_test.r6 TO authenticated, service_role;
TRUNCATE support_test.r6;
INSERT INTO support_test.r6 SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001';
UPDATE public.messages SET content = 'v2 rewritten wording' WHERE id = 'f0000000-0000-4000-8000-0000000000a1';
SELECT support_test.eq((SELECT content_revision FROM public.messages WHERE id = 'f0000000-0000-4000-8000-0000000000a1'), 1::bigint, 'content change bumps version');
UPDATE public.messages SET content_revision = 0 WHERE id = 'f0000000-0000-4000-8000-0000000000a1';
SELECT support_test.eq((SELECT content_revision FROM public.messages WHERE id = 'f0000000-0000-4000-8000-0000000000a1'), 1::bigint, 'legacy write cannot lower the version');
SELECT support_test.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') = (SELECT privacy_rev FROM support_test.r6), true, 'message edit alone does not touch the privacy revision');

SET ROLE service_role;
SELECT support_test.eq(support_test.confirm_msg('b3000000-0000-4000-8000-000000000001', 'hm-1', 'f0000000-0000-4000-8000-0000000000a1', 0), 'PRIVACY_REVISION_STALE', 'old cited revision rejected after in-place rewrite');
SELECT support_test.eq(support_test.confirm_msg('b3000000-0000-4000-8000-000000000001', 'hm-1', 'f0000000-0000-4000-8000-0000000000a1', 1), 'ok', 'correct current revision confirms');
RESET ROLE;

-- confirmed replay is first and unchanged by later edits
UPDATE public.messages SET content = 'v3 later wording' WHERE id = 'f0000000-0000-4000-8000-0000000000a1';
SET ROLE service_role;
SELECT support_test.eq(support_test.confirm_msg('b3000000-0000-4000-8000-000000000001', 'hm-1', 'f0000000-0000-4000-8000-0000000000a1', 1), 'ok', 'confirmed request replays after a later edit');
RESET ROLE;
SELECT support_test.eq((SELECT count(*) FROM public.support_context_receipts WHERE request_id = 'b3000000-0000-4000-8000-000000000001')::int, 1, 'replay created no second receipt');

-- role change, move to another conversation, deletion
UPDATE public.messages SET role = 'user' WHERE id = 'f0000000-0000-4000-8000-0000000000a2';
UPDATE public.messages SET conversation_id = 'cccccccc-0000-4000-8000-000000000003' WHERE id = 'f0000000-0000-4000-8000-0000000000a3';
DELETE FROM public.messages WHERE id = 'f0000000-0000-4000-8000-0000000000a4';
SET ROLE service_role;
SELECT support_test.eq(support_test.confirm_msg('b3000000-0000-4000-8000-000000000002', 'hm-2', 'f0000000-0000-4000-8000-0000000000a2', 0), 'PRIVACY_REVISION_STALE', 'role change');
SELECT support_test.eq(support_test.confirm_msg('b3000000-0000-4000-8000-000000000003', 'hm-3', 'f0000000-0000-4000-8000-0000000000a3', 0), 'PRIVACY_REVISION_STALE', 'moved message (old revision)');
SELECT support_test.eq(support_test.confirm_msg('b3000000-0000-4000-8000-000000000003', 'hm-3', 'f0000000-0000-4000-8000-0000000000a3', 1), 'PRIVACY_REVISION_STALE', 'moved message cannot be cited from the old conversation even at the new revision');
SELECT support_test.eq(support_test.confirm_msg('b3000000-0000-4000-8000-000000000004', 'hm-4', 'f0000000-0000-4000-8000-0000000000a4', 0), 'PRIVACY_REVISION_STALE', 'deleted message');
RESET ROLE;

-- a NEW user message saved during the budget/save step must not invalidate its own prepared context
TRUNCATE support_test.r6;
INSERT INTO support_test.r6 SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001';
INSERT INTO public.messages (id, conversation_id, role, content) VALUES
  ('f0000000-0000-4000-8000-0000000000b0', 'cccccccc-0000-4000-8000-000000000001', 'user', 'the current user message');
SELECT support_test.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') = (SELECT privacy_rev FROM support_test.r6), true, 'insert does not bump privacy');
SELECT support_test.eq((SELECT content_revision FROM public.messages WHERE id = 'f0000000-0000-4000-8000-0000000000a5'), 0::bigint, 'insert does not bump other messages');
SET ROLE service_role;
SELECT support_test.eq(support_test.confirm_msg('b3000000-0000-4000-8000-000000000006', 'hm-6', 'f0000000-0000-4000-8000-0000000000a5', 0), 'ok', 'prepared context with an untouched cited message still confirms after a new insert');
RESET ROLE;

-- proposal acceptance: basis message / proposing turn changed -> refused; unchanged control accepts
INSERT INTO public.messages (id, conversation_id, role, content) VALUES
  ('f0000000-0000-4000-8000-0000000000c1', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'basis message 1'),
  ('f0000000-0000-4000-8000-0000000000c2', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'proposing turn 1'),
  ('f0000000-0000-4000-8000-0000000000c3', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'basis message 2'),
  ('f0000000-0000-4000-8000-0000000000c4', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'proposing turn 2'),
  ('f0000000-0000-4000-8000-0000000000c5', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'proposing turn 3');
INSERT INTO public.support_context_receipts (id, user_id, request_id, conversation_id, assistant_message_id, privacy_revision, scope, provider_vendor, provider_model, route_version) VALUES
  ('e0000000-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000011', 'cccccccc-0000-4000-8000-000000000001', 'f0000000-0000-4000-8000-0000000000c2', 1, 'conversation_only', 'openai', 'm', 'r'),
  ('e0000000-0000-4000-8000-0000000000d2', 'aaaaaaaa-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000012', 'cccccccc-0000-4000-8000-000000000001', 'f0000000-0000-4000-8000-0000000000c4', 1, 'conversation_only', 'openai', 'm', 'r');
INSERT INTO public.support_context_receipts (id, user_id, request_id, support_session_id, conversation_id,
  assistant_message_id, privacy_revision, scope, provider_vendor, provider_model, route_version)
SELECT 'e0000000-0000-4000-8000-0000000000d3', 'aaaaaaaa-0000-4000-8000-000000000001',
  'b3000000-0000-4000-8000-000000000013', '51000000-0000-4000-8000-000000000010',
  'cccccccc-0000-4000-8000-000000000001', 'f0000000-0000-4000-8000-0000000000c5', privacy_revision,
  'conversation_only', 'openai', 'm', 'r'
FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001';
INSERT INTO public.support_context_receipt_sources (receipt_id, user_id, source_kind, source_id, source_revision)
VALUES ('e0000000-0000-4000-8000-0000000000d3', 'aaaaaaaa-0000-4000-8000-000000000001',
  'safety_policy', '00000000-0000-0000-0000-000000000001', 1);
INSERT INTO public.support_context_receipt_sources (receipt_id, user_id, source_kind, source_id, source_revision) VALUES
  ('e0000000-0000-4000-8000-0000000000d1', 'aaaaaaaa-0000-4000-8000-000000000001', 'message', 'f0000000-0000-4000-8000-0000000000c1', 0),
  ('e0000000-0000-4000-8000-0000000000d2', 'aaaaaaaa-0000-4000-8000-000000000001', 'message', 'f0000000-0000-4000-8000-0000000000c3', 0);
UPDATE public.messages SET content = 'basis message 1, rewritten' WHERE id = 'f0000000-0000-4000-8000-0000000000c1';   -- stale basis
UPDATE public.messages SET content = 'proposing turn 3, rewritten' WHERE id = 'f0000000-0000-4000-8000-0000000000c5';   -- stale proposing turn
INSERT INTO public.support_proposals (id, user_id, support_session_id, request_id, message_id, template_key, reason_code, basis_kind, basis_ref, privacy_revision, status, expires_at)
SELECT x.id, 'aaaaaaaa-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000010', x.req, x.msg, 'untangle_thought_v1', 'current_request', x.bk, x.bref,
       (SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 'offered', now() + interval '1 day'
FROM (VALUES
  ('b9000000-0000-4000-8000-0000000000e1'::uuid, 'b3000000-0000-4000-8000-000000000011'::uuid, 'f0000000-0000-4000-8000-0000000000c2'::uuid, 'message'::text, 'f0000000-0000-4000-8000-0000000000c1'::uuid),
  ('b9000000-0000-4000-8000-0000000000e2'::uuid, 'b3000000-0000-4000-8000-000000000012'::uuid, 'f0000000-0000-4000-8000-0000000000c4'::uuid, 'message'::text, 'f0000000-0000-4000-8000-0000000000c3'::uuid),
  ('b9000000-0000-4000-8000-0000000000e3'::uuid, 'b3000000-0000-4000-8000-000000000013'::uuid, 'f0000000-0000-4000-8000-0000000000c5'::uuid, NULL::text, NULL::uuid)
) AS x(id, req, msg, bk, bref);
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', '60000000-0000-4000-8000-0000000000f1',
  'session_id', '51000000-0000-4000-8000-000000000010', 'expected_revision', (SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000010'),
  'kind', 'accept_proposal', 'payload', jsonb_build_object('proposal_id', 'b9000000-0000-4000-8000-0000000000e1', 'activity_id', 'a9000000-0000-4000-8000-000000000001')))) ->> 'code', 'PROPOSAL_EXPIRED', 'basis message rewritten after the proposal');
SELECT support_test.eq((public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', '60000000-0000-4000-8000-0000000000f3',
  'session_id', '51000000-0000-4000-8000-000000000010', 'expected_revision', (SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000010'),
  'kind', 'accept_proposal', 'payload', jsonb_build_object('proposal_id', 'b9000000-0000-4000-8000-0000000000e3', 'activity_id', 'a9000000-0000-4000-8000-000000000003')))) ->> 'code', 'PROPOSAL_EXPIRED', 'proposing turn rewritten after the proposal');
SELECT support_test.eq((public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', '60000000-0000-4000-8000-0000000000f2',
  'session_id', '51000000-0000-4000-8000-000000000010', 'expected_revision', (SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000010'),
  'kind', 'accept_proposal', 'payload', jsonb_build_object('proposal_id', 'b9000000-0000-4000-8000-0000000000e2', 'activity_id', 'a9000000-0000-4000-8000-000000000002')))) ->> 'ok', 'true', 'unchanged basis and proposing turn accept');
RESET ROLE;


-- ===================== ROUND 8: Not now -> update_session.decline_template (NOT EXECUTED) =====================
INSERT INTO public.support_proposals (id, user_id, support_session_id, request_id, template_key, reason_code, privacy_revision, status, expires_at)
SELECT x.id, 'aaaaaaaa-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000010', x.req, x.tk, 'general_option',
       (SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 'offered', now() + interval '1 day'
FROM (VALUES
  ('b9000000-0000-4000-8000-0000000000f1'::uuid, 'b4000000-0000-4000-8000-000000000001'::uuid, 'choose_step_v1'::text),
  ('b9000000-0000-4000-8000-0000000000f2'::uuid, 'b4000000-0000-4000-8000-000000000002'::uuid, 'untangle_thought_v1'::text)
) AS x(id, req, tk);
CREATE TABLE IF NOT EXISTS support_test.r8 (acts bigint);
GRANT SELECT ON support_test.r8 TO authenticated, service_role;
TRUNCATE support_test.r8;
INSERT INTO support_test.r8 SELECT count(*) FROM public.support_activities;
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', '80000000-0000-4000-8000-000000000001',
  'session_id', '51000000-0000-4000-8000-000000000010', 'expected_revision', (SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000010'),
  'kind', 'update_session', 'payload', jsonb_build_object('decline_template', 'choose_step_v1')))) ->> 'ok', 'true', 'decline accepted');
RESET ROLE;
SELECT support_test.eq((SELECT 'choose_step_v1' = ANY (suppressed_templates) AND NOT ('untangle_thought_v1' = ANY (suppressed_templates)) AND NOT ('ground_present_v1' = ANY (suppressed_templates))
                        FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000010'), true, 'only the declined template is excluded');
SELECT support_test.eq((SELECT status FROM public.support_proposals WHERE id = 'b9000000-0000-4000-8000-0000000000f1'), 'expired', 'offered proposal for the declined template expired');
SELECT support_test.eq((SELECT status FROM public.support_proposals WHERE id = 'b9000000-0000-4000-8000-0000000000f2'), 'offered', 'other-template proposal untouched');
SELECT support_test.eq((SELECT count(*) FROM public.support_activities) = (SELECT acts FROM support_test.r8), true, 'no activity created');
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
-- exact replay: same operation id and payload -> confirmed replay, no mutation
SELECT support_test.eq((public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', '80000000-0000-4000-8000-000000000001',
  'session_id', '51000000-0000-4000-8000-000000000010', 'expected_revision', 1,
  'kind', 'update_session', 'payload', jsonb_build_object('decline_template', 'choose_step_v1')))) ->> 'replayed', 'true', 'replay returns the stored result');
-- repeat with a NEW operation id: no-op, revision unchanged
SELECT support_test.eq((public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', '80000000-0000-4000-8000-000000000002',
  'session_id', '51000000-0000-4000-8000-000000000010', 'expected_revision', (SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000010'),
  'kind', 'update_session', 'payload', jsonb_build_object('decline_template', 'choose_step_v1')))) ->> 'no_op', 'true', 'repeat decline is a no-op');
-- control: declining a DIFFERENT template changes state and expires only its own proposal
SELECT support_test.eq((public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', '80000000-0000-4000-8000-000000000003',
  'session_id', '51000000-0000-4000-8000-000000000010', 'expected_revision', (SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000010'),
  'kind', 'update_session', 'payload', jsonb_build_object('decline_template', 'untangle_thought_v1')))) ->> 'no_op', 'false', 'other template is a real change');
-- unknown key and a stale CAS
SELECT support_test.eq((public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', '80000000-0000-4000-8000-000000000004',
  'session_id', '51000000-0000-4000-8000-000000000010', 'expected_revision', (SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000010'),
  'kind', 'update_session', 'payload', jsonb_build_object('decline_template', 'not_a_template')))) ->> 'code', 'INVALID_PAYLOAD', 'unknown template rejected');
SELECT support_test.eq((public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', '80000000-0000-4000-8000-000000000005',
  'session_id', '51000000-0000-4000-8000-000000000010', 'expected_revision', 1,
  'kind', 'update_session', 'payload', jsonb_build_object('decline_template', 'ground_present_v1')))) ->> 'code', 'REVISION_CONFLICT', 'stale revision conflicts');
-- closed sessions reject the modification
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"80000000-0000-4000-8000-000000000006","session_id":"51000000-0000-4000-8000-000000000030","expected_revision":null,"kind":"create","payload":{"title":"closing"}}'::jsonb)) ->> 'ok', 'true', 'create closable');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"80000000-0000-4000-8000-000000000007","session_id":"51000000-0000-4000-8000-000000000030","expected_revision":1,"kind":"update_session","payload":{"close":"end_unfinished"}}'::jsonb)) ->> 'ok', 'true', 'close it');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"80000000-0000-4000-8000-000000000008","session_id":"51000000-0000-4000-8000-000000000030","expected_revision":2,"kind":"update_session","payload":{"decline_template":"choose_step_v1"}}'::jsonb)) ->> 'code', 'INVALID_PAYLOAD', 'closed session rejects decline');
RESET ROLE;
-- the other template's proposal is now expired by ITS decline, and an expired proposal cannot be accepted
SELECT support_test.eq((SELECT status FROM public.support_proposals WHERE id = 'b9000000-0000-4000-8000-0000000000f2'), 'expired', 'second decline expired its own proposal');


-- ===================== ROUND 9: daily intent is current context (NOT EXECUTED) =====================
CREATE OR REPLACE FUNCTION support_test.confirm_at(p_req uuid, p_hash text, p_priv bigint) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  r := public.support_confirm_chat_turn(jsonb_build_object(
    'user_id', 'aaaaaaaa-0000-4000-8000-000000000001', 'request_id', p_req,
    'conversation_id', 'cccccccc-0000-4000-8000-000000000001', 'assistant_content', 'reply', 'content_hash', p_hash,
    'privacy_revision', p_priv, 'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'm', 'route_version', 'r',
    'response', '{"ok":true}'::jsonb, 'response_status', 200));
  RETURN CASE WHEN (r ->> 'ok') = 'true' THEN 'ok' ELSE r ->> 'code' END;
END $$;
GRANT EXECUTE ON FUNCTION support_test.confirm_at(uuid, text, bigint) TO service_role;
CREATE TABLE IF NOT EXISTS support_test.r9 (before_rev bigint);
GRANT SELECT ON support_test.r9 TO authenticated, service_role;
INSERT INTO public.chat_requests (user_id, request_id, conversation_id, content_hash) VALUES
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b5000000-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000001', 'di-1'),
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b5000000-0000-4000-8000-000000000002', 'cccccccc-0000-4000-8000-000000000001', 'di-2'),
  ('aaaaaaaa-0000-4000-8000-000000000001', 'b5000000-0000-4000-8000-000000000003', 'cccccccc-0000-4000-8000-000000000001', 'di-3');

-- INSERT of a new current intent invalidates a request prepared at the old revision
TRUNCATE support_test.r9;
INSERT INTO support_test.r9 SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001';
INSERT INTO public.daily_intents (id, user_id, intent) VALUES ('d1000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'finish the email');
SELECT support_test.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') = (SELECT before_rev FROM support_test.r9) + 1, true, 'current intent insert advances the revision once');
SET ROLE service_role;
SELECT support_test.eq(support_test.confirm_at('b5000000-0000-4000-8000-000000000001', 'di-1', (SELECT before_rev FROM support_test.r9)), 'PRIVACY_REVISION_STALE', 'confirm prepared before the intent insert is stale');
RESET ROLE;

-- no-op UPDATE does not invalidate; real edits (text, expiry) do
TRUNCATE support_test.r9;
INSERT INTO support_test.r9 SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001';
UPDATE public.daily_intents SET intent = intent WHERE id = 'd1000000-0000-4000-8000-000000000001';
SELECT support_test.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') = (SELECT before_rev FROM support_test.r9), true, 'no-op update does not invalidate');
UPDATE public.daily_intents SET intent = 'different focus' WHERE id = 'd1000000-0000-4000-8000-000000000001';
SELECT support_test.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') = (SELECT before_rev FROM support_test.r9) + 1, true, 'intent edit invalidates');
UPDATE public.daily_intents SET expires_at = now() + interval '2 hours' WHERE id = 'd1000000-0000-4000-8000-000000000001';
SELECT support_test.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') = (SELECT before_rev FROM support_test.r9) + 2, true, 'expiry edit invalidates');

-- a rolled-back change leaves no revision behind
TRUNCATE support_test.r9;
INSERT INTO support_test.r9 SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001';
BEGIN;
INSERT INTO public.daily_intents (id, user_id, intent) VALUES ('d1000000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001', 'rolled back');
ROLLBACK;
SELECT support_test.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') = (SELECT before_rev FROM support_test.r9), true, 'rollback retains no revision');

-- expired-row writes do not invalidate; DELETE of the current intent does
INSERT INTO public.daily_intents (id, user_id, intent, created_at, expires_at)
  VALUES ('d1000000-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001', 'old', now() - interval '2 days', now() - interval '1 day');
DELETE FROM public.daily_intents WHERE id = 'd1000000-0000-4000-8000-000000000003';
SELECT support_test.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') = (SELECT before_rev FROM support_test.r9), true, 'expired intent insert/delete does not invalidate');
DELETE FROM public.daily_intents WHERE id = 'd1000000-0000-4000-8000-000000000001';
SELECT support_test.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') = (SELECT before_rev FROM support_test.r9) + 1, true, 'delete of the current intent invalidates');
SET ROLE service_role;
SELECT support_test.eq(support_test.confirm_at('b5000000-0000-4000-8000-000000000002', 'di-2', (SELECT before_rev FROM support_test.r9)), 'PRIVACY_REVISION_STALE', 'confirm prepared before the delete is stale');
SELECT support_test.eq(support_test.confirm_at('b5000000-0000-4000-8000-000000000003', 'di-3', (SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001')), 'ok', 'confirm at the current revision succeeds (intent change did not break confirmation)');
RESET ROLE;

-- a new chat message is still excluded from invalidation
TRUNCATE support_test.r9;
INSERT INTO support_test.r9 SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001';
INSERT INTO public.messages (id, conversation_id, role, content) VALUES ('f0000000-0000-4000-8000-0000000000d0', 'cccccccc-0000-4000-8000-000000000001', 'user', 'another user message');
SELECT support_test.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') = (SELECT before_rev FROM support_test.r9), true, 'message insert still does not invalidate');

-- account deletion cascade: no error, and the deleted owner's privacy row is not recreated
INSERT INTO auth.users (id, aud, role, email) VALUES ('cccccccc-0000-4000-8000-0000000000c9', 'authenticated', 'authenticated', 'c@example.invalid');
INSERT INTO public.daily_intents (id, user_id, intent) VALUES ('d1000000-0000-4000-8000-000000000009', 'cccccccc-0000-4000-8000-0000000000c9', 'to be cascaded');
SELECT support_test.eq((SELECT count(*) FROM public.support_privacy_state WHERE user_id = 'cccccccc-0000-4000-8000-0000000000c9')::int, 1, 'owner privacy row created by the intent');
DELETE FROM auth.users WHERE id = 'cccccccc-0000-4000-8000-0000000000c9';
SELECT support_test.eq((SELECT count(*) FROM public.support_privacy_state WHERE user_id = 'cccccccc-0000-4000-8000-0000000000c9')::int, 0, 'cascade leaves no recreated privacy row');
SELECT support_test.eq((SELECT count(*) FROM public.daily_intents WHERE user_id = 'cccccccc-0000-4000-8000-0000000000c9')::int, 0, 'intent cascaded away');


-- ===================== ROUND 10: acceptance revalidates EVERY receipt source (NOT EXECUTED) =====================
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"90000000-0000-4000-8000-000000000001","session_id":"51000000-0000-4000-8000-000000000040","expected_revision":null,"kind":"create","payload":{"title":"accept sources","concern":"first concern"}}'::jsonb)) ->> 'ok', 'true', 'create acceptance session');
RESET ROLE;
INSERT INTO public.messages (id, conversation_id, role, content) VALUES
  ('f0000000-0000-4000-8000-0000000000e1', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'history H1'),
  ('f0000000-0000-4000-8000-0000000000e2', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'history H2'),
  ('f0000000-0000-4000-8000-0000000000e3', 'cccccccc-0000-4000-8000-000000000001', 'assistant', 'history H3');
-- three receipts, each citing a history message AND the session at its CURRENT context revision
INSERT INTO public.support_context_receipts (id, user_id, request_id, support_session_id, conversation_id, privacy_revision, scope, provider_vendor, provider_model, route_version)
SELECT x.rid, 'aaaaaaaa-0000-4000-8000-000000000001', x.req, '51000000-0000-4000-8000-000000000040', 'cccccccc-0000-4000-8000-000000000001',
       (SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 'conversation_only', 'openai', 'm', 'r'
FROM (VALUES
  ('e0000000-0000-4000-8000-0000000000f1'::uuid, 'b6000000-0000-4000-8000-000000000001'::uuid),
  ('e0000000-0000-4000-8000-0000000000f2'::uuid, 'b6000000-0000-4000-8000-000000000002'::uuid),
  ('e0000000-0000-4000-8000-0000000000f3'::uuid, 'b6000000-0000-4000-8000-000000000003'::uuid)
) AS x(rid, req);
INSERT INTO public.support_context_receipt_sources (receipt_id, user_id, source_kind, source_id, source_revision)
SELECT x.rid, 'aaaaaaaa-0000-4000-8000-000000000001'::uuid, x.k, x.sid, x.rev
FROM (VALUES
  ('e0000000-0000-4000-8000-0000000000f1'::uuid, 'message'::text, 'f0000000-0000-4000-8000-0000000000e1'::uuid, 0::bigint),
  ('e0000000-0000-4000-8000-0000000000f2'::uuid, 'message'::text, 'f0000000-0000-4000-8000-0000000000e2'::uuid, 0::bigint),
  ('e0000000-0000-4000-8000-0000000000f3'::uuid, 'message'::text, 'f0000000-0000-4000-8000-0000000000e3'::uuid, 0::bigint)
) AS x(rid, k, sid, rev)
UNION ALL
SELECT r.rid, 'aaaaaaaa-0000-4000-8000-000000000001'::uuid, 'session', '51000000-0000-4000-8000-000000000040'::uuid,
       (SELECT context_revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000040')
FROM (VALUES ('e0000000-0000-4000-8000-0000000000f1'::uuid), ('e0000000-0000-4000-8000-0000000000f2'::uuid), ('e0000000-0000-4000-8000-0000000000f3'::uuid)) AS r(rid);
-- general options (no named basis) for all three receipts, plus a NAMED message basis for the third
INSERT INTO public.support_proposals (id, user_id, support_session_id, request_id, template_key, reason_code, basis_kind, basis_ref, privacy_revision, status, expires_at)
SELECT x.id, 'aaaaaaaa-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000040', x.req, x.tk, x.rc, x.bk, x.bref,
       (SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 'offered', now() + interval '1 day'
FROM (VALUES
  ('b9000000-0000-4000-8000-000000000f01'::uuid, 'b6000000-0000-4000-8000-000000000001'::uuid, 'ground_present_v1'::text, 'general_option'::text, NULL::text, NULL::uuid),
  ('b9000000-0000-4000-8000-000000000f02'::uuid, 'b6000000-0000-4000-8000-000000000002'::uuid, 'untangle_thought_v1'::text, 'general_option'::text, NULL::text, NULL::uuid),
  ('b9000000-0000-4000-8000-000000000f03'::uuid, 'b6000000-0000-4000-8000-000000000003'::uuid, 'choose_step_v1'::text, 'current_request'::text, 'message'::text, 'f0000000-0000-4000-8000-0000000000e3'::uuid)
) AS x(id, req, tk, rc, bk, bref);

-- (1) history rewritten (content_revision +1, privacy unchanged): the GENERAL proposal expires
UPDATE public.messages SET content = 'history H1, rewritten' WHERE id = 'f0000000-0000-4000-8000-0000000000e1';
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', '90000000-0000-4000-8000-000000000002',
  'session_id', '51000000-0000-4000-8000-000000000040', 'expected_revision', (SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000040'),
  'kind', 'accept_proposal', 'payload', jsonb_build_object('proposal_id', 'b9000000-0000-4000-8000-000000000f01', 'activity_id', 'a9100000-0000-4000-8000-000000000001')))) ->> 'code', 'PROPOSAL_EXPIRED', 'general proposal expires when cited history was rewritten');
RESET ROLE;
-- (2) concern edited (context_revision +1, offered status untouched): the other GENERAL proposal expires
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', '90000000-0000-4000-8000-000000000003',
  'session_id', '51000000-0000-4000-8000-000000000040', 'expected_revision', (SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000040'),
  'kind', 'update_session', 'payload', jsonb_build_object('concern', 'second, different concern')))) ->> 'ok', 'true', 'edit the concern');
RESET ROLE;
SELECT support_test.eq((SELECT status FROM public.support_proposals WHERE id = 'b9000000-0000-4000-8000-000000000f02'), 'offered', 'concern edit alone leaves status offered');
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', '90000000-0000-4000-8000-000000000004',
  'session_id', '51000000-0000-4000-8000-000000000040', 'expected_revision', (SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000040'),
  'kind', 'accept_proposal', 'payload', jsonb_build_object('proposal_id', 'b9000000-0000-4000-8000-000000000f02', 'activity_id', 'a9100000-0000-4000-8000-000000000002')))) ->> 'code', 'PROPOSAL_EXPIRED', 'general proposal expires when the session concern changed (fresh CAS)');
-- (3) the third receipt also cited the session at the OLD revision, so it is stale too ...
SELECT support_test.eq((public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', '90000000-0000-4000-8000-000000000005',
  'session_id', '51000000-0000-4000-8000-000000000040', 'expected_revision', (SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000040'),
  'kind', 'accept_proposal', 'payload', jsonb_build_object('proposal_id', 'b9000000-0000-4000-8000-000000000f03', 'activity_id', 'a9100000-0000-4000-8000-000000000003')))) ->> 'code', 'PROPOSAL_EXPIRED', 'named-basis proposal also expires when another receipt source (session) changed');
RESET ROLE;
-- (4) FRESH control: a new receipt built from the CURRENT session revision and an unchanged message accepts, named and general
INSERT INTO public.support_context_receipts (id, user_id, request_id, support_session_id, conversation_id, privacy_revision, scope, provider_vendor, provider_model, route_version)
SELECT x.rid, 'aaaaaaaa-0000-4000-8000-000000000001', x.req, '51000000-0000-4000-8000-000000000040', 'cccccccc-0000-4000-8000-000000000001',
       (SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 'conversation_only', 'openai', 'm', 'r'
FROM (VALUES ('e0000000-0000-4000-8000-0000000000f4'::uuid, 'b6000000-0000-4000-8000-000000000004'::uuid),
             ('e0000000-0000-4000-8000-0000000000f5'::uuid, 'b6000000-0000-4000-8000-000000000005'::uuid)) AS x(rid, req);
INSERT INTO public.support_context_receipt_sources (receipt_id, user_id, source_kind, source_id, source_revision)
SELECT r.rid, 'aaaaaaaa-0000-4000-8000-000000000001', 'session', '51000000-0000-4000-8000-000000000040'::uuid,
       (SELECT context_revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000040')
FROM (VALUES ('e0000000-0000-4000-8000-0000000000f4'::uuid), ('e0000000-0000-4000-8000-0000000000f5'::uuid)) AS r(rid);
INSERT INTO public.support_context_receipt_sources (receipt_id, user_id, source_kind, source_id, source_revision) VALUES
  ('e0000000-0000-4000-8000-0000000000f4', 'aaaaaaaa-0000-4000-8000-000000000001', 'message', 'f0000000-0000-4000-8000-0000000000e3', 0),
  ('e0000000-0000-4000-8000-0000000000f5', 'aaaaaaaa-0000-4000-8000-000000000001', 'message', 'f0000000-0000-4000-8000-0000000000e3', 0);
INSERT INTO public.support_proposals (id, user_id, support_session_id, request_id, template_key, reason_code, basis_kind, basis_ref, privacy_revision, status, expires_at)
SELECT x.id, 'aaaaaaaa-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000040', x.req, x.tk, x.rc, x.bk, x.bref,
       (SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 'offered', now() + interval '1 day'
FROM (VALUES
  ('b9000000-0000-4000-8000-000000000f04'::uuid, 'b6000000-0000-4000-8000-000000000004'::uuid, 'choose_step_v1'::text, 'current_request'::text, 'message'::text, 'f0000000-0000-4000-8000-0000000000e3'::uuid),
  ('b9000000-0000-4000-8000-000000000f05'::uuid, 'b6000000-0000-4000-8000-000000000005'::uuid, 'ground_present_v1'::text, 'general_option'::text, NULL::text, NULL::uuid)
) AS x(id, req, tk, rc, bk, bref);
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT support_test.eq((public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', '90000000-0000-4000-8000-000000000006',
  'session_id', '51000000-0000-4000-8000-000000000040', 'expected_revision', (SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000040'),
  'kind', 'accept_proposal', 'payload', jsonb_build_object('proposal_id', 'b9000000-0000-4000-8000-000000000f04', 'activity_id', 'a9100000-0000-4000-8000-000000000004')))) ->> 'ok', 'true', 'fresh named-basis proposal accepts');
SELECT support_test.eq((public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', '90000000-0000-4000-8000-000000000007',
  'session_id', '51000000-0000-4000-8000-000000000040', 'expected_revision', (SELECT revision FROM public.support_work_sessions WHERE id = '51000000-0000-4000-8000-000000000040'),
  'kind', 'accept_proposal', 'payload', jsonb_build_object('proposal_id', 'b9000000-0000-4000-8000-000000000f05', 'activity_id', 'a9100000-0000-4000-8000-000000000005')))) ->> 'ok', 'true', 'fresh general proposal accepts');
-- confirmed-operation replay still precedes all of the above checks
SELECT support_test.eq((public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', '90000000-0000-4000-8000-000000000006',
  'session_id', '51000000-0000-4000-8000-000000000040', 'expected_revision', 1,
  'kind', 'accept_proposal', 'payload', jsonb_build_object('proposal_id', 'b9000000-0000-4000-8000-000000000f04', 'activity_id', 'a9100000-0000-4000-8000-000000000004')))) ->> 'replayed', 'true', 'replay of the confirmed accept is unchanged');
RESET ROLE;

\echo 'support_session.sql: all assertions passed (NOT EXECUTED by its author)'
