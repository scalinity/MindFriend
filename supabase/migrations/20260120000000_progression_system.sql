-- Migration: 20260120_progression_system.sql
-- Description: Add XP, levels, skill trees, and seasonal events system

-- =============================================================================
-- MARK: - Badges (recreating if missing from initial schema)
-- =============================================================================

CREATE TABLE IF NOT EXISTS badges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  icon_name TEXT,
  category TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Handle 'name' column if it exists from a different schema version
-- Make it nullable or add it if missing
DO $$
BEGIN
  -- If name column exists with NOT NULL, make it nullable
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'badges' AND column_name = 'name' AND is_nullable = 'NO'
  ) THEN
    ALTER TABLE badges ALTER COLUMN name DROP NOT NULL;
  END IF;

  -- If name column doesn't exist, add it (nullable)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'badges' AND column_name = 'name'
  ) THEN
    ALTER TABLE badges ADD COLUMN name TEXT;
  END IF;

  -- Add title column if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'badges' AND column_name = 'title'
  ) THEN
    ALTER TABLE badges ADD COLUMN title TEXT;
  END IF;

  -- Add code column if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'badges' AND column_name = 'code'
  ) THEN
    ALTER TABLE badges ADD COLUMN code TEXT UNIQUE;
  END IF;

  -- Add description column if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'badges' AND column_name = 'description'
  ) THEN
    ALTER TABLE badges ADD COLUMN description TEXT;
  END IF;

  -- Add icon_name column if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'badges' AND column_name = 'icon_name'
  ) THEN
    ALTER TABLE badges ADD COLUMN icon_name TEXT;
  END IF;

  -- Add category column if missing
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'badges' AND column_name = 'category'
  ) THEN
    ALTER TABLE badges ADD COLUMN category TEXT;
  END IF;

  -- If requirement_type column exists with NOT NULL, make it nullable
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'badges' AND column_name = 'requirement_type' AND is_nullable = 'NO'
  ) THEN
    ALTER TABLE badges ALTER COLUMN requirement_type DROP NOT NULL;
  END IF;

  -- If requirement_value column exists with NOT NULL, make it nullable
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'badges' AND column_name = 'requirement_value' AND is_nullable = 'NO'
  ) THEN
    ALTER TABLE badges ALTER COLUMN requirement_value DROP NOT NULL;
  END IF;
END $$;

-- Sync name with title for any existing rows (only if both columns exist)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns WHERE table_name = 'badges' AND column_name = 'title'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns WHERE table_name = 'badges' AND column_name = 'name'
  ) THEN
    UPDATE badges SET name = title WHERE name IS NULL AND title IS NOT NULL;
  END IF;
END $$;

ALTER TABLE badges ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'badges' AND policyname = 'Anyone can view badges'
  ) THEN
    CREATE POLICY "Anyone can view badges" ON badges
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- =============================================================================
-- MARK: - User Badges (recreating if missing from initial schema)
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_badges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  badge_id UUID NOT NULL REFERENCES badges(id),
  earned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, badge_id)
);

CREATE INDEX IF NOT EXISTS idx_user_badges_user ON user_badges(user_id);

ALTER TABLE user_badges ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'user_badges' AND policyname = 'Users can view own badges'
  ) THEN
    CREATE POLICY "Users can view own badges" ON user_badges
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

-- =============================================================================
-- MARK: - User Stats (recreating if missing from initial schema)
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  current_streak_days INT NOT NULL DEFAULT 0,
  longest_streak_days INT NOT NULL DEFAULT 0,
  total_quests_completed INT NOT NULL DEFAULT 0,
  total_exercises_completed INT NOT NULL DEFAULT 0,
  last_quest_date TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE user_stats ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'user_stats' AND policyname = 'Users can view own stats'
  ) THEN
    CREATE POLICY "Users can view own stats" ON user_stats
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'user_stats' AND policyname = 'Users can update own stats'
  ) THEN
    CREATE POLICY "Users can update own stats" ON user_stats
      FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'user_stats' AND policyname = 'Users can insert own stats'
  ) THEN
    CREATE POLICY "Users can insert own stats" ON user_stats
      FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- MARK: - Add XP columns to user_stats

ALTER TABLE user_stats
  ADD COLUMN IF NOT EXISTS xp_total INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS xp_this_week INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS level INT NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS level_title TEXT NOT NULL DEFAULT 'Beginner',
  ADD COLUMN IF NOT EXISTS last_xp_reset_week TEXT;

-- MARK: - Level Thresholds (50 levels with exponential curve)

CREATE TABLE IF NOT EXISTS level_thresholds (
  level INT PRIMARY KEY,
  xp_required INT NOT NULL,
  title TEXT NOT NULL
);

INSERT INTO level_thresholds (level, xp_required, title) VALUES
  (1, 0, 'Beginner'),
  (2, 100, 'Beginner'),
  (3, 250, 'Beginner'),
  (4, 450, 'Beginner'),
  (5, 700, 'Novice'),
  (6, 1000, 'Novice'),
  (7, 1350, 'Novice'),
  (8, 1750, 'Novice'),
  (9, 2200, 'Apprentice'),
  (10, 2700, 'Apprentice'),
  (11, 3250, 'Apprentice'),
  (12, 3850, 'Apprentice'),
  (13, 4500, 'Practitioner'),
  (14, 5200, 'Practitioner'),
  (15, 5950, 'Practitioner'),
  (16, 6750, 'Practitioner'),
  (17, 7600, 'Journeyer'),
  (18, 8500, 'Journeyer'),
  (19, 9450, 'Journeyer'),
  (20, 10450, 'Journeyer'),
  (21, 11500, 'Explorer'),
  (22, 12600, 'Explorer'),
  (23, 13750, 'Explorer'),
  (24, 14950, 'Explorer'),
  (25, 16200, 'Pathfinder'),
  (26, 17500, 'Pathfinder'),
  (27, 18850, 'Pathfinder'),
  (28, 20250, 'Pathfinder'),
  (29, 21700, 'Seeker'),
  (30, 23200, 'Seeker'),
  (31, 24750, 'Seeker'),
  (32, 26350, 'Seeker'),
  (33, 28000, 'Sage'),
  (34, 29700, 'Sage'),
  (35, 31450, 'Sage'),
  (36, 33250, 'Sage'),
  (37, 35100, 'Master'),
  (38, 37000, 'Master'),
  (39, 38950, 'Master'),
  (40, 40950, 'Master'),
  (41, 43000, 'Grandmaster'),
  (42, 45100, 'Grandmaster'),
  (43, 47250, 'Grandmaster'),
  (44, 49450, 'Grandmaster'),
  (45, 51700, 'Legend'),
  (46, 54000, 'Legend'),
  (47, 56350, 'Legend'),
  (48, 58750, 'Legend'),
  (49, 61200, 'Transcendent'),
  (50, 63700, 'Transcendent')
ON CONFLICT (level) DO NOTHING;

-- Level thresholds are public read-only
ALTER TABLE level_thresholds ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'level_thresholds' AND policyname = 'Anyone can view level thresholds'
  ) THEN
    CREATE POLICY "Anyone can view level thresholds" ON level_thresholds
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- MARK: - Skill Thresholds (5 levels per skill)

CREATE TABLE IF NOT EXISTS skill_thresholds (
  level INT PRIMARY KEY,
  xp_required INT NOT NULL,
  title TEXT NOT NULL
);

INSERT INTO skill_thresholds (level, xp_required, title) VALUES
  (1, 0, 'Novice'),
  (2, 150, 'Apprentice'),
  (3, 400, 'Practitioner'),
  (4, 800, 'Expert'),
  (5, 1500, 'Master')
ON CONFLICT (level) DO NOTHING;

ALTER TABLE skill_thresholds ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'skill_thresholds' AND policyname = 'Anyone can view skill thresholds'
  ) THEN
    CREATE POLICY "Anyone can view skill thresholds" ON skill_thresholds
      FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- MARK: - Skill Progress (per exercise type)

CREATE TABLE IF NOT EXISTS skill_progress (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  skill_type TEXT NOT NULL CHECK (skill_type IN ('breathing', 'meditation', 'grounding', 'journaling', 'movement')),
  xp INT NOT NULL DEFAULT 0,
  level INT NOT NULL DEFAULT 1,
  exercises_completed INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE(user_id, skill_type)
);

CREATE INDEX IF NOT EXISTS idx_skill_progress_user ON skill_progress(user_id);

ALTER TABLE skill_progress ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'skill_progress' AND policyname = 'Users can view own skill progress') THEN
    CREATE POLICY "Users can view own skill progress" ON skill_progress FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'skill_progress' AND policyname = 'Users can insert own skill progress') THEN
    CREATE POLICY "Users can insert own skill progress" ON skill_progress FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'skill_progress' AND policyname = 'Users can update own skill progress') THEN
    CREATE POLICY "Users can update own skill progress" ON skill_progress FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END $$;

-- MARK: - Seasonal Events

CREATE TABLE IF NOT EXISTS seasonal_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  event_type TEXT NOT NULL CHECK (event_type IN ('challenge', 'theme', 'special')),
  required_activity_type TEXT CHECK (required_activity_type IN ('breathing', 'meditation', 'grounding', 'journaling', 'movement', 'quest', 'mood', 'circle')),
  reward_badge_id UUID REFERENCES badges(id),
  target_count INT NOT NULL DEFAULT 30,
  xp_multiplier FLOAT NOT NULL DEFAULT 1.0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT valid_event_dates CHECK (ends_at > starts_at)
);

CREATE INDEX IF NOT EXISTS idx_events_active ON seasonal_events(starts_at, ends_at);

ALTER TABLE seasonal_events ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'seasonal_events' AND policyname = 'Anyone can view seasonal events') THEN
    CREATE POLICY "Anyone can view seasonal events" ON seasonal_events FOR SELECT TO authenticated USING (true);
  END IF;
END $$;

-- MARK: - Event Participation

CREATE TABLE IF NOT EXISTS event_participation (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_id UUID NOT NULL REFERENCES seasonal_events(id) ON DELETE CASCADE,
  progress INT NOT NULL DEFAULT 0,
  completed_at TIMESTAMPTZ,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE(user_id, event_id)
);

CREATE INDEX IF NOT EXISTS idx_event_participation_user ON event_participation(user_id);
CREATE INDEX IF NOT EXISTS idx_event_participation_event ON event_participation(event_id);

ALTER TABLE event_participation ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'event_participation' AND policyname = 'Users can view own event participation') THEN
    CREATE POLICY "Users can view own event participation" ON event_participation FOR SELECT USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'event_participation' AND policyname = 'Users can join events') THEN
    CREATE POLICY "Users can join events" ON event_participation FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'event_participation' AND policyname = 'Users can update own event progress') THEN
    CREATE POLICY "Users can update own event progress" ON event_participation FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END $$;

-- MARK: - Award XP Function

CREATE OR REPLACE FUNCTION award_xp(
  p_user_id UUID,
  p_amount INT,
  p_activity_type TEXT,
  p_skill_type TEXT DEFAULT NULL
) RETURNS TABLE(new_xp INT, new_level INT, new_title TEXT, level_up BOOLEAN) AS $$
DECLARE
  v_current_xp INT;
  v_new_xp INT;
  v_current_level INT;
  v_new_level INT;
  v_new_title TEXT;
  v_level_changed BOOLEAN := FALSE;
  v_skill_xp INT;
  v_skill_level INT;
BEGIN
  -- Lock the row to prevent race conditions
  SELECT xp_total, level INTO v_current_xp, v_current_level
  FROM user_stats
  WHERE user_id = p_user_id
  FOR UPDATE;

  -- Initialize if null (shouldn't happen due to trigger, but defensive)
  IF v_current_xp IS NULL THEN
    v_current_xp := 0;
    v_current_level := 1;
  END IF;

  -- Calculate new XP
  v_new_xp := v_current_xp + p_amount;

  -- Determine new level from thresholds
  SELECT lt.level, lt.title INTO v_new_level, v_new_title
  FROM level_thresholds lt
  WHERE lt.xp_required <= v_new_xp
  ORDER BY lt.level DESC
  LIMIT 1;

  -- Check for level up
  v_level_changed := v_new_level > v_current_level;

  -- Update user stats
  UPDATE user_stats
  SET xp_total = v_new_xp,
      xp_this_week = xp_this_week + p_amount,
      level = v_new_level,
      level_title = v_new_title,
      updated_at = NOW()
  WHERE user_id = p_user_id;

  -- Update skill progress if skill type provided
  IF p_skill_type IS NOT NULL AND p_skill_type IN ('breathing', 'meditation', 'grounding', 'journaling', 'movement') THEN
    -- Insert or update skill progress
    INSERT INTO skill_progress (user_id, skill_type, xp, exercises_completed)
    VALUES (p_user_id, p_skill_type, p_amount, 1)
    ON CONFLICT (user_id, skill_type) DO UPDATE
    SET xp = skill_progress.xp + EXCLUDED.xp,
        exercises_completed = skill_progress.exercises_completed + 1,
        updated_at = NOW();

    -- Get updated skill XP to calculate level
    SELECT xp INTO v_skill_xp
    FROM skill_progress
    WHERE user_id = p_user_id AND skill_type = p_skill_type;

    -- Determine skill level
    SELECT st.level INTO v_skill_level
    FROM skill_thresholds st
    WHERE st.xp_required <= v_skill_xp
    ORDER BY st.level DESC
    LIMIT 1;

    -- Update skill level
    UPDATE skill_progress
    SET level = v_skill_level
    WHERE user_id = p_user_id AND skill_type = p_skill_type;
  END IF;

  RETURN QUERY SELECT v_new_xp, v_new_level, v_new_title, v_level_changed;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- MARK: - Increment Event Progress Function

CREATE OR REPLACE FUNCTION increment_event_progress(
  p_user_id UUID,
  p_activity_type TEXT
) RETURNS TABLE(event_id UUID, event_name TEXT, new_progress INT, target_count INT, just_completed BOOLEAN) AS $$
DECLARE
  v_participation RECORD;
  v_event RECORD;
  v_badge_id UUID;
BEGIN
  -- Find all active events that match this activity type
  FOR v_participation IN
    SELECT ep.id, ep.event_id, ep.progress, se.target_count, se.name, se.reward_badge_id
    FROM event_participation ep
    JOIN seasonal_events se ON se.id = ep.event_id
    WHERE ep.user_id = p_user_id
      AND ep.completed_at IS NULL
      AND se.required_activity_type = p_activity_type
      AND NOW() BETWEEN se.starts_at AND se.ends_at
    FOR UPDATE OF ep
  LOOP
    -- Increment progress
    UPDATE event_participation
    SET progress = progress + 1,
        completed_at = CASE
          WHEN progress + 1 >= v_participation.target_count THEN NOW()
          ELSE NULL
        END
    WHERE id = v_participation.id;

    -- Award badge if just completed
    IF v_participation.progress + 1 >= v_participation.target_count AND v_participation.reward_badge_id IS NOT NULL THEN
      INSERT INTO user_badges (user_id, badge_id)
      VALUES (p_user_id, v_participation.reward_badge_id)
      ON CONFLICT (user_id, badge_id) DO NOTHING;
    END IF;

    RETURN QUERY SELECT
      v_participation.event_id,
      v_participation.name,
      v_participation.progress + 1,
      v_participation.target_count,
      v_participation.progress + 1 >= v_participation.target_count;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- MARK: - Reset Weekly XP Function (called by client on app launch)

CREATE OR REPLACE FUNCTION reset_weekly_xp_if_needed(
  p_user_id UUID
) RETURNS BOOLEAN AS $$
DECLARE
  v_current_week TEXT;
  v_last_reset_week TEXT;
  v_was_reset BOOLEAN := FALSE;
BEGIN
  -- Get ISO week string (YYYY-WW format)
  v_current_week := TO_CHAR(NOW(), 'IYYY-IW');

  -- Get user's last reset week
  SELECT last_xp_reset_week INTO v_last_reset_week
  FROM user_stats
  WHERE user_id = p_user_id;

  -- Reset if week changed
  IF v_last_reset_week IS NULL OR v_last_reset_week != v_current_week THEN
    UPDATE user_stats
    SET xp_this_week = 0,
        last_xp_reset_week = v_current_week,
        updated_at = NOW()
    WHERE user_id = p_user_id;
    v_was_reset := TRUE;
  END IF;

  RETURN v_was_reset;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- MARK: - Seed Seasonal Events with Dynamic Badges

-- Ensure badges table has all required columns (may be missing if table existed with different schema)
ALTER TABLE badges ADD COLUMN IF NOT EXISTS code TEXT UNIQUE;
ALTER TABLE badges ADD COLUMN IF NOT EXISTS name TEXT;
ALTER TABLE badges ADD COLUMN IF NOT EXISTS title TEXT;
ALTER TABLE badges ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE badges ADD COLUMN IF NOT EXISTS icon_name TEXT;
ALTER TABLE badges ADD COLUMN IF NOT EXISTS category TEXT;

-- Insert event badges first (use ON CONFLICT to handle duplicates)
-- Include 'name' column to handle tables with that column
INSERT INTO badges (code, name, title, description, icon_name, category) VALUES
  ('gratitude_champion', '30 Days of Gratitude', '30 Days of Gratitude', 'Complete the November gratitude challenge', 'heart.text.square.fill', 'seasonal'),
  ('mindful_start', 'New Year Mindfulness', 'New Year Mindfulness', 'Complete the January meditation challenge', 'sparkles', 'seasonal'),
  ('spring_renewal', 'Spring Renewal', 'Spring Renewal', 'Complete the April movement challenge', 'leaf.fill', 'seasonal')
ON CONFLICT (code) DO NOTHING;

-- Insert seasonal events with badge references (only if not already present)
INSERT INTO seasonal_events (name, description, starts_at, ends_at, event_type, required_activity_type, reward_badge_id, target_count)
SELECT
  '30 Days of Gratitude',
  'Write a gratitude journal entry every day in November to earn a special badge',
  '2026-11-01 00:00:00+00',
  '2026-11-30 23:59:59+00',
  'challenge',
  'journaling',
  b.id,
  30
FROM badges b
WHERE b.code = 'gratitude_champion'
  AND NOT EXISTS (SELECT 1 FROM seasonal_events WHERE name = '30 Days of Gratitude');

INSERT INTO seasonal_events (name, description, starts_at, ends_at, event_type, required_activity_type, reward_badge_id, target_count)
SELECT
  'New Year Mindfulness',
  'Start the year right with daily meditation throughout January',
  '2027-01-01 00:00:00+00',
  '2027-01-31 23:59:59+00',
  'challenge',
  'meditation',
  b.id,
  31
FROM badges b
WHERE b.code = 'mindful_start'
  AND NOT EXISTS (SELECT 1 FROM seasonal_events WHERE name = 'New Year Mindfulness');

INSERT INTO seasonal_events (name, description, starts_at, ends_at, event_type, required_activity_type, reward_badge_id, target_count)
SELECT
  'Spring Renewal',
  'Get moving with daily movement exercises in April',
  '2027-04-01 00:00:00+00',
  '2027-04-30 23:59:59+00',
  'challenge',
  'movement',
  b.id,
  30
FROM badges b
WHERE b.code = 'spring_renewal'
  AND NOT EXISTS (SELECT 1 FROM seasonal_events WHERE name = 'Spring Renewal');

-- MARK: - Grant execute permissions

GRANT EXECUTE ON FUNCTION award_xp(UUID, INT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION increment_event_progress(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION reset_weekly_xp_if_needed(UUID) TO authenticated;
