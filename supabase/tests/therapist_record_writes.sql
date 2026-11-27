-- Synthetic rollback fixture: direct writes to therapist_assignments, therapist_notes and
-- therapy_access_log. A client marks an assignment on their own connection completed or skipped, as
-- released clients 1.0.4, 1.0.5 and 2.0 do, and reads their assignments and access log; nothing else.
-- A therapist writes none of these directly (therapist-api creates assignments, as the service role),
-- therapist notes are service-role only, and anon has no access at all.
BEGIN;

INSERT INTO public.supported_languages(code,name,native_name,is_active) VALUES ('en','English','English',true) ON CONFLICT DO NOTHING;
INSERT INTO public.level_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO public.skill_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
SET LOCAL statement_timeout = '20s';
INSERT INTO auth.users(id, email, raw_user_meta_data) VALUES
 ('17620000-0000-4000-8000-000000000001', 'client@example.invalid', '{}'),
 ('17620000-0000-4000-8000-000000000002', 'therapist@example.invalid', '{}'),
 ('17620000-0000-4000-8000-000000000003', 'second-client@example.invalid', '{}'),
 ('17620000-0000-4000-8000-000000000004', 'second-therapist@example.invalid', '{}');
INSERT INTO public.profiles(id) VALUES
 ('17620000-0000-4000-8000-000000000001'), ('17620000-0000-4000-8000-000000000002'),
 ('17620000-0000-4000-8000-000000000003'), ('17620000-0000-4000-8000-000000000004') ON CONFLICT(id) DO NOTHING;
INSERT INTO public.therapist_accounts(id, user_id) VALUES
 ('17620000-0000-4000-8000-0000000000a1', '17620000-0000-4000-8000-000000000002'),
 ('17620000-0000-4000-8000-0000000000a2', '17620000-0000-4000-8000-000000000004');

-- As the service role: two accepted connections with the first therapist, two assignments for the
-- first client and an overdue one for the second (therapist-api), and one access-log row each.
SET LOCAL ROLE service_role;
INSERT INTO public.therapy_connections(id, client_id, therapist_id, status, invited_by, connected_at) VALUES
 ('17620000-0000-4000-8000-0000000000c1', '17620000-0000-4000-8000-000000000001', '17620000-0000-4000-8000-0000000000a1', 'active', 'client', now()),
 ('17620000-0000-4000-8000-0000000000c2', '17620000-0000-4000-8000-000000000003', '17620000-0000-4000-8000-0000000000a1', 'active', 'client', now());
INSERT INTO public.therapist_assignments(id, connection_id, title, description, assignment_type, due_date) VALUES
 ('17620000-0000-4000-8000-0000000000e1', '17620000-0000-4000-8000-0000000000c1', 'Evening walk', 'Twenty minutes outside', 'custom', current_date + 7),
 ('17620000-0000-4000-8000-0000000000e2', '17620000-0000-4000-8000-0000000000c1', 'Gratitude list', NULL, 'custom', current_date + 7),
 ('17620000-0000-4000-8000-0000000000e3', '17620000-0000-4000-8000-0000000000c2', 'Breathing practice', NULL, 'custom', current_date - 1);
INSERT INTO public.therapy_access_log(connection_id, therapist_id, action) VALUES
 ('17620000-0000-4000-8000-0000000000c1', '17620000-0000-4000-8000-0000000000a1', 'view_mood'),
 ('17620000-0000-4000-8000-0000000000c2', '17620000-0000-4000-8000-0000000000a1', 'view_mood');
RESET ROLE;

CREATE FUNCTION pg_temp.act_as(person text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', person, 'role', current_user)::text, true);
  PERFORM set_config('request.jwt.claim.sub', COALESCE(person, ''), true);
END $$;
-- The statement must fail with a privilege error (missing grant or policy check).
CREATE FUNCTION pg_temp.denied(statement text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN
  BEGIN
    EXECUTE statement;
  EXCEPTION WHEN insufficient_privilege THEN RETURN;
  END;
  RAISE EXCEPTION 'Expected a privilege error as %: %', current_user, statement;
END $$;
-- The statement must change nothing: a privilege error, or no row matched.
CREATE FUNCTION pg_temp.refused(statement text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE changed integer;
BEGIN
  BEGIN
    EXECUTE statement;
    GET DIAGNOSTICS changed = ROW_COUNT;
  EXCEPTION WHEN insufficient_privilege THEN RETURN;
  END;
  IF changed <> 0 THEN RAISE EXCEPTION 'Expected no change as %, changed % rows: %', current_user, changed, statement; END IF;
END $$;
-- The statement must change, or return, exactly the given number of rows.
CREATE FUNCTION pg_temp.rows(expected integer, statement text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE counted integer;
BEGIN
  EXECUTE statement;
  GET DIAGNOSTICS counted = ROW_COUNT;
  IF counted <> expected THEN
    RAISE EXCEPTION 'Expected % rows as %, got %: %', expected, current_user, counted, statement;
  END IF;
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT USAGE ON SCHEMA %I TO anon, authenticated, service_role',
    (SELECT nspname FROM pg_namespace WHERE oid = pg_my_temp_schema()));
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.act_as(text), pg_temp.denied(text), pg_temp.refused(text), pg_temp.rows(integer, text)
  TO anon, authenticated, service_role;

-- Grants: anon has nothing on the three tables; authenticated reads assignments and the access log,
-- updates only an assignment's status, completed_at and client_notes, and has nothing on notes.
-- Neither runs the two SECURITY DEFINER functions that write these tables.
DO $$
DECLARE
  relation text;
  writable text[];
BEGIN
  FOREACH relation IN ARRAY ARRAY['public.therapist_assignments', 'public.therapist_notes', 'public.therapy_access_log'] LOOP
    IF has_table_privilege('anon', relation, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       OR has_any_column_privilege('anon', relation, 'SELECT, INSERT, UPDATE, REFERENCES') THEN
      RAISE EXCEPTION 'anon holds a privilege on %', relation;
    END IF;
    IF has_table_privilege('authenticated', relation, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       OR has_any_column_privilege('authenticated', relation, 'INSERT, REFERENCES') THEN
      RAISE EXCEPTION 'authenticated holds a write privilege on the whole of %', relation;
    END IF;
  END LOOP;
  IF has_any_column_privilege('authenticated', 'public.therapist_notes', 'SELECT, UPDATE') THEN
    RAISE EXCEPTION 'authenticated holds a privilege on therapist_notes';
  END IF;
  IF has_any_column_privilege('authenticated', 'public.therapy_access_log', 'UPDATE') THEN
    RAISE EXCEPTION 'authenticated can update therapy_access_log';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.therapist_assignments', 'SELECT')
     OR NOT has_table_privilege('authenticated', 'public.therapy_access_log', 'SELECT') THEN
    RAISE EXCEPTION 'authenticated lost the read the app relies on';
  END IF;
  SELECT array_agg(attname::text ORDER BY attname) INTO writable FROM pg_attribute
  WHERE attrelid = 'public.therapist_assignments'::regclass AND attnum > 0 AND NOT attisdropped
    AND has_column_privilege('authenticated', attrelid, attnum, 'UPDATE');
  IF writable IS DISTINCT FROM ARRAY['client_notes', 'completed_at', 'status'] THEN
    RAISE EXCEPTION 'authenticated can update % on therapist_assignments', writable;
  END IF;
  IF has_function_privilege('anon', 'public.log_therapy_access(uuid, uuid, text, text, uuid, text, text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.log_therapy_access(uuid, uuid, text, text, uuid, text, text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.expire_overdue_assignments()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.expire_overdue_assignments()', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon or authenticated can run a SECURITY DEFINER function that writes these tables';
  END IF;
END $$;

-- The first client: no insert or delete, no assignment column outside status, completed_at and
-- client_notes, nothing on notes, and a read-only access log of their own connection.
SET LOCAL ROLE authenticated;
SELECT pg_temp.act_as('17620000-0000-4000-8000-000000000001');
SELECT pg_temp.denied($q$INSERT INTO public.therapist_assignments(connection_id, title, assignment_type)
  VALUES ('17620000-0000-4000-8000-0000000000c1', 'Self-assigned', 'custom')$q$);
SELECT pg_temp.denied(format('UPDATE public.therapist_assignments SET %s WHERE id = %L', assignment, '17620000-0000-4000-8000-0000000000e1'))
FROM unnest(ARRAY[
  $a$title = 'Rewritten'$a$,
  $a$description = NULL$a$,
  $a$assignment_type = 'journal_prompt'$a$,
  $a$journal_prompt = 'Rewritten prompt'$a$,
  $a$exercise_id = NULL$a$,
  $a$due_date = current_date + 365$a$,
  $a$frequency = 'daily'$a$,
  $a$connection_id = '17620000-0000-4000-8000-0000000000c2'$a$,
  $a$created_at = now() - interval '1 year'$a$,
  $a$id = gen_random_uuid()$a$
]) AS assignment;
SELECT pg_temp.denied($q$DELETE FROM public.therapist_assignments WHERE id = '17620000-0000-4000-8000-0000000000e1'$q$);
SELECT pg_temp.denied($q$SELECT id FROM public.therapist_notes$q$);
SELECT pg_temp.denied($q$INSERT INTO public.therapist_notes(connection_id, therapist_id, content)
  VALUES ('17620000-0000-4000-8000-0000000000c1', '17620000-0000-4000-8000-0000000000a1', 'Forged note')$q$);
SELECT pg_temp.rows(1, $q$SELECT id FROM public.therapy_access_log$q$);
SELECT pg_temp.rows(2, $q$SELECT id FROM public.therapist_assignments$q$);
SELECT pg_temp.denied($q$INSERT INTO public.therapy_access_log(connection_id, therapist_id, action)
  VALUES ('17620000-0000-4000-8000-0000000000c1', '17620000-0000-4000-8000-0000000000a1', 'forged')$q$);
SELECT pg_temp.denied($q$UPDATE public.therapy_access_log SET action = 'forged'$q$);
SELECT pg_temp.denied($q$DELETE FROM public.therapy_access_log$q$);
SELECT pg_temp.denied($q$SELECT public.log_therapy_access('17620000-0000-4000-8000-0000000000c1',
  '17620000-0000-4000-8000-0000000000a1', 'forged')$q$);
SELECT pg_temp.denied($q$SELECT public.expire_overdue_assignments()$q$);
-- completeAssignment, with the columns it means to set and PostgREST's returned representation.
SELECT pg_temp.rows(1, $q$UPDATE public.therapist_assignments SET status = 'completed', completed_at = now(),
  client_notes = 'Went twice' WHERE id = '17620000-0000-4000-8000-0000000000e1' RETURNING *$q$);
-- skipAssignment.
SELECT pg_temp.rows(1, $q$UPDATE public.therapist_assignments SET status = 'skipped'
  WHERE id = '17620000-0000-4000-8000-0000000000e2' RETURNING *$q$);

-- The second client cannot change or read the first client's assignments or access log.
SELECT pg_temp.act_as('17620000-0000-4000-8000-000000000003');
SELECT pg_temp.refused(format('UPDATE public.therapist_assignments SET %s WHERE id = %L', assignment, target))
FROM unnest(ARRAY['17620000-0000-4000-8000-0000000000e1', '17620000-0000-4000-8000-0000000000e2']) AS target,
     unnest(ARRAY[
  $a$status = 'assigned'$a$,
  $a$completed_at = NULL, client_notes = 'Overwritten'$a$
]) AS assignment;
SELECT pg_temp.rows(1, $q$SELECT id FROM public.therapist_assignments$q$);
SELECT pg_temp.rows(1, $q$SELECT id FROM public.therapy_access_log$q$);

-- The therapist creates, changes and deletes nothing directly, and keeps no notes directly.
SELECT pg_temp.act_as('17620000-0000-4000-8000-000000000002');
SELECT pg_temp.denied($q$INSERT INTO public.therapist_assignments(connection_id, title, assignment_type)
  VALUES ('17620000-0000-4000-8000-0000000000c1', 'Direct assignment', 'custom')$q$);
SELECT pg_temp.refused(format('UPDATE public.therapist_assignments SET %s WHERE id = %L', assignment, '17620000-0000-4000-8000-0000000000e1'))
FROM unnest(ARRAY[
  $a$status = 'assigned', completed_at = NULL$a$,
  $a$client_notes = 'Overwritten'$a$,
  $a$title = 'Rewritten'$a$
]) AS assignment;
SELECT pg_temp.denied($q$DELETE FROM public.therapist_assignments WHERE id = '17620000-0000-4000-8000-0000000000e1'$q$);
SELECT pg_temp.denied($q$INSERT INTO public.therapist_notes(connection_id, therapist_id, content)
  VALUES ('17620000-0000-4000-8000-0000000000c1', '17620000-0000-4000-8000-0000000000a1', 'Session note')$q$);
SELECT pg_temp.denied($q$SELECT id FROM public.therapist_notes$q$);
SELECT pg_temp.denied($q$INSERT INTO public.therapy_access_log(connection_id, therapist_id, action)
  VALUES ('17620000-0000-4000-8000-0000000000c1', '17620000-0000-4000-8000-0000000000a1', 'forged')$q$);

-- The second therapist cannot attach a note to the first therapist's connection.
SELECT pg_temp.act_as('17620000-0000-4000-8000-000000000004');
SELECT pg_temp.denied($q$INSERT INTO public.therapist_notes(connection_id, therapist_id, content)
  VALUES ('17620000-0000-4000-8000-0000000000c1', '17620000-0000-4000-8000-0000000000a2', 'Note on another connection')$q$);
SELECT pg_temp.denied($q$INSERT INTO public.therapist_assignments(connection_id, title, assignment_type)
  VALUES ('17620000-0000-4000-8000-0000000000c1', 'Assignment on another connection', 'custom')$q$);
RESET ROLE;

-- anon: no read and no write.
SET LOCAL ROLE anon;
SELECT pg_temp.act_as(NULL);
SELECT pg_temp.denied(statement) FROM unnest(ARRAY[
  $q$SELECT id FROM public.therapist_assignments$q$,
  $q$INSERT INTO public.therapist_assignments(connection_id, title, assignment_type)
     VALUES ('17620000-0000-4000-8000-0000000000c1', 'Anonymous', 'custom')$q$,
  $q$UPDATE public.therapist_assignments SET status = 'completed'$q$,
  $q$DELETE FROM public.therapist_assignments$q$,
  $q$SELECT id FROM public.therapist_notes$q$,
  $q$INSERT INTO public.therapist_notes(connection_id, therapist_id, content)
     VALUES ('17620000-0000-4000-8000-0000000000c1', '17620000-0000-4000-8000-0000000000a1', 'Anonymous')$q$,
  $q$UPDATE public.therapist_notes SET content = 'Anonymous'$q$,
  $q$DELETE FROM public.therapist_notes$q$,
  $q$SELECT id FROM public.therapy_access_log$q$,
  $q$INSERT INTO public.therapy_access_log(connection_id, therapist_id, action)
     VALUES ('17620000-0000-4000-8000-0000000000c1', '17620000-0000-4000-8000-0000000000a1', 'forged')$q$,
  $q$UPDATE public.therapy_access_log SET action = 'forged'$q$,
  $q$DELETE FROM public.therapy_access_log$q$,
  $q$SELECT public.log_therapy_access('17620000-0000-4000-8000-0000000000c1', '17620000-0000-4000-8000-0000000000a1', 'forged')$q$,
  $q$SELECT public.expire_overdue_assignments()$q$
]) AS statement;
RESET ROLE;

-- The service role still does everything the functions do: therapist-api creates an assignment and
-- logs it, notes can be kept, and the maintenance function expires the overdue assignment.
SET LOCAL ROLE service_role;
SELECT pg_temp.rows(1, $q$INSERT INTO public.therapist_assignments(connection_id, title, assignment_type)
  VALUES ('17620000-0000-4000-8000-0000000000c1', 'Created through therapist-api', 'custom')$q$);
SELECT pg_temp.rows(1, $q$INSERT INTO public.therapist_notes(connection_id, therapist_id, content)
  VALUES ('17620000-0000-4000-8000-0000000000c1', '17620000-0000-4000-8000-0000000000a1', 'Session note')$q$);
SELECT pg_temp.rows(1, $q$SELECT public.log_therapy_access('17620000-0000-4000-8000-0000000000c1',
  '17620000-0000-4000-8000-0000000000a1', 'create_assignment')$q$);
DO $$ BEGIN
  IF public.expire_overdue_assignments() <> 1 THEN RAISE EXCEPTION 'Expected one overdue assignment to expire'; END IF;
END $$;
RESET ROLE;

-- Final state: only the writes above took effect.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.therapist_assignments WHERE id = '17620000-0000-4000-8000-0000000000e1'
      AND connection_id = '17620000-0000-4000-8000-0000000000c1' AND title = 'Evening walk'
      AND description = 'Twenty minutes outside' AND assignment_type = 'custom' AND due_date = current_date + 7
      AND frequency = 'once' AND status = 'completed' AND completed_at IS NOT NULL AND client_notes = 'Went twice') THEN
    RAISE EXCEPTION 'The completed assignment holds a change nobody was allowed to make';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.therapist_assignments WHERE id = '17620000-0000-4000-8000-0000000000e2'
      AND title = 'Gratitude list' AND status = 'skipped' AND completed_at IS NULL AND client_notes IS NULL) THEN
    RAISE EXCEPTION 'The skipped assignment holds a change nobody was allowed to make';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.therapist_assignments WHERE id = '17620000-0000-4000-8000-0000000000e3'
      AND connection_id = '17620000-0000-4000-8000-0000000000c2' AND status = 'expired') THEN
    RAISE EXCEPTION 'The overdue assignment did not expire';
  END IF;
  IF (SELECT count(*) FROM public.therapist_assignments) <> 4
     OR (SELECT count(*) FROM public.therapist_notes) <> 1
     OR (SELECT count(*) FROM public.therapy_access_log) <> 3
     OR (SELECT count(*) FROM public.therapy_access_log WHERE action = 'forged') <> 0 THEN
    RAISE EXCEPTION 'Unexpected rows: % assignments, % notes, % log entries',
      (SELECT count(*) FROM public.therapist_assignments), (SELECT count(*) FROM public.therapist_notes),
      (SELECT count(*) FROM public.therapy_access_log);
  END IF;
END $$;

ROLLBACK;
