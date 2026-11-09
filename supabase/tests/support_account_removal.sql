-- Account-removal regression for 20261107070000_support_account_removal.sql.
-- NOT EXECUTED by its author. Reaching the final \echo means every assertion above it passed;
-- nothing in this file is a recorded result.
--
-- RUN ONLY in an explicitly owned, disposable, network-none database named
-- support_account_removal_synthetic, as its owner/superuser, after the full migration chain INCLUDING
-- 20261107070000. It creates (and refuses to reuse) the scratch schema support_account_removal_test,
-- seeds three SYNTHETIC auth users and deletes one of them through the REAL auth.users FK cascade.
-- No production data, provider, network or real account is involved. Drop the database afterwards.
\set ON_ERROR_STOP on

DO $$ BEGIN
  IF current_database() <> 'support_account_removal_synthetic' THEN
    RAISE EXCEPTION 'refusing to run: database must be support_account_removal_synthetic (disposable)';
  END IF;
  IF to_regnamespace('support_account_removal_test') IS NOT NULL THEN
    RAISE EXCEPTION 'refusing to run: scratch schema support_account_removal_test already exists';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t
      WHERE t.tgrelid = 'auth.users'::regclass AND NOT t.tgisinternal
        AND t.tgfoid = 'public.support_write_mutex_statement()'::regprocedure
        AND (t.tgtype & 1) = 0 AND (t.tgtype & 2) = 2 AND (t.tgtype & 8) = 8 AND t.tgenabled <> 'D') THEN
    RAISE EXCEPTION 'auth.users BEFORE DELETE statement mutex trigger is not installed';
  END IF;
END $$;

CREATE SCHEMA support_account_removal_test;

CREATE FUNCTION support_account_removal_test.eq(actual anyelement, expected anyelement, label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF actual IS DISTINCT FROM expected THEN
    RAISE EXCEPTION 'FAIL %: got %, want %', label, actual, expected;
  END IF;
END $$;

CREATE TABLE support_account_removal_test.ids (tag text, k text, v uuid, PRIMARY KEY (tag, k));
CREATE TABLE support_account_removal_test.snap (tag text PRIMARY KEY, v text);

-- Hash of every public row owned by user u (any table with a user_id column) plus the messages of
-- u's conversations. Used for the "other owner is byte-identical" assertion.
CREATE FUNCTION support_account_removal_test.snapshot(u uuid) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE t record; acc text := ''; part text;
BEGIN
  FOR t IN SELECT c.table_name FROM information_schema.columns c
           JOIN information_schema.tables tb ON tb.table_schema = c.table_schema AND tb.table_name = c.table_name AND tb.table_type = 'BASE TABLE'
           WHERE c.table_schema = 'public' AND c.column_name = 'user_id' ORDER BY c.table_name LOOP
    EXECUTE format('SELECT coalesce(string_agg(x::text, ''|'' ORDER BY x::text), '''') FROM public.%I x WHERE x.user_id = $1', t.table_name) INTO part USING u;
    acc := acc || t.table_name || ':' || md5(part) || ';';
  END LOOP;
  SELECT coalesce(string_agg(m::text, '|' ORDER BY m::text), '') INTO part
    FROM public.messages m JOIN public.conversations cv ON cv.id = m.conversation_id WHERE cv.user_id = u;
  RETURN acc || 'messages:' || md5(part);
END $$;

-- Names of public tables that still hold rows for u ('' when none).
CREATE FUNCTION support_account_removal_test.remaining(u uuid) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE t record; n bigint; acc text := '';
BEGIN
  FOR t IN SELECT c.table_name FROM information_schema.columns c
           JOIN information_schema.tables tb ON tb.table_schema = c.table_schema AND tb.table_name = c.table_name AND tb.table_type = 'BASE TABLE'
           WHERE c.table_schema = 'public' AND c.column_name = 'user_id' ORDER BY c.table_name LOOP
    EXECUTE format('SELECT count(*) FROM public.%I x WHERE x.user_id = $1', t.table_name) INTO n USING u;
    IF n > 0 THEN acc := acc || t.table_name || '=' || n || ' '; END IF;
  END LOOP;
  SELECT count(*) INTO n FROM public.messages m JOIN public.conversations cv ON cv.id = m.conversation_id WHERE cv.user_id = u;
  IF n > 0 THEN acc := acc || 'messages=' || n; END IF;
  RETURN acc;
END $$;

-- Seeds one synthetic owner through the REAL write paths (legacy writers + M3 RPCs).
CREATE FUNCTION support_account_removal_test.seed_owner(u uuid, tag text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  c uuid := md5(tag || 'conv')::uuid;       m_src uuid := md5(tag || 'msrc')::uuid;     m_src2 uuid := md5(tag || 'msrc2')::uuid;
  mem_cited uuid := md5(tag || 'memc')::uuid; mem_other uuid := md5(tag || 'memo')::uuid; mem_legacy uuid := md5(tag || 'meml')::uuid;
  f_pend uuid := md5(tag || 'fp')::uuid;    f_leg uuid := md5(tag || 'fl')::uuid;       f_prom uuid := md5(tag || 'fq')::uuid;
  s uuid := md5(tag || 'sess')::uuid;       act uuid := md5(tag || 'act')::uuid;        req uuid := md5(tag || 'req')::uuid;
  r jsonb; priv bigint; mrev bigint;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', u::text, false);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, false);
  INSERT INTO public.conversations (id, user_id) VALUES (c, u);
  INSERT INTO public.messages (id, conversation_id, role, content) VALUES
    (m_src, c, 'user', 'source message ' || tag), (m_src2, c, 'user', 'second source ' || tag);
  -- ACTIVE curated memories (this is the shape that failed: an active row's guard DELETE path)
  INSERT INTO public.companion_memory (id, user_id, category, content) VALUES
    (mem_cited, u, 'preferences', 'cited memory ' || tag), (mem_other, u, 'boundaries', 'other memory ' || tag),
    (mem_legacy, u, 'preferences', 'legacy-delete memory ' || tag);
  -- pending + legacy-review candidates, and a PROMOTED pair created through the real approval RPC
  INSERT INTO public.memory_fragments (id, user_id, fragment_type, key, value, review_state, source_message_id)
    VALUES (f_pend, u, 'fact', 'kp', 'pending candidate ' || tag, 'pending', m_src);
  INSERT INTO public.memory_fragments (id, user_id, fragment_type, key, value, source_conversation_id)
    VALUES (f_leg, u, 'fact', 'kl', 'legacy review ' || tag, c);
  INSERT INTO public.memory_fragments (id, user_id, fragment_type, key, value, review_state, source_message_id)
    VALUES (f_prom, u, 'preference', 'kq', 'to promote ' || tag, 'pending', m_src2);
  r := public.support_memory_mutate(jsonb_build_object('schema_version', 1, 'operation_id', md5(tag || 'op1')::uuid,
        'kind', 'candidate_approve', 'payload', jsonb_build_object('fragment_id', f_prom)));
  IF r ->> 'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'seed approve failed: %', r; END IF;
  INSERT INTO public.daily_intents (id, user_id, intent) VALUES (md5(tag || 'di')::uuid, u, 'intent ' || tag);
  -- session + activity through the real RPC
  r := public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', md5(tag || 'op2')::uuid, 'session_id', s,
        'expected_revision', NULL, 'kind', 'create', 'payload', jsonb_build_object('title', 'seed ' || tag, 'context_scope', 'personalized', 'conversation_id', c)));
  IF r ->> 'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'seed session failed: %', r; END IF;
  r := public.support_apply_mutation(jsonb_build_object('schema_version', 1, 'operation_id', md5(tag || 'op3')::uuid, 'session_id', s,
        'expected_revision', 1, 'kind', 'start_activity', 'payload', jsonb_build_object('activity_id', act, 'template_key', 'untangle_thought_v1')));
  IF r ->> 'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'seed activity failed: %', r; END IF;
  -- a confirmed assistant turn (receipt + derived message) that cites mem_cited
  INSERT INTO public.chat_requests (user_id, request_id, conversation_id, content_hash) VALUES (u, req, c, 'h-' || tag);
  SELECT privacy_revision INTO priv FROM public.support_privacy_state WHERE user_id = u;
  SELECT revision INTO mrev FROM public.companion_memory WHERE id = mem_cited;
  r := public.support_confirm_chat_turn(jsonb_build_object('user_id', u, 'request_id', req, 'conversation_id', c, 'support_session_id', s,
        'assistant_content', 'derived reply ' || tag, 'content_origin', 'model', 'content_hash', 'h-' || tag, 'privacy_revision', priv,
        'scope', 'personalized', 'provider_vendor', 'openai', 'provider_model', 'synthetic', 'route_version', 'r1',
        'response', '{"ok":true}'::jsonb, 'response_status', 200,
        'sources', jsonb_build_array(jsonb_build_object('kind', 'companion_memory', 'id', mem_cited, 'revision', mrev))));
  IF r ->> 'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'seed confirm failed: %', r; END IF;
  INSERT INTO support_account_removal_test.ids VALUES (tag, 'derived_message', (r ->> 'message_id')::uuid), (tag, 'mem_cited', mem_cited),
    (tag, 'mem_other', mem_other), (tag, 'mem_legacy', mem_legacy), (tag, 'conv', c);
  -- ordinary Forget of a DIFFERENT memory leaves real suppression rows / memory events / privacy operations for this owner
  r := public.support_memory_mutate(jsonb_build_object('schema_version', 1, 'operation_id', md5(tag || 'op4')::uuid,
        'kind', 'memory_forget', 'payload', jsonb_build_object('memory_id', mem_other)));
  IF r ->> 'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'seed forget failed: %', r; END IF;
END $$;

-- ===================== FIXTURE: synthetic accounts =====================
INSERT INTO public.supported_languages (code, name, native_name, is_active) VALUES ('en', 'English', 'English', true) ON CONFLICT DO NOTHING;
INSERT INTO public.level_thresholds (level, xp_required, title) VALUES (1, 0, 'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO public.skill_thresholds (level, xp_required, title) VALUES (1, 0, 'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO auth.users (id, aud, role, email) VALUES
  ('a1111111-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'removed@example.invalid'),
  ('b2222222-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'kept@example.invalid'),
  ('c3333333-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'control@example.invalid');
INSERT INTO public.user_stats (user_id) VALUES
  ('a1111111-0000-4000-8000-000000000001'), ('b2222222-0000-4000-8000-000000000002'), ('c3333333-0000-4000-8000-000000000003')
  ON CONFLICT DO NOTHING;

SELECT support_account_removal_test.seed_owner('a1111111-0000-4000-8000-000000000001', 'u1');
SELECT support_account_removal_test.seed_owner('b2222222-0000-4000-8000-000000000002', 'u2');
SELECT support_account_removal_test.seed_owner('c3333333-0000-4000-8000-000000000003', 'u3');

-- the owner to be removed really has rows in every new table the cascade must clear
SELECT support_account_removal_test.eq((SELECT count(*) FROM public.companion_memory WHERE user_id = 'a1111111-0000-4000-8000-000000000001' AND deleted_at IS NULL)::int >= 3, true, 'u1 has active curated memories');
SELECT support_account_removal_test.eq((SELECT count(*) FROM public.memory_fragments WHERE user_id = 'a1111111-0000-4000-8000-000000000001')::int >= 3, true, 'u1 has pending, legacy and promoted fragments');
SELECT support_account_removal_test.eq((SELECT count(*) FROM public.support_suppressions WHERE user_id = 'a1111111-0000-4000-8000-000000000001')::int >= 1, true, 'u1 has suppression rows');
SELECT support_account_removal_test.eq((SELECT count(*) FROM public.support_privacy_state WHERE user_id = 'a1111111-0000-4000-8000-000000000001')::int, 1, 'u1 has a privacy row');
SELECT support_account_removal_test.eq((SELECT count(*) FROM public.support_context_receipts WHERE user_id = 'a1111111-0000-4000-8000-000000000001')::int, 1, 'u1 has a receipt');
SELECT support_account_removal_test.eq((SELECT count(*) FROM public.support_mutation_receipts WHERE user_id = 'a1111111-0000-4000-8000-000000000001')::int >= 2, true, 'u1 has operation receipts');
SELECT support_account_removal_test.eq((SELECT count(*) FROM public.support_activities WHERE user_id = 'a1111111-0000-4000-8000-000000000001')::int, 1, 'u1 has an activity');
SELECT support_account_removal_test.eq((SELECT count(*) FROM public.daily_intents WHERE user_id = 'a1111111-0000-4000-8000-000000000001')::int, 1, 'u1 has a daily intent');

INSERT INTO support_account_removal_test.snap
  SELECT 'u2', support_account_removal_test.snapshot('b2222222-0000-4000-8000-000000000002');
INSERT INTO support_account_removal_test.snap
  SELECT 'u3', support_account_removal_test.snapshot('c3333333-0000-4000-8000-000000000003');

-- ===================== ACCOUNT REMOVAL through the REAL FK cascade =====================
DELETE FROM auth.users WHERE id = 'a1111111-0000-4000-8000-000000000001';

SELECT support_account_removal_test.eq((SELECT count(*) FROM auth.users WHERE id = 'a1111111-0000-4000-8000-000000000001')::int, 0, 'owner removed');
SELECT support_account_removal_test.eq(support_account_removal_test.remaining('a1111111-0000-4000-8000-000000000001'), '', 'no public row of the removed owner remains (incl. messages)');
SELECT support_account_removal_test.eq((SELECT count(*) FROM public.conversations WHERE id = (SELECT v FROM support_account_removal_test.ids WHERE tag = 'u1' AND k = 'conv'))::int, 0, 'owner conversation gone');
SELECT support_account_removal_test.eq((SELECT count(*) FROM public.messages WHERE id = (SELECT v FROM support_account_removal_test.ids WHERE tag = 'u1' AND k = 'derived_message'))::int, 0, 'derived message gone');
-- no suppression / tombstone / privacy / event / operation row keyed to a vanished owner, anywhere
SELECT support_account_removal_test.eq(
  (SELECT count(*) FROM public.support_suppressions x WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = x.user_id))
+ (SELECT count(*) FROM public.support_privacy_state x WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = x.user_id))
+ (SELECT count(*) FROM public.support_privacy_operations x WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = x.user_id))
+ (SELECT count(*) FROM public.support_memory_events x WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = x.user_id))
+ (SELECT count(*) FROM public.support_mutation_receipts x WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = x.user_id)), 0::bigint,
  'no ownerless suppression/tombstone/privacy/event/operation rows');

-- the other owners are byte-identical (rows and content)
SELECT support_account_removal_test.eq(support_account_removal_test.snapshot('b2222222-0000-4000-8000-000000000002'), (SELECT v FROM support_account_removal_test.snap WHERE tag = 'u2'), 'other owner untouched');
SELECT support_account_removal_test.eq(support_account_removal_test.snapshot('c3333333-0000-4000-8000-000000000003'), (SELECT v FROM support_account_removal_test.snap WHERE tag = 'u3'), 'control owner untouched');
SELECT support_account_removal_test.eq((SELECT content FROM public.companion_memory WHERE id = (SELECT v FROM support_account_removal_test.ids WHERE tag = 'u2' AND k = 'mem_cited')), 'cited memory u2', 'other owner memory content exact');

-- ===================== POSITIVE CONTROLS: owner EXISTS -> exact suppression behavior is unchanged =====================
-- (a) RPC Forget of the memory that a confirmed assistant turn cited: the derived turn is suppressed
CREATE TABLE support_account_removal_test.pc AS
  SELECT privacy_revision AS before_rev FROM public.support_privacy_state WHERE user_id = 'c3333333-0000-4000-8000-000000000003';
SELECT set_config('request.jwt.claim.sub', 'c3333333-0000-4000-8000-000000000003', false);
SELECT set_config('request.jwt.claims', '{"sub":"c3333333-0000-4000-8000-000000000003","role":"authenticated"}', false);
SELECT support_account_removal_test.eq((public.support_memory_mutate(jsonb_build_object('schema_version', 1, 'operation_id', 'd3333333-0000-4000-8000-0000000000a1',
  'kind', 'memory_forget', 'payload', jsonb_build_object('memory_id', (SELECT v FROM support_account_removal_test.ids WHERE tag = 'u3' AND k = 'mem_cited'))))) ->> 'ok', 'true', 'owner-present Forget succeeds');
SELECT support_account_removal_test.eq((SELECT count(*) FROM public.companion_memory WHERE id = (SELECT v FROM support_account_removal_test.ids WHERE tag = 'u3' AND k = 'mem_cited'))::int, 0, 'memory hard-removed');
SELECT support_account_removal_test.eq((SELECT count(*) FROM public.support_suppressions WHERE user_id = 'c3333333-0000-4000-8000-000000000003' AND kind = 'memory'
   AND ref_id = (SELECT v FROM support_account_removal_test.ids WHERE tag = 'u3' AND k = 'mem_cited'))::int, 1, 'memory suppression recorded');
SELECT support_account_removal_test.eq((SELECT count(*) FROM public.support_suppressions WHERE user_id = 'c3333333-0000-4000-8000-000000000003' AND kind = 'message'
   AND ref_id = (SELECT v FROM support_account_removal_test.ids WHERE tag = 'u3' AND k = 'derived_message'))::int, 1, 'derived assistant message suppressed');
SELECT support_account_removal_test.eq((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = 'c3333333-0000-4000-8000-000000000003') > (SELECT before_rev FROM support_account_removal_test.pc), true, 'privacy revision advanced');
-- (b) retained LEGACY direct DELETE of an active memory while the owner exists still suppresses it
DELETE FROM public.companion_memory WHERE id = (SELECT v FROM support_account_removal_test.ids WHERE tag = 'u3' AND k = 'mem_legacy');
SELECT support_account_removal_test.eq((SELECT count(*) FROM public.support_suppressions WHERE user_id = 'c3333333-0000-4000-8000-000000000003' AND kind = 'memory'
   AND ref_id = (SELECT v FROM support_account_removal_test.ids WHERE tag = 'u3' AND k = 'mem_legacy'))::int, 1, 'legacy DELETE with an existing owner is still a suppressed Forget');
-- (c) fragment path with an existing owner: forgetting a promoted fragment still removes its canonical memory
SELECT support_account_removal_test.eq((public.support_memory_mutate(jsonb_build_object('schema_version', 1, 'operation_id', 'd3333333-0000-4000-8000-0000000000a2',
  'kind', 'memory_forget', 'payload', jsonb_build_object('fragment_id', md5('u3fq')::uuid)))) ->> 'ok', 'true', 'owner-present promoted fragment Forget succeeds');
SELECT support_account_removal_test.eq((SELECT count(*) FROM public.companion_memory WHERE approved_from_fragment_id = md5('u3fq')::uuid)::int, 0, 'its canonical memory is removed too');

\echo 'support_account_removal.sql: reached end - every assertion above passed (this file has NOT been executed by its author)'

-- =====================================================================================================
-- DOCUMENTED TWO-CONNECTION SCHEDULE for the auth.users parent-row / mutex cycle (NOT EXECUTED; the parent
-- stages it in an owned synthetic network-none database). Account U is any existing synthetic auth user
-- with a support_privacy_state row absent (so the writer's INSERT needs the auth FK key-share lock).
--
-- WITH the trigger aaa_support_write_mutex_auth_users_trg (expected, PASS):
--   A: BEGIN; SELECT public.support_acquire_write_mutex();            -- A holds the private mutex (owner role)
--   B: DELETE FROM auth.users WHERE id = U;                           -- B blocks in the BEFORE DELETE STATEMENT trigger.
--        Expected locks: B waits on the advisory lock (pg_locks locktype='advisory', granted=false);
--        B holds NO tuple/row lock on auth.users (verify: no pg_locks locktype='tuple' for B, and
--        SELECT ... FROM auth.users WHERE id=U FOR UPDATE NOWAIT from a third session succeeds).
--   A: INSERT INTO public.support_privacy_state (user_id) VALUES (U); -- needs FOR KEY SHARE on the auth row: granted
--   A: COMMIT;                                                        -- releases the mutex
--   B: proceeds; cascade runs; the DELETE commits. No SQLSTATE 40P01 on either connection.
--
-- NEGATIVE CONTROL (disposable DB only): ALTER TABLE auth.users DISABLE TRIGGER aaa_support_write_mutex_auth_users_trg;
--   B: BEGIN; DELETE FROM auth.users WHERE id = U;                    -- B takes the auth row exclusively; the first cascaded
--                                                                     --   child DELETE statement waits at its own mutex trigger
--        (start B FIRST, then A:)
--   A: BEGIN; SELECT public.support_acquire_write_mutex();            -- NOTE: if B already holds the mutex inside its cascade
--   A: INSERT INTO public.support_privacy_state (user_id) VALUES (U); -- needs the key-share lock B's DELETE blocks
--        Expected: exactly one of A/B is aborted with SQLSTATE 40P01 (deadlock detected) -- the cycle the trigger removes.
--   Re-enable: ALTER TABLE auth.users ENABLE TRIGGER aaa_support_write_mutex_auth_users_trg;
-- =====================================================================================================
