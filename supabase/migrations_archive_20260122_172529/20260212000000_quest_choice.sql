-- Migration: Quest Choice & Difficulty System
-- Allows users to choose between quest options, reroll, and builds preference learning.
-- See: specs/12-quest-choice.md

-- ============================================================================
-- Quest preference tracking
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_quest_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  quest_category TEXT NOT NULL, -- breathing, walk, journal, focus, gratitude, stretch
  completion_count INT DEFAULT 0,
  skip_count INT DEFAULT 0,
  total_rating_sum INT DEFAULT 0,
  rating_count INT DEFAULT 0,
  last_completed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id, quest_category)
);

CREATE INDEX IF NOT EXISTS idx_quest_prefs_user ON user_quest_preferences(user_id);

-- ============================================================================
-- Quick quest variants (shortened versions of full quests)
-- ============================================================================
CREATE TABLE IF NOT EXISTS quest_quick_variants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_template_id UUID NOT NULL REFERENCES quest_templates(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  steps JSONB NOT NULL, -- Reduced steps array
  estimated_minutes INT NOT NULL CHECK (estimated_minutes <= 5),
  xp_multiplier FLOAT DEFAULT 0.5,
  created_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(parent_template_id)
);

-- ============================================================================
-- Daily quest alternatives (generated per user per day)
-- ============================================================================
CREATE TABLE IF NOT EXISTS quest_alternatives (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  quest_date DATE NOT NULL,
  primary_quest_id UUID REFERENCES quest_templates(id),
  quick_variant_id UUID REFERENCES quest_quick_variants(id),
  alt_quest_id UUID REFERENCES quest_templates(id),
  rerolls_used INT DEFAULT 0,
  rerolls_max INT DEFAULT 1,
  selected_variant TEXT DEFAULT 'primary', -- primary, quick, alt, reroll
  created_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id, quest_date)
);

CREATE INDEX IF NOT EXISTS idx_quest_alts_user_date ON quest_alternatives(user_id, quest_date);

-- ============================================================================
-- Reroll history for analytics
-- ============================================================================
CREATE TABLE IF NOT EXISTS quest_reroll_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  quest_date DATE NOT NULL,
  from_quest_id UUID REFERENCES quest_templates(id),
  to_quest_id UUID REFERENCES quest_templates(id),
  reroll_number INT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reroll_user ON quest_reroll_history(user_id, quest_date);

-- ============================================================================
-- Row Level Security
-- ============================================================================
ALTER TABLE user_quest_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE quest_alternatives ENABLE ROW LEVEL SECURITY;
ALTER TABLE quest_quick_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE quest_reroll_history ENABLE ROW LEVEL SECURITY;

-- Users manage own preferences
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own preferences' AND tablename = 'user_quest_preferences'
  ) THEN
    CREATE POLICY "Users manage own preferences" ON user_quest_preferences
      FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;

-- Users see own alternatives
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Users see own alternatives' AND tablename = 'quest_alternatives'
  ) THEN
    CREATE POLICY "Users see own alternatives" ON quest_alternatives
      FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;

-- Anyone can read quick variants (public content)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Anyone can read quick variants' AND tablename = 'quest_quick_variants'
  ) THEN
    CREATE POLICY "Anyone can read quick variants" ON quest_quick_variants
      FOR SELECT USING (true);
  END IF;
END $$;

-- Users see own reroll history
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Users see own reroll history' AND tablename = 'quest_reroll_history'
  ) THEN
    CREATE POLICY "Users see own reroll history" ON quest_reroll_history
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

-- Users can insert own reroll history
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Users insert own reroll history' AND tablename = 'quest_reroll_history'
  ) THEN
    CREATE POLICY "Users insert own reroll history" ON quest_reroll_history
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- ============================================================================
-- Function: Get weighted quest for user (considers preferences)
-- ============================================================================
CREATE OR REPLACE FUNCTION get_weighted_quest_for_user(
  p_user_id UUID,
  p_exclude_category TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
  v_quest_id UUID;
BEGIN
  -- Get quest weighted by user preferences
  SELECT qt.id INTO v_quest_id
  FROM quest_templates qt
  LEFT JOIN user_quest_preferences uqp
    ON uqp.user_id = p_user_id AND uqp.quest_category = COALESCE(qt.category, qt.type)::text
  WHERE qt.is_active = TRUE
    AND (p_exclude_category IS NULL OR COALESCE(qt.category, qt.type)::text != p_exclude_category)
  ORDER BY
    -- Prefer categories with higher completion rates
    COALESCE(uqp.completion_count::float / NULLIF(uqp.completion_count + uqp.skip_count, 0), 0.5) DESC,
    -- Prefer categories with higher ratings
    COALESCE(uqp.total_rating_sum::float / NULLIF(uqp.rating_count, 0), 3) DESC,
    -- Add randomness
    RANDOM()
  LIMIT 1;

  RETURN v_quest_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Function: Generate quest alternatives for a user for a given date
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
BEGIN
  -- Check if already generated
  SELECT * INTO v_result FROM quest_alternatives
  WHERE user_id = p_user_id AND quest_date = p_date;

  IF FOUND THEN
    RETURN NEXT v_result;
    RETURN;
  END IF;

  -- Check premium status for reroll limit
  SELECT EXISTS (
    SELECT 1 FROM subscriptions
    WHERE user_id = p_user_id AND status = 'active'
  ) INTO v_is_premium;

  -- Get primary quest (weighted by preferences)
  v_primary := get_weighted_quest_for_user(p_user_id);

  IF v_primary IS NULL THEN
    -- No active quest templates, return empty
    RETURN;
  END IF;

  -- Get quick variant of primary (if exists)
  SELECT id INTO v_quick FROM quest_quick_variants
  WHERE parent_template_id = v_primary;

  -- Get the category of primary quest to exclude for alternative
  SELECT COALESCE(category, type)::text INTO v_primary_category FROM quest_templates WHERE id = v_primary;

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

-- ============================================================================
-- Function: Reroll quest to get a new primary
-- ============================================================================
CREATE OR REPLACE FUNCTION reroll_quest(p_user_id UUID, p_alternatives_id UUID)
RETURNS SETOF quest_alternatives AS $$
DECLARE
  v_current quest_alternatives;
  v_new_quest_id UUID;
  v_current_category TEXT;
  v_new_quick UUID;
  v_result quest_alternatives;
BEGIN
  -- Get current alternatives
  SELECT * INTO v_current FROM quest_alternatives
  WHERE id = p_alternatives_id AND user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Quest alternatives not found';
  END IF;

  -- Check if rerolls remaining
  IF v_current.rerolls_used >= v_current.rerolls_max AND v_current.rerolls_max != 999 THEN
    RAISE EXCEPTION 'No rerolls remaining';
  END IF;

  -- Get current quest category to exclude
  SELECT category::text INTO v_current_category FROM quest_templates WHERE id = v_current.primary_quest_id;

  -- Get new quest (different from current)
  SELECT id INTO v_new_quest_id
  FROM quest_templates
  WHERE is_active = TRUE
    AND category::text != COALESCE(v_current_category, '')
    AND id != v_current.primary_quest_id
  ORDER BY RANDOM()
  LIMIT 1;

  IF v_new_quest_id IS NULL THEN
    -- Fallback: just get any different quest
    SELECT id INTO v_new_quest_id
    FROM quest_templates
    WHERE is_active = TRUE AND id != v_current.primary_quest_id
    ORDER BY RANDOM()
    LIMIT 1;
  END IF;

  IF v_new_quest_id IS NULL THEN
    RAISE EXCEPTION 'No quest templates available';
  END IF;

  -- Get quick variant for new quest (if exists)
  SELECT id INTO v_new_quick FROM quest_quick_variants
  WHERE parent_template_id = v_new_quest_id;

  -- Log reroll history
  INSERT INTO quest_reroll_history (
    user_id, quest_date, from_quest_id, to_quest_id, reroll_number
  ) VALUES (
    p_user_id, v_current.quest_date, v_current.primary_quest_id, v_new_quest_id, v_current.rerolls_used + 1
  );

  -- Update alternatives
  UPDATE quest_alternatives
  SET
    primary_quest_id = v_new_quest_id,
    quick_variant_id = v_new_quick,
    rerolls_used = rerolls_used + 1,
    selected_variant = 'reroll'
  WHERE id = p_alternatives_id
  RETURNING * INTO v_result;

  RETURN NEXT v_result;
  RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Function: Update quest preference after completion/skip
-- ============================================================================
CREATE OR REPLACE FUNCTION update_quest_preference(
  p_user_id UUID,
  p_quest_category TEXT,
  p_completed BOOLEAN,
  p_rating INT DEFAULT NULL
)
RETURNS void AS $$
BEGIN
  INSERT INTO user_quest_preferences (
    user_id, quest_category, completion_count, skip_count, total_rating_sum, rating_count, last_completed_at, updated_at
  ) VALUES (
    p_user_id,
    p_quest_category,
    CASE WHEN p_completed THEN 1 ELSE 0 END,
    CASE WHEN NOT p_completed THEN 1 ELSE 0 END,
    COALESCE(p_rating, 0),
    CASE WHEN p_rating IS NOT NULL THEN 1 ELSE 0 END,
    CASE WHEN p_completed THEN NOW() ELSE NULL END,
    NOW()
  )
  ON CONFLICT (user_id, quest_category) DO UPDATE SET
    completion_count = user_quest_preferences.completion_count + (CASE WHEN p_completed THEN 1 ELSE 0 END),
    skip_count = user_quest_preferences.skip_count + (CASE WHEN NOT p_completed THEN 1 ELSE 0 END),
    total_rating_sum = user_quest_preferences.total_rating_sum + COALESCE(p_rating, 0),
    rating_count = user_quest_preferences.rating_count + (CASE WHEN p_rating IS NOT NULL THEN 1 ELSE 0 END),
    last_completed_at = CASE WHEN p_completed THEN NOW() ELSE user_quest_preferences.last_completed_at END,
    updated_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Seed quick variants for existing quest templates
-- These are shortened 2-3 min versions of standard quests
-- Note: Only runs if quest_templates has data (uses type/category column)
-- ============================================================================
DO $$
DECLARE
  v_template RECORD;
  v_has_data BOOLEAN;
BEGIN
  -- Check if quest_templates has any data
  SELECT EXISTS (SELECT 1 FROM quest_templates LIMIT 1) INTO v_has_data;

  IF NOT v_has_data THEN
    RAISE NOTICE 'No quest templates exist yet, skipping quick variant seeding';
    RETURN;
  END IF;

  FOR v_template IN
    SELECT id, COALESCE(category, type)::text as category, title, description
    FROM quest_templates
    WHERE COALESCE(is_active, TRUE) = TRUE
    LIMIT 10
  LOOP
    -- Only insert if no quick variant exists
    IF NOT EXISTS (SELECT 1 FROM quest_quick_variants WHERE parent_template_id = v_template.id) THEN
      INSERT INTO quest_quick_variants (parent_template_id, title, description, steps, estimated_minutes, xp_multiplier)
      VALUES (
        v_template.id,
        'Quick ' || v_template.title,
        'A shorter version: ' || v_template.description,
        CASE v_template.category
          WHEN 'breathing' THEN '[{"step": 1, "text": "Take 3 deep breaths"}, {"step": 2, "text": "Hold for 4 counts, exhale for 6 counts, repeat 3x"}]'::jsonb
          WHEN 'journal' THEN '[{"step": 1, "text": "Write one thing you are grateful for"}, {"step": 2, "text": "Note one intention for today"}]'::jsonb
          WHEN 'walk' THEN '[{"step": 1, "text": "Step outside"}, {"step": 2, "text": "Walk mindfully for 2 minutes"}]'::jsonb
          WHEN 'focus' THEN '[{"step": 1, "text": "Close your eyes"}, {"step": 2, "text": "Focus on your breath for 2 minutes"}]'::jsonb
          WHEN 'gratitude' THEN '[{"step": 1, "text": "Think of one thing you appreciate"}, {"step": 2, "text": "Say thank you silently"}]'::jsonb
          WHEN 'stretch' THEN '[{"step": 1, "text": "Stand up and stretch arms overhead"}, {"step": 2, "text": "Roll shoulders 5 times each direction"}]'::jsonb
          ELSE '[{"step": 1, "text": "Take a moment to breathe"}, {"step": 2, "text": "Complete a quick version of the exercise"}]'::jsonb
        END,
        3, -- 3 minutes
        0.5 -- 50% XP
      );
    END IF;
  END LOOP;
END $$;

-- ============================================================================
-- Grant execute permissions on functions
-- ============================================================================
GRANT EXECUTE ON FUNCTION get_weighted_quest_for_user(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION generate_quest_alternatives(UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION reroll_quest(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION update_quest_preference(UUID, TEXT, BOOLEAN, INT) TO authenticated;
