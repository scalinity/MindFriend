-- Synthetic rollback fixture: direct writes to therapy_connections. A client may change the sharing
-- flags of their own connection and revoke or end it, as released clients 1.0.4, 1.0.5 and 2.0 do,
-- and nothing else. A therapist writes nothing directly (therapist-accept accepts, as the service
-- role), and anon has no access at all.
BEGIN;

INSERT INTO public.supported_languages(code,name,native_name,is_active) VALUES ('en','English','English',true) ON CONFLICT DO NOTHING;
INSERT INTO public.level_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO public.skill_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
SET LOCAL statement_timeout = '20s';
INSERT INTO auth.users(id, email, raw_user_meta_data) VALUES
 ('17610000-0000-4000-8000-000000000001', 'client@example.invalid', '{}'),
 ('17610000-0000-4000-8000-000000000002', 'therapist@example.invalid', '{}'),
 ('17610000-0000-4000-8000-000000000003', 'second-client@example.invalid', '{}'),
 ('17610000-0000-4000-8000-000000000004', 'second-therapist@example.invalid', '{}');
INSERT INTO public.profiles(id) VALUES
 ('17610000-0000-4000-8000-000000000001'), ('17610000-0000-4000-8000-000000000002'),
 ('17610000-0000-4000-8000-000000000003'), ('17610000-0000-4000-8000-000000000004') ON CONFLICT(id) DO NOTHING;
INSERT INTO public.therapist_accounts(id, user_id) VALUES
 ('17610000-0000-4000-8000-0000000000a1', '17610000-0000-4000-8000-000000000002'),
 ('17610000-0000-4000-8000-0000000000a2', '17610000-0000-4000-8000-000000000004');

-- As the service role: the first client's pending invitation (therapist-invite), and the second
-- client's accepted connection (therapist-accept clears the hash and sets connected_at).
SET LOCAL ROLE service_role;
INSERT INTO public.therapy_connections(id, client_id, therapist_id, status, invited_by, invitation_token_hash, invitation_expires_at)
VALUES ('17610000-0000-4000-8000-0000000000c1', '17610000-0000-4000-8000-000000000001', '17610000-0000-4000-8000-0000000000a1',
        'pending', 'client', encode(sha256('synthetic-token-1'::bytea), 'hex'), now() + interval '7 days');
INSERT INTO public.therapy_connections(id, client_id, therapist_id, status, invited_by, connected_at)
VALUES ('17610000-0000-4000-8000-0000000000c2', '17610000-0000-4000-8000-000000000003', '17610000-0000-4000-8000-0000000000a1',
        'active', 'client', now());
RESET ROLE;

CREATE FUNCTION pg_temp.act_as(person text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', person, 'role', current_user)::text, true);
  PERFORM set_config('request.jwt.claim.sub', COALESCE(person, ''), true);
END $$;
-- The statement must fail with a privilege error (missing grant, policy check or trigger).
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
-- The statement must change exactly one row.
CREATE FUNCTION pg_temp.allowed(statement text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE changed integer;
BEGIN
  EXECUTE statement;
  GET DIAGNOSTICS changed = ROW_COUNT;
  IF changed <> 1 THEN RAISE EXCEPTION 'Expected one row changed as %, got %: %', current_user, changed, statement; END IF;
END $$;
DO $$ BEGIN
  EXECUTE format('GRANT USAGE ON SCHEMA %I TO anon, authenticated, service_role',
    (SELECT nspname FROM pg_namespace WHERE oid = pg_my_temp_schema()));
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.act_as(text), pg_temp.denied(text), pg_temp.refused(text), pg_temp.allowed(text)
  TO anon, authenticated, service_role;

-- Grants: anon has nothing; authenticated reads, and updates only the sharing flags, status and ended_at.
DO $$
DECLARE writable text[];
BEGIN
  IF has_table_privilege('anon', 'public.therapy_connections', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
     OR has_any_column_privilege('anon', 'public.therapy_connections', 'SELECT, INSERT, UPDATE, REFERENCES') THEN
    RAISE EXCEPTION 'anon holds a privilege on therapy_connections';
  END IF;
  IF has_table_privilege('authenticated', 'public.therapy_connections', 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
     OR has_any_column_privilege('authenticated', 'public.therapy_connections', 'INSERT, REFERENCES') THEN
    RAISE EXCEPTION 'authenticated holds a write privilege on the whole of therapy_connections';
  END IF;
  SELECT array_agg(attname::text ORDER BY attname) INTO writable FROM pg_attribute
  WHERE attrelid = 'public.therapy_connections'::regclass AND attnum > 0 AND NOT attisdropped
    AND has_column_privilege('authenticated', attrelid, attnum, 'UPDATE');
  IF writable IS DISTINCT FROM ARRAY['crisis_alerts_enabled', 'ended_at', 'share_assessments', 'share_exercises',
                                     'share_journal', 'share_mood', 'status'] THEN
    RAISE EXCEPTION 'authenticated can update %', writable;
  END IF;
END $$;

-- The first client: no insert or delete, no column outside the sharing flags, status and ended_at,
-- and no status other than revoked or ended with ended_at. Then their sharing change succeeds.
SET LOCAL ROLE authenticated;
SELECT pg_temp.act_as('17610000-0000-4000-8000-000000000001');
SELECT pg_temp.denied($q$INSERT INTO public.therapy_connections(client_id, therapist_id, status, invited_by, connected_at)
  VALUES ('17610000-0000-4000-8000-000000000001', '17610000-0000-4000-8000-0000000000a2', 'active', 'client', now())$q$);
SELECT pg_temp.denied($q$UPDATE public.therapy_connections SET status = 'active' WHERE id = '17610000-0000-4000-8000-0000000000c1'$q$);
SELECT pg_temp.denied($q$UPDATE public.therapy_connections SET status = NULL WHERE id = '17610000-0000-4000-8000-0000000000c1'$q$);
SELECT pg_temp.denied($q$UPDATE public.therapy_connections SET status = 'revoked' WHERE id = '17610000-0000-4000-8000-0000000000c1'$q$);
SELECT pg_temp.denied($q$UPDATE public.therapy_connections SET ended_at = now() WHERE id = '17610000-0000-4000-8000-0000000000c1'$q$);
SELECT pg_temp.denied(format('UPDATE public.therapy_connections SET %s WHERE id = %L', assignment, '17610000-0000-4000-8000-0000000000c1'))
FROM unnest(ARRAY[
  $a$therapist_id = '17610000-0000-4000-8000-0000000000a2'$a$,
  $a$client_id = '17610000-0000-4000-8000-000000000004'$a$,
  $a$invitation_token_hash = NULL$a$,
  $a$invitation_expires_at = now() + interval '1 year'$a$,
  $a$connected_at = now()$a$,
  $a$invited_by = 'therapist'$a$,
  $a$id = gen_random_uuid()$a$
]) AS assignment;
SELECT pg_temp.denied($q$DELETE FROM public.therapy_connections WHERE id = '17610000-0000-4000-8000-0000000000c1'$q$);
-- updateSharingSettings, with PostgREST's returned representation.
SELECT pg_temp.allowed($q$UPDATE public.therapy_connections SET share_mood = false, share_journal = true,
  share_assessments = false, share_exercises = true, crisis_alerts_enabled = false
  WHERE id = '17610000-0000-4000-8000-0000000000c1' RETURNING *$q$);

-- Another person cannot change the first client's connection.
SELECT pg_temp.act_as('17610000-0000-4000-8000-000000000003');
SELECT pg_temp.refused($q$UPDATE public.therapy_connections SET share_journal = false WHERE id = '17610000-0000-4000-8000-0000000000c1'$q$);
SELECT pg_temp.refused($q$UPDATE public.therapy_connections SET status = 'revoked', ended_at = now() WHERE id = '17610000-0000-4000-8000-0000000000c1'$q$);

-- The therapist changes nothing, on the pending invitation or on the accepted connection.
SELECT pg_temp.act_as('17610000-0000-4000-8000-000000000002');
SELECT pg_temp.refused(format('UPDATE public.therapy_connections SET %s WHERE id = %L', assignment, connection))
FROM unnest(ARRAY['17610000-0000-4000-8000-0000000000c1', '17610000-0000-4000-8000-0000000000c2']) AS connection,
     unnest(ARRAY[
  $a$share_journal = false$a$,
  $a$share_mood = true, share_assessments = true, share_exercises = false, crisis_alerts_enabled = true$a$,
  $a$status = 'active'$a$,
  $a$status = 'ended', ended_at = now()$a$,
  $a$client_id = '17610000-0000-4000-8000-000000000004'$a$,
  $a$invitation_token_hash = NULL, invitation_expires_at = now() + interval '1 year'$a$
]) AS assignment;
SELECT pg_temp.denied($q$INSERT INTO public.therapy_connections(client_id, therapist_id, status, invited_by)
  VALUES ('17610000-0000-4000-8000-000000000004', '17610000-0000-4000-8000-0000000000a1', 'active', 'therapist')$q$);
SELECT pg_temp.denied($q$DELETE FROM public.therapy_connections WHERE therapist_id = '17610000-0000-4000-8000-0000000000a1'$q$);

-- The first client revokes the invitation (revokeConnection). A revoked connection cannot be reopened.
SELECT pg_temp.act_as('17610000-0000-4000-8000-000000000001');
SELECT pg_temp.allowed($q$UPDATE public.therapy_connections SET status = 'revoked', ended_at = now()
  WHERE id = '17610000-0000-4000-8000-0000000000c1' RETURNING *$q$);
SELECT pg_temp.denied($q$UPDATE public.therapy_connections SET status = 'pending' WHERE id = '17610000-0000-4000-8000-0000000000c1'$q$);
SELECT pg_temp.denied($q$UPDATE public.therapy_connections SET status = 'active', ended_at = NULL WHERE id = '17610000-0000-4000-8000-0000000000c1'$q$);
SELECT pg_temp.denied($q$UPDATE public.therapy_connections SET ended_at = NULL WHERE id = '17610000-0000-4000-8000-0000000000c1'$q$);

-- The second client changes sharing on the accepted connection, cannot send it back to pending,
-- and ends it.
SELECT pg_temp.act_as('17610000-0000-4000-8000-000000000003');
SELECT pg_temp.allowed($q$UPDATE public.therapy_connections SET crisis_alerts_enabled = false
  WHERE id = '17610000-0000-4000-8000-0000000000c2' RETURNING *$q$);
SELECT pg_temp.denied($q$UPDATE public.therapy_connections SET status = 'pending' WHERE id = '17610000-0000-4000-8000-0000000000c2'$q$);
SELECT pg_temp.allowed($q$UPDATE public.therapy_connections SET status = 'ended', ended_at = now()
  WHERE id = '17610000-0000-4000-8000-0000000000c2' RETURNING *$q$);
RESET ROLE;

-- anon: no read and no write.
SET LOCAL ROLE anon;
SELECT pg_temp.act_as(NULL);
SELECT pg_temp.denied($q$SELECT id FROM public.therapy_connections$q$);
SELECT pg_temp.denied($q$INSERT INTO public.therapy_connections(client_id, therapist_id, status, invited_by)
  VALUES ('17610000-0000-4000-8000-000000000004', '17610000-0000-4000-8000-0000000000a2', 'active', 'client')$q$);
SELECT pg_temp.denied($q$UPDATE public.therapy_connections SET share_journal = true$q$);
SELECT pg_temp.denied($q$DELETE FROM public.therapy_connections$q$);
RESET ROLE;

-- The service role still changes status freely: therapist-invite reopens the revoked connection
-- with a new hash, and therapist-accept accepts it.
SET LOCAL ROLE service_role;
SELECT pg_temp.allowed($q$UPDATE public.therapy_connections SET status = 'pending',
  invitation_token_hash = encode(sha256('synthetic-token-2'::bytea), 'hex'), invitation_expires_at = now() + interval '7 days'
  WHERE id = '17610000-0000-4000-8000-0000000000c1'$q$);
SELECT pg_temp.allowed($q$UPDATE public.therapy_connections SET status = 'active', connected_at = now(),
  invitation_token_hash = NULL, invitation_expires_at = NULL
  WHERE id = '17610000-0000-4000-8000-0000000000c1' AND invitation_token_hash = encode(sha256('synthetic-token-2'::bytea), 'hex')$q$);
RESET ROLE;

-- Final state: only the writes above took effect.
DO $$ BEGIN
  IF (SELECT count(*) FROM public.therapy_connections) <> 2 THEN
    RAISE EXCEPTION 'Expected two connections, found %', (SELECT count(*) FROM public.therapy_connections);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.therapy_connections WHERE id = '17610000-0000-4000-8000-0000000000c1'
      AND client_id = '17610000-0000-4000-8000-000000000001' AND therapist_id = '17610000-0000-4000-8000-0000000000a1'
      AND status = 'active' AND invited_by = 'client' AND ended_at IS NOT NULL
      AND share_mood = false AND share_journal = true AND share_assessments = false AND share_exercises = true
      AND crisis_alerts_enabled = false) THEN
    RAISE EXCEPTION 'The first connection holds a change the client or therapist was not allowed to make';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.therapy_connections WHERE id = '17610000-0000-4000-8000-0000000000c2'
      AND client_id = '17610000-0000-4000-8000-000000000003' AND therapist_id = '17610000-0000-4000-8000-0000000000a1'
      AND status = 'ended' AND ended_at IS NOT NULL AND invitation_token_hash IS NULL
      AND share_mood = true AND share_journal = false AND share_assessments = true AND share_exercises = false
      AND crisis_alerts_enabled = false) THEN
    RAISE EXCEPTION 'The second connection holds a change the client or therapist was not allowed to make';
  END IF;
END $$;

ROLLBACK;
