-- Migration: GDPR Article 5(1)(e) - Storage Limitation
-- Purpose: Implement automatic data retention and deletion policies

-- Enable pg_cron extension for scheduled jobs
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- Grant execute to postgres user (required for pg_cron)
GRANT USAGE ON SCHEMA pg_catalog TO postgres;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'cron'
    AND p.proname = 'schedule'
    AND p.pronargs = 3
  ) THEN
    GRANT EXECUTE ON FUNCTION cron.schedule(text, text, text) TO postgres;
  END IF;
END $$;

-- 1. Add retention tracking to email_logs (90-day retention for GDPR compliance)
-- Clean up old email logs automatically
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'cron'
    AND p.proname = 'schedule'
    AND p.pronargs = 3
  ) THEN
    PERFORM cron.schedule(
      'cleanup-email-logs-90days',
      '0 3 * * *',  -- 3 AM daily
      'DELETE FROM email_logs WHERE created_at < NOW() - INTERVAL ''90 days'' AND status IN (''sent'', ''skipped'', ''failed'')'
    );

    -- 2. Add retention cleanup for email_dead_letter_queue (30-day retention)
    -- DLQ entries kept shorter since they represent failures needing investigation
    PERFORM cron.schedule(
      'cleanup-email-dlq-30days',
      '0 4 * * *',  -- 4 AM daily
      'DELETE FROM email_dead_letter_queue WHERE moved_to_dlq_at < NOW() - INTERVAL ''30 days''' 
    );

    -- 3. Clean up stale email_queue entries (pending/processing older than 7 days)
    -- Prevents database bloat from stuck processing records
    PERFORM cron.schedule(
      'cleanup-email-queue-stale',
      '0 2 * * *',  -- 2 AM daily
      'DELETE FROM email_queue WHERE status IN (''pending'', ''processing'') AND created_at < NOW() - INTERVAL ''7 days'' AND retry_count >= 3'
    );
  END IF;
END $$;

-- 4. Enforce user deletion cascade on email tables (GDPR Article 17 - Right to Erasure)
-- When a user is deleted, all their email data must be deleted automatically
ALTER TABLE IF EXISTS email_logs 
  DROP CONSTRAINT IF EXISTS email_logs_user_id_fkey,
  ADD CONSTRAINT email_logs_user_id_fkey 
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE IF EXISTS email_queue 
  DROP CONSTRAINT IF EXISTS email_queue_user_id_fkey,
  ADD CONSTRAINT email_queue_user_id_fkey 
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE IF EXISTS email_dead_letter_queue 
  DROP CONSTRAINT IF EXISTS email_dead_letter_queue_user_id_fkey,
  ADD CONSTRAINT email_dead_letter_queue_user_id_fkey 
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE IF EXISTS email_preferences 
  DROP CONSTRAINT IF EXISTS email_preferences_user_id_fkey,
  ADD CONSTRAINT email_preferences_user_id_fkey 
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE IF EXISTS email_suppression_list 
  DROP CONSTRAINT IF EXISTS email_suppression_list_user_id_fkey,
  ADD CONSTRAINT email_suppression_list_user_id_fkey 
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- 5. Create audit function to log GDPR-related deletions
CREATE OR REPLACE FUNCTION log_data_deletion()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO audit_log (action, table_name, record_id, user_id, reason)
  VALUES (
    'DELETE',
    TG_TABLE_NAME,
    COALESCE(NEW.id, OLD.id)::TEXT,
    COALESCE(NEW.user_id, OLD.user_id),
    'GDPR retention policy enforcement'
  );
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach audit trigger to email_logs
DROP TRIGGER IF EXISTS audit_email_logs_deletion ON email_logs;
CREATE TRIGGER audit_email_logs_deletion
  AFTER DELETE ON email_logs
  FOR EACH ROW
  EXECUTE FUNCTION log_data_deletion();

-- 6. Add metadata columns for GDPR tracking
ALTER TABLE email_logs ADD COLUMN IF NOT EXISTS retention_until TIMESTAMPTZ;
ALTER TABLE email_dead_letter_queue ADD COLUMN IF NOT EXISTS retention_until TIMESTAMPTZ;

-- Set initial retention dates
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'email_logs' AND column_name = 'retention_until'
  ) THEN
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'email_logs' AND column_name = 'created_at'
    ) THEN
      UPDATE email_logs SET retention_until = created_at + INTERVAL '90 days'
      WHERE retention_until IS NULL;
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'email_dead_letter_queue' AND column_name = 'retention_until'
  ) THEN
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'email_dead_letter_queue' AND column_name = 'moved_to_dlq_at'
    ) THEN
      UPDATE email_dead_letter_queue SET retention_until = moved_to_dlq_at + INTERVAL '30 days'
      WHERE retention_until IS NULL;
    END IF;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'email_logs' AND column_name = 'retention_until'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_email_logs_retention_until ON email_logs(retention_until);
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'email_dead_letter_queue' AND column_name = 'retention_until'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_email_dlq_retention_until ON email_dead_letter_queue(retention_until);
  END IF;
END $$;
