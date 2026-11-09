-- Voice context admission contract test. NOT EXECUTED by its author (source-only until the
-- parent reviews it). DISPOSABLE LOCAL DATABASE ONLY, with the whole migration chain through
-- 20261107020000_support_voice_context.sql applied, including the bounded relay chain
-- (20261023083500 ... 20261023092207, bound_monthly_ai_budget) and the support-session chain
-- in its LATEST M3 form (20261106230000 ... 20261106230200: private support_acquire_write_mutex,
-- support_memory_time_eligible(companion_memory, timestamptz), legacy-writer mutex triggers, and
-- messages.content_revision with support_message_revision_guard and the messages mutex trigger).
-- The time cases below sleep (about 7 s each); the two-connection lock-order procedure at the
-- end of this file is NOT run by psql -f and needs two sessions. Synthetic users only; run as a superuser/owner role
-- (it switches to service_role itself) and drop the database afterwards. As in
-- support_session.sql, adjust the FIXTURE block, not the assertions, for the selected schema.
-- No provider, network, microphone or real data is involved.
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
CREATE OR REPLACE FUNCTION pg_temp.as_service() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.role', 'service_role', false);
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, false);
  EXECUTE 'SET ROLE service_role';
END $$;

-- True when THIS backend holds M3's private write mutex (a transaction-scoped advisory lock).
CREATE OR REPLACE FUNCTION pg_temp.mutex_held() RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM pg_locks
    WHERE locktype = 'advisory' AND pid = pg_backend_pid() AND granted
      AND ((classid::bigint << 32) | objid::bigint) = hashtextextended('mindfriend.support.context-write-mutex', 0));
$$;

-- ===================== FIXTURE =====================
RESET ROLE;
INSERT INTO public.supported_languages(code,name,native_name,is_active) VALUES('en','English','English',true) ON CONFLICT DO NOTHING;
INSERT INTO public.level_thresholds(level,xp_required,title) VALUES(1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO public.skill_thresholds(level,xp_required,title) VALUES(1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO auth.users (id, aud, role, email) VALUES
  ('aaaaaaaa-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'va@example.invalid'),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'vb@example.invalid');
INSERT INTO public.user_stats (user_id) VALUES
  ('aaaaaaaa-0000-4000-8000-000000000001'), ('bbbbbbbb-0000-4000-8000-000000000002') ON CONFLICT DO NOTHING;
INSERT INTO public.conversations (id, user_id) VALUES
  ('cccccccc-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001'),
  ('cccccccc-0000-4000-8000-000000000002', 'bbbbbbbb-0000-4000-8000-000000000002'),
  ('cccccccc-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001');
-- Admission budgets, as in bounded_voice.sql (zero blocks admission by design).
UPDATE public.voice_provider_budget SET daily_seconds = 3600;
INSERT INTO public.monthly_ai_budget_months(month_start, limit_microdollars)
  VALUES (date_trunc('month', timezone('America/New_York', clock_timestamp()))::date, 10000000)
  ON CONFLICT (month_start) DO UPDATE SET limit_microdollars = excluded.limit_microdollars;

-- Sessions through the real M3 contract: A has an attached personalized session and an attached
-- conversation-only session; B has one.
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-0000000000a1","session_id":"61000000-0000-4000-8000-000000000001","expected_revision":null,"kind":"create","payload":{"title":"Voice work","context_scope":"personalized","conversation_id":"cccccccc-0000-4000-8000-000000000001"}}'::jsonb)) ->> 'ok', 'true', 'A personalized session');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"10000000-0000-4000-8000-0000000000a2","session_id":"61000000-0000-4000-8000-000000000002","expected_revision":null,"kind":"create","payload":{"title":"Voice narrow","context_scope":"conversation_only","conversation_id":"cccccccc-0000-4000-8000-000000000003"}}'::jsonb)) ->> 'ok', 'true', 'A conversation-only session');
SELECT pg_temp.as_user('bbbbbbbb-0000-4000-8000-000000000002');
SELECT pg_temp.eq((public.support_apply_mutation('{"schema_version":1,"operation_id":"20000000-0000-4000-8000-0000000000b1","session_id":"62000000-0000-4000-8000-000000000001","expected_revision":null,"kind":"create","payload":{"title":"B voice","context_scope":"personalized","conversation_id":"cccccccc-0000-4000-8000-000000000002"}}'::jsonb)) ->> 'ok', 'true', 'B session');
RESET ROLE;

CREATE TEMP TABLE voice_ctx(k text PRIMARY KEY, v text);
GRANT ALL ON voice_ctx TO PUBLIC;
INSERT INTO voice_ctx
  SELECT 'sources_a', jsonb_build_array(
    jsonb_build_object('kind', 'safety_policy', 'id', '00000000-0000-0000-0000-000000000001', 'revision', 1, 'date', NULL),
    jsonb_build_object('kind', 'session', 'id', '61000000-0000-4000-8000-000000000001', 'revision',
      (SELECT context_revision FROM public.support_work_sessions WHERE id = '61000000-0000-4000-8000-000000000001'), 'date', NULL))::text;
INSERT INTO voice_ctx SELECT 'privacy_a', (public.support_ensure_privacy_state('aaaaaaaa-0000-4000-8000-000000000001'))::text;
INSERT INTO voice_ctx VALUES ('hash', repeat('a', 64)), ('privacy_new', '0');

-- ===================== GRANTS: service role only =====================
SELECT pg_temp.eq(
  has_function_privilege('authenticated', 'public.prepare_voice_relay_context(uuid,uuid,uuid,text,bigint,text,integer,text,text,text,jsonb,jsonb)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.claim_voice_relay_context(uuid,uuid)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.voice_relay_context_binding(uuid,uuid)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.voice_relay_context_check(uuid,uuid)', 'EXECUTE')
  OR has_function_privilege('anon', 'public.claim_voice_relay_context(uuid,uuid)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.voice_relay_context_sources_ok(uuid,uuid,uuid,text,jsonb,timestamptz)', 'EXECUTE')
  OR has_function_privilege('authenticated', 'public.voice_relay_context_lock_sources(uuid,uuid,jsonb)', 'EXECUTE')
  OR has_function_privilege('service_role', 'public.voice_relay_context_lock_sources(uuid,uuid,jsonb)', 'EXECUTE')
  OR has_function_privilege('service_role', 'public.voice_relay_context_sources_ok(uuid,uuid,uuid,text,jsonb,timestamptz)', 'EXECUTE')
  OR has_table_privilege('authenticated', 'public.voice_relay_context_bindings', 'SELECT'),
  false, 'no API role can reach the voice context wrappers or bindings');
SELECT pg_temp.eq(has_function_privilege('service_role', 'public.prepare_voice_relay_context(uuid,uuid,uuid,text,bigint,text,integer,text,text,text,jsonb,jsonb)', 'EXECUTE'), true, 'service role can prepare');
SELECT pg_temp.eq(has_table_privilege('service_role', 'public.voice_relay_context_bindings', 'INSERT'), false, 'bindings are written only by the definer wrappers');
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq(pg_temp.err($q$SELECT public.claim_voice_relay_context('aaaaaaaa-0000-4000-8000-000000000001', gen_random_uuid())$q$) LIKE '%permission denied%', true, 'authenticated cannot call the claim wrapper');
RESET ROLE;

-- ===================== PREPARE: atomic verification, marker, receipt, binding =====================
SELECT pg_temp.as_service();
-- Cross-owner: B cannot bind A's session or conversation.
SELECT pg_temp.eq(pg_temp.err(format($q$SELECT public.prepare_voice_relay_context('bbbbbbbb-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000001','personalized',1,%L,100,'openai','gpt-realtime-2.1-mini','voice-relay-1',%L::jsonb,'[]'::jsonb)$q$, (SELECT v FROM voice_ctx WHERE k='hash'), (SELECT v FROM voice_ctx WHERE k='sources_a'))), 'SESSION_NOT_FOUND', 'cross-owner conversation rejected');
-- Session/conversation mismatch (A's own other conversation).
SELECT pg_temp.eq(pg_temp.err(format($q$SELECT public.prepare_voice_relay_context('aaaaaaaa-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000003','personalized',%s,%L,100,'openai','gpt-realtime-2.1-mini','voice-relay-1',%L::jsonb,'[]'::jsonb)$q$, (SELECT v FROM voice_ctx WHERE k='privacy_a'), (SELECT v FROM voice_ctx WHERE k='hash'), (SELECT v FROM voice_ctx WHERE k='sources_a'))), 'SESSION_CONVERSATION_MISMATCH', 'conversation not the session''s own');
-- Scope may narrow, never widen.
SELECT pg_temp.eq(pg_temp.err(format($q$SELECT public.prepare_voice_relay_context('aaaaaaaa-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000002','cccccccc-0000-4000-8000-000000000003','personalized',%s,%L,100,'openai','gpt-realtime-2.1-mini','voice-relay-1',%L::jsonb,'[]'::jsonb)$q$, (SELECT v FROM voice_ctx WHERE k='privacy_a'), (SELECT v FROM voice_ctx WHERE k='hash'), (SELECT v FROM voice_ctx WHERE k='sources_a'))), 'SCOPE_MISMATCH', 'scope widening rejected');
-- Stale acknowledged privacy revision.
SELECT pg_temp.eq(pg_temp.err(format($q$SELECT public.prepare_voice_relay_context('aaaaaaaa-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000001','personalized',999,%L,100,'openai','gpt-realtime-2.1-mini','voice-relay-1',%L::jsonb,'[]'::jsonb)$q$, (SELECT v FROM voice_ctx WHERE k='hash'), (SELECT v FROM voice_ctx WHERE k='sources_a'))), 'PRIVACY_REVISION_STALE', 'stale revision rejected');
-- A cited source at the wrong revision is stale (the session cited with an old revision).
SELECT pg_temp.eq(pg_temp.err(format($q$SELECT public.prepare_voice_relay_context('aaaaaaaa-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000001','personalized',%s,%L,100,'openai','gpt-realtime-2.1-mini','voice-relay-1',%L::jsonb,'[]'::jsonb)$q$, (SELECT v FROM voice_ctx WHERE k='privacy_a'), (SELECT v FROM voice_ctx WHERE k='hash'),
  '[{"kind":"safety_policy","id":"00000000-0000-0000-0000-000000000001","revision":1},{"kind":"session","id":"61000000-0000-4000-8000-000000000001","revision":999}]')), 'PRIVACY_REVISION_STALE', 'source revision checked');
-- Nothing above left a reservation, receipt or binding behind.
SELECT pg_temp.eq((SELECT count(*) FROM public.voice_relay_reservations WHERE user_id IN ('aaaaaaaa-0000-4000-8000-000000000001','bbbbbbbb-0000-4000-8000-000000000002'))::int, 0, 'failed prepares are fully rolled back');
SELECT pg_temp.eq((SELECT count(*) FROM public.voice_relay_context_bindings)::int, 0, 'no binding without a successful prepare');

-- Success: one transaction marks, receipts and binds.
INSERT INTO voice_ctx
  SELECT 'prep1', public.prepare_voice_relay_context('aaaaaaaa-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000001','personalized',
    (SELECT v::bigint FROM voice_ctx WHERE k='privacy_a'), (SELECT v FROM voice_ctx WHERE k='hash'), 1234, 'openai', 'gpt-realtime-2.1-mini', 'voice-relay-1',
    (SELECT v::jsonb FROM voice_ctx WHERE k='sources_a'), '["absence_metadata","health_data"]'::jsonb)::text;
INSERT INTO voice_ctx SELECT 'sid1', (v::jsonb ->> 'session_id') FROM voice_ctx WHERE k='prep1';
SELECT pg_temp.eq((SELECT context_required FROM public.voice_relay_reservations WHERE session_id = (SELECT v::uuid FROM voice_ctx WHERE k='sid1')), true, 'new admission is marked context_required at creation');
SELECT pg_temp.eq((SELECT context_claim_ok FROM public.voice_relay_reservations WHERE session_id = (SELECT v::uuid FROM voice_ctx WHERE k='sid1')), false, 'claim not yet authorized');
SELECT pg_temp.eq((SELECT claimed_at IS NULL FROM public.voice_relay_reservations WHERE session_id = (SELECT v::uuid FROM voice_ctx WHERE k='sid1')), true, 'prepare does not claim');
SELECT pg_temp.eq((SELECT v::jsonb ->> 'packet_sha256' FROM voice_ctx WHERE k='prep1'), repeat('a', 64), 'binding echoes the packet hash');
SELECT pg_temp.eq((SELECT count(*) FROM public.voice_relay_context_bindings b JOIN public.support_context_receipts r ON r.id = b.context_receipt_id
    WHERE b.session_id = (SELECT v::uuid FROM voice_ctx WHERE k='sid1') AND b.provider_vendor = 'openai' AND b.provider_model = 'gpt-realtime-2.1-mini'
      AND b.context_scope = 'personalized' AND r.assistant_message_id IS NULL AND r.request_id = b.session_id AND r.privacy_revision = b.privacy_revision)::int, 1, 'one binding with a content-free receipt');
SELECT pg_temp.eq((SELECT count(*) FROM public.support_context_receipt_sources WHERE receipt_id = (SELECT context_receipt_id FROM public.voice_relay_context_bindings))::int, 2, 'receipt references recorded');

-- ===================== CLAIM: never as legacy; wrapper revalidates and keeps every admission check =====================
-- Legacy claim of a context_required preparation is refused (guard trigger), and stays unclaimed.
SELECT pg_temp.eq(pg_temp.err(format($q$SELECT public.claim_voice_relay('aaaaaaaa-0000-4000-8000-000000000001', %L)$q$, (SELECT v FROM voice_ctx WHERE k='sid1'))), 'VOICE_CONTEXT_REQUIRED', 'legacy claim refused');
SELECT pg_temp.eq(pg_temp.err(format($q$UPDATE public.voice_relay_reservations SET claimed_at = now(), reserved_seconds = 120 WHERE session_id = %L$q$, (SELECT v FROM voice_ctx WHERE k='sid1'))), 'VOICE_CONTEXT_REQUIRED', 'direct claim refused');
SELECT pg_temp.eq(pg_temp.err(format($q$UPDATE public.voice_relay_reservations SET context_required = false WHERE session_id = %L$q$, (SELECT v FROM voice_ctx WHERE k='sid1'))), 'VOICE_CONTEXT_REQUIRED', 'marker cannot be cleared');
SELECT pg_temp.eq((SELECT claimed_at IS NULL FROM public.voice_relay_reservations WHERE session_id = (SELECT v::uuid FROM voice_ctx WHERE k='sid1')), true, 'still unclaimed after refusals');
-- Another owner cannot claim it.
SELECT pg_temp.eq(pg_temp.err(format($q$SELECT public.claim_voice_relay_context('bbbbbbbb-0000-4000-8000-000000000002', %L)$q$, (SELECT v FROM voice_ctx WHERE k='sid1'))), 'INVALID_SESSION', 'cross-owner claim rejected');
-- Peek: owner sees the frozen route; others and legacy preparations see unbound.
SELECT pg_temp.eq((public.voice_relay_context_binding('aaaaaaaa-0000-4000-8000-000000000001', (SELECT v::uuid FROM voice_ctx WHERE k='sid1'))) ->> 'provider_vendor', 'openai', 'route is readable before the claim');
SELECT pg_temp.eq((public.voice_relay_context_binding('bbbbbbbb-0000-4000-8000-000000000002', (SELECT v::uuid FROM voice_ctx WHERE k='sid1'))) ->> 'bound', 'false', 'other owner sees no binding');
-- Lease check is current while nothing changed.
SELECT pg_temp.eq((public.voice_relay_context_check('aaaaaaaa-0000-4000-8000-000000000001', (SELECT v::uuid FROM voice_ctx WHERE k='sid1'))) ->> 'ok', 'true', 'check is current');

-- A privacy correction between prepare and claim stops the claim, atomically (nothing consumed).
RESET ROLE;
SELECT public.support_bump_privacy('aaaaaaaa-0000-4000-8000-000000000001');
UPDATE voice_ctx SET v = (SELECT privacy_revision::text FROM public.support_privacy_state WHERE user_id = 'aaaaaaaa-0000-4000-8000-000000000001') WHERE k = 'privacy_new';
SELECT pg_temp.as_service();
SELECT pg_temp.eq((public.voice_relay_context_check('aaaaaaaa-0000-4000-8000-000000000001', (SELECT v::uuid FROM voice_ctx WHERE k='sid1'))) ->> 'code', 'PRIVACY_REVISION_STALE', 'check observes a correction');
SELECT pg_temp.eq(pg_temp.err(format($q$SELECT public.claim_voice_relay_context('aaaaaaaa-0000-4000-8000-000000000001', %L)$q$, (SELECT v FROM voice_ctx WHERE k='sid1'))), 'PRIVACY_REVISION_STALE', 'claim revalidates the privacy revision');
SELECT pg_temp.eq((SELECT claimed_at IS NULL AND NOT context_claim_ok FROM public.voice_relay_reservations WHERE session_id = (SELECT v::uuid FROM voice_ctx WHERE k='sid1')), true, 'refused claim consumed nothing');
SELECT pg_temp.eq((SELECT count(*) FROM public.monthly_ai_budget_receipts WHERE request_id = (SELECT v::uuid FROM voice_ctx WHERE k='sid1'))::int, 0, 'no monthly reservation for a refused claim');

-- Re-admit at the new revision (the client refreshes), then claim through the wrapper.
UPDATE voice_ctx SET v = (SELECT v FROM voice_ctx WHERE k = 'privacy_new') WHERE k = 'privacy_a';
INSERT INTO voice_ctx
  SELECT 'prep2', public.prepare_voice_relay_context('aaaaaaaa-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000001','personalized',
    (SELECT v::bigint FROM voice_ctx WHERE k='privacy_a'), repeat('b', 64), 2222, 'xai', 'grok-voice-3.0', 'voice-relay-1',
    (SELECT v::jsonb FROM voice_ctx WHERE k='sources_a'), '[]'::jsonb)::text;
INSERT INTO voice_ctx SELECT 'sid2', (v::jsonb ->> 'session_id') FROM voice_ctx WHERE k='prep2';
INSERT INTO voice_ctx
  SELECT 'claim2', public.claim_voice_relay_context('aaaaaaaa-0000-4000-8000-000000000001', (SELECT v::uuid FROM voice_ctx WHERE k='sid2'))::text;
SELECT pg_temp.eq((SELECT v::jsonb ->> 'reserved_seconds' FROM voice_ctx WHERE k='claim2'), '120', 'existing claim result is returned');
SELECT pg_temp.eq((SELECT v::jsonb ->> 'monthly_reserve_microdollars' FROM voice_ctx WHERE k='claim2'), '240000', 'fixed monthly reserve still applies');
SELECT pg_temp.eq((SELECT v::jsonb ->> 'provider_vendor' FROM voice_ctx WHERE k='claim2'), 'xai', 'claim returns the stored route, not ambient configuration');
SELECT pg_temp.eq((SELECT v::jsonb ->> 'packet_sha256' FROM voice_ctx WHERE k='claim2'), repeat('b', 64), 'claim returns the bound packet hash');
SELECT pg_temp.eq((SELECT claimed_at IS NOT NULL AND context_claim_ok AND budget_day IS NOT NULL FROM public.voice_relay_reservations WHERE session_id = (SELECT v::uuid FROM voice_ctx WHERE k='sid2')), true, 'claimed once with budget day');
SELECT pg_temp.eq((SELECT feature FROM public.monthly_ai_budget_receipts WHERE request_id = (SELECT v::uuid FROM voice_ctx WHERE k='sid2')), 'voice.live', 'monthly reserve attributed to voice.live');
SELECT pg_temp.eq(pg_temp.err(format($q$SELECT public.claim_voice_relay_context('aaaaaaaa-0000-4000-8000-000000000001', %L)$q$, (SELECT v FROM voice_ctx WHERE k='sid2'))), 'INVALID_SESSION', 'replay rejected');

-- One active relay per owner still holds; the refused wrapper claim rolls its marker back.
INSERT INTO voice_ctx
  SELECT 'prep3', public.prepare_voice_relay_context('aaaaaaaa-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000001','personalized',
    (SELECT v::bigint FROM voice_ctx WHERE k='privacy_a'), repeat('c', 64), 3333, 'openai', 'gpt-realtime-2.1-mini', 'voice-relay-1',
    (SELECT v::jsonb FROM voice_ctx WHERE k='sources_a'), '[]'::jsonb)::text;
INSERT INTO voice_ctx SELECT 'sid3', (v::jsonb ->> 'session_id') FROM voice_ctx WHERE k='prep3';
SELECT pg_temp.eq(pg_temp.err(format($q$SELECT public.claim_voice_relay_context('aaaaaaaa-0000-4000-8000-000000000001', %L)$q$, (SELECT v FROM voice_ctx WHERE k='sid3'))), 'RELAY_ALREADY_ACTIVE', 'second active relay refused');
SELECT pg_temp.eq((SELECT claimed_at IS NULL AND NOT context_claim_ok FROM public.voice_relay_reservations WHERE session_id = (SELECT v::uuid FROM voice_ctx WHERE k='sid3')), true, 'refused claim leaves no authorization behind');

-- Trusted settlement is unchanged: the existing finalizer closes the new-contract reservation.
SELECT public.finalize_voice_relay((SELECT v::uuid FROM voice_ctx WHERE k='sid2'), 30, false);
SELECT pg_temp.eq((SELECT finalized_at IS NOT NULL AND duration_seconds = 30 FROM public.voice_relay_reservations WHERE session_id = (SELECT v::uuid FROM voice_ctx WHERE k='sid2')), true, 'finalized with trusted duration');

-- Starts per minute: prep1..prep3 used the three allowed; the wrapper inherits the limit.
SELECT pg_temp.eq(pg_temp.err(format($q$SELECT public.prepare_voice_relay_context('aaaaaaaa-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000001','personalized',%s,%L,100,'openai','gpt-realtime-2.1-mini','voice-relay-1',%L::jsonb,'[]'::jsonb)$q$, (SELECT v FROM voice_ctx WHERE k='privacy_a'), repeat('e', 64), (SELECT v FROM voice_ctx WHERE k='sources_a'))), 'RATE_LIMITED', 'three starts per minute still apply');
SELECT pg_temp.eq((SELECT count(*) FROM public.voice_relay_context_bindings)::int, 3, 'the rate-limited prepare left no binding behind');

-- ===================== LEGACY PATH UNCHANGED =====================
SELECT pg_temp.eq((SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='voice_relay_reservations' AND column_name IN ('context_required','context_claim_ok') AND column_default = 'false')::int, 2, 'legacy rows default to unmarked');
INSERT INTO voice_ctx SELECT 'legacy_sid', (public.prepare_voice_relay('bbbbbbbb-0000-4000-8000-000000000002') ->> 'session_id');
SELECT pg_temp.eq((SELECT context_required FROM public.voice_relay_reservations WHERE session_id = (SELECT v::uuid FROM voice_ctx WHERE k='legacy_sid')), false, 'legacy prepare is unmarked');
SELECT pg_temp.eq((public.voice_relay_context_binding('bbbbbbbb-0000-4000-8000-000000000002', (SELECT v::uuid FROM voice_ctx WHERE k='legacy_sid'))) ->> 'bound', 'false', 'legacy preparation reports unbound');
SELECT pg_temp.eq(pg_temp.err(format($q$SELECT public.claim_voice_relay_context('bbbbbbbb-0000-4000-8000-000000000002', %L)$q$, (SELECT v FROM voice_ctx WHERE k='legacy_sid'))), 'VOICE_CONTEXT_REQUIRED', 'a legacy preparation is never claimed as new-contract');
-- sid2 is finalized, so the legacy claim for B is the only active relay.
SELECT pg_temp.eq((public.claim_voice_relay('bbbbbbbb-0000-4000-8000-000000000002', (SELECT v::uuid FROM voice_ctx WHERE k='legacy_sid')) ->> 'reserved_seconds')::int, 120, 'legacy claim works exactly as before');

-- ===================== CAPABILITIES =====================
RESET ROLE;
SELECT pg_temp.as_user('aaaaaaaa-0000-4000-8000-000000000001');
SELECT pg_temp.eq((public.support_capabilities() ->> 'voice_context')::int, 1, 'voice_context advertised as version 1');
SELECT pg_temp.eq((public.support_capabilities() ->> 'session_contract')::int, 1, 'other M3 capability keys are preserved');
SELECT pg_temp.eq(pg_temp.err($q$SELECT public.support_capabilities_base()$q$) LIKE '%permission denied%', true, 'the renamed base function is not exposed');
RESET ROLE;

-- ===================== M3 r4 LOCKING: write mutex first, held to commit; refresh is lock-free =====================
RESET ROLE;
-- A refresh takes no lock at all (it must never queue behind a writer).
DO $$ BEGIN
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  PERFORM public.voice_relay_context_check('aaaaaaaa-0000-4000-8000-000000000001', (SELECT v::uuid FROM voice_ctx WHERE k = 'sid1'));
  IF pg_temp.mutex_held() THEN RAISE EXCEPTION 'FAIL refresh took the write mutex'; END IF;
  IF EXISTS (SELECT 1 FROM pg_locks WHERE pid = pg_backend_pid() AND locktype = 'advisory') THEN
    RAISE EXCEPTION 'FAIL refresh took an advisory lock';
  END IF;
END $$;
-- The claim wrapper takes the mutex too, and holds it until commit. (A failed claim cannot show
-- this in one session: locks taken inside a rolled-back subtransaction are released with it.)
-- Make room first (age the 3/minute window, close the legacy relay still active above), then
-- prepare in ONE transaction and claim in ANOTHER.
UPDATE public.voice_relay_reservations SET prepared_at = prepared_at - interval '10 minutes';
SELECT pg_temp.as_service();
SELECT public.finalize_voice_relay((SELECT v::uuid FROM voice_ctx WHERE k='legacy_sid'), 0, false);
INSERT INTO voice_ctx
  SELECT 'prep5', public.prepare_voice_relay_context('aaaaaaaa-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000001','personalized',
    (SELECT v::bigint FROM voice_ctx WHERE k='privacy_a'), repeat('9', 64), 5555, 'openai', 'gpt-realtime-2.1-mini', 'voice-relay-1',
    (SELECT v::jsonb FROM voice_ctx WHERE k='sources_a'), '[]'::jsonb)::text;
INSERT INTO voice_ctx SELECT 'sid5', (v::jsonb ->> 'session_id') FROM voice_ctx WHERE k='prep5';
DO $$ BEGIN
  PERFORM public.claim_voice_relay_context('aaaaaaaa-0000-4000-8000-000000000001', (SELECT v::uuid FROM voice_ctx WHERE k='sid5'));
  IF NOT pg_temp.mutex_held() THEN RAISE EXCEPTION 'FAIL claim must hold the M3 write mutex until commit'; END IF;
END $$;
SELECT pg_temp.eq(pg_temp.mutex_held(), false, 'no mutex leaks past the transaction');

-- ===================== TIME: expiry and life-context review re-evaluated at every boundary =====================
-- No row is edited and the privacy revision never moves while the deadline passes (MF-M6S-002).
-- For each kind the memory is cited, admitted and claimed BEFORE its deadline; then: the next
-- refresh is not current; a second preparation made before the deadline cannot be claimed after
-- it (and consumes nothing); a fresh preparation after it is refused.
CREATE OR REPLACE FUNCTION pg_temp.time_case(p_kind text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  u constant uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  sess constant uuid := '61000000-0000-4000-8000-000000000001';
  conv constant uuid := 'cccccccc-0000-4000-8000-000000000001';
  m uuid := gen_random_uuid(); deadline timestamptz; v_priv bigint; v_srev bigint;
  v_sources jsonb; v_a uuid; v_b uuid; v_check jsonb; v_msg text;
BEGIN
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  -- Make room: age earlier preparations out of the 3/minute window, close any active relay.
  UPDATE public.voice_relay_reservations SET prepared_at = prepared_at - interval '10 minutes';
  PERFORM public.finalize_voice_relay(session_id, 0, false)
    FROM public.voice_relay_reservations WHERE claimed_at IS NOT NULL AND finalized_at IS NULL;
  deadline := clock_timestamp() + interval '6 seconds';
  PERFORM set_config('support.memory_rpc', 'on', true);   -- lets the fixture choose confirmed_at
  IF p_kind = 'expiry' THEN
    INSERT INTO public.companion_memory (id, user_id, category, content, expires_at)
      VALUES (m, u, 'boundaries', 'synthetic timed boundary', deadline);
  ELSIF p_kind = 'review' THEN
    INSERT INTO public.companion_memory (id, user_id, category, content, confirmed_at, review_due_at)
      VALUES (m, u, 'life_context', 'synthetic timed life fact', clock_timestamp(), deadline);
  ELSIF p_kind = 'default_review' THEN
    INSERT INTO public.companion_memory (id, user_id, category, content, confirmed_at)
      VALUES (m, u, 'life_context', 'synthetic default review', deadline - interval '90 days');
  ELSE
    RAISE EXCEPTION 'unknown kind %', p_kind;
  END IF;
  PERFORM set_config('support.memory_rpc', 'off', true);
  -- The insert advanced the privacy revision; read it AFTER, then never change anything again.
  SELECT privacy_revision INTO v_priv FROM public.support_privacy_state WHERE user_id = u;
  SELECT context_revision INTO v_srev FROM public.support_work_sessions WHERE id = sess;
  v_sources := jsonb_build_array(
    jsonb_build_object('kind', 'safety_policy', 'id', '00000000-0000-0000-0000-000000000001', 'revision', 1, 'date', NULL),
    jsonb_build_object('kind', 'session', 'id', sess, 'revision', v_srev, 'date', NULL),
    jsonb_build_object('kind', 'companion_memory', 'id', m, 'revision', (SELECT revision FROM public.companion_memory WHERE id = m), 'date', NULL));

  v_a := (public.prepare_voice_relay_context(u, sess, conv, 'personalized', v_priv, repeat('f', 64), 1000,
    'openai', 'gpt-realtime-2.1-mini', 'voice-relay-1', v_sources, '[]'::jsonb) ->> 'session_id')::uuid;
  IF NOT pg_temp.mutex_held() THEN RAISE EXCEPTION 'FAIL % prepare must hold the M3 write mutex until commit', p_kind; END IF;
  v_b := (public.prepare_voice_relay_context(u, sess, conv, 'personalized', v_priv, repeat('e', 64), 1000,
    'openai', 'gpt-realtime-2.1-mini', 'voice-relay-1', v_sources, '[]'::jsonb) ->> 'session_id')::uuid;
  PERFORM public.claim_voice_relay_context(u, v_a);   -- before the deadline: admitted
  v_check := public.voice_relay_context_check(u, v_a);
  IF v_check ->> 'ok' <> 'true' THEN RAISE EXCEPTION 'FAIL %: not current before the deadline: %', p_kind, v_check; END IF;

  PERFORM pg_sleep(greatest(0, extract(epoch FROM (deadline - clock_timestamp()))) + 0.5);   -- deadline passes
  v_check := public.voice_relay_context_check(u, v_a);
  IF v_check ->> 'ok' <> 'false' OR v_check ->> 'code' <> 'PRIVACY_REVISION_STALE' THEN
    RAISE EXCEPTION 'FAIL %: a refresh after the deadline was still current: %', p_kind, v_check;
  END IF;
  IF (SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = u) <> v_priv THEN
    RAISE EXCEPTION 'FAIL %: the privacy revision moved; the time rule was not what failed', p_kind;
  END IF;
  -- The preparation made before the deadline cannot be claimed after it; it consumes nothing.
  BEGIN
    PERFORM public.claim_voice_relay_context(u, v_b);
    RAISE EXCEPTION 'FAIL %: a claim after the deadline was admitted', p_kind;
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'PRIVACY_REVISION_STALE' THEN RAISE; END IF;
  END;
  IF NOT (SELECT claimed_at IS NULL AND NOT context_claim_ok FROM public.voice_relay_reservations WHERE session_id = v_b) THEN
    RAISE EXCEPTION 'FAIL %: the refused claim left state behind', p_kind;
  END IF;
  IF EXISTS (SELECT 1 FROM public.monthly_ai_budget_receipts WHERE request_id = v_b) THEN
    RAISE EXCEPTION 'FAIL %: the refused claim reserved monthly budget', p_kind;
  END IF;
  -- A fresh admission after the deadline refuses the source.
  BEGIN
    PERFORM public.prepare_voice_relay_context(u, sess, conv, 'personalized', v_priv, repeat('d', 64), 1000,
      'openai', 'gpt-realtime-2.1-mini', 'voice-relay-1', v_sources, '[]'::jsonb);
    RAISE EXCEPTION 'FAIL %: a preparation after the deadline was admitted', p_kind;
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'PRIVACY_REVISION_STALE' THEN RAISE; END IF;
  END;
  PERFORM public.finalize_voice_relay(v_a, 0, false);
END $$;
RESET ROLE;
SELECT pg_temp.time_case('expiry');
SELECT pg_temp.time_case('review');
SELECT pg_temp.time_case('default_review');

-- ===================== MESSAGES: exact cited versions (MF-M6S-004) =====================
-- A cited turn is bound to its M3 messages.content_revision. A same-id rewrite, re-role,
-- re-origin, move or delete advances the version (or removes the row) WITHOUT moving the
-- privacy revision, so only the version comparison can notice. An unrelated new message must
-- not invalidate anything.
CREATE OR REPLACE FUNCTION pg_temp.message_case(p_kind text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  u constant uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  sess constant uuid := '61000000-0000-4000-8000-000000000001';
  conv constant uuid := 'cccccccc-0000-4000-8000-000000000001';
  other_conv constant uuid := 'cccccccc-0000-4000-8000-000000000003';
  msg uuid := gen_random_uuid(); v_priv bigint; v_srev bigint; v_sources jsonb;
  v_a uuid; v_b uuid; v_check jsonb; v_msg text;
BEGIN
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  UPDATE public.voice_relay_reservations SET prepared_at = prepared_at - interval '10 minutes';
  PERFORM public.finalize_voice_relay(session_id, 0, false)
    FROM public.voice_relay_reservations WHERE claimed_at IS NOT NULL AND finalized_at IS NULL;
  INSERT INTO public.messages (id, conversation_id, role, content)
    VALUES (msg, conv, 'assistant', 'synthetic cited turn');
  IF (SELECT content_revision FROM public.messages WHERE id = msg) <> 0 THEN
    RAISE EXCEPTION 'FAIL %: a new message must start at version 0', p_kind;
  END IF;
  SELECT privacy_revision INTO v_priv FROM public.support_privacy_state WHERE user_id = u;
  SELECT context_revision INTO v_srev FROM public.support_work_sessions WHERE id = sess;
  v_sources := jsonb_build_array(
    jsonb_build_object('kind', 'safety_policy', 'id', '00000000-0000-0000-0000-000000000001', 'revision', 1, 'date', NULL),
    jsonb_build_object('kind', 'session', 'id', sess, 'revision', v_srev, 'date', NULL),
    jsonb_build_object('kind', 'message', 'id', msg, 'revision', 0, 'date', NULL));

  v_a := (public.prepare_voice_relay_context(u, sess, conv, 'personalized', v_priv, repeat('a', 64), 1000,
    'openai', 'gpt-realtime-2.1-mini', 'voice-relay-1', v_sources, '[]'::jsonb) ->> 'session_id')::uuid;
  v_b := (public.prepare_voice_relay_context(u, sess, conv, 'personalized', v_priv, repeat('b', 64), 1000,
    'openai', 'gpt-realtime-2.1-mini', 'voice-relay-1', v_sources, '[]'::jsonb) ->> 'session_id')::uuid;
  PERFORM public.claim_voice_relay_context(u, v_a);
  v_check := public.voice_relay_context_check(u, v_a);
  IF v_check ->> 'ok' <> 'true' THEN RAISE EXCEPTION 'FAIL %: not current before any change: %', p_kind, v_check; END IF;

  -- CONTROL: an unrelated new turn moves neither the privacy revision nor the cited version.
  INSERT INTO public.messages (conversation_id, role, content) VALUES (conv, 'user', 'an unrelated later turn');
  IF (SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = u) <> v_priv
     OR (SELECT content_revision FROM public.messages WHERE id = msg) <> 0 THEN
    RAISE EXCEPTION 'FAIL %: an unrelated insert moved a revision', p_kind;
  END IF;
  v_check := public.voice_relay_context_check(u, v_a);
  IF v_check ->> 'ok' <> 'true' THEN RAISE EXCEPTION 'FAIL %: an unrelated insert invalidated the packet: %', p_kind, v_check; END IF;

  -- The change itself (as a retained legacy writer such as apply-rewrite would make it).
  IF p_kind = 'content' THEN UPDATE public.messages SET content = 'rewritten wording' WHERE id = msg;
  ELSIF p_kind = 'role' THEN UPDATE public.messages SET role = 'user' WHERE id = msg;
  ELSIF p_kind = 'origin' THEN UPDATE public.messages SET content_origin = 'interface_fallback' WHERE id = msg;
  ELSIF p_kind = 'move' THEN UPDATE public.messages SET conversation_id = other_conv WHERE id = msg;
  ELSIF p_kind = 'delete' THEN DELETE FROM public.messages WHERE id = msg;
  ELSE RAISE EXCEPTION 'unknown kind %', p_kind;
  END IF;
  IF (SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = u) <> v_priv THEN
    RAISE EXCEPTION 'FAIL %: a message change must not need a privacy bump', p_kind;
  END IF;
  IF p_kind <> 'delete' AND (SELECT content_revision FROM public.messages WHERE id = msg) <> 1 THEN
    RAISE EXCEPTION 'FAIL %: the M3 version did not advance', p_kind;
  END IF;

  -- 1. A live lease: the next refresh is not current.
  v_check := public.voice_relay_context_check(u, v_a);
  IF v_check ->> 'ok' <> 'false' OR v_check ->> 'code' <> 'PRIVACY_REVISION_STALE' THEN
    RAISE EXCEPTION 'FAIL %: a refresh still accepted the old version: %', p_kind, v_check;
  END IF;
  -- 2. A preparation made earlier cannot be claimed (and consumes nothing).
  BEGIN
    PERFORM public.claim_voice_relay_context(u, v_b);
    RAISE EXCEPTION 'FAIL %: the claim accepted the old version', p_kind;
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'PRIVACY_REVISION_STALE' THEN RAISE; END IF;
  END;
  IF NOT (SELECT claimed_at IS NULL AND NOT context_claim_ok FROM public.voice_relay_reservations WHERE session_id = v_b)
     OR EXISTS (SELECT 1 FROM public.monthly_ai_budget_receipts WHERE request_id = v_b) THEN
    RAISE EXCEPTION 'FAIL %: the refused claim left state behind', p_kind;
  END IF;
  -- 3. A new preparation that still cites the old version is refused.
  BEGIN
    PERFORM public.prepare_voice_relay_context(u, sess, conv, 'personalized', v_priv, repeat('c', 64), 1000,
      'openai', 'gpt-realtime-2.1-mini', 'voice-relay-1', v_sources, '[]'::jsonb);
    RAISE EXCEPTION 'FAIL %: prepare accepted the old version', p_kind;
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'PRIVACY_REVISION_STALE' THEN RAISE; END IF;
  END;
  PERFORM public.finalize_voice_relay(v_a, 0, false);
END $$;
RESET ROLE;
SELECT pg_temp.message_case('content');
SELECT pg_temp.message_case('role');
SELECT pg_temp.message_case('origin');
SELECT pg_temp.message_case('move');
SELECT pg_temp.message_case('delete');

-- Citation input: omitted/null revision means 0 (never "any"); malformed is refused; a turn the
-- caller does not own cannot be cited.
CREATE OR REPLACE FUNCTION pg_temp.message_input_case() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  u constant uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  sess constant uuid := '61000000-0000-4000-8000-000000000001';
  conv constant uuid := 'cccccccc-0000-4000-8000-000000000001';
  msg uuid := gen_random_uuid(); foreign_msg uuid := gen_random_uuid(); v_priv bigint; v_srev bigint;
  base jsonb; v_msg text; v_id uuid;
BEGIN
  PERFORM set_config('request.jwt.claim.role', 'service_role', true);
  UPDATE public.voice_relay_reservations SET prepared_at = prepared_at - interval '10 minutes';
  PERFORM public.finalize_voice_relay(session_id, 0, false)
    FROM public.voice_relay_reservations WHERE claimed_at IS NOT NULL AND finalized_at IS NULL;
  INSERT INTO public.messages (id, conversation_id, role, content) VALUES (msg, conv, 'assistant', 'synthetic cited turn');
  INSERT INTO public.messages (id, conversation_id, role, content)
    VALUES (foreign_msg, 'cccccccc-0000-4000-8000-000000000002', 'assistant', 'another account''s turn');
  SELECT privacy_revision INTO v_priv FROM public.support_privacy_state WHERE user_id = u;
  SELECT context_revision INTO v_srev FROM public.support_work_sessions WHERE id = sess;
  base := jsonb_build_array(
    jsonb_build_object('kind', 'safety_policy', 'id', '00000000-0000-0000-0000-000000000001', 'revision', 1, 'date', NULL),
    jsonb_build_object('kind', 'session', 'id', sess, 'revision', v_srev, 'date', NULL));
  -- Omitted revision == 0: accepted for a turn still at 0.
  v_id := (public.prepare_voice_relay_context(u, sess, conv, 'personalized', v_priv, repeat('a', 64), 1000,
    'openai', 'gpt-realtime-2.1-mini', 'voice-relay-1',
    base || jsonb_build_array(jsonb_build_object('kind', 'message', 'id', msg, 'date', NULL)), '[]'::jsonb) ->> 'session_id')::uuid;
  -- Malformed (non-integer, negative, string): refused, not coerced.
  FOREACH v_msg IN ARRAY ARRAY['1.5', '"x"', '-1', 'true'] LOOP
    BEGIN
      PERFORM public.prepare_voice_relay_context(u, sess, conv, 'personalized', v_priv, repeat('b', 64), 1000,
        'openai', 'gpt-realtime-2.1-mini', 'voice-relay-1',
        base || jsonb_build_array(jsonb_build_object('kind', 'message', 'id', msg, 'revision', v_msg::jsonb, 'date', NULL)), '[]'::jsonb);
      RAISE EXCEPTION 'FAIL malformed revision % accepted', v_msg;
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> 'INVALID_VOICE_CONTEXT' THEN RAISE; END IF;
    END;
  END LOOP;
  -- A turn in someone else's conversation cannot be cited, whatever version is named.
  BEGIN
    PERFORM public.prepare_voice_relay_context(u, sess, conv, 'personalized', v_priv, repeat('c', 64), 1000,
      'openai', 'gpt-realtime-2.1-mini', 'voice-relay-1',
      base || jsonb_build_array(jsonb_build_object('kind', 'message', 'id', foreign_msg, 'revision', 0, 'date', NULL)), '[]'::jsonb);
    RAISE EXCEPTION 'FAIL a foreign turn was cited';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'PRIVACY_REVISION_STALE' THEN RAISE; END IF;
  END;
END $$;
RESET ROLE;
SELECT pg_temp.message_input_case();

SELECT 'PASS: support_voice_context.sql' AS result;

/* ===================== TWO-CONNECTION LOCK-ORDER PROCEDURE (NOT RUN BY psql -f) =====================
Same conventions as supabase/tests/support_session_concurrency.spec: a disposable database after
this file's fixtures, two psql sessions A and B, each switched per step to service_role by
setting request.jwt.claim.role (see pg_temp.as_service above). "B waits" = the statement blocks
(pg_stat_activity.wait_event_type 'Lock'). PASS for every scenario = no SQLSTATE 40P01 anywhere,
both transactions finish, and the stated end state holds. Fixture ids: user A, session
61000000-0000-4000-8000-000000000001, conversation cccccccc-0000-4000-8000-000000000001, and a
fresh unclaimed context preparation P (prepare_voice_relay_context, wait out the 3/minute
window between runs). M3 writers are exercised through support_apply_mutation (discard) and
support_memory_mutate / direct companion_memory UPDATEs (legacy writer), as in that spec.

V1  prepare vs discard (the cycle the reviewer described), both orders
    A: BEGIN; SELECT support_apply_mutation(<discard_activity_answers on the session>);
       -- takes the write mutex, then privacy FOR UPDATE, then the session; left OPEN
    B: SELECT prepare_voice_relay_context(...);          -- B waits at the MUTEX (before any row lock)
    A: COMMIT.  B completes (ok or PRIVACY_REVISION_STALE per the bump); never 40P01.
    Reverse: B: BEGIN; SELECT prepare_voice_relay_context(...); -- holds mutex+privacy SHARE+session SHARE, OPEN
             A: SELECT support_apply_mutation(<discard...>);   -- A waits at the MUTEX, holds nothing
             B: COMMIT. A completes.  Neither order can hold the session while waiting for privacy.
V2  claim vs discard, both orders: as V1 with claim_voice_relay_context(P). In the reverse order B
    additionally holds the owner advisory lock, voice_sessions and reservation rows, none of which
    A (an M3 writer) ever requests.
V3  prepare/claim vs a legacy writer and vs suppression, both orders
    A: BEGIN; UPDATE companion_memory SET content = 'x' WHERE id = <cited memory>;  -- statement
       trigger takes the mutex, the guard bumps privacy
    B: SELECT claim_voice_relay_context(P);   -- waits at the mutex.   A: COMMIT -> B: PRIVACY_REVISION_STALE.
    Reverse with support_memory_mutate(<suppress_source>) while B holds the claim open.
V4  voice family unaffected: A: BEGIN; SELECT finalize_voice_relay(<other active session>, 0, false);
    B: SELECT claim_voice_relay_context(P2);  -- B holds the mutex, waits on the owner/global lock
    A: COMMIT -> B continues.  An M3 writer C started meanwhile queues behind B's mutex only and
    both finish (finalize never requests the mutex, so there is no cycle).
V5  deadline crossed while waiting for the mutex (wall clock, not transaction start)
    Setup: a cited memory E with expires_at = clock_timestamp() + 8 s (edit BEFORE preparing, then
    prepare P citing E at its current revision and the current privacy revision).
    A: BEGIN; SELECT support_acquire_write_mutex();   -- hold it
    B: SELECT claim_voice_relay_context(P);            -- starts before the deadline, waits
    wait 10 s.   A: COMMIT.  Expect B: PRIVACY_REVISION_STALE although E's revision never changed.
V6  refresh is never blocked: A: BEGIN; SELECT support_acquire_write_mutex(); (open)
    B: SELECT voice_relay_context_check(<claimed session>);  -- returns immediately (<50 ms)
    while A holds the mutex and a privacy FOR UPDATE.

V7  FINAL eligibility boundary: a source deadline crossed while the claim waits on the GLOBAL
    voice lock (MF-M6S-002). Reproduces the reviewed schedule with real locks.
    Setup (psql session S, then exit; $DB, service role via request.jwt.claim.role):
      -- memory E that expires 4 s from now (insert it FIRST so its privacy bump precedes the read)
      SELECT set_config('request.jwt.claim.role','service_role',false);
      INSERT INTO companion_memory (id,user_id,category,content,expires_at)
        VALUES ('d0000000-0000-4000-8000-0000000000e7','aaaaaaaa-0000-4000-8000-000000000001',
                'boundaries','synthetic V7 boundary', clock_timestamp() + interval '4 seconds');
      -- prepare P citing E (kinds: safety_policy, session at its context_revision, companion_memory
      -- at revision 1) at the CURRENT privacy revision; \gset the returned session_id as :p
      -- (age earlier preparations out of the 3/minute window first, as in pg_temp.time_case)
    Then, within the 4 s window, three shell jobs:
      A.sql: BEGIN; SELECT pg_advisory_xact_lock(76544, 1); SELECT pg_sleep(5); COMMIT;
             -- holds the global voice lock for 5 s (a concurrent claim/finalize in its global step)
      B.sql: SELECT set_config('request.jwt.claim.role','service_role',false);
             SELECT pg_sleep(0.5);
             SELECT public.claim_voice_relay_context('aaaaaaaa-0000-4000-8000-000000000001', :'p');
      psql -X -d $DB -f A.sql & psql -X -v p=<P> -d $DB -f B.sql ; wait
    While B waits (checkable from a third session, around t=1..4 s):
      SELECT wait_event_type, wait_event FROM pg_stat_activity WHERE query LIKE '%claim_voice_relay_context%'
        AND pid <> pg_backend_pid();                    -- Lock / advisory
      SELECT 1 FROM pg_locks WHERE locktype='advisory' AND classid=76544 AND objid=1 AND NOT granted;  -- 1 row
    Expect: B's first eligibility check (t~0.5 s, before E's deadline) PASSES, B blocks inside
      claim_voice_relay at (76544,1) until A commits at ~5 s, E has expired in the meantime, and B
      ends with  ERROR: PRIVACY_REVISION_STALE  (no 40P01). End state, from a third session:
      SELECT claimed_at IS NULL, context_claim_ok, finalized_at IS NULL FROM voice_relay_reservations
        WHERE session_id = :'p';                                              -- t, f, t
      SELECT count(*) FROM monthly_ai_budget_receipts WHERE request_id = :'p';  -- 0 (debit rolled back)
      SELECT count(*) FROM voice_relay_reservations WHERE claimed_at IS NOT NULL AND finalized_at IS NULL;  -- as before
      voice_sessions.ended_at for :'p' still NULL. The privacy revision is unchanged throughout.
    Control: repeat with expires_at = clock_timestamp() + interval '60 seconds'. B succeeds after A
      commits (claimed, monthly receipt present), proving the refusal above was the deadline.
V8  The same crossing inside the MONTHLY budget wait. Replace A.sql with either independent hold:
      (a) BEGIN; SELECT pg_advisory_xact_lock(624130, 1); SELECT pg_sleep(5); COMMIT;
          -- B takes the global lock (76544,1) first, then waits at (624130,1)
      (b) BEGIN; SELECT * FROM monthly_ai_budget_months
            WHERE month_start = date_trunc('month', timezone('America/New_York', clock_timestamp()))::date
            FOR UPDATE; SELECT pg_sleep(5); COMMIT;   -- B takes (624130,1), then waits on the month row
    Same expectations and end state as V7 (including: while B waits it HOLDS the global voice lock, so a
    concurrent voice claim by another account queues behind it and then proceeds - verify no 40P01).
V9  message rewrite/delete versus voice admission at the write mutex, both orders
    Setup: a cited message M (assistant turn in the session's conversation, version 0) and a
    preparation P citing it at revision 0.
    A: BEGIN; UPDATE messages SET content = 'rewritten' WHERE id = M;   -- statement trigger takes the
       mutex; content_revision becomes 1; privacy revision unchanged; leave OPEN
    B: SELECT claim_voice_relay_context(<user>, P);     -- waits at the MUTEX (before any row lock)
    A: COMMIT.  B returns PRIVACY_REVISION_STALE; nothing claimed.
    Reverse: B: BEGIN; SELECT claim_voice_relay_context(<user>, P);  -- holds mutex and shares M; OPEN
       A: UPDATE messages SET content = 'rewritten' WHERE id = M;    -- waits at the mutex
       B: COMMIT (claim succeeds at version 0).  A completes; the NEXT voice_relay_context_check is
       not current (the lease would end within its 2 s refresh), and the privacy revision never moved.
    FK cascade: B holds an open claim as above; A: DELETE FROM conversations WHERE id = <the conversation>
       (cascade bypasses the statement trigger but must wait for B's FOR SHARE OF ms on M) -> A waits
       until B commits.  Run on a disposable copy of the fixture conversation only.
*/
