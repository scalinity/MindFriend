-- Support session: explicit, idempotent, review-only memory suggestions (spec 8.4).
--
-- NOT EXECUTED by its author. Requires 20261106230000..20261106230200 (and the later account
-- removal correction) and independent review on a disposable database first.
--
-- What this adds
--   * ONE content-free bookkeeping table, support_memory_suggestion_requests: request identity,
--     payload hash, status, attempt token, counters and candidate IDENTIFIERS. It stores no
--     message text, no candidate text, no provider output and no token. It is NOT a memory
--     store: candidates live only in the existing public.memory_fragments review store, and
--     approved memories only in public.companion_memory (via the existing approval RPC).
--   * A read-only preview RPC (authenticated, auth.uid()) and five service-role RPCs
--     (claim / dispatch / finish / commit / status) used by the support-memory-suggestions
--     Edge function. No RPC performs a model call; the provider call happens in the Edge
--     function strictly between `dispatch` and `commit`/`finish`. `dispatch` additionally
--     debits the existing daily AI quota (see below).
--
-- Idempotency / "never duplicate provider work after uncertain admission"
--   status machine (attempt is a compare-and-set token):
--     claimed ---dispatch---> dispatching ---commit---> saved
--        |                         |------finish-----> no_candidates | failed_provider | unknown
--        |                         '------commit(validation failed)--> stale
--        '--finish--> failed_pre_provider --(same id, same body, explicit retry)--> claimed
--   * `dispatch` is the LAST database step before the provider request. After it, nothing can
--     re-issue a provider call for the same request id: claim returns `replay`/`pending`.
--   * claimed older than 2 minutes provably never reached `dispatch`; it is treated as
--     failed_pre_provider and may be explicitly re-attempted with the same immutable body.
--   * dispatching older than 3 minutes (provider timeout is 45 s) becomes `unknown`: terminal for
--     this id, no candidates, never reported as generated/saved. A new Generate uses a new id.
--   * Same id + different session/conversation/privacy-revision/message-revision set is
--     OPERATION_ID_REUSED. At most one non-terminal request exists per (user, session).
--   * Daily AI quota is debited INSIDE `dispatch`, in the same transaction as the
--     claimed -> dispatching compare-and-set and AFTER source/privacy validation. A rejected
--     (stale/ineligible) dispatch debits nothing, a denied quota debits nothing and records
--     failed_pre_provider, and a dispatch whose response is lost cannot debit twice: it either
--     committed (row is dispatching, claim then returns pending/replay, never proceed) or it
--     rolled back (nothing was debited). There is no separate quota call that can be repeated.
--
-- Lock order (matches support_confirm_chat_turn). EVERY function here that writes -- claim,
-- dispatch, finish, commit and status (its lease expiry updates rows) -- takes the private write
-- mutex FIRST, before any advisory lock, expiry update or row lock. Then, where applicable:
-- privacy state -> session -> cited message rows (id order) -> the request row -> profiles
-- (quota, dispatch only) -> fragment rows. Review finding MS001: an earlier claim took only a
-- per-request advisory lock, then request-row locks (lease expiry), and only afterwards the
-- parent foreign-key key-share locks of a new receipt row. A session/account delete (mutex +
-- parent row, then its cascade waiting on a receipt row claim had locked) and that later parent
-- wait formed a cycle. With the mutex first, writers are serialized and none can hold a receipt
-- row while waiting for a parent held by a mutex holder.
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $$
BEGIN
  IF to_regclass('public.support_memory_suggestion_requests') IS NOT NULL THEN
    RAISE EXCEPTION 'support memory suggestions already present; review before applying';
  END IF;
  IF to_regclass('public.support_work_sessions') IS NULL
     OR to_regclass('public.support_suppressions') IS NULL
     OR to_regclass('public.support_privacy_state') IS NULL
     OR to_regprocedure('public.support_acquire_write_mutex()') IS NULL
     OR to_regprocedure('public.support_ensure_privacy_state(uuid)') IS NULL
     OR to_regprocedure('public.support_fragment_suppressed(uuid,uuid,uuid,uuid)') IS NULL
     OR to_regprocedure('public.support_memory_mutate(jsonb)') IS NULL
     OR to_regprocedure('public.support_try_uuid(text)') IS NULL
     OR to_regprocedure('public.check_and_increment_ai_quota(uuid,boolean)') IS NULL THEN
    RAISE EXCEPTION 'support session migrations 20261106230000..20261106230200 and the existing AI quota function must be present first';
  END IF;
  IF (SELECT count(*) FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'memory_fragments'
          AND column_name IN ('review_state', 'candidate_expires_at', 'source_message_id',
                              'source_conversation_id', 'promoted_memory_id', 'approved_at')) <> 6 THEN
    RAISE EXCEPTION 'memory_fragments review/provenance columns are missing';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Content-free request bookkeeping
-- ---------------------------------------------------------------------------
CREATE TABLE public.support_memory_suggestion_requests (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  request_id uuid NOT NULL,
  support_session_id uuid NOT NULL,
  -- Plain identifier (no FK): deleting the conversation must not retain or cascade anything.
  conversation_id uuid NOT NULL,
  -- sha256 of 'v1|session|conversation|privacy_revision|id:revision,...' (ids sorted). Identity only.
  payload_hash text NOT NULL CHECK (payload_hash ~ '^[0-9a-f]{64}$'),
  privacy_revision bigint NOT NULL CHECK (privacy_revision >= 1),
  source_count integer NOT NULL CHECK (source_count BETWEEN 1 AND 12),
  status text NOT NULL CHECK (status IN (
    'claimed', 'dispatching', 'saved', 'no_candidates', 'failed_pre_provider', 'failed_provider', 'stale', 'unknown')),
  failure_code text CHECK (failure_code IS NULL OR failure_code ~ '^[a-z0-9_]{1,40}$'),
  attempt integer NOT NULL DEFAULT 1 CHECK (attempt >= 1),
  candidate_ids uuid[] NOT NULL DEFAULT '{}' CHECK (cardinality(candidate_ids) <= 5),
  skipped_count smallint NOT NULL DEFAULT 0 CHECK (skipped_count BETWEEN 0 AND 5),
  claimed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  dispatched_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, request_id),
  CONSTRAINT support_memory_suggestion_requests_session_fk FOREIGN KEY (user_id, support_session_id)
    REFERENCES public.support_work_sessions (user_id, id) ON DELETE CASCADE,
  CONSTRAINT support_memory_suggestion_requests_finished_shape CHECK (
    (status IN ('claimed', 'dispatching')) = (finished_at IS NULL)),
  CONSTRAINT support_memory_suggestion_requests_dispatch_shape CHECK (
    CASE WHEN status IN ('claimed', 'failed_pre_provider') THEN dispatched_at IS NULL
         ELSE dispatched_at IS NOT NULL END),
  CONSTRAINT support_memory_suggestion_requests_saved_shape CHECK (
    (status = 'saved') = (cardinality(candidate_ids) > 0))
);
-- At most one non-terminal request per session (a second Generate cannot start a parallel provider call).
CREATE UNIQUE INDEX support_memory_suggestion_one_running_uidx
  ON public.support_memory_suggestion_requests (user_id, support_session_id)
  WHERE status IN ('claimed', 'dispatching');
COMMENT ON TABLE public.support_memory_suggestion_requests IS
  'Content-free identity/status bookkeeping for explicit memory-suggestion requests. Not a memory store: holds identifiers and counters only.';

ALTER TABLE public.support_memory_suggestion_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.support_memory_suggestion_requests FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.support_memory_suggestion_requests TO service_role;
-- Deliberately NO policy for anon/authenticated: reachable only through the RPCs below.

-- ---------------------------------------------------------------------------
-- Pure helpers
-- ---------------------------------------------------------------------------
-- NULL when the selection is well formed, otherwise a content-free message.
CREATE FUNCTION public.support_memory_suggestion_shape(p_sources jsonb) RETURNS text
LANGUAGE plpgsql STABLE SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE e jsonb; k text; v_id uuid; v_seen uuid[] := '{}';
BEGIN
  IF p_sources IS NULL OR jsonb_typeof(p_sources) IS DISTINCT FROM 'array' THEN RETURN 'sources must be an array'; END IF;
  IF jsonb_array_length(p_sources) < 1 OR jsonb_array_length(p_sources) > 12 THEN
    RETURN 'between 1 and 12 sources are required';
  END IF;
  FOR e IN SELECT x FROM jsonb_array_elements(p_sources) x LOOP
    IF jsonb_typeof(e) IS DISTINCT FROM 'object' THEN RETURN 'each source must be an object'; END IF;
    FOR k IN SELECT jsonb_object_keys(e) LOOP
      IF k NOT IN ('id', 'revision') THEN RETURN 'unknown source field'; END IF;
    END LOOP;
    IF jsonb_typeof(e -> 'id') IS DISTINCT FROM 'string' THEN RETURN 'source id must be a UUID'; END IF;
    v_id := public.support_try_uuid(e ->> 'id');
    IF v_id IS NULL THEN RETURN 'source id must be a UUID'; END IF;
    IF jsonb_typeof(e -> 'revision') IS DISTINCT FROM 'number' OR (e ->> 'revision') !~ '^[0-9]{1,15}$' THEN
      RETURN 'source revision must be a non-negative integer';
    END IF;
    IF v_id = ANY (v_seen) THEN RETURN 'duplicate source'; END IF;
    v_seen := v_seen || v_id;
  END LOOP;
  RETURN NULL;
END;
$$;

-- Only call after support_memory_suggestion_shape(p_sources) IS NULL.
CREATE FUNCTION public.support_memory_suggestion_hash(
  p_session uuid, p_conversation uuid, p_privacy bigint, p_sources jsonb
) RETURNS text LANGUAGE sql STABLE SET search_path = pg_catalog, public, pg_temp AS $$
  SELECT encode(sha256(convert_to(
    'v1|' || p_session::text || '|' || p_conversation::text || '|' || p_privacy::text || '|' ||
    coalesce((SELECT string_agg(((e ->> 'id')::uuid)::text || ':' || ((e ->> 'revision')::bigint)::text, ','
                                ORDER BY ((e ->> 'id')::uuid)::text)
                FROM jsonb_array_elements(p_sources) e), ''), 'UTF8')), 'hex');
$$;

-- Lease policy (documented above). Idempotent; only touches this table.
CREATE FUNCTION public.support_memory_suggestion_expire(p_user uuid) RETURNS void
LANGUAGE sql SET search_path = pg_catalog, public, pg_temp AS $$
  UPDATE public.support_memory_suggestion_requests
     SET status = 'failed_pre_provider', failure_code = 'claim_expired', finished_at = clock_timestamp(), updated_at = now()
   WHERE user_id = p_user AND status = 'claimed' AND claimed_at < clock_timestamp() - interval '2 minutes';
  UPDATE public.support_memory_suggestion_requests
     SET status = 'unknown', failure_code = 'lease_expired', finished_at = clock_timestamp(), updated_at = now()
   WHERE user_id = p_user AND status = 'dispatching' AND dispatched_at < clock_timestamp() - interval '3 minutes';
$$;

-- Stored outcome as returned to the Edge function. Identifiers and states only: never text.
CREATE FUNCTION public.support_memory_suggestion_result(r public.support_memory_suggestion_requests) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = pg_catalog, public, pg_temp AS $$
  SELECT jsonb_build_object(
    'request_id', r.request_id, 'session_id', r.support_session_id, 'conversation_id', r.conversation_id,
    'status', r.status, 'failure_code', r.failure_code, 'attempt', r.attempt,
    'privacy_revision', r.privacy_revision, 'saved_count', cardinality(r.candidate_ids),
    'skipped_count', r.skipped_count,
    'candidates', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', c.cid,
        'state', CASE
          WHEN f.id IS NULL THEN 'removed'
          WHEN public.support_fragment_suppressed(r.user_id, f.id, f.source_message_id, f.source_conversation_id) THEN 'removed'
          WHEN f.promoted_memory_id IS NOT NULL OR f.review_state = 'promoted' THEN 'approved'
          WHEN f.review_state = 'dismissed' THEN 'dismissed'
          WHEN f.review_state = 'expired'
               OR (f.review_state = 'pending' AND coalesce(f.candidate_expires_at, f.created_at + interval '7 days') <= clock_timestamp())
            THEN 'expired'
          WHEN f.review_state = 'pending' THEN 'pending_review'
          ELSE 'removed' END,
        'expires_at', CASE WHEN f.review_state = 'pending' THEN f.candidate_expires_at END) ORDER BY c.ord)
      FROM unnest(r.candidate_ids) WITH ORDINALITY AS c(cid, ord)
      LEFT JOIN public.memory_fragments f ON f.id = c.cid AND f.user_id = r.user_id), '[]'::jsonb));
$$;

-- ---------------------------------------------------------------------------
-- Source validation. Used by claim (no locks), dispatch and commit (locks, under the mutex).
-- Fails closed with a domain result, never an exception: {ok:false, code, message[, current_privacy_revision]}.
-- Eligible source = a USER message of THIS session's own conversation, original content
-- (no assistant/interface/safety text, no rehearsal or role-simulation text), at the exact
-- content_revision bound by the caller, not suppressed (message or whole conversation).
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_memory_suggestion_validate(
  p_user uuid, p_session uuid, p_conversation uuid, p_privacy bigint, p_sources jsonb, p_lock boolean
) RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  w public.support_work_sessions%ROWTYPE;
  v_cur bigint; v_shape text; e jsonb; v_id uuid; v_rev bigint; ms record; v_found boolean;
BEGIN
  v_shape := public.support_memory_suggestion_shape(p_sources);
  IF v_shape IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD', 'message', v_shape);
  END IF;

  -- Privacy state first, then the session, then message rows (see lock order above).
  PERFORM public.support_ensure_privacy_state(p_user);
  IF p_lock THEN
    SELECT privacy_revision INTO v_cur FROM public.support_privacy_state WHERE user_id = p_user FOR SHARE;
    SELECT * INTO w FROM public.support_work_sessions WHERE id = p_session AND user_id = p_user FOR SHARE;
  ELSE
    SELECT privacy_revision INTO v_cur FROM public.support_privacy_state WHERE user_id = p_user;
    SELECT * INTO w FROM public.support_work_sessions WHERE id = p_session AND user_id = p_user;
  END IF;
  v_found := FOUND;
  IF NOT v_found OR w.status = 'deleted' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'session_not_found');
  END IF;
  IF w.conversation_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'CONTENT_UNAVAILABLE', 'message', 'no_conversation');
  END IF;
  IF w.conversation_id <> p_conversation THEN
    RETURN jsonb_build_object('ok', false, 'code', 'CONTENT_UNAVAILABLE', 'message', 'conversation_changed');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.conversations c WHERE c.id = p_conversation AND c.user_id = p_user) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'conversation_not_found');
  END IF;
  IF v_cur IS DISTINCT FROM p_privacy THEN
    RETURN jsonb_build_object('ok', false, 'code', 'PRIVACY_REVISION_STALE', 'message', 'privacy_revision_changed',
                              'current_privacy_revision', v_cur);
  END IF;
  IF EXISTS (SELECT 1 FROM public.support_suppressions s
              WHERE s.user_id = p_user AND s.kind = 'conversation' AND s.ref_id = p_conversation) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'CONTENT_UNAVAILABLE', 'message', 'source_suppressed');
  END IF;

  FOR e IN SELECT x FROM jsonb_array_elements(p_sources) x ORDER BY (x ->> 'id') LOOP
    v_id := (e ->> 'id')::uuid; v_rev := (e ->> 'revision')::bigint;
    IF p_lock THEN
      SELECT m.role::text AS role, m.content, m.content_revision, m.content_origin,
             m.rehearsal_session_id, m.is_ai_role_simulation
        INTO ms
        FROM public.messages m JOIN public.conversations c ON c.id = m.conversation_id
        WHERE m.id = v_id AND m.conversation_id = p_conversation AND c.user_id = p_user
        FOR SHARE OF m;
    ELSE
      SELECT m.role::text AS role, m.content, m.content_revision, m.content_origin,
             m.rehearsal_session_id, m.is_ai_role_simulation
        INTO ms
        FROM public.messages m JOIN public.conversations c ON c.id = m.conversation_id
        WHERE m.id = v_id AND m.conversation_id = p_conversation AND c.user_id = p_user;
    END IF;
    IF NOT FOUND THEN
      -- Another owner's, another conversation's, or a deleted message: indistinguishable on purpose.
      RETURN jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'source_not_found');
    END IF;
    IF ms.role <> 'user' OR ms.content_origin IS NOT NULL OR ms.rehearsal_session_id IS NOT NULL
       OR coalesce(ms.is_ai_role_simulation, false) OR btrim(ms.content) = '' OR char_length(ms.content) > 4000 THEN
      RETURN jsonb_build_object('ok', false, 'code', 'CONTENT_UNAVAILABLE', 'message', 'ineligible_source');
    END IF;
    IF ms.content_revision <> v_rev THEN
      RETURN jsonb_build_object('ok', false, 'code', 'PRIVACY_REVISION_STALE', 'message', 'source_changed:message',
                                'current_privacy_revision', v_cur);
    END IF;
    IF EXISTS (SELECT 1 FROM public.support_suppressions s
                WHERE s.user_id = p_user AND s.kind = 'message' AND s.ref_id = v_id) THEN
      RETURN jsonb_build_object('ok', false, 'code', 'CONTENT_UNAVAILABLE', 'message', 'source_suppressed');
    END IF;
  END LOOP;
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- PREVIEW (read only, no model call, no write): which of MY user messages in THIS session's
-- conversation could be selected. authenticated + auth.uid(); returns only the caller's rows.
-- The Edge function applies the provider-text sanitizer so the preview shows exactly what is sent.
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_memory_suggestion_sources(p_session_id uuid, p_limit integer DEFAULT 20) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_user uuid := auth.uid();
  w public.support_work_sessions%ROWTYPE;
  v_priv bigint; v_msgs jsonb; v_suppressed integer; v_long integer; v_conv_suppressed boolean;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501'; END IF;
  SELECT * INTO w FROM public.support_work_sessions WHERE id = p_session_id AND user_id = v_user AND status <> 'deleted';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'code', 'NOT_FOUND'); END IF;
  IF w.conversation_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.conversations c WHERE c.id = w.conversation_id AND c.user_id = v_user) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'CONTENT_UNAVAILABLE', 'message', 'no_conversation');
  END IF;
  SELECT coalesce(p.privacy_revision, 1) INTO v_priv FROM (SELECT 1) x
    LEFT JOIN public.support_privacy_state p ON p.user_id = v_user;
  v_conv_suppressed := EXISTS (SELECT 1 FROM public.support_suppressions s
    WHERE s.user_id = v_user AND s.kind = 'conversation' AND s.ref_id = w.conversation_id);
  IF v_conv_suppressed THEN
    RETURN jsonb_build_object('ok', true, 'session_id', w.id, 'conversation_id', w.conversation_id, 'session_status', w.status,
      'privacy_revision', v_priv, 'messages', '[]'::jsonb, 'excluded', jsonb_build_object('suppressed', 0, 'too_long', 0, 'conversation_suppressed', true));
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id, 'revision', t.content_revision, 'created_at', t.created_at, 'content', t.content)
      ORDER BY t.created_at, t.id), '[]'::jsonb)
    INTO v_msgs
    FROM (
      SELECT m.id, m.content_revision, m.created_at, m.content FROM public.messages m
       WHERE m.conversation_id = w.conversation_id AND m.role::text = 'user' AND m.content_origin IS NULL
         AND m.rehearsal_session_id IS NULL AND NOT coalesce(m.is_ai_role_simulation, false)
         AND btrim(m.content) <> '' AND char_length(m.content) <= 4000
         AND NOT EXISTS (SELECT 1 FROM public.support_suppressions s
                          WHERE s.user_id = v_user AND s.kind = 'message' AND s.ref_id = m.id)
       ORDER BY m.created_at DESC, m.id DESC
       LIMIT least(greatest(coalesce(p_limit, 20), 1), 20)) t;
  SELECT count(*) INTO v_suppressed FROM public.messages m
    WHERE m.conversation_id = w.conversation_id AND m.role::text = 'user'
      AND EXISTS (SELECT 1 FROM public.support_suppressions s WHERE s.user_id = v_user AND s.kind = 'message' AND s.ref_id = m.id);
  SELECT count(*) INTO v_long FROM public.messages m
    WHERE m.conversation_id = w.conversation_id AND m.role::text = 'user' AND char_length(m.content) > 4000;
  RETURN jsonb_build_object('ok', true, 'session_id', w.id, 'conversation_id', w.conversation_id, 'session_status', w.status,
    'privacy_revision', v_priv, 'messages', v_msgs,
    'excluded', jsonb_build_object('suppressed', v_suppressed, 'too_long', v_long, 'conversation_suppressed', false));
END;
$$;

-- ---------------------------------------------------------------------------
-- CLAIM: replay-first, then fresh validation, then exactly one new attempt.
-- Returns action = proceed | pending | replay, or a domain failure. On proceed it also returns
-- the selected messages' text (chronological) bound to the validated revisions.
-- Mutex first (see lock order above); no quota, budget or provider work happens here.
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_memory_suggestion_claim(
  p_user uuid, p_request_id uuid, p_session uuid, p_conversation uuid, p_privacy bigint, p_sources jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  r public.support_memory_suggestion_requests%ROWTYPE;
  v_exists boolean; v_shape text; v_hash text; v jsonb; v_texts jsonb;
BEGIN
  -- FIRST statement: the private write mutex, before any advisory/row lock (MS001). It also
  -- serializes concurrent identical claims, so two of them cannot both proceed.
  PERFORM public.support_acquire_write_mutex();
  IF p_user IS NULL OR p_request_id IS NULL OR p_session IS NULL OR p_conversation IS NULL
     OR p_privacy IS NULL OR p_privacy < 1 THEN
    RETURN jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD', 'message', 'missing field');
  END IF;
  v_shape := public.support_memory_suggestion_shape(p_sources);
  IF v_shape IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD', 'message', v_shape);
  END IF;
  v_hash := public.support_memory_suggestion_hash(p_session, p_conversation, p_privacy, p_sources);

  PERFORM public.support_memory_suggestion_expire(p_user);

  SELECT * INTO r FROM public.support_memory_suggestion_requests WHERE user_id = p_user AND request_id = p_request_id FOR UPDATE;
  v_exists := FOUND;
  IF v_exists THEN
    -- Replay comes BEFORE any revision/privacy comparison (spec 9.4).
    IF r.payload_hash <> v_hash THEN
      RETURN jsonb_build_object('ok', false, 'code', 'OPERATION_ID_REUSED',
                                'message', 'request id was already used for a different selection');
    END IF;
    IF r.status IN ('claimed', 'dispatching') THEN
      RETURN jsonb_build_object('ok', true, 'action', 'pending', 'result', public.support_memory_suggestion_result(r));
    ELSIF r.status <> 'failed_pre_provider' THEN
      RETURN jsonb_build_object('ok', true, 'action', 'replay', 'result', public.support_memory_suggestion_result(r));
    END IF;
    -- failed_pre_provider: no provider request was ever made; explicit retry of the same body.
  END IF;

  v := public.support_memory_suggestion_validate(p_user, p_session, p_conversation, p_privacy, p_sources, false);
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN RETURN v; END IF;

  BEGIN
    IF v_exists THEN
      UPDATE public.support_memory_suggestion_requests
         SET status = 'claimed', attempt = attempt + 1, failure_code = NULL, claimed_at = clock_timestamp(),
             dispatched_at = NULL, finished_at = NULL, updated_at = now()
       WHERE user_id = p_user AND request_id = p_request_id RETURNING * INTO r;
    ELSE
      INSERT INTO public.support_memory_suggestion_requests
        (user_id, request_id, support_session_id, conversation_id, payload_hash, privacy_revision, source_count, status)
      VALUES (p_user, p_request_id, p_session, p_conversation, v_hash, p_privacy, jsonb_array_length(p_sources), 'claimed')
      RETURNING * INTO r;
    END IF;
  EXCEPTION WHEN unique_violation THEN
    -- Another request for this session is already in flight: nothing was started for this id.
    RETURN jsonb_build_object('ok', false, 'code', 'TEMPORARY_FAILURE', 'message', 'generation_in_progress');
  END;

  SELECT coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'revision', m.content_revision, 'created_at', m.created_at,
                                               'content', m.content) ORDER BY m.created_at, m.id), '[]'::jsonb)
    INTO v_texts
    FROM public.messages m
    WHERE m.conversation_id = p_conversation
      AND m.id IN (SELECT (x ->> 'id')::uuid FROM jsonb_array_elements(p_sources) x);
  RETURN jsonb_build_object('ok', true, 'action', 'proceed', 'attempt', r.attempt, 'sources', v_texts);
END;
$$;

-- ---------------------------------------------------------------------------
-- DISPATCH: the point of no return. Under the mutex: final pre-provider recheck, THEN the daily
-- AI quota debit through the EXISTING check_and_increment_ai_quota (no new quota authority),
-- THEN claimed -> dispatching (compare-and-set on the attempt token) -- all in ONE transaction.
--   * stale/ineligible sources -> failed_pre_provider, NO quota touched;
--   * quota denied             -> failed_pre_provider (daily_ai_limit), nothing debited;
--   * quota function answer malformed, or the compare-and-set unexpectedly lost -> RAISE, which
--     rolls back the debit and every write (the Edge function treats an error as an unconfirmed
--     dispatch: it never reaches the provider and the row stays claimed/dispatching, never
--     double-debited);
--   * success -> exactly one debit and the row is dispatching; replays see dispatching and
--     can never proceed again, so a lost response cannot cause a second debit.
-- p_is_premium is derived by the Edge function from the verified entitlement (service role only).
-- Budget reservation stays in the Edge function before this call, as in the chat path.
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_memory_suggestion_dispatch(
  p_user uuid, p_request_id uuid, p_attempt integer, p_sources jsonb, p_is_premium boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  r public.support_memory_suggestion_requests%ROWTYPE;
  v jsonb; v_shape text; v_q json; v_qj jsonb;
BEGIN
  PERFORM public.support_acquire_write_mutex();   -- first, before any row lock
  IF p_is_premium IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD', 'message', 'entitlement missing');
  END IF;
  v_shape := public.support_memory_suggestion_shape(p_sources);
  IF v_shape IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD', 'message', v_shape);
  END IF;
  SELECT * INTO r FROM public.support_memory_suggestion_requests WHERE user_id = p_user AND request_id = p_request_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'request_not_found'); END IF;
  IF r.status <> 'claimed' OR r.attempt <> p_attempt
     OR r.payload_hash <> public.support_memory_suggestion_hash(r.support_session_id, r.conversation_id, r.privacy_revision, p_sources) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'TEMPORARY_FAILURE', 'message', 'attempt_not_current');
  END IF;

  v := public.support_memory_suggestion_validate(p_user, r.support_session_id, r.conversation_id, r.privacy_revision, p_sources, true);
  PERFORM 1 FROM public.support_memory_suggestion_requests WHERE user_id = p_user AND request_id = p_request_id FOR UPDATE;
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN
    -- Rejected BEFORE any quota is touched.
    UPDATE public.support_memory_suggestion_requests
       SET status = 'failed_pre_provider',
           failure_code = CASE v ->> 'code' WHEN 'PRIVACY_REVISION_STALE' THEN 'stale_before_dispatch'
                                            WHEN 'NOT_FOUND' THEN 'source_missing' ELSE 'source_unavailable' END,
           finished_at = clock_timestamp(), updated_at = now()
     WHERE user_id = p_user AND request_id = p_request_id AND status = 'claimed' AND attempt = p_attempt;
    RETURN v;
  END IF;

  -- The ONE quota debit for this request id. Atomic with the compare-and-set below.
  SELECT public.check_and_increment_ai_quota(p_user, p_is_premium) INTO v_q;
  v_qj := to_jsonb(v_q);
  IF v_qj IS NULL OR jsonb_typeof(v_qj) IS DISTINCT FROM 'object'
     OR jsonb_typeof(v_qj -> 'allowed') IS DISTINCT FROM 'boolean'
     OR jsonb_typeof(v_qj -> 'quota_used') IS DISTINCT FROM 'number' OR (v_qj ->> 'quota_used') !~ '^[0-9]{1,9}$'
     OR jsonb_typeof(v_qj -> 'quota_limit') IS DISTINCT FROM 'number' OR (v_qj ->> 'quota_limit') !~ '^-?[0-9]{1,9}$'
     OR ((v_qj ->> 'quota_limit') ~ '^-?[0-9]{1,9}$'
         AND (v_qj ->> 'quota_limit')::integer < 0 AND NOT (p_is_premium AND (v_qj ->> 'quota_limit')::integer = -1)) THEN
    RAISE EXCEPTION 'QUOTA_UNCONFIRMED' USING ERRCODE = 'SS002';   -- rolls back any increment
  END IF;
  IF NOT (v_qj ->> 'allowed')::boolean THEN
    UPDATE public.support_memory_suggestion_requests
       SET status = 'failed_pre_provider', failure_code = 'daily_ai_limit', finished_at = clock_timestamp(), updated_at = now()
     WHERE user_id = p_user AND request_id = p_request_id AND status = 'claimed' AND attempt = p_attempt;
    RETURN jsonb_build_object('ok', false, 'code', 'ENTITLEMENT_REQUIRED', 'message', 'daily_ai_limit');
  END IF;

  UPDATE public.support_memory_suggestion_requests
     SET status = 'dispatching', dispatched_at = clock_timestamp(), updated_at = now()
   WHERE user_id = p_user AND request_id = p_request_id AND status = 'claimed' AND attempt = p_attempt;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'DISPATCH_CAS_LOST' USING ERRCODE = 'SS003';   -- never keep a debit without the dispatch
  END IF;
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- ---------------------------------------------------------------------------
-- FINISH: terminal transitions that save nothing.
--   failed_pre_provider  from claimed      (explicitly retryable with the same body)
--   failed_provider | unknown | no_candidates  from dispatching (terminal for this id)
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_memory_suggestion_finish(
  p_user uuid, p_request_id uuid, p_attempt integer, p_status text, p_failure_code text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE r public.support_memory_suggestion_requests%ROWTYPE;
BEGIN
  PERFORM public.support_acquire_write_mutex();   -- first, before any row lock (MS001)
  IF p_status NOT IN ('failed_pre_provider', 'failed_provider', 'unknown', 'no_candidates')
     OR (p_failure_code IS NOT NULL AND p_failure_code !~ '^[a-z0-9_]{1,40}$') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD', 'message', 'bad status');
  END IF;
  UPDATE public.support_memory_suggestion_requests
     SET status = p_status, failure_code = p_failure_code, finished_at = clock_timestamp(), updated_at = now()
   WHERE user_id = p_user AND request_id = p_request_id AND attempt = p_attempt
     AND status = CASE WHEN p_status = 'failed_pre_provider' THEN 'claimed' ELSE 'dispatching' END
   RETURNING * INTO r;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'code', 'TEMPORARY_FAILURE', 'message', 'attempt_not_current'); END IF;
  RETURN jsonb_build_object('ok', true, 'result', public.support_memory_suggestion_result(r));
END;
$$;

-- ---------------------------------------------------------------------------
-- COMMIT: the only writer of candidates. ALL-OR-NOTHING in one transaction:
--   mutex -> privacy/session/message locks + full revalidation against the revisions BOUND AT
--   CLAIM (a concurrent edit / Forget / delete / privacy change makes the whole commit stale:
--   nothing is written, request becomes `stale`) -> request row -> fragment rows.
-- p_candidates: [{fragment_type, key, value, source_message_id}] with source_message_id chosen
-- BY THE SERVER from the selected set (never taken from model output).
-- Inserted rows are review_state 'pending' with a seven day candidate_expires_at, provenance
-- source_message_id + source_conversation_id, and NO privacy bump (they are excluded from
-- personalization until the existing candidate_approve RPC promotes them).
-- Existing rows with the same (user, fragment_type, key) are never overwritten except an
-- unsuppressed dismissed/expired slot being re-proposed from a DIFFERENT source message.
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_memory_suggestion_commit(
  p_user uuid, p_request_id uuid, p_attempt integer, p_sources jsonb, p_candidates jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  r public.support_memory_suggestion_requests%ROWTYPE;
  f public.memory_fragments%ROWTYPE;
  v jsonb; v_shape text; c jsonb; k text;
  v_type text; v_key text; v_value text; v_src uuid; v_id uuid; v_ids uuid[] := '{}'; v_skipped integer := 0;
  v_prev text := coalesce(current_setting('support.memory_rpc', true), '');
  v_sources uuid[]; v_found boolean; v_status text;
BEGIN
  v_shape := public.support_memory_suggestion_shape(p_sources);
  IF v_shape IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD', 'message', v_shape);
  END IF;
  IF p_candidates IS NULL OR jsonb_typeof(p_candidates) IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_candidates) < 1 OR jsonb_array_length(p_candidates) > 5 THEN
    RETURN jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD', 'message', '1 to 5 candidates are required');
  END IF;
  SELECT array_agg((x ->> 'id')::uuid) INTO v_sources FROM jsonb_array_elements(p_sources) x;
  -- Validate the whole candidate list up front so nothing is written for a malformed one.
  FOR c IN SELECT x FROM jsonb_array_elements(p_candidates) x LOOP
    IF jsonb_typeof(c) IS DISTINCT FROM 'object' THEN
      RETURN jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD', 'message', 'candidate must be an object');
    END IF;
    FOR k IN SELECT jsonb_object_keys(c) LOOP
      IF k NOT IN ('fragment_type', 'key', 'value', 'source_message_id') THEN
        RETURN jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD', 'message', 'unknown candidate field');
      END IF;
    END LOOP;
    IF jsonb_typeof(c -> 'fragment_type') IS DISTINCT FROM 'string' OR (c ->> 'fragment_type') NOT IN ('person', 'event', 'preference', 'fact')
       OR jsonb_typeof(c -> 'key') IS DISTINCT FROM 'string' OR (c ->> 'key') !~ '^[a-z][a-z0-9_]{0,49}$'
       OR jsonb_typeof(c -> 'value') IS DISTINCT FROM 'string' OR btrim(c ->> 'value') = '' OR char_length(c ->> 'value') > 500
       OR jsonb_typeof(c -> 'source_message_id') IS DISTINCT FROM 'string' THEN
      RETURN jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD', 'message', 'invalid candidate');
    END IF;
    -- Provenance is server-bound: it must be one of the selected messages (no cast can raise here).
    v_src := public.support_try_uuid(c ->> 'source_message_id');
    IF v_src IS NULL OR NOT (v_src = ANY (v_sources)) THEN
      RETURN jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD', 'message', 'candidate source is not a selected message');
    END IF;
  END LOOP;

  PERFORM public.support_acquire_write_mutex();   -- first, before any row lock
  SELECT * INTO r FROM public.support_memory_suggestion_requests WHERE user_id = p_user AND request_id = p_request_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'code', 'NOT_FOUND', 'message', 'request_not_found'); END IF;
  IF r.payload_hash <> public.support_memory_suggestion_hash(r.support_session_id, r.conversation_id, r.privacy_revision, p_sources) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'OPERATION_ID_REUSED', 'message', 'selection differs from the claimed request');
  END IF;

  -- Final atomic revalidation against the BOUND revisions, with the privacy/session/message locks held.
  v := public.support_memory_suggestion_validate(p_user, r.support_session_id, r.conversation_id, r.privacy_revision, p_sources, true);
  SELECT * INTO r FROM public.support_memory_suggestion_requests WHERE user_id = p_user AND request_id = p_request_id FOR UPDATE;
  IF r.status <> 'dispatching' OR r.attempt <> p_attempt THEN
    RETURN jsonb_build_object('ok', false, 'code', 'TEMPORARY_FAILURE', 'message', 'attempt_not_current');
  END IF;
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN
    UPDATE public.support_memory_suggestion_requests
       SET status = 'stale', failure_code = 'source_changed', finished_at = clock_timestamp(), updated_at = now()
     WHERE user_id = p_user AND request_id = p_request_id;
    RETURN v;   -- nothing was written; the provider output is discarded
  END IF;

  PERFORM set_config('support.memory_rpc', 'on', true);
  FOR c IN SELECT x FROM jsonb_array_elements(p_candidates) x LOOP
    v_type := c ->> 'fragment_type'; v_key := c ->> 'key'; v_value := btrim(c ->> 'value');
    v_src := (c ->> 'source_message_id')::uuid;
    SELECT * INTO f FROM public.memory_fragments
      WHERE user_id = p_user AND fragment_type = v_type AND key = v_key FOR UPDATE;
    v_found := FOUND;
    IF NOT v_found THEN
      INSERT INTO public.memory_fragments (user_id, fragment_type, key, value, source_conversation_id, source_message_id,
                                           review_state, candidate_expires_at, extracted_at)
      VALUES (p_user, v_type, v_key, v_value, r.conversation_id, v_src, 'pending',
              clock_timestamp() + interval '7 days', now())
      RETURNING id INTO v_id;
      v_ids := v_ids || v_id;
    ELSIF f.review_state IN ('dismissed', 'expired') AND f.promoted_memory_id IS NULL
          AND f.source_message_id IS DISTINCT FROM v_src
          AND NOT public.support_fragment_suppressed(p_user, f.id, f.source_message_id, f.source_conversation_id) THEN
      -- Re-propose into a slot the person previously dismissed, only from a different message.
      UPDATE public.memory_fragments
         SET value = v_value, review_state = 'pending', source_message_id = v_src,
             source_conversation_id = r.conversation_id, candidate_expires_at = clock_timestamp() + interval '7 days',
             extracted_at = now(), approved_at = NULL, promoted_memory_id = NULL
       WHERE id = f.id;
      v_ids := v_ids || f.id;
    ELSE
      -- promoted, legacy_review (unknown provenance: never silently replaced), a live pending
      -- candidate, a suppressed/forgotten source, or the same dismissed source: leave untouched.
      v_skipped := v_skipped + 1;
    END IF;
  END LOOP;
  PERFORM set_config('support.memory_rpc', v_prev, true);

  v_status := CASE WHEN cardinality(v_ids) > 0 THEN 'saved' ELSE 'no_candidates' END;
  UPDATE public.support_memory_suggestion_requests
     SET status = v_status, candidate_ids = v_ids, skipped_count = v_skipped, failure_code = NULL,
         finished_at = clock_timestamp(), updated_at = now()
   WHERE user_id = p_user AND request_id = p_request_id AND status = 'dispatching' AND attempt = p_attempt
   RETURNING * INTO r;
  RETURN jsonb_build_object('ok', true, 'result', public.support_memory_suggestion_result(r));
END;
$$;

-- ---------------------------------------------------------------------------
-- STATUS: read the stored outcome (applies the lease policy). Never starts provider work.
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_memory_suggestion_status(p_user uuid, p_request_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE r public.support_memory_suggestion_requests%ROWTYPE;
BEGIN
  PERFORM public.support_acquire_write_mutex();   -- first: the lease expiry below updates request rows (MS001)
  PERFORM public.support_memory_suggestion_expire(p_user);
  SELECT * INTO r FROM public.support_memory_suggestion_requests WHERE user_id = p_user AND request_id = p_request_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'code', 'NOT_FOUND'); END IF;
  RETURN jsonb_build_object('ok', true,
    'action', CASE WHEN r.status IN ('claimed', 'dispatching') THEN 'pending' ELSE 'replay' END,
    'result', public.support_memory_suggestion_result(r));
END;
$$;

-- ---------------------------------------------------------------------------
-- Grants. Internal helpers are not callable by API roles. Only the preview RPC is exposed to
-- authenticated (it derives the owner from auth.uid()); everything that writes is service_role.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION
  public.support_memory_suggestion_shape(jsonb),
  public.support_memory_suggestion_hash(uuid, uuid, bigint, jsonb),
  public.support_memory_suggestion_expire(uuid),
  public.support_memory_suggestion_result(public.support_memory_suggestion_requests),
  public.support_memory_suggestion_validate(uuid, uuid, uuid, bigint, jsonb, boolean),
  public.support_memory_suggestion_claim(uuid, uuid, uuid, uuid, bigint, jsonb),
  public.support_memory_suggestion_dispatch(uuid, uuid, integer, jsonb, boolean),
  public.support_memory_suggestion_finish(uuid, uuid, integer, text, text),
  public.support_memory_suggestion_commit(uuid, uuid, integer, jsonb, jsonb),
  public.support_memory_suggestion_status(uuid, uuid),
  public.support_memory_suggestion_sources(uuid, integer)
FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.support_memory_suggestion_sources(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION
  public.support_memory_suggestion_claim(uuid, uuid, uuid, uuid, bigint, jsonb),
  public.support_memory_suggestion_dispatch(uuid, uuid, integer, jsonb, boolean),
  public.support_memory_suggestion_finish(uuid, uuid, integer, text, text),
  public.support_memory_suggestion_commit(uuid, uuid, integer, jsonb, jsonb),
  public.support_memory_suggestion_status(uuid, uuid)
TO service_role;

COMMIT;
