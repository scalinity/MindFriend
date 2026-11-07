\ir support/authz_fixture.sql
CREATE TEMP TABLE analysis_tables(name text);
INSERT INTO analysis_tables VALUES ('agent_learnings'),('agent_signals'),('agent_decisions'),
  ('daily_briefings'),('journal_analyses'),('voice_journal_analysis'),('rehearsal_feedback'),('billing_events');
GRANT SELECT ON analysis_tables TO anon, authenticated, service_role;
DO $$ DECLARE item record; BEGIN
  FOR item IN SELECT * FROM analysis_tables LOOP
    PERFORM pg_temp.authz_assert(has_table_privilege('service_role','public.'||item.name,'INSERT'), 'service insert retained: '||item.name);
    PERFORM pg_temp.authz_assert(NOT has_table_privilege('anon','public.'||item.name,'SELECT'), 'anonymous read exposed: '||item.name);
    PERFORM pg_temp.authz_assert(NOT has_table_privilege('authenticated','public.'||item.name,'INSERT'), 'client insert exposed: '||item.name);
  END LOOP;
END $$;
SET LOCAL ROLE service_role;
SELECT pg_temp.authz_claims(NULL);
INSERT INTO public.agent_learnings(user_id,learning_type,learned_value) VALUES
  ('f0200000-0000-4000-8000-000000000001','optimal_time','{"hour":9}'),
  ('f0200000-0000-4000-8000-000000000002','optimal_time','{"hour":10}');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT pg_temp.authz_claims(NULL);
DO $$ DECLARE item record; BEGIN
  FOR item IN SELECT * FROM analysis_tables LOOP
    PERFORM pg_temp.authz_denied(format('SELECT * FROM public.%I',item.name));
    PERFORM pg_temp.authz_denied(format('INSERT INTO public.%I DEFAULT VALUES',item.name));
  END LOOP;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
DO $$ DECLARE item record; BEGIN
  FOR item IN SELECT * FROM analysis_tables LOOP
    PERFORM pg_temp.authz_denied(format('INSERT INTO public.%I DEFAULT VALUES',item.name));
  END LOOP;
END $$;
SELECT pg_temp.authz_assert((SELECT count(*)=1 FROM public.agent_learnings),'owner learning read retained, other owner hidden');
SELECT pg_temp.authz_denied($q$UPDATE public.agent_learnings SET learned_value='{}'$q$);
SELECT pg_temp.authz_denied('DELETE FROM public.agent_learnings');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT pg_temp.authz_claims(NULL);
UPDATE public.agent_learnings SET confidence=0.9;
SELECT pg_temp.authz_assert((SELECT count(*)=2 FROM public.agent_learnings WHERE confidence=0.9),'service learning update retained');
DELETE FROM public.agent_learnings;
RESET ROLE;
ROLLBACK;
\echo 'PASS service analysis authorization'
