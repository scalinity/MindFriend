-- Unsaved memory suggestions can be saved for 7 days. After that the app hides them, so
-- nobody can dismiss them, and support_expire_candidates() (which blanks their text) was
-- never scheduled. Run it daily. SQL only: no HTTP call, no credential.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_cron')
     AND NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'support-expire-memory-candidates') THEN
    PERFORM cron.schedule(
      'support-expire-memory-candidates',
      '23 4 * * *',
      'SELECT public.support_expire_candidates();'
    );
  END IF;
END
$$;
