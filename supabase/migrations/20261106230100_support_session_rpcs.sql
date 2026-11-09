-- Support session server contract, part 2 of 3: session mutation and read RPCs.
--
-- NOT EXECUTED by its author; requires 20261106230000_support_session_schema.sql and
-- independent review on a disposable database first. Spec sections 9.2-9.5.
--
-- Contract of public.support_apply_mutation(envelope):
--   authenticate (auth.uid()) -> operation receipt lookup (replay returns the stored
--   confirmed response even if expected_revision is now stale) -> session row lock ->
--   session-wide CAS -> apply -> revision+1, one event, receipt, in ONE transaction.
--   Domain failures are returned as {"ok":false,"code":...}; the whole body runs in a
--   sub-transaction so a failure after a partial write leaves nothing behind.
--   finish_activity(completed, grounding) calls the existing complete_exercise_session
--   and award_exercise_session_xp inside the same transaction as the support state.
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $$
BEGIN
  IF to_regclass('public.support_work_sessions') IS NULL THEN
    RAISE EXCEPTION 'support schema migration must be applied first';
  END IF;
  IF to_regprocedure('public.complete_exercise_session(uuid,integer,text)') IS NULL
     OR to_regprocedure('public.award_exercise_session_xp(uuid)') IS NULL THEN
    RAISE EXCEPTION 'canonical exercise completion functions are missing';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Internal helpers (owner-only execution; never exposed to API roles)
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_try_ts(p_text text) RETURNS timestamptz
LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  RETURN p_text::timestamptz;
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$;

-- Domain error: SQLSTATE SS001, MESSAGE = contract error code, DETAIL = hint.
CREATE FUNCTION public.support_raise(p_code text, p_message text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  RAISE EXCEPTION '%', p_code USING ERRCODE = 'SS001', DETAIL = coalesce(p_message, '');
END;
$$;

CREATE FUNCTION public.support_opt_text(p_obj jsonb, p_key text, p_max integer) RETURNS text
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE v text;
BEGIN
  IF NOT (p_obj ? p_key) OR jsonb_typeof(p_obj -> p_key) = 'null' THEN RETURN NULL; END IF;
  IF jsonb_typeof(p_obj -> p_key) <> 'string' THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', p_key || ' must be a string');
  END IF;
  v := p_obj ->> p_key;
  IF char_length(v) > p_max THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', p_key || ' is too long');
  END IF;
  RETURN v;
END;
$$;

-- ONE coarse, private, transaction-scoped mutex for every context-changing write.
-- Acquired FIRST (before any row lock) by all new write/confirmation RPCs and by BEFORE
-- STATEMENT triggers on the retained legacy companion_memory / memory_fragments writers.
-- Single-user tradeoff: writes of this one-person app serialize behind each other. A write
-- is a short transaction (provider generation happens OUTSIDE database transactions), so the
-- cost is a few milliseconds of queueing; the benefit is that no inverse row-lock cycle,
-- empty-set/phantom insertion or legacy-versus-new interleaving can exist at all.
-- Re-entrant within a transaction. Not callable by API roles.
CREATE FUNCTION public.support_acquire_write_mutex() RETURNS void
LANGUAGE sql SET search_path = pg_catalog, pg_temp AS $$
  SELECT pg_advisory_xact_lock(hashtextextended('mindfriend.support.context-write-mutex', 0));
$$;

CREATE FUNCTION public.support_ensure_privacy_state(p_user uuid) RETURNS bigint
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE v bigint;
BEGIN
  INSERT INTO public.support_privacy_state (user_id) VALUES (p_user) ON CONFLICT (user_id) DO NOTHING;
  SELECT privacy_revision INTO v FROM public.support_privacy_state WHERE user_id = p_user;
  RETURN v;
END;
$$;

CREATE FUNCTION public.support_activity_json(a public.support_activities) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = pg_catalog, public, pg_temp AS $$
  SELECT jsonb_build_object(
    'id', a.id, 'template_key', a.template_key, 'template_version', a.template_version,
    'kind', a.kind, 'status', a.status, 'stop_reason', a.stop_reason,
    'canonical_ref_type', a.canonical_ref_type, 'canonical_ref_id', a.canonical_ref_id,
    'checkpoint', a.checkpoint, 'result', a.result, 'reflection', a.reflection,
    'active_ms', a.active_ms, 'last_changed_revision', a.last_changed_revision,
    'created_at', a.created_at, 'updated_at', a.updated_at, 'finished_at', a.finished_at);
$$;

CREATE FUNCTION public.support_snapshot(p_user uuid, p_session uuid) RETURNS jsonb
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  s public.support_work_sessions%ROWTYPE;
  v_priv bigint;
  v_acts jsonb;
  v_props jsonb;
BEGIN
  SELECT * INTO s FROM public.support_work_sessions WHERE id = p_session AND user_id = p_user;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT privacy_revision INTO v_priv FROM public.support_privacy_state WHERE user_id = p_user;
  v_priv := coalesce(v_priv, 1);
  SELECT coalesce(jsonb_agg(public.support_activity_json(a) ORDER BY a.created_at, a.id), '[]'::jsonb)
    INTO v_acts FROM public.support_activities a
    WHERE a.support_session_id = p_session AND a.user_id = p_user;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'template_key', p.template_key, 'reason_code', p.reason_code,
      'basis_kind', p.basis_kind, 'basis_ref', p.basis_ref, 'suggested_step', p.suggested_step,
      'status', p.status, 'expires_at', p.expires_at) ORDER BY p.created_at, p.id), '[]'::jsonb)
    INTO v_props FROM public.support_proposals p
    WHERE p.support_session_id = p_session AND p.user_id = p_user
      AND p.status = 'offered' AND p.expires_at > now() AND p.privacy_revision = v_priv;
  RETURN jsonb_build_object(
    'session', jsonb_build_object(
      'id', s.id, 'conversation_id', s.conversation_id, 'previous_session_id', s.previous_session_id,
      'selected_activity_id', s.selected_activity_id, 'title', s.title, 'concern', s.concern,
      'status', s.status, 'context_scope', s.context_scope, 'revision', s.revision,
      'suppressed_templates', to_jsonb(s.suppressed_templates),
      'created_at', s.created_at, 'updated_at', s.updated_at,
      'closed_at', s.closed_at, 'deleted_at', s.deleted_at),
    'activities', CASE WHEN s.status = 'deleted' THEN '[]'::jsonb ELSE v_acts END,
    'proposals', CASE WHEN s.status = 'deleted' THEN '[]'::jsonb ELSE v_props END,
    'privacy_revision', v_priv);
END;
$$;

-- Deselect the currently selected activity before another is selected (section 9.2).
CREATE FUNCTION public.support_release_selection(
  p_user uuid, p_session public.support_work_sessions, p_new_rev bigint, p_disposition text
) RETURNS void LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE a public.support_activities%ROWTYPE;
BEGIN
  IF p_disposition IS NOT NULL AND p_disposition NOT IN ('save', 'end') THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'previous_disposition must be save or end');
  END IF;
  FOR a IN SELECT * FROM public.support_activities
           WHERE support_session_id = p_session.id AND user_id = p_user AND status = 'in_progress'
           FOR UPDATE LOOP
    IF p_disposition IS NULL THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'previous_disposition required while another activity is in progress');
    ELSIF p_disposition = 'save' THEN
      UPDATE public.support_activities SET status = 'paused', last_changed_revision = p_new_rev, updated_at = now()
        WHERE id = a.id;
    ELSE
      UPDATE public.support_activities SET status = 'stopped', stop_reason = 'replaced',
        finished_at = now(), checkpoint = NULL, last_changed_revision = p_new_rev, updated_at = now(),
        result = CASE WHEN a.kind = 'next_step' THEN jsonb_build_object('step', jsonb_build_object('state', 'dismissed')) ELSE a.result END
        WHERE id = a.id;
    END IF;
  END LOOP;
  UPDATE public.support_work_sessions SET selected_activity_id = NULL WHERE id = p_session.id AND user_id = p_user;
END;
$$;

-- Resolve the canonical exercise id for a grounding template. The enabled server
-- catalog mapping is the ONLY authority: a client-supplied id may confirm it but can
-- never become it. NULL = unmapped, so no canonical exercise session may be created or
-- completed (the local practice still runs; completion stays pending).
CREATE FUNCTION public.support_resolve_exercise(p_template text, p_requested uuid) RETURNS uuid
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE v_mapped uuid;
BEGIN
  SELECT exercise_id INTO v_mapped FROM public.support_template_catalog
    WHERE template_key = p_template AND enabled AND kind = 'grounding';
  IF p_requested IS NOT NULL AND (v_mapped IS NULL OR p_requested <> v_mapped) THEN
    PERFORM public.support_raise('CONTENT_UNAVAILABLE', 'exercise does not match the server template mapping');
  END IF;
  RETURN v_mapped;
END;
$$;

-- A memory/fragment's origin conversation: explicit legacy conversation id, else the
-- OWNING conversation of its source message (message-only provenance is valid).
CREATE FUNCTION public.support_origin_conversation(p_conversation uuid, p_message uuid) RETURNS uuid
LANGUAGE sql STABLE SET search_path = pg_catalog, public, pg_temp AS $$
  SELECT coalesce(p_conversation, (SELECT ms.conversation_id FROM public.messages ms WHERE ms.id = p_message));
$$;

-- Is this activity suppressed (forgotten source / discarded)? Later content writes lose.
CREATE FUNCTION public.support_activity_suppressed(p_user uuid, p_activity uuid) RETURNS boolean
LANGUAGE sql STABLE SET search_path = pg_catalog, public, pg_temp AS $$
  SELECT EXISTS (SELECT 1 FROM public.support_suppressions s
    WHERE s.user_id = p_user AND s.kind = 'activity' AND s.ref_id = p_activity);
$$;

-- Time-based eligibility (no row change happens when a deadline passes, so every consumer
-- re-evaluates it): expiry, and the 90-day (or explicit) life-context review date.
CREATE FUNCTION public.support_memory_time_eligible(m public.companion_memory, p_at timestamptz) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path = pg_catalog, public, pg_temp AS $$
  -- p_at MUST be actual wall-clock time (clock_timestamp()) captured at the final
  -- eligibility boundary after blocking locks; transaction-start now() is not acceptable.
  SELECT (m.expires_at IS NULL OR m.expires_at > p_at)
     AND (m.category <> 'life_context'
          OR coalesce(m.review_due_at, coalesce(m.confirmed_at, m.created_at) + interval '90 days') > p_at);
$$;

-- Is one stored receipt source still current? Same owner / eligibility / exact-revision
-- semantics as atomic chat confirmation (support_confirm_chat_turn). Used by proposal
-- acceptance so a proposal expires when ANY context it was built from changed, not only its
-- named basis. p_now must be wall-clock time read after the blocking locks.
CREATE FUNCTION public.support_receipt_source_current(
  p_user uuid, p_kind text, p_id uuid, p_rev bigint, p_scope text, p_conv uuid, p_now timestamptz
) RETURNS boolean LANGUAGE plpgsql STABLE SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  m public.companion_memory%ROWTYPE;
  v_msg_rev bigint; v_msg_conv uuid;
BEGIN
  IF p_kind = 'safety_policy' THEN
    RETURN p_id = '00000000-0000-0000-0000-000000000001'::uuid;
  ELSIF p_kind = 'companion_memory' THEN
    IF p_scope <> 'personalized' THEN RETURN false; END IF;
    SELECT * INTO m FROM public.companion_memory WHERE id = p_id AND user_id = p_user;
    IF NOT FOUND THEN RETURN false; END IF;
    RETURN m.deleted_at IS NULL AND m.disabled_at IS NULL AND m.revision = p_rev
       AND public.support_memory_time_eligible(m, p_now)
       AND NOT EXISTS (SELECT 1 FROM public.support_suppressions s WHERE s.user_id = p_user AND (
            (s.kind = 'memory' AND s.ref_id = m.id)
         OR (s.kind = 'message' AND s.ref_id = m.source_message_id)
         OR (s.kind = 'conversation' AND s.ref_id = public.support_origin_conversation(m.source_conversation_id, m.source_message_id))));
  ELSIF p_kind = 'message' THEN
    SELECT ms.content_revision, ms.conversation_id INTO v_msg_rev, v_msg_conv
      FROM public.messages ms JOIN public.conversations c ON c.id = ms.conversation_id
      WHERE ms.id = p_id AND c.user_id = p_user;
    IF NOT FOUND THEN RETURN false; END IF;
    RETURN v_msg_rev = p_rev AND v_msg_conv = p_conv
       AND NOT EXISTS (SELECT 1 FROM public.support_suppressions s WHERE s.user_id = p_user AND (
            (s.kind = 'message' AND s.ref_id = p_id) OR (s.kind = 'conversation' AND s.ref_id = v_msg_conv)));
  ELSIF p_kind = 'daily_intent' THEN
    RETURN p_scope = 'personalized' AND EXISTS (
      SELECT 1 FROM public.daily_intents d WHERE d.id = p_id AND d.user_id = p_user AND d.expires_at > p_now);
  ELSIF p_kind = 'session' THEN
    RETURN EXISTS (SELECT 1 FROM public.support_work_sessions w
      WHERE w.id = p_id AND w.user_id = p_user AND w.status = 'open' AND w.context_revision = p_rev);
  ELSIF p_kind = 'activity_result' THEN
    RETURN EXISTS (SELECT 1 FROM public.support_activities a WHERE a.id = p_id AND a.user_id = p_user AND a.context_revision = p_rev)
       AND NOT EXISTS (SELECT 1 FROM public.support_suppressions s WHERE s.user_id = p_user AND s.kind = 'activity' AND s.ref_id = p_id);
  END IF;
  RETURN false;
END;
$$;

-- Transitive suppression (section 8.5). Seeds are rows already written to
-- support_suppressions by the caller. Runs to a fixpoint over every known derived edge:
--   suppressed memory/activity/message/conversation  -> assistant turns whose receipts cite it
--   suppressed message/conversation                  -> canonical memories, fragments and
--                                                       accepted activities sourced from it
-- History stays visible; the records are excluded from NEW context. Identifiers only.
CREATE FUNCTION public.support_suppress_closure(p_user uuid, p_op uuid, p_origin_session uuid DEFAULT NULL) RETURNS integer
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE v_n integer; v_round integer; v_msgs integer := 0; v_affected_session record; v_rev bigint;
BEGIN
  LOOP
    v_round := 0;
    INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason, operation_id)
    SELECT DISTINCT p_user, 'message', r.assistant_message_id, 'derived_from_forgotten', p_op
    FROM public.support_context_receipt_sources src
    JOIN public.support_context_receipts r ON r.id = src.receipt_id AND r.user_id = p_user
    WHERE src.user_id = p_user AND r.assistant_message_id IS NOT NULL AND (
         (src.source_kind = 'companion_memory' AND EXISTS (SELECT 1 FROM public.support_suppressions s
            WHERE s.user_id = p_user AND s.kind = 'memory' AND s.ref_id = src.source_id))
      OR (src.source_kind = 'message' AND EXISTS (SELECT 1 FROM public.support_suppressions s
            WHERE s.user_id = p_user AND s.kind = 'message' AND s.ref_id = src.source_id))
      OR (src.source_kind = 'message' AND EXISTS (SELECT 1 FROM public.messages ms
            JOIN public.support_suppressions s ON s.user_id = p_user AND s.kind = 'conversation' AND s.ref_id = ms.conversation_id
            WHERE ms.id = src.source_id))
      OR (src.source_kind = 'activity_result' AND EXISTS (SELECT 1 FROM public.support_suppressions s
            WHERE s.user_id = p_user AND s.kind = 'activity' AND s.ref_id = src.source_id)))
    ON CONFLICT (user_id, kind, ref_id) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT; v_round := v_round + v_n; v_msgs := v_msgs + v_n;

    INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason, operation_id)
    SELECT p_user, 'memory', m.id, 'derived_from_forgotten', p_op FROM public.companion_memory m
    WHERE m.user_id = p_user AND (
         (m.source_message_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.support_suppressions s
            WHERE s.user_id = p_user AND s.kind = 'message' AND s.ref_id = m.source_message_id))
      OR (public.support_origin_conversation(m.source_conversation_id, m.source_message_id) IS NOT NULL AND EXISTS (SELECT 1 FROM public.support_suppressions s
            WHERE s.user_id = p_user AND s.kind = 'conversation'
              AND s.ref_id = public.support_origin_conversation(m.source_conversation_id, m.source_message_id))))
    ON CONFLICT (user_id, kind, ref_id) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT; v_round := v_round + v_n;

    INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason, operation_id)
    SELECT p_user, 'fragment', f.id, 'derived_from_forgotten', p_op FROM public.memory_fragments f
    WHERE f.user_id = p_user AND (
         (f.source_message_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.support_suppressions s
            WHERE s.user_id = p_user AND s.kind = 'message' AND s.ref_id = f.source_message_id))
      OR (public.support_origin_conversation(f.source_conversation_id, f.source_message_id) IS NOT NULL AND EXISTS (SELECT 1 FROM public.support_suppressions s
            WHERE s.user_id = p_user AND s.kind = 'conversation'
              AND s.ref_id = public.support_origin_conversation(f.source_conversation_id, f.source_message_id))))
    ON CONFLICT (user_id, kind, ref_id) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT; v_round := v_round + v_n;

    INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason, operation_id)
    SELECT DISTINCT p_user, 'activity', p.accepted_activity_id, 'derived_from_forgotten', p_op
    FROM public.support_proposals p
    WHERE p.user_id = p_user AND p.accepted_activity_id IS NOT NULL AND (
         (p.message_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.support_suppressions s
            WHERE s.user_id = p_user AND s.kind = 'message' AND s.ref_id = p.message_id))
      OR (p.message_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.messages ms
            JOIN public.support_suppressions s ON s.user_id = p_user AND s.kind = 'conversation' AND s.ref_id = ms.conversation_id
            WHERE ms.id = p.message_id))
      OR (p.basis_kind = 'companion_memory' AND EXISTS (SELECT 1 FROM public.support_suppressions s
            WHERE s.user_id = p_user AND s.kind = 'memory' AND s.ref_id = p.basis_ref))
      OR (p.basis_kind = 'message' AND EXISTS (SELECT 1 FROM public.support_suppressions s
            WHERE s.user_id = p_user AND s.kind = 'message' AND s.ref_id = p.basis_ref)))
    ON CONFLICT (user_id, kind, ref_id) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT; v_round := v_round + v_n;
    EXIT WHEN v_round = 0;
  END LOOP;

  -- Suppression DOMINATES later writes (S02). Affected sessions are locked in id order
  -- (global order: memory/fragment rows -> privacy -> sessions -> proposals/activities;
  -- callers already hold the privacy lock exclusively). EVERY affected session except the
  -- caller's own origin session (whose outer mutation advances it exactly once) gets its
  -- revision/updated_at advanced so prepared attempts fail CAS and other devices see it in
  -- incremental sync. Active suppressed activities are stopped (reason discarded) and every
  -- suppressed activity is hard-scrubbed with a server-owned content_scrubbed_at marker.
  PERFORM set_config('support.discarding', 'on', true);
  FOR v_affected_session IN
    SELECT DISTINCT x.sid FROM (
      SELECT act.support_session_id AS sid FROM public.support_activities act
        WHERE act.user_id = p_user
          AND act.id IN (SELECT ref_id FROM public.support_suppressions WHERE user_id = p_user AND kind = 'activity')
          AND (act.content_scrubbed_at IS NULL OR act.status IN ('ready', 'in_progress', 'paused'))
      UNION ALL
      SELECT p.support_session_id FROM public.support_proposals p
        WHERE p.user_id = p_user AND p.status = 'offered' AND (
         (p.message_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.support_suppressions s
            WHERE s.user_id = p_user AND s.kind = 'message' AND s.ref_id = p.message_id))
      OR (p.message_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.messages ms
            JOIN public.support_suppressions s ON s.user_id = p_user AND s.kind = 'conversation' AND s.ref_id = ms.conversation_id
            WHERE ms.id = p.message_id))
      OR (p.basis_kind = 'companion_memory' AND EXISTS (SELECT 1 FROM public.support_suppressions s
            WHERE s.user_id = p_user AND s.kind = 'memory' AND s.ref_id = p.basis_ref))
      OR (p.basis_kind = 'message' AND EXISTS (SELECT 1 FROM public.support_suppressions s
            WHERE s.user_id = p_user AND s.kind = 'message' AND s.ref_id = p.basis_ref)))
      UNION ALL
      SELECT p.support_session_id FROM public.support_proposals p
        WHERE p.user_id = p_user AND p.suggested_step IS NOT NULL AND (
          p.status IN ('invalidated', 'expired')
          OR p.accepted_activity_id IN (SELECT ref_id FROM public.support_suppressions WHERE user_id = p_user AND kind = 'activity'))
    ) x ORDER BY x.sid LOOP
    v_rev := NULL;
    IF v_affected_session.sid IS DISTINCT FROM p_origin_session THEN
      UPDATE public.support_work_sessions SET revision = revision + 1, updated_at = now()
        WHERE id = v_affected_session.sid AND user_id = p_user AND status <> 'deleted' RETURNING revision INTO v_rev;
    END IF;
    UPDATE public.support_work_sessions SET selected_activity_id = NULL
      WHERE id = v_affected_session.sid AND user_id = p_user AND selected_activity_id IN
        (SELECT ref_id FROM public.support_suppressions WHERE user_id = p_user AND kind = 'activity');
    UPDATE public.support_proposals p SET status = 'invalidated'
      WHERE p.user_id = p_user AND p.support_session_id = v_affected_session.sid AND p.status = 'offered' AND (
         (p.message_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.support_suppressions s
            WHERE s.user_id = p_user AND s.kind = 'message' AND s.ref_id = p.message_id))
      OR (p.message_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.messages ms
            JOIN public.support_suppressions s ON s.user_id = p_user AND s.kind = 'conversation' AND s.ref_id = ms.conversation_id
            WHERE ms.id = p.message_id))
      OR (p.basis_kind = 'companion_memory' AND EXISTS (SELECT 1 FROM public.support_suppressions s
            WHERE s.user_id = p_user AND s.kind = 'memory' AND s.ref_id = p.basis_ref))
      OR (p.basis_kind = 'message' AND EXISTS (SELECT 1 FROM public.support_suppressions s
            WHERE s.user_id = p_user AND s.kind = 'message' AND s.ref_id = p.basis_ref)));
    UPDATE public.support_activities SET
        status = CASE WHEN status IN ('ready', 'in_progress', 'paused') THEN 'stopped' ELSE status END,
        stop_reason = CASE WHEN status IN ('ready', 'in_progress', 'paused') THEN 'discarded' ELSE stop_reason END,
        finished_at = CASE WHEN status IN ('ready', 'in_progress', 'paused') THEN now() ELSE finished_at END,
        checkpoint = NULL,
        -- Display marker only; erasure state is content_scrubbed_at. Raw result is replaced, never trusted.
        result = jsonb_build_object('discarded', true),
        reflection = CASE WHEN reflection IS NULL THEN NULL
          ELSE jsonb_build_object('outcome', reflection ->> 'outcome', 'note', NULL, 'share_note', false, 'shareable_text', NULL) END,
        content_scrubbed_at = coalesce(content_scrubbed_at, now()),
        last_changed_revision = coalesce(v_rev, last_changed_revision), updated_at = now()
      WHERE user_id = p_user AND support_session_id = v_affected_session.sid
        AND id IN (SELECT ref_id FROM public.support_suppressions WHERE user_id = p_user AND kind = 'activity')
        AND (content_scrubbed_at IS NULL OR status IN ('ready', 'in_progress', 'paused'));
    UPDATE public.support_proposals SET suggested_step = NULL
      WHERE user_id = p_user AND support_session_id = v_affected_session.sid AND suggested_step IS NOT NULL AND (
        status IN ('invalidated', 'expired') OR accepted_activity_id IN (
          SELECT ref_id FROM public.support_suppressions WHERE user_id = p_user AND kind = 'activity'));
  END LOOP;
  PERFORM set_config('support.discarding', 'off', true);
  RETURN v_msgs;
END;
$$;

-- ---------------------------------------------------------------------------
-- Per-kind handlers. Each returns jsonb:
--   {event_kind, activity_id?, no_op?, event_payload?, extra?}
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_do_create(p_user uuid, p_session_id uuid, p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_title text; v_concern text; v_scope text; v_conv uuid; v_prev uuid;
BEGIN
  v_title := coalesce(btrim(public.support_opt_text(p_payload, 'title', 80)), '');
  v_concern := public.support_opt_text(p_payload, 'concern', 4000);
  v_scope := coalesce(public.support_opt_text(p_payload, 'context_scope', 32), 'conversation_only');
  IF v_scope NOT IN ('conversation_only', 'personalized') THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'unknown context_scope');
  END IF;
  IF p_payload ? 'conversation_id' AND jsonb_typeof(p_payload -> 'conversation_id') <> 'null' THEN
    v_conv := public.support_try_uuid(p_payload ->> 'conversation_id');
    IF v_conv IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'conversation_id must be a UUID'); END IF;
    IF NOT EXISTS (SELECT 1 FROM public.conversations WHERE id = v_conv AND user_id = p_user) THEN
      PERFORM public.support_raise('NOT_FOUND', 'conversation not found');
    END IF;
    IF EXISTS (SELECT 1 FROM public.support_work_sessions WHERE conversation_id = v_conv AND status <> 'deleted') THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'conversation already has a session');
    END IF;
  END IF;
  IF p_payload ? 'previous_session_id' AND jsonb_typeof(p_payload -> 'previous_session_id') <> 'null' THEN
    v_prev := public.support_try_uuid(p_payload ->> 'previous_session_id');
    IF v_prev IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'previous_session_id must be a UUID'); END IF;
    IF NOT EXISTS (SELECT 1 FROM public.support_work_sessions WHERE id = v_prev AND user_id = p_user AND status <> 'deleted') THEN
      PERFORM public.support_raise('NOT_FOUND', 'previous session not found');
    END IF;
  END IF;
  INSERT INTO public.support_work_sessions (id, user_id, conversation_id, previous_session_id, title, concern, context_scope)
  VALUES (p_session_id, p_user, v_conv, v_prev, v_title, v_concern, v_scope)
  ON CONFLICT (id) DO NOTHING;
  IF NOT FOUND THEN
    -- Same message whether the id belongs to this or another user: no existence oracle.
    PERFORM public.support_raise('INVALID_PAYLOAD', 'session id unavailable');
  END IF;
  RETURN jsonb_build_object('event_kind', 'session_created');
END;
$$;

CREATE FUNCTION public.support_do_update_session(
  p_user uuid, p_session public.support_work_sessions, p_new_rev bigint, p_payload jsonb
) RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_title text; v_concern text; v_scope text; v_close text; v_conv uuid;
  v_changed boolean := false; v_closed boolean := false; v_pending integer;
  v_decl text; v_n integer;
BEGIN
  IF p_payload ? 'title' THEN
    v_title := coalesce(btrim(public.support_opt_text(p_payload, 'title', 80)), '');
    IF v_title IS DISTINCT FROM p_session.title THEN
      UPDATE public.support_work_sessions SET title = v_title WHERE id = p_session.id; v_changed := true;
    END IF;
  END IF;
  IF p_session.status = 'closed' AND (p_payload ?| ARRAY['concern', 'context_scope', 'conversation_id', 'attach_conversation_id', 'close', 'decline_template']) THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'closed session: only rename is allowed; continue as a new session');
  END IF;
  IF p_payload ? 'concern' THEN
    v_concern := public.support_opt_text(p_payload, 'concern', 4000);
    IF v_concern IS DISTINCT FROM p_session.concern THEN
      UPDATE public.support_work_sessions SET concern = v_concern WHERE id = p_session.id; v_changed := true;
    END IF;
  END IF;
  IF p_payload ? 'context_scope' THEN
    v_scope := public.support_opt_text(p_payload, 'context_scope', 32);
    IF v_scope IS NULL OR v_scope NOT IN ('conversation_only', 'personalized') THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'unknown context_scope');
    END IF;
    IF v_scope <> p_session.context_scope THEN
      UPDATE public.support_work_sessions SET context_scope = v_scope WHERE id = p_session.id;
      -- A proposal's basis may be personal; a scope change expires outstanding ones.
      UPDATE public.support_proposals SET status = 'expired'
        WHERE support_session_id = p_session.id AND user_id = p_user AND status = 'offered';
      v_changed := true;
    END IF;
  END IF;
  -- Lazy attachment: local practice/draft sessions have no cloud conversation until the
  -- first deliberate Send. `conversation_id` (alias attach_conversation_id) attaches an
  -- owned conversation once; an existing attachment is immutable.
  IF (p_payload ? 'conversation_id' AND jsonb_typeof(p_payload -> 'conversation_id') <> 'null')
     OR (p_payload ? 'attach_conversation_id' AND jsonb_typeof(p_payload -> 'attach_conversation_id') <> 'null') THEN
    v_conv := public.support_try_uuid(coalesce(p_payload ->> 'conversation_id', p_payload ->> 'attach_conversation_id'));
    IF v_conv IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'conversation_id must be a UUID'); END IF;
    IF (p_payload ? 'conversation_id' AND p_payload ? 'attach_conversation_id'
        AND p_payload ->> 'conversation_id' IS DISTINCT FROM p_payload ->> 'attach_conversation_id') THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'conversation_id and attach_conversation_id disagree');
    END IF;
    IF p_session.conversation_id IS NOT NULL AND p_session.conversation_id <> v_conv THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'session is already attached to a different conversation');
    ELSIF p_session.conversation_id IS NULL THEN
      IF NOT EXISTS (SELECT 1 FROM public.conversations WHERE id = v_conv AND user_id = p_user) THEN
        PERFORM public.support_raise('NOT_FOUND', 'conversation not found');
      END IF;
      IF EXISTS (SELECT 1 FROM public.support_work_sessions WHERE conversation_id = v_conv AND status <> 'deleted') THEN
        PERFORM public.support_raise('INVALID_PAYLOAD', 'conversation already has a session');
      END IF;
      UPDATE public.support_work_sessions SET conversation_id = v_conv WHERE id = p_session.id; v_changed := true;
    END IF;
  END IF;
  IF p_payload ? 'close' AND jsonb_typeof(p_payload -> 'close') <> 'null' THEN
    v_close := public.support_opt_text(p_payload, 'close', 32);
    IF v_close IS NULL OR v_close NOT IN ('end_unfinished', 'if_idle') THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'close must be end_unfinished or if_idle');
    END IF;
    SELECT count(*) INTO v_pending FROM public.support_activities
      WHERE support_session_id = p_session.id AND user_id = p_user AND status IN ('ready', 'in_progress', 'paused');
    IF v_close = 'end_unfinished' OR v_pending = 0 THEN
      -- Closing stops/dismisses pending work; it never completes it.
      UPDATE public.support_activities SET status = 'stopped', stop_reason = 'session_closed',
        finished_at = now(), checkpoint = NULL, last_changed_revision = p_new_rev, updated_at = now(),
        result = CASE WHEN kind = 'next_step' THEN jsonb_build_object('step', jsonb_build_object('state', 'dismissed')) ELSE result END
        WHERE support_session_id = p_session.id AND user_id = p_user AND status IN ('ready', 'in_progress', 'paused');
      UPDATE public.support_proposals SET status = 'expired'
        WHERE support_session_id = p_session.id AND user_id = p_user AND status = 'offered';
      UPDATE public.support_work_sessions SET status = 'closed', closed_at = now(), selected_activity_id = NULL
        WHERE id = p_session.id;
      v_changed := true; v_closed := true;
    END IF;
  END IF;
  -- "Not now" (spec 5.3): persist a per-session exclusion for ONE catalog template so the same
  -- unsolicited proposal is not offered again. No activity, no model call. Idempotent: the
  -- template is appended only once and a repeat changes nothing (-> no_op).
  IF p_payload ? 'decline_template' AND jsonb_typeof(p_payload -> 'decline_template') <> 'null' THEN
    v_decl := public.support_opt_text(p_payload, 'decline_template', 40);
    IF v_decl IS NULL OR v_decl NOT IN ('ground_present_v1', 'untangle_thought_v1', 'choose_step_v1') THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'decline_template must be a catalog template key');
    END IF;
    IF NOT (v_decl = ANY (p_session.suppressed_templates)) THEN
      UPDATE public.support_work_sessions SET suppressed_templates = array_append(suppressed_templates, v_decl)
        WHERE id = p_session.id AND user_id = p_user;
      v_changed := true;
    END IF;
    UPDATE public.support_proposals SET status = 'expired'
      WHERE support_session_id = p_session.id AND user_id = p_user AND status = 'offered' AND template_key = v_decl;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n > 0 THEN v_changed := true; END IF;
  END IF;
  IF NOT v_changed THEN
    RETURN jsonb_build_object('no_op', true,
      'extra', CASE WHEN v_close = 'if_idle' THEN jsonb_build_object('closed', false, 'pending_work', true) ELSE '{}'::jsonb END);
  END IF;
  RETURN jsonb_build_object('event_kind', CASE WHEN v_closed THEN 'session_closed' ELSE 'session_updated' END,
    'extra', jsonb_build_object('closed', v_closed));
END;
$$;

CREATE FUNCTION public.support_do_accept_proposal(
  p_user uuid, p_session public.support_work_sessions, p_new_rev bigint, p_payload jsonb
) RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_pid uuid := public.support_try_uuid(p_payload ->> 'proposal_id');
  v_aid uuid := public.support_try_uuid(p_payload ->> 'activity_id');
  v_prop public.support_proposals%ROWTYPE;
  v_cat public.support_template_catalog%ROWTYPE;
  v_priv bigint;
  v_ok boolean;
  v_cp jsonb;
  v_now timestamptz;
  v_rc record;
  v_src record;
BEGIN
  IF v_pid IS NULL OR v_aid IS NULL THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'proposal_id and activity_id must be UUIDs');
  END IF;
  SELECT * INTO v_prop FROM public.support_proposals
    WHERE id = v_pid AND user_id = p_user AND support_session_id = p_session.id FOR UPDATE;
  IF NOT FOUND THEN PERFORM public.support_raise('NOT_FOUND', 'proposal not found'); END IF;
  IF v_prop.status = 'accepted' THEN
    IF v_prop.accepted_activity_id = v_aid THEN
      RETURN jsonb_build_object('no_op', true, 'activity_id', v_aid);
    END IF;
    PERFORM public.support_raise('PROPOSAL_EXPIRED', 'proposal already accepted');
  END IF;
  -- Share-lock the privacy revision so a concurrent correction cannot slip between
  -- this check and commit.
  PERFORM public.support_ensure_privacy_state(p_user);
  SELECT privacy_revision INTO v_priv FROM public.support_privacy_state WHERE user_id = p_user FOR SHARE;
  -- Final eligibility boundary: wall clock read AFTER every blocking lock above.
  v_now := clock_timestamp();
  IF v_prop.status <> 'offered' OR v_prop.expires_at <= v_now OR v_prop.privacy_revision <> v_priv THEN
    PERFORM public.support_raise('PROPOSAL_EXPIRED', 'proposal is no longer valid');
  END IF;
  IF v_prop.message_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.support_suppressions WHERE user_id = p_user AND kind = 'message' AND ref_id = v_prop.message_id) THEN
    PERFORM public.support_raise('PROPOSAL_EXPIRED', 'proposal source was suppressed');
  END IF;
  -- EVERY source the proposing request was built from must still be current (spec 8.6:
  -- a proposal expires on any basis/context/privacy change). Revisions come from the stored
  -- receipt, never from the client. A proposal with no receipt cannot be trusted.
  SELECT rc.id, rc.scope, rc.conversation_id INTO v_rc FROM public.support_context_receipts rc
    WHERE rc.user_id = p_user AND rc.request_id = v_prop.request_id;
  IF NOT FOUND THEN PERFORM public.support_raise('PROPOSAL_EXPIRED', 'proposal has no context receipt'); END IF;
  FOR v_src IN SELECT source_kind, source_id, source_revision FROM public.support_context_receipt_sources
               WHERE receipt_id = v_rc.id AND user_id = p_user LOOP
    IF NOT public.support_receipt_source_current(p_user, v_src.source_kind, v_src.source_id, v_src.source_revision,
                                                 v_rc.scope, v_rc.conversation_id, v_now) THEN
      PERFORM public.support_raise('PROPOSAL_EXPIRED', 'proposal context changed');
    END IF;
  END LOOP;
  -- A message basis must still be at the exact revision the proposing request cited, and the
  -- proposing assistant turn must be unchanged since it was confirmed (revision 0 at insert).
  IF v_prop.message_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.messages ms WHERE ms.id = v_prop.message_id AND ms.content_revision = 0) THEN
    PERFORM public.support_raise('PROPOSAL_EXPIRED', 'proposal source message changed');
  END IF;
  IF v_prop.basis_kind = 'message' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.support_context_receipts rc
      JOIN public.support_context_receipt_sources src ON src.receipt_id = rc.id AND src.source_kind = 'message'
      JOIN public.messages ms ON ms.id = src.source_id AND ms.id = v_prop.basis_ref
      WHERE rc.user_id = p_user AND rc.request_id = v_prop.request_id AND src.source_revision = ms.content_revision) INTO v_ok;
    IF NOT v_ok THEN PERFORM public.support_raise('PROPOSAL_EXPIRED', 'proposal basis message changed'); END IF;
  END IF;
  IF v_prop.basis_kind = 'companion_memory' THEN
    SELECT EXISTS (SELECT 1 FROM public.companion_memory m
      WHERE m.id = v_prop.basis_ref AND m.user_id = p_user AND m.deleted_at IS NULL AND m.disabled_at IS NULL
        AND public.support_memory_time_eligible(m, v_now)
        AND NOT EXISTS (SELECT 1 FROM public.support_suppressions s
                        WHERE s.user_id = p_user AND s.kind = 'memory' AND s.ref_id = m.id)) INTO v_ok;
    IF NOT v_ok THEN PERFORM public.support_raise('PROPOSAL_EXPIRED', 'proposal basis is no longer eligible'); END IF;
  END IF;
  SELECT * INTO v_cat FROM public.support_template_catalog WHERE template_key = v_prop.template_key AND enabled;
  IF NOT FOUND THEN PERFORM public.support_raise('CONTENT_UNAVAILABLE', 'template unavailable'); END IF;

  PERFORM public.support_release_selection(p_user, p_session, p_new_rev, public.support_opt_text(p_payload, 'previous_disposition', 8));
  IF v_prop.suggested_step IS NOT NULL THEN
    v_cp := jsonb_build_object('version', 1, 'step', jsonb_build_object('action_text', v_prop.suggested_step, 'state', 'draft'));
  END IF;
  BEGIN
    INSERT INTO public.support_activities (id, user_id, support_session_id, template_key, template_version, kind,
      status, checkpoint, last_changed_revision)
    VALUES (v_aid, p_user, p_session.id, v_cat.template_key, v_cat.template_version, v_cat.kind, 'ready', v_cp, p_new_rev);
  EXCEPTION WHEN unique_violation THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'activity id unavailable');
  END;
  UPDATE public.support_work_sessions SET selected_activity_id = v_aid WHERE id = p_session.id;
  UPDATE public.support_proposals SET status = 'accepted', accepted_activity_id = v_aid WHERE id = v_prop.id;
  RETURN jsonb_build_object('event_kind', 'proposal_accepted', 'activity_id', v_aid,
    'event_payload', jsonb_build_object('template_key', v_cat.template_key));
END;
$$;

CREATE FUNCTION public.support_do_start_activity(
  p_user uuid, p_session public.support_work_sessions, p_new_rev bigint, p_payload jsonb
) RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_aid uuid := public.support_try_uuid(p_payload ->> 'activity_id');
  a public.support_activities%ROWTYPE;
  v_cat public.support_template_catalog%ROWTYPE;
  v_key text; v_ex uuid; v_req uuid; v_ref uuid; v_disp text;
BEGIN
  IF v_aid IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'activity_id must be a UUID'); END IF;
  v_disp := public.support_opt_text(p_payload, 'previous_disposition', 8);
  SELECT * INTO a FROM public.support_activities WHERE id = v_aid AND user_id = p_user AND support_session_id = p_session.id FOR UPDATE;
  IF FOUND THEN
    IF public.support_activity_suppressed(p_user, a.id) THEN
      RETURN jsonb_build_object('no_op', true, 'activity_id', a.id, 'extra', jsonb_build_object('reason', 'activity_discarded'));
    END IF;
    IF a.status = 'in_progress' AND p_session.selected_activity_id = a.id THEN
      RETURN jsonb_build_object('no_op', true, 'activity_id', a.id);
    END IF;
    IF a.status NOT IN ('ready', 'paused') THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'activity is already finished');
    END IF;
    IF p_session.selected_activity_id IS DISTINCT FROM a.id THEN
      PERFORM public.support_release_selection(p_user, p_session, p_new_rev, v_disp);
    END IF;
    UPDATE public.support_activities SET status = 'in_progress', last_changed_revision = p_new_rev, updated_at = now() WHERE id = a.id;
    UPDATE public.support_work_sessions SET selected_activity_id = a.id WHERE id = p_session.id;
    RETURN jsonb_build_object('event_kind', 'activity_started', 'activity_id', a.id, 'event_payload', jsonb_build_object('resumed', true));
  END IF;
  v_key := public.support_opt_text(p_payload, 'template_key', 40);
  SELECT * INTO v_cat FROM public.support_template_catalog WHERE template_key = v_key AND enabled;
  IF NOT FOUND THEN PERFORM public.support_raise('CONTENT_UNAVAILABLE', 'unknown or disabled template'); END IF;
  IF v_cat.kind = 'grounding' THEN
    IF p_payload ? 'exercise_id' AND jsonb_typeof(p_payload -> 'exercise_id') <> 'null' THEN
      v_req := public.support_try_uuid(p_payload ->> 'exercise_id');
      IF v_req IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'exercise_id must be a UUID'); END IF;
    END IF;
    v_ex := public.support_resolve_exercise(v_cat.template_key, v_req);
  END IF;
  PERFORM public.support_release_selection(p_user, p_session, p_new_rev, v_disp);
  IF v_ex IS NOT NULL THEN
    -- The activity row carries this id, so an ambiguous retry (same operation id)
    -- replays from the receipt and can never create a second exercise session.
    INSERT INTO public.exercise_sessions (user_id, exercise_id, started_at) VALUES (p_user, v_ex, now()) RETURNING id INTO v_ref;
  END IF;
  BEGIN
    INSERT INTO public.support_activities (id, user_id, support_session_id, template_key, template_version, kind, status,
      canonical_ref_type, canonical_ref_id, last_changed_revision)
    VALUES (v_aid, p_user, p_session.id, v_cat.template_key, v_cat.template_version, v_cat.kind, 'in_progress',
      CASE WHEN v_ref IS NULL THEN NULL ELSE 'exercise_session' END, v_ref, p_new_rev);
  EXCEPTION WHEN unique_violation THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'activity id unavailable');
  END;
  UPDATE public.support_work_sessions SET selected_activity_id = v_aid WHERE id = p_session.id;
  RETURN jsonb_build_object('event_kind', 'activity_started', 'activity_id', v_aid,
    'event_payload', jsonb_build_object('template_key', v_cat.template_key));
END;
$$;

-- Validates the practical-step object shared by checkpoint/finish.
CREATE FUNCTION public.support_check_step(p_step jsonb, p_require_text boolean, p_state text) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE v_text text;
BEGIN
  IF p_step IS NULL OR jsonb_typeof(p_step) <> 'object' THEN
    IF p_require_text THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'step is required'); END IF;
    RETURN;
  END IF;
  v_text := public.support_opt_text(p_step, 'action_text', 400);
  IF p_require_text AND (v_text IS NULL OR btrim(v_text) = '') THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'step text must not be empty');
  END IF;
  IF p_step ? 'state' AND (p_step ->> 'state') NOT IN ('draft', 'saved', 'self_reported_done', 'dismissed') THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'unknown step state');
  END IF;
  IF p_state IS NOT NULL AND (p_step ->> 'state') IS DISTINCT FROM p_state THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'step state must be ' || p_state);
  END IF;
END;
$$;

-- Template v1 stable prompt identifiers (section 5.4). Rejects any other id.
CREATE FUNCTION public.support_check_prompts(p_template text, p_cp jsonb) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_ids text[] := CASE p_template
    WHEN 'ground_present_v1' THEN ARRAY['see', 'feel', 'hear', 'smell', 'taste']
    WHEN 'untangle_thought_v1' THEN ARRAY['on_mind', 'certain_unclear', 'fairer_way']
    WHEN 'choose_step_v1' THEN ARRAY['action', 'smaller'] END;
  k text; e jsonb;
BEGIN
  IF p_cp IS NULL THEN RETURN; END IF;
  FOR k IN SELECT unnest(ARRAY['completed_steps', 'skipped_steps']) LOOP
    IF p_cp ? k AND jsonb_typeof(p_cp -> k) <> 'null' THEN
      IF jsonb_typeof(p_cp -> k) <> 'array' THEN PERFORM public.support_raise('INVALID_PAYLOAD', k || ' must be an array'); END IF;
      FOR e IN SELECT * FROM jsonb_array_elements(p_cp -> k) LOOP
        IF jsonb_typeof(e) <> 'string' OR NOT ((e #>> '{}') = ANY (v_ids)) THEN
          PERFORM public.support_raise('INVALID_PAYLOAD', 'unknown prompt id in ' || k);
        END IF;
      END LOOP;
    END IF;
  END LOOP;
  IF p_cp ? 'current_step' AND jsonb_typeof(p_cp -> 'current_step') <> 'null'
     AND (jsonb_typeof(p_cp -> 'current_step') <> 'string' OR NOT ((p_cp ->> 'current_step') = ANY (v_ids))) THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'unknown current_step');
  END IF;
  IF p_cp ? 'responses' AND jsonb_typeof(p_cp -> 'responses') <> 'null' THEN
    IF jsonb_typeof(p_cp -> 'responses') <> 'object' THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'responses must be an object'); END IF;
    FOR k, e IN SELECT * FROM jsonb_each(p_cp -> 'responses') LOOP
      IF NOT (k = ANY (v_ids)) OR jsonb_typeof(e) <> 'string' OR char_length(e #>> '{}') > 4000 THEN
        PERFORM public.support_raise('INVALID_PAYLOAD', 'responses need known prompt ids and strings up to 4000 characters');
      END IF;
    END LOOP;
  END IF;
END;
$$;

CREATE FUNCTION public.support_do_checkpoint(
  p_user uuid, p_session public.support_work_sessions, p_new_rev bigint, p_payload jsonb
) RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_aid uuid := public.support_try_uuid(p_payload ->> 'activity_id');
  a public.support_activities%ROWTYPE;
  v_cp jsonb := p_payload -> 'checkpoint';
  v_ms bigint; v_pause boolean := false;
BEGIN
  IF v_aid IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'activity_id must be a UUID'); END IF;
  IF v_cp IS NULL OR jsonb_typeof(v_cp) <> 'object' OR (v_cp ->> 'version') IS DISTINCT FROM '1' THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'checkpoint version 1 object required');
  END IF;
  IF octet_length(v_cp::text) > 32768 THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'checkpoint exceeds 32 KiB'); END IF;
  IF coalesce((p_payload ->> 'active_ms') !~ '^[0-9]{1,12}$', true) THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'active_ms must be a non-negative integer');
  END IF;
  v_ms := (p_payload ->> 'active_ms')::bigint;
  IF p_payload ? 'pause' THEN
    IF jsonb_typeof(p_payload -> 'pause') <> 'boolean' THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'pause must be boolean'); END IF;
    v_pause := (p_payload ->> 'pause')::boolean;
  END IF;
  SELECT * INTO a FROM public.support_activities WHERE id = v_aid AND user_id = p_user AND support_session_id = p_session.id FOR UPDATE;
  IF NOT FOUND THEN PERFORM public.support_raise('NOT_FOUND', 'activity not found'); END IF;
  IF public.support_activity_suppressed(p_user, a.id) THEN
    RETURN jsonb_build_object('no_op', true, 'activity_id', a.id, 'extra', jsonb_build_object('reason', 'activity_discarded'));
  END IF;
  IF a.status IN ('completed', 'stopped') THEN
    -- Never move backward over a terminal status.
    RETURN jsonb_build_object('no_op', true, 'activity_id', a.id, 'extra', jsonb_build_object('reason', 'activity_finished'));
  END IF;
  IF a.status = 'ready' THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'start the activity before checkpointing'); END IF;
  IF (v_cp ->> 'template_version') IS DISTINCT FROM a.template_version::text THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'checkpoint template_version does not match the activity');
  END IF;
  IF p_session.selected_activity_id IS NOT NULL AND p_session.selected_activity_id <> a.id THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'activity is not selected; resume it explicitly');
  END IF;
  PERFORM public.support_check_prompts(a.template_key, v_cp);
  IF a.kind = 'next_step' THEN
    PERFORM public.support_check_step(v_cp -> 'step', v_pause, CASE WHEN v_pause THEN 'saved' ELSE NULL END);
  END IF;
  IF v_cp = a.checkpoint AND v_ms <= a.active_ms AND (v_pause = (a.status = 'paused')) THEN
    RETURN jsonb_build_object('no_op', true, 'activity_id', a.id);
  END IF;
  UPDATE public.support_activities SET checkpoint = v_cp, active_ms = greatest(active_ms, v_ms),
    status = CASE WHEN v_pause THEN 'paused' ELSE 'in_progress' END,
    last_changed_revision = p_new_rev, updated_at = now()
    WHERE id = a.id;
  UPDATE public.support_work_sessions SET selected_activity_id = a.id WHERE id = p_session.id;
  RETURN jsonb_build_object('event_kind', CASE WHEN v_pause THEN 'activity_paused' ELSE 'activity_checkpointed' END,
    'activity_id', a.id, 'event_payload', jsonb_build_object('active_ms', greatest(a.active_ms, v_ms)));
END;
$$;

CREATE FUNCTION public.support_do_finish(
  p_user uuid, p_session public.support_work_sessions, p_new_rev bigint, p_payload jsonb
) RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_aid uuid := public.support_try_uuid(p_payload ->> 'activity_id');
  a public.support_activities%ROWTYPE;
  v_outcome text := public.support_opt_text(p_payload, 'outcome', 16);
  v_reason text := public.support_opt_text(p_payload, 'reason', 40);
  v_result jsonb := p_payload -> 'result';
  v_ms bigint := 0; v_rating integer; v_discard boolean := false;
  v_req uuid; v_ex uuid; v_ref uuid; v_xp record; v_xp_json jsonb := NULL;
  v_new_result jsonb; v_new_cp jsonb; v_final_cp jsonb := p_payload -> 'checkpoint';
BEGIN
  IF v_aid IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'activity_id must be a UUID'); END IF;
  IF v_final_cp IS NOT NULL AND jsonb_typeof(v_final_cp) = 'null' THEN v_final_cp := NULL; END IF;
  IF v_final_cp IS NOT NULL AND (jsonb_typeof(v_final_cp) <> 'object' OR (v_final_cp ->> 'version') IS DISTINCT FROM '1' OR octet_length(v_final_cp::text) > 32768) THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'final checkpoint must be a version 1 object up to 32 KiB');
  END IF;
  IF v_outcome IS NULL OR v_outcome NOT IN ('completed', 'stopped') THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'outcome must be completed or stopped');
  END IF;
  IF v_result IS NOT NULL AND (jsonb_typeof(v_result) <> 'object' OR octet_length(v_result::text) > 32768) THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'result must be an object up to 32 KiB');
  END IF;
  -- `discarded` is a server-reserved display marker; erasure state is content_scrubbed_at.
  IF v_result IS NOT NULL AND jsonb_typeof(v_result) = 'object' AND v_result ? 'discarded' THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'result.discarded is reserved');
  END IF;
  IF p_payload ? 'active_ms' THEN
    IF coalesce((p_payload ->> 'active_ms') !~ '^[0-9]{1,12}$', true) THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'active_ms must be a non-negative integer'); END IF;
    v_ms := (p_payload ->> 'active_ms')::bigint;
  END IF;
  IF p_payload ? 'rating' AND jsonb_typeof(p_payload -> 'rating') <> 'null' THEN
    IF coalesce((p_payload ->> 'rating') !~ '^[1-5]$', true) THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'rating must be 1-5'); END IF;
    v_rating := (p_payload ->> 'rating')::integer;
  END IF;
  IF p_payload ? 'discard_content' THEN
    IF jsonb_typeof(p_payload -> 'discard_content') <> 'boolean' THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'discard_content must be boolean'); END IF;
    v_discard := (p_payload ->> 'discard_content')::boolean;
  END IF;
  SELECT * INTO a FROM public.support_activities WHERE id = v_aid AND user_id = p_user AND support_session_id = p_session.id FOR UPDATE;
  IF NOT FOUND THEN PERFORM public.support_raise('NOT_FOUND', 'activity not found'); END IF;
  IF public.support_activity_suppressed(p_user, a.id) THEN
    RETURN jsonb_build_object('no_op', true, 'activity_id', a.id, 'extra', jsonb_build_object('reason', 'activity_discarded'));
  END IF;
  IF a.status IN ('completed', 'stopped') THEN
    IF a.status = v_outcome THEN
      RETURN jsonb_build_object('no_op', true, 'activity_id', a.id);
    END IF;
    PERFORM public.support_raise('INVALID_PAYLOAD', 'activity already ' || a.status);
  END IF;
  IF a.status = 'ready' AND v_outcome = 'completed' THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'start the activity before completing it');
  END IF;
  -- The exact final checkpoint travels with the finish; no earlier checkpoint is assumed.
  IF v_final_cp IS NOT NULL THEN
    IF (v_final_cp ->> 'template_version') IS DISTINCT FROM a.template_version::text THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'checkpoint template_version does not match the activity');
    END IF;
    PERFORM public.support_check_prompts(a.template_key, v_final_cp);
  END IF;

  IF v_outcome = 'completed' THEN
    IF v_reason = 'skipped_all' THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'an all-skipped activity is stopped, not completed');
    END IF;
    IF a.kind = 'next_step' THEN
      PERFORM public.support_check_step(v_result -> 'step', true, 'self_reported_done');
    END IF;
    IF a.kind = 'grounding' THEN
      v_ref := a.canonical_ref_id;
      IF v_ref IS NULL THEN
        IF p_payload ? 'exercise_id' AND jsonb_typeof(p_payload -> 'exercise_id') <> 'null' THEN
          v_req := public.support_try_uuid(p_payload ->> 'exercise_id');
          IF v_req IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'exercise_id must be a UUID'); END IF;
        END IF;
        v_ex := public.support_resolve_exercise(a.template_key, v_req);
        IF v_ex IS NULL THEN
          PERFORM public.support_raise('CONTENT_UNAVAILABLE', 'canonical exercise unavailable; completion stays pending');
        END IF;
        INSERT INTO public.exercise_sessions (user_id, exercise_id, started_at) VALUES (p_user, v_ex, now()) RETURNING id INTO v_ref;
        UPDATE public.support_activities SET canonical_ref_type = 'exercise_session', canonical_ref_id = v_ref WHERE id = a.id;
      END IF;
      -- Existing idempotent completion + 30 XP, same transaction, same session id.
      -- Lock order: support session -> activity -> exercise session -> user stats.
      PERFORM public.complete_exercise_session(v_ref, v_rating, NULL);
      SELECT * INTO v_xp FROM public.award_exercise_session_xp(v_ref);
      v_xp_json := jsonb_build_object('amount', v_xp.amount, 'new_xp', v_xp.new_xp,
        'new_level', v_xp.new_level, 'level_up', v_xp.level_up);
    END IF;
    v_new_result := v_result;
    v_new_cp := coalesce(v_final_cp, a.checkpoint);
  ELSE
    -- Stopped: never touches the canonical completion or XP routines.
    IF a.kind = 'next_step' THEN
      v_new_result := jsonb_build_object('step', jsonb_build_object('state', 'dismissed'));
      v_new_cp := NULL;
    ELSIF v_discard THEN
      v_new_result := NULL; v_new_cp := NULL;
    ELSE
      v_new_result := coalesce(v_result, a.result); v_new_cp := coalesce(v_final_cp, a.checkpoint);
    END IF;
  END IF;

  UPDATE public.support_activities SET status = v_outcome, stop_reason = CASE WHEN v_outcome = 'stopped' THEN coalesce(v_reason, 'user_ended') ELSE NULL END,
    result = v_new_result, checkpoint = v_new_cp, active_ms = greatest(active_ms, v_ms),
    finished_at = now(), last_changed_revision = p_new_rev, updated_at = now()
    WHERE id = a.id;
  IF p_session.selected_activity_id = a.id THEN
    UPDATE public.support_work_sessions SET selected_activity_id = NULL WHERE id = p_session.id;
  END IF;
  RETURN jsonb_build_object('event_kind', CASE WHEN v_outcome = 'completed' THEN 'activity_completed' ELSE 'activity_stopped' END,
    'activity_id', a.id,
    'event_payload', jsonb_build_object('outcome', v_outcome, 'reason', coalesce(v_reason, CASE WHEN v_outcome = 'stopped' THEN 'user_ended' END)),
    'extra', CASE WHEN v_xp_json IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('xp', v_xp_json) END);
END;
$$;

CREATE FUNCTION public.support_do_reflection(
  p_user uuid, p_session public.support_work_sessions, p_new_rev bigint, p_payload jsonb
) RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_aid uuid := public.support_try_uuid(p_payload ->> 'activity_id');
  a public.support_activities%ROWTYPE;
  v_outcome text := public.support_opt_text(p_payload, 'outcome', 16);
  v_note text := public.support_opt_text(p_payload, 'note', 1000);
  v_share boolean := false; v_shareable text := public.support_opt_text(p_payload, 'shareable_text', 1000);
  v_refl jsonb;
BEGIN
  IF v_aid IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'activity_id must be a UUID'); END IF;
  IF v_outcome IS NULL OR v_outcome NOT IN ('helpful', 'not_for_me', 'not_sure', 'skip') THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'outcome must be helpful, not_for_me, not_sure or skip');
  END IF;
  IF p_payload ? 'share_note' THEN
    IF jsonb_typeof(p_payload -> 'share_note') <> 'boolean' THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'share_note must be boolean'); END IF;
    v_share := (p_payload ->> 'share_note')::boolean;
  END IF;
  SELECT * INTO a FROM public.support_activities WHERE id = v_aid AND user_id = p_user AND support_session_id = p_session.id FOR UPDATE;
  IF NOT FOUND THEN PERFORM public.support_raise('NOT_FOUND', 'activity not found'); END IF;
  IF public.support_activity_suppressed(p_user, a.id) THEN
    RETURN jsonb_build_object('no_op', true, 'activity_id', a.id, 'extra', jsonb_build_object('reason', 'activity_discarded'));
  END IF;
  IF a.status NOT IN ('completed', 'stopped') THEN
    PERFORM public.support_raise('INVALID_PAYLOAD', 'reflect after the activity is completed or stopped');
  END IF;
  -- A discarded activity never regains answers/notes from a late reflection attempt.
  IF a.content_scrubbed_at IS NOT NULL THEN
    RETURN jsonb_build_object('no_op', true, 'activity_id', a.id, 'extra', jsonb_build_object('reason', 'activity_discarded'));
  END IF;
  -- Intimate free text is shareable only by deliberate inclusion.
  v_refl := jsonb_build_object('outcome', v_outcome, 'note', v_note, 'share_note', v_share,
    'shareable_text', CASE WHEN v_share THEN v_shareable ELSE NULL END);
  IF v_refl = a.reflection THEN
    RETURN jsonb_build_object('no_op', true, 'activity_id', a.id);
  END IF;
  UPDATE public.support_activities SET reflection = v_refl, last_changed_revision = p_new_rev, updated_at = now() WHERE id = a.id;
  IF v_outcome = 'not_for_me' AND NOT (a.template_key = ANY (p_session.suppressed_templates)) THEN
    UPDATE public.support_work_sessions SET suppressed_templates = array_append(suppressed_templates, a.template_key) WHERE id = p_session.id;
  END IF;
  RETURN jsonb_build_object('event_kind', 'reflection_recorded', 'activity_id', a.id,
    'event_payload', jsonb_build_object('outcome', v_outcome));
END;
$$;

-- Hard-scrub an activity's content (section 5.4 "Discard this reflection"). Works on
-- active and terminal activities; keeps a content-free stopped/discarded history.
-- Idempotent. Canonical exercise completion/XP is never touched or reversed.
CREATE FUNCTION public.support_do_discard(
  p_user uuid, p_session public.support_work_sessions, p_new_rev bigint, p_payload jsonb
) RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_aid uuid := public.support_try_uuid(p_payload ->> 'activity_id');
  a public.support_activities%ROWTYPE;
  v_active boolean; v_step_state text; v_new_result jsonb;
BEGIN
  IF v_aid IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'activity_id must be a UUID'); END IF;
  SELECT * INTO a FROM public.support_activities WHERE id = v_aid AND user_id = p_user AND support_session_id = p_session.id FOR UPDATE;
  IF NOT FOUND THEN PERFORM public.support_raise('NOT_FOUND', 'activity not found'); END IF;
  IF a.content_scrubbed_at IS NOT NULL AND a.checkpoint IS NULL
     AND (a.reflection IS NULL OR ((a.reflection ->> 'note') IS NULL AND (a.reflection ->> 'shareable_text') IS NULL)) THEN
    RETURN jsonb_build_object('no_op', true, 'activity_id', a.id);
  END IF;
  v_active := a.status IN ('ready', 'in_progress', 'paused');
  -- Keep only the content-free step state (never the text) for a practical step.
  v_step_state := CASE WHEN a.kind = 'next_step' THEN
    CASE WHEN v_active THEN 'dismissed' ELSE coalesce(a.result -> 'step' ->> 'state', 'dismissed') END END;
  v_new_result := jsonb_build_object('discarded', true)
    || CASE WHEN v_step_state IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('step', jsonb_build_object('state', v_step_state)) END;
  PERFORM set_config('support.discarding', 'on', true);
  UPDATE public.support_activities SET
      status = CASE WHEN v_active THEN 'stopped' ELSE status END,
      stop_reason = CASE WHEN v_active THEN 'discarded' ELSE stop_reason END,
      finished_at = CASE WHEN v_active THEN now() ELSE finished_at END,
      checkpoint = NULL, result = v_new_result, content_scrubbed_at = coalesce(content_scrubbed_at, now()),
      reflection = CASE WHEN reflection IS NULL THEN NULL
        ELSE jsonb_build_object('outcome', reflection ->> 'outcome', 'note', NULL, 'share_note', false, 'shareable_text', NULL) END,
      last_changed_revision = p_new_rev, updated_at = now()
    WHERE id = a.id;
  PERFORM set_config('support.discarding', 'off', true);
  IF p_session.selected_activity_id = a.id THEN
    UPDATE public.support_work_sessions SET selected_activity_id = NULL WHERE id = p_session.id;
  END IF;
  -- Derived copies: model-drafted step text on proposals tied to this activity, and any
  -- still-offered proposal text for the session's practical step.
  UPDATE public.support_proposals SET suggested_step = NULL
    WHERE user_id = p_user AND support_session_id = p_session.id
      AND (accepted_activity_id = a.id OR (a.kind = 'next_step' AND status = 'offered'));
  -- Receipt edges are KEPT (identifiers only): they are the provenance that lets the
  -- closure suppress assistant turns that already consumed this activity's content.
  INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason)
    VALUES (p_user, 'activity', a.id, 'activity_discarded') ON CONFLICT (user_id, kind, ref_id) DO NOTHING;
  PERFORM public.support_suppress_closure(p_user, NULL, p_session.id);
  RETURN jsonb_build_object('event_kind', 'activity_discarded', 'activity_id', a.id,
    'event_payload', jsonb_build_object('was_active', v_active));
END;
$$;

CREATE FUNCTION public.support_do_delete(p_user uuid, p_session public.support_work_sessions) RETURNS jsonb
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
  UPDATE public.support_work_sessions SET selected_activity_id = NULL WHERE id = p_session.id AND user_id = p_user;
  DELETE FROM public.support_activities WHERE support_session_id = p_session.id AND user_id = p_user;
  DELETE FROM public.support_session_events WHERE support_session_id = p_session.id AND user_id = p_user;
  DELETE FROM public.support_proposals WHERE support_session_id = p_session.id AND user_id = p_user;
  -- Derived references only; the conversation and its messages are separately owned
  -- records and are NOT deleted here.
  UPDATE public.support_context_receipts SET support_session_id = NULL WHERE support_session_id = p_session.id AND user_id = p_user;
  UPDATE public.messages SET support_session_id = NULL WHERE support_session_id = p_session.id
    AND conversation_id IN (SELECT id FROM public.conversations WHERE user_id = p_user);
  UPDATE public.chat_requests SET support_session_id = NULL WHERE support_session_id = p_session.id AND user_id = p_user;
  -- The row stays as a content-free tombstone.
  UPDATE public.support_work_sessions SET status = 'deleted', deleted_at = now(), title = '', concern = NULL,
    conversation_id = NULL, suppressed_templates = '{}' WHERE id = p_session.id AND user_id = p_user;
  RETURN jsonb_build_object('event_kind', 'session_deleted', 'extra', jsonb_build_object('deleted', true));
END;
$$;

-- ---------------------------------------------------------------------------
-- The one mutation entrypoint
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_apply_mutation(p_envelope jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_user uuid := auth.uid();
  v_op uuid; v_sid uuid; v_kind text; v_payload jsonb; v_expected bigint;
  v_hash text; v_receipt public.support_mutation_receipts%ROWTYPE;
  v_session public.support_work_sessions%ROWTYPE;
  v_new_rev bigint; v_res jsonb; v_event uuid; v_noop boolean; v_resp jsonb;
  v_code text; v_detail text; v_activity uuid; v_event_kind text;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501'; END IF;
  BEGIN
    IF p_envelope IS NULL OR jsonb_typeof(p_envelope) <> 'object' OR octet_length(p_envelope::text) > 131072 THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'envelope must be an object up to 128 KiB');
    END IF;
    IF (p_envelope ->> 'schema_version') IS DISTINCT FROM '1' THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'schema_version 1 required');
    END IF;
    v_op := public.support_try_uuid(p_envelope ->> 'operation_id');
    v_sid := public.support_try_uuid(p_envelope ->> 'session_id');
    IF v_op IS NULL OR v_sid IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'operation_id and session_id must be UUIDs'); END IF;
    v_kind := p_envelope ->> 'kind';
    IF v_kind IS NULL OR v_kind NOT IN ('create', 'update_session', 'accept_proposal', 'start_activity',
        'checkpoint_activity', 'finish_activity', 'discard_activity_answers', 'record_reflection', 'delete_session') THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'unknown kind');
    END IF;
    v_payload := coalesce(p_envelope -> 'payload', '{}'::jsonb);
    IF jsonb_typeof(v_payload) <> 'object' THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'payload must be an object'); END IF;
    IF p_envelope ? 'expected_revision' AND jsonb_typeof(p_envelope -> 'expected_revision') <> 'null' THEN
      IF coalesce((p_envelope ->> 'expected_revision') !~ '^[0-9]{1,15}$', true) THEN
        PERFORM public.support_raise('INVALID_PAYLOAD', 'expected_revision must be an integer');
      END IF;
      v_expected := (p_envelope ->> 'expected_revision')::bigint;
    END IF;

    PERFORM public.support_acquire_write_mutex();
    -- Serialize duplicate deliveries of the same operation.
    PERFORM pg_advisory_xact_lock(hashtextextended(v_user::text || ':' || v_op::text, 0));
    -- Context-changing writes serialize behind the single write mutex FIRST (see
    -- support_acquire_write_mutex); only then the privacy row, sessions, claims, proposals and
    -- activities are taken in that order. SHARE for ordinary kinds, EXCLUSIVE for discard.
    PERFORM public.support_ensure_privacy_state(v_user);
    IF v_kind = 'discard_activity_answers' THEN
      PERFORM 1 FROM public.support_privacy_state WHERE user_id = v_user FOR UPDATE;
    ELSE
      PERFORM 1 FROM public.support_privacy_state WHERE user_id = v_user FOR SHARE;
    END IF;
    v_hash := encode(sha256(convert_to(jsonb_build_object('s', 1, 'k', v_kind, 'sid', v_sid, 'p', v_payload)::text, 'UTF8')), 'hex');

    SELECT * INTO v_receipt FROM public.support_mutation_receipts WHERE user_id = v_user AND operation_id = v_op;
    IF FOUND THEN
      IF v_receipt.payload_hash <> v_hash OR v_receipt.operation_kind <> v_kind OR v_receipt.session_id <> v_sid THEN
        RETURN jsonb_build_object('ok', false, 'code', 'OPERATION_ID_REUSED',
          'message', 'operation_id was already used for a different request');
      END IF;
      -- Confirmed replay: no mutation, even when expected_revision is now old.
      RETURN v_receipt.response || jsonb_build_object('replayed', true, 'server_time', now(),
        'snapshot', public.support_snapshot(v_user, v_sid));
    END IF;

    IF v_kind = 'create' THEN
      IF v_expected IS NOT NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'expected_revision must be null on create'); END IF;
      v_res := public.support_do_create(v_user, v_sid, v_payload);
      v_new_rev := 1;
    ELSE
      SELECT * INTO v_session FROM public.support_work_sessions WHERE id = v_sid AND user_id = v_user FOR UPDATE;
      IF NOT FOUND OR v_session.status = 'deleted' THEN PERFORM public.support_raise('NOT_FOUND', 'session not found'); END IF;
      IF v_expected IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'expected_revision required'); END IF;
      IF v_expected <> v_session.revision THEN
        RETURN jsonb_build_object('ok', false, 'code', 'REVISION_CONFLICT', 'current_revision', v_session.revision,
          'snapshot', public.support_snapshot(v_user, v_sid));
      END IF;
      IF v_session.status = 'closed' AND v_kind NOT IN ('update_session', 'delete_session', 'discard_activity_answers') THEN
        PERFORM public.support_raise('INVALID_PAYLOAD', 'session is closed; continue as a new session');
      END IF;
      v_new_rev := v_session.revision + 1;
      v_res := CASE v_kind
        WHEN 'update_session' THEN public.support_do_update_session(v_user, v_session, v_new_rev, v_payload)
        WHEN 'accept_proposal' THEN public.support_do_accept_proposal(v_user, v_session, v_new_rev, v_payload)
        WHEN 'start_activity' THEN public.support_do_start_activity(v_user, v_session, v_new_rev, v_payload)
        WHEN 'checkpoint_activity' THEN public.support_do_checkpoint(v_user, v_session, v_new_rev, v_payload)
        WHEN 'finish_activity' THEN public.support_do_finish(v_user, v_session, v_new_rev, v_payload)
        WHEN 'record_reflection' THEN public.support_do_reflection(v_user, v_session, v_new_rev, v_payload)
        WHEN 'discard_activity_answers' THEN public.support_do_discard(v_user, v_session, v_new_rev, v_payload)
        WHEN 'delete_session' THEN public.support_do_delete(v_user, v_session)
      END;
    END IF;

    v_noop := coalesce((v_res ->> 'no_op')::boolean, false);
    v_activity := public.support_try_uuid(v_res ->> 'activity_id');
    v_event_kind := v_res ->> 'event_kind';
    IF v_noop THEN
      v_new_rev := v_session.revision;
    ELSE
      IF v_kind <> 'create' THEN
        UPDATE public.support_work_sessions SET revision = v_new_rev, updated_at = now() WHERE id = v_sid AND user_id = v_user;
      END IF;
      INSERT INTO public.support_session_events (user_id, support_session_id, activity_id, operation_id, kind, seq,
        client_occurred_at, payload)
      VALUES (v_user, v_sid, v_activity, v_op, v_event_kind, v_new_rev,
        public.support_try_ts(p_envelope ->> 'client_occurred_at'), coalesce(v_res -> 'event_payload', '{}'::jsonb))
      RETURNING id INTO v_event;
    END IF;

    v_resp := jsonb_build_object('ok', true, 'operation_id', v_op, 'kind', v_kind, 'revision', v_new_rev,
      'no_op', v_noop, 'event_id', v_event, 'activity_id', v_activity, 'sync_status', 'synced')
      || coalesce(v_res -> 'extra', '{}'::jsonb);
    INSERT INTO public.support_mutation_receipts (user_id, operation_id, operation_kind, session_id, target_id,
      payload_hash, resulting_revision, response)
    VALUES (v_user, v_op, v_kind, v_sid, v_activity, v_hash, v_new_rev, v_resp);
    RETURN v_resp || jsonb_build_object('replayed', false, 'server_time', now(),
      'snapshot', public.support_snapshot(v_user, v_sid));
  EXCEPTION WHEN SQLSTATE 'SS001' THEN
    GET STACKED DIAGNOSTICS v_code = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL;
    RETURN jsonb_build_object('ok', false, 'code', v_code, 'message', nullif(v_detail, ''));
  END;
END;
$$;

-- ---------------------------------------------------------------------------
-- Reads (no operation id, no CAS)
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_get_session(p_session_id uuid, p_after_seq bigint DEFAULT 0, p_event_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_user uuid := auth.uid();
  v_snap jsonb; v_events jsonb;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501'; END IF;
  v_snap := public.support_snapshot(v_user, p_session_id);
  IF v_snap IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NOT_FOUND');
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'activity_id', e.activity_id, 'operation_id', e.operation_id,
      'kind', e.kind, 'seq', e.seq, 'client_occurred_at', e.client_occurred_at, 'accepted_at', e.accepted_at,
      'payload', e.payload) ORDER BY e.seq), '[]'::jsonb)
    INTO v_events FROM (
      SELECT * FROM public.support_session_events
      WHERE support_session_id = p_session_id AND user_id = v_user AND seq > greatest(coalesce(p_after_seq, 0), 0)
      ORDER BY seq LIMIT least(greatest(coalesce(p_event_limit, 100), 1), 200)) e;
  RETURN jsonb_build_object('ok', true, 'snapshot', v_snap, 'events', v_events, 'server_time', now());
END;
$$;

CREATE FUNCTION public.support_session_summary(p_user uuid, p_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = pg_catalog, public, pg_temp AS $$
  SELECT jsonb_build_object(
    'id', s.id, 'conversation_id', s.conversation_id, 'previous_session_id', s.previous_session_id,
    'title', s.title, 'status', s.status, 'context_scope', s.context_scope, 'revision', s.revision,
    'selected_activity_id', s.selected_activity_id, 'created_at', s.created_at, 'updated_at', s.updated_at,
    'closed_at', s.closed_at, 'deleted_at', s.deleted_at,
    'unfinished_count', (SELECT count(*) FROM public.support_activities a
                         WHERE a.support_session_id = s.id AND a.user_id = p_user
                           AND a.status IN ('ready', 'in_progress', 'paused')),
    'selected_activity', (SELECT jsonb_build_object('id', a.id, 'template_key', a.template_key, 'status', a.status)
                          FROM public.support_activities a WHERE a.id = s.selected_activity_id AND a.user_id = p_user))
  FROM public.support_work_sessions s WHERE s.id = p_id AND s.user_id = p_user;
$$;

-- Stable (updated_at, id) cursor. p_direction 'desc' = history; 'asc' = incremental
-- sync from a cursor (pass p_include_deleted => true to receive tombstones).
CREATE FUNCTION public.support_list_sessions(
  p_limit integer DEFAULT 50, p_cursor_updated_at timestamptz DEFAULT NULL, p_cursor_id uuid DEFAULT NULL,
  p_status text DEFAULT NULL, p_direction text DEFAULT 'desc', p_include_deleted boolean DEFAULT false
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_user uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_asc boolean := coalesce(p_direction, 'desc') = 'asc';
  v_items jsonb; v_count integer; v_ts timestamptz; v_id uuid;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501'; END IF;
  IF p_direction IS NOT NULL AND p_direction NOT IN ('asc', 'desc') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD', 'message', 'direction must be asc or desc');
  END IF;
  IF p_status IS NOT NULL AND p_status NOT IN ('open', 'closed', 'deleted') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD', 'message', 'unknown status filter');
  END IF;
  IF (p_cursor_updated_at IS NULL) <> (p_cursor_id IS NULL) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD', 'message', 'cursor needs updated_at and id');
  END IF;
  IF v_asc THEN
    WITH page AS (
      SELECT s.id, s.updated_at FROM public.support_work_sessions s
      WHERE s.user_id = v_user AND (p_status IS NULL OR s.status = p_status)
        AND (p_include_deleted OR s.status <> 'deleted' OR p_status = 'deleted')
        AND (p_cursor_updated_at IS NULL OR (s.updated_at, s.id) > (p_cursor_updated_at, p_cursor_id))
      ORDER BY s.updated_at ASC, s.id ASC LIMIT v_limit)
    SELECT coalesce(jsonb_agg(public.support_session_summary(v_user, p.id) ORDER BY p.updated_at ASC, p.id ASC), '[]'::jsonb),
           count(*),
           (array_agg(p.updated_at ORDER BY p.updated_at DESC, p.id DESC))[1],
           (array_agg(p.id ORDER BY p.updated_at DESC, p.id DESC))[1]
      INTO v_items, v_count, v_ts, v_id FROM page p;
  ELSE
    WITH page AS (
      SELECT s.id, s.updated_at FROM public.support_work_sessions s
      WHERE s.user_id = v_user AND (p_status IS NULL OR s.status = p_status)
        AND (p_include_deleted OR s.status <> 'deleted' OR p_status = 'deleted')
        AND (p_cursor_updated_at IS NULL OR (s.updated_at, s.id) < (p_cursor_updated_at, p_cursor_id))
      ORDER BY s.updated_at DESC, s.id DESC LIMIT v_limit)
    SELECT coalesce(jsonb_agg(public.support_session_summary(v_user, p.id) ORDER BY p.updated_at DESC, p.id DESC), '[]'::jsonb),
           count(*),
           (array_agg(p.updated_at ORDER BY p.updated_at ASC, p.id ASC))[1],
           (array_agg(p.id ORDER BY p.updated_at ASC, p.id ASC))[1]
      INTO v_items, v_count, v_ts, v_id FROM page p;
  END IF;
  RETURN jsonb_build_object('ok', true, 'items', v_items,
    'next_cursor', CASE WHEN v_count >= v_limit THEN jsonb_build_object('updated_at', v_ts, 'id', v_id) END,
    'privacy_revision', coalesce((SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = v_user), 1),
    'server_time', now());
END;
$$;

-- ---------------------------------------------------------------------------
-- Grants: internal helpers/handlers are not callable by API roles
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION
  public.support_try_ts(text), public.support_raise(text, text), public.support_opt_text(jsonb, text, integer),
  public.support_ensure_privacy_state(uuid), public.support_activity_json(public.support_activities),
  public.support_snapshot(uuid, uuid), public.support_session_summary(uuid, uuid),
  public.support_release_selection(uuid, public.support_work_sessions, bigint, text),
  public.support_resolve_exercise(text, uuid), public.support_check_step(jsonb, boolean, text),
  public.support_do_create(uuid, uuid, jsonb),
  public.support_do_update_session(uuid, public.support_work_sessions, bigint, jsonb),
  public.support_do_accept_proposal(uuid, public.support_work_sessions, bigint, jsonb),
  public.support_do_start_activity(uuid, public.support_work_sessions, bigint, jsonb),
  public.support_do_checkpoint(uuid, public.support_work_sessions, bigint, jsonb),
  public.support_do_finish(uuid, public.support_work_sessions, bigint, jsonb),
  public.support_do_reflection(uuid, public.support_work_sessions, bigint, jsonb),
  public.support_do_delete(uuid, public.support_work_sessions),
  public.support_do_discard(uuid, public.support_work_sessions, bigint, jsonb),
  public.support_suppress_closure(uuid, uuid, uuid), public.support_memory_time_eligible(public.companion_memory, timestamptz), public.support_acquire_write_mutex(),
  public.support_origin_conversation(uuid, uuid), public.support_activity_suppressed(uuid, uuid),
  public.support_receipt_source_current(uuid, text, uuid, bigint, text, uuid, timestamptz),
  public.support_check_prompts(text, jsonb)
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.support_apply_mutation(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.support_get_session(uuid, bigint, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.support_list_sessions(integer, timestamptz, uuid, text, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.support_apply_mutation(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.support_get_session(uuid, bigint, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.support_list_sessions(integer, timestamptz, uuid, text, text, boolean) TO authenticated;

COMMIT;
