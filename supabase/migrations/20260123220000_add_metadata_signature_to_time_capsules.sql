-- Add metadata signature column to time_capsules table
-- SECURITY: Enables HMAC signature verification to prevent metadata tampering

ALTER TABLE time_capsules
ADD COLUMN IF NOT EXISTS metadata_signature TEXT;

COMMENT ON COLUMN time_capsules.metadata_signature IS
'HMAC-SHA256 signature of metadata (title, theme, created_at, deliver_at) using capsule encryption key. Prevents database administrator from tampering with metadata without detection.';

-- Index not needed - signature only verified on retrieval, not queried
