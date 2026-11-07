-- Forward correction: real account removal (DELETE FROM auth.users) with the support-session
-- memory guards installed. NOT EXECUTED by its author.
--
-- ACTUAL FAILURE (reproduced by the transcript fresh qualification, T11): deleting an auth user
-- cascades (FK ON DELETE CASCADE) into public.companion_memory / public.memory_fragments. Their
-- row guards (20261106230200) treat every DELETE as a user "Forget" and call
-- support_forget_memory_effects / support_forget_fragment_effects, which INSERT into
-- support_suppressions (FK -> auth.users) and bump/ensure support_privacy_state (FK -> auth.users).
-- During the cascade the parent auth.users row is already deleted, so the INSERT violates
-- support_suppressions_user_id_fkey and the whole account deletion rolls back. The earlier cascade
-- fixture only covered a daily intent, whose guard already checks owner existence
-- (support_bump_if_owner), and never an ACTIVE curated memory.
--
-- FIX 1 (narrow): in BOTH guards' DELETE branch, return OLD immediately when the owner no longer
-- exists in auth.users. That state is only reachable inside the FK cascade of a real account
-- deletion (the FK forbids such a row otherwise), where every owner-keyed support row is removed by
-- its own cascade; creating suppression / privacy / tombstone rows for a vanished owner would only
-- fail or resurrect owner data. While the owner EXISTS, every statement below this branch is
-- byte-identical to the baseline, so ordinary Forget, legacy DELETE, soft delete, edits, revisions,
-- suppression closure and privacy bumps are unchanged. No trigger is disabled and no error is
-- swallowed.
--
-- Other cascade paths were reviewed in the current root source and need no change:
--   * messages: reached through conversations(user_id) cascade; messages' triggers are the revision/
--     transcript guards (INSERT/UPDATE only) and the statement mutex (re-entrant); no owner rows are written.
--   * daily_intents: support_daily_intent_guard -> support_bump_if_owner already skips absent owners.
--   * support_work_sessions / activities / events / proposals / receipts / privacy rows /
--     voice bindings / mutation receipts: plain cascades, no DELETE row triggers.
--   * support_suppress_closure / support_ensure_privacy_state are reachable on DELETE only through the
--     two guards above (now bypassed for an absent owner) and through RPCs that authenticate an existing owner.
--
-- FIX 2 (lock order, one trigger): every M3 writer enters the private write mutex FIRST and then touches
-- rows with FKs to auth.users (support_privacy_state, support_suppressions, support_work_sessions, ...):
-- an INSERT takes FOR KEY SHARE on the auth.users row. A DELETE FROM auth.users locks that row exclusively
-- and THEN, in its cascade, runs child DELETE statements whose BEFORE STATEMENT triggers wait for the
-- mutex (aaa_support_write_mutex_* on companion_memory, memory_fragments, daily_intents, messages,
-- conversations). Writer holds mutex -> needs auth key-share; deleter holds auth row -> needs mutex:
-- a cycle. A BEFORE DELETE FOR EACH STATEMENT trigger on auth.users using M3's own
-- support_write_mutex_statement() enters the mutex before ANY auth row is locked. No INSERT/UPDATE/
-- sign-in path is touched. PRODUCTION ROLLOUT MUST SEPARATELY INSPECT that the migration role may
-- create a trigger on auth.users and that no auth-owned DELETE trigger ordering depends on it.
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $$
BEGIN
  IF to_regprocedure('public.support_companion_memory_guard()') IS NULL
     OR to_regprocedure('public.support_memory_fragment_guard()') IS NULL
     OR to_regprocedure('public.support_write_mutex_statement()') IS NULL
     OR to_regprocedure('public.support_forget_memory_effects(uuid,public.companion_memory,uuid)') IS NULL
     OR to_regprocedure('public.support_forget_fragment_effects(uuid,public.memory_fragments,uuid)') IS NULL THEN
    RAISE EXCEPTION 'M3 memory guards are missing; apply the support-session migrations first';
  END IF;
  -- Replace only the reviewed baseline bodies (md5 of pg_proc.prosrc, taken from
  -- 20261106230200_support_memory_context.sql).
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.support_companion_memory_guard()'::regprocedure)
       IS DISTINCT FROM '06aa06d70e89fdf6d9feea47a573188f'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.support_memory_fragment_guard()'::regprocedure)
       IS DISTINCT FROM 'cb650fbbb3642a7de208d436ae7e8115' THEN
    RAISE EXCEPTION 'support memory guard bodies differ from the reviewed baseline; refusing to replace';
  END IF;
END $$;

-- companion_memory guard: baseline body + the owner-absent DELETE branch.
CREATE OR REPLACE FUNCTION public.support_companion_memory_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_rpc boolean := coalesce(current_setting('support.memory_rpc', true), '') = 'on';
  v_op uuid := public.support_try_uuid(current_setting('support.op_id', true));
  v_priv bigint;
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- Account removal (FK cascade from auth.users): the owner is already gone, so there is
    -- nobody to suppress for and no owner-keyed row may be created.
    IF NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = OLD.user_id) THEN
      RETURN OLD;
    END IF;
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
    v_priv := public.support_bump_privacy(OLD.user_id);   -- privacy lock first
    IF NEW.disabled_at IS NOT NULL THEN
      NEW.disabled_at := coalesce(NEW.disabled_at, now());
      PERFORM public.support_invalidate_memory_proposals(OLD.user_id, OLD.id);
    END IF;
    PERFORM public.support_memory_event(OLD.user_id, 'companion_memory', OLD.id,
      CASE WHEN NEW.disabled_at IS NOT NULL THEN 'disabled' ELSE 'enabled' END, NEW.revision, v_priv, v_op);
  END IF;
  RETURN NEW;
END;
$$;

-- memory_fragments guard: baseline body + the same owner-absent DELETE branch.
CREATE OR REPLACE FUNCTION public.support_memory_fragment_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp AS $$
DECLARE
  v_rpc boolean := coalesce(current_setting('support.memory_rpc', true), '') = 'on';
  v_op uuid := public.support_try_uuid(current_setting('support.op_id', true));
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- Account removal (FK cascade from auth.users): see the companion_memory guard.
    IF NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = OLD.user_id) THEN
      RETURN OLD;
    END IF;
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
  -- A promoted fragment is PROVENANCE, never a second copy of the fact. Promoted,
  -- dismissed, expired and suppressed fragments keep an EMPTY value under every writer,
  -- so a legacy edit that completes after Forget (or an old promotion marker) cannot
  -- restore content.
  IF NEW.promoted_memory_id IS NOT NULL OR NEW.review_state IN ('promoted', 'dismissed', 'expired') THEN
    NEW.value := '';
  ELSIF public.support_fragment_suppressed(NEW.user_id, NEW.id, NEW.source_message_id, NEW.source_conversation_id) THEN
    NEW.value := '';
    IF NOT v_rpc THEN NEW.review_state := 'dismissed'; END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- Account deletion enters the private write mutex before ANY auth.users row lock (see FIX 2).
-- Created only when no equivalent enabled BEFORE DELETE statement trigger already calls
-- support_write_mutex_statement() on auth.users; failure to create it is NOT swallowed.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid = 'auth.users'::regclass AND NOT t.tgisinternal
      AND t.tgfoid = 'public.support_write_mutex_statement()'::regprocedure
      AND (t.tgtype & 1) = 0 AND (t.tgtype & 2) = 2 AND (t.tgtype & 8) = 8 AND t.tgenabled <> 'D') THEN
    CREATE TRIGGER aaa_support_write_mutex_auth_users_trg
      BEFORE DELETE ON auth.users
      FOR EACH STATEMENT EXECUTE FUNCTION public.support_write_mutex_statement();
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    WHERE t.tgrelid = 'auth.users'::regclass AND NOT t.tgisinternal
      AND t.tgfoid = 'public.support_write_mutex_statement()'::regprocedure
      AND (t.tgtype & 1) = 0 AND (t.tgtype & 2) = 2 AND (t.tgtype & 8) = 8 AND t.tgenabled <> 'D') THEN
    RAISE EXCEPTION 'auth.users has no enabled BEFORE DELETE statement trigger entering the write mutex; refusing';
  END IF;
END $$;

COMMIT;
