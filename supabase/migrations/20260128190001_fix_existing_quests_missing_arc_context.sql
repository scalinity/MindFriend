-- Migration: Fix existing quests that are missing arc context
-- Issue: Users who started quest arcs may have had their daily quest assigned
-- before the arc-checking fix. This updates those quests to use the correct
-- arc template and sets the arc_user_id.
-- 
-- Also fixes a pre-existing bug in update_challenge_progress_on_quest trigger
-- function that references NEW.completed instead of NEW.status = 'completed'.

-- ============================================================================
-- FIX 1: Repair broken trigger function (references non-existent 'completed' column)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.update_challenge_progress_on_quest()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- Fixed: quests table uses 'status' column, not 'completed' boolean
    IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
        UPDATE challenge_participants
        SET current_progress = CASE 
            WHEN c.challenge_type = 'quest' THEN 1
            WHEN c.challenge_type = 'streak' THEN (
                SELECT COUNT(DISTINCT DATE(completed_at))
                FROM quests
                WHERE user_id = NEW.user_id 
                AND status = 'completed'
                AND completed_at > NOW() - INTERVAL '7 days'
            )
            ELSE current_progress
        END
        FROM challenges c
        WHERE challenge_participants.challenge_id = c.id
        AND challenge_participants.user_id = NEW.user_id
        AND c.challenge_type IN ('quest', 'streak')
        AND c.ends_at > NOW();
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.update_challenge_progress_on_quest() IS 
'Updates challenge progress when a quest is completed. Fixed to use status column.';

-- ============================================================================
-- FIX 2: Update existing quests missing arc context
-- ============================================================================
DO $$
DECLARE
  v_record RECORD;
  v_today TEXT;
  v_arc_template_id UUID;
BEGIN
  v_today := TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD');
  
  -- Find all users with active arcs who have a quest for today without arc_user_id
  FOR v_record IN
    SELECT 
      q.id as quest_id,
      q.user_id,
      uqa.id as user_arc_id,
      qas.quest_template_id as arc_template_id
    FROM quests q
    JOIN user_quest_arcs uqa ON uqa.user_id = q.user_id AND uqa.status = 'active'
    JOIN quest_arc_steps qas ON qas.arc_id = uqa.arc_id AND qas.day_number = uqa.current_day + 1
    WHERE q.local_date = v_today
      AND q.arc_user_id IS NULL
      AND q.status = 'assigned'  -- Only fix quests that haven't been completed yet
  LOOP
    -- Update the quest to use the arc's template and set arc context
    UPDATE quests
    SET 
      template_id = v_record.arc_template_id,
      arc_user_id = v_record.user_arc_id
    WHERE id = v_record.quest_id;
    
    RAISE NOTICE 'Fixed quest % for user % to use arc template %', 
      v_record.quest_id, v_record.user_id, v_record.arc_template_id;
  END LOOP;
END;
$$;

-- ============================================================================
-- Add index to improve arc lookup performance in assign_daily_quest
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_user_quest_arcs_active_lookup 
ON user_quest_arcs(user_id, status) 
WHERE status = 'active';
