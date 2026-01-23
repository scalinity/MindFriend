-- ============================================================================
-- Email Summary System Schema
-- ============================================================================
-- Purpose: Complete email system with queue-based processing, rate limiting,
--          crisis suppression, and dead-letter queue for failed sends
-- Tables: email_preferences, email_queue, email_logs, email_dead_letter_queue
-- ============================================================================

-- Drop existing if needed (development only)
-- DO $$
-- BEGIN
--   DROP TRIGGER IF EXISTS on_auth_user_created_email_prefs ON auth.users CASCADE;
--   DROP FUNCTION IF EXISTS create_default_email_preferences() CASCADE;
--   DROP FUNCTION IF EXISTS claim_emails_for_processing(TEXT, INT) CASCADE;
--   DROP TABLE IF EXISTS email_dead_letter_queue CASCADE;
--   DROP TABLE IF EXISTS email_logs CASCADE;
--   DROP TABLE IF EXISTS email_queue CASCADE;
--   DROP TABLE IF EXISTS email_preferences CASCADE;
-- END $$;

-- ============================================================================
-- Table: email_preferences
-- ============================================================================
-- Stores user email preferences including timezone, send hour, and subscription types
CREATE TABLE IF NOT EXISTS email_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  timezone TEXT NOT NULL DEFAULT 'UTC',
  preferred_send_hour SMALLINT NOT NULL DEFAULT 9 CHECK (preferred_send_hour BETWEEN 0 AND 23),
  weekly_summary BOOLEAN NOT NULL DEFAULT false,
  streak_celebration BOOLEAN NOT NULL DEFAULT false,
  achievement_unlock BOOLEAN NOT NULL DEFAULT true,
  lapsed_nudge BOOLEAN NOT NULL DEFAULT false,
  monthly_report BOOLEAN NOT NULL DEFAULT false,
  unsubscribed_at TIMESTAMPTZ DEFAULT NULL,
  unsubscribe_reason TEXT DEFAULT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT unique_user_email_prefs UNIQUE(user_id)
);

CREATE INDEX IF NOT EXISTS idx_email_preferences_user_id ON email_preferences(user_id);
CREATE INDEX IF NOT EXISTS idx_email_preferences_unsubscribed ON email_preferences(unsubscribed_at) WHERE unsubscribed_at IS NOT NULL;

-- RLS Policies for email_preferences
ALTER TABLE email_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "Users can read own email preferences"
  ON email_preferences FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY IF NOT EXISTS "Users can update own email preferences"
  ON email_preferences FOR UPDATE
  USING (auth.uid() = user_id);

-- Service role can insert/select (for initialization and email processing)
CREATE POLICY IF NOT EXISTS "Service role manages email preferences"
  ON email_preferences FOR ALL
  USING (auth.role() = 'service_role');

-- ============================================================================
-- Table: email_queue
-- ============================================================================
-- Asynchronous email queue with concurrent-safe processing via row locking
CREATE TABLE IF NOT EXISTS email_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email_type TEXT NOT NULL CHECK (email_type IN ('weekly_summary', 'streak_celebration', 'achievement_unlock', 'lapsed_nudge', 'monthly_report')),
  template_version TEXT NOT NULL DEFAULT 'v1',
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'sent', 'failed')),
  scheduled_for TIMESTAMPTZ NOT NULL,
  retry_count SMALLINT NOT NULL DEFAULT 0,
  last_error TEXT DEFAULT NULL,
  locked_by TEXT DEFAULT NULL,
  locked_at TIMESTAMPTZ DEFAULT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_email_queue_user_id ON email_queue(user_id);
CREATE INDEX IF NOT EXISTS idx_email_queue_status_scheduled ON email_queue(status, scheduled_for) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_email_queue_processing_locked ON email_queue(status, locked_at) WHERE status = 'processing';

-- RLS Policies for email_queue
ALTER TABLE email_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "Service role manages email queue"
  ON email_queue FOR ALL
  USING (auth.role() = 'service_role');

-- ============================================================================
-- Table: email_logs
-- ============================================================================
-- Append-only audit log for all email sends (success, skipped, failed)
CREATE TABLE IF NOT EXISTS email_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email_type TEXT NOT NULL,
  template_version TEXT NOT NULL,
  message_id TEXT UNIQUE,
  status TEXT NOT NULL CHECK (status IN ('sent', 'skipped', 'failed')),
  skipped_reason TEXT DEFAULT NULL,
  failure_reason TEXT DEFAULT NULL,
  sent_at TIMESTAMPTZ DEFAULT NULL,
  opened_at TIMESTAMPTZ DEFAULT NULL,
  clicked_at TIMESTAMPTZ DEFAULT NULL,
  bounce_type TEXT DEFAULT NULL,
  bounce_reason TEXT DEFAULT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_email_logs_user_id ON email_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_email_logs_sent_at ON email_logs(sent_at) WHERE sent_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_email_logs_message_id ON email_logs(message_id) WHERE message_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_email_logs_rate_limit ON email_logs(user_id, sent_at) WHERE status = 'sent' AND sent_at > NOW() - INTERVAL '7 days';

-- RLS Policies for email_logs
ALTER TABLE email_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "Users can read own email logs"
  ON email_logs FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY IF NOT EXISTS "Service role manages email logs"
  ON email_logs FOR ALL
  USING (auth.role() = 'service_role');

-- ============================================================================
-- Table: email_dead_letter_queue
-- ============================================================================
-- Stores emails that failed after max retries (3) for manual review
CREATE TABLE IF NOT EXISTS email_dead_letter_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email_type TEXT NOT NULL,
  template_version TEXT NOT NULL,
  payload JSONB NOT NULL,
  failure_count SMALLINT NOT NULL,
  last_error TEXT NOT NULL,
  original_scheduled_for TIMESTAMPTZ NOT NULL,
  moved_to_dlq_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_by UUID DEFAULT NULL REFERENCES auth.users(id),
  reviewed_at TIMESTAMPTZ DEFAULT NULL,
  resolution_notes TEXT DEFAULT NULL
);

CREATE INDEX IF NOT EXISTS idx_email_dlq_user_id ON email_dead_letter_queue(user_id);
CREATE INDEX IF NOT EXISTS idx_email_dlq_reviewed ON email_dead_letter_queue(reviewed_at) WHERE reviewed_at IS NULL;

-- RLS Policies for email_dead_letter_queue
ALTER TABLE email_dead_letter_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "Service role manages DLQ"
  ON email_dead_letter_queue FOR ALL
  USING (auth.role() = 'service_role');

-- ============================================================================
-- Table: email_suppression_list
-- ============================================================================
-- Stores permanently bounced/complained emails to prevent sending to invalid addresses
CREATE TABLE IF NOT EXISTS email_suppression_list (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  reason TEXT NOT NULL,
  bounce_type TEXT DEFAULT NULL CHECK (bounce_type IN ('permanent', 'complaint')),
  suppressed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  unsuppressed_at TIMESTAMPTZ DEFAULT NULL,
  CONSTRAINT unique_user_email_suppression UNIQUE(user_id, email)
);

CREATE INDEX IF NOT EXISTS idx_email_suppression_user_id ON email_suppression_list(user_id);
CREATE INDEX IF NOT EXISTS idx_email_suppression_email ON email_suppression_list(email);
CREATE INDEX IF NOT EXISTS idx_email_suppression_suppressed ON email_suppression_list(suppressed_at) WHERE unsuppressed_at IS NULL;

-- RLS Policies for email_suppression_list
ALTER TABLE email_suppression_list ENABLE ROW LEVEL SECURITY;

CREATE POLICY IF NOT EXISTS "Service role manages suppression list"
  ON email_suppression_list FOR ALL
  USING (auth.role() = 'service_role');

-- ============================================================================
-- Function: create_default_email_preferences
-- ============================================================================
-- Initialization trigger: auto-create default email preferences for new users
CREATE OR REPLACE FUNCTION create_default_email_preferences()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO email_preferences (
    user_id,
    timezone,
    preferred_send_hour,
    weekly_summary,
    streak_celebration,
    achievement_unlock,
    lapsed_nudge,
    monthly_report
  )
  VALUES (
    NEW.id,
    'UTC',
    9,
    false,
    false,
    true,
    false,
    false
  )
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on auth.users insert
DROP TRIGGER IF EXISTS on_auth_user_created_email_prefs ON auth.users;
CREATE TRIGGER on_auth_user_created_email_prefs
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION create_default_email_preferences();

-- ============================================================================
-- Function: claim_emails_for_processing
-- ============================================================================
-- Concurrent-safe queue claim function using SELECT FOR UPDATE SKIP LOCKED
-- Prevents race conditions with multiple workers
CREATE OR REPLACE FUNCTION claim_emails_for_processing(
  p_worker_id TEXT,
  p_batch_size INT DEFAULT 10
)
RETURNS SETOF email_queue AS $$
BEGIN
  RETURN QUERY
  UPDATE email_queue
  SET 
    status = 'processing',
    locked_by = p_worker_id,
    locked_at = NOW(),
    updated_at = NOW()
  WHERE id IN (
    SELECT id FROM email_queue
    WHERE status = 'pending' AND scheduled_for <= NOW()
    ORDER BY scheduled_for ASC
    LIMIT p_batch_size
    FOR UPDATE SKIP LOCKED
  )
  RETURNING email_queue.*;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Function: cleanup_stale_locks
-- ============================================================================
-- Releases processing locks older than 10 minutes from crashed workers
-- Prevents deadlocked emails from being permanently stuck
CREATE OR REPLACE FUNCTION cleanup_stale_locks(
  p_lock_timeout_minutes INT DEFAULT 10
)
RETURNS INT AS $$
DECLARE
  v_released_count INT;
BEGIN
  UPDATE email_queue
  SET 
    status = 'pending',
    locked_by = NULL,
    locked_at = NULL,
    updated_at = NOW()
  WHERE status = 'processing' 
    AND locked_at < NOW() - (p_lock_timeout_minutes || ' minutes')::INTERVAL;
  
  GET DIAGNOSTICS v_released_count = ROW_COUNT;
  RETURN v_released_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Permissions
-- ============================================================================
-- Grant service role full access to all tables and functions
GRANT ALL ON email_preferences, email_queue, email_logs, email_dead_letter_queue, email_suppression_list TO service_role;
GRANT EXECUTE ON FUNCTION create_default_email_preferences() TO service_role;
GRANT EXECUTE ON FUNCTION claim_emails_for_processing(TEXT, INT) TO service_role;
GRANT EXECUTE ON FUNCTION cleanup_stale_locks(INT) TO service_role;