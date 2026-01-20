-- Allow organization plan_type on subscriptions

ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS valid_plan_type;
ALTER TABLE subscriptions ADD CONSTRAINT valid_plan_type
  CHECK (plan_type IN ('individual', 'couples', 'family', 'organization'));
