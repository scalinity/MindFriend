-- Add missing encrypted columns to pathway_progress table
-- These columns are referenced by submit_pathway_checkin RPC but were never created

ALTER TABLE pathway_progress ADD COLUMN IF NOT EXISTS encrypted_journal_entry TEXT;
ALTER TABLE pathway_progress ADD COLUMN IF NOT EXISTS journal_encryption_key_id TEXT;
ALTER TABLE pathway_progress ADD COLUMN IF NOT EXISTS encrypted_check_in_data TEXT;
ALTER TABLE pathway_progress ADD COLUMN IF NOT EXISTS check_in_encryption_key_id TEXT;
ALTER TABLE pathway_progress ADD COLUMN IF NOT EXISTS data_encrypted_at TIMESTAMPTZ;
