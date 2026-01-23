-- Migration: GDPR audit logging for data deletion and access
-- Purpose: Track all GDPR-related data operations for compliance audits

CREATE TABLE IF NOT EXISTS audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  action TEXT NOT NULL,
  table_name TEXT NOT NULL,
  record_id TEXT,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reason TEXT,
  details JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS for audit log
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

-- Policy: Only admins can read audit logs
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'audit_log' AND policyname = 'Admins read all audit logs'
  ) THEN
    CREATE POLICY "Admins read all audit logs"
      ON audit_log FOR SELECT
      TO authenticated
      USING (false);  -- Placeholder - adjust based on admin role
  END IF;
END $$;

-- Index for efficient audit queries
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'audit_log' AND column_name = 'user_id'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_audit_log_user_id ON audit_log(user_id);
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'audit_log' AND column_name = 'table_name'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_audit_log_table_name ON audit_log(table_name);
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'audit_log' AND column_name = 'created_at'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON audit_log(created_at);
  END IF;
END $$;

-- Retention: Keep audit logs for 2 years (GDPR requirement)
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
      'cleanup-audit-logs-2years',
      '0 5 * * 0',  -- 5 AM on Sundays
      'DELETE FROM audit_log WHERE created_at < NOW() - INTERVAL ''730 days''' 
    );
  END IF;
END $$;
