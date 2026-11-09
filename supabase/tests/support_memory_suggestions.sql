-- SQL assertions for 20261107080000_support_memory_suggestions.sql (spec 8.4).
--
-- AUTHORED, NOT EXECUTED by its author. DISPOSABLE SYNTHETIC DATABASE ONLY, network-none, never a
-- shared or production database. Run as a superuser (postgres/supabase_admin) AFTER the full
-- chain: baseline schema, 20261106230000, 20261106230100, 20261106230200, 20261107070000 and the
-- migration under test. Assumptions about the chain (stated, not verified by the author):
--   * auth.users accepts INSERT (id) only and auth.uid() reads request.jwt.claim.sub or
--     request.jwt.claims ->> 'sub' (true for Supabase and for the usual synthetic stub);
--   * roles anon / authenticated / service_role exist; public.messages has the baseline columns
--     (role message_role, is_ai_role_simulation) plus the support columns.
-- Everything runs inside one transaction that is ROLLED BACK; no real user data, provider, key,
-- network or worker is involved. Any failed assertion RAISEs and stops (ON_ERROR_STOP).
--   * public.profiles accepts the columns check_and_increment_ai_quota itself inserts (id, handle,
--     display_name, email, daily_ai_used, daily_ai_quota, quota_reset_at) and the existing
--     check_and_increment_ai_quota(uuid, boolean) function is present (the migration checks for it).
-- Concurrent interleavings (two sessions racing the mutex, the MS001 delete-vs-claim cycle) cannot
-- be expressed in a single script; the root harness adds the two-connection negative control. The
-- single-session cases below exercise the SAME validation code on each branch, and assert the
-- ACTUAL daily-quota counts in public.profiles (MS002), not a model of them.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL client_min_messages = warning;

CREATE FUNCTION pg_temp.expect(p_name text, p_ok boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'ASSERTION FAILED: %', p_name; END IF; END $$;
CREATE FUNCTION pg_temp.id(n integer) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true);
  PERFORM set_config('request.jwt.claims', CASE WHEN p_user IS NULL THEN '' ELSE jsonb_build_object('sub', p_user)::text END, true);
END $$;
CREATE FUNCTION pg_temp.priv(p_user uuid) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = p_user), 1) $$;
-- [{id, revision: CURRENT content_revision}] for message numbers (301..)
CREATE FUNCTION pg_temp.src(VARIADIC p_msgs integer[]) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_agg(jsonb_build_object('id', pg_temp.id(n),
    'revision', coalesce((SELECT content_revision FROM public.messages WHERE id = pg_temp.id(n)), 0)) ORDER BY n)
  FROM unnest(p_msgs) n $$;
CREATE FUNCTION pg_temp.claim(p_user uuid, p_req integer, p_session integer, p_conv integer, p_sources jsonb) RETURNS jsonb
LANGUAGE sql AS $$
  SELECT public.support_memory_suggestion_claim(p_user, pg_temp.id(p_req), pg_temp.id(p_session), pg_temp.id(p_conv),
                                                pg_temp.priv(p_user), p_sources) $$;
CREATE FUNCTION pg_temp.claim_at(p_user uuid, p_req integer, p_session integer, p_conv integer, p_priv bigint, p_sources jsonb) RETURNS jsonb
LANGUAGE sql AS $$
  SELECT public.support_memory_suggestion_claim(p_user, pg_temp.id(p_req), pg_temp.id(p_session), pg_temp.id(p_conv), p_priv, p_sources) $$;
CREATE FUNCTION pg_temp.used(p_user uuid) RETURNS integer LANGUAGE sql AS $$
  SELECT daily_ai_used FROM public.profiles WHERE id = p_user $$;
CREATE FUNCTION pg_temp.cand(p_type text, p_key text, p_value text, p_msg integer) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('fragment_type', p_type, 'key', p_key, 'value', p_value, 'source_message_id', pg_temp.id(p_msg)) $$;

-- ---------------------------------------------------------------------------
-- Fixtures (superuser, RLS bypassed): users 1-3, conversations 101-106, sessions 201-207
-- ---------------------------------------------------------------------------
INSERT INTO auth.users (id) VALUES (pg_temp.id(1)), (pg_temp.id(2)), (pg_temp.id(3));
-- Free-tier profiles with a generous daily quota so only the assertions below decide when it is exhausted.
INSERT INTO public.profiles (id, handle, display_name, email, daily_ai_used, daily_ai_quota, quota_reset_at) VALUES
  (pg_temp.id(1), 'ms_user_1', 'MS 1', 'ms1@example.test', 0, 100, now()),
  (pg_temp.id(2), 'ms_user_2', 'MS 2', 'ms2@example.test', 0, 100, now()),
  (pg_temp.id(3), 'ms_user_3', 'MS 3', 'ms3@example.test', 0, 100, now())
ON CONFLICT (id) DO UPDATE SET daily_ai_used = 0, daily_ai_quota = 100, quota_reset_at = now();
INSERT INTO public.conversations (id, user_id) VALUES
  (pg_temp.id(101), pg_temp.id(1)), (pg_temp.id(102), pg_temp.id(1)), (pg_temp.id(103), pg_temp.id(2)),
  (pg_temp.id(104), pg_temp.id(1)), (pg_temp.id(105), pg_temp.id(1)), (pg_temp.id(106), pg_temp.id(3));
INSERT INTO public.support_work_sessions (id, user_id, conversation_id, status, closed_at) VALUES
  (pg_temp.id(201), pg_temp.id(1), pg_temp.id(101), 'open', NULL),
  (pg_temp.id(202), pg_temp.id(2), pg_temp.id(103), 'open', NULL),
  (pg_temp.id(203), pg_temp.id(1), pg_temp.id(102), 'closed', now()),
  (pg_temp.id(204), pg_temp.id(1), NULL, 'open', NULL),
  (pg_temp.id(205), pg_temp.id(1), pg_temp.id(104), 'open', NULL),
  (pg_temp.id(206), pg_temp.id(1), pg_temp.id(105), 'open', NULL),
  (pg_temp.id(207), pg_temp.id(3), pg_temp.id(106), 'open', NULL);
INSERT INTO public.messages (id, conversation_id, role, content, content_origin) VALUES
  (pg_temp.id(301), pg_temp.id(101), 'user', 'My dog is named Max.', NULL),
  (pg_temp.id(302), pg_temp.id(101), 'user', 'I prefer short replies.', NULL),
  (pg_temp.id(303), pg_temp.id(101), 'assistant', 'That sounds hard. Zorblat.', 'model'),
  (pg_temp.id(304), pg_temp.id(102), 'user', 'A message in the closed session conversation.', NULL),
  (pg_temp.id(305), pg_temp.id(101), 'user', 'A message that will be suppressed.', NULL),
  (pg_temp.id(306), pg_temp.id(103), 'user', 'Another owner message.', NULL),
  (pg_temp.id(308), pg_temp.id(101), 'user', repeat('x', 4001), NULL),
  (pg_temp.id(309), pg_temp.id(101), 'assistant', 'Interface fallback text.', 'interface_fallback'),
  (pg_temp.id(310), pg_temp.id(102), 'user', 'Variant message A about Ana.', NULL),
  (pg_temp.id(311), pg_temp.id(102), 'user', 'Variant message B about Ben.', NULL),
  (pg_temp.id(312), pg_temp.id(102), 'user', 'Variant message C about Cy.', NULL),
  (pg_temp.id(313), pg_temp.id(102), 'user', 'Variant message D about Di.', NULL),
  (pg_temp.id(314), pg_temp.id(104), 'user', 'Message in a conversation whose session gets deleted.', NULL),
  (pg_temp.id(315), pg_temp.id(105), 'user', 'Key protection message one about Eve.', NULL),
  (pg_temp.id(316), pg_temp.id(105), 'user', 'Key protection message two about Finn.', NULL),
  (pg_temp.id(317), pg_temp.id(106), 'user', 'Message of the user who is deleted later.', NULL);
INSERT INTO public.messages (id, conversation_id, role, content, is_ai_role_simulation)
  VALUES (pg_temp.id(307), pg_temp.id(101), 'user', 'Role-play line, not the person speaking.', true);
SELECT public.support_ensure_privacy_state(pg_temp.id(1));
SELECT public.support_ensure_privacy_state(pg_temp.id(2));
SELECT public.support_ensure_privacy_state(pg_temp.id(3));

-- ---------------------------------------------------------------------------
-- 1. Structure, RLS and grants
-- ---------------------------------------------------------------------------
DO $$
DECLARE fn text;
BEGIN
  PERFORM pg_temp.expect('table has RLS enabled', (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.support_memory_suggestion_requests'::regclass));
  PERFORM pg_temp.expect('no client policy on the bookkeeping table',
    NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'support_memory_suggestion_requests'));
  PERFORM pg_temp.expect('anon/authenticated hold no table privilege',
    NOT has_table_privilege('anon', 'public.support_memory_suggestion_requests', 'SELECT,INSERT,UPDATE,DELETE')
    AND NOT has_table_privilege('authenticated', 'public.support_memory_suggestion_requests', 'SELECT')
    AND NOT has_table_privilege('authenticated', 'public.support_memory_suggestion_requests', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public.support_memory_suggestion_requests', 'UPDATE')
    AND NOT has_table_privilege('authenticated', 'public.support_memory_suggestion_requests', 'DELETE'));
  PERFORM pg_temp.expect('service_role keeps the table', has_table_privilege('service_role', 'public.support_memory_suggestion_requests', 'SELECT,INSERT,UPDATE,DELETE'));
  PERFORM pg_temp.expect('bookkeeping text columns are identity/status only',
    NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'support_memory_suggestion_requests'
                 AND data_type = 'text' AND column_name NOT IN ('payload_hash', 'status', 'failure_code')));
  FOR fn IN SELECT unnest(ARRAY[
      'public.support_memory_suggestion_claim(uuid,uuid,uuid,uuid,bigint,jsonb)',
      'public.support_memory_suggestion_dispatch(uuid,uuid,integer,jsonb,boolean)',
      'public.support_memory_suggestion_finish(uuid,uuid,integer,text,text)',
      'public.support_memory_suggestion_commit(uuid,uuid,integer,jsonb,jsonb)',
      'public.support_memory_suggestion_status(uuid,uuid)']) LOOP
    PERFORM pg_temp.expect('service_role only: ' || fn,
      has_function_privilege('service_role', fn, 'EXECUTE')
      AND NOT has_function_privilege('authenticated', fn, 'EXECUTE') AND NOT has_function_privilege('anon', fn, 'EXECUTE'));
  END LOOP;
  FOR fn IN SELECT unnest(ARRAY[
      'public.support_memory_suggestion_shape(jsonb)',
      'public.support_memory_suggestion_hash(uuid,uuid,bigint,jsonb)',
      'public.support_memory_suggestion_expire(uuid)',
      'public.support_memory_suggestion_validate(uuid,uuid,uuid,bigint,jsonb,boolean)',
      'public.support_memory_suggestion_result(public.support_memory_suggestion_requests)']) LOOP
    PERFORM pg_temp.expect('internal helper not callable by API roles: ' || fn,
      NOT has_function_privilege('authenticated', fn, 'EXECUTE') AND NOT has_function_privilege('anon', fn, 'EXECUTE'));
  END LOOP;
  PERFORM pg_temp.expect('preview RPC: authenticated yes, anon no',
    has_function_privilege('authenticated', 'public.support_memory_suggestion_sources(uuid,integer)', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.support_memory_suggestion_sources(uuid,integer)', 'EXECUTE'));
  PERFORM pg_temp.expect('definer functions pin search_path',
    (SELECT bool_and(p.prosecdef AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'))
       FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
        AND p.proname IN ('support_memory_suggestion_claim', 'support_memory_suggestion_dispatch', 'support_memory_suggestion_finish',
                          'support_memory_suggestion_commit', 'support_memory_suggestion_status', 'support_memory_suggestion_sources')));
END $$;

-- Runtime privilege denial (not just catalog): API roles cannot call the writers or read the table.
DO $$
DECLARE
  v_err text; v_u uuid := pg_temp.id(1); v_r uuid := pg_temp.id(401); v_s uuid := pg_temp.id(201); v_c uuid := pg_temp.id(101);
  v_src jsonb := jsonb_build_array(jsonb_build_object('id', pg_temp.id(301), 'revision', 0));
BEGIN
  -- Arguments are computed ABOVE, as the superuser: nothing here may fail merely because a restricted role cannot use pg_temp.
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.support_memory_suggestion_claim(v_u, v_r, v_s, v_c, 1, v_src);
    v_err := 'no error';
  EXCEPTION WHEN insufficient_privilege THEN v_err := 'denied'; END;
  RESET ROLE;
  PERFORM pg_temp.expect('authenticated cannot call claim', v_err = 'denied');
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM count(*) FROM public.support_memory_suggestion_requests;
    v_err := 'no error';
  EXCEPTION WHEN insufficient_privilege THEN v_err := 'denied'; END;
  RESET ROLE;
  PERFORM pg_temp.expect('authenticated cannot read the table', v_err = 'denied');
  SET LOCAL ROLE anon;
  BEGIN
    PERFORM public.support_memory_suggestion_sources(v_s, 20);
    v_err := 'no error';
  EXCEPTION WHEN insufficient_privilege THEN v_err := 'denied'; END;
  RESET ROLE;
  PERFORM pg_temp.expect('anon cannot call the preview', v_err = 'denied');
END $$;

-- ---------------------------------------------------------------------------
-- 2. Preview: read only, own USER messages of the session's conversation only
-- ---------------------------------------------------------------------------
DO $$
DECLARE v jsonb; v_ids uuid[]; v_reqs integer; v_frags integer; v_priv bigint := pg_temp.priv(pg_temp.id(1)); v_err text;
BEGIN
  SELECT count(*) INTO v_reqs FROM public.support_memory_suggestion_requests;
  SELECT count(*) INTO v_frags FROM public.memory_fragments;

  PERFORM pg_temp.as_user(pg_temp.id(1));
  v := public.support_memory_suggestion_sources(pg_temp.id(201), 20);
  PERFORM pg_temp.expect('preview ok', (v ->> 'ok')::boolean AND (v ->> 'session_status') = 'open');
  SELECT array_agg((m ->> 'id')::uuid ORDER BY m ->> 'created_at', m ->> 'id') INTO v_ids FROM jsonb_array_elements(v -> 'messages') m;
  PERFORM pg_temp.expect('preview lists only this conversation''s eligible USER messages (no assistant/interface/other conversation/other owner/suppression-eligible/too long)',
    v_ids @> ARRAY[pg_temp.id(301), pg_temp.id(302)]
    AND NOT (v_ids && ARRAY[pg_temp.id(303), pg_temp.id(304), pg_temp.id(306), pg_temp.id(307), pg_temp.id(308), pg_temp.id(309)]));
  PERFORM pg_temp.expect('preview reports the too-long exclusion by count', ((v -> 'excluded') ->> 'too_long')::integer = 1);
  PERFORM pg_temp.expect('preview binds the current privacy revision', (v ->> 'privacy_revision')::bigint = v_priv);
  PERFORM pg_temp.expect('preview rows carry the exact content revision', (SELECT bool_and((m ->> 'revision')::bigint = 0) FROM jsonb_array_elements(v -> 'messages') m));

  INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason) VALUES (pg_temp.id(1), 'message', pg_temp.id(305), 'user_source_exclusion');
  v := public.support_memory_suggestion_sources(pg_temp.id(201), 20);
  PERFORM pg_temp.expect('a suppressed message disappears from the preview and is counted',
    NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'messages') m WHERE (m ->> 'id')::uuid = pg_temp.id(305))
    AND ((v -> 'excluded') ->> 'suppressed')::integer = 1);

  v := public.support_memory_suggestion_sources(pg_temp.id(203), 20);
  PERFORM pg_temp.expect('a CLOSED session can be previewed', (v ->> 'ok')::boolean AND (v ->> 'session_status') = 'closed');
  v := public.support_memory_suggestion_sources(pg_temp.id(202), 20);
  PERFORM pg_temp.expect('another owner''s session is NOT_FOUND', NOT (v ->> 'ok')::boolean AND (v ->> 'code') = 'NOT_FOUND');
  v := public.support_memory_suggestion_sources(pg_temp.id(204), 20);
  PERFORM pg_temp.expect('a session without a conversation is unavailable, not fabricated',
    NOT (v ->> 'ok')::boolean AND (v ->> 'code') = 'CONTENT_UNAVAILABLE' AND (v ->> 'message') = 'no_conversation');
  v := public.support_memory_suggestion_sources(pg_temp.id(299), 20);
  PERFORM pg_temp.expect('an unknown session is NOT_FOUND', (v ->> 'code') = 'NOT_FOUND');

  PERFORM pg_temp.as_user(NULL);
  BEGIN
    PERFORM public.support_memory_suggestion_sources(pg_temp.id(201), 20);
    v_err := 'no error';
  EXCEPTION WHEN insufficient_privilege THEN v_err := 'denied'; END;
  PERFORM pg_temp.expect('unauthenticated preview raises AUTH_REQUIRED (42501)', v_err = 'denied');
  PERFORM pg_temp.expect('preview wrote nothing', (SELECT count(*) FROM public.support_memory_suggestion_requests) = v_reqs
    AND (SELECT count(*) FROM public.memory_fragments) = v_frags);
  DELETE FROM public.support_suppressions WHERE user_id = pg_temp.id(1) AND ref_id = pg_temp.id(305);
END $$;

-- ---------------------------------------------------------------------------
-- 3. Claim: replay-first, validation, one running request per session
-- ---------------------------------------------------------------------------
DO $$
DECLARE v jsonb; v2 jsonb; v_hash text; v_priv bigint := pg_temp.priv(pg_temp.id(1)); v_n integer;
BEGIN
  v := pg_temp.claim(pg_temp.id(1), 401, 201, 101, pg_temp.src(301, 302));
  PERFORM pg_temp.expect('first claim proceeds as attempt 1 with the bound message text',
    (v ->> 'ok')::boolean AND (v ->> 'action') = 'proceed' AND (v ->> 'attempt')::integer = 1 AND jsonb_array_length(v -> 'sources') = 2
    AND (v -> 'sources' -> 0 ->> 'content') IS NOT NULL);
  SELECT payload_hash INTO v_hash FROM public.support_memory_suggestion_requests WHERE request_id = pg_temp.id(401);
  PERFORM pg_temp.expect('request row is claimed with a sha256 identity hash', v_hash ~ '^[0-9a-f]{64}$'
    AND (SELECT status FROM public.support_memory_suggestion_requests WHERE request_id = pg_temp.id(401)) = 'claimed');

  v := pg_temp.claim(pg_temp.id(1), 401, 201, 101, pg_temp.src(302, 301));   -- same set, other order
  PERFORM pg_temp.expect('identical claim while running is pending (order is not identity), never proceeds again', (v ->> 'action') = 'pending');
  v := pg_temp.claim(pg_temp.id(1), 401, 201, 101, pg_temp.src(301));
  PERFORM pg_temp.expect('same id + different selection is OPERATION_ID_REUSED', (v ->> 'code') = 'OPERATION_ID_REUSED');
  v := public.support_memory_suggestion_claim(pg_temp.id(1), pg_temp.id(401), pg_temp.id(201), pg_temp.id(101), v_priv + 1, pg_temp.src(301, 302));
  PERFORM pg_temp.expect('same id + different privacy revision is OPERATION_ID_REUSED', (v ->> 'code') = 'OPERATION_ID_REUSED');
  v := pg_temp.claim(pg_temp.id(1), 402, 201, 101, pg_temp.src(301));
  PERFORM pg_temp.expect('a second request for the same session cannot start parallel work',
    (v ->> 'code') = 'TEMPORARY_FAILURE' AND (v ->> 'message') = 'generation_in_progress'
    AND NOT EXISTS (SELECT 1 FROM public.support_memory_suggestion_requests WHERE request_id = pg_temp.id(402)));

  -- Validation failures (checked before the busy check, so they are visible while 401 is running).
  v := pg_temp.claim(pg_temp.id(1), 403, 201, 101, pg_temp.src(303));
  PERFORM pg_temp.expect('assistant message rejected', (v ->> 'code') = 'CONTENT_UNAVAILABLE' AND (v ->> 'message') = 'ineligible_source');
  v := pg_temp.claim(pg_temp.id(1), 403, 201, 101, pg_temp.src(309));
  PERFORM pg_temp.expect('interface-fallback message rejected', (v ->> 'code') = 'CONTENT_UNAVAILABLE');
  v := pg_temp.claim(pg_temp.id(1), 403, 201, 101, pg_temp.src(307));
  PERFORM pg_temp.expect('role-simulation (or placeholder assistant) message rejected', (v ->> 'code') = 'CONTENT_UNAVAILABLE');
  v := pg_temp.claim(pg_temp.id(1), 403, 201, 101, pg_temp.src(308));
  PERFORM pg_temp.expect('over-long message rejected, never truncated', (v ->> 'code') = 'CONTENT_UNAVAILABLE');
  v := pg_temp.claim(pg_temp.id(1), 403, 201, 101, pg_temp.src(304));
  PERFORM pg_temp.expect('message of another conversation is NOT_FOUND', (v ->> 'code') = 'NOT_FOUND');
  v := pg_temp.claim(pg_temp.id(1), 403, 201, 101, pg_temp.src(306));
  PERFORM pg_temp.expect('another owner''s message is NOT_FOUND', (v ->> 'code') = 'NOT_FOUND');
  v := pg_temp.claim(pg_temp.id(1), 403, 201, 101, pg_temp.src(399));
  PERFORM pg_temp.expect('unknown message is NOT_FOUND', (v ->> 'code') = 'NOT_FOUND');
  v := pg_temp.claim(pg_temp.id(2), 403, 201, 101, pg_temp.src(301));
  PERFORM pg_temp.expect('another owner cannot claim this session', (v ->> 'code') = 'NOT_FOUND');
  v := pg_temp.claim(pg_temp.id(1), 403, 201, 102, pg_temp.src(304));
  PERFORM pg_temp.expect('conversation must be the session''s attached conversation', (v ->> 'code') = 'CONTENT_UNAVAILABLE' AND (v ->> 'message') = 'conversation_changed');
  v := pg_temp.claim(pg_temp.id(1), 403, 204, 101, pg_temp.src(301));
  PERFORM pg_temp.expect('session without a conversation is rejected', (v ->> 'code') = 'CONTENT_UNAVAILABLE');
  v := public.support_memory_suggestion_claim(pg_temp.id(1), pg_temp.id(403), pg_temp.id(201), pg_temp.id(101), 1, jsonb_build_array(jsonb_build_object('id', pg_temp.id(301), 'revision', 9)));
  PERFORM pg_temp.expect('a stale message revision (or privacy revision) is PRIVACY_REVISION_STALE', (v ->> 'code') = 'PRIVACY_REVISION_STALE');
  v := public.support_memory_suggestion_claim(pg_temp.id(1), pg_temp.id(403), pg_temp.id(201), pg_temp.id(101), v_priv + 7, pg_temp.src(301));
  PERFORM pg_temp.expect('stale privacy revision reports the current one',
    (v ->> 'code') = 'PRIVACY_REVISION_STALE' AND (v ->> 'current_privacy_revision')::bigint = v_priv);
  INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason) VALUES (pg_temp.id(1), 'message', pg_temp.id(305), 'user_source_exclusion');
  v := pg_temp.claim(pg_temp.id(1), 403, 201, 101, pg_temp.src(305));
  PERFORM pg_temp.expect('suppressed message rejected', (v ->> 'code') = 'CONTENT_UNAVAILABLE' AND (v ->> 'message') = 'source_suppressed');
  DELETE FROM public.support_suppressions WHERE user_id = pg_temp.id(1) AND ref_id = pg_temp.id(305);
  INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason) VALUES (pg_temp.id(1), 'conversation', pg_temp.id(101), 'user_source_exclusion');
  v := pg_temp.claim(pg_temp.id(1), 403, 201, 101, pg_temp.src(301));
  PERFORM pg_temp.expect('a suppressed conversation yields nothing', (v ->> 'code') = 'CONTENT_UNAVAILABLE');
  DELETE FROM public.support_suppressions WHERE user_id = pg_temp.id(1) AND ref_id = pg_temp.id(101);

  v := public.support_memory_suggestion_claim(pg_temp.id(1), pg_temp.id(403), pg_temp.id(201), pg_temp.id(101), v_priv, '[]'::jsonb);
  PERFORM pg_temp.expect('empty selection is INVALID_PAYLOAD', (v ->> 'code') = 'INVALID_PAYLOAD');
  v := public.support_memory_suggestion_claim(pg_temp.id(1), pg_temp.id(403), pg_temp.id(201), pg_temp.id(101), v_priv,
    (SELECT jsonb_agg(jsonb_build_object('id', pg_temp.id(500 + n), 'revision', 0)) FROM generate_series(1, 13) n));
  PERFORM pg_temp.expect('13 sources is INVALID_PAYLOAD', (v ->> 'code') = 'INVALID_PAYLOAD');
  v := public.support_memory_suggestion_claim(pg_temp.id(1), pg_temp.id(403), pg_temp.id(201), pg_temp.id(101), v_priv,
    jsonb_build_array(jsonb_build_object('id', pg_temp.id(301), 'revision', 0), jsonb_build_object('id', pg_temp.id(301), 'revision', 0)));
  PERFORM pg_temp.expect('duplicate source is INVALID_PAYLOAD', (v ->> 'code') = 'INVALID_PAYLOAD');
  v := public.support_memory_suggestion_claim(pg_temp.id(1), pg_temp.id(403), pg_temp.id(201), pg_temp.id(101), v_priv,
    jsonb_build_array(jsonb_build_object('id', pg_temp.id(301), 'revision', 0, 'text', 'smuggled client text')));
  PERFORM pg_temp.expect('unknown source field (client text) is INVALID_PAYLOAD', (v ->> 'code') = 'INVALID_PAYLOAD');
  v := public.support_memory_suggestion_claim(pg_temp.id(1), pg_temp.id(403), pg_temp.id(201), pg_temp.id(101), v_priv,
    jsonb_build_array(jsonb_build_object('id', 'not-a-uuid', 'revision', 0)));
  PERFORM pg_temp.expect('non-UUID source id is INVALID_PAYLOAD, not an exception', (v ->> 'code') = 'INVALID_PAYLOAD');
  PERFORM pg_temp.expect('rejected claims created no rows', (SELECT count(*) FROM public.support_memory_suggestion_requests) = 1);

  v := pg_temp.claim(pg_temp.id(1), 404, 203, 102, pg_temp.src(304));
  PERFORM pg_temp.expect('a different session (closed) may run independently', (v ->> 'action') = 'proceed');
  v := pg_temp.claim(pg_temp.id(2), 401, 202, 103, pg_temp.src(306));
  PERFORM pg_temp.expect('the same request uuid for another owner is an independent request', (v ->> 'action') = 'proceed');
  SELECT count(*) INTO v_n FROM public.support_memory_suggestion_requests WHERE request_id = pg_temp.id(401);
  PERFORM pg_temp.expect('request ids are scoped per owner', v_n = 2);
  v := public.support_memory_suggestion_status(pg_temp.id(2), pg_temp.id(404));
  PERFORM pg_temp.expect('status cannot read another owner''s request', (v ->> 'code') = 'NOT_FOUND');
  -- Release session 203 and 202 (terminal) so later blocks are not blocked by a running request.
  PERFORM public.support_memory_suggestion_finish(pg_temp.id(1), pg_temp.id(404), 1, 'failed_pre_provider', 'fixture_cleanup');
  PERFORM public.support_memory_suggestion_finish(pg_temp.id(2), pg_temp.id(401), 1, 'failed_pre_provider', 'fixture_cleanup');
END $$;

-- ---------------------------------------------------------------------------
-- 4. Dispatch -> commit: pending candidates, provenance, expiry, no eligibility, replay
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v jsonb; v_priv bigint; v_frag uuid; v_ids uuid[]; r public.support_memory_suggestion_requests%ROWTYPE;
  v_before_comp integer; v_ctx jsonb; v_list jsonb;
  v_p0 bigint := pg_temp.priv(pg_temp.id(1)); v_src0 jsonb := pg_temp.src(301, 302);   -- the transmitted body is immutable
  v_used0 integer := pg_temp.used(pg_temp.id(1));
BEGIN
  v := public.support_memory_suggestion_dispatch(pg_temp.id(1), pg_temp.id(401), 99, pg_temp.src(301, 302), false);
  PERFORM pg_temp.expect('dispatch with a stale attempt token is refused and changes nothing',
    (v ->> 'message') = 'attempt_not_current' AND (SELECT status FROM public.support_memory_suggestion_requests WHERE request_id = pg_temp.id(401) AND user_id = pg_temp.id(1)) = 'claimed');
  v := public.support_memory_suggestion_dispatch(pg_temp.id(1), pg_temp.id(401), 1, pg_temp.src(301), false);
  PERFORM pg_temp.expect('dispatch with a different selection is refused', (v ->> 'ok')::boolean IS NOT TRUE);
  PERFORM pg_temp.expect('refused dispatches debit NO quota (MS002)', pg_temp.used(pg_temp.id(1)) = v_used0);
  v := public.support_memory_suggestion_commit(pg_temp.id(1), pg_temp.id(401), 1, pg_temp.src(301, 302), jsonb_build_array(pg_temp.cand('person', 'dog_name', 'Max', 301)));
  PERFORM pg_temp.expect('commit before dispatch is refused', (v ->> 'message') = 'attempt_not_current');
  v := public.support_memory_suggestion_dispatch(pg_temp.id(1), pg_temp.id(401), 1, pg_temp.src(301, 302), false);
  PERFORM pg_temp.expect('dispatch moves claimed -> dispatching', (v ->> 'ok')::boolean
    AND (SELECT status FROM public.support_memory_suggestion_requests WHERE request_id = pg_temp.id(401) AND user_id = pg_temp.id(1)) = 'dispatching');
  PERFORM pg_temp.expect('exactly ONE daily-quota unit was debited, atomically with the dispatch (MS002)', pg_temp.used(pg_temp.id(1)) = v_used0 + 1);
  v := public.support_memory_suggestion_dispatch(pg_temp.id(1), pg_temp.id(401), 1, pg_temp.src(301, 302), false);
  PERFORM pg_temp.expect('a second dispatch for the same attempt is refused (no second provider call possible)', (v ->> 'message') = 'attempt_not_current');
  v := pg_temp.claim(pg_temp.id(1), 401, 201, 101, pg_temp.src(301, 302));
  PERFORM pg_temp.expect('claim after dispatch is pending, never proceed', (v ->> 'action') = 'pending');
  PERFORM pg_temp.expect('a repeated dispatch and a replayed claim never debit again (lost-response safety, MS002)', pg_temp.used(pg_temp.id(1)) = v_used0 + 1);

  -- Malformed candidate lists write NOTHING and leave the request dispatching.
  SELECT count(*) INTO v_before_comp FROM public.memory_fragments;
  v := public.support_memory_suggestion_commit(pg_temp.id(1), pg_temp.id(401), 1, pg_temp.src(301, 302),
    jsonb_build_array(pg_temp.cand('person', 'dog_name', 'Max', 301), pg_temp.cand('fact', 'x', 'Y', 304)));
  PERFORM pg_temp.expect('candidate whose source is not a selected message rejects the whole list', (v ->> 'code') = 'INVALID_PAYLOAD');
  v := public.support_memory_suggestion_commit(pg_temp.id(1), pg_temp.id(401), 1, pg_temp.src(301, 302),
    jsonb_build_array(jsonb_build_object('fragment_type', 'person', 'key', 'a', 'value', 'b', 'source_message_id', 'not-a-uuid')));
  PERFORM pg_temp.expect('non-uuid provenance is INVALID_PAYLOAD (no cast exception)', (v ->> 'code') = 'INVALID_PAYLOAD');
  v := public.support_memory_suggestion_commit(pg_temp.id(1), pg_temp.id(401), 1, pg_temp.src(301, 302),
    jsonb_build_array(jsonb_build_object('fragment_type', 'person', 'key', 'a', 'value', 'b', 'source_message_id', pg_temp.id(301), 'confidence', 1)));
  PERFORM pg_temp.expect('unknown candidate field rejected', (v ->> 'code') = 'INVALID_PAYLOAD');
  v := public.support_memory_suggestion_commit(pg_temp.id(1), pg_temp.id(401), 1, pg_temp.src(301, 302), jsonb_build_array(pg_temp.cand('mood', 'k', 'v', 301)));
  PERFORM pg_temp.expect('invalid fragment type rejected', (v ->> 'code') = 'INVALID_PAYLOAD');
  v := public.support_memory_suggestion_commit(pg_temp.id(1), pg_temp.id(401), 1, pg_temp.src(301, 302), jsonb_build_array(pg_temp.cand('fact', 'Bad Key', 'v', 301)));
  PERFORM pg_temp.expect('non snake_case key rejected', (v ->> 'code') = 'INVALID_PAYLOAD');
  v := public.support_memory_suggestion_commit(pg_temp.id(1), pg_temp.id(401), 1, pg_temp.src(301, 302), jsonb_build_array(pg_temp.cand('fact', 'k', repeat('v', 501), 301)));
  PERFORM pg_temp.expect('oversized value rejected', (v ->> 'code') = 'INVALID_PAYLOAD');
  v := public.support_memory_suggestion_commit(pg_temp.id(1), pg_temp.id(401), 1, pg_temp.src(301, 302),
    (SELECT jsonb_agg(pg_temp.cand('fact', 'k' || n, 'v', 301)) FROM generate_series(1, 6) n));
  PERFORM pg_temp.expect('six candidates rejected (maximum five)', (v ->> 'code') = 'INVALID_PAYLOAD');
  v := public.support_memory_suggestion_commit(pg_temp.id(1), pg_temp.id(401), 1, pg_temp.src(301, 302), '[]'::jsonb);
  PERFORM pg_temp.expect('empty candidate list is not a commit', (v ->> 'code') = 'INVALID_PAYLOAD');
  PERFORM pg_temp.expect('rejected commits wrote nothing and left the request dispatching',
    (SELECT count(*) FROM public.memory_fragments) = v_before_comp
    AND (SELECT status FROM public.support_memory_suggestion_requests WHERE request_id = pg_temp.id(401) AND user_id = pg_temp.id(1)) = 'dispatching');

  v_priv := pg_temp.priv(pg_temp.id(1));
  SELECT count(*) INTO v_before_comp FROM public.companion_memory;
  v := public.support_memory_suggestion_commit(pg_temp.id(1), pg_temp.id(401), 1, pg_temp.src(301, 302),
    jsonb_build_array(pg_temp.cand('person', 'dog_name', 'Max', 301), pg_temp.cand('preference', 'reply_length', 'short replies', 302)));
  PERFORM pg_temp.expect('commit succeeds', (v ->> 'ok')::boolean AND ((v -> 'result') ->> 'status') = 'saved' AND ((v -> 'result') ->> 'saved_count')::integer = 2);
  SELECT * INTO r FROM public.support_memory_suggestion_requests WHERE request_id = pg_temp.id(401) AND user_id = pg_temp.id(1);
  PERFORM pg_temp.expect('request is saved with exactly the candidate identifiers', r.status = 'saved' AND cardinality(r.candidate_ids) = 2 AND r.finished_at IS NOT NULL);
  PERFORM pg_temp.expect('candidates are PENDING with server-bound provenance and a seven-day expiry',
    (SELECT bool_and(f.review_state = 'pending' AND f.promoted_memory_id IS NULL AND f.approved_at IS NULL
                     AND f.source_conversation_id = pg_temp.id(101) AND f.source_message_id IS NOT NULL AND f.value <> ''
                     AND f.candidate_expires_at BETWEEN now() + interval '6 days 23 hours' AND clock_timestamp() + interval '7 days')
       FROM public.memory_fragments f WHERE f.id = ANY (r.candidate_ids)));
  PERFORM pg_temp.expect('provenance maps each key to the selected message it was bound to',
    (SELECT f.source_message_id FROM public.memory_fragments f WHERE f.id = ANY (r.candidate_ids) AND f.key = 'dog_name') = pg_temp.id(301)
    AND (SELECT f.source_message_id FROM public.memory_fragments f WHERE f.id = ANY (r.candidate_ids) AND f.key = 'reply_length') = pg_temp.id(302));
  PERFORM pg_temp.expect('NO automatic promotion and NO privacy/eligibility bump for pending candidates',
    (SELECT count(*) FROM public.companion_memory) = v_before_comp AND pg_temp.priv(pg_temp.id(1)) = v_priv);
  v_ctx := public.support_context_sources(pg_temp.id(1), pg_temp.id(101), 20, true);
  PERFORM pg_temp.expect('pending candidates are not eligible personal context', jsonb_array_length(v_ctx -> 'memories') = 0);
  PERFORM pg_temp.as_user(pg_temp.id(1));
  v_list := public.support_list_memory();
  PERFORM pg_temp.expect('they appear in the EXISTING review list, with message provenance',
    (SELECT count(*) FROM jsonb_array_elements(v_list -> 'candidates') c WHERE c ->> 'review_state' = 'pending' AND c ->> 'provenance' = 'message') = 2);
  PERFORM pg_temp.expect('the bookkeeping table never contains candidate or source text',
    NOT EXISTS (SELECT 1 FROM public.support_memory_suggestion_requests q WHERE q::text ILIKE '%Max%' OR q::text ILIKE '%short replies%' OR q::text ILIKE '%dog_name%'));

  -- Replay (identical body) returns identities/status only, whatever happened since.
  v := pg_temp.claim_at(pg_temp.id(1), 401, 201, 101, v_p0, v_src0);
  PERFORM pg_temp.expect('confirmed replay returns the same identities', (v ->> 'action') = 'replay'
    AND ((v -> 'result') ->> 'status') = 'saved' AND jsonb_array_length((v -> 'result') -> 'candidates') = 2);
  PERFORM pg_temp.expect('replay carries no text', (v::text) NOT ILIKE '%Max%' AND (v::text) NOT ILIKE '%short replies%');
  SELECT candidate_ids INTO v_ids FROM public.support_memory_suggestion_requests WHERE request_id = pg_temp.id(401) AND user_id = pg_temp.id(1);

  -- Existing approval RPC promotes (and only it): replay shows 'approved'.
  v := public.support_memory_mutate(jsonb_build_object('schema_version', 1, 'operation_id', pg_temp.id(901), 'kind', 'candidate_approve',
        'payload', jsonb_build_object('fragment_id', v_ids[1])));
  PERFORM pg_temp.expect('existing approval promotes a suggestion', (v ->> 'ok')::boolean AND (SELECT count(*) FROM public.companion_memory) = v_before_comp + 1);
  PERFORM pg_temp.as_user(NULL);
  PERFORM pg_temp.expect('approval moved the privacy revision (replay must still work: receipt precedes revision comparison)', pg_temp.priv(pg_temp.id(1)) > v_p0);
  v := pg_temp.claim_at(pg_temp.id(1), 401, 201, 101, v_p0, v_src0);
  PERFORM pg_temp.expect('replay shows the approved candidate as approved',
    (SELECT c ->> 'state' FROM jsonb_array_elements((v -> 'result') -> 'candidates') c WHERE (c ->> 'id')::uuid = v_ids[1]) = 'approved');
  -- Forget removes the other: replay shows 'removed'.
  PERFORM pg_temp.as_user(pg_temp.id(1));
  PERFORM public.support_memory_mutate(jsonb_build_object('schema_version', 1, 'operation_id', pg_temp.id(902), 'kind', 'memory_forget',
        'payload', jsonb_build_object('fragment_id', v_ids[2])));
  PERFORM pg_temp.as_user(NULL);
  v := pg_temp.claim_at(pg_temp.id(1), 401, 201, 101, v_p0, v_src0);
  PERFORM pg_temp.expect('replay shows a forgotten candidate as removed, with no text',
    (SELECT c ->> 'state' FROM jsonb_array_elements((v -> 'result') -> 'candidates') c WHERE (c ->> 'id')::uuid = v_ids[2]) = 'removed'
    AND v::text NOT ILIKE '%short replies%');
  v := public.support_memory_suggestion_status(pg_temp.id(1), pg_temp.id(401));
  PERFORM pg_temp.expect('status op reads the same stored outcome', (v ->> 'action') = 'replay' AND ((v -> 'result') ->> 'status') = 'saved');
END $$;

-- ---------------------------------------------------------------------------
-- 5. Late changes during the provider call prevent candidate resurrection
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v jsonb; v_src jsonb; v_req integer; v_variant text; v_msg integer; v_frags integer; v_p bigint; v_used integer;
BEGIN
  SELECT count(*) INTO v_frags FROM public.memory_fragments;
  FOR v_variant, v_msg IN SELECT * FROM (VALUES ('message_edited', 310), ('privacy_bumped', 311), ('message_suppressed', 312), ('message_deleted', 313)) AS t(variant, msg) LOOP
    v_req := 500 + v_msg;
    v_p := pg_temp.priv(pg_temp.id(1));
    v_src := pg_temp.src(v_msg);                                   -- revisions and privacy bound BEFORE the change
    v := pg_temp.claim_at(pg_temp.id(1), v_req, 203, 102, v_p, v_src);
    PERFORM pg_temp.expect(v_variant || ': claim proceeds', (v ->> 'action') = 'proceed');
    v := public.support_memory_suggestion_dispatch(pg_temp.id(1), pg_temp.id(v_req), 1, v_src, false);
    PERFORM pg_temp.expect(v_variant || ': dispatch ok', (v ->> 'ok')::boolean);
    IF v_variant = 'message_edited' THEN UPDATE public.messages SET content = 'Edited after the provider call' WHERE id = pg_temp.id(v_msg);
    ELSIF v_variant = 'privacy_bumped' THEN PERFORM public.support_bump_privacy(pg_temp.id(1));
    ELSIF v_variant = 'message_suppressed' THEN
      INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason) VALUES (pg_temp.id(1), 'message', pg_temp.id(v_msg), 'forgotten_memory');
    ELSE DELETE FROM public.messages WHERE id = pg_temp.id(v_msg);
    END IF;
    v := public.support_memory_suggestion_commit(pg_temp.id(1), pg_temp.id(v_req), 1, v_src,
           jsonb_build_array(pg_temp.cand('fact', 'late_' || v_msg, 'Late candidate', v_msg)));
    PERFORM pg_temp.expect(v_variant || ': commit is refused', (v ->> 'ok')::boolean IS NOT TRUE
      AND (v ->> 'code') IN ('PRIVACY_REVISION_STALE', 'CONTENT_UNAVAILABLE', 'NOT_FOUND'));
    PERFORM pg_temp.expect(v_variant || ': request is stale and nothing was written',
      (SELECT status FROM public.support_memory_suggestion_requests WHERE request_id = pg_temp.id(v_req) AND user_id = pg_temp.id(1)) = 'stale'
      AND (SELECT count(*) FROM public.memory_fragments) = v_frags
      AND NOT EXISTS (SELECT 1 FROM public.memory_fragments WHERE key = 'late_' || v_msg));
    v := pg_temp.claim_at(pg_temp.id(1), v_req, 203, 102, v_p, v_src);
    PERFORM pg_temp.expect(v_variant || ': replay of the stale request does not proceed', (v ->> 'action') = 'replay'
      AND ((v -> 'result') ->> 'status') = 'stale' AND ((v -> 'result') ->> 'saved_count')::integer = 0);
  END LOOP;

  -- A change between claim and dispatch stops before dispatch: failed_pre_provider, retryable with a fresh preview.
  v_src := pg_temp.src(310);
  v := pg_temp.claim_at(pg_temp.id(1), 560, 203, 102, pg_temp.priv(pg_temp.id(1)), v_src);
  PERFORM public.support_bump_privacy(pg_temp.id(1));
  v_used := pg_temp.used(pg_temp.id(1));
  v := public.support_memory_suggestion_dispatch(pg_temp.id(1), pg_temp.id(560), 1, v_src, false);
  PERFORM pg_temp.expect('privacy change before dispatch is refused', (v ->> 'code') = 'PRIVACY_REVISION_STALE');
  PERFORM pg_temp.expect('a stale dispatch rejection debits NO quota (MS002)', pg_temp.used(pg_temp.id(1)) = v_used);
  PERFORM pg_temp.expect('and recorded as pre-provider (no provider request was made)',
    (SELECT status || '/' || failure_code FROM public.support_memory_suggestion_requests WHERE request_id = pg_temp.id(560) AND user_id = pg_temp.id(1)) = 'failed_pre_provider/stale_before_dispatch');

  -- A deleted session cannot be committed into.
  v_src := pg_temp.src(314);
  v := pg_temp.claim_at(pg_temp.id(1), 570, 205, 104, pg_temp.priv(pg_temp.id(1)), v_src);
  v := public.support_memory_suggestion_dispatch(pg_temp.id(1), pg_temp.id(570), 1, v_src, false);
  UPDATE public.support_work_sessions SET status = 'deleted', deleted_at = now() WHERE id = pg_temp.id(205);
  v := public.support_memory_suggestion_commit(pg_temp.id(1), pg_temp.id(570), 1, v_src, jsonb_build_array(pg_temp.cand('fact', 'late_session', 'x', 314)));
  PERFORM pg_temp.expect('a deleted session refuses the commit and the request is stale',
    (v ->> 'code') = 'NOT_FOUND' AND (SELECT status FROM public.support_memory_suggestion_requests WHERE request_id = pg_temp.id(570) AND user_id = pg_temp.id(1)) = 'stale'
    AND NOT EXISTS (SELECT 1 FROM public.memory_fragments WHERE key = 'late_session'));
END $$;

-- ---------------------------------------------------------------------------
-- 6. Existing rows with the same key are never overwritten
-- ---------------------------------------------------------------------------
DO $$
DECLARE v jsonb; v_src jsonb;
BEGIN
  PERFORM set_config('support.memory_rpc', 'on', true);   -- controlled path, as the real RPCs do
  INSERT INTO public.memory_fragments (user_id, fragment_type, key, value, review_state, promoted_memory_id, approved_at)
    VALUES (pg_temp.id(1), 'person', 'k_promoted', 'original promoted', 'promoted', pg_temp.id(777), now());
  INSERT INTO public.memory_fragments (user_id, fragment_type, key, value, review_state)
    VALUES (pg_temp.id(1), 'fact', 'k_legacy', 'original legacy', 'legacy_review');
  INSERT INTO public.memory_fragments (user_id, fragment_type, key, value, review_state, candidate_expires_at, source_message_id, source_conversation_id)
    VALUES (pg_temp.id(1), 'preference', 'k_pending', 'original pending', 'pending', now() + interval '3 days', pg_temp.id(315), pg_temp.id(105));
  INSERT INTO public.memory_fragments (user_id, fragment_type, key, value, review_state, source_message_id, source_conversation_id)
    VALUES (pg_temp.id(1), 'fact', 'k_dismissed_same', '', 'dismissed', pg_temp.id(315), pg_temp.id(105));
  INSERT INTO public.memory_fragments (user_id, fragment_type, key, value, review_state, source_message_id, source_conversation_id)
    VALUES (pg_temp.id(1), 'fact', 'k_dismissed_other', '', 'dismissed', pg_temp.id(316), pg_temp.id(105));
  INSERT INTO public.memory_fragments (user_id, fragment_type, key, value, review_state, source_message_id, source_conversation_id)
    VALUES (pg_temp.id(1), 'fact', 'k_dismissed_supp', '', 'dismissed', pg_temp.id(305), pg_temp.id(101));
  PERFORM set_config('support.memory_rpc', 'off', true);
  INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason) VALUES (pg_temp.id(1), 'message', pg_temp.id(305), 'forgotten_memory');

  v_src := pg_temp.src(315, 316);
  v := pg_temp.claim(pg_temp.id(1), 580, 206, 105, v_src);
  PERFORM pg_temp.expect('claim for key protection proceeds', (v ->> 'action') = 'proceed');
  v := public.support_memory_suggestion_dispatch(pg_temp.id(1), pg_temp.id(580), 1, v_src, false);
  v := public.support_memory_suggestion_commit(pg_temp.id(1), pg_temp.id(580), 1, v_src, jsonb_build_array(
        pg_temp.cand('person', 'k_promoted', 'NEW', 316), pg_temp.cand('fact', 'k_legacy', 'NEW', 316),
        pg_temp.cand('preference', 'k_pending', 'NEW', 316), pg_temp.cand('fact', 'k_dismissed_same', 'NEW', 315),
        pg_temp.cand('fact', 'k_dismissed_other', 'NEW', 315)));
  PERFORM pg_temp.expect('commit succeeds with only the re-proposed slot', (v ->> 'ok')::boolean
    AND ((v -> 'result') ->> 'status') = 'saved' AND ((v -> 'result') ->> 'saved_count')::integer = 1 AND ((v -> 'result') ->> 'skipped_count')::integer = 4);
  PERFORM pg_temp.expect('promoted / legacy / live pending rows keep their original value',
    (SELECT review_state || '/' || promoted_memory_id::text || '/[' || value || ']' FROM public.memory_fragments WHERE user_id = pg_temp.id(1) AND key = 'k_promoted')
      = 'promoted/' || pg_temp.id(777)::text || '/[]'   -- still promoted, same canonical id; the guard keeps promoted values empty
    AND (SELECT value FROM public.memory_fragments WHERE user_id = pg_temp.id(1) AND key = 'k_legacy') = 'original legacy'
    AND (SELECT review_state FROM public.memory_fragments WHERE user_id = pg_temp.id(1) AND key = 'k_legacy') = 'legacy_review'
    AND (SELECT value FROM public.memory_fragments WHERE user_id = pg_temp.id(1) AND key = 'k_pending') = 'original pending');
  PERFORM pg_temp.expect('a dismissed slot is not re-proposed from the SAME message',
    (SELECT review_state FROM public.memory_fragments WHERE user_id = pg_temp.id(1) AND key = 'k_dismissed_same') = 'dismissed');
  PERFORM pg_temp.expect('a dismissed slot IS re-proposed from a DIFFERENT message, as pending with the new provenance',
    (SELECT review_state || '/' || source_message_id::text FROM public.memory_fragments WHERE user_id = pg_temp.id(1) AND key = 'k_dismissed_other')
      = 'pending/' || pg_temp.id(315)::text);
  -- Second request (the first is terminal): the slot whose OLD source is suppressed is never reused.
  v := pg_temp.claim(pg_temp.id(1), 581, 206, 105, v_src);
  PERFORM pg_temp.expect('second request proceeds once the first is terminal', (v ->> 'action') = 'proceed');
  v := public.support_memory_suggestion_dispatch(pg_temp.id(1), pg_temp.id(581), 1, v_src, false);
  v := public.support_memory_suggestion_commit(pg_temp.id(1), pg_temp.id(581), 1, v_src,
         jsonb_build_array(pg_temp.cand('fact', 'k_dismissed_supp', 'NEW', 316)));
  PERFORM pg_temp.expect('all-skipped commit is no_candidates with the skip counted',
    (v ->> 'ok')::boolean AND ((v -> 'result') ->> 'status') = 'no_candidates' AND ((v -> 'result') ->> 'saved_count')::integer = 0
    AND ((v -> 'result') ->> 'skipped_count')::integer = 1);
  PERFORM pg_temp.expect('a dismissed slot whose old source is suppressed is never touched',
    (SELECT review_state FROM public.memory_fragments WHERE user_id = pg_temp.id(1) AND key = 'k_dismissed_supp') = 'dismissed');
  DELETE FROM public.support_suppressions WHERE user_id = pg_temp.id(1) AND ref_id = pg_temp.id(305);
END $$;

-- ---------------------------------------------------------------------------
-- 7. finish / retry policy / leases
-- ---------------------------------------------------------------------------
DO $$
DECLARE v jsonb; v_src jsonb := pg_temp.src(310);
BEGIN
  -- Pre-provider failure is explicitly retryable with the SAME body (attempt increments).
  v := pg_temp.claim(pg_temp.id(1), 600, 203, 102, v_src);
  PERFORM pg_temp.expect('claim 600', (v ->> 'action') = 'proceed');
  v := public.support_memory_suggestion_finish(pg_temp.id(1), pg_temp.id(600), 7, 'failed_pre_provider', 'daily_ai_limit');
  PERFORM pg_temp.expect('finish with the wrong attempt token is refused', (v ->> 'message') = 'attempt_not_current');
  v := public.support_memory_suggestion_finish(pg_temp.id(1), pg_temp.id(600), 1, 'failed_pre_provider', 'daily_ai_limit');
  PERFORM pg_temp.expect('claimed -> failed_pre_provider', (v ->> 'ok')::boolean AND ((v -> 'result') ->> 'status') = 'failed_pre_provider');
  v := public.support_memory_suggestion_finish(pg_temp.id(1), pg_temp.id(600), 1, 'failed_pre_provider', 'x');
  PERFORM pg_temp.expect('a terminal row cannot be finished again', (v ->> 'ok')::boolean IS NOT TRUE);
  v := public.support_memory_suggestion_finish(pg_temp.id(1), pg_temp.id(600), 1, 'saved', NULL);
  PERFORM pg_temp.expect('finish can never fabricate saved', (v ->> 'code') = 'INVALID_PAYLOAD');
  v := pg_temp.claim(pg_temp.id(1), 600, 203, 102, v_src);
  PERFORM pg_temp.expect('explicit retry of the same id and body proceeds as attempt 2', (v ->> 'action') = 'proceed' AND (v ->> 'attempt')::integer = 2);
  v := public.support_memory_suggestion_finish(pg_temp.id(1), pg_temp.id(600), 2, 'unknown', 'x');
  PERFORM pg_temp.expect('unknown cannot be recorded before dispatch (state machine)', (v ->> 'ok')::boolean IS NOT TRUE);

  -- After dispatch: every terminal state is final for the id (replay, never proceed).
  v := public.support_memory_suggestion_dispatch(pg_temp.id(1), pg_temp.id(600), 2, v_src, false);
  v := public.support_memory_suggestion_finish(pg_temp.id(1), pg_temp.id(600), 2, 'unknown', 'transport_unknown');
  PERFORM pg_temp.expect('dispatching -> unknown', (v ->> 'ok')::boolean);
  v := pg_temp.claim(pg_temp.id(1), 600, 203, 102, v_src);
  PERFORM pg_temp.expect('unknown is replayed, never proceed (no silent second provider call)',
    (v ->> 'action') = 'replay' AND ((v -> 'result') ->> 'status') = 'unknown' AND ((v -> 'result') ->> 'saved_count')::integer = 0);

  FOR v IN SELECT jsonb_build_object('s', s, 'n', n) FROM (VALUES ('failed_provider', 601), ('no_candidates', 602)) t(s, n) LOOP
    PERFORM pg_temp.claim(pg_temp.id(1), (v ->> 'n')::integer, 203, 102, v_src);
    PERFORM public.support_memory_suggestion_dispatch(pg_temp.id(1), pg_temp.id((v ->> 'n')::integer), 1, v_src, false);
    PERFORM public.support_memory_suggestion_finish(pg_temp.id(1), pg_temp.id((v ->> 'n')::integer), 1, v ->> 's', NULL);
    PERFORM pg_temp.expect((v ->> 's') || ' replays without proceeding',
      (pg_temp.claim(pg_temp.id(1), (v ->> 'n')::integer, 203, 102, v_src) ->> 'action') = 'replay');
  END LOOP;

  -- Leases: stale claimed (>2 min) is retryable; stale dispatching (>3 min) becomes unknown.
  PERFORM pg_temp.claim(pg_temp.id(1), 610, 203, 102, v_src);
  UPDATE public.support_memory_suggestion_requests SET claimed_at = clock_timestamp() - interval '3 minutes' WHERE request_id = pg_temp.id(610) AND user_id = pg_temp.id(1);
  v := pg_temp.claim(pg_temp.id(1), 610, 203, 102, v_src);
  PERFORM pg_temp.expect('a claim that never dispatched expires and is re-claimed (attempt 2)', (v ->> 'action') = 'proceed' AND (v ->> 'attempt')::integer = 2);
  PERFORM public.support_memory_suggestion_dispatch(pg_temp.id(1), pg_temp.id(610), 2, v_src, false);
  UPDATE public.support_memory_suggestion_requests SET dispatched_at = clock_timestamp() - interval '4 minutes' WHERE request_id = pg_temp.id(610) AND user_id = pg_temp.id(1);
  v := pg_temp.claim(pg_temp.id(1), 610, 203, 102, v_src);
  PERFORM pg_temp.expect('a dispatching request past its lease becomes unknown and is never re-sent',
    (v ->> 'action') = 'replay' AND ((v -> 'result') ->> 'status') = 'unknown' AND ((v -> 'result') ->> 'failure_code') = 'lease_expired');
  v := public.support_memory_suggestion_commit(pg_temp.id(1), pg_temp.id(610), 2, v_src, jsonb_build_array(pg_temp.cand('fact', 'late_after_lease', 'x', 310)));
  PERFORM pg_temp.expect('a late result after lease expiry cannot be committed', (v ->> 'message') = 'attempt_not_current'
    AND NOT EXISTS (SELECT 1 FROM public.memory_fragments WHERE key = 'late_after_lease'));
  v := public.support_memory_suggestion_status(pg_temp.id(1), pg_temp.id(999));
  PERFORM pg_temp.expect('status of an unknown id is NOT_FOUND', (v ->> 'code') = 'NOT_FOUND');
END $$;

-- ---------------------------------------------------------------------------
-- 7b. Daily quota is debited ONLY by dispatch, exactly once per request id (MS002), with real counts
-- ---------------------------------------------------------------------------
DO $$
DECLARE v jsonb; v_src jsonb := pg_temp.src(311); v_used integer; v_p bigint;
BEGIN
  v_p := pg_temp.priv(pg_temp.id(1));
  v_used := pg_temp.used(pg_temp.id(1));
  v := pg_temp.claim_at(pg_temp.id(1), 620, 203, 102, v_p, v_src);
  PERFORM pg_temp.expect('claim debits nothing', (v ->> 'action') = 'proceed' AND pg_temp.used(pg_temp.id(1)) = v_used);

  -- Free tier, quota exhausted: a definite pre-provider denial that debits nothing.
  UPDATE public.profiles SET daily_ai_quota = daily_ai_used WHERE id = pg_temp.id(1);
  v := public.support_memory_suggestion_dispatch(pg_temp.id(1), pg_temp.id(620), 1, v_src, false);
  PERFORM pg_temp.expect('exhausted free quota is ENTITLEMENT_REQUIRED / daily_ai_limit',
    NOT (v ->> 'ok')::boolean AND (v ->> 'code') = 'ENTITLEMENT_REQUIRED' AND (v ->> 'message') = 'daily_ai_limit');
  PERFORM pg_temp.expect('the denial debited nothing and left a retryable pre-provider failure',
    pg_temp.used(pg_temp.id(1)) = v_used
    AND (SELECT status || '/' || failure_code FROM public.support_memory_suggestion_requests WHERE request_id = pg_temp.id(620) AND user_id = pg_temp.id(1))
        = 'failed_pre_provider/daily_ai_limit'
    AND (SELECT dispatched_at FROM public.support_memory_suggestion_requests WHERE request_id = pg_temp.id(620) AND user_id = pg_temp.id(1)) IS NULL);

  -- Explicit same-id retry once the quota is available: ONE debit total, however often the call is repeated.
  UPDATE public.profiles SET daily_ai_quota = 100 WHERE id = pg_temp.id(1);
  v := pg_temp.claim_at(pg_temp.id(1), 620, 203, 102, v_p, v_src);
  PERFORM pg_temp.expect('same-id retry re-claims as attempt 2 without debiting', (v ->> 'action') = 'proceed' AND (v ->> 'attempt')::integer = 2
    AND pg_temp.used(pg_temp.id(1)) = v_used);
  v := public.support_memory_suggestion_dispatch(pg_temp.id(1), pg_temp.id(620), 2, v_src, false);
  PERFORM pg_temp.expect('dispatch debits exactly one unit', (v ->> 'ok')::boolean AND pg_temp.used(pg_temp.id(1)) = v_used + 1);
  -- A lost dispatch RESPONSE looks like: the caller repeats dispatch / claim / status. None may debit again.
  PERFORM public.support_memory_suggestion_dispatch(pg_temp.id(1), pg_temp.id(620), 2, v_src, false);
  PERFORM pg_temp.claim_at(pg_temp.id(1), 620, 203, 102, v_p, v_src);
  PERFORM public.support_memory_suggestion_status(pg_temp.id(1), pg_temp.id(620));
  PERFORM pg_temp.expect('repeats after an applied dispatch never debit again', pg_temp.used(pg_temp.id(1)) = v_used + 1);
  UPDATE public.support_memory_suggestion_requests SET dispatched_at = clock_timestamp() - interval '4 minutes'
    WHERE request_id = pg_temp.id(620) AND user_id = pg_temp.id(1);
  v := pg_temp.claim_at(pg_temp.id(1), 620, 203, 102, v_p, v_src);
  PERFORM pg_temp.expect('the unconfirmed request ends unknown (terminal) and is never re-debited',
    (v ->> 'action') = 'replay' AND ((v -> 'result') ->> 'status') = 'unknown' AND pg_temp.used(pg_temp.id(1)) = v_used + 1);

  -- Premium (verified entitlement passed by the Edge function): never denied, still exactly one increment.
  v_used := pg_temp.used(pg_temp.id(1));
  UPDATE public.profiles SET daily_ai_quota = daily_ai_used WHERE id = pg_temp.id(1);
  v_src := pg_temp.src(310);   -- 312 is suppressed and 313 deleted by section 5; 310/311 are still eligible
  PERFORM pg_temp.claim_at(pg_temp.id(1), 621, 203, 102, v_p, v_src);
  v := public.support_memory_suggestion_dispatch(pg_temp.id(1), pg_temp.id(621), 1, v_src, true);
  PERFORM pg_temp.expect('premium dispatch is admitted and debits exactly one unit', (v ->> 'ok')::boolean AND pg_temp.used(pg_temp.id(1)) = v_used + 1);
  PERFORM public.support_memory_suggestion_finish(pg_temp.id(1), pg_temp.id(621), 1, 'unknown', 'fixture_cleanup');
  UPDATE public.profiles SET daily_ai_quota = 100 WHERE id = pg_temp.id(1);

  -- A missing entitlement argument is refused before anything is touched.
  PERFORM pg_temp.claim_at(pg_temp.id(1), 622, 203, 102, v_p, pg_temp.src(311));
  v_used := pg_temp.used(pg_temp.id(1));
  v := public.support_memory_suggestion_dispatch(pg_temp.id(1), pg_temp.id(622), 1, pg_temp.src(311), NULL);
  PERFORM pg_temp.expect('NULL entitlement is INVALID_PAYLOAD and debits nothing', (v ->> 'code') = 'INVALID_PAYLOAD' AND pg_temp.used(pg_temp.id(1)) = v_used);
  PERFORM public.support_memory_suggestion_finish(pg_temp.id(1), pg_temp.id(622), 1, 'failed_pre_provider', 'fixture_cleanup');
END $$;

-- ---------------------------------------------------------------------------
-- 8. Account removal removes the bookkeeping (FK cascade); no tombstone of content remains
-- ---------------------------------------------------------------------------
DO $$
DECLARE v jsonb; v_src jsonb := pg_temp.src(317);
BEGIN
  v := pg_temp.claim(pg_temp.id(3), 700, 207, 106, v_src);
  PERFORM pg_temp.expect('claim for the user being removed', (v ->> 'action') = 'proceed');
  PERFORM public.support_memory_suggestion_dispatch(pg_temp.id(3), pg_temp.id(700), 1, v_src, false);
  PERFORM public.support_memory_suggestion_commit(pg_temp.id(3), pg_temp.id(700), 1, v_src, jsonb_build_array(pg_temp.cand('fact', 'removed_user_fact', 'x', 317)));
  PERFORM pg_temp.expect('request and candidate exist before removal',
    EXISTS (SELECT 1 FROM public.support_memory_suggestion_requests WHERE user_id = pg_temp.id(3))
    AND EXISTS (SELECT 1 FROM public.memory_fragments WHERE user_id = pg_temp.id(3) AND key = 'removed_user_fact'));
  DELETE FROM auth.users WHERE id = pg_temp.id(3);   -- requires the account-removal correction in the chain
  PERFORM pg_temp.expect('account removal cascades the request bookkeeping and the candidate',
    NOT EXISTS (SELECT 1 FROM public.support_memory_suggestion_requests WHERE user_id = pg_temp.id(3))
    AND NOT EXISTS (SELECT 1 FROM public.memory_fragments WHERE user_id = pg_temp.id(3)));
END $$;

SELECT 'support_memory_suggestions.sql: all assertions passed' AS result;
ROLLBACK;
