-- Add last_transaction_id column for renewal detection
-- Fix #002: Renewals should extend expiry instead of being short-circuited

ALTER TABLE subscriptions
ADD COLUMN IF NOT EXISTS last_transaction_id TEXT;

-- Backfill existing subscriptions: use original_transaction_id as initial value
UPDATE subscriptions
SET last_transaction_id = original_transaction_id
WHERE last_transaction_id IS NULL;

-- Add uniqueness constraint on original_transaction_id
-- This prevents duplicate subscriptions for the same Apple transaction
CREATE UNIQUE INDEX IF NOT EXISTS idx_subscriptions_original_transaction_id
ON subscriptions(original_transaction_id)
WHERE original_transaction_id IS NOT NULL;

COMMENT ON COLUMN subscriptions.last_transaction_id IS 'Most recent transaction ID from Apple - changes on each renewal';
COMMENT ON COLUMN subscriptions.original_transaction_id IS 'First transaction ID from Apple - stable across renewals';
