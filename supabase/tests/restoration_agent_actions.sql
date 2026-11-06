\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;
-- Run in a disposable Supabase PostgreSQL database with its standard auth.uid().
CREATE TABLE public.agent_actions (id uuid PRIMARY KEY, user_id uuid, content jsonb);
ALTER TABLE public.agent_actions ENABLE ROW LEVEL SECURITY;
GRANT ALL ON public.agent_actions TO anon, authenticated, service_role;
CREATE POLICY "Service role manages agent actions" ON public.agent_actions
  FOR ALL TO public WITH CHECK (true);
CREATE POLICY "Users view own agent actions" ON public.agent_actions
  FOR SELECT TO public USING (auth.uid() = user_id);
CREATE POLICY "Users update own agent actions" ON public.agent_actions
  FOR UPDATE TO public USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
INSERT INTO public.agent_actions VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','{}'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','22222222-2222-4222-8222-222222222222','{}');
SET LOCAL ROLE anon;
DO $$ BEGIN
  IF EXISTS (SELECT FROM public.agent_actions) THEN RAISE EXCEPTION 'unexpected pre-fix anonymous read'; END IF;
  INSERT INTO public.agent_actions VALUES
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','22222222-2222-4222-8222-222222222222','{"synthetic":"forged action"}');
END $$;
RESET ROLE;
\ir ../migrations/20261023024312_restrict_agent_actions_policy.sql
SET LOCAL ROLE anon;
DO $$ BEGIN
  IF EXISTS (SELECT FROM public.agent_actions) THEN RAISE EXCEPTION 'anon read leaked'; END IF;
  BEGIN
    INSERT INTO public.agent_actions VALUES ('cccccccc-cccc-4ccc-8ccc-cccccccccccc',null,'{}');
    RAISE EXCEPTION 'anon insert allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    TRUNCATE public.agent_actions;
    RAISE EXCEPTION 'anon truncate allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
DO $$ DECLARE changed integer; BEGIN
  IF (SELECT count(*) FROM public.agent_actions) <> 1 THEN RAISE EXCEPTION 'cross-user read leaked'; END IF;
  UPDATE public.agent_actions SET content = '{"response":"seen"}' WHERE id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  GET DIAGNOSTICS changed = ROW_COUNT;
  IF changed <> 0 THEN RAISE EXCEPTION 'cross-user update allowed'; END IF;
  UPDATE public.agent_actions SET content = '{"response":"seen"}' WHERE id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  GET DIAGNOSTICS changed = ROW_COUNT;
  IF changed <> 1 THEN RAISE EXCEPTION 'owner update failed'; END IF;
  BEGIN
    UPDATE public.agent_actions SET user_id='22222222-2222-4222-8222-222222222222';
    RAISE EXCEPTION 'ownership reassignment allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$ BEGIN
  IF (SELECT count(*) FROM public.agent_actions) <> 3 THEN RAISE EXCEPTION 'service access broken'; END IF;
END $$;
RESET ROLE;
ROLLBACK;
\echo PASS: pre-fix anonymous action insertion reproduced; anonymous, cross-user, owner, service and TRUNCATE checks passed
