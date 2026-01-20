-- Migration: Also update existing quest_alternatives when there's a mismatch
-- This ensures that if a user already has alternatives generated but their
-- assigned quest differs, we update the primary to match.

-- ============================================================================
-- Updated Function: Generate quest alternatives - also fix existing mismatches
-- ============================================================================
CREATE OR REPLACE FUNCTION generate_quest_alternatives(p_user_id UUID, p_date DATE)
RETURNS SETOF quest_alternatives AS $$
DECLARE
  v_primary UUID;
  v_quick UUID;
  v_alt UUID;
  v_primary_category TEXT;
  v_is_premium BOOLEAN;
  v_result quest_alternatives;
  v_existing_quest_template UUID;
BEGIN
  -- First check if a quest was already assigned for today via assign_daily_quest
  SELECT template_id INTO v_existing_quest_template
  FROM quests
  WHERE user_id = p_user_id AND local_date = p_date::TEXT
  LIMIT 1;

  -- Check if alternatives already generated
  SELECT * INTO v_result FROM quest_alternatives
  WHERE user_id = p_user_id AND quest_date = p_date;

  IF FOUND THEN
    -- **FIX: Check if there's a mismatch between assigned quest and alternatives primary**
    IF v_existing_quest_template IS NOT NULL AND v_result.primary_quest_id != v_existing_quest_template THEN
      -- Update the primary to match the assigned quest
      -- Also update the quick variant if one exists for the new primary
      SELECT id INTO v_quick FROM quest_quick_variants
      WHERE parent_template_id = v_existing_quest_template;

      UPDATE quest_alternatives
      SET
        primary_quest_id = v_existing_quest_template,
        quick_variant_id = v_quick
      WHERE id = v_result.id
      RETURNING * INTO v_result;
    END IF;

    RETURN NEXT v_result;
    RETURN;
  END IF;

  -- Check premium status for reroll limit
  SELECT EXISTS (
    SELECT 1 FROM subscriptions
    WHERE user_id = p_user_id AND status = 'active'
  ) INTO v_is_premium;

  -- Use the already-assigned quest as primary if it exists
  IF v_existing_quest_template IS NOT NULL THEN
    v_primary := v_existing_quest_template;
  ELSE
    -- Get primary quest (weighted by preferences) - original behavior for fresh state
    v_primary := get_weighted_quest_for_user(p_user_id);
  END IF;

  IF v_primary IS NULL THEN
    -- No active quest templates, return empty
    RETURN;
  END IF;

  -- Get quick variant of primary (if exists)
  SELECT id INTO v_quick FROM quest_quick_variants
  WHERE parent_template_id = v_primary;

  -- Get the category of primary quest to exclude for alternative
  SELECT category::text INTO v_primary_category FROM quest_templates WHERE id = v_primary;

  -- Get alternative quest (different category)
  v_alt := get_weighted_quest_for_user(p_user_id, v_primary_category);

  -- If no different category available, just get another quest
  IF v_alt IS NULL THEN
    SELECT id INTO v_alt FROM quest_templates
    WHERE is_active = TRUE AND id != v_primary
    ORDER BY RANDOM()
    LIMIT 1;
  END IF;

  -- Insert and return
  INSERT INTO quest_alternatives (
    user_id, quest_date, primary_quest_id, quick_variant_id, alt_quest_id,
    rerolls_max
  ) VALUES (
    p_user_id, p_date, v_primary, v_quick, v_alt,
    CASE WHEN v_is_premium THEN 999 ELSE 1 END
  )
  RETURNING * INTO v_result;

  RETURN NEXT v_result;
  RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant permissions (idempotent)
GRANT EXECUTE ON FUNCTION generate_quest_alternatives(UUID, DATE) TO authenticated;
