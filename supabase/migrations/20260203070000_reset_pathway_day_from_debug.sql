-- Fix: Multiple check-in submissions during debugging caused current_day to advance too far.
-- Reset current_day to (actual completed check-ins + 1) for all pathways where it drifted.

UPDATE user_pathways up
SET
    current_day = COALESCE(completed_count.cnt, 0) + 1,
    current_phase_day = GREATEST(1, COALESCE(completed_count.cnt, 0) + 1 - (
        -- Subtract days from previous phases
        SELECT COALESCE(SUM(pp.duration_days), 0)
        FROM pathway_phases pp
        WHERE pp.pathway_id = up.pathway_id
        AND pp.phase_number < up.current_phase
    ))
FROM (
    SELECT user_pathway_id, COUNT(*) as cnt
    FROM pathway_progress
    WHERE check_in_completed = true
    GROUP BY user_pathway_id
) completed_count
WHERE up.id = completed_count.user_pathway_id
AND up.current_day > completed_count.cnt + 1
AND up.status = 'active';

-- Also clean up any pathway_progress rows for days that shouldn't exist yet
DELETE FROM pathway_progress pp
WHERE NOT pp.check_in_completed
AND pp.day_number > (
    SELECT current_day FROM user_pathways WHERE id = pp.user_pathway_id
);
