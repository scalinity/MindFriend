-- Fix: encrypted columns are bytea but RPC passes text (base64-encoded strings)
-- Change to text type to match the base64-encoded encrypted data from iOS

ALTER TABLE pathway_progress ALTER COLUMN encrypted_journal_entry TYPE TEXT USING encrypted_journal_entry::TEXT;
ALTER TABLE pathway_progress ALTER COLUMN encrypted_check_in_data TYPE TEXT USING encrypted_check_in_data::TEXT;
