-- EMPTY LOCAL DISPOSABLE DATABASE ONLY. Uses existing Supabase roles, no Auth
-- accounts, notifications, providers, publication changes or application workers.
-- Run as supabase_admin in a fresh presence_privacy_synthetic database. Copy this
-- file and its paired migration/rollback with their relative paths intact first.
\set ON_ERROR_STOP on
DO $$ BEGIN
  IF current_database() <> 'presence_privacy_synthetic' OR current_user <> 'supabase_admin'
    OR pg_catalog.to_regnamespace('auth') IS NOT NULL
    OR EXISTS (SELECT 1 FROM pg_catalog.pg_class AS c JOIN pg_catalog.pg_namespace AS n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relkind IN ('r','p')) THEN
    RAISE EXCEPTION 'Requires empty disposable presence_privacy_synthetic as supabase_admin';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='service_role' AND rolbypassrls)
    OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='anon')
    OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='authenticated') THEN
    RAISE EXCEPTION 'Requires existing Supabase roles; this fixture never changes global roles';
  END IF;
END $$;

-- Minimal columns used by the actual snapshot policies. No real user rows or
-- triggers are imported. The connection policy and is_circle_member definition
-- below match the pre-monthly-callers-20261023 schema-only backup.
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role;
CREATE TABLE public.user_presence(user_id uuid PRIMARY KEY,status text,last_seen_at timestamptz,current_activity text,updated_at timestamptz);
CREATE TABLE public.user_settings(user_id uuid PRIMARY KEY,show_presence boolean);
CREATE TABLE public.circle_members(id uuid PRIMARY KEY,circle_id uuid NOT NULL,user_id uuid NOT NULL);
CREATE TABLE public.buddy_relationships(id uuid PRIMARY KEY,inviter_id uuid NOT NULL,invitee_id uuid,status text NOT NULL);
ALTER TABLE public.user_presence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.circle_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.buddy_relationships ENABLE ROW LEVEL SECURITY;
GRANT ALL ON public.user_presence, public.user_settings, public.circle_members, public.buddy_relationships TO anon, authenticated, service_role;

CREATE FUNCTION public.is_circle_member(check_circle_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM circle_members WHERE circle_id=check_circle_id AND user_id=auth.uid());
$$;
CREATE POLICY "Members can view circle members" ON public.circle_members FOR SELECT
  USING (auth.uid()=user_id OR public.is_circle_member(circle_id));
CREATE POLICY "Users see own buddy relationships" ON public.buddy_relationships FOR SELECT
  USING (auth.uid()=inviter_id OR auth.uid()=invitee_id);
CREATE POLICY "Users can view own settings" ON public.user_settings FOR SELECT USING (auth.uid()=user_id);
CREATE POLICY "Users can update own settings" ON public.user_settings FOR UPDATE USING (auth.uid()=user_id);
CREATE POLICY "Users can view own presence" ON public.user_presence FOR SELECT USING (auth.uid()=user_id);
CREATE POLICY "Users can update own presence" ON public.user_presence FOR UPDATE USING (auth.uid()=user_id);
CREATE POLICY "Users can upsert own presence" ON public.user_presence FOR INSERT WITH CHECK (auth.uid()=user_id);
CREATE POLICY "Connections can view presence" ON public.user_presence FOR SELECT USING (
  user_id IN (SELECT cm2.user_id FROM public.circle_members AS cm1
    JOIN public.circle_members AS cm2 ON cm1.circle_id=cm2.circle_id WHERE cm1.user_id=auth.uid())
  OR user_id IN (SELECT CASE WHEN br.inviter_id=auth.uid() THEN br.invitee_id ELSE br.inviter_id END
    FROM public.buddy_relationships AS br WHERE br.status='accepted' AND (br.inviter_id=auth.uid() OR br.invitee_id=auth.uid())));

CREATE TEMP TABLE presence_policy_before AS SELECT polname,polcmd,polpermissive,polroles,
  pg_get_expr(polqual,polrelid) AS qual,pg_get_expr(polwithcheck,polrelid) AS with_check
  FROM pg_policy WHERE polrelid='public.user_presence'::regclass;
CREATE TEMP TABLE presence_acl_before AS SELECT relacl FROM pg_class WHERE oid='public.user_presence'::regclass;

INSERT INTO public.user_presence
SELECT ('60000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'online',now(),'synthetic',now()
FROM generate_series(1,10) n;
INSERT INTO public.user_settings SELECT user_id,CASE
  WHEN right(user_id::text,1) IN ('1','2','5') THEN false
  WHEN right(user_id::text,1)='7' THEN NULL ELSE true END
FROM public.user_presence WHERE right(user_id::text,1)<>'8';
INSERT INTO public.circle_members SELECT gen_random_uuid(),'60000000-0000-4000-9000-000000000001',user_id
FROM public.user_presence WHERE right(user_id::text,1) IN ('1','2','3','7','8');
INSERT INTO public.buddy_relationships VALUES
  ('60000000-0000-4000-a000-000000000001','60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000004','accepted'),
  ('60000000-0000-4000-a000-000000000002','60000000-0000-4000-8000-000000000005','60000000-0000-4000-8000-000000000001','accepted'),
  ('60000000-0000-4000-a000-000000000003','60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000009','pending'),
  ('60000000-0000-4000-a000-000000000004','60000000-0000-4000-8000-000000000010','60000000-0000-4000-8000-000000000001','accepted');

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','60000000-0000-4000-8000-000000000001',false);
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.user_presence WHERE user_id='60000000-0000-4000-8000-000000000002') THEN
    RAISE EXCEPTION 'Pre-fix hidden-circle exposure was not reproduced';
  END IF;
END $$;
RESET ROLE;
\ir ../migrations/20261023091000_honor_presence_privacy.sql

SET ROLE anon;
SELECT set_config('request.jwt.claim.sub','',false);
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.user_presence) THEN RAISE EXCEPTION 'Anonymous presence leak'; END IF;
  BEGIN
    PERFORM public.can_view_connected_presence('60000000-0000-4000-8000-000000000003');
    RAISE EXCEPTION 'Anonymous helper access';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET ROLE authenticated;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.user_presence) THEN RAISE EXCEPTION 'Missing-principal presence leak'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','60000000-0000-4000-8000-000000000001',false);
DO $$ DECLARE seen uuid[]; changed integer; BEGIN
  SELECT array_agg(user_id ORDER BY user_id) INTO seen FROM public.user_presence;
  IF seen IS DISTINCT FROM ARRAY[
    '60000000-0000-4000-8000-000000000001'::uuid,
    '60000000-0000-4000-8000-000000000003'::uuid,
    '60000000-0000-4000-8000-000000000004'::uuid,
    '60000000-0000-4000-8000-000000000010'::uuid] THEN
    RAISE EXCEPTION 'Wrong owner/circle/buddy visibility: %',seen;
  END IF;
  IF (SELECT count(*) FROM public.user_settings) <> 1
    OR public.can_view_connected_presence('60000000-0000-4000-8000-000000000006')
    OR public.can_view_connected_presence(NULL) THEN RAISE EXCEPTION 'Settings or unrelated preference exposed'; END IF;
  UPDATE public.user_presence SET current_activity='synthetic-owner-update' WHERE user_id='60000000-0000-4000-8000-000000000001';
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed<>1 THEN RAISE EXCEPTION 'Owner update denied'; END IF;
  UPDATE public.user_presence SET current_activity='cross-owner' WHERE user_id='60000000-0000-4000-8000-000000000003';
  GET DIAGNOSTICS changed=ROW_COUNT;
  IF changed<>0 THEN RAISE EXCEPTION 'Cross-owner update allowed'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','60000000-0000-4000-8000-000000000006',false);
DO $$ BEGIN
  IF (SELECT count(*) FROM public.user_presence) <> 1
    OR public.can_view_connected_presence('60000000-0000-4000-8000-000000000003') THEN
    RAISE EXCEPTION 'Outsider learned connection presence/preference';
  END IF;
END $$;
RESET ROLE;

-- Read the current preference and relationships on every statement, including opt-out.
UPDATE public.user_settings SET show_presence=true WHERE user_id='60000000-0000-4000-8000-000000000002';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','60000000-0000-4000-8000-000000000001',false);
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.user_presence WHERE user_id='60000000-0000-4000-8000-000000000002') THEN RAISE EXCEPTION 'Current opt-in ignored'; END IF;
END $$;
RESET ROLE;
UPDATE public.user_settings SET show_presence=false WHERE user_id='60000000-0000-4000-8000-000000000002';
UPDATE public.buddy_relationships SET status='declined' WHERE id='60000000-0000-4000-a000-000000000001';
DELETE FROM public.circle_members WHERE user_id='60000000-0000-4000-8000-000000000003';
SET ROLE authenticated;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.user_presence WHERE user_id IN (
    '60000000-0000-4000-8000-000000000002','60000000-0000-4000-8000-000000000003','60000000-0000-4000-8000-000000000004')) THEN
    RAISE EXCEPTION 'Opt-out or removed connection remained visible';
  END IF;
END $$;
RESET ROLE;
SET ROLE service_role;
DO $$ BEGIN
  IF (SELECT count(*) FROM public.user_presence)<>10 THEN RAISE EXCEPTION 'Service access changed'; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
  IF has_function_privilege('anon','public.can_view_connected_presence(uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.can_view_connected_presence(uuid)','EXECUTE')
    OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid='public.can_view_connected_presence(uuid)'::regprocedure
      AND prosecdef AND provolatile='s' AND proconfig @> ARRAY['search_path=""']) THEN
    RAISE EXCEPTION 'Unsafe helper attributes or permissions';
  END IF;
  IF EXISTS ((SELECT * FROM presence_policy_before WHERE polname<>'Connections can view presence') EXCEPT
    SELECT polname,polcmd,polpermissive,polroles,pg_get_expr(polqual,polrelid),pg_get_expr(polwithcheck,polrelid)
    FROM pg_policy WHERE polrelid='public.user_presence'::regclass)
    OR (SELECT relacl FROM presence_acl_before) IS DISTINCT FROM (SELECT relacl FROM pg_class WHERE oid='public.user_presence'::regclass) THEN
    RAISE EXCEPTION 'Other presence policies or table grants changed';
  END IF;
  RAISE NOTICE 'PASS: actual anon/authenticated/service roles; owner, circle and both buddy directions; false/null/missing preference; outsiders; current opt-out/removal; private settings and unchanged writes';
END $$;

\ir ../rollback/20261023091000_honor_presence_privacy.sql
DO $$ BEGIN
  IF to_regprocedure('public.can_view_connected_presence(uuid)') IS NOT NULL
    OR EXISTS ((SELECT * FROM presence_policy_before) EXCEPT
      SELECT polname,polcmd,polpermissive,polroles,pg_get_expr(polqual,polrelid),pg_get_expr(polwithcheck,polrelid)
      FROM pg_policy WHERE polrelid='public.user_presence'::regclass) THEN
    RAISE EXCEPTION 'Rollback did not restore the exact original policy';
  END IF;
  RAISE NOTICE 'PASS: rollback restores original policy and removes helper without publication changes';
END $$;
