-- Local synthetic database only; every fixture and helper is rolled back.
-- Run after the narrow_sql_authorization migration, using the network-none
-- mindfriend-restoration-20261022 container, database restoration_synthetic,
-- role supabase_admin and the local-synthetic-only password. Use psql -X
-- -v ON_ERROR_STOP=1 -f ...; any exception is a failed check.
-- No cron jobs or successful secret reads are executed.
\set ON_ERROR_STOP on
BEGIN;

DO $test$
BEGIN
  IF current_database() <> 'restoration_synthetic' OR current_user <> 'supabase_admin' THEN
    RAISE EXCEPTION 'Run only as supabase_admin in restoration_synthetic';
  END IF;
  IF EXISTS (SELECT 1 FROM auth.users) OR EXISTS (SELECT 1 FROM public.profiles) THEN
    RAISE EXCEPTION 'Requires an empty schema-only database; refusing existing user records';
  END IF;
END;
$test$;

CREATE TEMP TABLE internal_rpc_cases(signature text PRIMARY KEY, call_sql text NOT NULL);
INSERT INTO internal_rpc_cases VALUES
  ('public.add_family_member(uuid,uuid,text,text,text)', 'SELECT public.add_family_member(''fa100000-0000-0000-0000-000000000099''::uuid, ''fa100000-0000-0000-0000-000000000002''::uuid, ''parent'', NULL::text, NULL::text)'),
  ('public.get_cron_secret()', 'SELECT public.get_cron_secret()'),
  ('public.get_moods_for_pattern_analysis(uuid,integer)', 'SELECT * FROM public.get_moods_for_pattern_analysis(''fa100000-0000-0000-0000-000000000002''::uuid, 4)'),
  ('public.get_pending_notifications(integer)', 'SELECT * FROM public.get_pending_notifications(1)'),
  ('public.get_streak_at_risk_users(integer)', 'SELECT * FROM public.get_streak_at_risk_users(20)'),
  ('public.get_users_for_weekly_summary()', 'SELECT * FROM public.get_users_for_weekly_summary()'),
  ('public.claim_family_seat(uuid,uuid,text)', 'SELECT public.claim_family_seat(''fa100000-0000-0000-0000-000000000099''::uuid, ''fa100000-0000-0000-0000-000000000002''::uuid, NULL::text)'),
  ('public.release_family_seat(uuid,uuid)', 'SELECT public.release_family_seat(''fa100000-0000-0000-0000-000000000099''::uuid, ''fa100000-0000-0000-0000-000000000002''::uuid)'),
  ('public.submit_pathway_checkin(uuid,jsonb,text[],text)', 'SELECT public.submit_pathway_checkin(''fa100000-0000-0000-0000-000000000099''::uuid, ''{}''::jsonb, ''{}''::text[], NULL::text)'),
  ('public.submit_pathway_checkin(uuid,jsonb,text[],text,text,text)', 'SELECT public.submit_pathway_checkin(''fa100000-0000-0000-0000-000000000099''::uuid, ''{}''::jsonb, ''{}''::text[], NULL::text, NULL::text, NULL::text)'),
  ('public.check_rate_limit(uuid,text,timestamp with time zone,integer,integer)', 'SELECT * FROM public.check_rate_limit(''fa100000-0000-0000-0000-000000000002''::uuid, ''sql-authorization-test'', now(), 3, 60000)'),
  ('public.check_capacity_rate_limit(uuid,bigint,integer)', 'SELECT public.check_capacity_rate_limit(''fa100000-0000-0000-0000-000000000002''::uuid, 60000::bigint, 3)'),
  ('public.check_and_increment_synthesis_quota(uuid,boolean)', 'SELECT * FROM public.check_and_increment_synthesis_quota(''fa100000-0000-0000-0000-000000000002''::uuid, false)'),
  ('public.check_and_increment_synthesis_quota(uuid,boolean,integer)', 'SELECT * FROM public.check_and_increment_synthesis_quota(''fa100000-0000-0000-0000-000000000002''::uuid, false, 0)'),
  ('public.update_premium_shields(uuid,boolean)', 'SELECT public.update_premium_shields(''fa100000-0000-0000-0000-000000000002''::uuid, true)');
-- The shorter overloads overlap defaulted longer variants. Check their ACLs
-- by exact regprocedure OID below; exercise full-arity calls at runtime so
-- dispatch ambiguity cannot be mistaken for an authorization denial.
ALTER TABLE internal_rpc_cases ADD COLUMN runtime_callable boolean NOT NULL DEFAULT true;
UPDATE internal_rpc_cases SET runtime_callable = false WHERE signature IN (
  'public.submit_pathway_checkin(uuid,jsonb,text[],text)',
  'public.check_and_increment_synthesis_quota(uuid,boolean)'
);
GRANT SELECT ON internal_rpc_cases TO anon, authenticated, service_role;
DO $$ BEGIN
  EXECUTE format('GRANT USAGE ON SCHEMA %I TO anon, authenticated, service_role',
    (SELECT nspname FROM pg_namespace WHERE oid=pg_my_temp_schema()));
END $$;

CREATE FUNCTION pg_temp.require(p_condition boolean, p_label text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
BEGIN
  IF p_condition IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: %', p_label;
  END IF;
END;
$$;

CREATE FUNCTION pg_temp.expect_denied(p_sql text) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp AS $$
DECLARE
  v_denied boolean := false;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  PERFORM pg_temp.require(v_denied, 'Expected SQLSTATE 42501: ' || p_sql);
END;
$$;

GRANT EXECUTE ON FUNCTION pg_temp.require(boolean, text), pg_temp.expect_denied(text)
TO anon, authenticated, service_role;

-- ACL checks inspect every exact overload, including inherited PUBLIC access.
DO $test$
DECLARE
  v_case record;
  v_proc record;
BEGIN
  FOR v_case IN SELECT * FROM internal_rpc_cases LOOP
    SELECT * INTO STRICT v_proc FROM pg_catalog.pg_proc
      WHERE oid = to_regprocedure(v_case.signature);
    PERFORM pg_temp.require(NOT has_function_privilege('anon', v_proc.oid, 'EXECUTE'),
      'anon denied ' || v_case.signature);
    PERFORM pg_temp.require(NOT has_function_privilege('authenticated', v_proc.oid, 'EXECUTE'),
      'authenticated denied ' || v_case.signature);
    PERFORM pg_temp.require(has_function_privilege('service_role', v_proc.oid, 'EXECUTE'),
      'service execute ' || v_case.signature);
    PERFORM pg_temp.require(has_function_privilege(v_proc.proowner, v_proc.oid, 'EXECUTE'),
      'definer owner execute ' || v_case.signature);
    PERFORM pg_temp.require(NOT EXISTS (
      SELECT 1 FROM aclexplode(coalesce(v_proc.proacl, acldefault('f', v_proc.proowner))) a
      WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE'
    ), 'PUBLIC denied ' || v_case.signature);
    PERFORM pg_temp.require(CASE
      WHEN v_case.signature = 'public.check_rate_limit(uuid,text,timestamp with time zone,integer,integer)'
        THEN 'search_path=""' = ANY(v_proc.proconfig)
      ELSE 'search_path=pg_catalog, public, pg_temp' = ANY(v_proc.proconfig)
      END,
      'safe search path ' || v_case.signature);
  END LOOP;
END;
$test$;

-- Create exactly two synthetic principals. The auth trigger may create the
-- profiles/settings/stats; explicit inserts also support schema-only restores.
INSERT INTO auth.users (id, email, raw_app_meta_data, raw_user_meta_data)
VALUES
  ('fa100000-0000-0000-0000-000000000001', 'sql-owner-a@example.invalid', '{}', '{}'),
  ('fa100000-0000-0000-0000-000000000002', 'sql-owner-b@example.invalid', '{}', '{}');
INSERT INTO public.profiles (id, email, display_name, handle, timezone)
VALUES
  ('fa100000-0000-0000-0000-000000000001', 'sql-owner-a@example.invalid', 'Synthetic A', 'sql_auth_a', 'UTC'),
  ('fa100000-0000-0000-0000-000000000002', 'sql-owner-b@example.invalid', 'Synthetic B', 'sql_auth_b', 'UTC')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.user_stats (user_id)
VALUES ('fa100000-0000-0000-0000-000000000001'), ('fa100000-0000-0000-0000-000000000002')
ON CONFLICT (user_id) DO NOTHING;
INSERT INTO public.user_patterns (user_id, pattern_type, pattern_key, pattern_data, confidence)
VALUES ('fa100000-0000-0000-0000-000000000002', 'signature_stress_trigger', 'synthetic_marker', '{}', 0.8);

INSERT INTO public.couples_exercises
  (id, title, description, category, duration_minutes, instructions)
VALUES ('fa100000-0000-0000-0000-000000000010', 'Synthetic', 'SQL fixture', 'breathing', 1, '{}');
INSERT INTO public.partner_links (id, user_id_1, user_id_2, created_by, status)
VALUES ('fa100000-0000-0000-0000-000000000011',
  'fa100000-0000-0000-0000-000000000001', 'fa100000-0000-0000-0000-000000000002',
  'fa100000-0000-0000-0000-000000000001', 'active');
-- A completed session satisfies the existing rating_requires_completion rule.
INSERT INTO public.couples_exercise_sessions
  (id, partner_link_id, exercise_id, user_id_1, user_id_2, status, user_1_rating, user_2_rating)
VALUES ('fa100000-0000-0000-0000-000000000012', 'fa100000-0000-0000-0000-000000000011',
  'fa100000-0000-0000-0000-000000000010', 'fa100000-0000-0000-0000-000000000001',
  'fa100000-0000-0000-0000-000000000002', 'completed', 3, 3);

INSERT INTO public.forum_categories (id, name)
VALUES ('fa100000-0000-0000-0000-000000000020', 'Synthetic category');
INSERT INTO public.forum_boards (id, category_id, name)
VALUES ('fa100000-0000-0000-0000-000000000021', 'fa100000-0000-0000-0000-000000000020', 'Synthetic board');
INSERT INTO public.forum_threads (id, board_id, author_id, title, content, status)
VALUES ('fa100000-0000-0000-0000-000000000022', 'fa100000-0000-0000-0000-000000000021',
  'fa100000-0000-0000-0000-000000000002', 'Synthetic thread', 'SQL fixture', 'pending');
INSERT INTO public.forum_reports (id, reporter_id, thread_id, reason)
VALUES ('fa100000-0000-0000-0000-000000000023', 'fa100000-0000-0000-0000-000000000002',
  'fa100000-0000-0000-0000-000000000022', 'other');

-- Exercise an owner-run SECURITY DEFINER caller after revoking browser roles.
CREATE FUNCTION pg_temp.internal_definer_probe() RETURNS bigint
LANGUAGE sql SECURITY DEFINER SET search_path TO pg_catalog, public, pg_temp AS $$
  SELECT count(*) FROM public.get_moods_for_pattern_analysis('fa100000-0000-0000-0000-000000000002'::uuid, 4);
$$;
GRANT EXECUTE ON FUNCTION pg_temp.internal_definer_probe() TO authenticated;

SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claim.sub', '', true),
       set_config('request.jwt.claim.role', 'anon', true),
       set_config('request.jwt.claims', '{"role":"anon"}', true);
DO $test$
DECLARE v_case record;
BEGIN
  FOR v_case IN SELECT * FROM pg_temp.internal_rpc_cases WHERE runtime_callable LOOP
    PERFORM pg_temp.expect_denied(v_case.call_sql);
  END LOOP;
END;
$test$;
SELECT pg_temp.expect_denied($sql$SELECT public.get_stress_signature('fa100000-0000-0000-0000-000000000002'::uuid)$sql$);
SELECT pg_temp.expect_denied($sql$SELECT public.get_stress_signature(NULL::uuid)$sql$);
-- A role string in request claims cannot substitute for the actual SQL role.
SELECT set_config('request.jwt.claim.role', 'service_role', true),
       set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT pg_temp.expect_denied($sql$SELECT public.get_stress_signature('fa100000-0000-0000-0000-000000000002'::uuid)$sql$);
SELECT pg_temp.expect_denied($sql$SELECT public.update_session_rating('fa100000-0000-0000-0000-000000000012'::uuid, 'fa100000-0000-0000-0000-000000000002'::uuid, 5, 'forged')$sql$);
SELECT pg_temp.require(public.is_moderator() = false, 'anonymous moderator denied');
RESET ROLE;

-- A missing identity under the authenticated SQL role must also fail closed.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', true),
       set_config('request.jwt.claims', '{"role":"authenticated"}', true);
SELECT pg_temp.expect_denied($sql$SELECT public.get_stress_signature('fa100000-0000-0000-0000-000000000002'::uuid)$sql$);
SELECT pg_temp.expect_denied($sql$SELECT public.update_session_rating('fa100000-0000-0000-0000-000000000012'::uuid, 'fa100000-0000-0000-0000-000000000002'::uuid, 5, 'missing identity')$sql$);

SELECT set_config('request.jwt.claim.sub', 'fa100000-0000-0000-0000-000000000001', true),
       set_config('request.jwt.claims', '{"role":"authenticated","sub":"fa100000-0000-0000-0000-000000000001","user_metadata":{"role":"moderator"},"app_metadata":{}}', true);
DO $test$
DECLARE v_case record;
BEGIN
  FOR v_case IN SELECT * FROM pg_temp.internal_rpc_cases WHERE runtime_callable LOOP
    PERFORM pg_temp.expect_denied(v_case.call_sql);
  END LOOP;
END;
$test$;
SELECT pg_temp.expect_denied($sql$SELECT public.get_stress_signature('fa100000-0000-0000-0000-000000000002'::uuid)$sql$);
SELECT pg_temp.expect_denied($sql$SELECT public.get_stress_signature(NULL::uuid)$sql$);
SELECT pg_temp.expect_denied($sql$SELECT public.update_session_rating('fa100000-0000-0000-0000-000000000012'::uuid, 'fa100000-0000-0000-0000-000000000002'::uuid, 5, 'impersonated partner')$sql$);
SELECT pg_temp.require(public.is_moderator() = false, 'editable user_metadata cannot grant moderator');
SELECT pg_temp.require((SELECT count(*) = 0 FROM public.forum_reports), 'forged moderator cannot read reports');
DO $test$
DECLARE v_count integer;
BEGIN
  UPDATE public.forum_reports SET status = 'reviewed'
  WHERE id = 'fa100000-0000-0000-0000-000000000023';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  PERFORM pg_temp.require(v_count = 0, 'forged moderator cannot update reports');
END;
$test$;
SELECT pg_temp.require((public.update_session_rating('fa100000-0000-0000-0000-000000000012',
  'fa100000-0000-0000-0000-000000000001', 4, 'owner a')).user_1_rating = 4, 'owner can rate own side');
SELECT pg_temp.require(pg_temp.internal_definer_probe() = 0, 'definer owner can call internal RPC');

-- Server-issued moderator role continues to drive the existing forum policies.
SELECT set_config('request.jwt.claims', '{"role":"authenticated","sub":"fa100000-0000-0000-0000-000000000001","app_metadata":{"role":"moderator"},"user_metadata":{}}', true);
SELECT pg_temp.require(public.is_moderator() = true, 'app_metadata moderator recognized');
SELECT pg_temp.require((SELECT count(*) = 1 FROM public.forum_reports), 'server moderator can read reports');
DO $test$
DECLARE v_count integer;
BEGIN
  UPDATE public.forum_reports SET status = 'reviewed'
  WHERE id = 'fa100000-0000-0000-0000-000000000023';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  PERFORM pg_temp.require(v_count = 1, 'server moderator can update reports');
END;
$test$;

-- Owner B retains the direct iOS signature read and own-session rating.
SELECT set_config('request.jwt.claim.sub', 'fa100000-0000-0000-0000-000000000002', true),
       set_config('request.jwt.claims', '{"role":"authenticated","sub":"fa100000-0000-0000-0000-000000000002"}', true);
SELECT pg_temp.require(public.is_moderator() = false, 'missing app role is not moderator');
SELECT pg_temp.expect_denied($sql$SELECT public.update_premium_shields('fa100000-0000-0000-0000-000000000002'::uuid, true)$sql$);
SELECT pg_temp.require(public.get_stress_signature('fa100000-0000-0000-0000-000000000002')->'patterns'->0->>'category' = 'synthetic_marker', 'owner signature read');
SELECT pg_temp.require((public.update_session_rating('fa100000-0000-0000-0000-000000000012',
  'fa100000-0000-0000-0000-000000000002', 5, 'owner b')).user_2_rating = 5, 'owner can rate own side');
RESET ROLE;

SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claim.sub', '', true),
       set_config('request.jwt.claim.role', 'service_role', true),
       set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT pg_temp.require(public.get_stress_signature('fa100000-0000-0000-0000-000000000002')->'patterns'->0->>'category' = 'synthetic_marker', 'service signature read without user identity');
SELECT pg_temp.require((public.update_session_rating('fa100000-0000-0000-0000-000000000012',
  'fa100000-0000-0000-0000-000000000002', 4, 'service')).user_2_rating = 4, 'service rating retained');
SELECT pg_temp.require((SELECT count(*) = 0 FROM public.get_moods_for_pattern_analysis('fa100000-0000-0000-0000-000000000002', 4)), 'service mood query');
SELECT pg_temp.require((SELECT count(*) = 0 FROM public.get_pending_notifications(1)), 'service pending query');
SELECT pg_temp.require((SELECT count(*) = 0 FROM public.get_streak_at_risk_users(20)), 'service streak query');
SELECT pg_temp.require((SELECT count(*) = 0 FROM public.get_users_for_weekly_summary()), 'service weekly query');
SELECT pg_temp.require(public.claim_family_seat('fa100000-0000-0000-0000-000000000099',
  'fa100000-0000-0000-0000-000000000002', NULL)->>'code' = 'NO_ACTIVE_SUBSCRIPTION', 'service claim reaches expected missing fixture');
SELECT pg_temp.require(public.release_family_seat('fa100000-0000-0000-0000-000000000099',
  'fa100000-0000-0000-0000-000000000002')->>'code' = 'NO_SUBSCRIPTION', 'service release reaches expected missing fixture');
SELECT pg_temp.require((SELECT allowed FROM public.check_rate_limit('fa100000-0000-0000-0000-000000000002',
  'sql-authorization-test', now(), 3, 60000)), 'service rate limit retained');
SELECT pg_temp.require((public.check_capacity_rate_limit('fa100000-0000-0000-0000-000000000002',
  60000::bigint, 3)->>'allowed')::boolean, 'service capacity limit retained');
SELECT pg_temp.require((SELECT NOT allowed FROM public.check_and_increment_synthesis_quota(
  'fa100000-0000-0000-0000-000000000002', false, 0)), 'service three-argument quota retained');
SELECT public.update_premium_shields('fa100000-0000-0000-0000-000000000002', true);
SELECT pg_temp.require((SELECT streak_shields_max = 3 FROM public.user_stats
  WHERE user_id = 'fa100000-0000-0000-0000-000000000002'), 'service premium shield update retained');
DO $test$
DECLARE
  v_case record;
  v_reached_body boolean;
BEGIN
  FOR v_case IN SELECT * FROM pg_temp.internal_rpc_cases
      WHERE signature LIKE 'public.submit_pathway_checkin(%' AND runtime_callable LOOP
    v_reached_body := false;
    BEGIN
      EXECUTE v_case.call_sql;
    EXCEPTION WHEN raise_exception THEN
      v_reached_body := SQLERRM LIKE '%User pathway not found%';
    END;
    PERFORM pg_temp.require(v_reached_body, 'service pathway overload callable: ' || v_case.signature);
  END LOOP;
END;
$test$;
RESET ROLE;

-- Denied calls left no signature audit entry; only the owner and service reads did.
SELECT pg_temp.require((SELECT count(*) = 2 FROM public.pattern_access_audit
  WHERE user_id = 'fa100000-0000-0000-0000-000000000002'), 'denied reads have no audit side effect');
SELECT pg_temp.require((SELECT user_1_rating = 4 AND user_1_notes = 'owner a'
  AND user_2_rating = 4 AND user_2_notes = 'service'
  FROM public.couples_exercise_sessions WHERE id = 'fa100000-0000-0000-0000-000000000012'),
  'only authorized ratings were written');
SELECT pg_temp.require(has_function_privilege('authenticated',
  'public.upsert_signature_signal(uuid,text,double precision,text,date)', 'EXECUTE'), 'iOS signal RPC preserved');
SET LOCAL ROLE anon;
SELECT pg_temp.expect_denied($sql$SELECT public.upsert_signature_signal('fa100000-0000-0000-0000-000000000002','fixture',0.5,'user_input',current_date)$sql$);
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','fa100000-0000-0000-0000-000000000001',true);
SELECT pg_temp.expect_denied($sql$SELECT public.upsert_signature_signal('fa100000-0000-0000-0000-000000000002','fixture',0.5,'user_input',current_date)$sql$);
SELECT pg_temp.require(public.upsert_signature_signal('fa100000-0000-0000-0000-000000000001','fixture',0.5,'user_input',current_date) IS NOT NULL,'owner signal write retained');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.require(public.add_family_member('fa100000-0000-0000-0000-000000000099','fa100000-0000-0000-0000-000000000002','parent',NULL,NULL)->>'code'='FAMILY_NOT_FOUND','service membership helper retained');
RESET ROLE;

ROLLBACK;
SELECT 'PASS: 15 exact internal RPC ACLs, 13 runtime denial cases per browser role, owner/service and forum-policy checks; all synthetic fixtures rolled back' AS result;
