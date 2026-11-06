BEGIN;
-- Column grants protect direct Data API writes while retaining the existing
-- authenticated training/availability RPCs, which validate their own transitions.
REVOKE INSERT, UPDATE ON public.therapist_accounts, public.listeners FROM PUBLIC, anon, authenticated;
GRANT INSERT (user_id,license_number,license_state,npi_number,practice_name,practice_address,specialties,accepts_invites)
  ON public.therapist_accounts TO authenticated;
GRANT UPDATE (license_number,license_state,npi_number,practice_name,practice_address,specialties,accepts_invites)
  ON public.therapist_accounts TO authenticated;
GRANT INSERT (user_id,specializations,languages,available_hours,max_sessions_per_week,accepts_voice_calls,accepts_crisis_bridge,bio,display_name)
  ON public.listeners TO authenticated;
GRANT UPDATE (specializations,languages,available_hours,max_sessions_per_week,accepts_voice_calls,accepts_crisis_bridge,bio,display_name)
  ON public.listeners TO authenticated;

CREATE FUNCTION public.invalidate_changed_therapist_license() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  IF current_user IN ('anon','authenticated') AND (
    NEW.license_number IS DISTINCT FROM OLD.license_number
    OR NEW.license_state IS DISTINCT FROM OLD.license_state
    OR NEW.npi_number IS DISTINCT FROM OLD.npi_number
  ) THEN
    NEW.is_verified := false;
    NEW.license_verified_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.invalidate_changed_therapist_license() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER invalidate_changed_therapist_license BEFORE UPDATE ON public.therapist_accounts
  FOR EACH ROW EXECUTE FUNCTION public.invalidate_changed_therapist_license();
COMMIT;
