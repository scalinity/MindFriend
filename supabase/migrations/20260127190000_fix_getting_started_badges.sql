-- Fix Getting Started badges configuration
-- Ensures badges have correct requirement_type and requirement_config for auto-awarding

-- Update first_mood badge to ensure it has correct configuration
UPDATE badges_v2
SET
  requirement_type = 'count',
  requirement_config = '{"metric": "moods_logged", "target": 1}'::jsonb,
  is_active = true
WHERE slug = 'first_mood';

-- Update first_quest badge
UPDATE badges_v2
SET
  requirement_type = 'count',
  requirement_config = '{"metric": "quests_completed", "target": 1}'::jsonb,
  is_active = true
WHERE slug = 'first_quest';

-- Update first_exercise badge
UPDATE badges_v2
SET
  requirement_type = 'count',
  requirement_config = '{"metric": "exercises_completed", "target": 1}'::jsonb,
  is_active = true
WHERE slug = 'first_exercise';

-- Update first_meditation badge
UPDATE badges_v2
SET
  requirement_type = 'count',
  requirement_config = '{"metric": "meditations_completed", "target": 1}'::jsonb,
  is_active = true
WHERE slug = 'first_meditation';

-- Update first_circle badge (if exists)
UPDATE badges_v2
SET
  requirement_type = 'count',
  requirement_config = '{"metric": "circles_joined", "target": 1}'::jsonb,
  is_active = true
WHERE slug = 'first_circle';

-- Insert badges if they don't exist (in case they were never seeded)
INSERT INTO badges_v2 (slug, name, description, icon_url, category, requirement_type, requirement_config, rarity, xp_reward, is_active, sort_order)
VALUES
  ('first_mood', 'Mood Logger', 'Log your first mood', '/badges/first-mood.svg', 'getting_started', 'count', '{"metric": "moods_logged", "target": 1}'::jsonb, 'common', 10, true, 2),
  ('first_quest', 'Quest Starter', 'Complete your first quest', '/badges/first-quest.svg', 'getting_started', 'count', '{"metric": "quests_completed", "target": 1}'::jsonb, 'common', 10, true, 1),
  ('first_exercise', 'Moving Forward', 'Complete your first exercise', '/badges/first-exercise.svg', 'getting_started', 'count', '{"metric": "exercises_completed", "target": 1}'::jsonb, 'common', 10, true, 3),
  ('first_meditation', 'Inner Peace', 'Complete your first meditation', '/badges/first-meditation.svg', 'getting_started', 'count', '{"metric": "meditations_completed", "target": 1}'::jsonb, 'common', 10, true, 4),
  ('first_circle', 'Circle Joiner', 'Join your first circle', '/badges/circle-join.svg', 'circles', 'count', '{"metric": "circles_joined", "target": 1}'::jsonb, 'common', 25, true, 60)
ON CONFLICT (slug) DO UPDATE SET
  requirement_type = EXCLUDED.requirement_type,
  requirement_config = EXCLUDED.requirement_config,
  is_active = EXCLUDED.is_active;

-- Add comment
COMMENT ON TABLE badges_v2 IS 'Badge definitions with auto-trackable requirements. Getting Started badges fixed 2026-01-27.';
