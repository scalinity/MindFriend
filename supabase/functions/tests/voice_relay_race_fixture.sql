-- LOCAL ONLY. Run AFTER voice_relay_fixture.sql in its disposable database.
-- dblink uses only this local PostgreSQL database. No provider or external API is used.
\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS dblink;
SELECT set_config('request.jwt.claim.role', 'service_role', false);
-- A separate owner avoids the preparation rate limit exercised by the first fixture.
INSERT INTO auth.users VALUES ('30000000-0000-4000-8000-000000000003');
INSERT INTO public.profiles VALUES ('30000000-0000-4000-8000-000000000003', 'free');
CREATE TABLE public.voice_relay_test_race(session_id uuid);
INSERT INTO public.voice_relay_test_race SELECT (public.prepare_voice_relay('30000000-0000-4000-8000-000000000003')->>'session_id')::uuid;
SELECT dblink_connect('client_end', 'dbname=' || current_database() || ' application_name=voice_relay_race');
BEGIN;
SELECT public.claim_voice_relay('30000000-0000-4000-8000-000000000003', (SELECT session_id FROM public.voice_relay_test_race));
-- The client end blocks behind claim's row lock. It resumes only after COMMIT.
SELECT dblink_send_query('client_end', $query$
DO $remote$ BEGIN
 PERFORM set_config('request.jwt.claim.role','authenticated',false);
 PERFORM set_config('request.jwt.claim.sub','30000000-0000-4000-8000-000000000003',false);
 PERFORM public.end_voice_session((SELECT session_id FROM public.voice_relay_test_race),0);
END $remote$;
$query$);
DO $$
DECLARE blocked boolean := false;
BEGIN
 FOR attempt IN 1..100 LOOP
   PERFORM pg_stat_clear_snapshot();
   SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE application_name = 'voice_relay_race' AND wait_event_type = 'Lock') INTO blocked;
   EXIT WHEN blocked;
   PERFORM pg_sleep(0.01);
 END LOOP;
 IF NOT blocked THEN RAISE EXCEPTION 'Race fixture did not observe the client blocked on the row lock'; END IF;
END $$;
COMMIT;
SELECT * FROM dblink_get_result('client_end') AS result(status text);
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.voice_sessions WHERE id = (SELECT session_id FROM public.voice_relay_test_race) AND ended_at IS NOT NULL) THEN RAISE EXCEPTION 'Concurrent client end bypassed ledger'; END IF;
 IF public.get_voice_minutes_remaining('30000000-0000-4000-8000-000000000003') <> 1 THEN RAISE EXCEPTION 'Concurrent end released reservation'; END IF;
 RAISE NOTICE 'PASS: real two-connection claim/client-end race';
END $$;
SELECT dblink_disconnect('client_end');
DROP TABLE public.voice_relay_test_race;
