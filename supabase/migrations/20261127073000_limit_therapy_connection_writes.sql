-- Direct writes to therapy_connections are limited to what the invitation flow gives a client:
-- change the sharing flags of their own connection, or revoke or end it with ended_at, as
-- TherapyIntegrationService does in released clients 1.0.4, 1.0.5 and 2.0. therapist-invite creates
-- invitations and therapist-accept accepts them, both as the service role, so clients no longer
-- insert rows, therapists no longer update them, and anon has no access.
--
-- Column grants decide which columns a client may set. They cannot limit the values written to
-- status, and a policy cannot read the old row (a subquery on this table from its own policy is
-- rejected as recursive), so a trigger compares old and new: anon and authenticated may change
-- status or ended_at only to leave the connection revoked or ended with ended_at set. Without it a
-- client could set a pending invitation to active without the therapist accepting.
REVOKE ALL ON public.therapy_connections FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.therapy_connections TO authenticated;
GRANT UPDATE (share_mood, share_journal, share_assessments, share_exercises, crisis_alerts_enabled, status, ended_at)
  ON public.therapy_connections TO authenticated;

DROP POLICY "Clients can insert own connections" ON public.therapy_connections;
DROP POLICY "Therapists accept connections" ON public.therapy_connections;

CREATE FUNCTION public.limit_client_connection_status() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  IF current_user IN ('anon', 'authenticated')
     AND (NEW.status, NEW.ended_at) IS DISTINCT FROM (OLD.status, OLD.ended_at)
     AND (NEW.status IN ('revoked', 'ended') AND NEW.ended_at IS NOT NULL) IS NOT TRUE THEN
    RAISE EXCEPTION 'A connection can only be revoked or ended directly'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.limit_client_connection_status() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER limit_client_connection_status BEFORE UPDATE OF status, ended_at ON public.therapy_connections
  FOR EACH ROW EXECUTE FUNCTION public.limit_client_connection_status();
