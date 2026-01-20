/**
 * Migration: Hash Invitation Tokens
 * Purpose: Store SHA-256 hash of invitation tokens instead of plaintext
 * Security: Prevents token theft if database is compromised
 * Date: 2026-01-21
 */

-- Add new column for hashed token
ALTER TABLE therapy_connections
ADD COLUMN IF NOT EXISTS invitation_token_hash TEXT;

-- Create index on hash for faster lookups
CREATE INDEX IF NOT EXISTS idx_therapy_connections_token_hash
ON therapy_connections(invitation_token_hash)
WHERE invitation_token_hash IS NOT NULL;

-- Migrate existing plaintext tokens to hashes (if any exist)
-- NOTE: This is a one-way migration - existing tokens will become invalid
-- This is acceptable since tokens are typically short-lived (7 days)
UPDATE therapy_connections
SET invitation_token_hash = encode(digest(invitation_token, 'sha256'), 'hex'),
    invitation_token = NULL
WHERE invitation_token IS NOT NULL;

-- Add comment for documentation
COMMENT ON COLUMN therapy_connections.invitation_token_hash IS
'SHA-256 hash of JWT invitation token. Prevents token theft via database compromise.';

-- Update RLS policies to allow token hash queries
-- (Existing policies already cover this, just documenting)
