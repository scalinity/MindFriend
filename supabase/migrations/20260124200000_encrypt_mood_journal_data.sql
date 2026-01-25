-- Migration: Support client-side encrypted mood notes and journal entries
-- Purpose: Add schema support for iOS client-side encryption (base64-encoded)
-- Date: 2026-01-24
-- Author: Claude Code (security hardening)
--
-- Architecture: iOS app encrypts data using SecureStorage before sending to database
-- Database stores encrypted base64 strings in TEXT columns

-- ============================================================================
-- STEP 1: Add encrypted columns to existing tables
-- ============================================================================

-- Moods table: Add encrypted note column (TEXT for base64-encoded data)
ALTER TABLE moods
ADD COLUMN IF NOT EXISTS encrypted_note TEXT,
ADD COLUMN IF NOT EXISTS note_encryption_key_id TEXT,
ADD COLUMN IF NOT EXISTS note_encrypted_at TIMESTAMPTZ DEFAULT now();

-- Journal entries table: Add encrypted content column
ALTER TABLE journal_entries
ADD COLUMN IF NOT EXISTS encrypted_content TEXT,
ADD COLUMN IF NOT EXISTS content_encryption_key_id TEXT,
ADD COLUMN IF NOT EXISTS content_encrypted_at TIMESTAMPTZ DEFAULT now();

-- Pathway progress table: Add encrypted columns
ALTER TABLE pathway_progress
ADD COLUMN IF NOT EXISTS encrypted_journal_entry TEXT,
ADD COLUMN IF NOT EXISTS journal_encryption_key_id TEXT,
ADD COLUMN IF NOT EXISTS encrypted_check_in_data TEXT,
ADD COLUMN IF NOT EXISTS check_in_encryption_key_id TEXT,
ADD COLUMN IF NOT EXISTS data_encrypted_at TIMESTAMPTZ DEFAULT now();

-- ============================================================================
-- STEP 2: Create indexes for encrypted columns (for query performance)
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_moods_encrypted_note_key_id ON moods(note_encryption_key_id);
CREATE INDEX IF NOT EXISTS idx_journal_encrypted_content_key_id ON journal_entries(content_encryption_key_id);
CREATE INDEX IF NOT EXISTS idx_pathway_encrypted_journal_key_id ON pathway_progress(journal_encryption_key_id);

-- ============================================================================
-- STEP 3: Add comments for documentation
-- ============================================================================

COMMENT ON COLUMN moods.encrypted_note IS 'Base64-encoded encrypted note (encrypted client-side via iOS SecureStorage)';
COMMENT ON COLUMN moods.note_encryption_key_id IS 'Encryption key identifier (e.g., ios-securestorage-v1)';

COMMENT ON COLUMN journal_entries.encrypted_content IS 'Base64-encoded encrypted journal content (encrypted client-side)';
COMMENT ON COLUMN journal_entries.content_encryption_key_id IS 'Encryption key identifier';

COMMENT ON COLUMN pathway_progress.encrypted_journal_entry IS 'Base64-encoded encrypted journal entry (encrypted client-side)';
COMMENT ON COLUMN pathway_progress.encrypted_check_in_data IS 'Base64-encoded encrypted check-in notes (encrypted client-side)';
COMMENT ON COLUMN pathway_progress.journal_encryption_key_id IS 'Encryption key identifier for journal';
COMMENT ON COLUMN pathway_progress.check_in_encryption_key_id IS 'Encryption key identifier for check-in';

-- ============================================================================
-- NOTES
-- ============================================================================

-- Client-side encryption architecture:
-- 1. iOS app encrypts sensitive data using SecureStorage (AES-256-GCM)
-- 2. Encrypted data is base64-encoded for transport
-- 3. Database stores base64 strings in TEXT columns
-- 4. iOS app decrypts data when reading from database
-- 5. Key management handled entirely on iOS device (Keychain)
--
-- This approach ensures:
-- - Database never sees plaintext sensitive data
-- - No server-side key management needed
-- - Simple schema (no complex encryption functions)
-- - Fast queries (no decryption overhead on database)
