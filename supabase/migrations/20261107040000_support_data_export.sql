-- Owner data export (AC-20 / E01): one narrow, owner-bound, paginated, read-only RPC.
--
-- NOT EXECUTED by its author. A reviewer must read this exact file and apply it first to a
-- disposable database (fresh and production-shaped) with supabase/tests/support_data_export.sql
-- before any shared use. Forward-only and additive: it creates ONE function and changes no table,
-- no policy and no existing grant. Rollback: DROP FUNCTION public.export_owner_data_page(uuid, text, text, integer).
--
-- Why a SECURITY DEFINER function and not new table grants
--   The support tables that hold operation receipts, privacy operations, suppressions and memory
--   events deliberately have NO authenticated policy (20261106230000_support_session_schema.sql).
--   The export must still return them to their owner. Granting those tables to `authenticated`
--   would widen every future query; instead this one definer function reads them for exactly one
--   verified owner, one fixed dataset and one bounded page at a time.
--
-- Contract (mirrored by Core/SupportSession/SupportDataExport.swift)
--   * p_expected_owner must equal auth.uid(); anything else is 42501 ("Account changed") and nothing
--     is read. A missing principal is 28000. anon/PUBLIC have no EXECUTE.
--   * p_dataset is NOT SQL and NOT a table name: it must equal one entry of the immutable list
--     c_datasets below, and each entry maps to a fixed, reviewed query. Unknown names are 22023.
--   * Pages are keyset pages over stable ordered keys (ids; composite for receipt sources). The cursor
--     is the canonical text key of the last returned row and is validated by shape (22023 otherwise).
--     p_limit is 1..100 (rejected, never clamped). A page also stops once its rows reach 262144 bytes
--     of jsonb text, but always returns at least one row so paging always makes progress.
--   * Every returned row carries export_owner_id (derived from the row's OWN ownership join, never
--     from a constant) and export_key (the ordering/cursor key). The client rejects any row whose
--     owner differs or whose key does not strictly ascend.
--   * An optional table that is absent from this database is reported as status = 'unavailable'
--     with an explicit reason. It is never an empty successful dataset.
--   * Secrets and unrelated users are excluded by construction: profiles and subscriptions are
--     ALLOWLISTED by column (no push_token, no referred_by, no transaction identifiers, no family or
--     organization ids); circle invite codes and other members are never selected; shared catalogs
--     (quest templates, exercises, circles) contribute only the descriptive fields of the owner's
--     own join.
--   * Pages are separate statements. They are not one snapshot: a record that changes while the export
--     runs may appear in either state. The app records the start and end time and says so.
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $$
BEGIN
  IF pg_catalog.to_regprocedure('auth.uid()') IS NULL
     OR pg_catalog.to_regclass('public.profiles') IS NULL
     OR pg_catalog.to_regclass('public.conversations') IS NULL
     OR pg_catalog.to_regclass('public.messages') IS NULL THEN
    RAISE EXCEPTION 'owner data export requires auth.uid() and the baseline profiles/conversations/messages tables';
  END IF;
  IF pg_catalog.to_regprocedure('public.export_owner_data_page(uuid,text,text,integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'owner data export already present; review before applying';
  END IF;
END $$;

CREATE FUNCTION public.export_owner_data_page(
  p_expected_owner uuid,
  p_dataset text,
  p_after text DEFAULT NULL,
  p_limit integer DEFAULT 100
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '15s'
AS $$
DECLARE
  -- Immutable contract constants. Changing any of them is a new catalog_version.
  c_catalog_version constant integer := 1;
  c_max_rows        constant integer := 100;
  c_max_bytes       constant integer := 262144;
  c_uuid_pattern    constant text := '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
  c_datasets constant text[] := ARRAY[
    'profile', 'user_settings', 'moods', 'quests', 'conversations', 'messages',
    'circle_memberships', 'exercise_sessions', 'subscriptions', 'crisis_events',
    'companion_memories', 'memory_fragments',
    'support_privacy_state', 'support_sessions', 'support_activities', 'support_session_events',
    'support_mutation_receipts', 'support_proposals', 'support_context_receipts',
    'support_context_receipt_sources', 'support_privacy_operations', 'support_suppressions',
    'support_memory_events', 'support_onboarding_consent', 'offline_mutation_receipts',
    'support_memory_suggestion_requests'];
  -- Column ALLOWLISTS for the two tables that carry provider or unrelated-user identifiers.
  c_profile_columns constant text[] := ARRAY[
    'id', 'handle', 'display_name', 'email', 'avatar_url', 'timezone', 'created_at', 'updated_at',
    'daily_quest_time_local', 'quiet_hours_start_local', 'quiet_hours_end_local', 'reminders_enabled',
    'nudge_after_days_inactive', 'share_mood_in_circles', 'ai_tone', 'privacy_mode',
    'current_streak_days', 'longest_streak_days', 'total_quests_completed', 'total_exercises_completed',
    'subscription_tier', 'daily_ai_quota', 'daily_ai_used', 'quota_reset_at', 'wellness_focus',
    'onboarding_completed_at', 'typical_active_hour', 'premium_badge', 'last_session_at', 'session_count',
    'last_absence_days', 'fresh_start_used_at', 'referral_code', 'total_referrals', 'preferred_language',
    'activation_completed_at', 'first_quest_completed_at', 'first_mood_logged_at',
    'first_chat_message_at', 'unlocked_features', 'active_transition'];
  c_subscription_columns constant text[] := ARRAY[
    'id', 'user_id', 'product_id', 'status', 'expires_at', 'created_at', 'updated_at', 'plan_type',
    'billing_period', 'is_family_admin', 'seats_used', 'seats_total', 'access_source'];

  v_uid uuid := auth.uid();
  v_required text[];
  v_after_id uuid;
  v_after_receipt uuid;
  v_after_kind text;
  v_after_source uuid;
  v_keys text[];
  v_rows jsonb[];
  v_n integer;
  v_i integer;
  v_take integer := 0;
  v_bytes integer := 0;
  v_size integer;
  v_has_more boolean;
  v_next text;
  v_page jsonb;
BEGIN
  -- 1. Principal and expected owner BEFORE anything else is looked at.
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;
  IF p_expected_owner IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'Account changed' USING ERRCODE = '42501';
  END IF;

  -- 2. Fixed dataset, bounded page size, shape-checked cursor. Nothing here is interpolated into SQL.
  IF p_dataset IS NULL OR NOT (p_dataset = ANY (c_datasets)) THEN
    RAISE EXCEPTION 'Unknown export dataset' USING ERRCODE = '22023';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > c_max_rows THEN
    RAISE EXCEPTION 'Invalid export page size' USING ERRCODE = '22023';
  END IF;
  IF p_after IS NOT NULL THEN
    IF p_dataset = 'support_context_receipt_sources' THEN
      IF p_after !~ ('^' || c_uuid_pattern || ':[a-z_]{1,32}:' || c_uuid_pattern || '$') THEN
        RAISE EXCEPTION 'Invalid export cursor' USING ERRCODE = '22023';
      END IF;
      v_after_receipt := split_part(p_after, ':', 1)::uuid;
      v_after_kind := split_part(p_after, ':', 2);
      v_after_source := split_part(p_after, ':', 3)::uuid;
    ELSE
      IF p_after !~ ('^' || c_uuid_pattern || '$') THEN
        RAISE EXCEPTION 'Invalid export cursor' USING ERRCODE = '22023';
      END IF;
      v_after_id := p_after::uuid;
    END IF;
  END IF;

  -- 3. Explicit unavailability for an optional domain whose table is absent from this database.
  v_required := CASE p_dataset
    WHEN 'profile' THEN ARRAY['profiles']
    WHEN 'user_settings' THEN ARRAY['user_settings']
    WHEN 'moods' THEN ARRAY['moods']
    WHEN 'quests' THEN ARRAY['quests', 'quest_templates']
    WHEN 'conversations' THEN ARRAY['conversations']
    WHEN 'messages' THEN ARRAY['messages', 'conversations']
    WHEN 'circle_memberships' THEN ARRAY['circle_members', 'circles']
    WHEN 'exercise_sessions' THEN ARRAY['exercise_sessions', 'exercises']
    WHEN 'subscriptions' THEN ARRAY['subscriptions']
    WHEN 'crisis_events' THEN ARRAY['crisis_events']
    WHEN 'companion_memories' THEN ARRAY['companion_memory']
    WHEN 'memory_fragments' THEN ARRAY['memory_fragments']
    WHEN 'support_privacy_state' THEN ARRAY['support_privacy_state']
    WHEN 'support_sessions' THEN ARRAY['support_work_sessions']
    WHEN 'support_activities' THEN ARRAY['support_activities']
    WHEN 'support_session_events' THEN ARRAY['support_session_events']
    WHEN 'support_mutation_receipts' THEN ARRAY['support_mutation_receipts']
    WHEN 'support_proposals' THEN ARRAY['support_proposals']
    WHEN 'support_context_receipts' THEN ARRAY['support_context_receipts']
    WHEN 'support_context_receipt_sources' THEN ARRAY['support_context_receipt_sources', 'support_context_receipts']
    WHEN 'support_privacy_operations' THEN ARRAY['support_privacy_operations']
    WHEN 'support_suppressions' THEN ARRAY['support_suppressions']
    WHEN 'support_memory_events' THEN ARRAY['support_memory_events']
    WHEN 'support_onboarding_consent' THEN ARRAY['support_onboarding_consent']
    WHEN 'offline_mutation_receipts' THEN ARRAY['offline_mutation_receipts']
    WHEN 'support_memory_suggestion_requests' THEN ARRAY['support_memory_suggestion_requests']
  END;
  IF EXISTS (SELECT 1 FROM unnest(v_required) AS r(rel) WHERE pg_catalog.to_regclass('public.' || r.rel) IS NULL) THEN
    RETURN jsonb_build_object(
      'catalog_version', c_catalog_version, 'catalog_size', cardinality(c_datasets),
      'owner', v_uid, 'dataset', p_dataset, 'status', 'unavailable', 'reason', 'table_absent',
      'after', p_after, 'rows', '[]'::jsonb, 'row_count', 0, 'has_more', false, 'next_cursor', NULL::text,
      'limits', jsonb_build_object('max_rows', c_max_rows, 'max_page_bytes', c_max_bytes, 'requested_rows', p_limit));
  END IF;

  -- 4. One fixed, owner-filtered, keyset-ordered query per dataset. p_limit + 1 rows are read so
  --    "has more" is exact. Ownership is resolved from each row's real owner relationship.
  IF p_dataset = 'profile' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        coalesce((SELECT jsonb_object_agg(e.key, e.value) FROM jsonb_each(to_jsonb(t)) AS e WHERE e.key = ANY (c_profile_columns)), '{}'::jsonb)
          || jsonb_build_object('export_owner_id', t.id, 'export_key', t.id::text) AS j
      FROM public.profiles t
      WHERE t.id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'user_settings' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.id::text) AS j
      FROM public.user_settings t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'moods' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.id::text) AS j
      FROM public.moods t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'quests' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        to_jsonb(t) || jsonb_build_object(
          'template', CASE WHEN q.id IS NULL THEN NULL::jsonb ELSE jsonb_build_object(
            'id', q.id, 'title', q.title, 'description', q.description, 'category', q.category,
            'estimated_minutes', q.estimated_minutes, 'xp_reward', q.xp_reward, 'is_premium', q.is_premium) END,
          'export_owner_id', t.user_id, 'export_key', t.id::text) AS j
      FROM public.quests t
      LEFT JOIN public.quest_templates q ON q.id = t.template_id
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'conversations' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.id::text) AS j
      FROM public.conversations t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'messages' THEN
    -- messages has no owner column: ownership is the owning conversation, resolved by the join.
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', c.user_id, 'export_key', t.id::text) AS j
      FROM public.messages t
      JOIN public.conversations c ON c.id = t.conversation_id
      WHERE c.user_id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'circle_memberships' THEN
    -- Only the owner's membership row and the circle's descriptive fields. No invite code, no other member.
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        to_jsonb(t) || jsonb_build_object(
          'circle', CASE WHEN c.id IS NULL THEN NULL::jsonb ELSE jsonb_build_object(
            'id', c.id, 'name', c.name, 'description', c.description, 'created_at', c.created_at) END,
          'export_owner_id', t.user_id, 'export_key', t.id::text) AS j
      FROM public.circle_members t
      LEFT JOIN public.circles c ON c.id = t.circle_id
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'exercise_sessions' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        to_jsonb(t) || jsonb_build_object(
          'exercise', CASE WHEN x.id IS NULL THEN NULL::jsonb ELSE jsonb_build_object(
            'id', x.id, 'title', x.title, 'type', x.type) END,
          'export_owner_id', t.user_id, 'export_key', t.id::text) AS j
      FROM public.exercise_sessions t
      LEFT JOIN public.exercises x ON x.id = t.exercise_id
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'subscriptions' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        coalesce((SELECT jsonb_object_agg(e.key, e.value) FROM jsonb_each(to_jsonb(t)) AS e WHERE e.key = ANY (c_subscription_columns)), '{}'::jsonb)
          || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.id::text) AS j
      FROM public.subscriptions t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'crisis_events' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.id::text) AS j
      FROM public.crisis_events t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'companion_memories' THEN
    -- Curated store, including soft-deleted rows (deleted_at is visible; the app does not hide what is held).
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.id::text) AS j
      FROM public.companion_memory t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'memory_fragments' THEN
    -- Generated store with its provenance (source ids) and review state exactly as stored.
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.id::text) AS j
      FROM public.memory_fragments t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'support_privacy_state' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.user_id) AS ord, t.user_id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.user_id::text) AS j
      FROM public.support_privacy_state t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.user_id > v_after_id)
      ORDER BY t.user_id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'support_sessions' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.id::text) AS j
      FROM public.support_work_sessions t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'support_activities' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.id::text) AS j
      FROM public.support_activities t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'support_session_events' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.id::text) AS j
      FROM public.support_session_events t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'support_mutation_receipts' THEN
    -- Primary key is (user_id, operation_id); operation_id is unique within the one verified owner.
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.operation_id) AS ord, t.operation_id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.operation_id::text) AS j
      FROM public.support_mutation_receipts t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.operation_id > v_after_id)
      ORDER BY t.operation_id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'support_proposals' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.id::text) AS j
      FROM public.support_proposals t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'support_context_receipts' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.id::text) AS j
      FROM public.support_context_receipts t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'support_context_receipt_sources' THEN
    -- A source row is the owner's only if its row owner AND its receipt's owner both are. The reported
    -- owner is the RECEIPT's, so a source attached to someone else's receipt can never be labelled mine.
    -- The composite cursor orders by (receipt_id, source_kind COLLATE "C", source_id); the key string
    -- uses ':' (below every kind character) so string order equals tuple order.
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.receipt_id, t.source_kind COLLATE "C", t.source_id) AS ord,
        t.receipt_id::text || ':' || t.source_kind || ':' || t.source_id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', r.user_id,
          'export_key', t.receipt_id::text || ':' || t.source_kind || ':' || t.source_id::text) AS j
      FROM public.support_context_receipt_sources t
      JOIN public.support_context_receipts r ON r.id = t.receipt_id AND r.user_id = v_uid
      WHERE t.user_id = v_uid
        AND (v_after_receipt IS NULL
             OR (t.receipt_id, t.source_kind COLLATE "C", t.source_id) > (v_after_receipt, v_after_kind, v_after_source))
      ORDER BY t.receipt_id, t.source_kind COLLATE "C", t.source_id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'support_privacy_operations' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.operation_id) AS ord, t.operation_id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.operation_id::text) AS j
      FROM public.support_privacy_operations t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.operation_id > v_after_id)
      ORDER BY t.operation_id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'support_suppressions' THEN
    -- Identifier-only ledger (no forgotten plaintext is stored here), exported with its reason and revision.
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.id::text) AS j
      FROM public.support_suppressions t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'support_memory_events' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.id) AS ord, t.id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.id::text) AS j
      FROM public.support_memory_events t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.id > v_after_id)
      ORDER BY t.id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'support_onboarding_consent' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.user_id) AS ord, t.user_id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.user_id::text) AS j
      FROM public.support_onboarding_consent t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.user_id > v_after_id)
      ORDER BY t.user_id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'offline_mutation_receipts' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.operation_id) AS ord, t.operation_id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.operation_id::text) AS j
      FROM public.offline_mutation_receipts t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.operation_id > v_after_id)
      ORDER BY t.operation_id LIMIT p_limit + 1) s;

  ELSIF p_dataset = 'support_memory_suggestion_requests' THEN
    SELECT array_agg(s.k ORDER BY s.ord), array_agg(s.j ORDER BY s.ord) INTO v_keys, v_rows FROM (
      SELECT row_number() OVER (ORDER BY t.request_id) AS ord, t.request_id::text AS k,
        to_jsonb(t) || jsonb_build_object('export_owner_id', t.user_id, 'export_key', t.request_id::text) AS j
      FROM public.support_memory_suggestion_requests t
      WHERE t.user_id = v_uid AND (v_after_id IS NULL OR t.request_id > v_after_id)
      ORDER BY t.request_id LIMIT p_limit + 1) s;

  ELSE
    -- Unreachable while c_datasets and these branches agree; fail closed rather than guess a table.
    RAISE EXCEPTION 'Export dataset is not implemented' USING ERRCODE = 'XX000';
  END IF;

  -- 5. Row and byte bounds. At most p_limit rows; stop before the row that would pass c_max_bytes of
  --    jsonb text, but always keep the first row so a page can never be empty while more rows exist.
  v_n := coalesce(cardinality(v_rows), 0);
  FOR v_i IN 1..v_n LOOP
    EXIT WHEN v_i > p_limit;
    v_size := pg_catalog.octet_length(v_rows[v_i]::text);
    IF v_take > 0 AND v_bytes + v_size > c_max_bytes THEN
      EXIT;
    END IF;
    v_bytes := v_bytes + v_size;
    v_take := v_i;
  END LOOP;
  v_has_more := v_n > v_take;
  v_next := CASE WHEN v_has_more THEN v_keys[v_take] ELSE NULL END;

  v_page := jsonb_build_object(
    'catalog_version', c_catalog_version, 'catalog_size', cardinality(c_datasets),
    'owner', v_uid, 'dataset', p_dataset, 'status', 'available',
    'after', p_after,
    'rows', coalesce((SELECT jsonb_agg(u.r ORDER BY u.ord) FROM unnest(v_rows[1:v_take]) WITH ORDINALITY AS u(r, ord)), '[]'::jsonb),
    'row_count', v_take, 'has_more', v_has_more, 'next_cursor', v_next,
    'limits', jsonb_build_object('max_rows', c_max_rows, 'max_page_bytes', c_max_bytes, 'requested_rows', p_limit));
  RETURN v_page;
END;
$$;

COMMENT ON FUNCTION public.export_owner_data_page(uuid, text, text, integer) IS
  'Owner data export: one verified owner, one fixed dataset, one bounded keyset page (<=100 rows, ~256 KiB). Read-only. See 20261107040000_support_data_export.sql.';

REVOKE ALL ON FUNCTION public.export_owner_data_page(uuid, text, text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.export_owner_data_page(uuid, text, text, integer) TO authenticated;

COMMIT;
