-- Migration: Fix assign_daily_quest to support Quest Arcs
-- Issue: When a user starts a quest arc/journey, their daily quest should come from
-- the arc's scheduled steps, not random selection. The RPC was missing arc checking.

CREATE OR REPLACE FUNCTION public.assign_daily_quest(p_local_date text)
RETURNS TABLE(
  id uuid,
  user_id uuid,
  template_id uuid,
  local_date text,
  status text,
  assigned_at timestamp with time zone,
  completed_at timestamp with time zone,
  created_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_user_id UUID;
  v_existing_quest RECORD;
  v_template_id UUID;
  v_arc_user_id UUID;
  v_arc_step RECORD;
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

  -- NEW: Check for active quest arc and get the next step
  SELECT
    qas.quest_template_id,
    uqa.id as user_arc_id
  INTO v_arc_step
  FROM user_quest_arcs uqa
  JOIN quest_arc_steps qas ON qas.arc_id = uqa.arc_id
    AND qas.day_number = uqa.current_day + 1
  WHERE uqa.user_id = v_user_id
    AND uqa.status = 'active'
  LIMIT 1;

  IF v_arc_step IS NOT NULL AND v_arc_step.quest_template_id IS NOT NULL THEN
    -- Use the arc's quest template
    v_template_id := v_arc_step.quest_template_id;
    v_arc_user_id := v_arc_step.user_arc_id;
  ELSE
    -- Fallback: Select a random quest template (prefer ones not recently assigned)
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

    v_arc_user_id := NULL;
  END IF;

  -- If still no template, raise error
  IF v_template_id IS NULL THEN
    RAISE EXCEPTION 'No active quest templates available';
  END IF;

  -- Insert new quest and return it
  RETURN QUERY
  INSERT INTO quests (user_id, template_id, local_date, status, assigned_at, created_at, arc_user_id)
  VALUES (v_user_id, v_template_id, p_local_date, 'assigned', NOW(), NOW(), v_arc_user_id)
  RETURNING quests.id, quests.user_id, quests.template_id, quests.local_date,
            quests.status, quests.assigned_at, quests.completed_at, quests.created_at;
END;
$$;

-- Add comment documenting the fix
COMMENT ON FUNCTION public.assign_daily_quest(text) IS 
'Assigns daily quest for authenticated user. Now checks for active quest arcs first, 
falling back to random selection if no arc is active. Idempotent - returns existing 
quest if already assigned for the date.';
