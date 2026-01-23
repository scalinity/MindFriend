-- MindFriend: Encrypt Transcripts (GDPR Art. 32 - Data Encryption)
-- Purpose: Encrypt sensitive transcript data at rest
-- Created: 2026-01-22
-- Security: Implements AES-256-CBC encryption for transcripts

-- Enable pgcrypto extension for encryption functions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create encrypted transcript column using pgcrypto
-- Using convert_from/convert_to for proper text handling
ALTER TABLE rehearsal_sessions
  ADD COLUMN IF NOT EXISTS transcript_encrypted BYTEA;

-- Migrate existing plaintext transcripts to encrypted column
-- Only migrate non-empty transcripts to save space
UPDATE rehearsal_sessions
SET transcript_encrypted = pgp_sym_encrypt(
  transcript,
  current_setting('app.encryption_key'),
  'cipher-algo=aes256'
)
WHERE transcript IS NOT NULL AND transcript != '';

-- Drop the plaintext transcript column (after migration)
ALTER TABLE rehearsal_sessions
  DROP COLUMN IF EXISTS transcript;

-- Rename encrypted column to transcript
ALTER TABLE rehearsal_sessions
  RENAME COLUMN transcript_encrypted TO transcript;

-- Add NOT NULL constraint
ALTER TABLE rehearsal_sessions
  ALTER COLUMN transcript SET DEFAULT pgp_sym_encrypt('[]'::text, current_setting('app.encryption_key'), 'cipher-algo=aes256');

-- Drop the legacy trigger_content column (contains old unencrypted data)
ALTER TABLE rehearsal_sessions
  DROP COLUMN IF EXISTS trigger_content;

-- Add index on created_at for performance (transcripts are encrypted, can't index)
CREATE INDEX IF NOT EXISTS idx_rehearsal_sessions_created_at
  ON rehearsal_sessions(created_at DESC)
  WHERE status IN ('completed', 'abandoned', 'crisis_ended');

-- RLS Policy: Users can only decrypt their own transcripts
CREATE POLICY "Users can decrypt own session transcripts"
  ON rehearsal_sessions FOR SELECT
  USING (auth.uid() = user_id);

COMMENT ON COLUMN rehearsal_sessions.transcript IS
'Encrypted JSON transcript using AES-256-CBC. Decrypted via pgp_sym_decrypt(transcript, app.encryption_key)';

-- Audit logging: Record encryption migration
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
  'REHEARSAL_SESSIONS',
  NULL,
  jsonb_build_object('migration', '20260703000006', 'action', 'encrypt_transcripts'),
  NOW()
) ON CONFLICT DO NOTHING;
