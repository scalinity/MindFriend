-- Migration: assign_daily_quest RPC and quest completion stats trigger
-- Issue #005: Daily Quest Assignment

-- MARK: - assign_daily_quest RPC
-- Idempotent function that assigns a random quest template for the day if not already assigned
-- Returns the quest (existing or newly created)

CREATE OR REPLACE FUNCTION assign_daily_quest(p_local_date TEXT)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  template_id UUID,
  local_date TEXT,
  status TEXT,
  assigned_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_existing_quest RECORD;
  v_template_id UUID;
BEGIN
  -- Get the authenticated user
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Check if quest already exists for this date (idempotent)
  SELECT q.* INTO v_existing_quest
  FROM quests q
  WHERE q.user_id = v_user_id AND q.local_date = p_local_date;

  IF FOUND THEN
    -- Return existing quest
    RETURN QUERY
    SELECT q.id, q.user_id, q.template_id, q.local_date, q.status,
           q.assigned_at, q.completed_at, q.created_at
    FROM quests q
    WHERE q.id = v_existing_quest.id;
    RETURN;
  END IF;

  -- Select a random quest template (prefer ones not recently assigned)
  SELECT qt.id INTO v_template_id
  FROM quest_templates qt
  WHERE qt.is_active = true
    AND qt.id NOT IN (
      SELECT q.template_id
      FROM quests q
      WHERE q.user_id = v_user_id
        AND q.local_date >= (p_local_date::DATE - INTERVAL '7 days')::TEXT
    )
  ORDER BY RANDOM()
  LIMIT 1;

  -- If all templates used recently, pick any active one
  IF v_template_id IS NULL THEN
    SELECT qt.id INTO v_template_id
    FROM quest_templates qt
    WHERE qt.is_active = true
    ORDER BY RANDOM()
    LIMIT 1;
  END IF;

  -- If still no template, raise error
  IF v_template_id IS NULL THEN
    RAISE EXCEPTION 'No active quest templates available';
  END IF;

  -- Insert new quest and return it
  RETURN QUERY
  INSERT INTO quests (user_id, template_id, local_date, status, assigned_at, created_at)
  VALUES (v_user_id, v_template_id, p_local_date, 'assigned', NOW(), NOW())
  RETURNING quests.id, quests.user_id, quests.template_id, quests.local_date,
            quests.status, quests.assigned_at, quests.completed_at, quests.created_at;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION assign_daily_quest(TEXT) TO authenticated;

-- MARK: - Quest Completion Stats Trigger
-- Updates user_stats when a quest is marked as completed

CREATE OR REPLACE FUNCTION update_stats_on_quest_completion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_last_quest_date TEXT;
  v_current_streak INT;
  v_longest_streak INT;
  v_yesterday TEXT;
BEGIN
  -- Only process when status changes to 'completed'
  IF NEW.status = 'completed' AND (OLD.status IS NULL OR OLD.status != 'completed') THEN
    -- Calculate yesterday's date
    v_yesterday := ((NEW.local_date::DATE) - INTERVAL '1 day')::DATE::TEXT;

    -- Get current stats
    SELECT last_quest_date, current_streak_days, longest_streak_days
    INTO v_last_quest_date, v_current_streak, v_longest_streak
    FROM user_stats
    WHERE user_id = NEW.user_id;

    -- Calculate new streak
    IF v_last_quest_date IS NULL OR v_last_quest_date = v_yesterday THEN
      -- Continue or start streak
      v_current_streak := COALESCE(v_current_streak, 0) + 1;
    ELSIF v_last_quest_date = NEW.local_date THEN
      -- Same day, no change (shouldn't happen but handle it)
      NULL;
    ELSE
      -- Streak broken, restart at 1
      v_current_streak := 1;
    END IF;

    -- Update longest streak if needed
    IF v_current_streak > COALESCE(v_longest_streak, 0) THEN
      v_longest_streak := v_current_streak;
    END IF;

    -- Update user_stats (upsert)
    INSERT INTO user_stats (user_id, current_streak_days, longest_streak_days, total_quests_completed, last_quest_date, updated_at)
    VALUES (NEW.user_id, v_current_streak, v_longest_streak, 1, NEW.local_date, NOW())
    ON CONFLICT (user_id) DO UPDATE SET
      current_streak_days = v_current_streak,
      longest_streak_days = GREATEST(user_stats.longest_streak_days, v_longest_streak),
      total_quests_completed = user_stats.total_quests_completed + 1,
      last_quest_date = NEW.local_date,
      updated_at = NOW();
  END IF;

  RETURN NEW;
END;
$$;

-- Drop trigger if exists and recreate
DROP TRIGGER IF EXISTS trg_quest_completed_stats ON quests;

CREATE TRIGGER trg_quest_completed_stats
  AFTER UPDATE ON quests
  FOR EACH ROW
  EXECUTE FUNCTION update_stats_on_quest_completion();

-- Also trigger on INSERT (for cases where quest is inserted as completed)
DROP TRIGGER IF EXISTS trg_quest_inserted_completed_stats ON quests;

CREATE TRIGGER trg_quest_inserted_completed_stats
  AFTER INSERT ON quests
  FOR EACH ROW
  WHEN (NEW.status = 'completed')
  EXECUTE FUNCTION update_stats_on_quest_completion();
