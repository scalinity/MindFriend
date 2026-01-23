-- Fix P0-001: Add 'earned' event type to streak_shield_events constraint
-- This allows the assign-quest function to properly log shield earning at 7-day milestones

-- Drop the old constraint
ALTER TABLE streak_shield_events
DROP CONSTRAINT IF EXISTS streak_shield_events_event_type_check;

-- Add the new constraint with 'earned' included
ALTER TABLE streak_shield_events
ADD CONSTRAINT streak_shield_events_event_type_check
CHECK (event_type = ANY (ARRAY['earned'::text, 'used'::text, 'expired'::text, 'reset'::text, 'purchased'::text]));

-- Add comment explaining the event types
COMMENT ON CONSTRAINT streak_shield_events_event_type_check ON streak_shield_events IS
'Valid event types: earned (7-day milestone), used (protect streak), expired (unused after time), reset (monthly reset), purchased (store purchase)';
