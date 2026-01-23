-- Security Audit Logging Infrastructure (Audit Issue #8)
-- Severity: P2 - Monitoring Gap
--
-- Problem: Blocked profile modification attempts (trigger exceptions) are not logged.
--          This prevents detection of:
--          - Privilege escalation attempts
--          - Quota exhaustion attacks
--          - Subscription tier bypass attempts
--
-- Solution: Create security audit table and log all privilege escalation attempts
--           via trigger on profile modifications

-- =============================================================================
-- MARK: - Create Audit Log Table
-- =============================================================================

CREATE TABLE IF NOT EXISTS security_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Event identification
    event_type TEXT NOT NULL,  -- e.g., 'PRIVILEGE_ESCALATION_ATTEMPT', 'QUOTA_BYPASS_ATTEMPT'
    severity TEXT NOT NULL,    -- 'low', 'medium', 'high', 'critical'

    -- User information
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Event details
    table_name TEXT NOT NULL,  -- 'profiles', etc.
    operation TEXT NOT NULL,   -- 'UPDATE', 'INSERT'

    -- What they tried to do
    attempted_changes JSONB,   -- {"subscription_tier": "premium", "daily_ai_quota": 999}

    -- Context
    ip_address INET,           -- For correlation
    user_agent TEXT,           -- For correlation

    -- Status
    blocked BOOLEAN NOT NULL DEFAULT TRUE,  -- Was the operation blocked?
    reason TEXT,               -- Why it was blocked

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_security_audit_user_id ON security_audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_security_audit_event_type ON security_audit_log(event_type);
CREATE INDEX IF NOT EXISTS idx_security_audit_severity ON security_audit_log(severity);
CREATE INDEX IF NOT EXISTS idx_security_audit_created_at ON security_audit_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_security_audit_blocked ON security_audit_log(blocked);

-- =============================================================================
-- MARK: - Enable RLS on Audit Log
-- =============================================================================

ALTER TABLE security_audit_log ENABLE ROW LEVEL SECURITY;

-- Only authenticated users can read their own audit logs
CREATE POLICY "Users can read own security audit logs"
  ON security_audit_log
  FOR SELECT
  USING (auth.uid() = user_id);

-- Service role can read all logs (for investigation)
CREATE POLICY "Service role can read all security audit logs"
  ON security_audit_log
  FOR SELECT
  USING (current_setting('role', true) = 'service_role');

-- Only system can insert (via triggers)
CREATE POLICY "Only system can insert audit logs"
  ON security_audit_log
  FOR INSERT
  WITH CHECK (current_setting('role', true) = 'service_role');

-- =============================================================================
-- MARK: - Create Audit Trigger Function
-- =============================================================================

CREATE OR REPLACE FUNCTION log_profile_privilege_escalation_attempt()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_attempted_changes JSONB;
  v_blocked BOOLEAN := FALSE;
  v_reason TEXT := NULL;
  v_severity TEXT := 'medium';
  v_user_id UUID;
BEGIN
  -- Extract user ID from trigger context
  v_user_id := COALESCE(auth.uid(), NEW.id);

  -- Detect privilege escalation attempts
  v_attempted_changes := jsonb_build_object();

  -- Check for subscription tier modification attempt
  IF NEW.subscription_tier IS DISTINCT FROM OLD.subscription_tier AND
     (SELECT auth.role() != 'service_role') THEN
    v_attempted_changes := v_attempted_changes || jsonb_build_object(
      'subscription_tier', jsonb_build_object(
        'old', OLD.subscription_tier,
        'attempted', NEW.subscription_tier
      )
    );
    v_blocked := TRUE;
    v_reason := 'Unauthorized subscription_tier modification';
    v_severity := 'critical';
  END IF;

  -- Check for quota modification attempt
  IF (NEW.daily_ai_quota IS DISTINCT FROM OLD.daily_ai_quota OR
      NEW.quota_reset_at IS DISTINCT FROM OLD.quota_reset_at) AND
     (SELECT auth.role() != 'service_role') THEN
    v_attempted_changes := v_attempted_changes || jsonb_build_object(
      'quota', jsonb_build_object(
        'old_limit', OLD.daily_ai_quota,
        'attempted_limit', NEW.daily_ai_quota,
        'old_reset_at', OLD.quota_reset_at,
        'attempted_reset_at', NEW.quota_reset_at
      )
    );
    v_blocked := TRUE;
    v_reason := 'Unauthorized quota modification';
    v_severity := 'critical';
  END IF;

  -- Check for premium badge modification attempt
  IF NEW.premium_badge IS DISTINCT FROM OLD.premium_badge AND
     (SELECT auth.role() != 'service_role') THEN
    v_attempted_changes := v_attempted_changes || jsonb_build_object(
      'premium_badge', jsonb_build_object(
        'old', OLD.premium_badge,
        'attempted', NEW.premium_badge
      )
    );
    v_blocked := TRUE;
    v_reason := 'Unauthorized premium_badge modification';
    v_severity := 'high';
  END IF;

  -- Log the attempt if privileges were escalated
  IF v_blocked AND jsonb_array_length(jsonb_object_keys(v_attempted_changes)::jsonb) > 0 THEN
    INSERT INTO security_audit_log (
      event_type,
      severity,
      user_id,
      table_name,
      operation,
      attempted_changes,
      ip_address,
      user_agent,
      blocked,
      reason
    ) VALUES (
      'PRIVILEGE_ESCALATION_ATTEMPT',
      v_severity,
      v_user_id,
      'profiles',
      TG_OP,
      v_attempted_changes,
      NULL,  -- IP would need to come from request context
      NULL,  -- User agent would need to come from request context
      TRUE,
      v_reason
    );
  END IF;

  RETURN NEW;
END;
$$;

-- =============================================================================
-- MARK: - Attach Audit Trigger
-- =============================================================================

-- Drop existing trigger if any
DROP TRIGGER IF EXISTS tr_audit_profile_modifications ON public.profiles;

-- Create trigger on all profile modifications
CREATE TRIGGER tr_audit_profile_modifications
AFTER UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION log_profile_privilege_escalation_attempt();

-- =============================================================================
-- MARK: - Create Audit Views for Investigation
-- =============================================================================

-- View: Recent privilege escalation attempts (last 24 hours)
CREATE OR REPLACE VIEW v_recent_escalation_attempts AS
SELECT
  id,
  user_id,
  event_type,
  severity,
  attempted_changes,
  reason,
  created_at
FROM security_audit_log
WHERE event_type = 'PRIVILEGE_ESCALATION_ATTEMPT'
  AND created_at > NOW() - INTERVAL '24 hours'
ORDER BY created_at DESC;

-- View: Users with multiple escalation attempts
CREATE OR REPLACE VIEW v_repeat_escalation_offenders AS
SELECT
  user_id,
  COUNT(*) as attempt_count,
  MAX(created_at) as last_attempt,
  ARRAY_AGG(DISTINCT severity ORDER BY severity DESC) as severity_levels
FROM security_audit_log
WHERE event_type = 'PRIVILEGE_ESCALATION_ATTEMPT'
  AND created_at > NOW() - INTERVAL '7 days'
GROUP BY user_id
HAVING COUNT(*) > 1
ORDER BY attempt_count DESC;

-- =============================================================================
-- MARK: - Documentation
-- =============================================================================

COMMENT ON TABLE security_audit_log IS
  'Security audit trail for privilege escalation attempts and other suspicious activities';

COMMENT ON COLUMN security_audit_log.event_type IS
  'Type of security event: PRIVILEGE_ESCALATION_ATTEMPT, QUOTA_BYPASS_ATTEMPT, etc.';

COMMENT ON COLUMN security_audit_log.severity IS
  'Severity level: low, medium, high, critical';

COMMENT ON COLUMN security_audit_log.attempted_changes IS
  'JSON object showing what changes were attempted';

COMMENT ON COLUMN security_audit_log.blocked IS
  'Whether the operation was successfully blocked by security controls';

COMMENT ON VIEW v_recent_escalation_attempts IS
  'Shows all privilege escalation attempts from the last 24 hours for investigation';

COMMENT ON VIEW v_repeat_escalation_offenders IS
  'Identifies users with multiple escalation attempts (potential attackers)';
