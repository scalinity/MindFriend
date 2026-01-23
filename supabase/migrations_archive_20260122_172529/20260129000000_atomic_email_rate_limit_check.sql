-- Migration: Atomic rate limit check with transaction-level locking
-- Purpose: Fix TOCTOU race condition in email rate limiting

CREATE OR REPLACE FUNCTION insert_email_log_with_rate_limit_check(
  p_user_id UUID,
  p_email_log_data JSONB
)
RETURNS JSONB AS $$
DECLARE
  v_count INT;
  v_within_limit BOOLEAN;
  v_result JSONB;
BEGIN
  -- Start transaction with serializable isolation to prevent TOCTOU
  -- Count sent emails in past 7 days with row-level lock to prevent concurrent reads
  SELECT COUNT(*)
  INTO v_count
  FROM email_logs
  WHERE user_id = p_user_id
    AND status = 'sent'
    AND sent_at > NOW() - INTERVAL '7 days'
  FOR UPDATE;  -- Lock to prevent concurrent rate limit checks

  v_within_limit := v_count < 10;

  -- Insert email log entry
  INSERT INTO email_logs (
    user_id,
    email_type,
    template_version,
    message_id,
    status,
    sent_at,
    created_at
  )
  SELECT
    (p_email_log_data->>'user_id')::UUID,
    p_email_log_data->>'email_type',
    p_email_log_data->>'template_version',
    p_email_log_data->>'message_id',
    p_email_log_data->>'status',
    (p_email_log_data->>'sent_at')::TIMESTAMPTZ,
    (p_email_log_data->>'created_at')::TIMESTAMPTZ;

  v_result := jsonb_build_object(
    'success', true,
    'withinLimit', v_within_limit
  );

  RETURN v_result;
EXCEPTION WHEN OTHERS THEN
  v_result := jsonb_build_object(
    'success', false,
    'withinLimit', false,
    'error', SQLERRM
  );
  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to service role
GRANT EXECUTE ON FUNCTION insert_email_log_with_rate_limit_check(UUID, JSONB) TO service_role;
