-- Support session server contract, part 1 of 3: schema, constraints, RLS, grants.
--
-- NOT EXECUTED by its author. A reviewer must apply it first to a disposable
-- database (fresh and production-shaped) before any shared use. Forward-only and
-- additive: no existing table is dropped or rewritten, no historical migration is
-- edited. Spec: docs/SUPPORT_SESSION_SPEC.md sections 8.4, 8.5, 9.3, 9.5.
--
-- Design notes
--  * Writes to the new user data go only through the SECURITY DEFINER functions in
--    part 2/3 (fixed search_path, auth.uid() ownership checks, explicit grants).
--    Authenticated users get SELECT on their own rows only, so a direct PostgREST
--    write can never bypass the session-wide CAS, the operation receipts or the
--    owner/reference validation.
--  * The memory stores are the existing singular public.companion_memory (curated)
--    and public.memory_fragments (generated). Only metadata columns are added; no
--    third copy of any personal fact is created. Suppression/tombstone tables hold
--    identifiers and timestamps only, never forgotten plaintext.
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $$
BEGIN
  IF to_regclass('public.support_work_sessions') IS NOT NULL
     OR to_regclass('public.support_activities') IS NOT NULL
     OR to_regclass('public.support_privacy_state') IS NOT NULL THEN
    RAISE EXCEPTION 'support session schema already present; review before applying';
  END IF;
  IF to_regclass('public.companion_memory') IS NULL
     OR to_regclass('public.memory_fragments') IS NULL
     OR to_regclass('public.conversations') IS NULL
     OR to_regclass('public.messages') IS NULL
     OR to_regclass('public.chat_requests') IS NULL
     OR to_regclass('public.exercise_sessions') IS NULL THEN
    RAISE EXCEPTION 'expected baseline tables are missing';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_try_uuid(p_text text)
RETURNS uuid LANGUAGE plpgsql IMMUTABLE
SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  RETURN p_text::uuid;
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.support_try_uuid(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.support_try_uuid(text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Per-user privacy state (monotonic revision) and its replay receipts
-- ---------------------------------------------------------------------------
CREATE TABLE public.support_privacy_state (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  privacy_revision bigint NOT NULL DEFAULT 1 CHECK (privacy_revision >= 1),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.support_privacy_operations (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  operation_id uuid NOT NULL,
  kind text NOT NULL,
  payload_hash text NOT NULL,
  resulting_revision bigint NOT NULL,
  response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, operation_id)
);

-- Identifier-only suppression ledger (section 8.5). ref_id is a message,
-- conversation, companion_memory or memory_fragment id; no content is stored.
CREATE TABLE public.support_suppressions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('message', 'conversation', 'memory', 'fragment', 'activity')),
  ref_id uuid NOT NULL,
  reason text NOT NULL CHECK (reason IN (
    'forgotten_memory', 'forgotten_fragment', 'derived_from_forgotten', 'user_source_exclusion',
    'activity_discarded')),
  memory_revision integer,
  operation_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, kind, ref_id)
);
CREATE INDEX support_suppressions_user_idx ON public.support_suppressions (user_id, kind);

-- Memory revision/tombstone identity. Identifiers and timestamps only.
CREATE TABLE public.support_memory_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  memory_kind text NOT NULL CHECK (memory_kind IN ('companion_memory', 'memory_fragment')),
  memory_id uuid NOT NULL,
  event text NOT NULL CHECK (event IN (
    'created', 'edited', 'disabled', 'enabled', 'forgotten', 'approved', 'dismissed', 'expired')),
  memory_revision integer,
  privacy_revision bigint,
  operation_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX support_memory_events_user_idx ON public.support_memory_events (user_id, memory_id, created_at);

-- ---------------------------------------------------------------------------
-- Sessions, activities, events, receipts
-- ---------------------------------------------------------------------------
CREATE TABLE public.support_work_sessions (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  conversation_id uuid REFERENCES public.conversations(id) ON DELETE SET NULL,
  previous_session_id uuid,
  selected_activity_id uuid,
  title text NOT NULL DEFAULT '' CHECK (char_length(title) <= 80),
  concern text CHECK (concern IS NULL OR char_length(concern) <= 4000),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed', 'deleted')),
  context_scope text NOT NULL DEFAULT 'conversation_only'
    CHECK (context_scope IN ('conversation_only', 'personalized')),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision >= 1),
  -- Bumped only when context-relevant fields change (concern, scope, attachment).
  context_revision bigint NOT NULL DEFAULT 1 CHECK (context_revision >= 1),
  suppressed_templates text[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz,
  deleted_at timestamptz,
  UNIQUE (user_id, id),
  CONSTRAINT support_work_sessions_prev_fk FOREIGN KEY (user_id, previous_session_id)
    REFERENCES public.support_work_sessions (user_id, id) ON DELETE NO ACTION,
  CONSTRAINT support_work_sessions_not_self_prev CHECK (previous_session_id IS NULL OR previous_session_id <> id),
  CONSTRAINT support_work_sessions_deleted_shape CHECK (
    (status = 'deleted') = (deleted_at IS NOT NULL)),
  CONSTRAINT support_work_sessions_closed_shape CHECK (
    status <> 'closed' OR closed_at IS NOT NULL)
);
-- At most one live session per attached conversation (tombstones detach).
CREATE UNIQUE INDEX support_work_sessions_conversation_uidx
  ON public.support_work_sessions (conversation_id) WHERE conversation_id IS NOT NULL AND status <> 'deleted';
CREATE INDEX support_work_sessions_owner_list_idx ON public.support_work_sessions (user_id, updated_at, id);

CREATE TABLE public.support_activities (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  support_session_id uuid NOT NULL,
  template_key text NOT NULL CHECK (template_key IN ('ground_present_v1', 'untangle_thought_v1', 'choose_step_v1')),
  template_version integer NOT NULL DEFAULT 1 CHECK (template_version >= 1),
  kind text NOT NULL CHECK (kind IN ('grounding', 'untangle', 'next_step')),
  status text NOT NULL CHECK (status IN ('ready', 'in_progress', 'paused', 'completed', 'stopped')),
  stop_reason text CHECK (stop_reason IS NULL OR char_length(stop_reason) <= 40),
  canonical_ref_type text CHECK (canonical_ref_type IN ('exercise_session', 'journal_entry')),
  canonical_ref_id uuid,
  checkpoint jsonb CHECK (checkpoint IS NULL OR octet_length(checkpoint::text) <= 32768),
  result jsonb CHECK (result IS NULL OR octet_length(result::text) <= 32768),
  reflection jsonb CHECK (reflection IS NULL OR octet_length(reflection::text) <= 4096),
  active_ms bigint NOT NULL DEFAULT 0 CHECK (active_ms >= 0),
  -- Bumped when status, result, reflection or checkpoint-presence change; a context
  -- receipt citing an older value can no longer be confirmed.
  context_revision bigint NOT NULL DEFAULT 1 CHECK (context_revision >= 1),
  last_changed_revision bigint NOT NULL CHECK (last_changed_revision >= 1),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  UNIQUE (support_session_id, id),
  CONSTRAINT support_activities_session_fk FOREIGN KEY (user_id, support_session_id)
    REFERENCES public.support_work_sessions (user_id, id) ON DELETE CASCADE,
  CONSTRAINT support_activities_kind_template CHECK (
    (template_key = 'ground_present_v1' AND kind = 'grounding')
    OR (template_key = 'untangle_thought_v1' AND kind = 'untangle')
    OR (template_key = 'choose_step_v1' AND kind = 'next_step')),
  CONSTRAINT support_activities_ref_shape CHECK (
    (canonical_ref_type IS NULL) = (canonical_ref_id IS NULL)),
  CONSTRAINT support_activities_finished_shape CHECK (
    (status IN ('completed', 'stopped')) = (finished_at IS NOT NULL))
);
CREATE UNIQUE INDEX support_activities_one_in_progress_uidx
  ON public.support_activities (support_session_id) WHERE status = 'in_progress';
CREATE INDEX support_activities_session_idx ON public.support_activities (support_session_id, updated_at, id);
CREATE INDEX support_activities_owner_idx ON public.support_activities (user_id, updated_at, id);

-- Same-session selection. Deferred so selection and creation share a transaction.
ALTER TABLE public.support_work_sessions
  ADD CONSTRAINT support_work_sessions_selected_fk FOREIGN KEY (id, selected_activity_id)
  REFERENCES public.support_activities (support_session_id, id) DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE public.support_session_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  support_session_id uuid NOT NULL,
  activity_id uuid,
  operation_id uuid NOT NULL,
  kind text NOT NULL CHECK (kind IN (
    'session_created', 'session_updated', 'session_closed', 'proposal_accepted',
    'activity_started', 'activity_checkpointed', 'activity_paused', 'activity_completed',
    'activity_stopped', 'activity_discarded', 'reflection_recorded', 'session_deleted')),
  seq bigint NOT NULL CHECK (seq >= 1),
  client_occurred_at timestamptz,
  accepted_at timestamptz NOT NULL DEFAULT now(),
  payload jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (octet_length(payload::text) <= 2048),
  UNIQUE (support_session_id, seq),
  CONSTRAINT support_events_session_fk FOREIGN KEY (user_id, support_session_id)
    REFERENCES public.support_work_sessions (user_id, id) ON DELETE CASCADE
);
CREATE INDEX support_session_events_owner_idx ON public.support_session_events (user_id, support_session_id, seq);

-- Unique (user_id, operation_id). Content-free: it survives deletion of the session
-- (the session row itself remains as a tombstone) so late replay cannot resurrect work.
CREATE TABLE public.support_mutation_receipts (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  operation_id uuid NOT NULL,
  operation_kind text NOT NULL,
  session_id uuid NOT NULL,
  target_id uuid,
  payload_hash text NOT NULL,
  resulting_revision bigint NOT NULL,
  response jsonb NOT NULL CHECK (octet_length(response::text) <= 4096),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, operation_id)
);
CREATE INDEX support_mutation_receipts_session_idx ON public.support_mutation_receipts (user_id, session_id);

-- Server catalog registry for model/client template keys. exercise_id maps the
-- grounding template to its canonical exercises row; NULL means "not mapped yet"
-- (section 5.4: a disposable-environment seed/mapping is a documented dependency).
CREATE TABLE public.support_template_catalog (
  template_key text PRIMARY KEY CHECK (template_key IN ('ground_present_v1', 'untangle_thought_v1', 'choose_step_v1')),
  template_version integer NOT NULL DEFAULT 1,
  kind text NOT NULL CHECK (kind IN ('grounding', 'untangle', 'next_step')),
  exercise_id uuid REFERENCES public.exercises(id) ON DELETE SET NULL,
  estimated_minutes integer NOT NULL CHECK (estimated_minutes BETWEEN 1 AND 60),
  enabled boolean NOT NULL DEFAULT true
);
INSERT INTO public.support_template_catalog (template_key, template_version, kind, estimated_minutes) VALUES
  ('ground_present_v1', 1, 'grounding', 2),
  ('untangle_thought_v1', 1, 'untangle', 3),
  ('choose_step_v1', 1, 'next_step', 1);

-- Proposal (section 8.6). One per request; becomes actionable only via the
-- confirmation RPC in part 3.
CREATE TABLE public.support_proposals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  support_session_id uuid NOT NULL,
  request_id uuid NOT NULL,
  message_id uuid,
  template_key text NOT NULL REFERENCES public.support_template_catalog(template_key),
  reason_code text NOT NULL CHECK (reason_code IN (
    'current_request', 'approved_preference', 'selected_intent', 'general_option')),
  basis_kind text CHECK (basis_kind IN ('companion_memory', 'message', 'activity')),
  basis_ref uuid,
  suggested_step text CHECK (suggested_step IS NULL OR char_length(suggested_step) <= 400),
  privacy_revision bigint NOT NULL,
  status text NOT NULL DEFAULT 'offered' CHECK (status IN (
    'offered', 'accepted', 'declined', 'expired', 'invalidated')),
  accepted_activity_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  UNIQUE (user_id, request_id),
  CONSTRAINT support_proposals_session_fk FOREIGN KEY (user_id, support_session_id)
    REFERENCES public.support_work_sessions (user_id, id) ON DELETE CASCADE,
  CONSTRAINT support_proposals_basis_shape CHECK ((basis_kind IS NULL) = (basis_ref IS NULL)),
  CONSTRAINT support_proposals_step_template CHECK (suggested_step IS NULL OR template_key = 'choose_step_v1')
);
CREATE INDEX support_proposals_session_idx ON public.support_proposals (user_id, support_session_id, status);
CREATE INDEX support_proposals_basis_idx ON public.support_proposals (user_id, basis_kind, basis_ref) WHERE basis_ref IS NOT NULL;

-- Immutable context receipt (section 8.3). References and minimal labels only.
CREATE TABLE public.support_context_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  request_id uuid NOT NULL,
  support_session_id uuid,
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  assistant_message_id uuid,
  schema_version integer NOT NULL DEFAULT 1,
  privacy_revision bigint NOT NULL,
  scope text NOT NULL CHECK (scope IN ('conversation_only', 'personalized')),
  provider_vendor text NOT NULL CHECK (char_length(provider_vendor) BETWEEN 1 AND 32),
  provider_model text NOT NULL CHECK (char_length(provider_model) BETWEEN 1 AND 64),
  route_version text NOT NULL CHECK (char_length(route_version) BETWEEN 1 AND 32),
  exclusions text[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, request_id)
);
CREATE INDEX support_context_receipts_message_idx ON public.support_context_receipts (user_id, assistant_message_id);

CREATE TABLE public.support_context_receipt_sources (
  receipt_id uuid NOT NULL REFERENCES public.support_context_receipts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source_kind text NOT NULL CHECK (source_kind IN (
    'message', 'companion_memory', 'daily_intent', 'session', 'activity_result', 'safety_policy')),
  source_id uuid NOT NULL,
  source_revision bigint NOT NULL DEFAULT 0,
  source_date timestamptz,
  PRIMARY KEY (receipt_id, source_kind, source_id)
);
CREATE INDEX support_receipt_sources_lookup_idx
  ON public.support_context_receipt_sources (user_id, source_kind, source_id);

-- ---------------------------------------------------------------------------
-- Ownership validation of cross-table references (a valid UUID proves nothing)
-- ---------------------------------------------------------------------------
CREATE FUNCTION public.support_work_sessions_validate_refs() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
  IF NEW.conversation_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.conversations c WHERE c.id = NEW.conversation_id AND c.user_id = NEW.user_id) THEN
    RAISE EXCEPTION 'conversation is not owned by session owner' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER support_work_sessions_validate_refs_trg
  BEFORE INSERT OR UPDATE OF conversation_id, user_id ON public.support_work_sessions
  FOR EACH ROW EXECUTE FUNCTION public.support_work_sessions_validate_refs();

CREATE FUNCTION public.support_activities_validate_refs() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
  IF NEW.canonical_ref_type = 'exercise_session' AND NOT EXISTS (
      SELECT 1 FROM public.exercise_sessions e WHERE e.id = NEW.canonical_ref_id AND e.user_id = NEW.user_id) THEN
    RAISE EXCEPTION 'exercise session is not owned by activity owner' USING ERRCODE = '42501';
  END IF;
  IF NEW.canonical_ref_type = 'journal_entry' AND NOT EXISTS (
      SELECT 1 FROM public.journal_entries j WHERE j.id = NEW.canonical_ref_id AND j.user_id = NEW.user_id) THEN
    RAISE EXCEPTION 'journal entry is not owned by activity owner' USING ERRCODE = '42501';
  END IF;
  -- A completed or stopped execution is immutable except for an appended reflection.
  IF TG_OP = 'UPDATE' AND OLD.status IN ('completed', 'stopped')
     AND coalesce(current_setting('support.discarding', true), '') <> 'on' THEN
    IF NEW.status IS DISTINCT FROM OLD.status
       OR NEW.result IS DISTINCT FROM OLD.result
       OR NEW.canonical_ref_id IS DISTINCT FROM OLD.canonical_ref_id
       OR NEW.finished_at IS DISTINCT FROM OLD.finished_at THEN
      -- Only the discard handler (support.discarding = on, transaction-local) may scrub a
      -- terminal activity's content; nothing else legitimately reaches this branch.
      RAISE EXCEPTION 'terminal activity is immutable' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE FUNCTION public.support_context_revision_bump() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
  IF TG_TABLE_NAME = 'support_work_sessions' THEN
    IF NEW.concern IS DISTINCT FROM OLD.concern OR NEW.context_scope IS DISTINCT FROM OLD.context_scope
       OR NEW.conversation_id IS DISTINCT FROM OLD.conversation_id OR NEW.status IS DISTINCT FROM OLD.status THEN
      NEW.context_revision := OLD.context_revision + 1;
    END IF;
  ELSE
    IF NEW.status IS DISTINCT FROM OLD.status OR NEW.result IS DISTINCT FROM OLD.result
       OR NEW.reflection IS DISTINCT FROM OLD.reflection OR (NEW.checkpoint IS NULL) <> (OLD.checkpoint IS NULL) THEN
      NEW.context_revision := OLD.context_revision + 1;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER support_work_sessions_context_revision_trg BEFORE UPDATE ON public.support_work_sessions
  FOR EACH ROW EXECUTE FUNCTION public.support_context_revision_bump();
CREATE TRIGGER support_activities_context_revision_trg BEFORE UPDATE ON public.support_activities
  FOR EACH ROW EXECUTE FUNCTION public.support_context_revision_bump();

CREATE TRIGGER support_activities_validate_refs_trg
  BEFORE INSERT OR UPDATE ON public.support_activities
  FOR EACH ROW EXECUTE FUNCTION public.support_activities_validate_refs();

-- ---------------------------------------------------------------------------
-- Additive metadata on the EXISTING memory stores and chat tables
-- ---------------------------------------------------------------------------
-- Curated store (singular companion_memory). Existing rows are user-authored by
-- the existing management UI, so they keep their honest origin and remain eligible.
ALTER TABLE public.companion_memory
  ADD COLUMN IF NOT EXISTS origin text NOT NULL DEFAULT 'user_authored'
    CHECK (origin IN ('user_authored', 'approved_candidate')),
  ADD COLUMN IF NOT EXISTS revision integer NOT NULL DEFAULT 1 CHECK (revision >= 1),
  ADD COLUMN IF NOT EXISTS confirmed_at timestamptz,
  ADD COLUMN IF NOT EXISTS disabled_at timestamptz,
  ADD COLUMN IF NOT EXISTS review_due_at timestamptz,
  ADD COLUMN IF NOT EXISTS expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS source_message_id uuid,
  ADD COLUMN IF NOT EXISTS source_conversation_id uuid,
  ADD COLUMN IF NOT EXISTS approved_from_fragment_id uuid;

-- Generated store. DEFAULT 'legacy_review' means every pre-existing automatic
-- fragment, and every fragment written by code that predates this contract, is
-- excluded from new personalization until the person approves it (section 8.4).
ALTER TABLE public.memory_fragments
  ADD COLUMN IF NOT EXISTS review_state text NOT NULL DEFAULT 'legacy_review'
    CHECK (review_state IN ('legacy_review', 'pending', 'promoted', 'dismissed', 'expired')),
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS promoted_memory_id uuid,
  ADD COLUMN IF NOT EXISTS candidate_expires_at timestamptz;

-- Optional chat metadata; old clients and old rows simply have NULLs.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS support_session_id uuid,
  ADD COLUMN IF NOT EXISTS content_origin text
    CHECK (content_origin IS NULL OR content_origin IN ('model', 'interface_fallback', 'safety_response'));
ALTER TABLE public.chat_requests
  ADD COLUMN IF NOT EXISTS support_session_id uuid;

CREATE INDEX IF NOT EXISTS idx_companion_memory_user_revision
  ON public.companion_memory (user_id, disabled_at) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_memory_fragments_review
  ON public.memory_fragments (user_id, review_state);

-- ---------------------------------------------------------------------------
-- RLS and grants: owner SELECT only on user-facing tables; mutation via RPC
-- ---------------------------------------------------------------------------
ALTER TABLE public.support_privacy_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_privacy_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_suppressions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_memory_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_work_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_session_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_mutation_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_template_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_proposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_context_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_context_receipt_sources ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON
  public.support_privacy_state, public.support_privacy_operations, public.support_suppressions,
  public.support_memory_events, public.support_work_sessions, public.support_activities,
  public.support_session_events, public.support_mutation_receipts, public.support_template_catalog,
  public.support_proposals, public.support_context_receipts, public.support_context_receipt_sources
FROM PUBLIC, anon, authenticated;
GRANT ALL ON
  public.support_privacy_state, public.support_privacy_operations, public.support_suppressions,
  public.support_memory_events, public.support_work_sessions, public.support_activities,
  public.support_session_events, public.support_mutation_receipts, public.support_template_catalog,
  public.support_proposals, public.support_context_receipts, public.support_context_receipt_sources
TO service_role;

GRANT SELECT ON public.support_privacy_state, public.support_work_sessions, public.support_activities,
  public.support_session_events, public.support_proposals, public.support_context_receipts,
  public.support_context_receipt_sources, public.support_template_catalog TO authenticated;

CREATE POLICY support_privacy_state_owner_select ON public.support_privacy_state
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY support_work_sessions_owner_select ON public.support_work_sessions
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY support_activities_owner_select ON public.support_activities
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY support_session_events_owner_select ON public.support_session_events
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY support_proposals_owner_select ON public.support_proposals
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY support_context_receipts_owner_select ON public.support_context_receipts
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY support_receipt_sources_owner_select ON public.support_context_receipt_sources
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY support_template_catalog_read ON public.support_template_catalog
  FOR SELECT TO authenticated USING (true);
-- Operation receipts, privacy operations, suppression ledger and memory events have
-- no authenticated policy at all: they are reachable only through the RPCs.

COMMIT;
