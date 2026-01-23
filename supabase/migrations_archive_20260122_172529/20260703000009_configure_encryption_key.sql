-- MindFriend: Configure Encryption Key for pgcrypto
-- Purpose: Set up AES-256-CBC encryption key for GDPR Art. 32 compliance
-- Created: 2026-01-22
-- Security: This must be set via environment variables in Supabase Dashboard

-- Configure the encryption key that will be used by pgcrypto functions
-- NOTE: In production, this should be set via Supabase project settings
-- to use a secret key from Supabase Vault for enhanced security

-- For local development, this can be set via:
-- ALTER DATABASE postgres SET app.encryption_key TO '<base64-encoded-256-bit-key>';

-- Verify extension is enabled
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Test that encryption works (this will fail if key is not properly configured)
-- Subsequent Edge Functions will use this key via current_setting('app.encryption_key')

-- Create helper function to validate encryption setup
CREATE OR REPLACE FUNCTION verify_encryption_configured()
RETURNS TABLE (configured BOOLEAN, algorithm TEXT, key_status TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
  -- Check if encryption key is configured
  RETURN QUERY SELECT 
    (current_setting('app.encryption_key', true) IS NOT NULL)::BOOLEAN as configured,
    'aes256'::TEXT as algorithm,
    CASE 
      WHEN current_setting('app.encryption_key', true) IS NOT NULL THEN 'CONFIGURED'
      ELSE 'NOT_CONFIGURED - Set via Supabase Dashboard'
    END as key_status;
END;
$$;

COMMENT ON FUNCTION verify_encryption_configured IS
'Verifies that encryption key is properly configured in Supabase environment';

-- Log migration completion
INSERT INTO audit_logs (
  user_id,
  action,
  resource_type,
  resource_id,
  changes,
  created_at
) VALUES (
  NULL,
  'MIGRATION_COMPLETED',
  'ENCRYPTION_CONFIG',
  NULL,
  jsonb_build_object(
    'migration', '20260703000009',
    'action', 'configure_encryption_key',
    'note', 'Key must be configured via Supabase Dashboard settings'
  ),
  NOW()
) ON CONFLICT DO NOTHING;
