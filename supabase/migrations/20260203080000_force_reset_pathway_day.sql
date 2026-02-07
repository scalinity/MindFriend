-- Force reset: Debug check-ins advanced the day incorrectly.
-- Reset all active pathways to day 2 (preserving 1 completed check-in for day 1).
-- Delete any pathway_progress records beyond day 1.

-- Reset pathway day counters
UPDATE user_pathways
SET current_day = 2, current_phase_day = 2, updated_at = now()
WHERE status = 'active' AND current_day > 2;

-- Remove progress records for days beyond 1 (debug artifacts)
DELETE FROM pathway_progress
WHERE day_number > 1;
