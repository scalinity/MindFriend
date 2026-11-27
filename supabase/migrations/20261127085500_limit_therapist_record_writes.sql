-- Direct writes to therapist_assignments, therapist_notes and therapy_access_log are limited to what
-- released clients 1.0.4, 1.0.5 and 2.0 do: a client marks an assignment on their own connection
-- completed or skipped (TherapyIntegrationService.completeAssignment and skipAssignment) and reads
-- their assignments and access log. therapist-api creates assignments, and chat, therapist-api and
-- therapist-accept write the access log, all as the service role; nothing outside the service role
-- reads or writes therapist_notes. So anon has no access, a client updates only an assignment's
-- status, completed_at and client_notes, therapists no longer create assignments or keep notes
-- directly, and the access log is read-only.
--
-- completeAssignment means to set completed_at and client_notes. Released builds send those keys as
-- completedAt and clientNotes (supabase-swift 2.55.4 does not convert keys), which PostgREST rejects
-- before the update reaches the database, so completing an assignment fails with or without this
-- change; skipping works. The grant names the real columns so a corrected client needs no migration.
--
-- No trigger limits the status value: a client can set any status the check constraint allows, but
-- only on assignments of their own connections, so it changes nothing anyone else wrote.
--
-- log_therapy_access and expire_overdue_assignments are SECURITY DEFINER and anyone could run them,
-- which would write these tables past the grants below. Nothing calls them, so only the service
-- role keeps them.
REVOKE ALL ON public.therapist_assignments FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.therapist_assignments TO authenticated;
GRANT UPDATE (status, completed_at, client_notes) ON public.therapist_assignments TO authenticated;
DROP POLICY "Therapists create assignments" ON public.therapist_assignments;

REVOKE ALL ON public.therapist_notes FROM PUBLIC, anon, authenticated;
DROP POLICY "Therapist notes private" ON public.therapist_notes;

REVOKE ALL ON public.therapy_access_log FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.therapy_access_log TO authenticated;

REVOKE ALL ON FUNCTION public.log_therapy_access(uuid, uuid, text, text, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.expire_overdue_assignments() FROM PUBLIC, anon, authenticated;
