BEGIN;
ALTER POLICY "Service manages queue" ON public.email_queue
  TO service_role USING (true) WITH CHECK (true);
ALTER POLICY "Service manages dlq" ON public.email_dead_letter_queue
  TO service_role USING (true) WITH CHECK (true);
REVOKE ALL ON TABLE public.email_queue, public.email_dead_letter_queue FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.email_queue, public.email_dead_letter_queue TO service_role;
COMMIT;
