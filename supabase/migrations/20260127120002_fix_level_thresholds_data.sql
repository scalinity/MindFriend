-- Fix level_thresholds table data to match iOS xpThresholds array
-- And recalculate all user levels in user_stats table

-- First, ensure level_thresholds has correct data
-- Use DELETE + INSERT to fully refresh (ON CONFLICT DO NOTHING won't update existing wrong data)

DELETE FROM level_thresholds WHERE level <= 50;

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
  (50, 63700, 'Transcendent');

-- Now recalculate all user levels in user_stats based on their xp_total
-- Using the newly refreshed level_thresholds table
UPDATE user_stats us
SET
  level = COALESCE((
    SELECT lt.level
    FROM level_thresholds lt
    WHERE lt.xp_required <= COALESCE(us.xp_total, 0)
    ORDER BY lt.level DESC
    LIMIT 1
  ), 1),
  level_title = COALESCE((
    SELECT lt.title
    FROM level_thresholds lt
    WHERE lt.xp_required <= COALESCE(us.xp_total, 0)
    ORDER BY lt.level DESC
    LIMIT 1
  ), 'Beginner'),
  updated_at = NOW()
WHERE xp_total IS NOT NULL AND xp_total > 0;

-- Log the fix
DO $$
DECLARE
  affected_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO affected_count
  FROM user_stats
  WHERE xp_total IS NOT NULL AND xp_total > 0;
  RAISE NOTICE 'Recalculated levels for % users based on corrected level_thresholds', affected_count;
END $$;
