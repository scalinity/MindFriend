-- Migration: Wellbeing Debt Economy Rebalance
-- Date: 2026-01-30
-- Purpose: Support one-time social isolation tracking and document threshold changes

-- Add last_isolation_date to prevent daily stacking of isolation penalties
-- Isolation is now a ONE-TIME event when it starts, not a daily penalty
ALTER TABLE wellbeing_debt_profiles
  ADD COLUMN IF NOT EXISTS last_isolation_date DATE;

-- Add index for efficient isolation lookups
CREATE INDEX IF NOT EXISTS idx_wellbeing_profiles_isolation
  ON wellbeing_debt_profiles(user_id, last_isolation_date)
  WHERE last_isolation_date IS NOT NULL;

-- Update comment to document new default threshold
COMMENT ON COLUMN wellbeing_debt_profiles.learned_threshold IS
  'Personalized threshold (10th percentile of crash debts). Default is -75 until 3+ crashes. Rebalanced 2026-01-30.';

-- Clean up any existing daily-stacked social isolation transactions
-- Keep only the most recent one per 3-day window to align with new behavior
-- This is a one-time cleanup for existing data
WITH ranked_isolation AS (
  SELECT
    id,
    user_id,
    date,
    ROW_NUMBER() OVER (
      PARTITION BY user_id,
      (date::date - (date::date - '2020-01-01'::date) % 3) -- Group by 3-day windows
      ORDER BY date DESC
    ) as rn
  FROM wellbeing_transactions
  WHERE category = 'social_isolation'
)
DELETE FROM wellbeing_transactions
WHERE id IN (
  SELECT id FROM ranked_isolation WHERE rn > 1
);

-- Log the migration
DO $$
BEGIN
  RAISE NOTICE 'Wellbeing debt economy rebalanced: default threshold -50 -> -75, isolation now one-time';
END $$;
