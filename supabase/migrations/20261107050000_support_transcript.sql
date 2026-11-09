-- Voice transcript append (docs/SUPPORT_SESSION_SPEC.md 9.8, "transcript events").
-- NOT EXECUTED by its author; no deployment or SQL execution is authorized by this file.
-- Forward-only. Requires the LATEST M3 chain (20261106230000 ... 20261106230200: the private
-- support_acquire_write_mutex, support_raise, messages.content_revision and its guard).
-- Sorts after 20261107040000_support_data_export.sql.
--
-- Model. A final voice transcript turn IS a canonical `messages` row: id = the app's stable
-- local event UUID, role/content reused, created_at = the time the speech actually occurred
-- (so every existing created_at reader sees chronological order even when an older final
-- arrives after a newer one). There is NO second transcript-text table. Five nullable,
-- content-free columns carry the provenance the spec asks for:
--     voice_call_id, voice_event_order, voice_provider_item_id, voice_provider_event_id,
--     voice_occurred_at, voice_source_session_id
-- plus the existing messages.support_session_id for the CURRENT owning support session.
-- voice_source_session_id is the IMMUTABLE record of the session the event was originally stored
-- under (an identifier only, never text). M3's session delete deliberately clears BOTH
-- messages.support_session_id and the tombstone's conversation_id, so after a delete nothing else
-- can prove which session an event came from; replay therefore requires this exact id.
--
-- Provenance cannot be forged. Those columns are RESERVED: a BEFORE INSERT/UPDATE guard
-- clears them on a direct insert (the row itself is kept, so legacy same-owner inserts stay
-- compatible) and restores them on a direct update, unless the write comes from
-- append_support_transcript - a transaction-local marker AND a non-API current_user (the
-- function owner), so neither the marker alone nor a spoofed value is enough.
--
-- API (authenticated only):
--   public.append_support_transcript(
--     p_expected_owner uuid, p_session_id uuid, p_conversation_id uuid, p_event_id uuid,
--     p_voice_call_id uuid, p_event_order bigint, p_role text, p_text text,
--     p_occurred_at timestamptz, p_provider_item_id text DEFAULT NULL,
--     p_provider_event_id text DEFAULT NULL) RETURNS jsonb
--   Success: {"ok":true,"replay":bool,"event_id","message_id","conversation_id",
--             "voice_call_id","event_order","role","occurred_at"}   (no body is ever echoed)
--   Failure: {"ok":false,"code":C,"message":optional} with C in
--     OWNER_MISMATCH, INVALID_PAYLOAD, NOT_FOUND, SESSION_CONVERSATION_MISMATCH,
--     CONTENT_UNAVAILABLE, OPERATION_ID_REUSED.
--   No auth.uid(): raises AUTH_REQUIRED (SQLSTATE 42501). anon/service_role cannot execute.
--
-- Closed sessions. Closing a session preserves its history and its conversation attachment, and a
-- final transcript turn can have been acknowledged locally BEFORE an offline close. A first
-- upload after Close is therefore accepted as STORAGE-ONLY reconciliation for a closed,
-- undeleted, owned session attached to the exact owned conversation: the same ids, bounds and
-- replay-first semantics, no session/activity/reward write, no AI, and no conversation re-ranking.
-- Voice Start/admission stays open-only (that is the voice admission functions, not this file).
-- A DELETED session still takes nothing (NOT_FOUND) and a suppressed conversation or message id
-- still takes nothing (CONTENT_UNAVAILABLE), so no erased content can come back.
--
-- Conversation deletion enters the write mutex first (TR-R04). support_work_sessions.conversation_id is
-- ON DELETE SET NULL, so an ordinary DELETE FROM conversations locks the conversation row and THEN needs
-- the session row for the foreign-key update, while an append holds the session row (shared) and then
-- wants the conversation row: a lock cycle (40P01). A BEFORE DELETE FOR EACH STATEMENT trigger on
-- conversations, reusing M3's own support_write_mutex_statement(), makes every conversation DELETE take
-- the private mutex BEFORE it locks any row, exactly like M3's triggers on messages, companion_memory,
-- daily_intents and memory_fragments. Owner RLS ("manage own conversations") and every other behavior of
-- conversations are untouched. Whether a foreign-key CASCADE delete (account deletion) also fires this
-- statement trigger is a PostgreSQL behavior that this file does NOT assume either way; it is a
-- qualification item for a real run (see the harness notes in supabase/tests/support_transcript.sql).
--
-- Direct reader for the UI (authenticated only), so the app and the AI context agree on order:
--   public.support_get_conversation_messages(p_expected_owner uuid, p_conversation_id uuid,
--                                            p_limit integer DEFAULT 50) RETURNS jsonb
--   Returns a JSON ARRAY of the LATEST p_limit canonical messages, oldest -> newest, each exactly
--     {"id","conversation_id","role","content","created_at","content_origin","voice_call_id","voice_event_order"}
--   (voice_call_id / voice_event_order / content_origin are null when absent; created_at is the stored
--   value, never rewritten). "Latest" and the final order use the SAME call-anchor / provider-order key as
--   support_context_sources below; the limit is applied after that ordering. Nothing is filtered by role,
--   origin or suppression (what the person can see is not what the model may use), and nothing is
--   written, locked or stored. Not an envelope: failures RAISE (SQLSTATE in parentheses): AUTH_REQUIRED
--   (42501), OWNER_MISMATCH (42501), INVALID_PAYLOAD for a limit outside 1..100 or NULL (22023),
--   NOT_FOUND for a conversation that is not the caller's, whether foreign or nonexistent (PT404).
--   SECURITY INVOKER with a fixed search_path: row-level security on messages/conversations enforces
--   ownership independently of the explicit check, and no privilege is elevated.
--
-- History order. support_context_sources (the one shared reader of conversation history for text
-- and voice context) is replaced, byte for byte except its history projection, so that a voice
-- call's turns sort by the provider observation order. created_at alone cannot: the wire rounds
-- to milliseconds, so order 1 and order 2 can tie or even invert.
BEGIN;

DO $$ BEGIN
  IF pg_catalog.to_regclass('public.messages') IS NULL
    OR pg_catalog.to_regclass('public.conversations') IS NULL
    OR pg_catalog.to_regclass('public.support_work_sessions') IS NULL
    OR pg_catalog.to_regclass('public.support_suppressions') IS NULL
    OR pg_catalog.to_regtype('public.message_role') IS NULL
    OR pg_catalog.to_regprocedure('public.support_raise(text,text)') IS NULL
    OR pg_catalog.to_regprocedure('public.support_ensure_privacy_state(uuid)') IS NULL
    OR pg_catalog.to_regprocedure('public.support_acquire_write_mutex()') IS NULL
    OR pg_catalog.to_regprocedure('public.support_write_mutex_statement()') IS NULL
    OR pg_catalog.to_regprocedure('public.support_message_revision_guard()') IS NULL
    OR NOT EXISTS (SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'content_revision')
    OR NOT EXISTS (SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'support_session_id') THEN
    RAISE EXCEPTION 'Apply the latest M3 support-session chain first';
  END IF;
END $$;

-- The reader replaced below is copied from the AUDITED root M3 definition. Refuse to replace
-- anything else: a drifted or locally modified function must never be overwritten by a stale copy.
-- Hash = sha256 of pg_proc.prosrc of root supabase/migrations/20261106230200_support_memory_context.sql
-- (file sha256 7061e7b1a98aa806f3c440f54ad15867a2e0493112fdbc6165b065854bb6d4b1), function body 2796 bytes.
DO $$
DECLARE v_src text; v_sec boolean; v_vol "char"; v_cfg text[];
BEGIN
  SELECT p.prosrc, p.prosecdef, p.provolatile, p.proconfig INTO v_src, v_sec, v_vol, v_cfg
    FROM pg_catalog.pg_proc p
    WHERE p.oid = pg_catalog.to_regprocedure('public.support_context_sources(uuid,uuid,integer,boolean)')::oid;
  IF v_src IS NULL THEN
    RAISE EXCEPTION 'public.support_context_sources(uuid,uuid,integer,boolean) is missing; apply the latest M3 chain first';
  END IF;
  IF pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(v_src, 'UTF8')), 'hex')
       <> 'c1956b97863a42dc32a61f5fe1861f97f77e1d425794d722e642d5780c5237e0' THEN
    RAISE EXCEPTION 'support_context_sources is not the audited M3 definition (sha256 mismatch); refusing to replace it';
  END IF;
  IF NOT v_sec OR v_vol <> 's' OR v_cfg IS DISTINCT FROM ARRAY['search_path=pg_catalog, public, pg_temp'] THEN
    RAISE EXCEPTION 'support_context_sources does not have the audited security properties; refusing to replace it';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Reserved, nullable, content-free provenance on the canonical message row
-- ---------------------------------------------------------------------------
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS voice_call_id uuid,
  ADD COLUMN IF NOT EXISTS voice_event_order bigint,
  ADD COLUMN IF NOT EXISTS voice_provider_item_id text,
  ADD COLUMN IF NOT EXISTS voice_provider_event_id text,
  ADD COLUMN IF NOT EXISTS voice_occurred_at timestamptz,
  ADD COLUMN IF NOT EXISTS voice_source_session_id uuid;

-- NOT VALID then VALIDATE: existing rows are all-NULL here, so validation cannot fail, and the
-- two-step form avoids holding the stronger lock while scanning.
ALTER TABLE public.messages
  ADD CONSTRAINT messages_voice_event_bounds CHECK (
    (voice_event_order IS NULL OR voice_event_order BETWEEN 1 AND 9007199254740991)
    AND (voice_provider_item_id IS NULL OR char_length(voice_provider_item_id) BETWEEN 1 AND 256)
    AND (voice_provider_event_id IS NULL OR char_length(voice_provider_event_id) BETWEEN 1 AND 256)) NOT VALID,
  ADD CONSTRAINT messages_voice_event_coherent CHECK (
    (voice_call_id IS NULL AND voice_event_order IS NULL AND voice_occurred_at IS NULL
       AND voice_provider_item_id IS NULL AND voice_provider_event_id IS NULL AND voice_source_session_id IS NULL)
    OR (voice_call_id IS NOT NULL AND voice_event_order IS NOT NULL AND voice_occurred_at IS NOT NULL
        AND voice_source_session_id IS NOT NULL)) NOT VALID;
ALTER TABLE public.messages VALIDATE CONSTRAINT messages_voice_event_bounds;
ALTER TABLE public.messages VALIDATE CONSTRAINT messages_voice_event_coherent;

-- One provider observation per (conversation, call, order). Scoped by the OWNED conversation,
-- so a conflict can never reveal another account's call or order.
CREATE UNIQUE INDEX messages_voice_call_order_uidx
  ON public.messages (conversation_id, voice_call_id, voice_event_order) WHERE voice_call_id IS NOT NULL;
CREATE INDEX messages_voice_call_idx ON public.messages (voice_call_id) WHERE voice_call_id IS NOT NULL;

COMMENT ON COLUMN public.messages.voice_call_id IS
'Reserved. Voice-call identity of a transcript turn; written only by append_support_transcript (guard trigger clears it on direct writes). NULL for every ordinary message.';
COMMENT ON COLUMN public.messages.voice_event_order IS
'Reserved. 1-based provider observation order within voice_call_id (not the arrival order).';
COMMENT ON COLUMN public.messages.voice_source_session_id IS
'Reserved, immutable. The support session the transcript turn was originally stored under (identifier only). Survives session deletion, which clears support_session_id; replay must name exactly this session.';
COMMENT ON COLUMN public.messages.voice_occurred_at IS
'Reserved. When the speech actually occurred (device clock, bounded server-side); created_at is set to the same instant for chronological readers.';

-- ---------------------------------------------------------------------------
-- Guard: reserved fields are writable only by append_support_transcript
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_transcript_guard() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  -- Both conditions: the transaction-local marker set inside the RPC AND a non-API role. The
  -- RPC is SECURITY DEFINER, so current_user is its owner there, never anon/authenticated.
  v_rpc boolean := coalesce(current_setting('support.transcript_rpc', true), '') = 'on'
                   AND current_user NOT IN ('anon', 'authenticated');
BEGIN
  IF v_rpc THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    -- Legacy direct insert stays valid; it just cannot claim transcript provenance.
    NEW.voice_call_id := NULL; NEW.voice_event_order := NULL;
    NEW.voice_provider_item_id := NULL; NEW.voice_provider_event_id := NULL; NEW.voice_occurred_at := NULL;
    NEW.voice_source_session_id := NULL;
  ELSE
    -- Provenance is immutable outside the RPC (session deletion's support_session_id detach
    -- and every ordinary content update are unaffected).
    NEW.voice_call_id := OLD.voice_call_id; NEW.voice_event_order := OLD.voice_event_order;
    NEW.voice_provider_item_id := OLD.voice_provider_item_id;
    NEW.voice_provider_event_id := OLD.voice_provider_event_id; NEW.voice_occurred_at := OLD.voice_occurred_at;
    NEW.voice_source_session_id := OLD.voice_source_session_id;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER support_transcript_guard_trg
  BEFORE INSERT OR UPDATE ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.support_transcript_guard();

-- ---------------------------------------------------------------------------
-- Conversation DELETE enters the private write mutex before any row lock (TR-R04)
-- ---------------------------------------------------------------------------
-- Uses M3's actual statement function (SECURITY DEFINER, so an owner-role DELETE under RLS can still enter
-- the private mutex). Created only when no equivalent ENABLED BEFORE DELETE statement trigger on
-- conversations already calls it (e.g. a later M3 revision), so the mutex is never entered twice by name.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid = 'public.conversations'::regclass AND NOT t.tgisinternal
      AND t.tgfoid = 'public.support_write_mutex_statement()'::regprocedure
      AND (t.tgtype & 1) = 0   -- FOR EACH STATEMENT
      AND (t.tgtype & 2) = 2   -- BEFORE
      AND (t.tgtype & 8) = 8   -- DELETE
      AND t.tgenabled <> 'D') THEN
    CREATE TRIGGER aaa_support_write_mutex_conversations_trg
      BEFORE DELETE ON public.conversations
      FOR EACH STATEMENT EXECUTE FUNCTION public.support_write_mutex_statement();
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid = 'public.conversations'::regclass AND NOT t.tgisinternal
      AND t.tgfoid = 'public.support_write_mutex_statement()'::regprocedure
      AND (t.tgtype & 1) = 0 AND (t.tgtype & 2) = 2 AND (t.tgtype & 8) = 8 AND t.tgenabled <> 'D') THEN
    RAISE EXCEPTION 'conversations has no enabled BEFORE DELETE statement trigger entering the write mutex; refusing';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- append_support_transcript
-- ---------------------------------------------------------------------------
-- Lock order (M3 canonical): private write mutex FIRST, then the owner's privacy row, the
-- support session, the conversation (shared locks). Every M3 context writer, the retained legacy
-- message rewrite/delete, and (above) an ordinary conversation DELETE take the same mutex before any
-- row lock, so the session-then-conversation order here cannot form a cycle with the conversation-then-
-- session order of the SET NULL foreign-key action. (An FK-cascade delete is not assumed to be covered;
-- see the qualification notes in the test file.)
-- Evaluation order: authenticate -> owner -> payload -> locks -> an ALREADY CONFIRMED owned
-- event is honored (identical => replay, different => conflict) BEFORE any session-closure,
-- attachment or privacy rejection -> only then the new-event checks. The replay path never
-- inserts, updates or touches anything.
CREATE FUNCTION public.append_support_transcript(
  p_expected_owner uuid, p_session_id uuid, p_conversation_id uuid, p_event_id uuid,
  p_voice_call_id uuid, p_event_order bigint, p_role text, p_text text, p_occurred_at timestamptz,
  p_provider_item_id text DEFAULT NULL, p_provider_event_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_nil constant uuid := '00000000-0000-0000-0000-000000000000';
  v_session public.support_work_sessions%ROWTYPE; v_session_found boolean := false;
  v_msg public.messages%ROWTYPE; v_msg_found boolean := false; v_msg_owner uuid;
  v_code text; v_detail text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501'; END IF;
  BEGIN
    -- 1. The captured owner must be the authenticated owner, before anything is looked up.
    IF p_expected_owner IS DISTINCT FROM v_uid THEN
      PERFORM public.support_raise('OWNER_MISMATCH', 'the captured owner is not the signed-in account');
    END IF;
    -- 2. Pure payload validation (no row is read; no input value is echoed).
    IF p_session_id IS NULL OR p_conversation_id IS NULL OR p_event_id IS NULL OR p_voice_call_id IS NULL
       OR p_session_id = v_nil OR p_conversation_id = v_nil OR p_event_id = v_nil OR p_voice_call_id = v_nil THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'identifiers must be non-nil UUIDs');
    END IF;
    IF p_event_order IS NULL OR p_event_order < 1 OR p_event_order > 9007199254740991 THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'event_order must be a positive integer');
    END IF;
    IF p_role IS NULL OR p_role NOT IN ('user', 'assistant') THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'role must be user or assistant');
    END IF;
    IF p_text IS NULL OR char_length(p_text) > 20000 THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'text must be at most 20000 characters');
    END IF;
    IF p_text ~ '^\s*$' THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'text must not be blank');
    END IF;
    IF p_occurred_at IS NULL OR p_occurred_at < timestamptz '2020-01-01 00:00:00+00'
       OR p_occurred_at > clock_timestamp() + interval '5 minutes' THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'occurred_at is outside the accepted range');
    END IF;
    IF (p_provider_item_id IS NOT NULL AND char_length(p_provider_item_id) NOT BETWEEN 1 AND 256)
       OR (p_provider_event_id IS NOT NULL AND char_length(p_provider_event_id) NOT BETWEEN 1 AND 256) THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'provider identifiers must be 1 to 256 characters');
    END IF;

    -- 3. Locks, M3's order. The mutex comes first; nothing else is read before it.
    PERFORM public.support_acquire_write_mutex();
    PERFORM public.support_ensure_privacy_state(v_uid);
    PERFORM 1 FROM public.support_privacy_state WHERE user_id = v_uid FOR SHARE;
    SELECT * INTO v_session FROM public.support_work_sessions
      WHERE id = p_session_id AND user_id = v_uid FOR SHARE;
    v_session_found := FOUND;
    PERFORM 1 FROM public.conversations WHERE id = p_conversation_id AND user_id = v_uid FOR SHARE;
    IF NOT FOUND THEN
      -- Not owned and not existing are the same answer. (A replay needs the conversation, too:
      -- if it is gone its messages are gone, and nothing may be recreated.)
      PERFORM public.support_raise('NOT_FOUND', 'session or conversation not found');
    END IF;

    -- 4. An already-confirmed event is honored before any later closure/privacy rejection.
    SELECT * INTO v_msg FROM public.messages WHERE id = p_event_id;
    v_msg_found := FOUND;
    IF v_msg_found THEN
      SELECT c.user_id INTO v_msg_owner FROM public.conversations c WHERE c.id = v_msg.conversation_id;
      -- Another account's id, or this account's id in another conversation, answers exactly like
      -- an altered replay: the caller learns only that the identifier is unusable.
      IF v_msg_owner IS DISTINCT FROM v_uid OR v_msg.conversation_id <> p_conversation_id
         OR v_msg.voice_call_id IS DISTINCT FROM p_voice_call_id
         OR v_msg.voice_event_order IS DISTINCT FROM p_event_order
         OR v_msg.role::text <> p_role OR v_msg.content <> p_text
         OR v_msg.voice_occurred_at IS DISTINCT FROM p_occurred_at
         OR v_msg.voice_provider_item_id IS DISTINCT FROM p_provider_item_id
         OR v_msg.voice_provider_event_id IS DISTINCT FROM p_provider_event_id
         -- The EXACT original session, from the immutable voice_source_session_id. M3's session delete
         -- clears messages.support_session_id AND the tombstone's conversation_id, so neither the
         -- current link nor "some owned session is deleted" can prove where an event came from: the
         -- stored source id must equal the named session, whether that session is live, closed or
         -- deleted, and a different session of any status is a conflict. The current link may only be
         -- NULL (detached by deletion) or the same session; nothing here ever rewrites it.
         OR v_msg.voice_source_session_id IS DISTINCT FROM p_session_id
         OR (v_msg.support_session_id IS NOT NULL AND v_msg.support_session_id <> p_session_id) THEN
        PERFORM public.support_raise('OPERATION_ID_REUSED', 'event identity conflict');
      END IF;
      RETURN jsonb_build_object('ok', true, 'replay', true, 'event_id', v_msg.id, 'message_id', v_msg.id,
        'conversation_id', v_msg.conversation_id, 'voice_call_id', v_msg.voice_call_id,
        'event_order', v_msg.voice_event_order, 'role', v_msg.role::text, 'occurred_at', v_msg.voice_occurred_at);
    END IF;

    -- 5. A NEW event: the session must be this account's, undeleted (open, or closed - a final
    -- acknowledged before an offline Close is reconciled storage-only) and attached to exactly this
    -- conversation, and nothing the account forgot may be re-introduced.
    IF NOT v_session_found OR v_session.status NOT IN ('open', 'closed') THEN
      PERFORM public.support_raise('NOT_FOUND', 'session or conversation not found');
    END IF;
    IF v_session.conversation_id IS DISTINCT FROM p_conversation_id THEN
      PERFORM public.support_raise('SESSION_CONVERSATION_MISMATCH', 'the session is not attached to this conversation');
    END IF;
    IF EXISTS (SELECT 1 FROM public.support_suppressions s WHERE s.user_id = v_uid AND (
          (s.kind = 'conversation' AND s.ref_id = p_conversation_id)
       OR (s.kind = 'message' AND s.ref_id = p_event_id))) THEN
      PERFORM public.support_raise('CONTENT_UNAVAILABLE', 'this conversation or message was removed from use');
    END IF;
    -- One call belongs to one conversation of this account.
    IF EXISTS (SELECT 1 FROM public.messages m JOIN public.conversations c ON c.id = m.conversation_id
               WHERE m.voice_call_id = p_voice_call_id AND c.user_id = v_uid AND m.conversation_id <> p_conversation_id) THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'the call belongs to another conversation');
    END IF;
    -- One provider observation per (call, order): a different event id for it is a conflict.
    IF EXISTS (SELECT 1 FROM public.messages WHERE conversation_id = p_conversation_id
               AND voice_call_id = p_voice_call_id AND voice_event_order = p_event_order) THEN
      PERFORM public.support_raise('OPERATION_ID_REUSED', 'event identity conflict');
    END IF;

    -- 6. Insert exactly once. No ON CONFLICT: an unexpected collision is a refusal, never an overwrite.
    BEGIN
      PERFORM set_config('support.transcript_rpc', 'on', true);
      INSERT INTO public.messages (
        id, conversation_id, role, content, created_at, support_session_id,
        voice_call_id, voice_event_order, voice_provider_item_id, voice_provider_event_id, voice_occurred_at,
        voice_source_session_id)
      VALUES (
        p_event_id, p_conversation_id, p_role::public.message_role, p_text, p_occurred_at, p_session_id,
        p_voice_call_id, p_event_order, p_provider_item_id, p_provider_event_id, p_occurred_at,
        p_session_id)
      RETURNING * INTO v_msg;
      PERFORM set_config('support.transcript_rpc', 'off', true);
    EXCEPTION WHEN unique_violation THEN
      PERFORM public.support_raise('OPERATION_ID_REUSED', 'event identity conflict');
    END;
    -- Only a live session re-ranks its conversation; a closed one is reconciled storage-only
    -- (no session, activity, event or conversation-ordering side effect of any kind).
    IF v_session.status = 'open' THEN
      UPDATE public.conversations SET updated_at = now() WHERE id = p_conversation_id AND user_id = v_uid;
    END IF;
    RETURN jsonb_build_object('ok', true, 'replay', false, 'event_id', v_msg.id, 'message_id', v_msg.id,
      'conversation_id', v_msg.conversation_id, 'voice_call_id', v_msg.voice_call_id,
      'event_order', v_msg.voice_event_order, 'role', v_msg.role::text, 'occurred_at', v_msg.voice_occurred_at);
  EXCEPTION WHEN SQLSTATE 'SS001' THEN
    GET STACKED DIAGNOSTICS v_code = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL;
    RETURN jsonb_build_object('ok', false, 'code', v_code, 'message', nullif(v_detail, ''));
  END;
END;
$$;

-- ---------------------------------------------------------------------------
-- support_context_sources: history ordering honors the voice observation order
-- ---------------------------------------------------------------------------
-- Everything except the history projection below is the audited root definition, verbatim
-- (ownership check, memory/intent reads, privacy revision, conversation suppression, role/origin
-- filter, per-message suppression, limit clamp, content_revision, return shape, attributes).
-- CREATE OR REPLACE keeps the owner and the existing privileges; they are re-asserted below.
CREATE OR REPLACE FUNCTION public.support_context_sources(
  p_user uuid, p_conversation uuid, p_history_limit integer DEFAULT 20, p_include_personal boolean DEFAULT true
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_priv bigint; v_mem jsonb := '[]'::jsonb; v_intent jsonb := NULL; v_hist jsonb; v_conv_suppressed boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.conversations WHERE id = p_conversation AND user_id = p_user) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NOT_FOUND');
  END IF;
  SELECT coalesce(p.privacy_revision, 1) INTO v_priv FROM (SELECT 1) x LEFT JOIN public.support_privacy_state p ON p.user_id = p_user;
  v_conv_suppressed := EXISTS (SELECT 1 FROM public.support_suppressions s
    WHERE s.user_id = p_user AND s.kind = 'conversation' AND s.ref_id = p_conversation);
  IF p_include_personal THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', m.id, 'category', m.category, 'content', m.content, 'revision', m.revision,
        'confirmed_at', coalesce(m.confirmed_at, m.created_at), 'review_due_at', m.review_due_at, 'expires_at', m.expires_at)
        ORDER BY m.created_at, m.id), '[]'::jsonb)
      INTO v_mem FROM public.companion_memory m
      WHERE m.user_id = p_user AND m.deleted_at IS NULL AND m.disabled_at IS NULL
        AND NOT EXISTS (SELECT 1 FROM public.support_suppressions s WHERE s.user_id = p_user AND (
              (s.kind = 'memory' AND s.ref_id = m.id)
           OR (s.kind = 'message' AND s.ref_id = m.source_message_id)
           OR (s.kind = 'conversation' AND s.ref_id = public.support_origin_conversation(m.source_conversation_id, m.source_message_id))));
    SELECT jsonb_build_object('id', d.id, 'intent', d.intent, 'created_at', d.created_at, 'expires_at', d.expires_at)
      INTO v_intent FROM public.daily_intents d WHERE d.user_id = p_user AND d.expires_at > now() ORDER BY d.created_at DESC LIMIT 1;
  END IF;
  -- A suppressed (legacy-provenance) conversation contributes no history to new context.
  IF v_conv_suppressed THEN
    v_hist := '[]'::jsonb;
  ELSE
    -- Voice transcript turns (messages.voice_call_id) are placed by the provider observation order,
    -- never by timestamp alone. Each call is one group positioned at the MINIMUM created_at of the
    -- call's rows in THIS (owned) conversation; inside a group the turns follow voice_event_order
    -- numerically whatever their individual timestamps; ordinary messages keep (created_at, id).
    -- The final key (group_at, group_key, in_group, id) is total and deterministic; the limit is
    -- applied AFTER this ordering, taking the last N of it. Optional voice_call_id /
    -- voice_event_order are added only to voice turns, so older clients see unchanged entries.
    SELECT coalesce(jsonb_agg(
        jsonb_build_object('id', h.id, 'role', h.role, 'content', h.content, 'created_at', h.created_at, 'content_revision', h.content_revision)
        || CASE WHEN h.voice_call_id IS NULL THEN '{}'::jsonb
                ELSE jsonb_build_object('voice_call_id', h.voice_call_id, 'voice_event_order', h.voice_event_order) END
        ORDER BY h.group_at, h.group_key, h.in_group, h.id), '[]'::jsonb)
      INTO v_hist FROM (
        SELECT ms.id, ms.role, ms.content, ms.created_at, ms.content_revision, ms.voice_call_id, ms.voice_event_order,
               coalesce((SELECT min(c.created_at) FROM public.messages c
                          WHERE c.conversation_id = p_conversation AND c.voice_call_id = ms.voice_call_id), ms.created_at) AS group_at,
               coalesce(ms.voice_call_id, ms.id) AS group_key,
               coalesce(ms.voice_event_order, 0) AS in_group
        FROM public.messages ms
        WHERE ms.conversation_id = p_conversation
          AND ms.role IN ('user', 'assistant')
          AND coalesce(ms.content_origin, 'model') = 'model'
          AND NOT EXISTS (SELECT 1 FROM public.support_suppressions s WHERE s.user_id = p_user AND s.kind = 'message' AND s.ref_id = ms.id)
        ORDER BY group_at DESC, group_key DESC, in_group DESC, ms.id DESC LIMIT least(greatest(p_history_limit, 1), 40)) h;
  END IF;
  RETURN jsonb_build_object('ok', true, 'privacy_revision', v_priv, 'memories', v_mem, 'daily_intent', v_intent,
    'history', v_hist, 'conversation_suppressed', v_conv_suppressed);
END;
$$;

REVOKE ALL ON FUNCTION public.support_context_sources(uuid, uuid, integer, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.support_context_sources(uuid, uuid, integer, boolean) TO service_role;
DO $$ BEGIN
  IF pg_catalog.has_function_privilege('anon', 'public.support_context_sources(uuid,uuid,integer,boolean)', 'EXECUTE')
     OR pg_catalog.has_function_privilege('authenticated', 'public.support_context_sources(uuid,uuid,integer,boolean)', 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('service_role', 'public.support_context_sources(uuid,uuid,integer,boolean)', 'EXECUTE') THEN
    RAISE EXCEPTION 'support_context_sources privileges changed; refusing';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- support_get_conversation_messages: the UI's page of history, in the SAME order the AI reads it
-- ---------------------------------------------------------------------------
-- The ordering expression below is the one in support_context_sources (group_at / group_key / in_group /
-- id, limit after ordering), kept textually identical on purpose; the test file asserts that the two
-- readers return the same sequence for tied, reversed and delayed-arrival voice turns.
CREATE FUNCTION public.support_get_conversation_messages(
  p_expected_owner uuid, p_conversation_id uuid, p_limit integer DEFAULT 50
) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_rows jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501'; END IF;
  IF p_expected_owner IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'OWNER_MISMATCH' USING ERRCODE = '42501'; END IF;
  IF p_conversation_id IS NULL OR p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
    RAISE EXCEPTION 'INVALID_PAYLOAD' USING ERRCODE = '22023';
  END IF;
  -- Foreign and nonexistent are one answer. (Row-level security would hide a foreign row anyway.)
  IF NOT EXISTS (SELECT 1 FROM public.conversations WHERE id = p_conversation_id AND user_id = v_uid) THEN
    RAISE EXCEPTION 'NOT_FOUND' USING ERRCODE = 'PT404';
  END IF;
  SELECT coalesce(jsonb_agg(
      jsonb_build_object('id', h.id, 'conversation_id', h.conversation_id, 'role', h.role, 'content', h.content,
        'created_at', h.created_at, 'content_origin', h.content_origin,
        'voice_call_id', h.voice_call_id, 'voice_event_order', h.voice_event_order)
      ORDER BY h.group_at, h.group_key, h.in_group, h.id), '[]'::jsonb)
    INTO v_rows FROM (
      SELECT ms.id, ms.conversation_id, ms.role, ms.content, ms.created_at, ms.content_origin,
             ms.voice_call_id, ms.voice_event_order,
             coalesce((SELECT min(c.created_at) FROM public.messages c
                        WHERE c.conversation_id = p_conversation_id AND c.voice_call_id = ms.voice_call_id), ms.created_at) AS group_at,
             coalesce(ms.voice_call_id, ms.id) AS group_key,
             coalesce(ms.voice_event_order, 0) AS in_group
      FROM public.messages ms
      WHERE ms.conversation_id = p_conversation_id
      ORDER BY group_at DESC, group_key DESC, in_group DESC, ms.id DESC LIMIT p_limit) h;
  RETURN v_rows;
END;
$$;

-- ---------------------------------------------------------------------------
-- Grants: authenticated only; a fixed, safe search_path is set on the function above.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.support_transcript_guard() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.support_get_conversation_messages(uuid, uuid, integer) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.support_get_conversation_messages(uuid, uuid, integer) TO authenticated;
REVOKE ALL ON FUNCTION
  public.append_support_transcript(uuid, uuid, uuid, uuid, uuid, bigint, text, text, timestamptz, text, text)
FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  public.append_support_transcript(uuid, uuid, uuid, uuid, uuid, bigint, text, text, timestamptz, text, text)
TO authenticated;

COMMENT ON FUNCTION public.append_support_transcript(uuid, uuid, uuid, uuid, uuid, bigint, text, text, timestamptz, text, text) IS
'Idempotent append of one FINAL voice transcript turn as a canonical messages row (id = p_event_id). Authenticated only; the captured owner must equal auth.uid(). A confirmed identical event replays (replay=true) without any write, even after the session closed or was deleted, but only when the named session is exactly the one it was originally stored under (immutable voice_source_session_id); an altered payload under the same id, or the same (call, order) under another id, is OPERATION_ID_REUSED. New events require an owned, undeleted session (open, or closed for storage-only reconciliation) attached to the exact owned conversation and nothing suppressed. Returns identifiers and order only, never the body.';

COMMENT ON FUNCTION public.support_get_conversation_messages(uuid, uuid, integer) IS
'UI page of conversation history as a JSON array, oldest to newest among the latest p_limit (1..100), ordered exactly like support_context_sources: voice calls anchored at their minimum created_at and ordered by voice_event_order, plain messages by (created_at, id), limit after ordering. Unfiltered by role, origin or suppression. Invoker rights; the caller must be the expected owner and own the conversation.';

COMMIT;
