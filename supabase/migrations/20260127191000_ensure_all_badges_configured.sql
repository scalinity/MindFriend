-- Ensure ALL badges are properly configured for auto-awarding
-- This migration upserts all badge definitions with correct requirement_type and requirement_config

-- ============================================================================
-- GETTING STARTED BADGES (5)
-- ============================================================================
INSERT INTO badges_v2 (slug, name, description, icon_url, category, requirement_type, requirement_config, rarity, xp_reward, is_active, sort_order)
VALUES
    ('first_quest', 'First Steps', 'Complete your first quest', '/badges/first-quest.svg', 'getting_started', 'count', '{"metric": "quests_completed", "target": 1}', 'common', 10, true, 1),
    ('first_mood', 'Mood Logger', 'Log your first mood', '/badges/first-mood.svg', 'getting_started', 'count', '{"metric": "moods_logged", "target": 1}', 'common', 10, true, 2),
    ('first_exercise', 'Moving Forward', 'Complete your first exercise', '/badges/first-exercise.svg', 'getting_started', 'count', '{"metric": "exercises_completed", "target": 1}', 'common', 10, true, 3),
    ('first_meditation', 'Inner Peace', 'Complete your first meditation', '/badges/first-meditation.svg', 'getting_started', 'count', '{"metric": "meditations_completed", "target": 1}', 'common', 10, true, 4),
    ('profile_complete', 'All Set', 'Complete your profile setup', '/badges/profile-complete.svg', 'getting_started', 'manual', '{"trigger": "profile_complete"}', 'common', 25, true, 5)
ON CONFLICT (slug) DO UPDATE SET
    requirement_type = EXCLUDED.requirement_type,
    requirement_config = EXCLUDED.requirement_config,
    is_active = true;

-- ============================================================================
-- QUEST MILESTONE BADGES (5)
-- ============================================================================
INSERT INTO badges_v2 (slug, name, description, icon_url, category, tier, tier_order, requirement_type, requirement_config, rarity, xp_reward, is_active, sort_order)
VALUES
    ('quests_10', 'Quest Explorer', 'Complete 10 quests', '/badges/quests-bronze.svg', 'quests', 'bronze', 1, 'count', '{"metric": "quests_completed", "target": 10}', 'common', 25, true, 10),
    ('quests_25', 'Quest Achiever', 'Complete 25 quests', '/badges/quests-silver.svg', 'quests', 'silver', 2, 'count', '{"metric": "quests_completed", "target": 25}', 'uncommon', 50, true, 11),
    ('quests_50', 'Quest Champion', 'Complete 50 quests', '/badges/quests-gold.svg', 'quests', 'gold', 3, 'count', '{"metric": "quests_completed", "target": 50}', 'rare', 100, true, 12),
    ('quests_100', 'Quest Master', 'Complete 100 quests', '/badges/quests-diamond.svg', 'quests', 'diamond', 4, 'count', '{"metric": "quests_completed", "target": 100}', 'epic', 250, true, 13),
    ('quests_250', 'Quest Legend', 'Complete 250 quests', '/badges/quests-legendary.svg', 'quests', 'legendary', 5, 'count', '{"metric": "quests_completed", "target": 250}', 'legendary', 500, true, 14)
ON CONFLICT (slug) DO UPDATE SET
    requirement_type = EXCLUDED.requirement_type,
    requirement_config = EXCLUDED.requirement_config,
    is_active = true;

-- ============================================================================
-- STREAK BADGES (6)
-- ============================================================================
INSERT INTO badges_v2 (slug, name, description, icon_url, category, tier, tier_order, requirement_type, requirement_config, rarity, xp_reward, is_active, sort_order)
VALUES
    ('streak_7', 'Week Warrior', '7-day streak', '/badges/streak-7.svg', 'streaks', 'bronze', 1, 'streak', '{"streak_type": "quest", "target": 7}', 'common', 50, true, 20),
    ('streak_14', 'Fortnight Force', '14-day streak', '/badges/streak-14.svg', 'streaks', 'silver', 2, 'streak', '{"streak_type": "quest", "target": 14}', 'uncommon', 100, true, 21),
    ('streak_30', 'Monthly Master', '30-day streak', '/badges/streak-30.svg', 'streaks', 'gold', 3, 'streak', '{"streak_type": "quest", "target": 30}', 'rare', 200, true, 22),
    ('streak_60', 'Double Down', '60-day streak', '/badges/streak-60.svg', 'streaks', 'diamond', 4, 'streak', '{"streak_type": "quest", "target": 60}', 'epic', 400, true, 23),
    ('streak_100', 'Century Club', '100-day streak', '/badges/streak-100.svg', 'streaks', 'legendary', 5, 'streak', '{"streak_type": "quest", "target": 100}', 'legendary', 1000, true, 24),
    ('streak_365', 'Year of Growth', '365-day streak', '/badges/streak-365.svg', 'streaks', 'legendary', 5, 'streak', '{"streak_type": "quest", "target": 365}', 'legendary', 5000, true, 25)
ON CONFLICT (slug) DO UPDATE SET
    requirement_type = EXCLUDED.requirement_type,
    requirement_config = EXCLUDED.requirement_config,
    is_active = true;

-- ============================================================================
-- EXERCISE BADGES (6)
-- ============================================================================
INSERT INTO badges_v2 (slug, name, description, icon_url, category, tier, tier_order, requirement_type, requirement_config, rarity, xp_reward, is_active, sort_order)
VALUES
    ('exercises_10', 'Active Mind', 'Complete 10 exercises', '/badges/exercise-bronze.svg', 'exercises', 'bronze', 1, 'count', '{"metric": "exercises_completed", "target": 10}', 'common', 25, true, 30),
    ('exercises_25', 'Wellness Warrior', 'Complete 25 exercises', '/badges/exercise-silver.svg', 'exercises', 'silver', 2, 'count', '{"metric": "exercises_completed", "target": 25}', 'uncommon', 50, true, 31),
    ('exercises_50', 'Fitness Fanatic', 'Complete 50 exercises', '/badges/exercise-gold.svg', 'exercises', 'gold', 3, 'count', '{"metric": "exercises_completed", "target": 50}', 'rare', 100, true, 32),
    ('exercises_100', 'Exercise Expert', 'Complete 100 exercises', '/badges/exercise-diamond.svg', 'exercises', 'diamond', 4, 'count', '{"metric": "exercises_completed", "target": 100}', 'epic', 250, true, 33),
    ('breathing_master', 'Breath Master', 'Complete 20 breathing exercises', '/badges/breathing-master.svg', 'exercises', 'gold', 3, 'count', '{"metric": "exercises_completed", "target": 20, "filter": {"type": "breathing"}}', 'rare', 100, true, 34),
    ('grounding_guru', 'Grounding Guru', 'Complete 15 grounding exercises', '/badges/grounding-guru.svg', 'exercises', 'gold', 3, 'count', '{"metric": "exercises_completed", "target": 15, "filter": {"type": "grounding"}}', 'rare', 100, true, 35)
ON CONFLICT (slug) DO UPDATE SET
    requirement_type = EXCLUDED.requirement_type,
    requirement_config = EXCLUDED.requirement_config,
    is_active = true;

-- ============================================================================
-- MEDITATION BADGES (6)
-- ============================================================================
INSERT INTO badges_v2 (slug, name, description, icon_url, category, tier, tier_order, requirement_type, requirement_config, rarity, xp_reward, is_active, sort_order)
VALUES
    ('meditation_10', 'Meditation Starter', 'Complete 10 meditations', '/badges/meditation-bronze.svg', 'meditation', 'bronze', 1, 'count', '{"metric": "meditations_completed", "target": 10}', 'common', 25, true, 40),
    ('meditation_25', 'Calm Seeker', 'Complete 25 meditations', '/badges/meditation-silver.svg', 'meditation', 'silver', 2, 'count', '{"metric": "meditations_completed", "target": 25}', 'uncommon', 50, true, 41),
    ('meditation_50', 'Mindful Maven', 'Complete 50 meditations', '/badges/meditation-gold.svg', 'meditation', 'gold', 3, 'count', '{"metric": "meditations_completed", "target": 50}', 'rare', 100, true, 42),
    ('meditation_100', 'Zen Master', 'Complete 100 meditations', '/badges/meditation-diamond.svg', 'meditation', 'diamond', 4, 'count', '{"metric": "meditations_completed", "target": 100}', 'epic', 250, true, 43),
    ('meditation_time_60', 'Hour of Peace', 'Meditate for 60 minutes total', '/badges/meditation-hour.svg', 'meditation', 'silver', 2, 'time', '{"metric": "meditation_time", "target": 3600}', 'uncommon', 75, true, 44),
    ('meditation_time_600', 'Ten Hours of Calm', 'Meditate for 10 hours total', '/badges/meditation-10hrs.svg', 'meditation', 'gold', 3, 'time', '{"metric": "meditation_time", "target": 36000}', 'rare', 200, true, 45)
ON CONFLICT (slug) DO UPDATE SET
    requirement_type = EXCLUDED.requirement_type,
    requirement_config = EXCLUDED.requirement_config,
    is_active = true;

-- ============================================================================
-- MOOD LOGGING BADGES (4)
-- ============================================================================
INSERT INTO badges_v2 (slug, name, description, icon_url, category, tier, tier_order, requirement_type, requirement_config, rarity, xp_reward, is_active, sort_order)
VALUES
    ('moods_10', 'Self Aware', 'Log 10 moods', '/badges/mood-bronze.svg', 'mood', 'bronze', 1, 'count', '{"metric": "moods_logged", "target": 10}', 'common', 25, true, 50),
    ('moods_30', 'Mood Tracker', 'Log 30 moods', '/badges/mood-silver.svg', 'mood', 'silver', 2, 'count', '{"metric": "moods_logged", "target": 30}', 'uncommon', 50, true, 51),
    ('moods_100', 'Emotional Intelligence', 'Log 100 moods', '/badges/mood-gold.svg', 'mood', 'gold', 3, 'count', '{"metric": "moods_logged", "target": 100}', 'rare', 100, true, 52),
    ('moods_365', 'Year in Review', 'Log 365 moods', '/badges/mood-diamond.svg', 'mood', 'diamond', 4, 'count', '{"metric": "moods_logged", "target": 365}', 'epic', 500, true, 53)
ON CONFLICT (slug) DO UPDATE SET
    requirement_type = EXCLUDED.requirement_type,
    requirement_config = EXCLUDED.requirement_config,
    is_active = true;

-- ============================================================================
-- CIRCLE/SOCIAL BADGES (4)
-- ============================================================================
INSERT INTO badges_v2 (slug, name, description, icon_url, category, tier, tier_order, requirement_type, requirement_config, rarity, xp_reward, is_active, sort_order)
VALUES
    ('first_circle', 'Circle Joiner', 'Join your first circle', '/badges/circle-join.svg', 'circles', 'bronze', 1, 'count', '{"metric": "circles_joined", "target": 1}', 'common', 25, true, 60),
    ('circle_posts_10', 'Community Voice', 'Post 10 circle check-ins', '/badges/circle-posts-bronze.svg', 'circles', 'bronze', 1, 'count', '{"metric": "circle_posts", "target": 10}', 'common', 25, true, 61),
    ('circle_posts_50', 'Circle Leader', 'Post 50 circle check-ins', '/badges/circle-posts-gold.svg', 'circles', 'gold', 3, 'count', '{"metric": "circle_posts", "target": 50}', 'rare', 100, true, 62),
    ('circle_creator', 'Circle Creator', 'Create a circle', '/badges/circle-create.svg', 'circles', 'silver', 2, 'manual', '{"trigger": "circle_created"}', 'uncommon', 50, true, 63)
ON CONFLICT (slug) DO UPDATE SET
    requirement_type = EXCLUDED.requirement_type,
    requirement_config = EXCLUDED.requirement_config,
    is_active = true;

-- ============================================================================
-- LEVEL MILESTONE BADGES (5)
-- ============================================================================
INSERT INTO badges_v2 (slug, name, description, icon_url, category, tier, tier_order, requirement_type, requirement_config, rarity, xp_reward, is_active, sort_order)
VALUES
    ('level_5', 'Rising Star', 'Reach Level 5', '/badges/level-5.svg', 'special', 'bronze', 1, 'count', '{"metric": "user_level", "target": 5}', 'common', 50, true, 70),
    ('level_10', 'Explorer', 'Reach Level 10', '/badges/level-10.svg', 'special', 'silver', 2, 'count', '{"metric": "user_level", "target": 10}', 'uncommon', 100, true, 71),
    ('level_25', 'Adept', 'Reach Level 25', '/badges/level-25.svg', 'special', 'gold', 3, 'count', '{"metric": "user_level", "target": 25}', 'rare', 250, true, 72),
    ('level_50', 'Master', 'Reach Level 50', '/badges/level-50.svg', 'special', 'diamond', 4, 'count', '{"metric": "user_level", "target": 50}', 'epic', 500, true, 73),
    ('level_100', 'Legend', 'Reach Level 100', '/badges/level-100.svg', 'special', 'legendary', 5, 'count', '{"metric": "user_level", "target": 100}', 'legendary', 1000, true, 74)
ON CONFLICT (slug) DO UPDATE SET
    requirement_type = EXCLUDED.requirement_type,
    requirement_config = EXCLUDED.requirement_config,
    is_active = true;

-- ============================================================================
-- SECRET/SPECIAL BADGES (5)
-- These are manual badges, not auto-trackable
-- ============================================================================
INSERT INTO badges_v2 (slug, name, description, icon_url, category, requirement_type, requirement_config, rarity, is_secret, reveal_hint, xp_reward, is_active, sort_order)
VALUES
    ('night_owl', 'Night Owl', 'Complete an activity after midnight', '/badges/night-owl.svg', 'special', 'manual', '{"trigger": "activity_after_midnight"}', 'rare', true, 'The quiet hours hold secrets...', 100, true, 80),
    ('early_bird', 'Early Bird', 'Complete an activity before 6am', '/badges/early-bird.svg', 'special', 'manual', '{"trigger": "activity_before_6am"}', 'rare', true, 'The early bird catches the badge!', 100, true, 81),
    ('perfect_week', 'Perfect Week', 'Complete all quests in a week', '/badges/perfect-week.svg', 'special', 'manual', '{"trigger": "perfect_week"}', 'epic', true, 'Consistency is key...', 250, true, 82),
    ('comeback_kid', 'Comeback Kid', 'Return after 7+ days away', '/badges/comeback.svg', 'special', 'manual', '{"trigger": "returned_after_7_days"}', 'uncommon', true, 'Sometimes we all need a break', 75, true, 83),
    ('founding_member', 'Founding Member', 'Joined during launch week', '/badges/founding-member.svg', 'special', 'manual', '{"trigger": "founding_member"}', 'legendary', false, NULL, 500, true, 84)
ON CONFLICT (slug) DO UPDATE SET
    requirement_type = EXCLUDED.requirement_type,
    requirement_config = EXCLUDED.requirement_config,
    is_active = true;

-- ============================================================================
-- VERIFICATION QUERY (for debugging)
-- ============================================================================
-- Run this to verify badges are properly configured:
-- SELECT slug, name, requirement_type, requirement_config, is_active
-- FROM badges_v2
-- WHERE requirement_type IN ('count', 'streak', 'time')
-- ORDER BY sort_order;

COMMENT ON TABLE badges_v2 IS 'Badge definitions - ALL auto-trackable badges configured 2026-01-27. Total: 46 badges (41 auto-trackable, 5 manual).';
