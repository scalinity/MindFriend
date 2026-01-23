-- Allow organization plan_type on subscriptions

-- Add plan_type column if it doesn't exist (may be created by later migration)
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS plan_type TEXT DEFAULT 'individual';

-- Update constraint to include organization plan type
ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS valid_plan_type;
ALTER TABLE subscriptions ADD CONSTRAINT valid_plan_type
  CHECK (plan_type IN ('individual', 'couples', 'family', 'organization'));
