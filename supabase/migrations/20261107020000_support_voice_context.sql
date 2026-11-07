-- M6 voice context admission binding (docs/SUPPORT_SESSION_SPEC.md 5.8 and 9.8).
-- NOT EXECUTED by its author; no deployment or SQL execution is authorized by this file.
-- Requires the bounded relay chain (20261023083500 ... 20261023092207) and the support-session
-- chain through M3 r4 (20261106230000 ... 20261106230200), whose private
-- support_acquire_write_mutex() and support_memory_time_eligible(companion_memory, timestamptz)
-- this file calls. Forward-only; it adds objects and wraps, and never redefines, the existing
-- prepare_voice_relay / claim_voice_relay / finalize_voice_relay.
--
-- Contract
--   * prepare_voice_relay_context: ONE transaction that verifies owner/session/conversation/
--     scope/privacy revision/cited sources, calls the unchanged prepare_voice_relay (owner
--     advisory lock, 3 starts/minute, minutes quota, one session+reservation), MARKS the
--     reservation context_required, and stores the context receipt, its content-free source
--     references and the binding (packet SHA-256, route). No other transaction can ever observe
--     an unmarked or unbound new-contract preparation.
--   * claim_voice_relay_context: revalidates owner/binding/privacy revision/sources, then calls
--     the unchanged claim_voice_relay (owner, global-budget and monthly-reserve locks and
--     checks, one active relay, 2-minute expiry). A trigger refuses any claim of a
--     context_required reservation that did not pass through this wrapper, so a new-contract
--     admission can never be claimed as legacy.
--   * voice_relay_context_binding / voice_relay_context_check: read-only; route lookup before
--     any claim and the privacy-lease refresh.
-- No instruction text, memory text or transcript is stored: identifiers, revisions and a hash.
--
-- LOCK ORDER (prepare and claim). M3's single private write mutex is taken FIRST, before any
-- privacy, session, memory or voice lock, exactly as every M3 context-changing write does, so a
-- concurrent correction, discard, suppression or legacy memory write queues behind the mutex
-- and can never hold the privacy row while we hold a session row (MF-M6S-001). Then, in order:
--   1. support_acquire_write_mutex()                      (M3 write mutex)
--   2. owner advisory lock 76543                          (voice, as prepare/claim/finalize)
--   3. claim only: voice_sessions row, then its reservation row         (voice, as claim)
--   4. cited companion_memory rows FOR SHARE, ORDER BY id (M3: memories before privacy)
--   5. privacy row FOR SHARE                              (M3)
--   6. support_work_sessions row FOR SHARE                (M3)
--   7. cited support_activities rows FOR SHARE, ORDER BY id (M3)
--   7b. cited messages FOR SHARE OF ms, ORDER BY id (M3 locks them last, while verifying)
--   8. v_now := clock_timestamp()                         (after EVERY lock above)
--   9. claim only: the unchanged claim_voice_relay (re-entrant owner lock, then the global
--      budget lock 76544 and the monthly reserve) - THESE can block
--  10. claim only: FINAL eligibility boundary, a fresh clock_timestamp() read AFTER step 9 and
--      before the transaction can commit (MF-M6S-002). A source deadline crossed while step 9
--      waited raises, which aborts the whole transaction: claimed reservation, context_claim_ok
--      and the monthly debit are rolled back together. Nothing was dispatched, so there is no
--      provider usage to settle; nothing is committed and then undone.
-- The global voice lock is last and no voice-only transaction (finalize, legacy claim, client
-- end) ever takes an M3 resource or the mutex, so no cycle exists between the two families.
-- voice_relay_context_check is deliberately lock-free: a refresh must never queue behind
-- writers (its own 2 s timeout would then end a healthy call) and it cannot deadlock.
-- Time: no row changes when an expiry or life-context review deadline passes, so every
-- consumer re-evaluates it. All of prepare, claim (before AND after its inner admission waits)
-- and every lease refresh call M3's support_memory_time_eligible with an explicit
-- clock_timestamp() (never now()). prepare has no blocking step after its single check: the
-- owner lock it needs is already held (re-entrant) and nothing else can wait.
-- Message versions (MF-M6S-004): a cited message is bound to its exact M3 content_revision
-- (a server-owned counter advanced by a change of content, role, conversation or origin and
-- NOT by the account privacy revision). prepare, claim and every refresh compare it, so an
-- in-place rewrite, re-role, re-origin, move or delete of a cited turn ends the lease at the
-- next refresh even though the privacy revision never moved. A NEW message does not touch any
-- other message's version, so an unrelated insert never invalidates a packet.
BEGIN;

DO $$ BEGIN
  IF pg_catalog.to_regclass('public.voice_relay_reservations') IS NULL
    OR pg_catalog.to_regprocedure('public.prepare_voice_relay(uuid)') IS NULL
    OR pg_catalog.to_regprocedure('public.claim_voice_relay(uuid,uuid)') IS NULL
    OR pg_catalog.to_regprocedure('public.reserve_monthly_ai_budget(uuid,uuid,text,bigint)') IS NULL THEN
    RAISE EXCEPTION 'Apply the bounded voice relay migrations first';
  END IF;
  IF pg_catalog.to_regclass('public.support_work_sessions') IS NULL
    OR pg_catalog.to_regclass('public.support_activities') IS NULL
    OR pg_catalog.to_regclass('public.support_privacy_state') IS NULL
    OR pg_catalog.to_regclass('public.support_context_receipts') IS NULL
    OR pg_catalog.to_regclass('public.support_context_receipt_sources') IS NULL
    OR pg_catalog.to_regclass('public.support_suppressions') IS NULL
    OR pg_catalog.to_regclass('public.companion_memory') IS NULL
    OR pg_catalog.to_regclass('public.daily_intents') IS NULL
    OR pg_catalog.to_regprocedure('public.support_ensure_privacy_state(uuid)') IS NULL
    OR pg_catalog.to_regprocedure('public.support_origin_conversation(uuid,uuid)') IS NULL
    OR pg_catalog.to_regprocedure('public.support_try_uuid(text)') IS NULL
    OR pg_catalog.to_regprocedure('public.support_try_ts(text)') IS NULL
    OR pg_catalog.to_regprocedure('public.support_capabilities()') IS NULL THEN
    RAISE EXCEPTION 'Apply the support-session migrations first';
  END IF;
  -- M3 r4 concurrency and time contract; refuse the earlier M3 chain that lacks it.
  IF pg_catalog.to_regprocedure('public.support_acquire_write_mutex()') IS NULL
    OR pg_catalog.to_regprocedure('public.support_memory_time_eligible(public.companion_memory,timestamp with time zone)') IS NULL THEN
    RAISE EXCEPTION 'Apply the finalized M3 chain (support_acquire_write_mutex, support_memory_time_eligible) first';
  END IF;
  -- Latest M3: server-owned message versions and the statement mutex on message rewrites.
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'content_revision')
    OR pg_catalog.to_regprocedure('public.support_message_revision_guard()') IS NULL
    OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
        WHERE tgrelid = 'public.messages'::regclass AND tgname = 'aaa_support_write_mutex_messages_trg')
    OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
        WHERE tgrelid = 'public.messages'::regclass AND tgname = 'support_message_revision_guard_trg') THEN
    RAISE EXCEPTION 'Apply the latest M3 chain (messages.content_revision and its guard and mutex triggers) first';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Reservation markers. Existing (legacy) rows keep both false.
-- ---------------------------------------------------------------------------
ALTER TABLE public.voice_relay_reservations
  ADD COLUMN context_required boolean NOT NULL DEFAULT false,
  ADD COLUMN context_claim_ok boolean NOT NULL DEFAULT false;

-- A context_required reservation can be claimed only inside claim_voice_relay_context, which
-- sets context_claim_ok in the same transaction (rolled back if the claim raises). The marker
-- never reverts. This holds for every caller of claim_voice_relay, whatever its body.
CREATE FUNCTION public.voice_relay_context_claim_guard() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
  IF OLD.context_required AND NOT NEW.context_required THEN
    RAISE EXCEPTION 'VOICE_CONTEXT_REQUIRED';
  END IF;
  IF NEW.context_required AND NEW.claimed_at IS NOT NULL AND OLD.claimed_at IS NULL
     AND NOT NEW.context_claim_ok THEN
    RAISE EXCEPTION 'VOICE_CONTEXT_REQUIRED';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER voice_relay_context_claim_guard_trg
  BEFORE UPDATE ON public.voice_relay_reservations
  FOR EACH ROW EXECUTE FUNCTION public.voice_relay_context_claim_guard();

-- ---------------------------------------------------------------------------
-- Binding: one row per new-contract admission. Content-free by construction.
-- ---------------------------------------------------------------------------
CREATE TABLE public.voice_relay_context_bindings (
  session_id uuid PRIMARY KEY REFERENCES public.voice_relay_reservations(session_id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  support_session_id uuid NOT NULL,
  conversation_id uuid NOT NULL,
  context_scope text NOT NULL CHECK (context_scope IN ('conversation_only', 'personalized')),
  privacy_revision bigint NOT NULL CHECK (privacy_revision >= 1),
  context_receipt_id uuid NOT NULL REFERENCES public.support_context_receipts(id) ON DELETE CASCADE,
  packet_sha256 text NOT NULL CHECK (packet_sha256 ~ '^[0-9a-f]{64}$'),
  packet_bytes integer NOT NULL CHECK (packet_bytes BETWEEN 1 AND 8000),
  provider_vendor text NOT NULL CHECK (provider_vendor IN ('openai', 'xai')),
  provider_model text NOT NULL CHECK (char_length(provider_model) BETWEEN 1 AND 64),
  route_version text NOT NULL CHECK (char_length(route_version) BETWEEN 1 AND 32),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX voice_relay_context_bindings_owner_idx
  ON public.voice_relay_context_bindings (user_id, created_at);
ALTER TABLE public.voice_relay_context_bindings ENABLE ROW LEVEL SECURITY;
-- Platform default privileges may already have granted every API role; reset them all so the
-- only write path is the definer wrappers below.
REVOKE ALL ON public.voice_relay_context_bindings FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.voice_relay_context_bindings TO service_role;
COMMENT ON TABLE public.voice_relay_context_bindings IS
'Service-only. Owner/session/conversation/scope/privacy revision/receipt/packet SHA-256/provider route bound to one voice admission. Holds no instruction, memory or transcript text; the packet is re-derived from current sources and must hash identically.';

-- ---------------------------------------------------------------------------
-- Source verification shared by prepare, claim and the lease check.
-- Returns NULL when every cited source is owned, eligible AT p_at and at its admitted
-- revision, otherwise the error code. Reads only. p_at MUST be a clock_timestamp() read after
-- the caller's locks (the lease check holds none and reads it immediately before calling);
-- it is never now()/transaction start. Time eligibility is M3's own rule (expiry, and the
-- explicit or default 90-day life-context review deadline).
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.voice_relay_context_sources_ok(
  p_user uuid, p_support_session uuid, p_conversation uuid, p_scope text, p_sources jsonb, p_at timestamptz
) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_src jsonb; v_kind text; v_id uuid; v_rev bigint; v_session_seen boolean := false;
  v_msg_rev bigint; v_msg_conv uuid;
  m public.companion_memory%ROWTYPE; ss public.support_work_sessions%ROWTYPE; act public.support_activities%ROWTYPE;
  v_safety constant uuid := '00000000-0000-0000-0000-000000000001';
BEGIN
  IF p_at IS NULL OR p_sources IS NULL OR jsonb_typeof(p_sources) <> 'array' OR jsonb_array_length(p_sources) > 64 THEN
    RETURN 'INVALID_VOICE_CONTEXT';
  END IF;
  -- A suppressed (legacy-provenance) conversation contributes nothing to voice context.
  IF EXISTS (SELECT 1 FROM public.support_suppressions s
             WHERE s.user_id = p_user AND s.kind = 'conversation' AND s.ref_id = p_conversation) THEN
    RETURN 'PRIVACY_REVISION_STALE';
  END IF;
  FOR v_src IN SELECT * FROM jsonb_array_elements(p_sources) LOOP
    v_kind := v_src ->> 'kind';
    v_id := public.support_try_uuid(v_src ->> 'id');
    IF v_kind IS NULL OR v_id IS NULL THEN RETURN 'INVALID_VOICE_CONTEXT'; END IF;
    v_rev := CASE WHEN coalesce(v_src ->> 'revision', '') ~ '^[0-9]{1,15}$' THEN (v_src ->> 'revision')::bigint END;
    IF v_kind = 'companion_memory' THEN
      IF p_scope <> 'personalized' OR v_rev IS NULL THEN RETURN 'INVALID_VOICE_CONTEXT'; END IF;
      SELECT * INTO m FROM public.companion_memory WHERE id = v_id AND user_id = p_user;
      IF NOT FOUND OR m.deleted_at IS NOT NULL OR m.disabled_at IS NOT NULL OR m.revision <> v_rev
         OR NOT public.support_memory_time_eligible(m, p_at)
         OR EXISTS (SELECT 1 FROM public.support_suppressions s WHERE s.user_id = p_user AND (
              (s.kind = 'memory' AND s.ref_id = m.id)
           OR (s.kind = 'message' AND s.ref_id = m.source_message_id)
           OR (s.kind = 'conversation' AND s.ref_id = public.support_origin_conversation(m.source_conversation_id, m.source_message_id)))) THEN
        RETURN 'PRIVACY_REVISION_STALE';
      END IF;
    ELSIF v_kind = 'message' THEN
      -- Exact cited version (M3 messages.content_revision). An omitted or null revision means 0,
      -- the stored default - never "any version"; a present but malformed one is refused.
      IF v_rev IS NULL THEN
        IF v_src ? 'revision' AND jsonb_typeof(v_src -> 'revision') <> 'null' THEN
          RETURN 'INVALID_VOICE_CONTEXT';
        END IF;
        v_rev := 0;
      END IF;
      SELECT ms.content_revision, ms.conversation_id INTO v_msg_rev, v_msg_conv
        FROM public.messages ms JOIN public.conversations c ON c.id = ms.conversation_id
        WHERE ms.id = v_id AND c.user_id = p_user;
      -- Missing/deleted, not owned, edited or re-roled or re-origined (version moved), or moved
      -- to another conversation: all stale. Only an unchanged turn in THIS conversation passes.
      IF NOT FOUND OR v_msg_rev <> v_rev OR v_msg_conv <> p_conversation
         OR EXISTS (SELECT 1 FROM public.support_suppressions s WHERE s.user_id = p_user AND (
              (s.kind = 'message' AND s.ref_id = v_id)
           OR (s.kind = 'conversation' AND s.ref_id = v_msg_conv))) THEN
        RETURN 'PRIVACY_REVISION_STALE';
      END IF;
    ELSIF v_kind = 'daily_intent' THEN
      IF p_scope <> 'personalized' THEN RETURN 'INVALID_VOICE_CONTEXT'; END IF;
      IF NOT EXISTS (SELECT 1 FROM public.daily_intents d
                     WHERE d.id = v_id AND d.user_id = p_user AND d.expires_at > p_at) THEN
        RETURN 'PRIVACY_REVISION_STALE';
      END IF;
    ELSIF v_kind = 'session' THEN
      IF v_id <> p_support_session OR v_rev IS NULL THEN RETURN 'INVALID_VOICE_CONTEXT'; END IF;
      SELECT * INTO ss FROM public.support_work_sessions WHERE id = v_id AND user_id = p_user;
      IF NOT FOUND OR ss.status <> 'open' OR ss.context_revision <> v_rev
         OR ss.conversation_id IS DISTINCT FROM p_conversation THEN
        RETURN 'PRIVACY_REVISION_STALE';
      END IF;
      v_session_seen := true;
    ELSIF v_kind = 'activity_result' THEN
      IF v_rev IS NULL THEN RETURN 'INVALID_VOICE_CONTEXT'; END IF;
      SELECT * INTO act FROM public.support_activities
        WHERE id = v_id AND user_id = p_user AND support_session_id = p_support_session;
      IF NOT FOUND OR act.context_revision <> v_rev
         OR EXISTS (SELECT 1 FROM public.support_suppressions s
                    WHERE s.user_id = p_user AND s.kind = 'activity' AND s.ref_id = act.id) THEN
        RETURN 'PRIVACY_REVISION_STALE';
      END IF;
    ELSIF v_kind = 'safety_policy' THEN
      IF v_id <> v_safety THEN RETURN 'INVALID_VOICE_CONTEXT'; END IF;
    ELSE
      RETURN 'INVALID_VOICE_CONTEXT';
    END IF;
  END LOOP;
  -- The session the packet was built from must itself be cited, so it is revision-checked.
  IF NOT v_session_seen THEN RETURN 'INVALID_VOICE_CONTEXT'; END IF;
  RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------------
-- M3 lock pass, in M3's canonical order (r4 support_confirm_chat_turn): write mutex ->
-- cited memory rows -> privacy -> session -> cited activities -> cited messages. Shared locks only. The wrappers
-- have already taken the mutex (and their voice locks) first; this re-takes it, which is a
-- no-op, so a caller can never reach the row locks without it. Returns the locked privacy
-- revision. The caller reads the wall clock only AFTER this returns.
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.voice_relay_context_lock_sources(p_user uuid, p_support_session uuid, p_sources jsonb) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE v_priv bigint;
BEGIN
  IF p_user IS NULL OR p_support_session IS NULL OR p_sources IS NULL OR jsonb_typeof(p_sources) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_VOICE_CONTEXT';
  END IF;
  PERFORM public.support_acquire_write_mutex();
  PERFORM 1 FROM public.companion_memory
    WHERE user_id = p_user AND id IN (
      SELECT public.support_try_uuid(e ->> 'id') FROM jsonb_array_elements(p_sources) e
      WHERE e ->> 'kind' = 'companion_memory')
    ORDER BY id FOR SHARE;
  PERFORM public.support_ensure_privacy_state(p_user);
  SELECT privacy_revision INTO v_priv FROM public.support_privacy_state WHERE user_id = p_user FOR SHARE;
  PERFORM 1 FROM public.support_work_sessions WHERE id = p_support_session AND user_id = p_user FOR SHARE;
  PERFORM 1 FROM public.support_activities
    WHERE user_id = p_user AND support_session_id = p_support_session AND id IN (
      SELECT public.support_try_uuid(e ->> 'id') FROM jsonb_array_elements(p_sources) e
      WHERE e ->> 'kind' = 'activity_result')
    ORDER BY id FOR SHARE;
  -- Cited turns last, as M3 locks them while verifying. Message rewrites and deletes already
  -- queue behind the mutex; this row lock additionally holds off an FK-cascade delete (which
  -- bypasses the statement trigger) until we commit.
  PERFORM 1 FROM public.messages ms JOIN public.conversations c ON c.id = ms.conversation_id
    WHERE c.user_id = p_user AND ms.id IN (
      SELECT public.support_try_uuid(e ->> 'id') FROM jsonb_array_elements(p_sources) e
      WHERE e ->> 'kind' = 'message')
    ORDER BY ms.id FOR SHARE OF ms;
  RETURN v_priv;
END;
$$;

-- ---------------------------------------------------------------------------
-- POST: atomic verify + prepare + mark + receipt + binding
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.prepare_voice_relay_context(
  p_user_id uuid, p_support_session_id uuid, p_conversation_id uuid, p_scope text,
  p_privacy_revision bigint, p_packet_sha256 text, p_packet_bytes integer,
  p_provider_vendor text, p_provider_model text, p_route_version text,
  p_sources jsonb, p_exclusions jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_cur bigint; v_session public.support_work_sessions%ROWTYPE; v_now timestamptz;
  v_prepared jsonb; v_sid uuid; v_receipt uuid; v_bad text;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501'; END IF;
  IF p_user_id IS NULL OR p_support_session_id IS NULL OR p_conversation_id IS NULL
     OR coalesce(p_scope, '') NOT IN ('conversation_only', 'personalized')
     OR p_privacy_revision IS NULL OR p_privacy_revision < 1
     OR coalesce(p_packet_sha256, '') !~ '^[0-9a-f]{64}$'
     OR p_packet_bytes IS NULL OR p_packet_bytes NOT BETWEEN 1 AND 8000
     OR coalesce(p_provider_vendor, '') NOT IN ('openai', 'xai')
     OR coalesce(p_provider_model, '') = '' OR coalesce(p_route_version, '') = ''
     OR jsonb_typeof(p_sources) IS DISTINCT FROM 'array'
     OR jsonb_typeof(p_exclusions) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'INVALID_VOICE_CONTEXT';
  END IF;
  -- 1. M3 write mutex FIRST (before any privacy/session/memory/voice lock).
  PERFORM public.support_acquire_write_mutex();
  -- 2. The owner lock the existing wrappers take first (re-entrant inside prepare_voice_relay).
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 76543));
  -- 4-7. Cited memories -> privacy -> session -> cited activities (M3 canonical order).
  v_cur := public.voice_relay_context_lock_sources(p_user_id, p_support_session_id, p_sources);
  -- 8. Final eligibility boundary: wall clock AFTER every blocking lock above.
  v_now := clock_timestamp();

  IF NOT EXISTS (SELECT 1 FROM public.conversations WHERE id = p_conversation_id AND user_id = p_user_id) THEN
    RAISE EXCEPTION 'SESSION_NOT_FOUND';
  END IF;
  SELECT * INTO v_session FROM public.support_work_sessions
    WHERE id = p_support_session_id AND user_id = p_user_id AND status = 'open';
  IF NOT FOUND THEN RAISE EXCEPTION 'SESSION_NOT_FOUND'; END IF;
  -- Voice binds an ATTACHED session: the conversation must be the session's own.
  IF v_session.conversation_id IS DISTINCT FROM p_conversation_id THEN
    RAISE EXCEPTION 'SESSION_CONVERSATION_MISMATCH';
  END IF;
  -- A request may narrow, never widen, the session's scope.
  IF p_scope = 'personalized' AND v_session.context_scope <> 'personalized' THEN
    RAISE EXCEPTION 'SCOPE_MISMATCH';
  END IF;
  IF v_cur IS DISTINCT FROM p_privacy_revision THEN RAISE EXCEPTION 'PRIVACY_REVISION_STALE'; END IF;
  v_bad := public.voice_relay_context_sources_ok(p_user_id, p_support_session_id, p_conversation_id, p_scope, p_sources, v_now);
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION '%', v_bad; END IF;

  -- Existing admission-time limits (3/minute, minutes quota) apply unchanged; any raise
  -- here rolls back everything above and below.
  v_prepared := public.prepare_voice_relay(p_user_id);
  v_sid := (v_prepared ->> 'session_id')::uuid;
  UPDATE public.voice_relay_reservations SET context_required = true
    WHERE session_id = v_sid AND user_id = p_user_id AND claimed_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_SESSION'; END IF;

  INSERT INTO public.support_context_receipts (
    user_id, request_id, support_session_id, conversation_id, assistant_message_id,
    privacy_revision, scope, provider_vendor, provider_model, route_version, exclusions)
  VALUES (
    p_user_id, v_sid, p_support_session_id, p_conversation_id, NULL,
    v_cur, p_scope, p_provider_vendor, p_provider_model, p_route_version,
    coalesce(ARRAY(SELECT jsonb_array_elements_text(p_exclusions)), '{}'))
  RETURNING id INTO v_receipt;
  INSERT INTO public.support_context_receipt_sources (
    receipt_id, user_id, source_kind, source_id, source_revision, source_date)
  SELECT v_receipt, p_user_id, e ->> 'kind', public.support_try_uuid(e ->> 'id'),
         CASE WHEN coalesce(e ->> 'revision', '') ~ '^[0-9]{1,15}$' THEN (e ->> 'revision')::bigint ELSE 0 END,
         public.support_try_ts(e ->> 'date')
  FROM jsonb_array_elements(p_sources) e
  ON CONFLICT DO NOTHING;
  INSERT INTO public.voice_relay_context_bindings (
    session_id, user_id, support_session_id, conversation_id, context_scope, privacy_revision,
    context_receipt_id, packet_sha256, packet_bytes, provider_vendor, provider_model, route_version)
  VALUES (
    v_sid, p_user_id, p_support_session_id, p_conversation_id, p_scope, v_cur,
    v_receipt, p_packet_sha256, p_packet_bytes, p_provider_vendor, p_provider_model, p_route_version);

  RETURN v_prepared || pg_catalog.jsonb_build_object(
    'context_receipt_id', v_receipt, 'privacy_revision', v_cur,
    'packet_sha256', p_packet_sha256, 'packet_bytes', p_packet_bytes);
END;
$$;

-- ---------------------------------------------------------------------------
-- GET step 1 (read-only): is this preparation a new-contract admission, and on which route?
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.voice_relay_context_binding(p_user_id uuid, p_session_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE b public.voice_relay_context_bindings%ROWTYPE;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501'; END IF;
  SELECT * INTO b FROM public.voice_relay_context_bindings
    WHERE session_id = p_session_id AND user_id = p_user_id;
  IF NOT FOUND THEN RETURN pg_catalog.jsonb_build_object('bound', false); END IF;
  RETURN pg_catalog.jsonb_build_object(
    'bound', true, 'support_session_id', b.support_session_id, 'conversation_id', b.conversation_id,
    'context_scope', b.context_scope, 'privacy_revision', b.privacy_revision,
    'context_receipt_id', b.context_receipt_id, 'packet_sha256', b.packet_sha256,
    'packet_bytes', b.packet_bytes, 'provider_vendor', b.provider_vendor,
    'provider_model', b.provider_model, 'route_version', b.route_version);
END;
$$;

-- ---------------------------------------------------------------------------
-- GET step 3: revalidate, then the unchanged budgeted claim
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.claim_voice_relay_context(p_user_id uuid, p_session_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  b public.voice_relay_context_bindings%ROWTYPE; v_res public.voice_relay_reservations%ROWTYPE;
  v_session public.support_work_sessions%ROWTYPE; v_cur bigint; v_now timestamptz;
  v_sources jsonb; v_bad text; v_claim jsonb;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501'; END IF;
  IF p_user_id IS NULL OR p_session_id IS NULL THEN RAISE EXCEPTION 'INVALID_SESSION'; END IF;
  -- 1. M3 write mutex FIRST, before the owner lock, any voice row lock or any M3 row lock.
  PERFORM public.support_acquire_write_mutex();
  -- 2-3. Then the existing claim order: owner advisory lock, voice_sessions row, reservation row.
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text, 76543));
  PERFORM 1 FROM public.voice_sessions WHERE id = p_session_id AND user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_SESSION'; END IF;
  SELECT * INTO v_res FROM public.voice_relay_reservations
    WHERE session_id = p_session_id AND user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_SESSION'; END IF;
  IF NOT v_res.context_required THEN RAISE EXCEPTION 'VOICE_CONTEXT_REQUIRED'; END IF;
  SELECT * INTO b FROM public.voice_relay_context_bindings
    WHERE session_id = p_session_id AND user_id = p_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'VOICE_CONTEXT_REQUIRED'; END IF;
  SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'kind', s.source_kind, 'id', s.source_id, 'revision', s.source_revision)), '[]'::jsonb)
    INTO v_sources FROM public.support_context_receipt_sources s
    WHERE s.receipt_id = b.context_receipt_id AND s.user_id = p_user_id;

  -- 4-7. Cited memories -> privacy -> session -> cited activities (M3 canonical order).
  v_cur := public.voice_relay_context_lock_sources(p_user_id, b.support_session_id, v_sources);
  -- 8. Final eligibility boundary: wall clock AFTER every blocking lock above.
  v_now := clock_timestamp();

  SELECT * INTO v_session FROM public.support_work_sessions
    WHERE id = b.support_session_id AND user_id = p_user_id AND status = 'open';
  IF NOT FOUND THEN RAISE EXCEPTION 'SESSION_NOT_FOUND'; END IF;
  IF v_session.conversation_id IS DISTINCT FROM b.conversation_id THEN
    RAISE EXCEPTION 'SESSION_CONVERSATION_MISMATCH';
  END IF;
  IF b.context_scope = 'personalized' AND v_session.context_scope <> 'personalized' THEN
    RAISE EXCEPTION 'SCOPE_MISMATCH';
  END IF;
  IF v_cur IS DISTINCT FROM b.privacy_revision THEN RAISE EXCEPTION 'PRIVACY_REVISION_STALE'; END IF;
  v_bad := public.voice_relay_context_sources_ok(
    p_user_id, b.support_session_id, b.conversation_id, b.context_scope, v_sources, v_now);
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION '%', v_bad; END IF;

  -- 9. Authorizes exactly this claim for the guard trigger. If claim_voice_relay raises
  -- (replay, expired, active relay, minutes, daily budget, monthly reserve) the flag rolls
  -- back too. The global budget lock (76544) and the monthly budget locks are taken INSIDE
  -- claim_voice_relay, after every lock above, and are the steps that can block for a while.
  UPDATE public.voice_relay_reservations SET context_claim_ok = true WHERE session_id = p_session_id;
  v_claim := public.claim_voice_relay(p_user_id, p_session_id);
  -- 10. FINAL eligibility boundary: a fresh wall-clock read AFTER the global/monthly waits and
  -- before this transaction can commit. The privacy row, session, cited memories, activities
  -- and turns are still share-locked, so no writer could have changed them; only the passage
  -- of time can have crossed a deadline during step 9. If it did, raising here aborts the whole
  -- transaction: the claimed reservation, context_claim_ok and the monthly debit are rolled
  -- back together, and the caller issues no secret and opens no socket.
  v_bad := public.voice_relay_context_sources_ok(
    p_user_id, b.support_session_id, b.conversation_id, b.context_scope, v_sources, clock_timestamp());
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION '%', v_bad; END IF;
  RETURN v_claim || pg_catalog.jsonb_build_object(
    'support_session_id', b.support_session_id, 'conversation_id', b.conversation_id,
    'context_scope', b.context_scope, 'privacy_revision', b.privacy_revision,
    'context_receipt_id', b.context_receipt_id, 'packet_sha256', b.packet_sha256,
    'provider_vendor', b.provider_vendor, 'provider_model', b.provider_model,
    'route_version', b.route_version);
END;
$$;

-- ---------------------------------------------------------------------------
-- Lease refresh. Lock-free by design (see LOCK ORDER). Every call re-evaluates the time rules
-- with a fresh clock_timestamp(): an expiry or review deadline that passes mid-call changes no
-- row and no privacy revision, so this is the only place it can be noticed.
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.voice_relay_context_check(p_user_id uuid, p_session_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  b public.voice_relay_context_bindings%ROWTYPE; ss public.support_work_sessions%ROWTYPE;
  v_cur bigint; v_bad text; v_sources jsonb;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501'; END IF;
  SELECT * INTO b FROM public.voice_relay_context_bindings
    WHERE session_id = p_session_id AND user_id = p_user_id;
  IF NOT FOUND THEN RETURN pg_catalog.jsonb_build_object('ok', false, 'code', 'VOICE_CONTEXT_REQUIRED'); END IF;
  SELECT coalesce(max(privacy_revision), 1) INTO v_cur FROM public.support_privacy_state WHERE user_id = p_user_id;
  IF v_cur <> b.privacy_revision THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'code', 'PRIVACY_REVISION_STALE');
  END IF;
  SELECT * INTO ss FROM public.support_work_sessions WHERE id = b.support_session_id AND user_id = p_user_id;
  IF NOT FOUND OR ss.status <> 'open' OR ss.conversation_id IS DISTINCT FROM b.conversation_id
     OR (b.context_scope = 'personalized' AND ss.context_scope <> 'personalized') THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'code', 'SESSION_NOT_FOUND');
  END IF;
  SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'kind', s.source_kind, 'id', s.source_id, 'revision', s.source_revision)), '[]'::jsonb)
    INTO v_sources FROM public.support_context_receipt_sources s
    WHERE s.receipt_id = b.context_receipt_id AND s.user_id = p_user_id;
  v_bad := public.voice_relay_context_sources_ok(
    p_user_id, b.support_session_id, b.conversation_id, b.context_scope, v_sources, clock_timestamp());
  IF v_bad IS NOT NULL THEN RETURN pg_catalog.jsonb_build_object('ok', false, 'code', v_bad); END IF;
  RETURN pg_catalog.jsonb_build_object('ok', true, 'privacy_revision', v_cur, 'packet_sha256', b.packet_sha256);
END;
$$;

-- ---------------------------------------------------------------------------
-- Capability negotiation: advertise voice_context 1 without redefining M3's other keys.
-- ---------------------------------------------------------------------------
ALTER FUNCTION public.support_capabilities() RENAME TO support_capabilities_base;
REVOKE ALL ON FUNCTION public.support_capabilities_base() FROM PUBLIC, anon, authenticated, service_role;
CREATE FUNCTION public.support_capabilities() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
  SELECT public.support_capabilities_base()
    || pg_catalog.jsonb_build_object('voice_context', 1, 'voice_privacy_lease_ms', 5000);
$$;

-- ---------------------------------------------------------------------------
-- Grants: service role only, except the capability probe M3 already exposed.
-- ---------------------------------------------------------------------------
-- Internal helpers: callable only by the definer wrappers (which run as the function owner).
REVOKE ALL ON FUNCTION
  public.voice_relay_context_claim_guard(),
  public.voice_relay_context_sources_ok(uuid, uuid, uuid, text, jsonb, timestamptz),
  public.voice_relay_context_lock_sources(uuid, uuid, jsonb)
FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.prepare_voice_relay_context(uuid, uuid, uuid, text, bigint, text, integer, text, text, text, jsonb, jsonb),
  public.voice_relay_context_binding(uuid, uuid),
  public.claim_voice_relay_context(uuid, uuid),
  public.voice_relay_context_check(uuid, uuid)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.prepare_voice_relay_context(uuid, uuid, uuid, text, bigint, text, integer, text, text, text, jsonb, jsonb),
  public.voice_relay_context_binding(uuid, uuid),
  public.claim_voice_relay_context(uuid, uuid),
  public.voice_relay_context_check(uuid, uuid)
TO service_role;
REVOKE ALL ON FUNCTION public.support_capabilities() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.support_capabilities() TO authenticated, service_role;

COMMENT ON FUNCTION public.prepare_voice_relay_context(uuid, uuid, uuid, text, bigint, text, integer, text, text, text, jsonb, jsonb) IS
'Atomic new-contract voice admission: verifies owner/session/conversation/scope/privacy revision/sources, calls the unchanged prepare_voice_relay, marks the reservation context_required and stores receipt references plus the packet SHA-256 and provider route in one transaction.';
COMMENT ON FUNCTION public.claim_voice_relay_context(uuid, uuid) IS
'Revalidates the bound packet (owner, session, scope, privacy revision, cited source revisions) and then calls the unchanged claim_voice_relay so every owner/global/monthly admission check still applies. The guard trigger refuses any other claim of a context_required reservation.';

COMMIT;
