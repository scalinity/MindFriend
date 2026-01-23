-- Migration: 20260215_celebration_sharing.sql
-- Description: Add celebration moments and social sharing system

-- =============================================================================
-- MARK: - Celebration Events Table
-- =============================================================================

CREATE TABLE IF NOT EXISTS celebration_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  celebration_type TEXT NOT NULL CHECK (celebration_type IN (
    'streak_milestone', 'level_up', 'badge_unlock', 'quest_milestone', 'exercise_milestone'
  )),
  value INT NOT NULL, -- streak days, level number, quest count, etc.
  badge_id UUID REFERENCES badges(id),
  shown_at TIMESTAMPTZ DEFAULT NOW(),
  shared_to_circle BOOLEAN DEFAULT FALSE,
  shared_externally BOOLEAN DEFAULT FALSE,
  circle_post_id UUID REFERENCES circle_posts(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_celebrations_user ON celebration_events(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_celebrations_type ON celebration_events(celebration_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_celebrations_not_shown ON celebration_events(user_id) WHERE shown_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_celebrations_circle_post ON celebration_events(circle_post_id) WHERE circle_post_id IS NOT NULL;

-- =============================================================================
-- MARK: - Share Card Templates
-- =============================================================================

CREATE TABLE IF NOT EXISTS share_card_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_type TEXT NOT NULL UNIQUE,
  background_color TEXT NOT NULL,
  accent_color TEXT NOT NULL,
  icon_name TEXT NOT NULL,
  message_template TEXT NOT NULL, -- "I just hit a {value}-day streak!"
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Pre-populate templates
INSERT INTO share_card_templates (template_type, background_color, accent_color, icon_name, message_template) VALUES
  ('streak_7', '#FF6B35', '#FFFFFF', 'flame.fill', 'One week strong! 🔥 {value} days of wellness.'),
  ('streak_14', '#FF6B35', '#FFFFFF', 'flame.fill', 'Two weeks! 🔥 {value} days and counting.'),
  ('streak_30', '#FF6B35', '#FFFFFF', 'flame.fill', 'One month! 🎉 {value} days and counting.'),
  ('streak_60', '#FF8C00', '#FFFFFF', 'flame.fill', 'Two months of dedication! 🔥 {value} days strong.'),
  ('streak_100', '#FFD700', '#000000', 'flame.fill', '💯 days of dedication. Unstoppable!'),
  ('streak_365', '#FFD700', '#000000', 'crown.fill', 'A full year! 🏆 {value} days of wellness mastery.'),
  ('level_up', '#6B5B95', '#FFFFFF', 'star.fill', 'Level {value} unlocked! ⭐'),
  ('badge_unlock', '#88B04B', '#FFFFFF', 'trophy.fill', 'New badge unlocked! 🏆'),
  ('quest_10', '#0072B2', '#FFFFFF', 'checkmark.seal.fill', '{value} quests completed! 💪 Just getting started.'),
  ('quest_50', '#0072B2', '#FFFFFF', 'checkmark.seal.fill', '{value} quests completed! 💪 Building momentum.'),
  ('quest_100', '#0072B2', '#FFFFFF', 'checkmark.seal.fill', '{value} quests completed! 🎉 Century club!'),
  ('quest_500', '#0072B2', '#FFFFFF', 'checkmark.seal.fill', '{value} quests completed! 🏆 Wellness warrior!'),
  ('exercise_10', '#4CAF50', '#FFFFFF', 'figure.mind.and.body', '{value} exercises completed! 🧘'),
  ('exercise_50', '#4CAF50', '#FFFFFF', 'figure.mind.and.body', '{value} exercises completed! 💪 Dedicated practitioner.'),
  ('exercise_100', '#4CAF50', '#FFFFFF', 'figure.mind.and.body', '{value} exercises completed! 🏆 Wellness champion!')
ON CONFLICT (template_type) DO UPDATE SET
  background_color = EXCLUDED.background_color,
  accent_color = EXCLUDED.accent_color,
  icon_name = EXCLUDED.icon_name,
  message_template = EXCLUDED.message_template;

-- =============================================================================
-- MARK: - Celebration Reactions
-- =============================================================================

CREATE TABLE IF NOT EXISTS celebration_reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  celebration_event_id UUID NOT NULL REFERENCES celebration_events(id) ON DELETE CASCADE,
  reactor_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  emoji TEXT NOT NULL CHECK (emoji IN ('🎉', '👏', '🔥', '💪', '❤️', '⭐')),
  created_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(celebration_event_id, reactor_user_id)
);

CREATE INDEX IF NOT EXISTS idx_celebration_reactions ON celebration_reactions(celebration_event_id);
CREATE INDEX IF NOT EXISTS idx_celebration_reactions_user ON celebration_reactions(reactor_user_id);

-- =============================================================================
-- MARK: - Row Level Security
-- =============================================================================

ALTER TABLE celebration_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE share_card_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE celebration_reactions ENABLE ROW LEVEL SECURITY;

-- Celebration events policies
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'celebration_events' AND policyname = 'Users can view own celebrations') THEN
    CREATE POLICY "Users can view own celebrations" ON celebration_events
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'celebration_events' AND policyname = 'Users can insert own celebrations') THEN
    CREATE POLICY "Users can insert own celebrations" ON celebration_events
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'celebration_events' AND policyname = 'Users can update own celebrations') THEN
    CREATE POLICY "Users can update own celebrations" ON celebration_events
      FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END $$;

-- Circle members can view celebrations shared to their circles
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'celebration_events' AND policyname = 'Circle members can view shared celebrations') THEN
    CREATE POLICY "Circle members can view shared celebrations" ON celebration_events
      FOR SELECT USING (
        shared_to_circle = TRUE AND
        EXISTS (
          SELECT 1 FROM circle_posts cp
          JOIN circle_members cm ON cm.circle_id = cp.circle_id
          WHERE cp.id = celebration_events.circle_post_id
            AND cm.user_id = auth.uid()
        )
      );
  END IF;
END $$;

-- Share card templates policies
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'share_card_templates' AND policyname = 'Anyone can view active templates') THEN
    CREATE POLICY "Anyone can view active templates" ON share_card_templates
      FOR SELECT TO authenticated USING (is_active = TRUE);
  END IF;
END $$;

-- Celebration reactions policies
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'celebration_reactions' AND policyname = 'Users can view celebration reactions') THEN
    CREATE POLICY "Users can view celebration reactions" ON celebration_reactions
      FOR SELECT USING (
        EXISTS (
          SELECT 1 FROM celebration_events ce
          WHERE ce.id = celebration_reactions.celebration_event_id
            AND (
              ce.user_id = auth.uid()
              OR (
                ce.shared_to_circle = TRUE
                AND EXISTS (
                  SELECT 1 FROM circle_posts cp
                  JOIN circle_members cm ON cm.circle_id = cp.circle_id
                  WHERE cp.id = ce.circle_post_id
                    AND cm.user_id = auth.uid()
                )
              )
            )
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'celebration_reactions' AND policyname = 'Circle members can react to celebrations') THEN
    CREATE POLICY "Circle members can react to celebrations" ON celebration_reactions
      FOR INSERT WITH CHECK (
        auth.uid() = reactor_user_id AND
        EXISTS (
          SELECT 1 FROM celebration_events ce
          JOIN circle_posts cp ON cp.id = ce.circle_post_id
          JOIN circle_members cm ON cm.circle_id = cp.circle_id
          WHERE ce.id = celebration_reactions.celebration_event_id
            AND cm.user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'celebration_reactions' AND policyname = 'Users can delete own reactions') THEN
    CREATE POLICY "Users can delete own reactions" ON celebration_reactions
      FOR DELETE USING (auth.uid() = reactor_user_id);
  END IF;
END $$;

-- =============================================================================
-- MARK: - Milestone Detection Function
-- =============================================================================

CREATE OR REPLACE FUNCTION check_milestone_triggers(
  p_user_id UUID,
  p_streak INT DEFAULT NULL,
  p_quest_count INT DEFAULT NULL,
  p_exercise_count INT DEFAULT NULL,
  p_new_level INT DEFAULT NULL,
  p_badge_id UUID DEFAULT NULL
) RETURNS TABLE(
  celebration_id UUID,
  celebration_type TEXT,
  value INT,
  badge_id UUID
) AS $$
DECLARE
  v_celebration_id UUID;
  v_streak_milestones INT[] := ARRAY[7, 14, 30, 60, 100, 365];
  v_quest_milestones INT[] := ARRAY[10, 50, 100, 500];
  v_exercise_milestones INT[] := ARRAY[10, 50, 100];
BEGIN
  -- Check streak milestones
  IF p_streak IS NOT NULL AND p_streak = ANY(v_streak_milestones) THEN
    -- Only create if not already created for this milestone
    IF NOT EXISTS (
      SELECT 1 FROM celebration_events ce
      WHERE ce.user_id = p_user_id
        AND ce.celebration_type = 'streak_milestone'
        AND ce.value = p_streak
        AND ce.created_at > NOW() - INTERVAL '24 hours'
    ) THEN
      INSERT INTO celebration_events (user_id, celebration_type, value, shown_at)
      VALUES (p_user_id, 'streak_milestone', p_streak, NULL)
      RETURNING id INTO v_celebration_id;

      RETURN QUERY SELECT v_celebration_id, 'streak_milestone'::TEXT, p_streak, NULL::UUID;
    END IF;
  END IF;

  -- Check quest milestones
  IF p_quest_count IS NOT NULL AND p_quest_count = ANY(v_quest_milestones) THEN
    IF NOT EXISTS (
      SELECT 1 FROM celebration_events ce
      WHERE ce.user_id = p_user_id
        AND ce.celebration_type = 'quest_milestone'
        AND ce.value = p_quest_count
    ) THEN
      INSERT INTO celebration_events (user_id, celebration_type, value, shown_at)
      VALUES (p_user_id, 'quest_milestone', p_quest_count, NULL)
      RETURNING id INTO v_celebration_id;

      RETURN QUERY SELECT v_celebration_id, 'quest_milestone'::TEXT, p_quest_count, NULL::UUID;
    END IF;
  END IF;

  -- Check exercise milestones
  IF p_exercise_count IS NOT NULL AND p_exercise_count = ANY(v_exercise_milestones) THEN
    IF NOT EXISTS (
      SELECT 1 FROM celebration_events ce
      WHERE ce.user_id = p_user_id
        AND ce.celebration_type = 'exercise_milestone'
        AND ce.value = p_exercise_count
    ) THEN
      INSERT INTO celebration_events (user_id, celebration_type, value, shown_at)
      VALUES (p_user_id, 'exercise_milestone', p_exercise_count, NULL)
      RETURNING id INTO v_celebration_id;

      RETURN QUERY SELECT v_celebration_id, 'exercise_milestone'::TEXT, p_exercise_count, NULL::UUID;
    END IF;
  END IF;

  -- Check level up (always triggers a celebration)
  IF p_new_level IS NOT NULL THEN
    INSERT INTO celebration_events (user_id, celebration_type, value, shown_at)
    VALUES (p_user_id, 'level_up', p_new_level, NULL)
    RETURNING id INTO v_celebration_id;

    RETURN QUERY SELECT v_celebration_id, 'level_up'::TEXT, p_new_level, NULL::UUID;
  END IF;

  -- Check badge unlock (always triggers a celebration)
  IF p_badge_id IS NOT NULL THEN
    INSERT INTO celebration_events (user_id, celebration_type, value, badge_id, shown_at)
    VALUES (p_user_id, 'badge_unlock', 1, p_badge_id, NULL)
    RETURNING id INTO v_celebration_id;

    RETURN QUERY SELECT v_celebration_id, 'badge_unlock'::TEXT, 1, p_badge_id;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- MARK: - Get Pending Celebrations Function
-- =============================================================================

CREATE OR REPLACE FUNCTION get_pending_celebrations(p_user_id UUID)
RETURNS TABLE(
  id UUID,
  celebration_type TEXT,
  value INT,
  badge_id UUID,
  badge_title TEXT,
  badge_description TEXT,
  badge_icon_name TEXT,
  created_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    ce.id,
    ce.celebration_type,
    ce.value,
    ce.badge_id,
    b.title AS badge_title,
    b.description AS badge_description,
    b.icon_name AS badge_icon_name,
    ce.created_at
  FROM celebration_events ce
  LEFT JOIN badges b ON b.id = ce.badge_id
  WHERE ce.user_id = p_user_id
    AND ce.shown_at IS NULL
  ORDER BY ce.created_at ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- MARK: - Mark Celebration Shown Function
-- =============================================================================

CREATE OR REPLACE FUNCTION mark_celebration_shown(p_celebration_id UUID)
RETURNS VOID AS $$
BEGIN
  UPDATE celebration_events
  SET shown_at = NOW()
  WHERE id = p_celebration_id
    AND user_id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- MARK: - Share Celebration to Circles Function
-- =============================================================================

CREATE OR REPLACE FUNCTION share_celebration_to_circles(p_celebration_id UUID)
RETURNS UUID AS $$
DECLARE
  v_user_id UUID;
  v_celebration RECORD;
  v_circle_id UUID;
  v_post_id UUID;
  v_post_content TEXT;
  v_user_name TEXT;
BEGIN
  -- Get the user ID from the celebration
  SELECT user_id, celebration_type, value, badge_id INTO v_celebration
  FROM celebration_events
  WHERE id = p_celebration_id AND user_id = auth.uid();

  IF v_celebration.user_id IS NULL THEN
    RAISE EXCEPTION 'Celebration not found or not owned by user';
  END IF;

  v_user_id := v_celebration.user_id;

  -- Get user display name
  SELECT display_name INTO v_user_name
  FROM profiles
  WHERE id = v_user_id;

  -- Generate post content based on celebration type
  CASE v_celebration.celebration_type
    WHEN 'streak_milestone' THEN
      v_post_content := '🔥 ' || COALESCE(v_user_name, 'A friend') || ' just hit a ' || v_celebration.value || '-day streak!';
    WHEN 'level_up' THEN
      v_post_content := '⭐ ' || COALESCE(v_user_name, 'A friend') || ' reached Level ' || v_celebration.value || '!';
    WHEN 'badge_unlock' THEN
      SELECT '🏆 ' || COALESCE(v_user_name, 'A friend') || ' earned the "' || title || '" badge!' INTO v_post_content
      FROM badges WHERE id = v_celebration.badge_id;
    WHEN 'quest_milestone' THEN
      v_post_content := '💪 ' || COALESCE(v_user_name, 'A friend') || ' completed ' || v_celebration.value || ' quests!';
    WHEN 'exercise_milestone' THEN
      v_post_content := '🧘 ' || COALESCE(v_user_name, 'A friend') || ' completed ' || v_celebration.value || ' exercises!';
    ELSE
      v_post_content := '🎉 ' || COALESCE(v_user_name, 'A friend') || ' achieved a milestone!';
  END CASE;

  -- Get user's primary circle (first circle they're a member of)
  SELECT cm.circle_id INTO v_circle_id
  FROM circle_members cm
  WHERE cm.user_id = v_user_id
  ORDER BY cm.joined_at
  LIMIT 1;

  IF v_circle_id IS NOT NULL THEN
    -- Create the circle post
    INSERT INTO circle_posts (circle_id, user_id, post_type, mood_emoji, body_text, local_date)
    VALUES (
      v_circle_id,
      v_user_id,
      'milestone',
      '🎉',
      v_post_content,
      TO_CHAR(NOW() AT TIME ZONE 'UTC', 'YYYY-MM-DD')
    )
    RETURNING id INTO v_post_id;

    -- Update the celebration to mark as shared
    UPDATE celebration_events
    SET shared_to_circle = TRUE,
        circle_post_id = v_post_id
    WHERE id = p_celebration_id;
  END IF;

  RETURN v_post_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- MARK: - Get Celebration Reactions Summary
-- =============================================================================

CREATE OR REPLACE FUNCTION get_celebration_reactions(p_celebration_id UUID)
RETURNS TABLE(
  emoji TEXT,
  count BIGINT,
  user_reacted BOOLEAN
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    cr.emoji,
    COUNT(*)::BIGINT AS count,
    BOOL_OR(cr.reactor_user_id = auth.uid()) AS user_reacted
  FROM celebration_reactions cr
  WHERE cr.celebration_event_id = p_celebration_id
  GROUP BY cr.emoji
  ORDER BY count DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- MARK: - Grant Execute Permissions
-- =============================================================================

GRANT EXECUTE ON FUNCTION check_milestone_triggers(UUID, INT, INT, INT, INT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_pending_celebrations(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION mark_celebration_shown(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION share_celebration_to_circles(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_celebration_reactions(UUID) TO authenticated;
