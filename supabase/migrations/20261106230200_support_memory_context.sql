-- Support session server contract, part 3 of 3: memory lifecycle, privacy revision,
-- legacy-write guards, canonical chat-turn confirmation, receipt resolution, capabilities.
--
-- NOT EXECUTED by its author; requires parts 1 and 2 and independent review on a
-- disposable database first. Spec sections 8.2-8.6.
--
-- Invariants enforced IN THE DATABASE (so the existing update-companion-memory /
-- delete-companion-memory endpoints and direct fragment writes cannot bypass them):
--   * Editing a memory's content/category increments its revision, invalidates dependent
--     proposals, suppresses assistant turns that cited an older revision (and their
--     transitive closure) and increments the account privacy revision.
--   * Stopping/resuming use, soft-deleting or deleting a memory increments the privacy
--     revision; deleting/soft-deleting forgets (suppression + closure + content removal).
--   * Protected provenance/approval columns on companion_memory and review columns on
--     memory_fragments are writable only by the controlled RPC path
--     (support.memory_rpc = on, transaction-local). Legacy writes keep working; fabricated
--     origin/approval/provenance is silently reset to the honest value.
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $$
BEGIN
  IF to_regprocedure('public.support_apply_mutation(jsonb)') IS NULL
     OR to_regprocedure('public.support_suppress_closure(uuid,uuid,boolean)') IS NULL THEN
    RAISE EXCEPTION 'support session RPC migration must be applied first';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_bump_privacy(p_user uuid) RETURNS bigint
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE v bigint;
BEGIN
  PERFORM public.support_ensure_privacy_state(p_user);
  UPDATE public.support_privacy_state SET privacy_revision = privacy_revision + 1, updated_at = now()
    WHERE user_id = p_user RETURNING privacy_revision INTO v;
  RETURN v;
END;
$$;

CREATE FUNCTION public.support_invalidate_memory_proposals(p_user uuid, p_memory uuid) RETURNS void
LANGUAGE sql SET search_path = pg_catalog, public, pg_temp AS $$
  UPDATE public.support_proposals SET status = 'invalidated'
   WHERE user_id = p_user AND status = 'offered' AND basis_kind = 'companion_memory' AND basis_ref = p_memory;
$$;

CREATE FUNCTION public.support_memory_event(
  p_user uuid, p_kind text, p_id uuid, p_event text, p_mrev integer, p_prev bigint, p_op uuid
) RETURNS void LANGUAGE sql SET search_path = pg_catalog, public, pg_temp AS $$
  INSERT INTO public.support_memory_events (user_id, memory_kind, memory_id, event, memory_revision, privacy_revision, operation_id)
  VALUES (p_user, p_kind, p_id, p_event, p_mrev, p_prev, p_op);
$$;

-- Forget a canonical memory: suppression, provenance, fragment copies, closure, privacy.
CREATE FUNCTION public.support_forget_memory_effects(p_user uuid, m public.companion_memory, p_op uuid) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_prev text := coalesce(current_setting('support.memory_rpc', true), '');
  v_skip uuid := public.support_try_uuid(current_setting('support.skip_fragment', true));
  v_priv bigint;
BEGIN
  PERFORM set_config('support.memory_rpc', 'on', true);
  INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason, memory_revision, operation_id)
    VALUES (p_user, 'memory', m.id, 'forgotten_memory', m.revision, p_op) ON CONFLICT (user_id, kind, ref_id) DO NOTHING;
  IF m.source_message_id IS NOT NULL THEN
    INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason, operation_id)
      VALUES (p_user, 'message', m.source_message_id, 'forgotten_memory', p_op) ON CONFLICT (user_id, kind, ref_id) DO NOTHING;
  ELSIF m.source_conversation_id IS NOT NULL THEN
    INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason, operation_id)
      VALUES (p_user, 'conversation', m.source_conversation_id, 'forgotten_memory', p_op) ON CONFLICT (user_id, kind, ref_id) DO NOTHING;
  END IF;
  -- The promoted fragment held a second copy of the plaintext: blank it (never the row
  -- currently being deleted by an outer trigger, which would cancel that delete).
  UPDATE public.memory_fragments SET value = '', review_state = 'dismissed', updated_at = now()
    WHERE user_id = p_user AND id IS DISTINCT FROM v_skip
      AND (id = m.approved_from_fragment_id OR promoted_memory_id = m.id);
  IF m.approved_from_fragment_id IS NOT NULL THEN
    INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason, operation_id)
      VALUES (p_user, 'fragment', m.approved_from_fragment_id, 'forgotten_fragment', p_op) ON CONFLICT (user_id, kind, ref_id) DO NOTHING;
  END IF;
  PERFORM public.support_suppress_closure(p_user, p_op);
  v_priv := public.support_bump_privacy(p_user);
  PERFORM public.support_memory_event(p_user, 'companion_memory', m.id, 'forgotten', m.revision, v_priv, p_op);
  PERFORM set_config('support.memory_rpc', v_prev, true);
END;
$$;

-- Forget a generated fragment. A promoted fragment forgets its canonical memory too.
CREATE FUNCTION public.support_forget_fragment_effects(p_user uuid, f public.memory_fragments, p_op uuid) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_prev text := coalesce(current_setting('support.memory_rpc', true), '');
  v_prev_skip text := coalesce(current_setting('support.skip_fragment', true), '');
  v_priv bigint;
BEGIN
  PERFORM set_config('support.memory_rpc', 'on', true);
  INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason, operation_id)
    VALUES (p_user, 'fragment', f.id, 'forgotten_fragment', p_op) ON CONFLICT (user_id, kind, ref_id) DO NOTHING;
  IF f.source_message_id IS NOT NULL THEN
    INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason, operation_id)
      VALUES (p_user, 'message', f.source_message_id, 'forgotten_fragment', p_op) ON CONFLICT (user_id, kind, ref_id) DO NOTHING;
  ELSIF f.source_conversation_id IS NOT NULL THEN
    -- Legacy provenance is conversation-level only.
    INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason, operation_id)
      VALUES (p_user, 'conversation', f.source_conversation_id, 'forgotten_fragment', p_op) ON CONFLICT (user_id, kind, ref_id) DO NOTHING;
  END IF;
  PERFORM set_config('support.skip_fragment', f.id::text, true);
  -- Deleting the canonical record runs its own forget effects via its guard trigger.
  DELETE FROM public.companion_memory
    WHERE user_id = p_user AND (id = f.promoted_memory_id OR approved_from_fragment_id = f.id);
  PERFORM set_config('support.skip_fragment', v_prev_skip, true);
  PERFORM public.support_suppress_closure(p_user, p_op);
  v_priv := public.support_bump_privacy(p_user);
  PERFORM public.support_memory_event(p_user, 'memory_fragment', f.id, 'forgotten', NULL, v_priv, p_op);
  PERFORM set_config('support.memory_rpc', v_prev, true);
END;
$$;

-- A correction: new revision. Turns that cited an older revision (and their transitive
-- dependents) leave future context; dependent proposals are invalidated.
CREATE FUNCTION public.support_memory_edit_effects(p_user uuid, p_memory uuid, p_old_rev integer, p_new_rev integer, p_op uuid) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE v_priv bigint;
BEGIN
  PERFORM public.support_invalidate_memory_proposals(p_user, p_memory);
  INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason, operation_id)
    SELECT DISTINCT p_user, 'message', r.assistant_message_id, 'derived_from_forgotten', p_op
    FROM public.support_context_receipt_sources src
    JOIN public.support_context_receipts r ON r.id = src.receipt_id AND r.user_id = p_user
    WHERE src.user_id = p_user AND src.source_kind = 'companion_memory' AND src.source_id = p_memory
      AND src.source_revision <= p_old_rev AND r.assistant_message_id IS NOT NULL
    ON CONFLICT (user_id, kind, ref_id) DO NOTHING;
  PERFORM public.support_suppress_closure(p_user, p_op);
  v_priv := public.support_bump_privacy(p_user);
  PERFORM public.support_memory_event(p_user, 'companion_memory', p_memory, 'edited', p_new_rev, v_priv, p_op);
END;
$$;

-- ---------------------------------------------------------------------------
-- Guard triggers: the same invariants for every writer, including legacy endpoints
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_companion_memory_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_rpc boolean := coalesce(current_setting('support.memory_rpc', true), '') = 'on';
  v_op uuid := public.support_try_uuid(current_setting('support.op_id', true));
  v_priv bigint;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.deleted_at IS NULL THEN PERFORM public.support_forget_memory_effects(OLD.user_id, OLD, v_op); END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NOT v_rpc THEN
      -- Legacy creation keeps working but cannot fabricate approval/provenance.
      NEW.origin := 'user_authored'; NEW.approved_from_fragment_id := NULL;
      NEW.source_message_id := NULL; NEW.source_conversation_id := NULL;
      NEW.revision := 1; NEW.disabled_at := NULL; NEW.confirmed_at := now();
    ELSE
      NEW.confirmed_at := coalesce(NEW.confirmed_at, now());
    END IF;
    -- A new ACTIVE memory (legacy create or approved candidate) changes what a request may
    -- include: advance the privacy/eligibility revision in the same transaction. The bump
    -- takes the row lock that confirmation holds FOR SHARE, so an in-flight request cannot
    -- confirm at the previous revision after this boundary was acknowledged.
    IF NEW.deleted_at IS NULL AND NEW.disabled_at IS NULL THEN
      v_priv := public.support_bump_privacy(NEW.user_id);
      PERFORM public.support_memory_event(NEW.user_id, 'companion_memory', NEW.id, 'created', NEW.revision, v_priv, v_op);
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE
  IF NOT v_rpc THEN
    NEW.origin := OLD.origin; NEW.approved_from_fragment_id := OLD.approved_from_fragment_id;
    NEW.source_message_id := OLD.source_message_id; NEW.source_conversation_id := OLD.source_conversation_id;
    NEW.revision := OLD.revision; NEW.confirmed_at := OLD.confirmed_at;
  END IF;
  IF OLD.deleted_at IS NOT NULL THEN
    NEW.deleted_at := OLD.deleted_at; NEW.content := OLD.content;   -- no resurrection
    RETURN NEW;
  END IF;
  IF NEW.deleted_at IS NOT NULL THEN
    -- Legacy soft delete is treated as Forget: remove plaintext, suppress, bump.
    PERFORM public.support_forget_memory_effects(OLD.user_id, OLD, v_op);
    NEW.content := '[removed]'; NEW.revision := OLD.revision + 1;
    RETURN NEW;
  END IF;
  IF NEW.content IS DISTINCT FROM OLD.content OR NEW.category IS DISTINCT FROM OLD.category THEN
    NEW.revision := OLD.revision + 1; NEW.confirmed_at := now(); NEW.review_due_at := NULL;
    PERFORM public.support_memory_edit_effects(OLD.user_id, OLD.id, OLD.revision, NEW.revision, v_op);
  END IF;
  IF NEW.expires_at IS DISTINCT FROM OLD.expires_at OR NEW.review_due_at IS DISTINCT FROM OLD.review_due_at THEN
    -- Extending relevance can make a stale/expired memory eligible again.
    v_priv := public.support_bump_privacy(OLD.user_id);
  END IF;
  IF (NEW.disabled_at IS NULL) <> (OLD.disabled_at IS NULL) THEN
    IF NEW.disabled_at IS NOT NULL THEN
      NEW.disabled_at := coalesce(NEW.disabled_at, now());
      PERFORM public.support_invalidate_memory_proposals(OLD.user_id, OLD.id);
    END IF;
    v_priv := public.support_bump_privacy(OLD.user_id);
    PERFORM public.support_memory_event(OLD.user_id, 'companion_memory', OLD.id,
      CASE WHEN NEW.disabled_at IS NOT NULL THEN 'disabled' ELSE 'enabled' END, NEW.revision, v_priv, v_op);
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER support_companion_memory_guard_trg
  BEFORE INSERT OR UPDATE OR DELETE ON public.companion_memory
  FOR EACH ROW EXECUTE FUNCTION public.support_companion_memory_guard();

CREATE FUNCTION public.support_memory_fragment_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_rpc boolean := coalesce(current_setting('support.memory_rpc', true), '') = 'on';
  v_op uuid := public.support_try_uuid(current_setting('support.op_id', true));
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.support_forget_fragment_effects(OLD.user_id, OLD, v_op);
    RETURN OLD;
  END IF;
  IF NOT v_rpc THEN
    IF TG_OP = 'INSERT' THEN
      IF NEW.review_state NOT IN ('legacy_review', 'pending') THEN NEW.review_state := 'legacy_review'; END IF;
      NEW.approved_at := NULL; NEW.promoted_memory_id := NULL;
    ELSE
      NEW.review_state := OLD.review_state; NEW.approved_at := OLD.approved_at;
      NEW.promoted_memory_id := OLD.promoted_memory_id; NEW.candidate_expires_at := OLD.candidate_expires_at;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER support_memory_fragment_guard_trg
  BEFORE INSERT OR UPDATE OR DELETE ON public.memory_fragments
  FOR EACH ROW EXECUTE FUNCTION public.support_memory_fragment_guard();

-- ---------------------------------------------------------------------------
-- Memory / privacy mutation entrypoint
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_memory_mutate(p_envelope jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_user uuid := auth.uid();
  v_op uuid; v_kind text; v_payload jsonb; v_hash text;
  v_rec public.support_privacy_operations%ROWTYPE;
  v_resp jsonb := '{}'::jsonb; v_code text; v_detail text;
  v_id uuid; v_content text; v_cat text; v_expected integer;
  m public.companion_memory%ROWTYPE;
  f public.memory_fragments%ROWTYPE;
  v_new_id uuid; v_closure integer := 0; v_ckind text; v_rev integer;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501'; END IF;
  BEGIN
    IF p_envelope IS NULL OR jsonb_typeof(p_envelope) <> 'object' OR octet_length(p_envelope::text) > 16384 THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'envelope must be an object up to 16 KiB');
    END IF;
    IF (p_envelope ->> 'schema_version') IS DISTINCT FROM '1' THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'schema_version 1 required'); END IF;
    v_op := public.support_try_uuid(p_envelope ->> 'operation_id');
    IF v_op IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'operation_id must be a UUID'); END IF;
    v_kind := p_envelope ->> 'kind';
    IF v_kind IS NULL OR v_kind NOT IN ('memory_edit', 'memory_stop_using', 'memory_resume_using', 'memory_forget',
        'candidate_approve', 'candidate_dismiss', 'suppress_source', 'unsuppress_source') THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'unknown kind');
    END IF;
    v_payload := coalesce(p_envelope -> 'payload', '{}'::jsonb);
    IF jsonb_typeof(v_payload) <> 'object' THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'payload must be an object'); END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(v_user::text || ':priv:' || v_op::text, 0));
    PERFORM public.support_ensure_privacy_state(v_user);
    -- Serialize every privacy-affecting mutation for this account.
    PERFORM 1 FROM public.support_privacy_state WHERE user_id = v_user FOR UPDATE;
    v_hash := encode(sha256(convert_to(jsonb_build_object('s', 1, 'k', v_kind, 'p', v_payload)::text, 'UTF8')), 'hex');
    SELECT * INTO v_rec FROM public.support_privacy_operations WHERE user_id = v_user AND operation_id = v_op;
    IF FOUND THEN   -- replay precedes any revision comparison
      IF v_rec.payload_hash <> v_hash OR v_rec.kind <> v_kind THEN
        RETURN jsonb_build_object('ok', false, 'code', 'OPERATION_ID_REUSED', 'message', 'operation_id was already used for a different request');
      END IF;
      RETURN v_rec.response || jsonb_build_object('replayed', true, 'server_time', now());
    END IF;

    PERFORM set_config('support.op_id', v_op::text, true);
    v_id := public.support_try_uuid(coalesce(v_payload ->> 'memory_id', v_payload ->> 'fragment_id', v_payload ->> 'id'));
    IF v_payload ? 'expected_revision' AND jsonb_typeof(v_payload -> 'expected_revision') <> 'null' THEN
      IF coalesce((v_payload ->> 'expected_revision') !~ '^[0-9]{1,9}$', true) THEN
        PERFORM public.support_raise('INVALID_PAYLOAD', 'expected_revision must be an integer');
      END IF;
      v_expected := (v_payload ->> 'expected_revision')::integer;
    END IF;

    IF v_kind = 'memory_edit' THEN
      v_content := btrim(public.support_opt_text(v_payload, 'content', 500));
      v_cat := public.support_opt_text(v_payload, 'category', 32);
      IF v_id IS NULL OR v_content IS NULL OR v_content = '' THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'memory_id and non-empty content required'); END IF;
      IF v_expected IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'expected_revision is required for a correction'); END IF;
      SELECT * INTO m FROM public.companion_memory WHERE id = v_id AND user_id = v_user AND deleted_at IS NULL FOR UPDATE;
      IF NOT FOUND THEN PERFORM public.support_raise('NOT_FOUND', 'memory not found'); END IF;
      IF v_cat IS NOT NULL AND v_cat NOT IN ('boundaries', 'preferences', 'triggers', 'avoid_topics', 'positive_reinforcement', 'life_context') THEN
        PERFORM public.support_raise('INVALID_PAYLOAD', 'unknown category');
      END IF;
      IF v_expected <> m.revision THEN
        RETURN jsonb_build_object('ok', false, 'code', 'REVISION_CONFLICT', 'current_revision', m.revision,
          'memory', jsonb_build_object('id', m.id, 'category', m.category, 'content', m.content, 'revision', m.revision));
      END IF;
      IF v_content = m.content AND coalesce(v_cat, m.category) = m.category THEN
        v_resp := jsonb_build_object('no_op', true, 'memory_id', m.id, 'memory_revision', m.revision);
      ELSE
        -- The guard trigger assigns the new revision, suppresses turns that cited the old
        -- one, invalidates proposals and bumps the privacy revision (legacy writers too).
        UPDATE public.companion_memory SET content = v_content, category = coalesce(v_cat, category)
          WHERE id = m.id RETURNING revision INTO v_rev;
        v_resp := jsonb_build_object('memory_id', m.id, 'memory_revision', v_rev);
      END IF;

    ELSIF v_kind IN ('memory_stop_using', 'memory_resume_using') THEN
      IF v_id IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'memory_id required'); END IF;
      SELECT * INTO m FROM public.companion_memory WHERE id = v_id AND user_id = v_user AND deleted_at IS NULL FOR UPDATE;
      IF NOT FOUND THEN PERFORM public.support_raise('NOT_FOUND', 'memory not found'); END IF;
      IF v_expected IS NOT NULL AND v_expected <> m.revision THEN
        RETURN jsonb_build_object('ok', false, 'code', 'REVISION_CONFLICT', 'current_revision', m.revision,
          'memory', jsonb_build_object('id', m.id, 'category', m.category, 'content', m.content, 'revision', m.revision));
      END IF;
      IF (v_kind = 'memory_stop_using') = (m.disabled_at IS NOT NULL) THEN
        v_resp := jsonb_build_object('no_op', true, 'memory_id', m.id);
      ELSE
        UPDATE public.companion_memory SET disabled_at = CASE WHEN v_kind = 'memory_stop_using' THEN now() END WHERE id = m.id;
        v_resp := jsonb_build_object('memory_id', m.id);
      END IF;

    ELSIF v_kind = 'memory_forget' THEN
      IF v_id IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'memory_id or fragment_id required'); END IF;
      SELECT * INTO m FROM public.companion_memory WHERE id = v_id AND user_id = v_user FOR UPDATE;
      IF FOUND THEN
        -- Hard removal; the guard trigger performs suppression, closure and privacy bump.
        DELETE FROM public.companion_memory WHERE id = m.id;
        SELECT count(*) INTO v_closure FROM public.support_suppressions WHERE user_id = v_user AND kind = 'message' AND operation_id = v_op;
        v_resp := jsonb_build_object('memory_id', m.id, 'suppressed_turns', v_closure);
      ELSE
        SELECT * INTO f FROM public.memory_fragments WHERE id = v_id AND user_id = v_user FOR UPDATE;
        IF NOT FOUND THEN PERFORM public.support_raise('NOT_FOUND', 'memory not found'); END IF;
        -- A promoted fragment's canonical memory is forgotten by the same transaction.
        DELETE FROM public.memory_fragments WHERE id = f.id;
        SELECT count(*) INTO v_closure FROM public.support_suppressions WHERE user_id = v_user AND kind = 'message' AND operation_id = v_op;
        v_resp := jsonb_build_object('fragment_id', f.id, 'memory_id', f.promoted_memory_id, 'suppressed_turns', v_closure,
          'conversation_scope_excluded', f.source_message_id IS NULL AND f.source_conversation_id IS NOT NULL);
      END IF;

    ELSIF v_kind = 'candidate_approve' THEN
      IF v_id IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'fragment_id required'); END IF;
      v_content := btrim(public.support_opt_text(v_payload, 'content', 500));
      SELECT * INTO f FROM public.memory_fragments WHERE id = v_id AND user_id = v_user FOR UPDATE;
      IF NOT FOUND THEN PERFORM public.support_raise('NOT_FOUND', 'candidate not found'); END IF;
      IF f.review_state = 'promoted' THEN
        v_resp := jsonb_build_object('no_op', true, 'fragment_id', f.id, 'memory_id', f.promoted_memory_id);
      ELSE
        IF f.review_state NOT IN ('pending', 'legacy_review')
           OR (f.review_state = 'pending' AND f.candidate_expires_at IS NOT NULL AND f.candidate_expires_at <= now())
           OR EXISTS (SELECT 1 FROM public.support_suppressions s WHERE s.user_id = v_user AND (
                (s.kind = 'fragment' AND s.ref_id = f.id)
             OR (s.kind = 'message' AND s.ref_id = f.source_message_id)
             OR (s.kind = 'conversation' AND s.ref_id = public.support_origin_conversation(f.source_conversation_id, f.source_message_id)))) THEN
          PERFORM public.support_raise('CONTENT_UNAVAILABLE', 'candidate is expired, dismissed or suppressed');
        END IF;
        v_content := coalesce(nullif(v_content, ''), btrim(f.value));
        IF v_content IS NULL OR v_content = '' THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'candidate has no content'); END IF;
        v_cat := CASE WHEN f.fragment_type = 'preference' THEN 'preferences' ELSE 'life_context' END;
        PERFORM set_config('support.memory_rpc', 'on', true);
        BEGIN
          INSERT INTO public.companion_memory (user_id, category, content, origin, confirmed_at,
            source_message_id, source_conversation_id, approved_from_fragment_id)
          VALUES (v_user, v_cat, v_content, 'approved_candidate', now(), f.source_message_id, f.source_conversation_id, f.id)
          RETURNING id INTO v_new_id;
        EXCEPTION WHEN raise_exception THEN
          IF SQLERRM LIKE 'Memory limit reached%' THEN
            PERFORM public.support_raise('MEMORY_LIMIT_REACHED', 'the 20 confirmed memory limit is reached');
          END IF;
          RAISE;
        END;
        UPDATE public.memory_fragments SET review_state = 'promoted', approved_at = now(), promoted_memory_id = v_new_id,
          value = '', updated_at = now() WHERE id = f.id;   -- one canonical copy only
        PERFORM set_config('support.memory_rpc', 'off', true);
        PERFORM public.support_memory_event(v_user, 'companion_memory', v_new_id, 'approved', 1, NULL, v_op);
        v_resp := jsonb_build_object('fragment_id', f.id, 'memory_id', v_new_id);
      END IF;

    ELSIF v_kind = 'candidate_dismiss' THEN
      IF v_id IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'fragment_id required'); END IF;
      SELECT * INTO f FROM public.memory_fragments WHERE id = v_id AND user_id = v_user FOR UPDATE;
      IF NOT FOUND THEN PERFORM public.support_raise('NOT_FOUND', 'candidate not found'); END IF;
      IF f.review_state = 'promoted' THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'already saved; use Forget'); END IF;
      IF f.review_state = 'dismissed' THEN
        v_resp := jsonb_build_object('no_op', true, 'fragment_id', f.id);
      ELSE
        PERFORM set_config('support.memory_rpc', 'on', true);
        UPDATE public.memory_fragments SET review_state = 'dismissed', value = '', updated_at = now() WHERE id = f.id;
        PERFORM set_config('support.memory_rpc', 'off', true);
        PERFORM public.support_memory_event(v_user, 'memory_fragment', f.id, 'dismissed', NULL, NULL, v_op);
        v_resp := jsonb_build_object('fragment_id', f.id);
      END IF;

    ELSIF v_kind IN ('suppress_source', 'unsuppress_source') THEN
      v_ckind := public.support_opt_text(v_payload, 'source_kind', 16);
      IF v_id IS NULL OR v_ckind IS NULL OR v_ckind NOT IN ('conversation', 'message') THEN
        PERFORM public.support_raise('INVALID_PAYLOAD', 'source_kind (conversation|message) and id required');
      END IF;
      IF v_ckind = 'conversation' AND NOT EXISTS (SELECT 1 FROM public.conversations WHERE id = v_id AND user_id = v_user) THEN
        PERFORM public.support_raise('NOT_FOUND', 'conversation not found');
      END IF;
      IF v_ckind = 'message' AND NOT EXISTS (SELECT 1 FROM public.messages ms JOIN public.conversations c ON c.id = ms.conversation_id
                                              WHERE ms.id = v_id AND c.user_id = v_user) THEN
        PERFORM public.support_raise('NOT_FOUND', 'message not found');
      END IF;
      IF v_kind = 'suppress_source' THEN
        INSERT INTO public.support_suppressions (user_id, kind, ref_id, reason, operation_id)
          VALUES (v_user, v_ckind, v_id, 'user_source_exclusion', v_op) ON CONFLICT (user_id, kind, ref_id) DO NOTHING;
        v_closure := public.support_suppress_closure(v_user, v_op);
        PERFORM public.support_bump_privacy(v_user);
        v_resp := jsonb_build_object('source_kind', v_ckind, 'id', v_id, 'suppressed_turns', v_closure);
      ELSE
        -- Only a deliberate user exclusion can be lifted; forgotten/derived entries stay.
        DELETE FROM public.support_suppressions WHERE user_id = v_user AND kind = v_ckind AND ref_id = v_id AND reason = 'user_source_exclusion';
        v_resp := jsonb_build_object('source_kind', v_ckind, 'id', v_id);
      END IF;
    END IF;

    v_resp := jsonb_build_object('ok', true, 'operation_id', v_op, 'kind', v_kind) || v_resp
      || jsonb_build_object('privacy_revision', (SELECT privacy_revision FROM public.support_privacy_state WHERE user_id = v_user));
    INSERT INTO public.support_privacy_operations (user_id, operation_id, kind, payload_hash, resulting_revision, response)
      VALUES (v_user, v_op, v_kind, v_hash, (v_resp ->> 'privacy_revision')::bigint, v_resp);
    RETURN v_resp || jsonb_build_object('replayed', false, 'server_time', now());
  EXCEPTION WHEN SQLSTATE 'SS001' THEN
    GET STACKED DIAGNOSTICS v_code = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL;
    RETURN jsonb_build_object('ok', false, 'code', v_code, 'message', nullif(v_detail, ''));
  END;
END;
$$;

-- ---------------------------------------------------------------------------
-- Memory page read
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_list_memory() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_user uuid := auth.uid();
  v_saved jsonb; v_cands jsonb; v_intent jsonb; v_priv bigint;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501'; END IF;
  SELECT coalesce(p.privacy_revision, 1) INTO v_priv FROM (SELECT 1) x
    LEFT JOIN public.support_privacy_state p ON p.user_id = v_user;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', m.id, 'category', m.category, 'content', m.content, 'origin', m.origin, 'revision', m.revision,
      'state', CASE
        WHEN EXISTS (SELECT 1 FROM public.support_suppressions s WHERE s.user_id = v_user AND s.kind = 'memory' AND s.ref_id = m.id) THEN 'excluded'
        WHEN m.disabled_at IS NOT NULL THEN 'disabled'
        WHEN m.expires_at IS NOT NULL AND m.expires_at <= now() THEN 'expired'
        WHEN m.category = 'life_context'
             AND coalesce(m.review_due_at, coalesce(m.confirmed_at, m.created_at) + interval '90 days') <= now() THEN 'stale'
        ELSE 'confirmed' END,
      'confirmed_at', coalesce(m.confirmed_at, m.created_at), 'review_due_at', m.review_due_at,
      'expires_at', m.expires_at, 'disabled_at', m.disabled_at, 'last_used_at', m.last_used_at,
      'source_message_id', m.source_message_id) ORDER BY m.created_at, m.id), '[]'::jsonb)
    INTO v_saved FROM public.companion_memory m WHERE m.user_id = v_user AND m.deleted_at IS NULL;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', f.id, 'fragment_type', f.fragment_type, 'value', f.value, 'review_state', f.review_state,
      'provenance', CASE WHEN f.source_message_id IS NOT NULL THEN 'message'
                         WHEN f.source_conversation_id IS NOT NULL THEN 'conversation' ELSE 'unknown' END,
      'source_message_id', f.source_message_id, 'source_conversation_id', f.source_conversation_id,
      'candidate_expires_at', f.candidate_expires_at, 'extracted_at', f.extracted_at) ORDER BY f.extracted_at, f.id), '[]'::jsonb)
    INTO v_cands FROM public.memory_fragments f
    WHERE f.user_id = v_user AND f.value <> ''
      AND (f.review_state = 'legacy_review' OR (f.review_state = 'pending' AND coalesce(f.candidate_expires_at, f.created_at + interval '7 days') > now()))
      AND NOT EXISTS (SELECT 1 FROM public.support_suppressions s WHERE s.user_id = v_user AND (
            (s.kind = 'fragment' AND s.ref_id = f.id) OR (s.kind = 'message' AND s.ref_id = f.source_message_id)
         OR (s.kind = 'conversation' AND s.ref_id = public.support_origin_conversation(f.source_conversation_id, f.source_message_id))));
  SELECT jsonb_build_object('id', d.id, 'intent', d.intent, 'created_at', d.created_at, 'expires_at', d.expires_at)
    INTO v_intent FROM public.daily_intents d
    WHERE d.user_id = v_user AND d.expires_at > now() ORDER BY d.created_at DESC LIMIT 1;
  RETURN jsonb_build_object('ok', true, 'privacy_revision', v_priv, 'max_confirmed', 20,
    'saved', v_saved, 'candidates', v_cands, 'daily_intent', v_intent, 'server_time', now());
END;
$$;

CREATE FUNCTION public.support_expire_candidates() RETURNS integer
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE v integer;
BEGIN
  PERFORM set_config('support.memory_rpc', 'on', true);
  WITH x AS (
    UPDATE public.memory_fragments SET review_state = 'expired', value = '', updated_at = now()
     WHERE review_state = 'pending' AND coalesce(candidate_expires_at, created_at + interval '7 days') <= now()
     RETURNING 1)
  SELECT count(*) INTO v FROM x;
  PERFORM set_config('support.memory_rpc', 'off', true);
  RETURN v;
END;
$$;

-- ---------------------------------------------------------------------------
-- Canonical chat-turn confirmation (service role only).
-- Requires the EXISTING chat_requests claim (owner, conversation, content hash) and
-- stores a non-null terminal response/status in the same transaction as the message,
-- receipt, sources and optional proposal. Every cited, revision-bound source is
-- re-validated under a share lock, so a concurrent correction, discard, scope change or
-- suppression prevents confirmation of stale output.
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_confirm_chat_turn(p_args jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_user uuid := public.support_try_uuid(p_args ->> 'user_id');
  v_req uuid := public.support_try_uuid(p_args ->> 'request_id');
  v_conv uuid := public.support_try_uuid(p_args ->> 'conversation_id');
  v_sid uuid := public.support_try_uuid(p_args ->> 'support_session_id');
  v_hash text := p_args ->> 'content_hash';
  v_status integer; v_response jsonb := p_args -> 'response';
  v_expected bigint; v_cur bigint; v_scope text := p_args ->> 'scope';
  v_origin text := coalesce(p_args ->> 'content_origin', 'model');
  v_content text := p_args ->> 'assistant_content';
  v_claim public.chat_requests%ROWTYPE;
  v_existing public.support_context_receipts%ROWTYPE;
  v_prop public.support_proposals%ROWTYPE;
  v_session public.support_work_sessions%ROWTYPE;
  v_msg uuid; v_receipt uuid; v_pid uuid; v_src jsonb; v_pr jsonb := p_args -> 'proposal';
  v_reason text; v_bkind text; v_bref uuid; v_tmpl text; v_drop text;
  v_sk text; v_sid2 uuid; v_rev bigint; v_rows integer;
  m public.companion_memory%ROWTYPE; act public.support_activities%ROWTYPE; ss public.support_work_sessions%ROWTYPE;
  v_safety constant uuid := '00000000-0000-0000-0000-000000000001';
BEGIN
  -- Access control is the grant list below (service_role only).
  BEGIN
    IF v_user IS NULL OR v_req IS NULL OR v_conv IS NULL OR v_content IS NULL OR btrim(v_content) = ''
       OR v_scope IS NULL OR v_scope NOT IN ('conversation_only', 'personalized')
       OR v_origin NOT IN ('model', 'interface_fallback', 'safety_response')
       OR coalesce(p_args ->> 'privacy_revision', '') !~ '^[0-9]{1,15}$'
       OR coalesce(p_args ->> 'provider_vendor', '') = '' OR coalesce(p_args ->> 'provider_model', '') = ''
       OR coalesce(p_args ->> 'route_version', '') = ''
       OR coalesce(v_hash, '') = ''
       OR v_response IS NULL OR jsonb_typeof(v_response) <> 'object'
       OR coalesce(p_args ->> 'response_status', '') !~ '^2[0-9]{2}$' THEN
      PERFORM public.support_raise('INVALID_PAYLOAD', 'missing or invalid confirmation fields (content_hash, response, response_status are required)');
    END IF;
    v_expected := (p_args ->> 'privacy_revision')::bigint;
    v_status := (p_args ->> 'response_status')::integer;
    PERFORM pg_advisory_xact_lock(hashtextextended(v_user::text || ':chat:' || v_req::text, 0));

    -- The canonical claim is mandatory and immutable in identity.
    SELECT * INTO v_claim FROM public.chat_requests WHERE user_id = v_user AND request_id = v_req FOR UPDATE;
    IF NOT FOUND THEN PERFORM public.support_raise('NOT_FOUND', 'no request claim for this request id'); END IF;
    IF v_claim.conversation_id <> v_conv OR v_claim.content_hash <> v_hash THEN
      RETURN jsonb_build_object('ok', false, 'code', 'OPERATION_ID_REUSED', 'message', 'request identity differs from the claimed request');
    END IF;

    SELECT * INTO v_existing FROM public.support_context_receipts WHERE user_id = v_user AND request_id = v_req;
    IF FOUND THEN
      SELECT * INTO v_prop FROM public.support_proposals WHERE user_id = v_user AND request_id = v_req;
      RETURN jsonb_build_object('ok', true, 'replayed', true, 'message_id', v_existing.assistant_message_id,
        'receipt_id', v_existing.id, 'proposal_id', v_prop.id, 'response', v_claim.response, 'response_status', v_claim.response_status);
    END IF;
    IF v_claim.response IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false, 'code', 'OPERATION_ID_REUSED', 'message', 'request already finalized without a context receipt');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.conversations WHERE id = v_conv AND user_id = v_user) THEN
      PERFORM public.support_raise('NOT_FOUND', 'conversation not found');
    END IF;
    IF v_sid IS NOT NULL THEN
      SELECT * INTO v_session FROM public.support_work_sessions WHERE id = v_sid AND user_id = v_user AND status = 'open' FOR SHARE;
      IF NOT FOUND OR (v_session.conversation_id IS NOT NULL AND v_session.conversation_id <> v_conv) THEN
        PERFORM public.support_raise('NOT_FOUND', 'session not found for this conversation');
      END IF;
    END IF;

    PERFORM public.support_ensure_privacy_state(v_user);
    SELECT privacy_revision INTO v_cur FROM public.support_privacy_state WHERE user_id = v_user FOR SHARE;
    IF v_cur <> v_expected THEN
      RETURN jsonb_build_object('ok', false, 'code', 'PRIVACY_REVISION_STALE', 'current_privacy_revision', v_cur);
    END IF;

    -- Verify every cited source is owned, eligible AND still at the revision assembled.
    FOR v_src IN SELECT * FROM jsonb_array_elements(coalesce(p_args -> 'sources', '[]'::jsonb)) LOOP
      v_sk := v_src ->> 'kind'; v_sid2 := public.support_try_uuid(v_src ->> 'id');
      IF v_sid2 IS NULL OR v_sk IS NULL THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'source needs kind and id'); END IF;
      IF v_sk IN ('companion_memory', 'session', 'activity_result') THEN
        IF coalesce((v_src ->> 'revision') !~ '^[0-9]{1,15}$', true) THEN
          PERFORM public.support_raise('INVALID_PAYLOAD', 'source ' || v_sk || ' needs a revision');
        END IF;
        v_rev := (v_src ->> 'revision')::bigint;
      END IF;
      IF v_sk = 'companion_memory' THEN
        IF v_scope <> 'personalized' THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'saved memory is not allowed in conversation-only scope'); END IF;
        SELECT * INTO m FROM public.companion_memory WHERE id = v_sid2 AND user_id = v_user FOR SHARE;
        IF NOT FOUND THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'memory not found'); END IF;
        IF m.deleted_at IS NOT NULL OR m.disabled_at IS NOT NULL OR m.revision <> v_rev
           OR EXISTS (SELECT 1 FROM public.support_suppressions s WHERE s.user_id = v_user AND (
                (s.kind = 'memory' AND s.ref_id = m.id)
             OR (s.kind = 'message' AND s.ref_id = m.source_message_id)
             OR (s.kind = 'conversation' AND s.ref_id = public.support_origin_conversation(m.source_conversation_id, m.source_message_id)))) THEN
          PERFORM public.support_raise('PRIVACY_REVISION_STALE', 'source_changed:companion_memory');
        END IF;
      ELSIF v_sk = 'message' THEN
        IF NOT EXISTS (SELECT 1 FROM public.messages ms JOIN public.conversations c ON c.id = ms.conversation_id
                       WHERE ms.id = v_sid2 AND c.user_id = v_user) THEN
          PERFORM public.support_raise('INVALID_PAYLOAD', 'message not found');
        END IF;
        IF EXISTS (SELECT 1 FROM public.support_suppressions s WHERE s.user_id = v_user AND (
              (s.kind = 'message' AND s.ref_id = v_sid2)
           OR (s.kind = 'conversation' AND s.ref_id = (SELECT conversation_id FROM public.messages WHERE id = v_sid2)))) THEN
          PERFORM public.support_raise('PRIVACY_REVISION_STALE', 'source_changed:message');
        END IF;
      ELSIF v_sk = 'daily_intent' THEN
        IF v_scope <> 'personalized' THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'daily intent is not allowed in conversation-only scope'); END IF;
        IF NOT EXISTS (SELECT 1 FROM public.daily_intents d WHERE d.id = v_sid2 AND d.user_id = v_user AND d.expires_at > now()) THEN
          PERFORM public.support_raise('PRIVACY_REVISION_STALE', 'source_changed:daily_intent');
        END IF;
      ELSIF v_sk = 'session' THEN
        SELECT * INTO ss FROM public.support_work_sessions WHERE id = v_sid2 AND user_id = v_user FOR SHARE;
        IF NOT FOUND THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'session not found'); END IF;
        IF ss.status <> 'open' OR ss.context_revision <> v_rev THEN PERFORM public.support_raise('PRIVACY_REVISION_STALE', 'source_changed:session'); END IF;
      ELSIF v_sk = 'activity_result' THEN
        SELECT * INTO act FROM public.support_activities WHERE id = v_sid2 AND user_id = v_user FOR SHARE;
        IF NOT FOUND THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'activity not found'); END IF;
        IF act.context_revision <> v_rev OR EXISTS (SELECT 1 FROM public.support_suppressions s
             WHERE s.user_id = v_user AND s.kind = 'activity' AND s.ref_id = act.id) THEN
          PERFORM public.support_raise('PRIVACY_REVISION_STALE', 'source_changed:activity_result');
        END IF;
      ELSIF v_sk = 'safety_policy' THEN
        IF v_sid2 <> v_safety THEN PERFORM public.support_raise('INVALID_PAYLOAD', 'unknown safety policy source'); END IF;
      ELSE
        PERFORM public.support_raise('INVALID_PAYLOAD', 'unknown source kind');
      END IF;
    END LOOP;

    INSERT INTO public.messages (conversation_id, role, content, support_session_id, content_origin)
      VALUES (v_conv, 'assistant', v_content, v_sid, v_origin) RETURNING id INTO v_msg;
    UPDATE public.conversations SET updated_at = now() WHERE id = v_conv AND user_id = v_user;
    INSERT INTO public.support_context_receipts (user_id, request_id, support_session_id, conversation_id, assistant_message_id,
      privacy_revision, scope, provider_vendor, provider_model, route_version, exclusions)
    VALUES (v_user, v_req, v_sid, v_conv, v_msg, v_cur, v_scope, p_args ->> 'provider_vendor', p_args ->> 'provider_model',
      p_args ->> 'route_version',
      coalesce(ARRAY(SELECT jsonb_array_elements_text(coalesce(p_args -> 'exclusions', '[]'::jsonb))), '{}'))
    RETURNING id INTO v_receipt;
    INSERT INTO public.support_context_receipt_sources (receipt_id, user_id, source_kind, source_id, source_revision, source_date)
      SELECT v_receipt, v_user, e ->> 'kind', public.support_try_uuid(e ->> 'id'),
             coalesce((e ->> 'revision')::bigint, 0), public.support_try_ts(e ->> 'date')
      FROM jsonb_array_elements(coalesce(p_args -> 'sources', '[]'::jsonb)) e
      ON CONFLICT DO NOTHING;

    -- Optional proposal: validated again here; an invalid one is dropped, text is kept.
    IF v_pr IS NOT NULL AND jsonb_typeof(v_pr) = 'object' AND v_sid IS NOT NULL AND v_origin <> 'safety_response' THEN
      v_tmpl := v_pr ->> 'template_key'; v_reason := v_pr ->> 'reason_code';
      v_bkind := v_pr ->> 'basis_kind'; v_bref := public.support_try_uuid(v_pr ->> 'basis_ref');
      v_drop := NULL;
      IF NOT EXISTS (SELECT 1 FROM public.support_template_catalog WHERE template_key = v_tmpl AND enabled) THEN
        v_drop := 'unknown template';
      ELSIF v_tmpl = ANY (v_session.suppressed_templates) THEN
        v_drop := 'template declined this session';
      ELSIF v_reason IS NULL OR v_reason NOT IN ('current_request', 'approved_preference', 'selected_intent', 'general_option') THEN
        v_drop := 'bad reason';
      ELSIF (v_pr ->> 'suggested_step') IS NOT NULL AND (v_tmpl <> 'choose_step_v1' OR char_length(v_pr ->> 'suggested_step') > 400) THEN
        v_drop := 'bad step';
      END IF;
      IF v_drop IS NULL AND (v_bref IS NOT NULL OR v_reason = 'approved_preference') THEN
        IF v_bref IS NULL OR v_bkind IS NULL OR NOT EXISTS (
            SELECT 1 FROM public.support_context_receipt_sources
            WHERE receipt_id = v_receipt AND source_id = v_bref
              AND source_kind = CASE v_bkind WHEN 'companion_memory' THEN 'companion_memory' WHEN 'message' THEN 'message'
                                              WHEN 'activity' THEN 'activity_result' END) THEN
          v_reason := 'general_option'; v_bkind := NULL; v_bref := NULL;
        END IF;
      END IF;
      IF v_drop IS NULL THEN
        INSERT INTO public.support_proposals (user_id, support_session_id, request_id, message_id, template_key, reason_code,
          basis_kind, basis_ref, suggested_step, privacy_revision, expires_at)
        VALUES (v_user, v_sid, v_req, v_msg, v_tmpl, v_reason, v_bkind, v_bref, v_pr ->> 'suggested_step', v_cur, now() + interval '24 hours')
        RETURNING id INTO v_pid;
      END IF;
    END IF;

    -- The server-generated identifiers are stored with the response in this transaction.
    -- (Rendering the final client response from them remains the chat integration's job.)
    v_response := v_response || jsonb_build_object('support_confirmed', jsonb_build_object(
      'message_id', v_msg, 'receipt_id', v_receipt, 'proposal_id', v_pid));
    UPDATE public.chat_requests SET support_session_id = v_sid, response = v_response, response_status = v_status
      WHERE user_id = v_user AND request_id = v_req AND response IS NULL;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN PERFORM public.support_raise('TEMPORARY_FAILURE', 'terminal request receipt was not saved'); END IF;
    RETURN jsonb_build_object('ok', true, 'replayed', false, 'message_id', v_msg, 'receipt_id', v_receipt,
      'proposal_id', v_pid, 'proposal_dropped', v_drop, 'privacy_revision', v_cur,
      'response', v_response, 'response_status', v_status);
  EXCEPTION WHEN SQLSTATE 'SS001' THEN
    GET STACKED DIAGNOSTICS v_sk = MESSAGE_TEXT, v_drop = PG_EXCEPTION_DETAIL;
    RETURN jsonb_build_object('ok', false, 'code', v_sk, 'message', nullif(v_drop, ''));
  END;
END;
$$;

-- Receipt as displayed: references resolved through CURRENT ownership/deletion rules.
CREATE FUNCTION public.support_get_context_receipt(p_request_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_user uuid := auth.uid();
  r public.support_context_receipts%ROWTYPE;
  v_sources jsonb;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE = '42501'; END IF;
  SELECT * INTO r FROM public.support_context_receipts WHERE user_id = v_user AND request_id = p_request_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'code', 'NOT_FOUND'); END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'kind', s.source_kind, 'id', s.source_id, 'revision_at_send', s.source_revision, 'date', s.source_date,
      'state', CASE
        WHEN s.source_kind = 'companion_memory' THEN
          CASE WHEN EXISTS (SELECT 1 FROM public.companion_memory m WHERE m.id = s.source_id AND m.user_id = v_user AND m.deleted_at IS NULL)
                    AND NOT EXISTS (SELECT 1 FROM public.support_suppressions x WHERE x.user_id = v_user AND x.kind = 'memory' AND x.ref_id = s.source_id)
               THEN 'available' ELSE 'removed' END
        WHEN s.source_kind = 'message' THEN
          CASE WHEN EXISTS (SELECT 1 FROM public.messages ms WHERE ms.id = s.source_id)
                    AND NOT EXISTS (SELECT 1 FROM public.support_suppressions x WHERE x.user_id = v_user AND x.kind = 'message' AND x.ref_id = s.source_id)
               THEN 'available' ELSE 'removed' END
        WHEN s.source_kind = 'activity_result' THEN
          CASE WHEN EXISTS (SELECT 1 FROM public.support_activities a WHERE a.id = s.source_id AND a.user_id = v_user)
                    AND NOT EXISTS (SELECT 1 FROM public.support_suppressions x WHERE x.user_id = v_user AND x.kind = 'activity' AND x.ref_id = s.source_id)
               THEN 'available' ELSE 'removed' END
        ELSE 'available' END,
      'label', CASE WHEN s.source_kind = 'companion_memory' THEN
                 (SELECT m.category FROM public.companion_memory m WHERE m.id = s.source_id AND m.user_id = v_user AND m.deleted_at IS NULL) END
    ) ORDER BY s.source_kind, s.source_id), '[]'::jsonb)
    INTO v_sources FROM public.support_context_receipt_sources s WHERE s.receipt_id = r.id AND s.user_id = v_user;
  RETURN jsonb_build_object('ok', true, 'receipt', jsonb_build_object(
    'schema_version', r.schema_version, 'receipt_id', r.id, 'request_id', r.request_id,
    'support_session_id', r.support_session_id, 'conversation_id', r.conversation_id,
    'assistant_message_id', r.assistant_message_id, 'privacy_revision', r.privacy_revision, 'scope', r.scope,
    'provider', jsonb_build_object('vendor', r.provider_vendor, 'model', r.provider_model, 'route_version', r.route_version),
    'sources', v_sources, 'exclusions', to_jsonb(r.exclusions), 'created_at', r.created_at));
END;
$$;

-- Eligible-context snapshot for the server ContextPolicy. Service role only. Scope-aware:
-- with p_include_personal = false NO memory or daily-intent row is read at all.
CREATE FUNCTION public.support_context_sources(
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
    SELECT coalesce(jsonb_agg(jsonb_build_object('id', h.id, 'role', h.role, 'content', h.content, 'created_at', h.created_at)
        ORDER BY h.created_at, h.id), '[]'::jsonb)
      INTO v_hist FROM (
        SELECT ms.id, ms.role, ms.content, ms.created_at FROM public.messages ms
        WHERE ms.conversation_id = p_conversation
          AND ms.role IN ('user', 'assistant')
          AND coalesce(ms.content_origin, 'model') = 'model'
          AND NOT EXISTS (SELECT 1 FROM public.support_suppressions s WHERE s.user_id = p_user AND s.kind = 'message' AND s.ref_id = ms.id)
        ORDER BY ms.created_at DESC, ms.id DESC LIMIT least(greatest(p_history_limit, 1), 40)) h;
  END IF;
  RETURN jsonb_build_object('ok', true, 'privacy_revision', v_priv, 'memories', v_mem, 'daily_intent', v_intent,
    'history', v_hist, 'conversation_suppressed', v_conv_suppressed);
END;
$$;

-- Capability negotiation (distinguish "not deployed" from a temporary error)
CREATE FUNCTION public.support_capabilities() RETURNS jsonb
LANGUAGE sql STABLE SET search_path = pg_catalog, public, pg_temp AS $$
  SELECT jsonb_build_object(
    'session_contract', 1,
    'context_policy', 1,
    'voice_context', 0,
    'privacy_revision', true,
    'memory_lifecycle', true,
    'chat_confirmation', true,
    'lazy_attach', true,
    'schema', '20261106230200');
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION
  public.support_bump_privacy(uuid), public.support_invalidate_memory_proposals(uuid, uuid),
  public.support_memory_event(uuid, text, uuid, text, integer, bigint, uuid),
  public.support_forget_memory_effects(uuid, public.companion_memory, uuid),
  public.support_forget_fragment_effects(uuid, public.memory_fragments, uuid),
  public.support_memory_edit_effects(uuid, uuid, integer, integer, uuid),
  public.support_companion_memory_guard(), public.support_memory_fragment_guard()
FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.support_memory_mutate(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.support_list_memory() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.support_get_context_receipt(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.support_capabilities() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.support_memory_mutate(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.support_list_memory() TO authenticated;
GRANT EXECUTE ON FUNCTION public.support_get_context_receipt(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.support_capabilities() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.support_confirm_chat_turn(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.support_context_sources(uuid, uuid, integer, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.support_expire_candidates() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.support_confirm_chat_turn(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.support_context_sources(uuid, uuid, integer, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.support_expire_candidates() TO service_role;

COMMIT;
