-- EMPTY LOCAL DISPOSABLE DATABASE ONLY. Synthetic rows, no Auth accounts, no providers, no network.
-- NOT EXECUTED by its author: a reviewer reads ../migrations/20261107040000_support_data_export.sql
-- first, then runs this file as supabase_admin in a fresh `support_data_export_synthetic` database
-- (copy the file with its relative ../migrations path intact; it applies the migration with \ir).
--
-- It builds the minimum synthetic shape of every exported table (real column names for everything the
-- function touches, plus the SECRET/unrelated-user columns it must never return), seeds two owners and
-- adversarial cross-owner rows, applies the migration, and then proves:
--   anon / no principal / wrong expected owner / unknown dataset / bad page size / bad cursor are refused,
--   every dataset returns only the verified owner's rows (no other owner, no secret, no unrelated user),
--   the 100-row bound, the byte bound (and guaranteed progress on one oversized row), keyset cursors,
--   internal ownership through conversations and through receipts, allowlisted profile/subscription/
--   circle columns, explicit `unavailable` for an absent table, and that no grant/policy/row changed.
\set ON_ERROR_STOP on
DO $$ BEGIN
  IF current_database() <> 'support_data_export_synthetic' OR current_user <> 'supabase_admin'
    OR pg_catalog.to_regnamespace('auth') IS NOT NULL
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_class AS c JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')) THEN
    RAISE EXCEPTION 'Requires an empty disposable support_data_export_synthetic database as supabase_admin';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'service_role' AND rolbypassrls)
    OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'anon')
    OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'authenticated') THEN
    RAISE EXCEPTION 'Requires existing Supabase roles; this fixture never changes global roles';
  END IF;
END $$;

CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Synthetic shapes. Secret / unrelated-user columns are present so exclusion is observable.
-- ---------------------------------------------------------------------------
CREATE TABLE public.profiles(id uuid PRIMARY KEY, handle text, display_name text, email text, avatar_url text,
  timezone text, created_at timestamptz DEFAULT now(), subscription_tier text DEFAULT 'free', daily_ai_quota integer DEFAULT 5,
  referral_code text, push_token text, referred_by uuid);
CREATE TABLE public.user_settings(id uuid PRIMARY KEY, user_id uuid NOT NULL, ai_tone text DEFAULT 'friendly', show_presence boolean DEFAULT true);
CREATE TABLE public.moods(id uuid PRIMARY KEY, user_id uuid NOT NULL, local_date date NOT NULL DEFAULT current_date, mood_score integer NOT NULL DEFAULT 5, note text);
CREATE TABLE public.quest_templates(id uuid PRIMARY KEY, title text NOT NULL, description text NOT NULL, category text, estimated_minutes integer, xp_reward integer, is_premium boolean);
CREATE TABLE public.quests(id uuid PRIMARY KEY, user_id uuid NOT NULL, template_id uuid NOT NULL, local_date text, status text, reflection_note text);
CREATE TABLE public.conversations(id uuid PRIMARY KEY, user_id uuid NOT NULL, title text);
CREATE TABLE public.messages(id uuid PRIMARY KEY, conversation_id uuid NOT NULL, role text NOT NULL, content text NOT NULL,
  support_session_id uuid, content_origin text);
CREATE TABLE public.circles(id uuid PRIMARY KEY, name text NOT NULL, description text, invite_code text NOT NULL, owner_id uuid NOT NULL, created_at timestamptz DEFAULT now());
CREATE TABLE public.circle_members(id uuid PRIMARY KEY, circle_id uuid NOT NULL, user_id uuid NOT NULL, joined_at timestamptz DEFAULT now(), role text DEFAULT 'member');
CREATE TABLE public.exercises(id uuid PRIMARY KEY, title text NOT NULL, type text NOT NULL);
CREATE TABLE public.exercise_sessions(id uuid PRIMARY KEY, user_id uuid NOT NULL, exercise_id uuid NOT NULL, completed boolean DEFAULT false, note text);
CREATE TABLE public.subscriptions(id uuid PRIMARY KEY, user_id uuid NOT NULL, product_id text NOT NULL, original_transaction_id text NOT NULL,
  last_transaction_id text, status text NOT NULL, plan_type text, billing_period text, family_id uuid, organization_id uuid, seats_used integer, seats_total integer);
CREATE TABLE public.crisis_events(id uuid PRIMARY KEY, user_id uuid NOT NULL, conversation_id uuid, detected_at timestamptz DEFAULT now(), notes text);
CREATE TABLE public.companion_memory(id uuid PRIMARY KEY, user_id uuid NOT NULL, category text, content text NOT NULL, deleted_at timestamptz, origin text, revision integer DEFAULT 1);
CREATE TABLE public.memory_fragments(id uuid PRIMARY KEY, user_id uuid NOT NULL, fragment_type text, key text, value text, review_state text DEFAULT 'legacy_review',
  source_conversation_id uuid, source_message_id uuid);
CREATE TABLE public.support_privacy_state(user_id uuid PRIMARY KEY, privacy_revision bigint NOT NULL DEFAULT 1);
CREATE TABLE public.support_work_sessions(id uuid PRIMARY KEY, user_id uuid NOT NULL, title text, concern text, status text DEFAULT 'open');
CREATE TABLE public.support_activities(id uuid PRIMARY KEY, user_id uuid NOT NULL, support_session_id uuid NOT NULL, template_key text, result jsonb);
CREATE TABLE public.support_session_events(id uuid PRIMARY KEY, user_id uuid NOT NULL, support_session_id uuid NOT NULL, kind text, seq bigint);
CREATE TABLE public.support_mutation_receipts(user_id uuid NOT NULL, operation_id uuid NOT NULL, operation_kind text, session_id uuid, payload_hash text,
  response jsonb DEFAULT '{}', PRIMARY KEY (user_id, operation_id));
CREATE TABLE public.support_proposals(id uuid PRIMARY KEY, user_id uuid NOT NULL, support_session_id uuid, request_id uuid, template_key text, suggested_step text);
CREATE TABLE public.support_context_receipts(id uuid PRIMARY KEY, user_id uuid NOT NULL, request_id uuid, conversation_id uuid, provider_vendor text);
CREATE TABLE public.support_context_receipt_sources(receipt_id uuid NOT NULL, user_id uuid NOT NULL, source_kind text NOT NULL, source_id uuid NOT NULL,
  source_revision bigint DEFAULT 0, PRIMARY KEY (receipt_id, source_kind, source_id));
CREATE TABLE public.support_privacy_operations(user_id uuid NOT NULL, operation_id uuid NOT NULL, kind text, payload_hash text, response jsonb DEFAULT '{}',
  PRIMARY KEY (user_id, operation_id));
CREATE TABLE public.support_suppressions(id uuid PRIMARY KEY, user_id uuid NOT NULL, kind text, ref_id uuid, reason text);
CREATE TABLE public.support_memory_events(id uuid PRIMARY KEY, user_id uuid NOT NULL, memory_kind text, memory_id uuid, event text);
CREATE TABLE public.support_onboarding_consent(user_id uuid PRIMARY KEY, birth_year integer, age_thirteen_confirmed boolean, consent_version text);
CREATE TABLE public.offline_mutation_receipts(user_id uuid NOT NULL, operation_id uuid NOT NULL, kind text, payload_hash text, result jsonb DEFAULT '{}',
  PRIMARY KEY (user_id, operation_id));
CREATE TABLE public.support_memory_suggestion_requests(user_id uuid NOT NULL, request_id uuid NOT NULL, support_session_id uuid NOT NULL,
  status text NOT NULL, payload_hash text NOT NULL, source_count integer NOT NULL, PRIMARY KEY (user_id, request_id));

-- Same posture as the real schema: RLS on, NO table privilege for any API role. The export must work
-- without them (definer), which also proves nothing was widened for it.
DO $$ DECLARE t record; BEGIN
  FOR t IN SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname = 'public' LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t.tablename);
    EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, anon, authenticated', t.tablename);
    EXECUTE format('GRANT ALL ON public.%I TO service_role', t.tablename);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- Deterministic synthetic data. Owner A is the exporter; B is the other account; C exercises byte bounds.
-- ---------------------------------------------------------------------------
CREATE SCHEMA export_test;
GRANT USAGE ON SCHEMA export_test TO anon, authenticated;
CREATE FUNCTION export_test.id(tag text, n integer) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT md5('export-test:' || tag || ':' || n)::uuid $$;

CREATE FUNCTION export_test.load_owner(p_owner uuid, p_tag text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE g integer; k text;
BEGIN
  INSERT INTO public.profiles(id, handle, display_name, email, timezone, referral_code, push_token, referred_by)
    VALUES (p_owner, p_tag || '-handle', p_tag || '-SENTINEL-profile', p_tag || '@example.invalid', 'UTC', 'REF-' || p_tag,
            'SECRET-PUSH-TOKEN-' || p_tag, 'ffffffff-ffff-4fff-8fff-ffffffffffff');
  INSERT INTO public.support_privacy_state(user_id, privacy_revision) VALUES (p_owner, 3);
  INSERT INTO public.support_onboarding_consent VALUES (p_owner, 1990, true, '2026-11-06');
  FOR g IN 1..2 LOOP
    INSERT INTO public.user_settings VALUES (export_test.id(p_tag || '-settings', g), p_owner, 'friendly', true);
    INSERT INTO public.moods(id, user_id, note) VALUES (export_test.id(p_tag || '-moods', g), p_owner, p_tag || '-SENTINEL-mood-' || g);
    INSERT INTO public.quest_templates VALUES (export_test.id(p_tag || '-qt', g), 'Template ' || p_tag || g, 'Shared template', 'mindfulness', 5, 50, false)
      ON CONFLICT DO NOTHING;
    INSERT INTO public.quests VALUES (export_test.id(p_tag || '-quests', g), p_owner, export_test.id(p_tag || '-qt', g), '2026-11-0' || g, 'assigned',
      p_tag || '-SENTINEL-quest-' || g);
    INSERT INTO public.conversations VALUES (export_test.id(p_tag || '-conv', g), p_owner, p_tag || '-SENTINEL-conversation-' || g);
    INSERT INTO public.messages VALUES (export_test.id(p_tag || '-msg', g * 10 + 1), export_test.id(p_tag || '-conv', g), 'user', p_tag || '-SENTINEL-message-u' || g, NULL, NULL);
    INSERT INTO public.messages VALUES (export_test.id(p_tag || '-msg', g * 10 + 2), export_test.id(p_tag || '-conv', g), 'assistant', p_tag || '-SENTINEL-message-a' || g, NULL, 'model');
    INSERT INTO public.circles VALUES (export_test.id(p_tag || '-circle', g), 'Circle ' || p_tag || g, 'Circle description', 'SECRET-INVITE-' || p_tag || g,
      p_owner, now());
    INSERT INTO public.circle_members VALUES (export_test.id(p_tag || '-member', g), export_test.id(p_tag || '-circle', g), p_owner, now(), 'owner');
    INSERT INTO public.exercises VALUES (export_test.id(p_tag || '-ex', g), 'Exercise ' || p_tag || g, 'breathing') ON CONFLICT DO NOTHING;
    INSERT INTO public.exercise_sessions VALUES (export_test.id(p_tag || '-exs', g), p_owner, export_test.id(p_tag || '-ex', g), true, p_tag || '-SENTINEL-exercise-' || g);
    INSERT INTO public.subscriptions VALUES (export_test.id(p_tag || '-sub', g), p_owner, 'product.' || g, 'SECRET-TXN-' || p_tag || g, 'SECRET-LAST-TXN-' || p_tag || g,
      'active', 'individual', 'monthly', export_test.id('family', 1), export_test.id('org', 1), 1, 1);
    INSERT INTO public.crisis_events VALUES (export_test.id(p_tag || '-crisis', g), p_owner, export_test.id(p_tag || '-conv', g), now(), p_tag || '-SENTINEL-crisis-' || g);
    INSERT INTO public.companion_memory VALUES (export_test.id(p_tag || '-cm', g), p_owner, 'preferences', p_tag || '-SENTINEL-curated-' || g,
      CASE WHEN g = 2 THEN now() END, 'user_authored', 1);
    INSERT INTO public.memory_fragments VALUES (export_test.id(p_tag || '-mf', g), p_owner, 'fact', 'k' || g, p_tag || '-SENTINEL-generated-' || g, 'pending',
      export_test.id(p_tag || '-conv', g), export_test.id(p_tag || '-msg', g * 10 + 1));
    INSERT INTO public.support_work_sessions VALUES (export_test.id(p_tag || '-ss', g), p_owner, p_tag || '-SENTINEL-session-' || g, p_tag || '-SENTINEL-concern-' || g, 'open');
    INSERT INTO public.support_activities VALUES (export_test.id(p_tag || '-act', g), p_owner, export_test.id(p_tag || '-ss', g), 'ground_present_v1',
      jsonb_build_object('note', p_tag || '-SENTINEL-activity-' || g));
    INSERT INTO public.support_session_events VALUES (export_test.id(p_tag || '-evt', g), p_owner, export_test.id(p_tag || '-ss', g), 'session_created', g);
    INSERT INTO public.support_mutation_receipts(user_id, operation_id, operation_kind, session_id, payload_hash)
      VALUES (p_owner, export_test.id(p_tag || '-op', g), 'create_session', export_test.id(p_tag || '-ss', g), repeat('a', 64));
    INSERT INTO public.support_proposals VALUES (export_test.id(p_tag || '-prop', g), p_owner, export_test.id(p_tag || '-ss', g), export_test.id(p_tag || '-req', g),
      'choose_step_v1', p_tag || '-SENTINEL-step-' || g);
    INSERT INTO public.support_context_receipts VALUES (export_test.id(p_tag || '-rcpt', g), p_owner, export_test.id(p_tag || '-req', g),
      export_test.id(p_tag || '-conv', g), 'openai');
    FOREACH k IN ARRAY ARRAY['message', 'companion_memory'] LOOP
      INSERT INTO public.support_context_receipt_sources VALUES (export_test.id(p_tag || '-rcpt', g), p_owner, k, export_test.id(p_tag || '-src-' || k, g), 1);
    END LOOP;
    INSERT INTO public.support_privacy_operations(user_id, operation_id, kind, payload_hash)
      VALUES (p_owner, export_test.id(p_tag || '-pop', g), 'forget_memory', repeat('b', 64));
    INSERT INTO public.support_suppressions VALUES (export_test.id(p_tag || '-sup', g), p_owner, 'memory', export_test.id(p_tag || '-cm', g), 'forgotten_memory');
    INSERT INTO public.support_memory_events VALUES (export_test.id(p_tag || '-mev', g), p_owner, 'companion_memory', export_test.id(p_tag || '-cm', g), 'created');
    INSERT INTO public.offline_mutation_receipts(user_id, operation_id, kind, payload_hash)
      VALUES (p_owner, export_test.id(p_tag || '-off', g), 'mood', repeat('c', 64));
    INSERT INTO public.support_memory_suggestion_requests(user_id, request_id, support_session_id, status, payload_hash, source_count)
      VALUES(p_owner, export_test.id(p_tag || '-memreq', g), export_test.id(p_tag || '-ss', g), 'unknown', repeat('e',64), 1);
  END LOOP;
END $$;

SELECT export_test.load_owner('70000000-0000-4000-8000-0000000000aa', 'A');
SELECT export_test.load_owner('70000000-0000-4000-8000-0000000000bb', 'B');
-- Composite identity: the same request UUID belongs to two owners independently.
UPDATE public.support_memory_suggestion_requests SET request_id=export_test.id('A-memreq',1)
WHERE user_id='70000000-0000-4000-8000-0000000000bb' AND request_id=export_test.id('B-memreq',1);

-- Owner A bulk: more than one page in several datasets (moods 250, messages 138 incl. 8 large,
-- offline receipts 130, receipt sources 120 on ONE receipt across all six kinds).
INSERT INTO public.moods(id, user_id, note)
  SELECT export_test.id('A-moods-bulk', g), '70000000-0000-4000-8000-0000000000aa', 'A-SENTINEL-mood-bulk' FROM generate_series(1, 248) g;
INSERT INTO public.messages(id, conversation_id, role, content)
  SELECT export_test.id('A-msg-bulk', g), export_test.id('A-conv', 1), 'user', 'A-SENTINEL-message-bulk-' || g FROM generate_series(1, 126) g;
INSERT INTO public.messages(id, conversation_id, role, content)
  SELECT export_test.id('A-msg-big', g), export_test.id('A-conv', 2), 'user', 'A-SENTINEL-big-' || repeat('x', 40000) FROM generate_series(1, 8) g;
INSERT INTO public.offline_mutation_receipts(user_id, operation_id, kind, payload_hash)
  SELECT '70000000-0000-4000-8000-0000000000aa', export_test.id('A-off-bulk', g), 'quest', repeat('d', 64) FROM generate_series(1, 128) g;
INSERT INTO public.support_memory_suggestion_requests(user_id, request_id, support_session_id, status, payload_hash, source_count)
  SELECT '70000000-0000-4000-8000-0000000000aa', export_test.id('A-memreq-bulk', g), export_test.id('A-ss', 1), 'unknown', repeat('e',64), 1
  FROM generate_series(1,128) g;
INSERT INTO public.support_context_receipt_sources(receipt_id, user_id, source_kind, source_id, source_revision)
  SELECT export_test.id('A-rcpt', 1), '70000000-0000-4000-8000-0000000000aa',
         (ARRAY['message', 'companion_memory', 'daily_intent', 'session', 'activity_result', 'safety_policy'])[1 + (g % 6)],
         export_test.id('A-src-bulk', g), 1 FROM generate_series(1, 116) g;

-- Shared circle owned by B with both accounts as members: A must see only A's membership row.
INSERT INTO public.circles VALUES (export_test.id('shared', 1), 'Shared circle', 'Shared description', 'SECRET-INVITE-SHARED',
  '70000000-0000-4000-8000-0000000000bb', now());
INSERT INTO public.circle_members VALUES (export_test.id('shared-member', 1), export_test.id('shared', 1), '70000000-0000-4000-8000-0000000000aa', now(), 'member');
INSERT INTO public.circle_members VALUES (export_test.id('shared-member', 2), export_test.id('shared', 1), '70000000-0000-4000-8000-0000000000bb', now(), 'owner');

-- Adversarial rows. None may ever be exported to A, and none to B either.
INSERT INTO public.messages(id, conversation_id, role, content) VALUES
  (export_test.id('dangling-msg', 1), export_test.id('no-such-conversation', 1), 'user', 'DANGLING-SENTINEL-1'),
  (export_test.id('dangling-msg', 2), export_test.id('no-such-conversation', 2), 'user', 'DANGLING-SENTINEL-2');
-- A source stamped with A but attached to B's receipt, B's stamp on A's receipt, and a dangling receipt.
INSERT INTO public.support_context_receipt_sources VALUES
  (export_test.id('B-rcpt', 1), '70000000-0000-4000-8000-0000000000aa', 'message', export_test.id('forged', 1), 1),
  (export_test.id('A-rcpt', 2), '70000000-0000-4000-8000-0000000000bb', 'message', export_test.id('forged', 2), 1),
  (export_test.id('no-such-receipt', 1), '70000000-0000-4000-8000-0000000000aa', 'message', export_test.id('forged', 3), 1);

-- Owner C: a single oversized message (300000 chars) then two tiny ones, ids ordered big < small.
SELECT export_test.load_owner('70000000-0000-4000-8000-0000000000cc', 'C');
DELETE FROM public.messages WHERE conversation_id IN (export_test.id('C-conv', 1), export_test.id('C-conv', 2));
INSERT INTO public.messages(id, conversation_id, role, content) VALUES
  ('00000000-0000-4000-8000-000000000001', export_test.id('C-conv', 1), 'user', 'C-SENTINEL-oversized-' || repeat('y', 300000)),
  ('00000000-0000-4000-8000-000000000002', export_test.id('C-conv', 1), 'user', 'C-SENTINEL-small-1'),
  ('00000000-0000-4000-8000-000000000003', export_test.id('C-conv', 1), 'user', 'C-SENTINEL-small-2');

CREATE TABLE export_test.expected(owner_id uuid, dataset text, n integer, PRIMARY KEY (owner_id, dataset));
GRANT SELECT ON export_test.expected TO authenticated;
INSERT INTO export_test.expected(owner_id, dataset, n)
SELECT o.owner_id, d.dataset, CASE
    WHEN o.owner_id = '70000000-0000-4000-8000-0000000000aa' AND d.dataset = 'moods' THEN 250
    WHEN o.owner_id = '70000000-0000-4000-8000-0000000000aa' AND d.dataset = 'messages' THEN 138
    WHEN o.owner_id = '70000000-0000-4000-8000-0000000000aa' AND d.dataset = 'offline_mutation_receipts' THEN 130
    WHEN o.owner_id = '70000000-0000-4000-8000-0000000000aa' AND d.dataset = 'support_memory_suggestion_requests' THEN 130
    WHEN o.owner_id = '70000000-0000-4000-8000-0000000000aa' AND d.dataset = 'support_context_receipt_sources' THEN 120
    WHEN o.owner_id = '70000000-0000-4000-8000-0000000000cc' AND d.dataset = 'messages' THEN 3
    WHEN d.dataset = 'circle_memberships' AND o.owner_id <> '70000000-0000-4000-8000-0000000000cc' THEN 3
    WHEN d.dataset = 'messages' THEN 4
    WHEN d.dataset = 'support_context_receipt_sources' THEN 4
    WHEN d.dataset IN ('profile', 'support_privacy_state', 'support_onboarding_consent') THEN 1
    ELSE 2 END
FROM (VALUES ('70000000-0000-4000-8000-0000000000aa'::uuid), ('70000000-0000-4000-8000-0000000000bb'::uuid),
             ('70000000-0000-4000-8000-0000000000cc'::uuid)) o(owner_id)
CROSS JOIN (VALUES ('profile'), ('user_settings'), ('moods'), ('quests'), ('conversations'), ('messages'),
  ('circle_memberships'), ('exercise_sessions'), ('subscriptions'), ('crisis_events'), ('companion_memories'),
  ('memory_fragments'), ('support_privacy_state'), ('support_sessions'), ('support_activities'),
  ('support_session_events'), ('support_mutation_receipts'), ('support_proposals'), ('support_context_receipts'),
  ('support_context_receipt_sources'), ('support_privacy_operations'), ('support_suppressions'),
  ('support_memory_events'), ('support_onboarding_consent'), ('offline_mutation_receipts'), ('support_memory_suggestion_requests')) d(dataset);

-- Walks every page for one owner/dataset and asserts the page contract on the way.
CREATE FUNCTION export_test.walk(p_owner uuid, p_dataset text, p_limit integer DEFAULT 100) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
  v_after text; v_page jsonb; v_rows jsonb := '[]'::jsonb; v_pages integer := 0; v_prev text; v_row jsonb; v_key text;
  v_count integer; v_bytes integer; v_last text;
BEGIN
  LOOP
    v_page := public.export_owner_data_page(p_owner, p_dataset, v_after, p_limit);
    v_pages := v_pages + 1;
    IF v_pages > 60 THEN RAISE EXCEPTION 'runaway paging for %', p_dataset; END IF;
    IF (v_page->>'catalog_version')::integer <> 1 OR (v_page->>'catalog_size')::integer <> 26
       OR (v_page->>'owner')::uuid <> p_owner OR v_page->>'dataset' <> p_dataset OR v_page->>'status' <> 'available'
       OR (v_page->>'after') IS DISTINCT FROM v_after THEN
      RAISE EXCEPTION 'page envelope inconsistent for %: %', p_dataset, (v_page - 'rows');
    END IF;
    v_count := jsonb_array_length(v_page->'rows');
    IF v_count <> (v_page->>'row_count')::integer OR v_count > p_limit OR v_count > 100 THEN
      RAISE EXCEPTION 'row bound violated for % (% rows)', p_dataset, v_count;
    END IF;
    IF (v_page->'limits'->>'max_rows')::integer <> 100 OR (v_page->'limits'->>'max_page_bytes')::integer <> 262144 THEN
      RAISE EXCEPTION 'limits not reported';
    END IF;
    v_bytes := 0; v_last := NULL;
    FOR v_row IN SELECT value FROM jsonb_array_elements(v_page->'rows') LOOP
      v_key := v_row->>'export_key';
      IF v_key IS NULL OR (v_row->>'export_owner_id') IS DISTINCT FROM p_owner::text THEN
        RAISE EXCEPTION 'row owner/key missing or foreign in %', p_dataset;
      END IF;
      IF v_prev IS NOT NULL AND NOT (v_key COLLATE "C" > v_prev COLLATE "C") THEN
        RAISE EXCEPTION 'keys not strictly ascending in %: % then %', p_dataset, v_prev, v_key;
      END IF;
      v_prev := v_key; v_last := v_key;
      v_bytes := v_bytes + octet_length(v_row::text);
    END LOOP;
    IF v_count > 1 AND v_bytes > 262144 THEN RAISE EXCEPTION 'byte bound violated for % (% bytes)', p_dataset, v_bytes; END IF;
    IF (v_page->>'has_more')::boolean THEN
      IF v_count < 1 OR (v_page->>'next_cursor') IS DISTINCT FROM v_last THEN
        RAISE EXCEPTION 'next_cursor is not the last returned key in %', p_dataset;
      END IF;
    ELSIF (v_page->'next_cursor') <> 'null'::jsonb THEN
      RAISE EXCEPTION 'next_cursor present without has_more in %', p_dataset;
    END IF;
    v_rows := v_rows || (v_page->'rows');
    EXIT WHEN NOT (v_page->>'has_more')::boolean;
    v_after := v_page->>'next_cursor';
  END LOOP;
  RETURN jsonb_build_object('rows', v_rows, 'pages', v_pages);
END $$;

GRANT EXECUTE ON FUNCTION export_test.walk(uuid, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION export_test.id(text, integer) TO authenticated, anon;

-- Capture the before-state that the migration and every export call must leave untouched.
CREATE FUNCTION export_test.fingerprint() RETURNS text LANGUAGE plpgsql AS $$
DECLARE t record; r text; acc text := '';
BEGIN
  FOR t IN SELECT c.relname, c.relacl::text AS acl, c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public' AND c.relkind = 'r' ORDER BY c.relname LOOP
    EXECUTE format('SELECT coalesce(sum(hashtext(x::text)::numeric), 0)::text FROM public.%I x', t.relname) INTO r;
    acc := acc || t.relname || ':' || r || ':' || coalesce(t.acl, '-') || ':' || t.relrowsecurity::text || ';';
  END LOOP;
  RETURN md5(acc || (SELECT coalesce(string_agg(polrelid::regclass::text || polname, ',' ORDER BY polrelid::regclass::text, polname), '') FROM pg_policy));
END $$;
CREATE TEMP TABLE export_before AS SELECT export_test.fingerprint() AS fp;

\ir ../migrations/20261107040000_support_data_export.sql

-- ---------------------------------------------------------------------------
-- Function posture: definer, read-only (STABLE), pinned search_path/timeout, no anon/PUBLIC execute.
-- ---------------------------------------------------------------------------
DO $$ DECLARE f pg_proc%ROWTYPE; BEGIN
  SELECT * INTO STRICT f FROM pg_proc WHERE oid = 'public.export_owner_data_page(uuid,text,text,integer)'::regprocedure;
  IF NOT f.prosecdef OR f.provolatile <> 's' OR f.prorettype <> 'jsonb'::regtype THEN RAISE EXCEPTION 'Function must be STABLE SECURITY DEFINER jsonb'; END IF;
  IF NOT ('search_path=""' = ANY (f.proconfig) OR 'search_path=' = ANY (f.proconfig)) THEN RAISE EXCEPTION 'search_path not pinned empty: %', f.proconfig; END IF;
  IF NOT EXISTS (SELECT 1 FROM unnest(f.proconfig) c WHERE c LIKE 'statement_timeout=%') THEN RAISE EXCEPTION 'statement_timeout not pinned'; END IF;
  IF has_function_privilege('anon', f.oid, 'EXECUTE') OR has_function_privilege('public', f.oid, 'EXECUTE')
     OR NOT has_function_privilege('authenticated', f.oid, 'EXECUTE') THEN RAISE EXCEPTION 'Wrong EXECUTE grants'; END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname LIKE 'export\_%') <> 1 THEN RAISE EXCEPTION 'Migration must add exactly one public function'; END IF;
END $$;

-- Migration changed no table, row, ACL, RLS flag or policy.
DO $$ BEGIN
  IF export_test.fingerprint() IS DISTINCT FROM (SELECT fp FROM export_before) THEN RAISE EXCEPTION 'Migration changed data, grants or policies'; END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Refusals
-- ---------------------------------------------------------------------------
SET ROLE anon;
SELECT set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-0000000000aa', false);
DO $$ BEGIN
  BEGIN
    PERFORM public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', 'moods', NULL, 100);
    RAISE EXCEPTION 'anon executed the export';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;

SET ROLE authenticated;
-- The export must not depend on any table grant, and direct table reads stay closed.
SELECT set_config('request.jwt.claim.sub', '', false);
DO $$ BEGIN
  BEGIN
    PERFORM public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', 'moods', NULL, 100);
    RAISE EXCEPTION 'No principal was accepted';
  EXCEPTION WHEN SQLSTATE '28000' THEN NULL; END;
END $$;
SELECT set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-0000000000aa', false);
DO $$ BEGIN
  BEGIN
    PERFORM count(*) FROM public.support_mutation_receipts;
    RAISE EXCEPTION 'authenticated can read an internal table directly';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  -- Wrong expected owner (account switched) reads nothing, for every dataset.
  BEGIN
    PERFORM public.export_owner_data_page('70000000-0000-4000-8000-0000000000bb', 'messages', NULL, 100);
    RAISE EXCEPTION 'Foreign expected owner was accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.export_owner_data_page(NULL, 'messages', NULL, 100);
    RAISE EXCEPTION 'NULL expected owner was accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  -- Unknown, injected, schema-qualified, wrong-case and empty dataset names are not SQL and not accepted.
  FOR i IN 1..6 LOOP
    BEGIN
      PERFORM public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa',
        (ARRAY['moods; DROP TABLE public.moods', 'public.moods', 'MOODS', '', 'pg_catalog.pg_authid', 'support_template_catalog'])[i], NULL, 100);
      RAISE EXCEPTION 'Unlisted dataset % was accepted', i;
    EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  END LOOP;
  BEGIN PERFORM public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', NULL, NULL, 100);
    RAISE EXCEPTION 'NULL dataset accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  -- Page size is rejected, never clamped.
  FOR i IN 1..4 LOOP
    BEGIN
      PERFORM public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', 'moods', NULL, (ARRAY[0, 101, -1, 100000])[i]);
      RAISE EXCEPTION 'Page size % accepted', i;
    EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  END LOOP;
  BEGIN PERFORM public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', 'moods', NULL, NULL);
    RAISE EXCEPTION 'NULL page size accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  -- Cursor shape: only a canonical lowercase uuid (or the composite receipt-source key) is accepted.
  FOR i IN 1..5 LOOP
    BEGIN
      PERFORM public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', 'moods',
        (ARRAY['not-a-uuid', '70000000-0000-4000-8000-0000000000AA', '00000000-0000-0000-0000-000000000000''; select 1', '', ' '])[i], 100);
      RAISE EXCEPTION 'Cursor % accepted', i;
    EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  END LOOP;
  FOR i IN 1..4 LOOP
    BEGIN
      PERFORM public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', 'support_context_receipt_sources',
        (ARRAY['70000000-0000-4000-8000-0000000000aa', 'x:message:70000000-0000-4000-8000-0000000000aa',
               '70000000-0000-4000-8000-0000000000aa:MESSAGE:70000000-0000-4000-8000-0000000000aa',
               '70000000-0000-4000-8000-0000000000aa:message:70000000-0000-4000-8000-0000000000aa:extra'])[i], 100);
      RAISE EXCEPTION 'Source cursor % accepted', i;
    EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- Every dataset, every owner: exact counts, only the owner's rows, no secret, no unrelated user.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  e record; w jsonb; owners uuid[] := ARRAY['70000000-0000-4000-8000-0000000000aa', '70000000-0000-4000-8000-0000000000bb', '70000000-0000-4000-8000-0000000000cc']::uuid[];
  o uuid; txt text; tag text;
BEGIN
  FOREACH o IN ARRAY owners LOOP
    PERFORM set_config('request.jwt.claim.sub', o::text, false);
    tag := CASE o WHEN owners[1] THEN 'A' WHEN owners[2] THEN 'B' ELSE 'C' END;
    txt := '';
    FOR e IN SELECT dataset, n FROM export_test.expected WHERE owner_id = o ORDER BY dataset LOOP
      w := export_test.walk(o, e.dataset, 100);
      IF jsonb_array_length(w->'rows') <> e.n THEN
        RAISE EXCEPTION 'owner % dataset %: expected % rows, got %', tag, e.dataset, e.n, jsonb_array_length(w->'rows');
      END IF;
      IF (SELECT count(DISTINCT r->>'export_key') FROM jsonb_array_elements(w->'rows') r) <> e.n THEN
        RAISE EXCEPTION 'owner % dataset %: duplicate keys across pages', tag, e.dataset;
      END IF;
      IF e.n > 100 AND (w->>'pages')::integer < 2 THEN RAISE EXCEPTION 'dataset % did not paginate', e.dataset; END IF;
      txt := txt || (w->>'rows');
    END LOOP;
    IF txt LIKE '%SECRET-%' OR txt LIKE '%push_token%' OR txt LIKE '%referred_by%' OR txt LIKE '%invite_code%'
       OR txt LIKE '%original_transaction_id%' OR txt LIKE '%last_transaction_id%' OR txt LIKE '%family_id%'
       OR txt LIKE '%organization_id%' OR txt LIKE '%ffffffff-ffff-4fff-8fff-ffffffffffff%' OR txt LIKE '%DANGLING-SENTINEL%' THEN
      RAISE EXCEPTION 'Owner % export contains a secret, an unrelated-user identifier or a dangling row', tag;
    END IF;
    IF tag <> 'A' AND txt LIKE '%A-SENTINEL%' THEN RAISE EXCEPTION 'Owner % received owner A content', tag; END IF;
    IF tag <> 'B' AND txt LIKE '%B-SENTINEL%' THEN RAISE EXCEPTION 'Owner % received owner B content', tag; END IF;
    IF tag <> 'C' AND txt LIKE '%C-SENTINEL%' THEN RAISE EXCEPTION 'Owner % received owner C content', tag; END IF;
    IF txt NOT LIKE '%' || tag || '-SENTINEL-mood%' OR txt NOT LIKE '%' || tag || '-SENTINEL-concern%'
       OR txt NOT LIKE '%' || tag || '-SENTINEL-generated%' OR txt NOT LIKE '%' || tag || '-SENTINEL-curated%' THEN
      RAISE EXCEPTION 'Owner % is missing its own content', tag;
    END IF;
  END LOOP;
END $$;

-- Exact 100 / 100 / 50 split for 250 moods, and a stable resume from the server cursor.
SELECT set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-0000000000aa', false);
DO $$
DECLARE p1 jsonb; p2 jsonb; p3 jsonb; p4 jsonb;
BEGIN
  p1 := public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', 'moods', NULL, 100);
  p2 := public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', 'moods', p1->>'next_cursor', 100);
  p3 := public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', 'moods', p2->>'next_cursor', 100);
  IF (p1->>'row_count')::integer <> 100 OR (p2->>'row_count')::integer <> 100 OR (p3->>'row_count')::integer <> 50
     OR NOT (p1->>'has_more')::boolean OR NOT (p2->>'has_more')::boolean OR (p3->>'has_more')::boolean
     OR (p3->'next_cursor') <> 'null'::jsonb THEN RAISE EXCEPTION 'moods did not split 100/100/50'; END IF;
  IF (p1->'rows'->99->>'export_key') <> (p1->>'next_cursor') OR (p2->'rows'->0->>'export_key') COLLATE "C" <= (p1->>'next_cursor') COLLATE "C" THEN
    RAISE EXCEPTION 'cursor is not a strict keyset boundary';
  END IF;
  -- Resuming from the same cursor again returns the identical page (stable ordering, no state kept server-side).
  IF public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', 'moods', p1->>'next_cursor', 100) IS DISTINCT FROM p2 THEN
    RAISE EXCEPTION 'resume is not stable';
  END IF;
  -- A smaller requested page is honoured exactly.
  IF (public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', 'moods', NULL, 7)->>'row_count')::integer <> 7 THEN RAISE EXCEPTION 'limit 7'; END IF;
  -- A well-formed cursor beyond the last row is an empty final page, not an error and not a restart.
  p4 := public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', 'moods', 'ffffffff-ffff-ffff-ffff-ffffffffffff', 100);
  IF (p4->>'row_count')::integer <> 0 OR (p4->>'has_more')::boolean OR p4->>'status' <> 'available' THEN RAISE EXCEPTION 'cursor past the end'; END IF;
  -- Another owner's id used as a cursor cannot widen what A sees (A has no row owned by B at any key).
  p4 := public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', 'moods', export_test.id('B-moods', 1)::text, 100);
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p4->'rows') r WHERE r->>'export_owner_id' <> '70000000-0000-4000-8000-0000000000aa') THEN
    RAISE EXCEPTION 'foreign cursor widened the export';
  END IF;
END $$;

-- Byte bound: 8 messages of ~40 KB each cannot all be in one page; every page stays under the cap.
DO $$
DECLARE page jsonb; after text; seen integer := 0; bytes integer; r jsonb;
BEGIN
  LOOP
    page := public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', 'messages', after, 100);
    bytes := 0;
    FOR r IN SELECT value FROM jsonb_array_elements(page->'rows') LOOP
      bytes := bytes + octet_length(r::text);
      IF r->>'content' LIKE 'A-SENTINEL-big-%' THEN seen := seen + 1; END IF;
    END LOOP;
    IF (page->>'row_count')::integer > 1 AND bytes > 262144 THEN RAISE EXCEPTION 'page of % bytes', bytes; END IF;
    EXIT WHEN NOT (page->>'has_more')::boolean;
    after := page->>'next_cursor';
  END LOOP;
  IF seen <> 8 THEN RAISE EXCEPTION 'large messages lost: %', seen; END IF;
END $$;

-- Progress on one oversized row: owner C's first row alone exceeds the cap; it is returned alone, then the rest.
SELECT set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-0000000000cc', false);
DO $$
DECLARE p1 jsonb; p2 jsonb;
BEGIN
  p1 := public.export_owner_data_page('70000000-0000-4000-8000-0000000000cc', 'messages', NULL, 100);
  IF (p1->>'row_count')::integer <> 1 OR NOT (p1->>'has_more')::boolean
     OR octet_length(p1->'rows'->>0) <= 262144 THEN RAISE EXCEPTION 'oversized first row was not returned alone'; END IF;
  p2 := public.export_owner_data_page('70000000-0000-4000-8000-0000000000cc', 'messages', p1->>'next_cursor', 100);
  IF (p2->>'row_count')::integer <> 2 OR (p2->>'has_more')::boolean THEN RAISE EXCEPTION 'rest after oversized row'; END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Internal ownership and allowlists (as owner A)
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-0000000000aa', false);
DO $$
DECLARE w jsonb; k text;
BEGIN
  -- Forged source rows (A-stamped on B's receipt, B-stamped on A's receipt, dangling) are absent for both owners.
  w := export_test.walk('70000000-0000-4000-8000-0000000000aa', 'support_context_receipt_sources', 7);
  IF jsonb_array_length(w->'rows') <> 120 OR (w->>'rows') LIKE '%' || export_test.id('forged', 1)::text || '%'
     OR (w->>'rows') LIKE '%' || export_test.id('forged', 2)::text || '%' OR (w->>'rows') LIKE '%' || export_test.id('forged', 3)::text || '%' THEN
    RAISE EXCEPTION 'receipt-source ownership is not resolved through the receipt';
  END IF;
  -- Composite order is receipt id, then kind, then source id, and survives a tiny page size.
  IF (w->'pages')::integer <> 18 THEN RAISE EXCEPTION 'expected 18 pages of <=7, got %', w->'pages'; END IF;
  -- Messages are owned only through their conversation: no dangling or foreign-conversation message.
  w := export_test.walk('70000000-0000-4000-8000-0000000000aa', 'messages', 100);
  IF (w->>'rows') LIKE '%DANGLING%' OR (w->>'rows') LIKE '%B-SENTINEL%' THEN RAISE EXCEPTION 'message ownership leak'; END IF;
  -- Profile: allowlist only. Subscription: allowlist only. Circle: owner's membership and descriptive fields only.
  w := export_test.walk('70000000-0000-4000-8000-0000000000aa', 'profile', 100);
  IF (w->'rows'->0) ? 'push_token' OR (w->'rows'->0) ? 'referred_by' OR NOT ((w->'rows'->0) ? 'display_name') THEN RAISE EXCEPTION 'profile allowlist'; END IF;
  w := export_test.walk('70000000-0000-4000-8000-0000000000aa', 'subscriptions', 100);
  IF (w->'rows'->0) ? 'original_transaction_id' OR (w->'rows'->0) ? 'last_transaction_id' OR (w->'rows'->0) ? 'family_id'
     OR (w->'rows'->0) ? 'organization_id' OR NOT ((w->'rows'->0) ? 'product_id') THEN RAISE EXCEPTION 'subscription allowlist'; END IF;
  w := export_test.walk('70000000-0000-4000-8000-0000000000aa', 'circle_memberships', 100);
  IF jsonb_array_length(w->'rows') <> 3 OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(w->'rows') r
       WHERE r->>'user_id' <> '70000000-0000-4000-8000-0000000000aa' OR (r->'circle') ? 'invite_code' OR (r->'circle') ? 'owner_id') THEN
    RAISE EXCEPTION 'circle membership leak';
  END IF;
  -- Joined catalog descriptions are present for quests and exercises; soft-deleted curated memory stays visible with its flag.
  w := export_test.walk('70000000-0000-4000-8000-0000000000aa', 'quests', 100);
  IF NOT (w->'rows'->0->'template' ? 'title') THEN RAISE EXCEPTION 'quest template missing'; END IF;
  w := export_test.walk('70000000-0000-4000-8000-0000000000aa', 'companion_memories', 100);
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(w->'rows') r WHERE r->>'deleted_at' IS NOT NULL) THEN RAISE EXCEPTION 'soft-deleted memory hidden'; END IF;
  -- Provenance/review/suppression metadata is preserved as stored.
  w := export_test.walk('70000000-0000-4000-8000-0000000000aa', 'memory_fragments', 100);
  IF NOT (w->'rows'->0 ? 'review_state' AND w->'rows'->0 ? 'source_message_id' AND w->'rows'->0 ? 'source_conversation_id') THEN RAISE EXCEPTION 'fragment provenance dropped'; END IF;
  w := export_test.walk('70000000-0000-4000-8000-0000000000aa', 'support_suppressions', 100);
  IF NOT (w->'rows'->0 ? 'reason' AND w->'rows'->0 ? 'ref_id') THEN RAISE EXCEPTION 'suppression ledger dropped'; END IF;
END $$;
RESET ROLE;

-- ---------------------------------------------------------------------------
-- Absent optional domain is explicit `unavailable`, never an empty successful dataset (rolled back).
-- ---------------------------------------------------------------------------
BEGIN;
DROP TABLE public.offline_mutation_receipts;
DROP TABLE public.support_memory_suggestion_requests;
DROP TABLE public.quest_templates;  -- a joined catalog counts: quests cannot be exported faithfully without it
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-0000000000aa', true);
DO $$
DECLARE p jsonb;
BEGIN
  p := public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', 'offline_mutation_receipts', NULL, 100);
  IF p->>'status' <> 'unavailable' OR p->>'reason' <> 'table_absent' OR jsonb_array_length(p->'rows') <> 0
     OR (p->>'row_count')::integer <> 0 OR (p->>'has_more')::boolean OR (p->>'catalog_size')::integer <> 26 THEN
    RAISE EXCEPTION 'absent table was not reported as unavailable: %', p;
  END IF;
  p := public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', 'support_memory_suggestion_requests', NULL, 100);
  IF p->>'status' <> 'unavailable' OR p->>'reason' <> 'table_absent' OR jsonb_array_length(p->'rows') <> 0 THEN
    RAISE EXCEPTION 'absent memory request table must make export explicitly incomplete';
  END IF;
  p := public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', 'quests', NULL, 100);
  IF p->>'status' <> 'unavailable' THEN RAISE EXCEPTION 'quests without its catalog table must be unavailable'; END IF;
  p := public.export_owner_data_page('70000000-0000-4000-8000-0000000000aa', 'moods', NULL, 100);
  IF p->>'status' <> 'available' THEN RAISE EXCEPTION 'unrelated datasets must be unaffected'; END IF;
END $$;
RESET ROLE;
ROLLBACK;

-- ---------------------------------------------------------------------------
-- Nothing the export did changed any row, grant, RLS flag or policy.
-- ---------------------------------------------------------------------------
DO $$ BEGIN
  IF export_test.fingerprint() IS DISTINCT FROM (SELECT fp FROM export_before) THEN
    RAISE EXCEPTION 'Export calls changed data, grants or policies';
  END IF;
END $$;

SELECT 'support_data_export synthetic fixture: all assertions passed' AS result;
