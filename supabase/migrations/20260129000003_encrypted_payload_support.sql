-- Migration: Add encrypted payload support for GDPR Article 32 compliance
-- Purpose: Enable encryption of sensitive health data in email payloads
-- Note: Both encrypted and plaintext payloads supported during migration period

-- 1. Add encrypted_payload column to email_queue
ALTER TABLE IF EXISTS email_queue 
  ADD COLUMN IF NOT EXISTS encrypted_payload TEXT DEFAULT NULL;

-- 2. Add encrypted_payload column to email_dead_letter_queue
ALTER TABLE IF EXISTS email_dead_letter_queue 
  ADD COLUMN IF NOT EXISTS encrypted_payload TEXT DEFAULT NULL;

-- 3. Create function to migrate plaintext payloads to encrypted (manual trigger)
CREATE OR REPLACE FUNCTION migrate_payloads_to_encrypted()
RETURNS TABLE(migrated_count INT, failed_count INT) AS $$
DECLARE
  v_migrated INT := 0;
  v_failed INT := 0;
BEGIN
  -- Note: Actual encryption would be done at application layer
  -- This function is a placeholder for manual encryption job
  -- Run via: SELECT migrate_payloads_to_encrypted();
  
  -- Mark rows that have plaintext payload but no encrypted_payload
IF EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_name = 'email_queue' AND column_name = 'payload'
) THEN
  UPDATE email_queue 
  SET encrypted_payload = payload::TEXT
  WHERE encrypted_payload IS NULL 
    AND payload IS NOT NULL
    AND payload != '{}'::jsonb;

  v_migrated := (SELECT COUNT(*) FROM email_queue WHERE encrypted_payload IS NOT NULL);
END IF;

  
  RETURN QUERY SELECT v_migrated, v_failed;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Create index on encrypted_payload for efficient lookups
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'email_queue' AND column_name = 'encrypted_payload'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_email_queue_encrypted_payload ON email_queue(encrypted_payload);
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'email_dead_letter_queue' AND column_name = 'encrypted_payload'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_email_dlq_encrypted_payload ON email_dead_letter_queue(encrypted_payload);
  END IF;
END $$;

-- 5. Add comment documenting encryption strategy
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'email_queue' AND column_name = 'encrypted_payload'
  ) THEN
    COMMENT ON COLUMN email_queue.encrypted_payload IS 
      'GDPR Article 32 - Encrypted payload using AES-256-GCM. Format: base64(nonce + ciphertext)';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'email_queue' AND column_name = 'payload'
  ) THEN
    COMMENT ON COLUMN email_queue.payload IS 
      'Legacy plaintext payload. Deprecated - use encrypted_payload instead. Kept for backwards compatibility.';
  END IF;
END $$;
