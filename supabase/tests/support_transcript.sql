-- append_support_transcript contract test. NOT EXECUTED by its author (source-only until the
-- parent reviews it); NO result in this file has been observed. DISPOSABLE LOCAL DATABASE ONLY,
-- with the whole migration chain through 20261107050000_support_transcript.sql applied on top of
-- the LATEST M3 chain (private support_acquire_write_mutex, support_raise, messages.content_revision
-- and its guard/mutex triggers). Synthetic users only; run as a superuser/owner role (it switches
-- to anon/authenticated/service_role itself), expect it to leave the database dirty, and drop the
-- database afterwards. No provider, network, microphone, budget or XP is involved.
-- As in support_session.sql, adjust the FIXTURE block (minimal auth.users/conversations inserts)
-- for the selected schema, not the assertions. The two-connection procedures at the end are
-- comments: psql -f does NOT run them.
\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION pg_temp.eq(actual anyelement, expected anyelement, label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF actual IS DISTINCT FROM expected THEN
    RAISE EXCEPTION 'FAIL %: got %, want %', label, actual, expected;
  END IF;
END $$;
-- Runs one statement and returns its error message, or 'OK'.
CREATE OR REPLACE FUNCTION pg_temp.err(stmt text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE stmt;
  RETURN 'OK';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLERRM;
END $$;
CREATE OR REPLACE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', u::text, false);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, false);
  EXECUTE 'SET ROLE authenticated';
END $$;
CREATE OR REPLACE FUNCTION pg_temp.as_nobody() RETURNS void LANGUAGE plpgsql AS $$
BEGIN   -- authenticated database role, but no subject claim
  PERFORM set_config('request.jwt.claim.sub', '', false);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', false);
  PERFORM set_config('request.jwt.claims', '{"role":"authenticated"}', false);
  EXECUTE 'SET ROLE authenticated';
END $$;
CREATE OR REPLACE FUNCTION pg_temp.as_anon() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', false);
  PERFORM set_config('request.jwt.claim.role', 'anon', false);
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', false);
  EXECUTE 'SET ROLE anon';
END $$;
CREATE OR REPLACE FUNCTION pg_temp.as_service() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.role', 'service_role', false);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', false);
  EXECUTE 'SET ROLE service_role';
END $$;
-- True when THIS backend holds M3's private write mutex (a transaction-scoped advisory lock).
CREATE OR REPLACE FUNCTION pg_temp.mutex_held() RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM pg_locks
    WHERE locktype = 'advisory' AND pid = pg_backend_pid() AND granted
      AND ((classid::bigint << 32) | objid::bigint) = hashtextextended('mindfriend.support.context-write-mutex', 0));
$$;
-- Fixed instants (now() is per statement in autocommit; replays must reuse the same value).
CREATE TEMP TABLE tx_at(k text PRIMARY KEY, v timestamptz);
GRANT SELECT ON tx_at TO PUBLIC;
INSERT INTO tx_at VALUES ('t1', now() - interval '30 minutes'), ('t2', now() - interval '29 minutes'),
  ('t3', now() - interval '28 minutes'), ('t4', now() - interval '27 minutes');
CREATE OR REPLACE FUNCTION pg_temp.tm(p_k text) RETURNS timestamptz LANGUAGE sql STABLE AS $$ SELECT v FROM tx_at WHERE tx_at.k = p_k $$;
-- The RPC with defaults; invoker rights, so the caller's role and claims decide everything.
CREATE OR REPLACE FUNCTION pg_temp.ap(
  p_owner uuid, p_session uuid, p_conv uuid, p_event uuid, p_call uuid, p_order bigint, p_role text, p_text text,
  p_at timestamptz, p_item text DEFAULT NULL, p_pev text DEFAULT NULL
) RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.append_support_transcript(p_owner, p_session, p_conv, p_event, p_call, p_order, p_role, p_text, p_at, p_item, p_pev)
$$;

-- ===================== FIXTURE =====================
RESET ROLE;
INSERT INTO public.supported_languages(code,name,native_name,is_active) VALUES('en','English','English',true) ON CONFLICT DO NOTHING;
INSERT INTO public.level_thresholds(level,xp_required,title) VALUES(1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO public.skill_thresholds(level,xp_required,title) VALUES(1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO auth.users (id, aud, role, email) VALUES
  ('aaaaaaaa-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'ta@example.invalid'),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'tb@example.invalid');
INSERT INTO public.conversations (id, user_id) VALUES
  ('c1000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001'),   -- CA1 open session
  ('c1000000-0000-4000-8000-000000000002', 'aaaaaaaa-0000-4000-8000-000000000001'),   -- CA2 session will be closed
  ('c1000000-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001'),   -- CA3 session will be deleted
  ('c1000000-0000-4000-8000-000000000004', 'aaaaaaaa-0000-4000-8000-000000000001'),   -- CA4 no session attached
  ('c1000000-0000-4000-8000-000000000005', 'aaaaaaaa-0000-4000-8000-000000000001'),   -- CA5 will be suppressed
  ('c1000000-0000-4000-8000-000000000006', 'aaaaaaaa-0000-4000-8000-000000000001'),   -- CA6 ordering / cascade
  ('c2000000-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000002');   -- CB1
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT public.support_apply_mutation(format('{"schema_version":1,"operation_id":"%s","session_id":"%s","expected_revision":null,"kind":"create","payload":{"title":"s","context_scope":"conversation_only"%s}}',
  op, sid, CASE WHEN conv IS NULL THEN '' ELSE ',"conversation_id":"' || conv || '"' END)::jsonb)
FROM (VALUES
  ('10000000-0000-4000-8000-0000000000a1', '5a000000-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-0000000000a2', '5a000000-0000-4000-8000-000000000002', 'c1000000-0000-4000-8000-000000000002'),
  ('10000000-0000-4000-8000-0000000000a3', '5a000000-0000-4000-8000-000000000003', 'c1000000-0000-4000-8000-000000000003'),
  ('10000000-0000-4000-8000-0000000000a5', '5a000000-0000-4000-8000-000000000005', 'c1000000-0000-4000-8000-000000000005'),
  ('10000000-0000-4000-8000-0000000000a6', '5a000000-0000-4000-8000-000000000006', 'c1000000-0000-4000-8000-000000000006'),
  ('10000000-0000-4000-8000-0000000000a7', '5a000000-0000-4000-8000-000000000007', NULL)   -- SA7: never attached
) v(op, sid, conv);
SELECT pg_temp.as_user('bbbbbbbb-0000-4000-8000-000000000002');
SELECT public.support_apply_mutation('{"schema_version":1,"operation_id":"20000000-0000-4000-8000-0000000000b1","session_id":"5b000000-0000-4000-8000-000000000001","expected_revision":null,"kind":"create","payload":{"title":"b","context_scope":"conversation_only","conversation_id":"c2000000-0000-4000-8000-000000000001"}}'::jsonb);
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
-- SA2 is closed through the real contract.
SELECT pg_temp.eq(public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-0000000000c2","session_id":"5a000000-0000-4000-8000-000000000002","expected_revision":1,"kind":"update_session","payload":{"close":"end_unfinished"}}'::jsonb) ->> 'ok', 'true', 'SA2 closed');
RESET ROLE;

-- ===================== GRANTS / AUTHENTICATION =====================
SELECT pg_temp.eq(has_function_privilege('authenticated', 'public.append_support_transcript(uuid,uuid,uuid,uuid,uuid,bigint,text,text,timestamptz,text,text)', 'EXECUTE'), true, 'authenticated can execute');
SELECT pg_temp.eq(
  has_function_privilege('anon', 'public.append_support_transcript(uuid,uuid,uuid,uuid,uuid,bigint,text,text,timestamptz,text,text)', 'EXECUTE')
  OR has_function_privilege('service_role', 'public.append_support_transcript(uuid,uuid,uuid,uuid,uuid,bigint,text,text,timestamptz,text,text)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.support_transcript_guard()', 'EXECUTE'),
  false, 'only authenticated may execute the RPC; the guard is not executable');
SELECT pg_temp.eq((SELECT prosecdef FROM pg_proc WHERE oid = 'public.append_support_transcript(uuid,uuid,uuid,uuid,uuid,bigint,text,text,timestamptz,text,text)'::regprocedure), true, 'security definer');
SELECT pg_temp.eq((SELECT proconfig::text FROM pg_proc WHERE oid = 'public.append_support_transcript(uuid,uuid,uuid,uuid,uuid,bigint,text,text,timestamptz,text,text)'::regprocedure) LIKE '%search_path=pg_catalog, public, pg_temp%', true, 'fixed safe search_path');

SELECT pg_temp.as_anon();
SELECT pg_temp.eq(pg_temp.err($q$SELECT pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','ca110000-0000-4000-8000-000000000001',1,'user','hi',now())$q$) LIKE '%permission denied%', true, 'anon cannot call');
SELECT pg_temp.as_nobody();
SELECT pg_temp.eq(pg_temp.err($q$SELECT pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','ca110000-0000-4000-8000-000000000001',1,'user','hi',now())$q$), 'AUTH_REQUIRED', 'no subject: AUTH_REQUIRED');
RESET ROLE;
SELECT pg_temp.eq((SELECT count(*) FROM public.messages WHERE id = 'e0000000-0000-4000-8000-000000000001')::int, 0, 'rejected callers wrote nothing');

-- ===================== OWNER =====================
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('bbbbbbbb-0000-4000-8000-000000000002','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','ca110000-0000-4000-8000-000000000001',1,'user','hi',pg_temp.tm('t1')) ->> 'code', 'OWNER_MISMATCH', 'a captured owner that is not auth.uid() is refused');
SELECT pg_temp.eq(pg_temp.ap(NULL,'5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','ca110000-0000-4000-8000-000000000001',1,'user','hi',pg_temp.tm('t1')) ->> 'code', 'OWNER_MISMATCH', 'missing owner refused');
RESET ROLE;
SELECT pg_temp.eq((SELECT count(*) FROM public.messages WHERE id = 'e0000000-0000-4000-8000-000000000001')::int, 0, 'owner mismatch wrote nothing');

-- ===================== HAPPY PATH =====================
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
CREATE TEMP TABLE tx_r(k text PRIMARY KEY, v jsonb);
GRANT ALL ON tx_r TO PUBLIC;
INSERT INTO tx_r SELECT 'first', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','ca110000-0000-4000-8000-000000000001',1,'user','I keep putting off an email',pg_temp.tm('t1'),'item_1','evt_1');
SELECT pg_temp.eq((SELECT v ->> 'ok' FROM tx_r WHERE k='first'), 'true', 'first append ok');
SELECT pg_temp.eq((SELECT v ->> 'replay' FROM tx_r WHERE k='first'), 'false', 'first append is not a replay');
SELECT pg_temp.eq((SELECT v ->> 'event_id' FROM tx_r WHERE k='first'), 'e0000000-0000-4000-8000-000000000001', 'event_id echoed');
SELECT pg_temp.eq((SELECT v ->> 'message_id' FROM tx_r WHERE k='first'), 'e0000000-0000-4000-8000-000000000001', 'message_id = event_id (the canonical row)');
SELECT pg_temp.eq((SELECT v ->> 'conversation_id' FROM tx_r WHERE k='first'), 'c1000000-0000-4000-8000-000000000001', 'conversation_id');
SELECT pg_temp.eq((SELECT v ->> 'voice_call_id' FROM tx_r WHERE k='first'), 'ca110000-0000-4000-8000-000000000001', 'voice_call_id');
SELECT pg_temp.eq((SELECT (v ->> 'event_order')::bigint FROM tx_r WHERE k='first'), 1::bigint, 'event_order');
SELECT pg_temp.eq((SELECT v ->> 'role' FROM tx_r WHERE k='first'), 'user', 'role');
SELECT pg_temp.eq((SELECT (v ->> 'occurred_at')::timestamptz FROM tx_r WHERE k='first'), pg_temp.tm('t1'), 'occurred_at');
SELECT pg_temp.eq((SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys((SELECT v FROM tx_r WHERE k='first')) AS key),
  ARRAY['conversation_id','event_id','event_order','message_id','occurred_at','ok','replay','role','voice_call_id'], 'exact response keys, and no body');
RESET ROLE;
SELECT pg_temp.eq((SELECT count(*) FROM public.messages WHERE id = 'e0000000-0000-4000-8000-000000000001')::int, 1, 'one canonical message');
SELECT pg_temp.eq((SELECT content FROM public.messages WHERE id = 'e0000000-0000-4000-8000-000000000001'), 'I keep putting off an email', 'text stored as the canonical content');
SELECT pg_temp.eq((SELECT support_session_id FROM public.messages WHERE id = 'e0000000-0000-4000-8000-000000000001'), '5a000000-0000-4000-8000-000000000001'::uuid, 'session identity carried');
SELECT pg_temp.eq((SELECT voice_provider_item_id || '/' || voice_provider_event_id FROM public.messages WHERE id = 'e0000000-0000-4000-8000-000000000001'), 'item_1/evt_1', 'provider identity carried');
SELECT pg_temp.eq((SELECT created_at = voice_occurred_at AND voice_occurred_at = pg_temp.tm('t1') FROM public.messages WHERE id = 'e0000000-0000-4000-8000-000000000001'), true, 'created_at is the actual time of speech');
SELECT pg_temp.eq((SELECT content_revision FROM public.messages WHERE id = 'e0000000-0000-4000-8000-000000000001'), 0::bigint, 'new message starts at M3 version 0');
SELECT pg_temp.eq((SELECT content_origin IS NULL FROM public.messages WHERE id = 'e0000000-0000-4000-8000-000000000001'), true, 'ordinary (model-origin) history row for existing readers');
-- No second transcript-text store was created.
SELECT pg_temp.eq((SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name ILIKE '%transcript%')::int, 0, 'no duplicate transcript table');

-- ===================== 100 REPLAYS -> ONE canonical message =====================
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
DO $$
DECLARE r jsonb; i int; before_ts timestamptz; after_ts timestamptz;
BEGIN
  SELECT updated_at INTO before_ts FROM public.conversations WHERE id = 'c1000000-0000-4000-8000-000000000001';
  FOR i IN 1..100 LOOP
    r := pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','ca110000-0000-4000-8000-000000000001',1,'user','I keep putting off an email',pg_temp.tm('t1'),'item_1','evt_1');
    IF r ->> 'ok' <> 'true' OR r ->> 'replay' <> 'true' OR r ->> 'message_id' <> 'e0000000-0000-4000-8000-000000000001' THEN
      RAISE EXCEPTION 'FAIL replay %: %', i, r;
    END IF;
  END LOOP;
  SELECT updated_at INTO after_ts FROM public.conversations WHERE id = 'c1000000-0000-4000-8000-000000000001';
  IF after_ts IS DISTINCT FROM before_ts THEN RAISE EXCEPTION 'FAIL replays touched the conversation'; END IF;
END $$;
RESET ROLE;
SELECT pg_temp.eq((SELECT count(*) FROM public.messages WHERE id = 'e0000000-0000-4000-8000-000000000001')::int, 1, '100 replays still one message');
SELECT pg_temp.eq((SELECT count(*) FROM public.messages WHERE conversation_id = 'c1000000-0000-4000-8000-000000000001' AND voice_call_id IS NOT NULL)::int, 1, 'replays created no other row');

-- ===================== ALTERED REPLAY (same id) is refused; the stored row never changes =====================
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','ca110000-0000-4000-8000-000000000001',1,'user','CHANGED',pg_temp.tm('t1'),'item_1','evt_1') ->> 'code', 'OPERATION_ID_REUSED', 'text altered');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','ca110000-0000-4000-8000-000000000001',1,'assistant','I keep putting off an email',pg_temp.tm('t1'),'item_1','evt_1') ->> 'code', 'OPERATION_ID_REUSED', 'role altered');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','ca110000-0000-4000-8000-000000000001',2,'user','I keep putting off an email',pg_temp.tm('t1'),'item_1','evt_1') ->> 'code', 'OPERATION_ID_REUSED', 'order altered');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','ca110000-0000-4000-8000-000000000002',1,'user','I keep putting off an email',pg_temp.tm('t1'),'item_1','evt_1') ->> 'code', 'OPERATION_ID_REUSED', 'call altered');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','ca110000-0000-4000-8000-000000000001',1,'user','I keep putting off an email',pg_temp.tm('t2'),'item_1','evt_1') ->> 'code', 'OPERATION_ID_REUSED', 'occurred_at altered');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','ca110000-0000-4000-8000-000000000001',1,'user','I keep putting off an email',pg_temp.tm('t1'),'item_X','evt_1') ->> 'code', 'OPERATION_ID_REUSED', 'provider item altered');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','ca110000-0000-4000-8000-000000000001',1,'user','I keep putting off an email',pg_temp.tm('t1'),'item_1',NULL) ->> 'code', 'OPERATION_ID_REUSED', 'provider event dropped');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000006','c1000000-0000-4000-8000-000000000006','e0000000-0000-4000-8000-000000000001','ca110000-0000-4000-8000-000000000001',1,'user','I keep putting off an email',pg_temp.tm('t1'),'item_1','evt_1') ->> 'code', 'OPERATION_ID_REUSED', 'same id claimed for another own conversation');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000006','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','ca110000-0000-4000-8000-000000000001',1,'user','I keep putting off an email',pg_temp.tm('t1'),'item_1','evt_1') ->> 'code', 'OPERATION_ID_REUSED', 'same id claimed under another session');
RESET ROLE;
SELECT pg_temp.eq((SELECT content || '|' || role::text || '|' || voice_event_order::text || '|' || voice_call_id::text FROM public.messages WHERE id = 'e0000000-0000-4000-8000-000000000001'),
  'I keep putting off an email|user|1|ca110000-0000-4000-8000-000000000001', 'no overwrite: the original row is exactly as first stored');
SELECT pg_temp.eq((SELECT count(*) FROM public.messages WHERE voice_call_id IS NOT NULL)::int, 1, 'refusals created nothing');

-- ===================== CROSS-OWNER: identical answers, no existence leak =====================
SELECT pg_temp.as_user('bbbbbbbb-0000-4000-8000-000000000002');
-- B reuses A's event id for its own, valid conversation/session: indistinguishable from an altered replay.
SELECT pg_temp.eq(pg_temp.ap('bbbbbbbb-0000-4000-8000-000000000002','5b000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000001','cb110000-0000-4000-8000-000000000001',1,'user','B text',pg_temp.tm('t1')) ->> 'code', 'OPERATION_ID_REUSED', 'foreign event id is unusable, with the generic answer');
-- B naming A's session or A's conversation: the answer for a foreign and for a nonexistent id is the SAME value.
SELECT pg_temp.eq(
  pg_temp.ap('bbbbbbbb-0000-4000-8000-000000000002','5a000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000b1','cb110000-0000-4000-8000-000000000001',1,'user','x',pg_temp.tm('t1')),
  pg_temp.ap('bbbbbbbb-0000-4000-8000-000000000002','5a999999-0000-4000-8000-000000000999','c2000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000b1','cb110000-0000-4000-8000-000000000001',1,'user','x',pg_temp.tm('t1')),
  'foreign session == nonexistent session');
SELECT pg_temp.eq(
  pg_temp.ap('bbbbbbbb-0000-4000-8000-000000000002','5b000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000b2','cb110000-0000-4000-8000-000000000001',1,'user','x',pg_temp.tm('t1')),
  pg_temp.ap('bbbbbbbb-0000-4000-8000-000000000002','5b000000-0000-4000-8000-000000000001','c9999999-0000-4000-8000-000000000999','e0000000-0000-4000-8000-0000000000b2','cb110000-0000-4000-8000-000000000001',1,'user','x',pg_temp.tm('t1')),
  'foreign conversation == nonexistent conversation');
SELECT pg_temp.eq(pg_temp.ap('bbbbbbbb-0000-4000-8000-000000000002','5b000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000b2','cb110000-0000-4000-8000-000000000001',1,'user','x',pg_temp.tm('t1')) ->> 'code', 'NOT_FOUND', 'foreign conversation is NOT_FOUND');
-- A's call id and order used by B in B's own conversation never collide (uniqueness is per owned conversation).
SELECT pg_temp.eq(pg_temp.ap('bbbbbbbb-0000-4000-8000-000000000002','5b000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000b3','ca110000-0000-4000-8000-000000000001',1,'user','B turn',pg_temp.tm('t1')) ->> 'ok', 'true', 'B may use any call id; no cross-owner collision signal');
RESET ROLE;
SELECT pg_temp.eq((SELECT conversation_id FROM public.messages WHERE id = 'e0000000-0000-4000-8000-000000000001'), 'c1000000-0000-4000-8000-000000000001'::uuid, 'A''s row untouched by B');

-- ===================== SESSION STATE: unattached / mismatched / closed / deleted =====================
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000007','c1000000-0000-4000-8000-000000000004','e0000000-0000-4000-8000-000000000010','ca110000-0000-4000-8000-000000000010',1,'user','x',pg_temp.tm('t1')) ->> 'code', 'SESSION_CONVERSATION_MISMATCH', 'a session with no conversation attached');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000004','e0000000-0000-4000-8000-000000000011','ca110000-0000-4000-8000-000000000010',1,'user','x',pg_temp.tm('t1')) ->> 'code', 'SESSION_CONVERSATION_MISMATCH', 'a session attached to a DIFFERENT own conversation');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000004','e0000000-0000-4000-8000-000000000011','ca110000-0000-4000-8000-000000000010',1,'user','x',pg_temp.tm('t1')) ->> 'ok', 'false', 'not stored');
-- Closed session. Close preserves history and the conversation attachment, and a final turn can have
-- been acknowledged locally BEFORE an offline Close, so a first upload after Close is accepted as
-- STORAGE-ONLY reconciliation: same ids, bounds and replay-first semantics, and no session, activity,
-- event, receipt, proposal, privacy or conversation-ordering side effect. (Voice Start/admission stays
-- open-only; that is the voice admission functions, not this RPC.) Deleted and suppressed stay refused.
RESET ROLE;
CREATE TEMP TABLE tx_closed AS SELECT
  (SELECT row(s.revision, s.updated_at, s.status, s.closed_at, s.context_revision, s.conversation_id)::text
     FROM public.support_work_sessions s WHERE s.id = '5a000000-0000-4000-8000-000000000002') AS sess,
  (SELECT updated_at FROM public.conversations WHERE id = 'c1000000-0000-4000-8000-000000000002') AS conv_updated,
  (SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') AS priv,
  (SELECT count(*) FROM public.support_activities WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') AS acts,
  (SELECT count(*) FROM public.support_session_events WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') AS evs,
  (SELECT count(*) FROM public.support_mutation_receipts WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') AS rcpts,
  (SELECT count(*) FROM public.support_proposals WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') AS props;
GRANT SELECT ON tx_closed TO PUBLIC;
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
-- A closed session attached to ANOTHER conversation than the one named is still a mismatch.
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000004','e0000000-0000-4000-8000-000000000019','ca110000-0000-4000-8000-000000000019',1,'user','x',pg_temp.tm('t1')) ->> 'code', 'SESSION_CONVERSATION_MISMATCH', 'closed: exact attachment is still required');
INSERT INTO tx_r SELECT 'ca2', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000002','e0000000-0000-4000-8000-000000000020','ca110000-0000-4000-8000-000000000020',1,'user','sent before the session closed',pg_temp.tm('t1'));
RESET ROLE;
SELECT pg_temp.eq((SELECT v ->> 'ok' || '/' || (v ->> 'replay') FROM tx_r WHERE k='ca2'), 'true/false', 'the FIRST upload after Close is stored (storage-only reconciliation), not refused');
SELECT pg_temp.eq((SELECT content || '|' || coalesce(support_session_id::text, 'NULL') || '|' || voice_event_order::text FROM public.messages WHERE id = 'e0000000-0000-4000-8000-000000000020'),
  'sent before the session closed|5a000000-0000-4000-8000-000000000002|1', 'stored with its session identity');
SELECT pg_temp.eq((SELECT row(s.revision, s.updated_at, s.status, s.closed_at, s.context_revision, s.conversation_id)::text FROM public.support_work_sessions s WHERE s.id = '5a000000-0000-4000-8000-000000000002'),
  (SELECT sess FROM tx_closed), 'the closed session row is byte-for-byte unchanged (still closed)');
SELECT pg_temp.eq((SELECT updated_at FROM public.conversations WHERE id = 'c1000000-0000-4000-8000-000000000002'), (SELECT conv_updated FROM tx_closed), 'a closed-session reconciliation does not re-rank the conversation');
SELECT pg_temp.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'), (SELECT priv FROM tx_closed), 'no privacy revision change');
SELECT pg_temp.eq(ARRAY[(SELECT count(*) FROM public.support_activities WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'), (SELECT count(*) FROM public.support_session_events WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'),
   (SELECT count(*) FROM public.support_mutation_receipts WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001'), (SELECT count(*) FROM public.support_proposals WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001')],
  ARRAY[(SELECT acts FROM tx_closed), (SELECT evs FROM tx_closed), (SELECT rcpts FROM tx_closed), (SELECT props FROM tx_closed)], 'no activity, session event, mutation receipt or proposal was created');
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000002','e0000000-0000-4000-8000-000000000020','ca110000-0000-4000-8000-000000000020',1,'user','sent before the session closed',pg_temp.tm('t1')) ->> 'replay', 'true', 'its replay is honored first');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000002','c1000000-0000-4000-8000-000000000002','e0000000-0000-4000-8000-000000000020','ca110000-0000-4000-8000-000000000020',1,'user','altered',pg_temp.tm('t1')) ->> 'code', 'OPERATION_ID_REUSED', 'an altered replay is still a conflict');
RESET ROLE;

-- Close AFTER confirming: confirm while open, close for real, then replay, extend and conflict.
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-0000000000a8","session_id":"5a000000-0000-4000-8000-000000000008","expected_revision":null,"kind":"create","payload":{"title":"late close","context_scope":"conversation_only","conversation_id":"c1000000-0000-4000-8000-000000000004"}}'::jsonb);
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000008','c1000000-0000-4000-8000-000000000004','e0000000-0000-4000-8000-000000000021','ca110000-0000-4000-8000-000000000021',1,'user','confirmed while open',pg_temp.tm('t1')) ->> 'ok', 'true', 'appended while open');
SELECT pg_temp.eq(public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-0000000000c8","session_id":"5a000000-0000-4000-8000-000000000008","expected_revision":1,"kind":"update_session","payload":{"close":"end_unfinished"}}'::jsonb) ->> 'ok', 'true', 'closed');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000008','c1000000-0000-4000-8000-000000000004','e0000000-0000-4000-8000-000000000021','ca110000-0000-4000-8000-000000000021',1,'user','confirmed while open',pg_temp.tm('t1')) ->> 'replay', 'true', 'a confirmed identical event is honored after the session closed');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000008','c1000000-0000-4000-8000-000000000004','e0000000-0000-4000-8000-000000000021','ca110000-0000-4000-8000-000000000021',1,'user','altered after close',pg_temp.tm('t1')) ->> 'code', 'OPERATION_ID_REUSED', 'an altered replay after closure is a conflict, not a replay');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000008','c1000000-0000-4000-8000-000000000004','e0000000-0000-4000-8000-000000000022','ca110000-0000-4000-8000-000000000021',2,'user','a later final of the same call, acknowledged before the offline close',pg_temp.tm('t2')) ->> 'replay', 'false', 'a NEW final after Close is stored (storage-only), not refused');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000008','c1000000-0000-4000-8000-000000000004','e0000000-0000-4000-8000-000000000022','ca110000-0000-4000-8000-000000000021',2,'user','a later final of the same call, acknowledged before the offline close',pg_temp.tm('t2')) ->> 'replay', 'true', 'and then replays');
RESET ROLE;
SELECT pg_temp.eq((SELECT status FROM public.support_work_sessions WHERE id = '5a000000-0000-4000-8000-000000000008'), 'closed', 'the session stayed closed (no reopen, no revision)');
-- Closed sessions never override erasure: a forgotten message id or a suppressed conversation takes nothing.
INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason)
VALUES ('aaaaaaaa-0000-4000-8000-000000000001', 'message', 'e0000000-0000-4000-8000-000000000023', 'user_source_exclusion');
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000008','c1000000-0000-4000-8000-000000000004','e0000000-0000-4000-8000-000000000023','ca110000-0000-4000-8000-000000000021',3,'user','a forgotten identity on a closed session',pg_temp.tm('t3')) ->> 'code', 'CONTENT_UNAVAILABLE', 'closed + forgotten message id: refused');
RESET ROLE;
INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason)
VALUES ('aaaaaaaa-0000-4000-8000-000000000001', 'conversation', 'c1000000-0000-4000-8000-000000000004', 'user_source_exclusion');
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000008','c1000000-0000-4000-8000-000000000004','e0000000-0000-4000-8000-000000000024','ca110000-0000-4000-8000-000000000021',4,'user','a suppressed conversation on a closed session',pg_temp.tm('t3')) ->> 'code', 'CONTENT_UNAVAILABLE', 'closed + suppressed conversation: refused');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000008','c1000000-0000-4000-8000-000000000004','e0000000-0000-4000-8000-000000000022','ca110000-0000-4000-8000-000000000021',2,'user','a later final of the same call, acknowledged before the offline close',pg_temp.tm('t2')) ->> 'replay', 'true', 'but an already-confirmed event still replays');
RESET ROLE;
DELETE FROM public.support_suppressions WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001' AND ref_id IN ('c1000000-0000-4000-8000-000000000004', 'e0000000-0000-4000-8000-000000000023');

-- Deleted session: content stays (original records remain), the link is detached, nothing resurrects.
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000003','c1000000-0000-4000-8000-000000000003','e0000000-0000-4000-8000-000000000030','ca110000-0000-4000-8000-000000000030',1,'user','before the session is deleted',pg_temp.tm('t1')) ->> 'ok', 'true', 'appended to SA3');
RESET ROLE;
CREATE TEMP TABLE tx_cnt AS SELECT (SELECT count(*) FROM public.messages) AS msgs, (SELECT count(*) FROM public.conversations) AS convs;
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-0000000000d3","session_id":"5a000000-0000-4000-8000-000000000003","expected_revision":1,"kind":"delete_session","payload":{}}'::jsonb) ->> 'ok', 'true', 'SA3 deleted through the real contract');
RESET ROLE;
SELECT pg_temp.eq((SELECT msgs FROM tx_cnt) = (SELECT count(*) FROM public.messages) AND (SELECT convs FROM tx_cnt) = (SELECT count(*) FROM public.conversations), true, 'session deletion removed no message and no conversation');
SELECT pg_temp.eq((SELECT support_session_id IS NULL AND voice_call_id IS NOT NULL AND voice_event_order = 1 AND content = 'before the session is deleted' FROM public.messages WHERE id = 'e0000000-0000-4000-8000-000000000030'), true, 'the original record remains; only the session link was detached');
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000003','c1000000-0000-4000-8000-000000000003','e0000000-0000-4000-8000-000000000030','ca110000-0000-4000-8000-000000000030',1,'user','before the session is deleted',pg_temp.tm('t1')) ->> 'replay', 'true', 'an identical replay naming the TOMBSTONED session is honored');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000003','c1000000-0000-4000-8000-000000000003','e0000000-0000-4000-8000-000000000030','ca110000-0000-4000-8000-000000000030',1,'user','altered',pg_temp.tm('t1')) ->> 'code', 'OPERATION_ID_REUSED', 'an altered replay is still refused');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000003','c1000000-0000-4000-8000-000000000003','e0000000-0000-4000-8000-000000000031','ca110000-0000-4000-8000-000000000030',2,'user','a new turn for a deleted session',pg_temp.tm('t2')) ->> 'code', 'NOT_FOUND', 'a NEW event for a deleted session is refused');
-- A replay that names a different, live session must not be accepted just because the stored link is NULL.
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000003','e0000000-0000-4000-8000-000000000030','ca110000-0000-4000-8000-000000000030',1,'user','before the session is deleted',pg_temp.tm('t1')) ->> 'code', 'OPERATION_ID_REUSED', 'a detached message is not adoptable by another session');
RESET ROLE;
SELECT pg_temp.eq((SELECT support_session_id IS NULL AND voice_source_session_id = '5a000000-0000-4000-8000-000000000003' FROM public.messages WHERE id = 'e0000000-0000-4000-8000-000000000030'), true, 'the session link was never restored; the immutable source session survives the delete');

-- ===================== TR-R03: two SEPARATELY deleted owned sessions, SAME conversation =====================
-- M3's delete clears messages.support_session_id AND the tombstone's conversation_id, so "some owned
-- session is deleted" proves nothing about where an event came from. Replay must name EXACTLY the
-- session the event was stored under (immutable voice_source_session_id), live, closed or deleted.
INSERT INTO public.conversations (id, user_id) VALUES ('c1000000-0000-4000-8000-00000000000b', 'aaaaaaaa-0000-4000-8000-000000000001');   -- CA11
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-0000000000ad","session_id":"5a000000-0000-4000-8000-00000000000d","expected_revision":null,"kind":"create","payload":{"title":"first life","context_scope":"conversation_only","conversation_id":"c1000000-0000-4000-8000-00000000000b"}}'::jsonb);
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000d','c1000000-0000-4000-8000-00000000000b','e0000000-0000-4000-8000-00000000d001','ca110000-0000-4000-8000-00000000d001',1,'user','first life of the conversation',pg_temp.tm('t1')) ->> 'ok', 'true', 'event 1 stored under SA13');
SELECT pg_temp.eq(public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-0000000000d4","session_id":"5a000000-0000-4000-8000-00000000000d","expected_revision":1,"kind":"delete_session","payload":{}}'::jsonb) ->> 'ok', 'true', 'SA13 deleted (frees the conversation)');
SELECT public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-0000000000ae","session_id":"5a000000-0000-4000-8000-00000000000e","expected_revision":null,"kind":"create","payload":{"title":"second life","context_scope":"conversation_only","conversation_id":"c1000000-0000-4000-8000-00000000000b"}}'::jsonb);
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000e','c1000000-0000-4000-8000-00000000000b','e0000000-0000-4000-8000-00000000d002','ca110000-0000-4000-8000-00000000d002',1,'assistant','second life of the conversation',pg_temp.tm('t2')) ->> 'ok', 'true', 'event 2 stored under SA14 (same conversation)');
SELECT pg_temp.eq(public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-0000000000d5","session_id":"5a000000-0000-4000-8000-00000000000e","expected_revision":1,"kind":"delete_session","payload":{}}'::jsonb) ->> 'ok', 'true', 'SA14 deleted');
RESET ROLE;
SELECT pg_temp.eq((SELECT count(*) FROM public.support_work_sessions WHERE id IN ('5a000000-0000-4000-8000-00000000000d', '5a000000-0000-4000-8000-00000000000e') AND status = 'deleted' AND conversation_id IS NULL AND user_id = 'aaaaaaaa-0000-4000-8000-000000000001')::int, 2, 'two owned tombstones, neither remembering the conversation');
SELECT pg_temp.eq((SELECT count(*) FROM public.messages WHERE id IN ('e0000000-0000-4000-8000-00000000d001', 'e0000000-0000-4000-8000-00000000d002') AND support_session_id IS NULL)::int, 2, 'both messages are detached: the current link proves nothing');
SELECT pg_temp.eq((SELECT array_agg(voice_source_session_id::text ORDER BY id) FROM public.messages WHERE id IN ('e0000000-0000-4000-8000-00000000d001', 'e0000000-0000-4000-8000-00000000d002')),
  ARRAY['5a000000-0000-4000-8000-00000000000d', '5a000000-0000-4000-8000-00000000000e'], 'but each still records its ORIGINAL session');
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
-- The original session replays; every other session, deleted or not, is a conflict.
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000d','c1000000-0000-4000-8000-00000000000b','e0000000-0000-4000-8000-00000000d001','ca110000-0000-4000-8000-00000000d001',1,'user','first life of the conversation',pg_temp.tm('t1')) ->> 'replay', 'true', 'event 1 + its ORIGINAL deleted session SA13: replay');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000e','c1000000-0000-4000-8000-00000000000b','e0000000-0000-4000-8000-00000000d001','ca110000-0000-4000-8000-00000000d001',1,'user','first life of the conversation',pg_temp.tm('t1')) ->> 'code', 'OPERATION_ID_REUSED', 'event 1 + a DIFFERENT deleted owned session SA14: conflict');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000e','c1000000-0000-4000-8000-00000000000b','e0000000-0000-4000-8000-00000000d002','ca110000-0000-4000-8000-00000000d002',1,'assistant','second life of the conversation',pg_temp.tm('t2')) ->> 'replay', 'true', 'event 2 + its ORIGINAL deleted session SA14: replay');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000d','c1000000-0000-4000-8000-00000000000b','e0000000-0000-4000-8000-00000000d002','ca110000-0000-4000-8000-00000000d002',1,'assistant','second life of the conversation',pg_temp.tm('t2')) ->> 'code', 'OPERATION_ID_REUSED', 'event 2 + SA13: conflict (the order of deletion does not matter)');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-00000000000b','e0000000-0000-4000-8000-00000000d001','ca110000-0000-4000-8000-00000000d001',1,'user','first life of the conversation',pg_temp.tm('t1')) ->> 'code', 'OPERATION_ID_REUSED', 'a LIVE owned session cannot adopt it either');
SELECT pg_temp.eq(
  pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5b000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-00000000000b','e0000000-0000-4000-8000-00000000d001','ca110000-0000-4000-8000-00000000d001',1,'user','first life of the conversation',pg_temp.tm('t1')),
  pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a999999-0000-4000-8000-000000000999','c1000000-0000-4000-8000-00000000000b','e0000000-0000-4000-8000-00000000d001','ca110000-0000-4000-8000-00000000d001',1,'user','first life of the conversation',pg_temp.tm('t1')),
  'a foreign session and a nonexistent session give the SAME answer (no existence leak)');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a999999-0000-4000-8000-000000000999','c1000000-0000-4000-8000-00000000000b','e0000000-0000-4000-8000-00000000d001','ca110000-0000-4000-8000-00000000d001',1,'user','first life of the conversation',pg_temp.tm('t1')) ->> 'code', 'OPERATION_ID_REUSED', 'a nonexistent session is a conflict, not a replay');
-- Nothing new can be added under a deleted session.
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000d','c1000000-0000-4000-8000-00000000000b','e0000000-0000-4000-8000-00000000d003','ca110000-0000-4000-8000-00000000d001',2,'user','new under SA13',pg_temp.tm('t3')) ->> 'code', 'NOT_FOUND', 'a NEW event under deleted SA13: NOT_FOUND');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000e','c1000000-0000-4000-8000-00000000000b','e0000000-0000-4000-8000-00000000d004','ca110000-0000-4000-8000-00000000d002',2,'user','new under SA14',pg_temp.tm('t3')) ->> 'code', 'NOT_FOUND', 'a NEW event under deleted SA14: NOT_FOUND');
-- A later LIVE session on the same conversation takes new events but never adopts the old ones.
SELECT public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-0000000000af","session_id":"5a000000-0000-4000-8000-00000000000f","expected_revision":null,"kind":"create","payload":{"title":"third life","context_scope":"conversation_only","conversation_id":"c1000000-0000-4000-8000-00000000000b"}}'::jsonb);
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000f','c1000000-0000-4000-8000-00000000000b','e0000000-0000-4000-8000-00000000d001','ca110000-0000-4000-8000-00000000d001',1,'user','first life of the conversation',pg_temp.tm('t1')) ->> 'code', 'OPERATION_ID_REUSED', 'the live SA15 on the same conversation cannot claim event 1');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000f','c1000000-0000-4000-8000-00000000000b','e0000000-0000-4000-8000-00000000d005','ca110000-0000-4000-8000-00000000d003',1,'user','a new event for the live session',pg_temp.tm('t3')) ->> 'replay', 'false', 'but it stores its own new events');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000d','c1000000-0000-4000-8000-00000000000b','e0000000-0000-4000-8000-00000000d001','ca110000-0000-4000-8000-00000000d001',1,'user','first life of the conversation',pg_temp.tm('t1')) ->> 'replay', 'true', 'and event 1 still replays under SA13 afterwards');
RESET ROLE;
-- No attach rewrite anywhere.
SELECT pg_temp.eq((SELECT array_agg(coalesce(support_session_id::text, 'NULL') || '>' || voice_source_session_id::text ORDER BY id) FROM public.messages WHERE conversation_id = 'c1000000-0000-4000-8000-00000000000b'),
  ARRAY['NULL>5a000000-0000-4000-8000-00000000000d', 'NULL>5a000000-0000-4000-8000-00000000000e', '5a000000-0000-4000-8000-00000000000f>5a000000-0000-4000-8000-00000000000f'],
  'old messages stay detached (no attach rewrite); the new one is attached to its own session; sources are immutable');

-- ===================== PRIVACY: forgotten sources are never re-introduced =====================
INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason)
VALUES ('aaaaaaaa-0000-4000-8000-000000000001', 'conversation', 'c1000000-0000-4000-8000-000000000005', 'user_source_exclusion');
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000005','c1000000-0000-4000-8000-000000000005','e0000000-0000-4000-8000-000000000040','ca110000-0000-4000-8000-000000000040',1,'user','into a forgotten conversation',pg_temp.tm('t1')) ->> 'code', 'CONTENT_UNAVAILABLE', 'a suppressed conversation takes no new transcript');
RESET ROLE;
-- A forgotten MESSAGE id: even a deleted row cannot be re-appended under the same identity.
INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason)
VALUES ('aaaaaaaa-0000-4000-8000-000000000001', 'message', 'e0000000-0000-4000-8000-000000000050', 'user_source_exclusion');
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000006','c1000000-0000-4000-8000-000000000006','e0000000-0000-4000-8000-000000000050','ca110000-0000-4000-8000-000000000050',1,'user','must not come back',pg_temp.tm('t1')) ->> 'code', 'CONTENT_UNAVAILABLE', 'a forgotten message identity is not resurrected');
RESET ROLE;
SELECT pg_temp.eq((SELECT count(*) FROM public.messages WHERE id IN ('e0000000-0000-4000-8000-000000000040', 'e0000000-0000-4000-8000-000000000050'))::int, 0, 'nothing was written for either');
-- An already-confirmed event in a conversation suppressed LATER still replays (no new content).
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000006','c1000000-0000-4000-8000-000000000006','e0000000-0000-4000-8000-000000000060','ca110000-0000-4000-8000-000000000060',1,'user','kept',pg_temp.tm('t1')) ->> 'ok', 'true', 'appended to CA6');
RESET ROLE;
INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason)
VALUES ('aaaaaaaa-0000-4000-8000-000000000001', 'conversation', 'c1000000-0000-4000-8000-000000000006', 'user_source_exclusion');
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000006','c1000000-0000-4000-8000-000000000006','e0000000-0000-4000-8000-000000000060','ca110000-0000-4000-8000-000000000060',1,'user','kept',pg_temp.tm('t1')) ->> 'replay', 'true', 'a confirmed identical event replays even after the conversation was suppressed');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000006','c1000000-0000-4000-8000-000000000006','e0000000-0000-4000-8000-000000000061','ca110000-0000-4000-8000-000000000060',2,'user','new',pg_temp.tm('t2')) ->> 'code', 'CONTENT_UNAVAILABLE', 'but a new event there is refused');
RESET ROLE;
DELETE FROM public.support_suppressions WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001' AND kind = 'conversation' AND ref_id = 'c1000000-0000-4000-8000-000000000006';

-- ===================== ORDERING: an older final arrives after a newer one =====================
-- Provider observation order is what the event carries; arrival order is irrelevant.
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000006','c1000000-0000-4000-8000-000000000006','e0000000-0000-4000-8000-000000000072','ca110000-0000-4000-8000-000000000070',2,'assistant','newer reply, arrives FIRST',pg_temp.tm('t3')) ->> 'ok', 'true', 'order 2 arrives first');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000006','c1000000-0000-4000-8000-000000000006','e0000000-0000-4000-8000-000000000071','ca110000-0000-4000-8000-000000000070',1,'user','older utterance, arrives SECOND',pg_temp.tm('t2')) ->> 'ok', 'true', 'order 1 arrives later and is accepted');
RESET ROLE;
SELECT pg_temp.eq((SELECT array_agg(id ORDER BY voice_event_order) FROM public.messages WHERE voice_call_id = 'ca110000-0000-4000-8000-000000000070'),
  ARRAY['e0000000-0000-4000-8000-000000000071', 'e0000000-0000-4000-8000-000000000072']::uuid[], 'metadata order is the provider order, not arrival order');
SELECT pg_temp.eq((SELECT array_agg(id ORDER BY created_at, id) FROM public.messages WHERE voice_call_id = 'ca110000-0000-4000-8000-000000000070'),
  ARRAY['e0000000-0000-4000-8000-000000000071', 'e0000000-0000-4000-8000-000000000072']::uuid[], 'existing created_at readers see chronological order');
SELECT pg_temp.eq((SELECT array_agg(voice_occurred_at ORDER BY voice_event_order) FROM public.messages WHERE voice_call_id = 'ca110000-0000-4000-8000-000000000070'),
  ARRAY[pg_temp.tm('t2'), pg_temp.tm('t3')], 'actual occurred timestamps preserved');
-- The existing shared context reader sees the same canonical rows, in that order, as ordinary history.
SELECT pg_temp.as_service();
SELECT pg_temp.eq((SELECT array_agg(h ->> 'id' ORDER BY ord) FROM jsonb_array_elements(public.support_context_sources('aaaaaaaa-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000006', 20, false) -> 'history') WITH ORDINALITY AS t(h, ord)
    WHERE h ->> 'id' IN ('e0000000-0000-4000-8000-000000000071', 'e0000000-0000-4000-8000-000000000072')),
  ARRAY['e0000000-0000-4000-8000-000000000071', 'e0000000-0000-4000-8000-000000000072'], 'M3 context history includes transcript turns chronologically');
RESET ROLE;

-- ===================== HISTORY ORDER: support_context_sources honors the provider order =====================
-- Root M3 sorts history by (created_at, id). The wire rounds to milliseconds, so voice order 1 and order 2
-- can TIE, or a clock reversal can invert them. The replaced reader groups each call at the MINIMUM
-- created_at of its rows in the owned conversation, orders a call numerically by voice_event_order, keeps
-- ordinary messages on (created_at, id), and applies the limit after that ordering.
INSERT INTO tx_at
  SELECT k, base.v + delta FROM (VALUES
    ('tT', interval '0'), ('tT1', interval '1 second'), ('tTm1', interval '-1 second'), ('tTmid', interval '0.5 second'),
    ('p_before', interval '-60 seconds'), ('p_after', interval '120 seconds'),
    ('a1', interval '-50 seconds'), ('a2', interval '-40 seconds'), ('a3', interval '-30 seconds'), ('a5', interval '-10 seconds'),
    ('b_early', interval '-1 hour')
  ) o(k, delta), (SELECT now() - interval '20 minutes' AS v) base;
INSERT INTO public.conversations (id, user_id) VALUES
  ('c1000000-0000-4000-8000-000000000007', 'aaaaaaaa-0000-4000-8000-000000000001'),   -- CA7 tie
  ('c1000000-0000-4000-8000-000000000008', 'aaaaaaaa-0000-4000-8000-000000000001'),   -- CA8 reversed clock + plain neighbours + limit
  ('c1000000-0000-4000-8000-000000000009', 'aaaaaaaa-0000-4000-8000-000000000001'),   -- CA9 two calls at one instant + cross-conversation isolation
  ('c1000000-0000-4000-8000-00000000000a', 'aaaaaaaa-0000-4000-8000-000000000001');   -- CA10 plain-only control
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT public.support_apply_mutation(format('{"schema_version":1,"operation_id":"%s","session_id":"%s","expected_revision":null,"kind":"create","payload":{"title":"o","context_scope":"conversation_only","conversation_id":"%s"}}', op, sid, conv)::jsonb)
FROM (VALUES
  ('10000000-0000-4000-8000-0000000000aa', '5a000000-0000-4000-8000-00000000000a', 'c1000000-0000-4000-8000-000000000007'),
  ('10000000-0000-4000-8000-0000000000ab', '5a000000-0000-4000-8000-00000000000b', 'c1000000-0000-4000-8000-000000000008'),
  ('10000000-0000-4000-8000-0000000000ac', '5a000000-0000-4000-8000-00000000000c', 'c1000000-0000-4000-8000-000000000009')) v(op, sid, conv);
RESET ROLE;
-- helpers: the history array as the shared reader returns it, and its ids / voice orders
CREATE OR REPLACE FUNCTION pg_temp.hist(p_conv uuid, p_limit int DEFAULT 20) RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.support_context_sources('aaaaaaaa-0000-4000-8000-000000000001'::uuid, p_conv, p_limit, false) -> 'history' $$;
CREATE OR REPLACE FUNCTION pg_temp.ids(h jsonb) RETURNS text[] LANGUAGE sql AS $$
  SELECT coalesce(array_agg(e ->> 'id' ORDER BY ord), '{}') FROM jsonb_array_elements(h) WITH ORDINALITY t(e, ord) $$;

-- (1) TIED timestamps, delayed arrival. order 1 has the LARGER uuid (...702), order 2 the smaller (...701),
--     both at the same instant; order 2 arrives FIRST. (created_at, id) alone would put order 2 first.
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000a','c1000000-0000-4000-8000-000000000007','e0000000-0000-4000-8000-000000000701','ca110000-0000-4000-8000-000000000071',2,'assistant','second observation, arrives first',pg_temp.tm('tT')) ->> 'ok', 'true', 'tie: order 2 stored first');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000a','c1000000-0000-4000-8000-000000000007','e0000000-0000-4000-8000-000000000702','ca110000-0000-4000-8000-000000000071',1,'user','first observation, arrives later',pg_temp.tm('tT')) ->> 'ok', 'true', 'tie: order 1 stored second');
RESET ROLE;
SELECT pg_temp.eq((SELECT array_agg(id::text ORDER BY created_at, id) FROM public.messages WHERE conversation_id = 'c1000000-0000-4000-8000-000000000007'),
  ARRAY['e0000000-0000-4000-8000-000000000701', 'e0000000-0000-4000-8000-000000000702'], 'the fixture discriminates: (created_at, id) alone would put order 2 first');
SELECT pg_temp.as_service();
SELECT pg_temp.eq(pg_temp.ids(pg_temp.hist('c1000000-0000-4000-8000-000000000007')),
  ARRAY['e0000000-0000-4000-8000-000000000702', 'e0000000-0000-4000-8000-000000000701'], 'tied timestamps: order 1 before order 2');
SELECT pg_temp.eq((SELECT array_agg((e ->> 'voice_event_order')::int ORDER BY ord) FROM jsonb_array_elements(pg_temp.hist('c1000000-0000-4000-8000-000000000007')) WITH ORDINALITY t(e, ord)), ARRAY[1, 2], 'voice_event_order is returned');
SELECT pg_temp.eq((SELECT bool_and(e ->> 'voice_call_id' = 'ca110000-0000-4000-8000-000000000071') FROM jsonb_array_elements(pg_temp.hist('c1000000-0000-4000-8000-000000000007')) e), true, 'voice_call_id is returned');
RESET ROLE;

-- (2) REVERSED clock + plain neighbours. order 1 at tT+1s, order 2 at tT (the later observation carries the
--     EARLIER timestamp). Plain turns at tT-60s, tT+0.5s (between the two timestamps) and tT+120s.
INSERT INTO public.messages (id, conversation_id, role, content, created_at) VALUES
  ('f0000000-0000-4000-8000-000000000810', 'c1000000-0000-4000-8000-000000000008', 'user', 'plain before', pg_temp.tm('p_before')),
  ('f0000000-0000-4000-8000-000000000811', 'c1000000-0000-4000-8000-000000000008', 'assistant', 'plain between the call timestamps', pg_temp.tm('tTmid')),
  ('f0000000-0000-4000-8000-000000000812', 'c1000000-0000-4000-8000-000000000008', 'user', 'plain after', pg_temp.tm('p_after'));
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000b','c1000000-0000-4000-8000-000000000008','e0000000-0000-4000-8000-000000000801','ca110000-0000-4000-8000-000000000081',1,'user','first observation, LATER timestamp',pg_temp.tm('tT1')) ->> 'ok', 'true', 'reversed: order 1 (tT+1s)');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000b','c1000000-0000-4000-8000-000000000008','e0000000-0000-4000-8000-000000000802','ca110000-0000-4000-8000-000000000081',2,'assistant','second observation, EARLIER timestamp',pg_temp.tm('tT')) ->> 'ok', 'true', 'reversed: order 2 (tT)');
RESET ROLE;
SELECT pg_temp.eq((SELECT array_agg(id::text ORDER BY created_at, id) FROM public.messages WHERE conversation_id = 'c1000000-0000-4000-8000-000000000008'),
  ARRAY['f0000000-0000-4000-8000-000000000810', 'e0000000-0000-4000-8000-000000000802', 'f0000000-0000-4000-8000-000000000811', 'e0000000-0000-4000-8000-000000000801', 'f0000000-0000-4000-8000-000000000812'],
  'the fixture discriminates: raw created_at order inverts the call');
SELECT pg_temp.as_service();
-- the whole call sits at its MINIMUM timestamp (tT), so it precedes the plain turn at tT+0.5s even though order 1 is later than that
SELECT pg_temp.eq(pg_temp.ids(pg_temp.hist('c1000000-0000-4000-8000-000000000008')),
  ARRAY['f0000000-0000-4000-8000-000000000810', 'e0000000-0000-4000-8000-000000000801', 'e0000000-0000-4000-8000-000000000802', 'f0000000-0000-4000-8000-000000000811', 'f0000000-0000-4000-8000-000000000812'],
  'reversed clock: the call is one group at its minimum time, ordered by voice_event_order; plain turns keep chronology');
-- the limit applies AFTER that ordering (last N of it), not to raw created_at
SELECT pg_temp.eq(pg_temp.ids(pg_temp.hist('c1000000-0000-4000-8000-000000000008', 3)),
  ARRAY['e0000000-0000-4000-8000-000000000802', 'f0000000-0000-4000-8000-000000000811', 'f0000000-0000-4000-8000-000000000812'], 'limit 3 is the last 3 of the stable order');
SELECT pg_temp.eq(pg_temp.ids(pg_temp.hist('c1000000-0000-4000-8000-000000000008', 1)), ARRAY['f0000000-0000-4000-8000-000000000812'], 'limit 1');
SELECT pg_temp.eq(jsonb_array_length(pg_temp.hist('c1000000-0000-4000-8000-000000000008', 0)), 1, 'limit 0 is clamped to 1 (unchanged clamp)');
SELECT pg_temp.eq(jsonb_array_length(pg_temp.hist('c1000000-0000-4000-8000-000000000008', 1000)), 5, 'a large limit returns everything (clamped at 40)');
-- delayed arrival does not matter: the same call stored in the opposite arrival order reads the same (checked on CA7 above)
RESET ROLE;

-- (3) Two calls with the SAME group time, a plain turn at that very instant, and cross-conversation isolation.
INSERT INTO public.messages (id, conversation_id, role, content, created_at) VALUES
  ('f0000000-0000-4000-8000-000000000990', 'c1000000-0000-4000-8000-000000000009', 'user', 'plain at the same instant', pg_temp.tm('tT'));
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000c','c1000000-0000-4000-8000-000000000009','e0000000-0000-4000-8000-000000000922','ca110000-0000-4000-8000-000000000092',2,'assistant','K92 second',pg_temp.tm('tT')) ->> 'ok', 'true', 'K92/2');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000c','c1000000-0000-4000-8000-000000000009','e0000000-0000-4000-8000-000000000912','ca110000-0000-4000-8000-000000000091',2,'assistant','K91 second',pg_temp.tm('tT')) ->> 'ok', 'true', 'K91/2');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000c','c1000000-0000-4000-8000-000000000009','e0000000-0000-4000-8000-000000000921','ca110000-0000-4000-8000-000000000092',1,'user','K92 first',pg_temp.tm('tT')) ->> 'ok', 'true', 'K92/1');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-00000000000c','c1000000-0000-4000-8000-000000000009','e0000000-0000-4000-8000-000000000911','ca110000-0000-4000-8000-000000000091',1,'user','K91 first',pg_temp.tm('tT')) ->> 'ok', 'true', 'K91/1');
RESET ROLE;
CREATE TEMP TABLE tx_h9 AS SELECT pg_temp.hist('c1000000-0000-4000-8000-000000000009') AS before_b;
GRANT SELECT ON tx_h9 TO PUBLIC;
SELECT pg_temp.as_service();
SELECT pg_temp.eq(pg_temp.ids(pg_temp.hist('c1000000-0000-4000-8000-000000000009')) = pg_temp.ids((SELECT before_b FROM tx_h9)), true, 'deterministic: a second read is identical');
-- each call is contiguous (a group) and numerically ordered inside
SELECT pg_temp.eq((SELECT array_agg(e ->> 'voice_call_id' || ':' || (e ->> 'voice_event_order') ORDER BY ord) FROM jsonb_array_elements(pg_temp.hist('c1000000-0000-4000-8000-000000000009')) WITH ORDINALITY t(e, ord) WHERE e ? 'voice_call_id'),
  CASE WHEN 'ca110000-0000-4000-8000-000000000091'::uuid < 'ca110000-0000-4000-8000-000000000092'::uuid
       THEN ARRAY['ca110000-0000-4000-8000-000000000091:1', 'ca110000-0000-4000-8000-000000000091:2', 'ca110000-0000-4000-8000-000000000092:1', 'ca110000-0000-4000-8000-000000000092:2']
       ELSE ARRAY['ca110000-0000-4000-8000-000000000092:1', 'ca110000-0000-4000-8000-000000000092:2', 'ca110000-0000-4000-8000-000000000091:1', 'ca110000-0000-4000-8000-000000000091:2'] END,
  'two calls at one instant: whole groups, ties broken by the call id, numeric order inside each');
SELECT pg_temp.eq(jsonb_array_length(pg_temp.hist('c1000000-0000-4000-8000-000000000009')), 5, 'the plain turn at the same instant is also present exactly once');
RESET ROLE;
-- Another ACCOUNT uses the same call id with an EARLIER timestamp in its own conversation: A's grouping must not move.
SELECT pg_temp.as_user('bbbbbbbb-0000-4000-8000-000000000002');
SELECT pg_temp.eq(pg_temp.ap('bbbbbbbb-0000-4000-8000-000000000002','5b000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000009b1','ca110000-0000-4000-8000-000000000091',1,'user','B shares the call id, an hour earlier',pg_temp.tm('b_early')) ->> 'ok', 'true', 'B stores a turn under the same call id');
RESET ROLE;
SELECT pg_temp.as_service();
SELECT pg_temp.eq(pg_temp.ids(pg_temp.hist('c1000000-0000-4000-8000-000000000009')), pg_temp.ids((SELECT before_b FROM tx_h9)), 'a call id reused by another account does not move A''s group (the minimum is per owned conversation)');
SELECT pg_temp.eq(public.support_context_sources('bbbbbbbb-0000-4000-8000-000000000002', 'c1000000-0000-4000-8000-000000000009', 20, false), jsonb_build_object('ok', false, 'code', 'NOT_FOUND'), 'B cannot read A''s conversation history (unchanged NOT_FOUND)');
SELECT pg_temp.eq(jsonb_array_length(public.support_context_sources('bbbbbbbb-0000-4000-8000-000000000002', 'c2000000-0000-4000-8000-000000000001', 20, false) -> 'history') >= 1, true, 'B reads its own history');
RESET ROLE;

-- (4) PLAIN-ONLY control: the reader behaves exactly like the original (created_at, id) rule, entries unchanged.
INSERT INTO public.messages (id, conversation_id, role, content, created_at) VALUES
  ('f0000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-00000000000a', 'user', 'a1', pg_temp.tm('a1')),
  ('f0000000-0000-4000-8000-0000000000a2', 'c1000000-0000-4000-8000-00000000000a', 'assistant', 'a2', pg_temp.tm('a2')),
  ('f0000000-0000-4000-8000-0000000000a4', 'c1000000-0000-4000-8000-00000000000a', 'assistant', 'a4 ties a3, larger id', pg_temp.tm('a3')),
  ('f0000000-0000-4000-8000-0000000000a3', 'c1000000-0000-4000-8000-00000000000a', 'user', 'a3', pg_temp.tm('a3')),
  ('f0000000-0000-4000-8000-0000000000a5', 'c1000000-0000-4000-8000-00000000000a', 'user', 'a5', pg_temp.tm('a5')),
  ('f0000000-0000-4000-8000-0000000000a6', 'c1000000-0000-4000-8000-00000000000a', 'assistant', 'a6', pg_temp.tm('tT')),
  ('f0000000-0000-4000-8000-0000000000a7', 'c1000000-0000-4000-8000-00000000000a', 'user', 'system role is not history', pg_temp.tm('tT')),
  ('f0000000-0000-4000-8000-0000000000a8', 'c1000000-0000-4000-8000-00000000000a', 'user', 'suppressed message', pg_temp.tm('tT')),
  ('f0000000-0000-4000-8000-0000000000a9', 'c1000000-0000-4000-8000-00000000000a', 'assistant', 'interface fallback is not history', pg_temp.tm('tT'));
UPDATE public.messages SET role = 'system' WHERE id = 'f0000000-0000-4000-8000-0000000000a7';
UPDATE public.messages SET content_origin = 'interface_fallback' WHERE id = 'f0000000-0000-4000-8000-0000000000a9';
INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason) VALUES ('aaaaaaaa-0000-4000-8000-000000000001', 'message', 'f0000000-0000-4000-8000-0000000000a8', 'user_source_exclusion');
SELECT pg_temp.as_service();
SELECT pg_temp.eq(pg_temp.ids(pg_temp.hist('c1000000-0000-4000-8000-00000000000a')),
  (SELECT array_agg(id::text ORDER BY created_at, id) FROM (SELECT id, created_at FROM public.messages WHERE conversation_id = 'c1000000-0000-4000-8000-00000000000a'
     AND id NOT IN ('f0000000-0000-4000-8000-0000000000a7', 'f0000000-0000-4000-8000-0000000000a8', 'f0000000-0000-4000-8000-0000000000a9')) o),
  'plain-only: identical to the original (created_at, id) rule, with role/origin/suppression filters unchanged');
SELECT pg_temp.eq(pg_temp.ids(pg_temp.hist('c1000000-0000-4000-8000-00000000000a', 3)),
  (SELECT array_agg(id::text ORDER BY created_at, id) FROM (SELECT id, created_at FROM public.messages WHERE conversation_id = 'c1000000-0000-4000-8000-00000000000a'
     AND id NOT IN ('f0000000-0000-4000-8000-0000000000a7', 'f0000000-0000-4000-8000-0000000000a8', 'f0000000-0000-4000-8000-0000000000a9')
     ORDER BY created_at DESC, id DESC LIMIT 3) o), 'plain-only: the limit takes the same last N as before');
SELECT pg_temp.eq((SELECT bool_and(NOT (e ? 'voice_call_id') AND NOT (e ? 'voice_event_order')) FROM jsonb_array_elements(pg_temp.hist('c1000000-0000-4000-8000-00000000000a')) e), true, 'plain entries carry no voice keys (safe for old clients)');
SELECT pg_temp.eq((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys((pg_temp.hist('c1000000-0000-4000-8000-00000000000a') -> 0)) AS k),
  ARRAY['content', 'content_revision', 'created_at', 'id', 'role'], 'plain entry shape is exactly the original');
-- Everything else about the reader is untouched.
SELECT pg_temp.eq((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(public.support_context_sources('aaaaaaaa-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-00000000000a', 20, true)) AS k),
  ARRAY['conversation_suppressed', 'daily_intent', 'history', 'memories', 'ok', 'privacy_revision'], 'top-level shape unchanged');
SELECT pg_temp.eq(public.support_context_sources('aaaaaaaa-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-00000000000a', 20, false) -> 'memories', '[]'::jsonb, 'conversation-only reads no memory (unchanged)');
RESET ROLE;
INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason) VALUES ('aaaaaaaa-0000-4000-8000-000000000001', 'conversation', 'c1000000-0000-4000-8000-00000000000a', 'user_source_exclusion');
SELECT pg_temp.as_service();
SELECT pg_temp.eq(public.support_context_sources('aaaaaaaa-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-00000000000a', 20, false) -> 'history', '[]'::jsonb, 'a suppressed conversation still yields no history');
SELECT pg_temp.eq(public.support_context_sources('aaaaaaaa-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-00000000000a', 20, false) ->> 'conversation_suppressed', 'true', 'and says so');
RESET ROLE;
DELETE FROM public.support_suppressions WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001' AND ref_id = 'c1000000-0000-4000-8000-00000000000a';

-- Security properties and the installed definition.
SELECT pg_temp.eq((SELECT prosecdef AND provolatile = 's' AND proconfig = ARRAY['search_path=pg_catalog, public, pg_temp'] FROM pg_proc WHERE oid = 'public.support_context_sources(uuid,uuid,integer,boolean)'::regprocedure), true, 'still STABLE SECURITY DEFINER with the audited search_path');
SELECT pg_temp.eq(has_function_privilege('service_role', 'public.support_context_sources(uuid,uuid,integer,boolean)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'public.support_context_sources(uuid,uuid,integer,boolean)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'public.support_context_sources(uuid,uuid,integer,boolean)', 'EXECUTE'), true, 'original grants unchanged: service_role only');
SELECT pg_temp.eq((SELECT encode(sha256(convert_to(prosrc, 'UTF8')), 'hex') FROM pg_proc WHERE oid = 'public.support_context_sources(uuid,uuid,integer,boolean)'::regprocedure),
  '61f1b3223130e8de5095323543f3bdfa8c4a3b6fe104796bab0482965787d575', 'the installed definition is exactly the reviewed one (sha256 of prosrc)');

-- ===================== UI DIRECT READER: support_get_conversation_messages =====================
-- The app pages history with this RPC; it must agree with the AI context reader on order. Same key, no
-- role/origin/suppression filter (what the person can see is not what the model may use), invoker rights.
INSERT INTO public.conversations (id, user_id) VALUES ('c1000000-0000-4000-8000-00000000000c', 'aaaaaaaa-0000-4000-8000-000000000001');   -- CA12: empty
CREATE OR REPLACE FUNCTION pg_temp.errstate(stmt text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE stmt;
  RETURN 'OK';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLSTATE || ':' || SQLERRM;
END $$;
CREATE OR REPLACE FUNCTION pg_temp.ui(p_conv uuid, p_limit int DEFAULT 50) RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.support_get_conversation_messages('aaaaaaaa-0000-4000-8000-000000000001'::uuid, p_conv, p_limit) $$;

-- attributes and grants
SELECT pg_temp.eq(has_function_privilege('authenticated', 'public.support_get_conversation_messages(uuid,uuid,integer)', 'EXECUTE'), true, 'authenticated can execute');
SELECT pg_temp.eq(has_function_privilege('anon', 'public.support_get_conversation_messages(uuid,uuid,integer)', 'EXECUTE')
  OR has_function_privilege('service_role', 'public.support_get_conversation_messages(uuid,uuid,integer)', 'EXECUTE'), false, 'authenticated only');
SELECT pg_temp.eq((SELECT NOT prosecdef AND provolatile = 's' AND proconfig = ARRAY['search_path=pg_catalog, public, pg_temp'] FROM pg_proc WHERE oid = 'public.support_get_conversation_messages(uuid,uuid,integer)'::regprocedure), true, 'SECURITY INVOKER, STABLE, fixed search_path');
SELECT pg_temp.eq(pg_get_function_arguments('public.support_get_conversation_messages(uuid,uuid,integer)'::regprocedure), 'p_expected_owner uuid, p_conversation_id uuid, p_limit integer DEFAULT 50', 'exact signature and default limit');
-- the ordering expression is textually the same one the AI context reader uses
SELECT pg_temp.eq(
  regexp_replace(regexp_replace((SELECT substring(prosrc from 'coalesce\(\(SELECT min\(c\.created_at\).*?AS in_group') FROM pg_proc WHERE oid = 'public.support_get_conversation_messages(uuid,uuid,integer)'::regprocedure), 'p_conversation_id', 'p_conversation', 'g'), '\s+', ' ', 'g'),
  regexp_replace((SELECT substring(prosrc from 'coalesce\(\(SELECT min\(c\.created_at\).*?AS in_group') FROM pg_proc WHERE oid = 'public.support_context_sources(uuid,uuid,integer,boolean)'::regprocedure), '\s+', ' ', 'g'),
  'the call-anchor key expression is identical after whitespace normalization in the UI reader and the context reader');
SELECT pg_temp.eq(
  (SELECT substring(prosrc from 'ORDER BY group_at DESC, group_key DESC, in_group DESC, ms\.id DESC') || substring(prosrc from 'ORDER BY h\.group_at, h\.group_key, h\.in_group, h\.id') FROM pg_proc WHERE oid = 'public.support_get_conversation_messages(uuid,uuid,integer)'::regprocedure),
  (SELECT substring(prosrc from 'ORDER BY group_at DESC, group_key DESC, in_group DESC, ms\.id DESC') || substring(prosrc from 'ORDER BY h\.group_at, h\.group_key, h\.in_group, h\.id') FROM pg_proc WHERE oid = 'public.support_context_sources(uuid,uuid,integer,boolean)'::regprocedure),
  'and so are both ORDER BY clauses');

-- access control, exact SQLSTATEs (PostgREST maps 42501 -> 401/403, 22023 -> 400, PT404 -> 404)
SELECT pg_temp.as_anon();
SELECT pg_temp.eq(pg_temp.errstate($q$SELECT pg_temp.ui('c1000000-0000-4000-8000-000000000007')$q$) LIKE '42501:%permission denied%', true, 'anon: permission denied');
SELECT pg_temp.as_nobody();
SELECT pg_temp.eq(pg_temp.errstate($q$SELECT pg_temp.ui('c1000000-0000-4000-8000-000000000007')$q$), '42501:AUTH_REQUIRED', 'no subject: AUTH_REQUIRED');
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.errstate($q$SELECT public.support_get_conversation_messages('bbbbbbbb-0000-4000-8000-000000000002', 'c1000000-0000-4000-8000-000000000007', 20)$q$), '42501:OWNER_MISMATCH', 'a captured owner that is not auth.uid()');
SELECT pg_temp.eq(pg_temp.errstate($q$SELECT public.support_get_conversation_messages(NULL, 'c1000000-0000-4000-8000-000000000007', 20)$q$), '42501:OWNER_MISMATCH', 'missing owner');
SELECT pg_temp.eq(pg_temp.errstate($q$SELECT pg_temp.ui('c2000000-0000-4000-8000-000000000001')$q$), 'PT404:NOT_FOUND', 'a foreign conversation');
SELECT pg_temp.eq(pg_temp.errstate($q$SELECT pg_temp.ui('c9999999-0000-4000-8000-000000000999')$q$), 'PT404:NOT_FOUND', 'a nonexistent conversation answers identically (no existence leak)');
SELECT pg_temp.eq(pg_temp.errstate($q$SELECT public.support_get_conversation_messages('aaaaaaaa-0000-4000-8000-000000000001', NULL, 20)$q$), '22023:INVALID_PAYLOAD', 'NULL conversation id');
SELECT pg_temp.eq(pg_temp.errstate($q$SELECT pg_temp.ui('c1000000-0000-4000-8000-000000000007', 0)$q$), '22023:INVALID_PAYLOAD', 'limit 0');
SELECT pg_temp.eq(pg_temp.errstate($q$SELECT pg_temp.ui('c1000000-0000-4000-8000-000000000007', 101)$q$), '22023:INVALID_PAYLOAD', 'limit 101');
SELECT pg_temp.eq(pg_temp.errstate($q$SELECT pg_temp.ui('c1000000-0000-4000-8000-000000000007', -1)$q$), '22023:INVALID_PAYLOAD', 'limit -1');
SELECT pg_temp.eq(pg_temp.errstate($q$SELECT public.support_get_conversation_messages('aaaaaaaa-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000007', NULL)$q$), '22023:INVALID_PAYLOAD', 'explicit NULL limit');
SELECT pg_temp.eq(jsonb_typeof(pg_temp.ui('c1000000-0000-4000-8000-000000000007', 1)) || jsonb_typeof(pg_temp.ui('c1000000-0000-4000-8000-000000000007', 100)), 'arrayarray', 'limits 1 and 100 are accepted; the result is a bare JSON array');
SELECT pg_temp.eq(jsonb_typeof(public.support_get_conversation_messages('aaaaaaaa-0000-4000-8000-000000000001', 'c1000000-0000-4000-8000-000000000007')), 'array', 'the limit defaults');
SELECT pg_temp.eq(pg_temp.ui('c1000000-0000-4000-8000-00000000000c'), '[]'::jsonb, 'an empty conversation is an empty array');
RESET ROLE;

-- UI order == AI order for tied, reversed and multi-call conversations, at every limit (snapshot the AI side as owner)
CREATE TEMP TABLE tx_ui(k text PRIMARY KEY, ids text[]);
GRANT ALL ON tx_ui TO PUBLIC;
INSERT INTO tx_ui
  SELECT 'ctx|' || c || '|' || n, pg_temp.ids(pg_temp.hist(c::uuid, n))
  FROM unnest(ARRAY['c1000000-0000-4000-8000-000000000007', 'c1000000-0000-4000-8000-000000000008', 'c1000000-0000-4000-8000-000000000009']) c, generate_series(1, 6) n;
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq((SELECT count(*) FROM tx_ui WHERE k LIKE 'ctx|%')::int, 18, 'the comparison is not vacuous: 3 conversations x 6 limits');
SELECT pg_temp.eq((SELECT count(*) FROM tx_ui t WHERE t.k LIKE 'ctx|%'
    AND pg_temp.ids(pg_temp.ui(split_part(t.k, '|', 2)::uuid, split_part(t.k, '|', 3)::int)) IS DISTINCT FROM t.ids)::int, 0, 'UI and AI return the same sequence for tied (CA7), reversed+plain (CA8) and two-call (CA9) conversations at every limit');
-- and the absolute expectations, so agreement cannot be agreement on a wrong order
SELECT pg_temp.eq(pg_temp.ids(pg_temp.ui('c1000000-0000-4000-8000-000000000007')), ARRAY['e0000000-0000-4000-8000-000000000702', 'e0000000-0000-4000-8000-000000000701'], 'tied timestamps, delayed arrival: order 1 then order 2');
SELECT pg_temp.eq(pg_temp.ids(pg_temp.ui('c1000000-0000-4000-8000-000000000008')),
  ARRAY['f0000000-0000-4000-8000-000000000810', 'e0000000-0000-4000-8000-000000000801', 'e0000000-0000-4000-8000-000000000802', 'f0000000-0000-4000-8000-000000000811', 'f0000000-0000-4000-8000-000000000812'], 'reversed clock: one group at its minimum time, provider order inside, plain turns chronological');
SELECT pg_temp.eq(pg_temp.ids(pg_temp.ui('c1000000-0000-4000-8000-000000000008', 3)),
  ARRAY['e0000000-0000-4000-8000-000000000802', 'f0000000-0000-4000-8000-000000000811', 'f0000000-0000-4000-8000-000000000812'], 'the LATEST 3 of that order, oldest first (not the newest 3 by raw created_at)');
-- exact row shape, preserved timestamps, voice metadata, conversation id
SELECT pg_temp.eq((SELECT bool_and((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e) AS k)
      = ARRAY['content', 'content_origin', 'conversation_id', 'created_at', 'id', 'role', 'voice_call_id', 'voice_event_order']) FROM jsonb_array_elements(pg_temp.ui('c1000000-0000-4000-8000-000000000008')) e), true, 'every row has exactly the eight documented keys');
SELECT pg_temp.eq((SELECT bool_and((e ->> 'created_at')::timestamptz = (SELECT m.created_at FROM public.messages m WHERE m.id = (e ->> 'id')::uuid)
        AND (e ->> 'conversation_id')::uuid = 'c1000000-0000-4000-8000-000000000008') FROM jsonb_array_elements(pg_temp.ui('c1000000-0000-4000-8000-000000000008')) e), true, 'created_at is the stored value, never rewritten; conversation_id is the requested one');
SELECT pg_temp.eq((SELECT (e ->> 'created_at')::timestamptz FROM jsonb_array_elements(pg_temp.ui('c1000000-0000-4000-8000-000000000008')) e WHERE e ->> 'id' = 'e0000000-0000-4000-8000-000000000802'), pg_temp.tm('tT'), 'the reversed event keeps ITS actual (earlier) timestamp while sorting after order 1');
SELECT pg_temp.eq((SELECT array_agg((e ->> 'voice_event_order') ORDER BY ord) FROM jsonb_array_elements(pg_temp.ui('c1000000-0000-4000-8000-000000000008')) WITH ORDINALITY t(e, ord) WHERE jsonb_typeof(e -> 'voice_call_id') = 'string'), ARRAY['1', '2'], 'voice rows carry call id and provider order');
SELECT pg_temp.eq((SELECT bool_and(jsonb_typeof(e -> 'voice_call_id') = 'null' AND jsonb_typeof(e -> 'voice_event_order') = 'null') FROM jsonb_array_elements(pg_temp.ui('c1000000-0000-4000-8000-00000000000a')) e), true, 'plain rows carry explicit nulls for the voice keys');
SELECT pg_temp.eq(pg_temp.ids(pg_temp.ui('c1000000-0000-4000-8000-000000000009')) = pg_temp.ids(pg_temp.ui('c1000000-0000-4000-8000-000000000009')), true, 'deterministic');
-- Unfiltered visible history: system role, fallback origin and a suppressed message are all shown (the AI reader excludes them)
SELECT pg_temp.eq(jsonb_array_length(pg_temp.ui('c1000000-0000-4000-8000-00000000000a')), 9, 'CA10: every canonical row is visible');
SELECT pg_temp.eq(pg_temp.ids(pg_temp.ui('c1000000-0000-4000-8000-00000000000a')),
  (SELECT array_agg(id::text ORDER BY created_at, id) FROM public.messages WHERE conversation_id = 'c1000000-0000-4000-8000-00000000000a'), 'plain-only: exactly (created_at, id) over ALL rows');
SELECT pg_temp.eq((SELECT e ->> 'content_origin' FROM jsonb_array_elements(pg_temp.ui('c1000000-0000-4000-8000-00000000000a')) e WHERE e ->> 'id' = 'f0000000-0000-4000-8000-0000000000a9'), 'interface_fallback', 'content_origin is returned');
SELECT pg_temp.eq((SELECT e ->> 'role' FROM jsonb_array_elements(pg_temp.ui('c1000000-0000-4000-8000-00000000000a')) e WHERE e ->> 'id' = 'f0000000-0000-4000-8000-0000000000a7'), 'system', 'role is returned as text');
SELECT pg_temp.eq(pg_temp.ids(pg_temp.ui('c1000000-0000-4000-8000-00000000000a', 1)), (SELECT ids[array_length(ids, 1):array_length(ids, 1)] FROM (SELECT pg_temp.ids(pg_temp.ui('c1000000-0000-4000-8000-00000000000a')) AS ids) x), 'limit 1 is the newest row of the same order');
RESET ROLE;
-- A suppressed CONVERSATION changes what the model may use, not what the person can see.
INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason) VALUES ('aaaaaaaa-0000-4000-8000-000000000001', 'conversation', 'c1000000-0000-4000-8000-00000000000a', 'user_source_exclusion');
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(jsonb_array_length(pg_temp.ui('c1000000-0000-4000-8000-00000000000a')), 9, 'a suppressed conversation is still visible to its owner');
RESET ROLE;
SELECT pg_temp.as_service();
SELECT pg_temp.eq(pg_temp.hist('c1000000-0000-4000-8000-00000000000a'), '[]'::jsonb, 'while the AI context reader returns nothing for it');
RESET ROLE;
DELETE FROM public.support_suppressions WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001' AND ref_id = 'c1000000-0000-4000-8000-00000000000a';
-- Accounts are isolated in both directions.
SELECT pg_temp.as_user('bbbbbbbb-0000-4000-8000-000000000002');
SELECT pg_temp.eq(pg_temp.errstate($q$SELECT public.support_get_conversation_messages('bbbbbbbb-0000-4000-8000-000000000002', 'c1000000-0000-4000-8000-000000000009', 20)$q$), 'PT404:NOT_FOUND', 'B cannot read A''s conversation');
SELECT pg_temp.eq((SELECT bool_and((e ->> 'conversation_id')::uuid = 'c2000000-0000-4000-8000-000000000001') AND count(*) >= 1 FROM jsonb_array_elements(public.support_get_conversation_messages('bbbbbbbb-0000-4000-8000-000000000002', 'c2000000-0000-4000-8000-000000000001', 20)) e), true, 'B reads only its own rows');
SELECT pg_temp.eq((SELECT count(*) FROM jsonb_array_elements(public.support_get_conversation_messages('bbbbbbbb-0000-4000-8000-000000000002', 'c2000000-0000-4000-8000-000000000001', 20)) e WHERE e ->> 'voice_call_id' = 'ca110000-0000-4000-8000-000000000091')::int, 1, 'B''s turn that reuses A''s call id sits in B''s own history, ordered on its own');
RESET ROLE;
-- No side effects: the reader neither wrote nor locked anything.
SELECT pg_temp.eq(pg_temp.mutex_held(), false, 'the direct reader never takes the write mutex');

-- ===================== (call, order) uniqueness and call/conversation consistency =====================
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000006','c1000000-0000-4000-8000-000000000006','e0000000-0000-4000-8000-000000000073','ca110000-0000-4000-8000-000000000070',2,'assistant','a DIFFERENT event for an observed (call, order)',pg_temp.tm('t3')) ->> 'code', 'OPERATION_ID_REUSED', 'one event per (call, order)');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-000000000074','ca110000-0000-4000-8000-000000000070',3,'user','the call lives in another conversation',pg_temp.tm('t4')) ->> 'code', 'INVALID_PAYLOAD', 'one call belongs to one conversation');
RESET ROLE;

-- ===================== BOUNDS =====================
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
CREATE TEMP TABLE tx_b(label text, got text, want text);
GRANT ALL ON tx_b TO PUBLIC;
INSERT INTO tx_b SELECT 'text 20000 chars ok', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000c1','ca110000-0000-4000-8000-0000000000c1',1,'user',repeat('x',20000),pg_temp.tm('t1')) ->> 'ok', 'true';
INSERT INTO tx_b SELECT 'text 20000 CODE POINTS (4-byte) ok', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000c2','ca110000-0000-4000-8000-0000000000c1',2,'user',repeat(chr(128512),20000),pg_temp.tm('t1')) ->> 'ok', 'true';
INSERT INTO tx_b SELECT 'text 20001 refused', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000c3','ca110000-0000-4000-8000-0000000000c1',3,'user',repeat('x',20001),pg_temp.tm('t1')) ->> 'code', 'INVALID_PAYLOAD';
INSERT INTO tx_b SELECT 'blank text refused', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000c4','ca110000-0000-4000-8000-0000000000c1',4,'user','  ' || chr(10) || ' ',pg_temp.tm('t1')) ->> 'code', 'INVALID_PAYLOAD';
INSERT INTO tx_b SELECT 'NULL text refused', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000c5','ca110000-0000-4000-8000-0000000000c1',5,'user',NULL,pg_temp.tm('t1')) ->> 'code', 'INVALID_PAYLOAD';
INSERT INTO tx_b SELECT 'order 0 refused', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000c6','ca110000-0000-4000-8000-0000000000c1',0,'user','x',pg_temp.tm('t1')) ->> 'code', 'INVALID_PAYLOAD';
INSERT INTO tx_b SELECT 'order -1 refused', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000c7','ca110000-0000-4000-8000-0000000000c1',-1,'user','x',pg_temp.tm('t1')) ->> 'code', 'INVALID_PAYLOAD';
INSERT INTO tx_b SELECT 'order 2^53 refused', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000c8','ca110000-0000-4000-8000-0000000000c1',9007199254740992,'user','x',pg_temp.tm('t1')) ->> 'code', 'INVALID_PAYLOAD';
INSERT INTO tx_b SELECT 'order 2^53-1 ok', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000c9','ca110000-0000-4000-8000-0000000000c1',9007199254740991,'user','x',pg_temp.tm('t1')) ->> 'ok', 'true';
INSERT INTO tx_b SELECT 'role system refused', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000ca','ca110000-0000-4000-8000-0000000000c1',6,'system','x',pg_temp.tm('t1')) ->> 'code', 'INVALID_PAYLOAD';
INSERT INTO tx_b SELECT 'role case-sensitive', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000cb','ca110000-0000-4000-8000-0000000000c1',7,'User','x',pg_temp.tm('t1')) ->> 'code', 'INVALID_PAYLOAD';
INSERT INTO tx_b SELECT 'nil event id refused', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','ca110000-0000-4000-8000-0000000000c1',8,'user','x',pg_temp.tm('t1')) ->> 'code', 'INVALID_PAYLOAD';
INSERT INTO tx_b SELECT 'nil call id refused', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000cc','00000000-0000-0000-0000-000000000000',8,'user','x',pg_temp.tm('t1')) ->> 'code', 'INVALID_PAYLOAD';
INSERT INTO tx_b SELECT 'NULL call id refused', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000cd',NULL,8,'user','x',pg_temp.tm('t1')) ->> 'code', 'INVALID_PAYLOAD';
INSERT INTO tx_b SELECT 'provider id 256 ok', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000ce','ca110000-0000-4000-8000-0000000000c2',1,'user','x',pg_temp.tm('t1'),repeat('i',256),repeat('e',256)) ->> 'ok', 'true';
INSERT INTO tx_b SELECT 'provider item 257 refused', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000cf','ca110000-0000-4000-8000-0000000000c2',2,'user','x',pg_temp.tm('t1'),repeat('i',257),NULL) ->> 'code', 'INVALID_PAYLOAD';
INSERT INTO tx_b SELECT 'provider event 257 refused', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000d0','ca110000-0000-4000-8000-0000000000c2',2,'user','x',pg_temp.tm('t1'),NULL,repeat('e',257)) ->> 'code', 'INVALID_PAYLOAD';
INSERT INTO tx_b SELECT 'empty provider id refused (not coerced)', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000d1','ca110000-0000-4000-8000-0000000000c2',2,'user','x',pg_temp.tm('t1'),'',NULL) ->> 'code', 'INVALID_PAYLOAD';
INSERT INTO tx_b SELECT 'NULL occurred_at refused', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000d2','ca110000-0000-4000-8000-0000000000c2',2,'user','x',NULL) ->> 'code', 'INVALID_PAYLOAD';
INSERT INTO tx_b SELECT 'occurred_at 1 hour ahead refused', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000d3','ca110000-0000-4000-8000-0000000000c2',2,'user','x',clock_timestamp() + interval '1 hour') ->> 'code', 'INVALID_PAYLOAD';
INSERT INTO tx_b SELECT 'occurred_at before 2020 refused', pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000d4','ca110000-0000-4000-8000-0000000000c2',2,'user','x',timestamptz '2019-12-31 00:00:00+00') ->> 'code', 'INVALID_PAYLOAD';
RESET ROLE;
SELECT pg_temp.eq((SELECT count(*) FROM tx_b WHERE got IS DISTINCT FROM want)::int, 0, 'every bound behaves as specified: ' || coalesce((SELECT string_agg(label || ' (' || coalesce(got, 'NULL') || ')', '; ') FROM tx_b WHERE got IS DISTINCT FROM want), 'all ok'));
SELECT pg_temp.eq((SELECT count(*) FROM public.messages WHERE id IN
  ('e0000000-0000-4000-8000-0000000000c3','e0000000-0000-4000-8000-0000000000c4','e0000000-0000-4000-8000-0000000000c5','e0000000-0000-4000-8000-0000000000c6',
   'e0000000-0000-4000-8000-0000000000c7','e0000000-0000-4000-8000-0000000000c8','e0000000-0000-4000-8000-0000000000ca','e0000000-0000-4000-8000-0000000000cb',
   'e0000000-0000-4000-8000-0000000000cc','e0000000-0000-4000-8000-0000000000cd','e0000000-0000-4000-8000-0000000000cf','e0000000-0000-4000-8000-0000000000d0',
   'e0000000-0000-4000-8000-0000000000d1','e0000000-0000-4000-8000-0000000000d2','e0000000-0000-4000-8000-0000000000d3','e0000000-0000-4000-8000-0000000000d4'))::int, 0, 'refused payloads stored nothing');

-- ===================== RESERVED FIELDS CANNOT BE FORGED; LEGACY INSERTS STAY COMPATIBLE =====================
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
-- A plain same-owner direct insert (the pre-existing path) still works.
INSERT INTO public.messages (id, conversation_id, role, content) VALUES ('f0000000-0000-4000-8000-0000000000e1', 'c1000000-0000-4000-8000-000000000001', 'user', 'legacy direct insert');
-- Claiming transcript provenance on a direct insert keeps the row but drops the claim.
INSERT INTO public.messages (id, conversation_id, role, content, voice_call_id, voice_event_order, voice_provider_item_id, voice_provider_event_id, voice_occurred_at, voice_source_session_id)
  VALUES ('f0000000-0000-4000-8000-0000000000e2', 'c1000000-0000-4000-8000-000000000001', 'user', 'forged provenance', 'ca110000-0000-4000-8000-0000000000ff', 99, 'forged_item', 'forged_evt', now(), '5a000000-0000-4000-8000-000000000001');
-- The transaction-local marker alone is not enough for an API role.
DO $$ BEGIN
  PERFORM set_config('support.transcript_rpc', 'on', true);
  INSERT INTO public.messages (id, conversation_id, role, content, voice_call_id, voice_event_order, voice_occurred_at, voice_source_session_id)
    VALUES ('f0000000-0000-4000-8000-0000000000e3', 'c1000000-0000-4000-8000-000000000001', 'user', 'forged with the marker', 'ca110000-0000-4000-8000-0000000000ff', 98, now(), '5a000000-0000-4000-8000-000000000001');
END $$;
-- Another account's conversation is still protected by the existing policy.
SELECT pg_temp.eq(pg_temp.err($q$INSERT INTO public.messages (conversation_id, role, content) VALUES ('c2000000-0000-4000-8000-000000000001', 'user', 'cross-owner direct insert')$q$) LIKE '%row-level security%', true, 'cross-owner direct insert is still refused');
-- No UPDATE policy exists for API roles: an attempt to rewrite provenance changes nothing.
UPDATE public.messages SET voice_call_id = NULL, voice_event_order = 5 WHERE id = 'e0000000-0000-4000-8000-000000000001';
RESET ROLE;
SELECT pg_temp.eq((SELECT voice_call_id IS NULL AND voice_event_order IS NULL AND voice_provider_item_id IS NULL AND voice_provider_event_id IS NULL AND voice_occurred_at IS NULL AND voice_source_session_id IS NULL FROM public.messages WHERE id = 'f0000000-0000-4000-8000-0000000000e1'), true, 'legacy insert: ordinary message');
SELECT pg_temp.eq((SELECT voice_call_id IS NULL AND voice_event_order IS NULL AND voice_provider_item_id IS NULL AND voice_provider_event_id IS NULL AND voice_occurred_at IS NULL AND voice_source_session_id IS NULL FROM public.messages WHERE id = 'f0000000-0000-4000-8000-0000000000e2'), true, 'forged provenance cleared, row kept');
SELECT pg_temp.eq((SELECT voice_call_id IS NULL AND voice_source_session_id IS NULL FROM public.messages WHERE id = 'f0000000-0000-4000-8000-0000000000e3'), true, 'the marker alone cannot authorize an API role');
SELECT pg_temp.eq((SELECT count(*) FROM public.messages WHERE id IN ('f0000000-0000-4000-8000-0000000000e1','f0000000-0000-4000-8000-0000000000e2','f0000000-0000-4000-8000-0000000000e3'))::int, 3, 'all three direct inserts were kept');
SELECT pg_temp.eq((SELECT voice_event_order FROM public.messages WHERE id = 'e0000000-0000-4000-8000-000000000001'), 1::bigint, 'RPC provenance not rewritable by an API role');
-- Even a non-RPC owner/service update cannot rewrite provenance; ordinary updates are unaffected.
UPDATE public.messages SET voice_call_id = 'ca110000-0000-4000-8000-0000000000aa', voice_event_order = 77, voice_source_session_id = '5a000000-0000-4000-8000-000000000007' WHERE id = 'e0000000-0000-4000-8000-000000000001';
SELECT pg_temp.eq((SELECT voice_call_id::text || '/' || voice_event_order::text || '/' || voice_source_session_id::text FROM public.messages WHERE id = 'e0000000-0000-4000-8000-000000000001'), 'ca110000-0000-4000-8000-000000000001/1/5a000000-0000-4000-8000-000000000001', 'provenance, including the source session, restored on a non-RPC update');
-- A transcript row cannot exist without its immutable source session (coherence CHECK), even for the owner role.
DO $$ BEGIN
  PERFORM set_config('support.transcript_rpc', 'on', true);
  BEGIN
    INSERT INTO public.messages (conversation_id, role, content, voice_call_id, voice_event_order, voice_occurred_at)
      VALUES ('c1000000-0000-4000-8000-000000000001', 'user', 'no source session', 'ca110000-0000-4000-8000-0000000000fe', 1, now());
    RAISE EXCEPTION 'FAIL a transcript row without voice_source_session_id was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
UPDATE public.messages SET content = 'edited by a legacy writer' WHERE id = 'f0000000-0000-4000-8000-0000000000e1';
SELECT pg_temp.eq((SELECT content_revision FROM public.messages WHERE id = 'f0000000-0000-4000-8000-0000000000e1'), 1::bigint, 'ordinary M3 message versioning is unaffected');

-- ===================== NO SIDE EFFECTS =====================
SELECT pg_temp.eq(pg_temp.mutex_held(), false, 'no lock leaks past the statement');
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
DO $$
DECLARE r jsonb; priv_before bigint; priv_after bigint; v_n int;
BEGIN
  SELECT privacy_revision INTO priv_before FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001';
  r := pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000f1','ca110000-0000-4000-8000-0000000000f1',1,'user','lock probe',pg_temp.tm('t1'));
  IF r ->> 'ok' <> 'true' THEN RAISE EXCEPTION 'FAIL probe append: %', r; END IF;
  IF NOT pg_temp.mutex_held() THEN RAISE EXCEPTION 'FAIL the M3 write mutex must be held (taken first) until commit'; END IF;
  SELECT privacy_revision INTO priv_after FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001';
  IF priv_before IS DISTINCT FROM priv_after THEN RAISE EXCEPTION 'FAIL an append must not move the privacy revision'; END IF;
END $$;
RESET ROLE;
SELECT pg_temp.eq(pg_temp.mutex_held(), false, 'the mutex is released with the transaction');
-- No AI / budget / voice-minute / XP table is touched by the RPC (counts only where the tables exist).
DO $$
DECLARE t text; n_before bigint; BEGIN
  FOREACH t IN ARRAY ARRAY['monthly_ai_budget_receipts', 'voice_relay_reservations', 'voice_sessions', 'voice_usage'] LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n_before;
      PERFORM set_config('tx.cnt_' || t, n_before::text, false);
    END IF;
  END LOOP;
END $$;
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','e0000000-0000-4000-8000-0000000000f2','ca110000-0000-4000-8000-0000000000f1',2,'assistant','no side effects',pg_temp.tm('t2')) ->> 'ok', 'true', 'append');
RESET ROLE;
DO $$
DECLARE t text; n_after bigint; BEGIN
  FOREACH t IN ARRAY ARRAY['monthly_ai_budget_receipts', 'voice_relay_reservations', 'voice_sessions', 'voice_usage'] LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('SELECT count(*) FROM public.%I', t) INTO n_after;
      IF n_after::text IS DISTINCT FROM current_setting('tx.cnt_' || t, true) THEN RAISE EXCEPTION 'FAIL append changed %', t; END IF;
    END IF;
  END LOOP;
END $$;

-- ===================== CASCADE: existing deletion semantics, nothing extra =====================
-- Deleting a conversation removes exactly its own messages (FK cascade); other conversations'
-- transcript turns and A's other records are untouched. (Account deletion cascades the same way
-- through conversations; not exercised here to keep the fixture reusable.)
CREATE TEMP TABLE tx_c AS SELECT
  (SELECT count(*) FROM public.messages WHERE conversation_id = 'c1000000-0000-4000-8000-000000000006') AS in_c6,
  (SELECT count(*) FROM public.messages WHERE conversation_id <> 'c1000000-0000-4000-8000-000000000006') AS elsewhere;
DELETE FROM public.conversations WHERE id = 'c1000000-0000-4000-8000-000000000006';
SELECT pg_temp.eq((SELECT count(*) FROM public.messages WHERE conversation_id = 'c1000000-0000-4000-8000-000000000006')::int, 0, 'the deleted conversation lost its messages');
SELECT pg_temp.eq((SELECT count(*) FROM public.messages)::bigint, (SELECT elsewhere FROM tx_c), 'no unrelated message was deleted');
SELECT pg_temp.eq((SELECT in_c6 FROM tx_c) > 0, true, 'the cascade had something to remove');
-- And an event for the deleted conversation can no longer be (re)created.
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000006','c1000000-0000-4000-8000-000000000006','e0000000-0000-4000-8000-000000000071','ca110000-0000-4000-8000-000000000070',1,'user','older utterance, arrives SECOND',pg_temp.tm('t2')) ->> 'code', 'NOT_FOUND', 'a replay into a deleted conversation is NOT_FOUND, never a recreation');
RESET ROLE;

-- ===================== TR-R04: ordinary conversation DELETE enters the write mutex before any row lock =====================
-- SOURCE-LEVEL assertions only (single connection). That the trigger actually removes the lock cycle is a
-- two-connection property: see C6a-C6c below, which have NOT been run.
SELECT pg_temp.eq((SELECT count(*) FROM pg_trigger t WHERE t.tgrelid = 'public.conversations'::regclass AND NOT t.tgisinternal
    AND t.tgfoid = 'public.support_write_mutex_statement()'::regprocedure
    AND (t.tgtype & 1) = 0 AND (t.tgtype & 2) = 2 AND (t.tgtype & 8) = 8 AND t.tgenabled <> 'D')::int, 1,
  'exactly one enabled BEFORE DELETE statement trigger on conversations enters the mutex through M3''s own function');
SELECT pg_temp.eq((SELECT t.tgname FROM pg_trigger t WHERE t.tgrelid = 'public.conversations'::regclass AND NOT t.tgisinternal
    AND t.tgfoid = 'public.support_write_mutex_statement()'::regprocedure), 'aaa_support_write_mutex_conversations_trg', 'named with M3''s aaa_ convention');
SELECT pg_temp.eq((SELECT bool_and((t.tgtype & (4 | 16 | 32)) = 0) FROM pg_trigger t WHERE t.tgname = 'aaa_support_write_mutex_conversations_trg'
    AND t.tgrelid = 'public.conversations'::regclass), true, 'DELETE only: inserts, updates and truncates of conversations are not serialized');
-- A statement-level trigger runs even when no row matches.
DO $$ BEGIN
  DELETE FROM public.conversations WHERE id = 'c9999999-0000-4000-8000-000000000999';
  IF NOT pg_temp.mutex_held() THEN RAISE EXCEPTION 'FAIL a conversation DELETE did not enter the write mutex'; END IF;
END $$;
-- Ordinary traffic is not newly serialized.
DO $$ BEGIN
  UPDATE public.conversations SET updated_at = updated_at WHERE id = 'c1000000-0000-4000-8000-000000000001';
  IF pg_temp.mutex_held() THEN RAISE EXCEPTION 'FAIL an UPDATE of conversations took the write mutex'; END IF;
END $$;
-- Legacy owner RLS is unchanged: B cannot delete A's conversation (the statement trigger still runs for it).
INSERT INTO public.conversations (id, user_id) VALUES ('c1000000-0000-4000-8000-00000000000d', 'aaaaaaaa-0000-4000-8000-000000000001');   -- CA13 throwaway
INSERT INTO public.messages (id, conversation_id, role, content) VALUES ('f0000000-0000-4000-8000-0000000000d1', 'c1000000-0000-4000-8000-00000000000d', 'user', 'throwaway');
SELECT pg_temp.as_user('bbbbbbbb-0000-4000-8000-000000000002');
DO $$ DECLARE n int; BEGIN
  DELETE FROM public.conversations WHERE id = 'c1000000-0000-4000-8000-00000000000d';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL another account deleted a conversation it does not own (% rows)', n; END IF;
END $$;
RESET ROLE;
SELECT pg_temp.eq((SELECT count(*) FROM public.conversations WHERE id = 'c1000000-0000-4000-8000-00000000000d')::int, 1, 'owner RLS: the foreign DELETE changed nothing');
-- The owner can still delete their own conversation as an authenticated user; the definer statement function
-- lets that role enter the private mutex.
CREATE TEMP TABLE tx_del AS SELECT (SELECT count(*) FROM public.messages) AS msgs;
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
DO $$ DECLARE n int; BEGIN
  DELETE FROM public.conversations WHERE id = 'c1000000-0000-4000-8000-00000000000d';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL the owner could not delete their own conversation (% rows)', n; END IF;
  IF NOT pg_temp.mutex_held() THEN RAISE EXCEPTION 'FAIL an owner DELETE did not enter the write mutex'; END IF;
END $$;
RESET ROLE;
SELECT pg_temp.eq((SELECT count(*) FROM public.conversations WHERE id = 'c1000000-0000-4000-8000-00000000000d')::int, 0, 'the owner''s own conversation is deleted');
SELECT pg_temp.eq((SELECT msgs FROM tx_del) - (SELECT count(*) FROM public.messages), 1::bigint, 'exactly its own message went with it (existing cascade); nothing unrelated');
-- Deleting a conversation that a support session was attached to: the session survives, detached; the
-- transcript turn goes with the conversation; nothing is resurrected by a replay.
INSERT INTO public.conversations (id, user_id) VALUES ('c1000000-0000-4000-8000-00000000000e', 'aaaaaaaa-0000-4000-8000-000000000001');   -- CA14
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-0000000000b0","session_id":"5a000000-0000-4000-8000-000000000010","expected_revision":null,"kind":"create","payload":{"title":"conv delete","context_scope":"conversation_only","conversation_id":"c1000000-0000-4000-8000-00000000000e"}}'::jsonb);
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000010','c1000000-0000-4000-8000-00000000000e','e0000000-0000-4000-8000-00000000e001','ca110000-0000-4000-8000-00000000e001',1,'user','lives and dies with the conversation',pg_temp.tm('t1')) ->> 'ok', 'true', 'stored in CA14');
DELETE FROM public.conversations WHERE id = 'c1000000-0000-4000-8000-00000000000e';
RESET ROLE;
SELECT pg_temp.eq((SELECT status || '/' || coalesce(conversation_id::text, 'NULL') FROM public.support_work_sessions WHERE id = '5a000000-0000-4000-8000-000000000010'), 'open/NULL', 'the session row survives (live), detached by the existing SET NULL: no unrelated record was deleted');
SELECT pg_temp.eq((SELECT count(*) FROM public.messages WHERE id = 'e0000000-0000-4000-8000-00000000e001')::int, 0, 'the transcript turn went with its conversation');
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.ap('aaaaaaaa-0000-4000-8000-000000000001','5a000000-0000-4000-8000-000000000010','c1000000-0000-4000-8000-00000000000e','e0000000-0000-4000-8000-00000000e001','ca110000-0000-4000-8000-00000000e001',1,'user','lives and dies with the conversation',pg_temp.tm('t1')) ->> 'code', 'NOT_FOUND', 'a replay into the deleted conversation is NOT_FOUND, never a recreation');
RESET ROLE;

SELECT 'FINISHED (no PASS is claimed until the parent runs this in a disposable database): support_transcript.sql' AS result;

/* ===================== TWO-CONNECTION PROCEDURES (NOT RUN BY psql -f) =====================
Same conventions as supabase/tests/support_session_concurrency.spec and the voice context file:
a disposable database after this file's fixtures, two psql sessions A and B, each switched per
step with pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001') (a session-level role, so
define the helper in each session). "B waits" = the statement blocks (pg_stat_activity.wait_event_type
= 'Lock', wait_event 'advisory'). PASS for every scenario = no SQLSTATE 40P01 anywhere, both
transactions finish, and the stated end state holds. Fresh ids below use the e0000000-...-0000000000fN
and ca110000-...-0000000000fN ranges.

C1  concurrent duplicate intent (the same event twice)
    A: BEGIN; SELECT append(E=...f3, call=...f3, order=1, 'same text');      -- takes the mutex; OPEN
    B: SELECT append(E=...f3, call=...f3, order=1, 'same text');             -- waits at the MUTEX
    A: COMMIT.
    Expect: A replay=false, B replay=true with the same message_id; exactly ONE row with that id.
    Reverse (B first) is symmetric.
C2  same id, altered payload, concurrently
    A: BEGIN; append(E=...f4, ..., 'original');   B: append(E=...f4, ..., 'different'); -- B waits
    A: COMMIT.  Expect B: {"ok":false,"code":"OPERATION_ID_REUSED"}; the stored text is 'original'.
C3  different event ids, same (call, order)
    A: BEGIN; append(E=...f5, call=...f5, order=1);   B: append(E=...f6, call=...f5, order=1);
    A: COMMIT.  Expect B: OPERATION_ID_REUSED (explicit check; the partial unique index is the
    backstop and would surface the same code through the handler).
C4  append versus session deletion, both orders
    A: BEGIN; support_apply_mutation(delete_session on the session, current expected_revision);  -- mutex, OPEN
    B: append(new event, same session).    -- waits; after A COMMIT: NOT_FOUND (a deleted session takes no content)
    Reverse: B: BEGIN; append(new event); (OPEN)  A: delete_session -> waits; B COMMIT; A completes;
    the appended message survives with support_session_id NULL and its voice_* fields intact.
C8  append versus Close (the session becomes closed while a final is in flight), both orders
    A: BEGIN; support_apply_mutation(update_session close, current expected_revision);  -- mutex, OPEN
    B: append(new event, same session)   -- waits at the MUTEX; after A COMMIT it is stored (storage-only,
       session stays closed, replay=false); a repeat is replay=true.   Reverse: B first, then A closes;
       both succeed; no deadlock; the session row is written only by A.
C5  append versus suppression of the conversation / forgetting the message id, both orders
    A: BEGIN; support_memory_mutate(<suppress source conversation C>)  (or INSERT into support_suppressions
       through the supported mutation); OPEN.   B: append(new event in C) -- waits; after A COMMIT:
    CONTENT_UNAVAILABLE.   Reverse: B first appends, A's suppression then queues behind B's mutex;
    afterwards the replay of B's event is still honored (replay=true) and any NEW event is CONTENT_UNAVAILABLE.
C6  append versus an ORDINARY conversation DELETE (TR-R04). Background: support_work_sessions.conversation_id is
    ON DELETE SET NULL, so DELETE locks the conversation row, then the FK action needs the session row; the
    append holds the session row (FOR SHARE) and then wants the conversation row. Source fix: the BEFORE
    DELETE statement trigger enters the private mutex BEFORE any row lock. Fixture ids: a conversation C
    with an open attached session S (use the CA1/SA1 pair or a fresh pair; prefer a fresh pair per run).
    NONE of C6a-C6e has been run; they are the real-PostgreSQL qualification of the source fix.
C6a DELETE first, then append
    A: BEGIN; DELETE FROM public.conversations WHERE id = C;   -- the statement trigger takes the mutex before
                                                                  -- any row lock; then C's row lock, then the SET NULL update
    B: SELECT public.append_support_transcript(<owner>, S, C, <event>, <call>, 1, 'user', 'x', <t>);
       -- EXACT WAIT POINT: B blocks inside its FIRST table-touching step, support_acquire_write_mutex().
       Verify (third session, while B waits):
         SELECT wait_event_type, wait_event FROM pg_stat_activity WHERE pid = <B>;     -- Lock / advisory
         SELECT 1 FROM pg_locks WHERE pid = <B> AND locktype = 'advisory' AND NOT granted;   -- 1 row (the mutex key)
         SELECT count(*) FROM pg_locks WHERE pid = <B> AND granted AND locktype IN ('tuple','transactionid')
           AND NOT (locktype = 'transactionid' AND mode = 'ExclusiveLock');                 -- 0: B holds no row lock yet
    A: COMMIT.   Expect B: {"ok":false,"code":"NOT_FOUND"}; C gone, its messages gone, S live with
       conversation_id NULL; no SQLSTATE 40P01 anywhere.
C6b append first, then DELETE
    B: BEGIN; SELECT public.append_support_transcript(... S, C ...);   -- holds mutex, privacy S, session S, conversation S; OPEN
    A: DELETE FROM public.conversations WHERE id = C;
       -- EXACT WAIT POINT: A blocks in the BEFORE STATEMENT trigger on the mutex, BEFORE locking C's row.
       Verify: A wait_event 'advisory' as above; and a THIRD session can still take the row:
         SELECT 1 FROM public.conversations WHERE id = C FOR KEY SHARE NOWAIT; -- compatible with B's updated_at NO KEY UPDATE; A holds no row lock
    B: COMMIT.   A resumes: C deleted, S detached by SET NULL, B's new message cascaded. Expect no 40P01.
C6c deterministic three-session pin (also the NEGATIVE CONTROL that proves the harness sees the defect)
    C (pin): BEGIN; SELECT 1 FROM public.conversations WHERE id = C FOR UPDATE;         -- holds C's row
    A: DELETE FROM public.conversations WHERE id = C;                                      -- start A FIRST
    B: SELECT public.append_support_transcript(... S, C ...);                              -- start B SECOND
    C: COMMIT (release the pin).
    WITH the trigger (the delivered state): A took the mutex first and waits only for the row; B waits at the
       MUTEX holding nothing. Expect A completes, then B returns NOT_FOUND. No 40P01.
    WITHOUT the trigger (DISPOSABLE DATABASE ONLY):  ALTER TABLE public.conversations DISABLE TRIGGER
       aaa_support_write_mutex_conversations_trg;  then repeat. B takes the mutex, privacy S, session S and
       waits on the conversation row behind A in the queue; after the pin is released A gets the row, its
       SET NULL update waits for B's session lock, and B waits for A: expect SQLSTATE 40P01 for exactly one of
       them after deadlock_timeout. Re-enable:  ALTER TABLE public.conversations ENABLE TRIGGER
       aaa_support_write_mutex_conversations_trg;   If the disabled run does NOT deadlock, the schedule is not
       exercising the defect and C6a/C6b prove nothing - stop and report.
C6d FK-CASCADE qualification (do not assume either answer): does a cascaded delete fire a BEFORE STATEMENT
    trigger on the child table in the target PostgreSQL? Probe in a scratch session:
      CREATE TEMP TABLE pq(id int PRIMARY KEY);  CREATE TEMP TABLE cq(pid int REFERENCES pq ON DELETE CASCADE);
      CREATE FUNCTION pg_temp.note() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE NOTICE 'child statement trigger fired'; RETURN NULL; END $$;
      CREATE TRIGGER t BEFORE DELETE ON cq FOR EACH STATEMENT EXECUTE FUNCTION pg_temp.note();
      INSERT INTO pq VALUES (1); INSERT INTO cq VALUES (1); DELETE FROM pq;   -- NOTICE printed? record yes/no
    Record the answer with the server version. It decides whether account deletion (DELETE FROM auth.users, which
    cascades to conversations) enters the mutex for conversations; the new trigger and M3's existing ones on
    messages/companion_memory/daily_intents/memory_fragments behave identically in that respect.
C6e account deletion versus an in-flight append (only meaningful if C6d printed the NOTICE)
    B: BEGIN; SELECT public.append_support_transcript(... S, C ...);   -- holds the mutex; OPEN
    A: DELETE FROM auth.users WHERE id = <owner>;                       -- holds the auth.users row, cascades to conversations
    Observe whether A waits at the mutex from inside the cascade. B: COMMIT. A completes.
    RISK to record, not assume away: a writer that holds the mutex and then needs the auth.users row (KEY SHARE,
    e.g. support_apply_mutation create inserting a session) while A holds that row and waits for the mutex is a
    possible cycle. If observed, the remedy belongs to the account-deletion flow (enter the mutex first), not here.
C7  the mutex is genuinely first: A: BEGIN; SELECT public.support_acquire_write_mutex(); OPEN.
    B: append(...)  -> waits (and holds NO privacy/session/conversation lock while waiting: confirm with
    pg_locks that B holds no row locks on support_privacy_state/support_work_sessions/conversations).
    A: COMMIT -> B completes.
*/
