\ir support/authz_fixture.sql

CREATE TEMP TABLE reader_cases(signature text, call_sql text);
INSERT INTO reader_cases VALUES
  ('public.calculate_weekly_stats(uuid)', 'SELECT * FROM public.calculate_weekly_stats($1)'),
  ('public.calculate_mood_trend(uuid,integer)', 'SELECT * FROM public.calculate_mood_trend($1, 7)'),
  ('public.calculate_user_absence(uuid)', 'SELECT * FROM public.calculate_user_absence($1)'),
  ('public.get_buddy_widget_data(uuid)', 'SELECT * FROM public.get_buddy_widget_data($1)'),
  ('public.get_notification_engagement_stats(uuid)', 'SELECT * FROM public.get_notification_engagement_stats($1)'),
  ('public.get_notification_training_data(uuid)', NULL),
  ('public.get_notification_training_data(uuid,integer)', 'SELECT * FROM public.get_notification_training_data($1, 30)'),
  ('public.get_weekly_engagement_stats(uuid)', 'SELECT * FROM public.get_weekly_engagement_stats($1)');
GRANT SELECT ON reader_cases TO anon, authenticated, service_role;
DO $$ DECLARE item record; BEGIN
  FOR item IN SELECT * FROM reader_cases LOOP
    PERFORM pg_temp.authz_assert(NOT has_function_privilege('anon', item.signature, 'execute'), 'anonymous reader grant: '||item.signature);
    PERFORM pg_temp.authz_assert(has_function_privilege('authenticated', item.signature, 'execute'), 'owner reader missing: '||item.signature);
    PERFORM pg_temp.authz_assert(has_function_privilege('service_role', item.signature, 'execute'), 'service reader missing: '||item.signature);
  END LOOP;
  PERFORM pg_temp.authz_assert(NOT has_function_privilege('authenticated', 'public.find_mood_decline_users(integer,integer)', 'execute'), 'batch mood reader exposed');
  PERFORM pg_temp.authz_assert(NOT has_function_privilege('anon', 'public.calculate_weekly_stats_extended(uuid)', 'execute')
    AND NOT has_function_privilege('authenticated', 'public.calculate_weekly_stats_extended(uuid)', 'execute'), 'extended stats reader exposed');
END $$;

INSERT INTO public.circles(id,name,invite_code,owner_id) VALUES
  ('f0200000-0000-4000-9000-000000000001','Synthetic circle','AUTHZPRIVATE','f0200000-0000-4000-8000-000000000001');
INSERT INTO public.circle_members(circle_id,user_id,role) VALUES
  ('f0200000-0000-4000-9000-000000000001','f0200000-0000-4000-8000-000000000001','owner');
INSERT INTO public.moods(user_id,mood_score,local_date)
VALUES ('f0200000-0000-4000-8000-000000000001',4,current_date);
UPDATE public.user_settings SET show_presence = true WHERE user_id='f0200000-0000-4000-8000-000000000001';
INSERT INTO public.user_presence(user_id,status,last_seen_at)
VALUES ('f0200000-0000-4000-8000-000000000001','online',now());

SET LOCAL ROLE anon;
SELECT pg_temp.authz_claims(NULL);
DO $$ DECLARE item record; BEGIN
  FOR item IN SELECT * FROM reader_cases WHERE call_sql IS NOT NULL LOOP
    PERFORM pg_temp.authz_denied(replace(item.call_sql,'$1',quote_literal('f0200000-0000-4000-8000-000000000001')||'::uuid'));
  END LOOP;
END $$;
SELECT pg_temp.authz_denied($q$SELECT * FROM public.get_circle_presence('f0200000-0000-4000-9000-000000000001')$q$);
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims(NULL);
DO $$ DECLARE item record; BEGIN
  FOR item IN SELECT * FROM reader_cases WHERE call_sql IS NOT NULL LOOP
    PERFORM pg_temp.authz_denied(replace(item.call_sql,'$1',quote_literal('f0200000-0000-4000-8000-000000000001')||'::uuid'));
  END LOOP;
END $$;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
DO $$ DECLARE item record; BEGIN
  FOR item IN SELECT * FROM reader_cases WHERE call_sql IS NOT NULL LOOP
    PERFORM pg_temp.authz_denied(replace(item.call_sql,'$1',quote_literal('f0200000-0000-4000-8000-000000000002')||'::uuid'));
    EXECUTE item.call_sql USING 'f0200000-0000-4000-8000-000000000001'::uuid;
  END LOOP;
END $$;
SELECT pg_temp.authz_assert((SELECT checkin_count=1 FROM public.calculate_weekly_stats('f0200000-0000-4000-8000-000000000001')), 'owner mood record preserved');
SELECT pg_temp.authz_assert((SELECT count(*)=1 FROM public.get_circle_presence('f0200000-0000-4000-9000-000000000001')), 'member presence visible');
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000003');
SELECT pg_temp.authz_denied($q$SELECT * FROM public.get_circle_presence('f0200000-0000-4000-9000-000000000001')$q$);
-- A forged JWT role string cannot replace the actual SQL execution role.
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SELECT pg_temp.authz_denied($q$SELECT * FROM public.calculate_weekly_stats('f0200000-0000-4000-8000-000000000001')$q$);
RESET ROLE;

SET LOCAL ROLE service_role;
SELECT pg_temp.authz_claims(NULL);
DO $$ DECLARE item record; BEGIN
  FOR item IN SELECT * FROM reader_cases WHERE call_sql IS NOT NULL LOOP
    EXECUTE item.call_sql USING 'f0200000-0000-4000-8000-000000000002'::uuid;
  END LOOP;
END $$;
SELECT * FROM public.get_circle_presence('f0200000-0000-4000-9000-000000000001');
SELECT * FROM public.find_mood_decline_users(2,2);
RESET ROLE;

-- The legacy overloads have overlapping default arguments. Temporarily rename
-- the longer overload only inside this rolled-back test to exercise the short body.
ALTER FUNCTION public.get_notification_training_data(uuid,integer) RENAME TO authz_long_training_reader;
SET LOCAL ROLE authenticated;
SELECT pg_temp.authz_claims('f0200000-0000-4000-8000-000000000001');
SELECT pg_temp.authz_denied($q$SELECT * FROM public.get_notification_training_data('f0200000-0000-4000-8000-000000000002'::uuid)$q$);
SELECT * FROM public.get_notification_training_data('f0200000-0000-4000-8000-000000000001'::uuid);
RESET ROLE;
ROLLBACK;
\echo 'PASS private activity authorization'
