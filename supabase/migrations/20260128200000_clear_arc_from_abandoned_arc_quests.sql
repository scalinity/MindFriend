-- Migration: Clear arc_user_id from quests when the arc has been abandoned
-- This fixes quests that were assigned while an arc was active but the arc was later exited

-- Clear arc_user_id from all quests that reference abandoned arcs
UPDATE quests q
SET arc_user_id = NULL
WHERE q.arc_user_id IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM user_quest_arcs uqa
    WHERE uqa.id = q.arc_user_id
    AND uqa.status = 'abandoned'
  );

-- Also clear from quests where the arc was completed (user finished the whole journey)
-- but the quest itself is still 'assigned' (edge case for same-day completion/restart scenarios)
-- Note: Completed arcs should retain context for historical record, so we only clear 'abandoned'
