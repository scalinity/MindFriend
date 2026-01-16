-- Achievement System 2.0
-- Comprehensive gamification with skill trees, XP, streaks, seasons, and collectibles

-- ============================================================================
-- SEASONS (Create first - referenced by badges)
-- ============================================================================

CREATE TABLE IF NOT EXISTS seasons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    slug TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    theme TEXT, -- 'spring_renewal', 'summer_energy', etc.

    -- Visual
    banner_url TEXT,
    color_primary TEXT,
    color_secondary TEXT,

    -- Timing
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,

    -- Rewards
    free_track_rewards JSONB, -- Array of milestone rewards
    premium_track_rewards JSONB,

    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- BADGES V2 - Enhanced badge definitions
-- ============================================================================

CREATE TABLE IF NOT EXISTS badges_v2 (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Identity
    slug TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL,

    -- Visual
    icon_url TEXT NOT NULL,
    background_color TEXT,
    animation_type TEXT, -- 'none', 'sparkle', 'pulse', 'glow'

    -- Classification
    category TEXT NOT NULL CHECK (category IN (
        'getting_started', 'streaks', 'quests', 'exercises',
        'meditation', 'mood', 'circles', 'special', 'seasonal'
    )),
    subcategory TEXT,

    -- Tier (for progressive badges)
    tier TEXT CHECK (tier IN ('bronze', 'silver', 'gold', 'diamond', 'legendary')),
    tier_order INTEGER, -- 1=bronze, 2=silver, etc.
    parent_badge_id UUID REFERENCES badges_v2(id), -- For tier progression

    -- Requirements
    requirement_type TEXT NOT NULL, -- 'count', 'streak', 'time', 'combination', 'manual'
    requirement_config JSONB NOT NULL, -- Flexible requirement definition

    -- Progress tracking
    progress_trackable BOOLEAN DEFAULT true,
    progress_metric TEXT, -- For tracking partial progress

    -- Rarity
    rarity TEXT DEFAULT 'common' CHECK (rarity IN (
        'common', 'uncommon', 'rare', 'epic', 'legendary'
    )),

    -- Visibility
    is_secret BOOLEAN DEFAULT false,
    reveal_hint TEXT, -- Hint for secret badges

    -- Timing
    is_seasonal BOOLEAN DEFAULT false,
    season_id UUID REFERENCES seasons(id),
    available_from TIMESTAMPTZ,
    available_until TIMESTAMPTZ,

    -- Rewards
    xp_reward INTEGER DEFAULT 0,
    unlock_content JSONB, -- {"theme": "dark_zen", "avatar_item": "meditation_hat"}

    -- Stats
    total_earners INTEGER DEFAULT 0,

    -- Meta
    is_active BOOLEAN DEFAULT true,
    sort_order INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for badges
CREATE INDEX IF NOT EXISTS idx_badges_v2_category ON badges_v2(category);
CREATE INDEX IF NOT EXISTS idx_badges_v2_seasonal ON badges_v2(is_seasonal, season_id);
CREATE INDEX IF NOT EXISTS idx_badges_v2_tier ON badges_v2(parent_badge_id);
CREATE INDEX IF NOT EXISTS idx_badges_v2_active ON badges_v2(is_active);

-- ============================================================================
-- USER BADGES V2 - User badge progress and awards
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_badges_v2 (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    badge_id UUID NOT NULL REFERENCES badges_v2(id),

    -- Progress
    progress_current INTEGER DEFAULT 0,
    progress_target INTEGER,
    progress_percentage NUMERIC(5,2) GENERATED ALWAYS AS (
        CASE WHEN progress_target > 0 AND progress_target IS NOT NULL
        THEN LEAST((progress_current::NUMERIC / progress_target * 100), 100)
        ELSE 0 END
    ) STORED,

    -- Award status
    earned_at TIMESTAMPTZ,
    is_earned BOOLEAN DEFAULT false,

    -- Social
    shared_to_circle BOOLEAN DEFAULT false,
    is_showcased BOOLEAN DEFAULT false, -- Featured on profile

    -- Notifications
    notified_at_50 BOOLEAN DEFAULT false,
    notified_at_75 BOOLEAN DEFAULT false,
    notified_at_90 BOOLEAN DEFAULT false,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_id, badge_id)
);

CREATE INDEX IF NOT EXISTS idx_user_badges_v2_user ON user_badges_v2(user_id);
CREATE INDEX IF NOT EXISTS idx_user_badges_v2_earned ON user_badges_v2(user_id, is_earned);
CREATE INDEX IF NOT EXISTS idx_user_badges_v2_progress ON user_badges_v2(user_id, progress_percentage DESC);

-- ============================================================================
-- SKILL TREES
-- ============================================================================

CREATE TABLE IF NOT EXISTS skill_trees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    slug TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    icon_url TEXT,
    color TEXT, -- Primary color

    max_level INTEGER DEFAULT 10,

    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Skill tree nodes
CREATE TABLE IF NOT EXISTS skill_tree_nodes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tree_id UUID NOT NULL REFERENCES skill_trees(id) ON DELETE CASCADE,

    -- Identity
    slug TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    icon_url TEXT,

    -- Position in tree
    tier INTEGER NOT NULL, -- 1-5, higher = more advanced
    position INTEGER NOT NULL, -- Position within tier

    -- Prerequisites
    prerequisite_nodes UUID[], -- Node IDs that must be unlocked first

    -- Unlock requirements
    unlock_type TEXT NOT NULL CHECK (unlock_type IN (
        'xp', 'badge', 'activity', 'purchase'
    )),
    unlock_config JSONB NOT NULL,

    -- Rewards
    xp_reward INTEGER DEFAULT 0,
    badge_reward_id UUID REFERENCES badges_v2(id),
    unlock_content JSONB,

    UNIQUE(tree_id, slug)
);

CREATE INDEX IF NOT EXISTS idx_skill_nodes_tree ON skill_tree_nodes(tree_id, tier);

-- User skill tree progress
CREATE TABLE IF NOT EXISTS user_skill_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    tree_id UUID NOT NULL REFERENCES skill_trees(id),

    -- Overall progress
    current_level INTEGER DEFAULT 1,
    current_xp INTEGER DEFAULT 0,
    total_xp INTEGER DEFAULT 0,

    -- Nodes
    unlocked_nodes UUID[] DEFAULT '{}',

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_id, tree_id)
);

-- ============================================================================
-- USER EXPERIENCE & LEVELS
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_experience (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Overall
    total_xp INTEGER DEFAULT 0,
    current_level INTEGER DEFAULT 1,
    xp_to_next_level INTEGER DEFAULT 100,

    -- Daily tracking
    daily_xp INTEGER DEFAULT 0,
    daily_xp_date DATE DEFAULT CURRENT_DATE,

    -- Weekly tracking
    weekly_xp INTEGER DEFAULT 0,
    week_start_date DATE,

    -- Prestige
    prestige_level INTEGER DEFAULT 0,

    -- Bonuses
    xp_multiplier NUMERIC(3,2) DEFAULT 1.0,
    multiplier_expires_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_id)
);

-- XP transactions log
CREATE TABLE IF NOT EXISTS xp_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    amount INTEGER NOT NULL,
    source TEXT NOT NULL, -- 'quest', 'exercise', 'mood', 'badge', 'streak', 'bonus'
    source_id TEXT, -- ID of the triggering entity
    description TEXT,

    -- Multiplier at time of transaction
    multiplier_applied NUMERIC(3,2) DEFAULT 1.0,
    base_amount INTEGER, -- Before multiplier

    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_xp_transactions_user ON xp_transactions(user_id, created_at DESC);

-- ============================================================================
-- ENHANCED STREAKS V2
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_streaks_v2 (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    streak_type TEXT NOT NULL CHECK (streak_type IN (
        'quest', 'mood', 'exercise', 'meditation', 'checkin', 'app_open'
    )),

    -- Current streak
    current_count INTEGER DEFAULT 0,
    longest_count INTEGER DEFAULT 0,

    -- Dates
    last_activity_date DATE,
    streak_start_date DATE,

    -- Shields
    shields_available INTEGER DEFAULT 0,
    shields_used_this_week INTEGER DEFAULT 0,
    last_shield_used_date DATE,

    -- Recovery
    recovery_available BOOLEAN DEFAULT false,
    recovery_deadline TIMESTAMPTZ,
    broken_streak_count INTEGER, -- What the streak was before breaking

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_id, streak_type)
);

-- ============================================================================
-- USER SEASON PROGRESS
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_season_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    season_id UUID NOT NULL REFERENCES seasons(id),

    -- Progress
    season_xp INTEGER DEFAULT 0,
    season_level INTEGER DEFAULT 1,

    -- Track
    has_premium_pass BOOLEAN DEFAULT false,

    -- Claimed rewards
    free_rewards_claimed INTEGER[] DEFAULT '{}',
    premium_rewards_claimed INTEGER[] DEFAULT '{}',

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_id, season_id)
);

-- ============================================================================
-- COLLECTIBLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS collectibles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    slug TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    description TEXT,

    type TEXT NOT NULL CHECK (type IN (
        'avatar_item', 'theme', 'buddy', 'card', 'frame', 'effect'
    )),

    -- Visual
    preview_url TEXT,
    asset_url TEXT,

    -- Rarity
    rarity TEXT DEFAULT 'common' CHECK (rarity IN (
        'common', 'uncommon', 'rare', 'epic', 'legendary'
    )),

    -- Acquisition
    acquisition_type TEXT NOT NULL CHECK (acquisition_type IN (
        'badge', 'level', 'season', 'purchase', 'event', 'gift'
    )),
    acquisition_config JSONB,

    -- Stats
    total_owners INTEGER DEFAULT 0,

    is_tradeable BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User collectibles
CREATE TABLE IF NOT EXISTS user_collectibles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    collectible_id UUID NOT NULL REFERENCES collectibles(id),

    acquired_at TIMESTAMPTZ DEFAULT NOW(),
    acquisition_source TEXT,

    -- Equipped status
    is_equipped BOOLEAN DEFAULT false,

    UNIQUE(user_id, collectible_id)
);

-- ============================================================================
-- ACHIEVEMENT REACTIONS (Social)
-- ============================================================================

CREATE TABLE IF NOT EXISTS achievement_reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Who earned the achievement
    user_badge_id UUID NOT NULL REFERENCES user_badges_v2(id) ON DELETE CASCADE,

    -- Who reacted
    reactor_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Reaction
    reaction_type TEXT NOT NULL, -- 'celebrate', 'fire', 'heart', 'star', 'wow'

    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_badge_id, reactor_user_id)
);

-- ============================================================================
-- WEEKLY CHALLENGES
-- ============================================================================

CREATE TABLE IF NOT EXISTS weekly_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    week_start DATE NOT NULL,

    title TEXT NOT NULL,
    description TEXT,

    -- Requirements
    challenge_type TEXT NOT NULL,
    target_value INTEGER NOT NULL,

    -- Rewards
    xp_reward INTEGER DEFAULT 0,
    badge_reward_id UUID REFERENCES badges_v2(id),

    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User challenge progress
CREATE TABLE IF NOT EXISTS user_challenge_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    challenge_id UUID NOT NULL REFERENCES weekly_challenges(id),

    current_progress INTEGER DEFAULT 0,
    completed_at TIMESTAMPTZ,
    reward_claimed BOOLEAN DEFAULT false,

    UNIQUE(user_id, challenge_id)
);

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE badges_v2 ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_badges_v2 ENABLE ROW LEVEL SECURITY;
ALTER TABLE skill_trees ENABLE ROW LEVEL SECURITY;
ALTER TABLE skill_tree_nodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_skill_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_experience ENABLE ROW LEVEL SECURITY;
ALTER TABLE xp_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_streaks_v2 ENABLE ROW LEVEL SECURITY;
ALTER TABLE seasons ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_season_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE collectibles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_collectibles ENABLE ROW LEVEL SECURITY;
ALTER TABLE achievement_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE weekly_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_challenge_progress ENABLE ROW LEVEL SECURITY;

-- Public read for definitions (wrap in DO blocks for idempotency)
DO $$ BEGIN
    CREATE POLICY "Public read badges" ON badges_v2 FOR SELECT USING (is_active = true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE POLICY "Public read skill trees" ON skill_trees FOR SELECT USING (is_active = true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE POLICY "Public read skill nodes" ON skill_tree_nodes FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE POLICY "Public read seasons" ON seasons FOR SELECT USING (is_active = true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE POLICY "Public read collectibles" ON collectibles FOR SELECT USING (is_active = true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE POLICY "Public read challenges" ON weekly_challenges FOR SELECT USING (is_active = true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- User data isolation
DO $$ BEGIN
    CREATE POLICY "Users manage own badges" ON user_badges_v2 FOR ALL USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE POLICY "Users manage own skills" ON user_skill_progress FOR ALL USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE POLICY "Users manage own xp" ON user_experience FOR ALL USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE POLICY "Users see own transactions" ON xp_transactions FOR SELECT USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE POLICY "Users manage own streaks" ON user_streaks_v2 FOR ALL USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE POLICY "Users manage own season progress" ON user_season_progress FOR ALL USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE POLICY "Users manage own collectibles" ON user_collectibles FOR ALL USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE POLICY "Users manage own challenges" ON user_challenge_progress FOR ALL USING (auth.uid() = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Reactions are readable by all authenticated users and can be created by anyone
DO $$ BEGIN
    CREATE POLICY "Read achievement reactions" ON achievement_reactions FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE POLICY "Create achievement reactions" ON achievement_reactions
        FOR INSERT WITH CHECK (auth.uid() = reactor_user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to calculate level from XP
CREATE OR REPLACE FUNCTION calculate_level(total_xp INTEGER)
RETURNS INTEGER AS $$
BEGIN
    -- Level formula: level = floor(sqrt(total_xp / 50)) + 1
    -- Requires progressively more XP per level
    RETURN GREATEST(1, FLOOR(SQRT(total_xp::NUMERIC / 50)) + 1);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to calculate XP needed for next level
CREATE OR REPLACE FUNCTION xp_for_level(level INTEGER)
RETURNS INTEGER AS $$
BEGIN
    -- XP needed = 50 * (level^2 - (level-1)^2)
    RETURN 50 * (level * level - (level - 1) * (level - 1));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to get total XP required to reach a level
CREATE OR REPLACE FUNCTION total_xp_for_level(level INTEGER)
RETURNS INTEGER AS $$
BEGIN
    -- Total XP = 50 * (level-1)^2
    RETURN 50 * (level - 1) * (level - 1);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Trigger to update badge earner count
CREATE OR REPLACE FUNCTION update_badge_earner_count()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_earned AND (OLD IS NULL OR NOT OLD.is_earned) THEN
        UPDATE badges_v2 SET total_earners = total_earners + 1
        WHERE id = NEW.badge_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_update_badge_earners ON user_badges_v2;
CREATE TRIGGER trigger_update_badge_earners
    AFTER INSERT OR UPDATE ON user_badges_v2
    FOR EACH ROW
    EXECUTE FUNCTION update_badge_earner_count();

-- Trigger to update collectible owner count
CREATE OR REPLACE FUNCTION update_collectible_owner_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE collectibles SET total_owners = total_owners + 1
        WHERE id = NEW.collectible_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE collectibles SET total_owners = GREATEST(0, total_owners - 1)
        WHERE id = OLD.collectible_id;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_update_collectible_owners ON user_collectibles;
CREATE TRIGGER trigger_update_collectible_owners
    AFTER INSERT OR DELETE ON user_collectibles
    FOR EACH ROW
    EXECUTE FUNCTION update_collectible_owner_count();

-- ============================================================================
-- RPC FUNCTIONS
-- ============================================================================

-- Increment season XP (called by award-xp function)
CREATE OR REPLACE FUNCTION increment_season_xp(
    p_user_id UUID,
    p_season_id UUID,
    p_xp_amount INTEGER
)
RETURNS VOID AS $$
DECLARE
    v_current_xp INTEGER;
    v_new_level INTEGER;
BEGIN
    -- Upsert progress record
    INSERT INTO user_season_progress (user_id, season_id, season_xp, season_level)
    VALUES (p_user_id, p_season_id, p_xp_amount, 1)
    ON CONFLICT (user_id, season_id)
    DO UPDATE SET
        season_xp = user_season_progress.season_xp + p_xp_amount,
        updated_at = NOW();

    -- Get new totals and calculate level
    SELECT season_xp INTO v_current_xp
    FROM user_season_progress
    WHERE user_id = p_user_id AND season_id = p_season_id;

    v_new_level := calculate_level(v_current_xp);

    -- Update level if changed
    UPDATE user_season_progress
    SET season_level = v_new_level
    WHERE user_id = p_user_id AND season_id = p_season_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Increment skill tree XP
CREATE OR REPLACE FUNCTION increment_skill_xp(
    p_user_id UUID,
    p_tree_id UUID,
    p_xp_amount INTEGER
)
RETURNS VOID AS $$
DECLARE
    v_current_xp INTEGER;
    v_total_xp INTEGER;
    v_new_level INTEGER;
    v_max_level INTEGER;
BEGIN
    -- Get max level for this tree
    SELECT max_level INTO v_max_level FROM skill_trees WHERE id = p_tree_id;

    -- Upsert progress record
    INSERT INTO user_skill_progress (user_id, tree_id, current_xp, total_xp, current_level)
    VALUES (p_user_id, p_tree_id, p_xp_amount, p_xp_amount, 1)
    ON CONFLICT (user_id, tree_id)
    DO UPDATE SET
        current_xp = user_skill_progress.current_xp + p_xp_amount,
        total_xp = user_skill_progress.total_xp + p_xp_amount,
        updated_at = NOW();

    -- Get new totals and calculate level
    SELECT total_xp INTO v_total_xp
    FROM user_skill_progress
    WHERE user_id = p_user_id AND tree_id = p_tree_id;

    v_new_level := LEAST(calculate_level(v_total_xp), v_max_level);

    -- Update level if changed
    UPDATE user_skill_progress
    SET current_level = v_new_level
    WHERE user_id = p_user_id AND tree_id = p_tree_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- SEED DATA: 5 SKILL TREES
-- ============================================================================

INSERT INTO skill_trees (slug, name, description, icon_url, color, max_level) VALUES
    ('mindfulness', 'Mindfulness', 'Master the art of present moment awareness', '/icons/skill-trees/mindfulness.svg', '#7C3AED', 10),
    ('resilience', 'Resilience', 'Build strength through challenges', '/icons/skill-trees/resilience.svg', '#059669', 10),
    ('connection', 'Connection', 'Deepen your relationships with others', '/icons/skill-trees/connection.svg', '#EC4899', 10),
    ('self_care', 'Self-Care', 'Nurture your body and mind', '/icons/skill-trees/self-care.svg', '#F59E0B', 10),
    ('growth', 'Growth', 'Expand your comfort zone', '/icons/skill-trees/growth.svg', '#3B82F6', 10)
ON CONFLICT (slug) DO NOTHING;

-- ============================================================================
-- SEED DATA: BADGES (100+ badges across categories)
-- ============================================================================

-- Getting Started badges (5)
INSERT INTO badges_v2 (slug, name, description, icon_url, category, requirement_type, requirement_config, rarity, xp_reward, sort_order) VALUES
    ('first_quest', 'First Steps', 'Complete your first quest', '/badges/first-quest.svg', 'getting_started', 'count', '{"metric": "quests_completed", "target": 1}', 'common', 10, 1),
    ('first_mood', 'Mood Logger', 'Log your first mood', '/badges/first-mood.svg', 'getting_started', 'count', '{"metric": "moods_logged", "target": 1}', 'common', 10, 2),
    ('first_exercise', 'Moving Forward', 'Complete your first exercise', '/badges/first-exercise.svg', 'getting_started', 'count', '{"metric": "exercises_completed", "target": 1}', 'common', 10, 3),
    ('first_meditation', 'Inner Peace', 'Complete your first meditation', '/badges/first-meditation.svg', 'getting_started', 'count', '{"metric": "meditations_completed", "target": 1}', 'common', 10, 4),
    ('profile_complete', 'All Set', 'Complete your profile setup', '/badges/profile-complete.svg', 'getting_started', 'manual', '{"trigger": "profile_complete"}', 'common', 25, 5)
ON CONFLICT (slug) DO NOTHING;

-- Quest Milestone badges (Bronze -> Silver -> Gold -> Diamond tiers)
INSERT INTO badges_v2 (slug, name, description, icon_url, category, tier, tier_order, requirement_type, requirement_config, rarity, xp_reward, sort_order) VALUES
    ('quests_10', 'Quest Explorer', 'Complete 10 quests', '/badges/quests-bronze.svg', 'quests', 'bronze', 1, 'count', '{"metric": "quests_completed", "target": 10}', 'common', 25, 10),
    ('quests_25', 'Quest Achiever', 'Complete 25 quests', '/badges/quests-silver.svg', 'quests', 'silver', 2, 'count', '{"metric": "quests_completed", "target": 25}', 'uncommon', 50, 11),
    ('quests_50', 'Quest Champion', 'Complete 50 quests', '/badges/quests-gold.svg', 'quests', 'gold', 3, 'count', '{"metric": "quests_completed", "target": 50}', 'rare', 100, 12),
    ('quests_100', 'Quest Master', 'Complete 100 quests', '/badges/quests-diamond.svg', 'quests', 'diamond', 4, 'count', '{"metric": "quests_completed", "target": 100}', 'epic', 250, 13),
    ('quests_250', 'Quest Legend', 'Complete 250 quests', '/badges/quests-legendary.svg', 'quests', 'legendary', 5, 'count', '{"metric": "quests_completed", "target": 250}', 'legendary', 500, 14)
ON CONFLICT (slug) DO NOTHING;

-- Streak badges
INSERT INTO badges_v2 (slug, name, description, icon_url, category, tier, tier_order, requirement_type, requirement_config, rarity, xp_reward, sort_order) VALUES
    ('streak_7', 'Week Warrior', '7-day streak', '/badges/streak-7.svg', 'streaks', 'bronze', 1, 'streak', '{"streak_type": "quest", "target": 7}', 'common', 50, 20),
    ('streak_14', 'Fortnight Force', '14-day streak', '/badges/streak-14.svg', 'streaks', 'silver', 2, 'streak', '{"streak_type": "quest", "target": 14}', 'uncommon', 100, 21),
    ('streak_30', 'Monthly Master', '30-day streak', '/badges/streak-30.svg', 'streaks', 'gold', 3, 'streak', '{"streak_type": "quest", "target": 30}', 'rare', 200, 22),
    ('streak_60', 'Double Down', '60-day streak', '/badges/streak-60.svg', 'streaks', 'diamond', 4, 'streak', '{"streak_type": "quest", "target": 60}', 'epic', 400, 23),
    ('streak_100', 'Century Club', '100-day streak', '/badges/streak-100.svg', 'streaks', 'legendary', 5, 'streak', '{"streak_type": "quest", "target": 100}', 'legendary', 1000, 24),
    ('streak_365', 'Year of Growth', '365-day streak', '/badges/streak-365.svg', 'streaks', 'legendary', 5, 'streak', '{"streak_type": "quest", "target": 365}', 'legendary', 5000, 25)
ON CONFLICT (slug) DO NOTHING;

-- Exercise badges
INSERT INTO badges_v2 (slug, name, description, icon_url, category, tier, tier_order, requirement_type, requirement_config, rarity, xp_reward, sort_order) VALUES
    ('exercises_10', 'Active Mind', 'Complete 10 exercises', '/badges/exercise-bronze.svg', 'exercises', 'bronze', 1, 'count', '{"metric": "exercises_completed", "target": 10}', 'common', 25, 30),
    ('exercises_25', 'Wellness Warrior', 'Complete 25 exercises', '/badges/exercise-silver.svg', 'exercises', 'silver', 2, 'count', '{"metric": "exercises_completed", "target": 25}', 'uncommon', 50, 31),
    ('exercises_50', 'Fitness Fanatic', 'Complete 50 exercises', '/badges/exercise-gold.svg', 'exercises', 'gold', 3, 'count', '{"metric": "exercises_completed", "target": 50}', 'rare', 100, 32),
    ('exercises_100', 'Exercise Expert', 'Complete 100 exercises', '/badges/exercise-diamond.svg', 'exercises', 'diamond', 4, 'count', '{"metric": "exercises_completed", "target": 100}', 'epic', 250, 33),
    ('breathing_master', 'Breath Master', 'Complete 20 breathing exercises', '/badges/breathing-master.svg', 'exercises', 'gold', 3, 'count', '{"metric": "exercises_completed", "target": 20, "filter": {"type": "breathing"}}', 'rare', 100, 34),
    ('grounding_guru', 'Grounding Guru', 'Complete 15 grounding exercises', '/badges/grounding-guru.svg', 'exercises', 'gold', 3, 'count', '{"metric": "exercises_completed", "target": 15, "filter": {"type": "grounding"}}', 'rare', 100, 35)
ON CONFLICT (slug) DO NOTHING;

-- Meditation badges
INSERT INTO badges_v2 (slug, name, description, icon_url, category, tier, tier_order, requirement_type, requirement_config, rarity, xp_reward, sort_order) VALUES
    ('meditation_10', 'Meditation Starter', 'Complete 10 meditations', '/badges/meditation-bronze.svg', 'meditation', 'bronze', 1, 'count', '{"metric": "meditations_completed", "target": 10}', 'common', 25, 40),
    ('meditation_25', 'Calm Seeker', 'Complete 25 meditations', '/badges/meditation-silver.svg', 'meditation', 'silver', 2, 'count', '{"metric": "meditations_completed", "target": 25}', 'uncommon', 50, 41),
    ('meditation_50', 'Mindful Maven', 'Complete 50 meditations', '/badges/meditation-gold.svg', 'meditation', 'gold', 3, 'count', '{"metric": "meditations_completed", "target": 50}', 'rare', 100, 42),
    ('meditation_100', 'Zen Master', 'Complete 100 meditations', '/badges/meditation-diamond.svg', 'meditation', 'diamond', 4, 'count', '{"metric": "meditations_completed", "target": 100}', 'epic', 250, 43),
    ('meditation_time_60', 'Hour of Peace', 'Meditate for 60 minutes total', '/badges/meditation-hour.svg', 'meditation', 'silver', 2, 'time', '{"metric": "meditation_time", "target": 3600}', 'uncommon', 75, 44),
    ('meditation_time_600', 'Ten Hours of Calm', 'Meditate for 10 hours total', '/badges/meditation-10hrs.svg', 'meditation', 'gold', 3, 'time', '{"metric": "meditation_time", "target": 36000}', 'rare', 200, 45)
ON CONFLICT (slug) DO NOTHING;

-- Mood logging badges
INSERT INTO badges_v2 (slug, name, description, icon_url, category, tier, tier_order, requirement_type, requirement_config, rarity, xp_reward, sort_order) VALUES
    ('moods_10', 'Self Aware', 'Log 10 moods', '/badges/mood-bronze.svg', 'mood', 'bronze', 1, 'count', '{"metric": "moods_logged", "target": 10}', 'common', 25, 50),
    ('moods_30', 'Mood Tracker', 'Log 30 moods', '/badges/mood-silver.svg', 'mood', 'silver', 2, 'count', '{"metric": "moods_logged", "target": 30}', 'uncommon', 50, 51),
    ('moods_100', 'Emotional Intelligence', 'Log 100 moods', '/badges/mood-gold.svg', 'mood', 'gold', 3, 'count', '{"metric": "moods_logged", "target": 100}', 'rare', 100, 52),
    ('moods_365', 'Year in Review', 'Log 365 moods', '/badges/mood-diamond.svg', 'mood', 'diamond', 4, 'count', '{"metric": "moods_logged", "target": 365}', 'epic', 500, 53)
ON CONFLICT (slug) DO NOTHING;

-- Circle/Social badges
INSERT INTO badges_v2 (slug, name, description, icon_url, category, tier, tier_order, requirement_type, requirement_config, rarity, xp_reward, sort_order) VALUES
    ('first_circle', 'Circle Joiner', 'Join your first circle', '/badges/circle-join.svg', 'circles', 'bronze', 1, 'count', '{"metric": "circles_joined", "target": 1}', 'common', 25, 60),
    ('circle_posts_10', 'Community Voice', 'Post 10 circle check-ins', '/badges/circle-posts-bronze.svg', 'circles', 'bronze', 1, 'count', '{"metric": "circle_posts", "target": 10}', 'common', 25, 61),
    ('circle_posts_50', 'Circle Leader', 'Post 50 circle check-ins', '/badges/circle-posts-gold.svg', 'circles', 'gold', 3, 'count', '{"metric": "circle_posts", "target": 50}', 'rare', 100, 62),
    ('circle_creator', 'Circle Creator', 'Create a circle', '/badges/circle-create.svg', 'circles', 'silver', 2, 'manual', '{"trigger": "circle_created"}', 'uncommon', 50, 63)
ON CONFLICT (slug) DO NOTHING;

-- Level milestone badges
INSERT INTO badges_v2 (slug, name, description, icon_url, category, tier, tier_order, requirement_type, requirement_config, rarity, xp_reward, sort_order) VALUES
    ('level_5', 'Rising Star', 'Reach Level 5', '/badges/level-5.svg', 'special', 'bronze', 1, 'count', '{"metric": "user_level", "target": 5}', 'common', 50, 70),
    ('level_10', 'Explorer', 'Reach Level 10', '/badges/level-10.svg', 'special', 'silver', 2, 'count', '{"metric": "user_level", "target": 10}', 'uncommon', 100, 71),
    ('level_25', 'Adept', 'Reach Level 25', '/badges/level-25.svg', 'special', 'gold', 3, 'count', '{"metric": "user_level", "target": 25}', 'rare', 250, 72),
    ('level_50', 'Master', 'Reach Level 50', '/badges/level-50.svg', 'special', 'diamond', 4, 'count', '{"metric": "user_level", "target": 50}', 'epic', 500, 73),
    ('level_100', 'Legend', 'Reach Level 100', '/badges/level-100.svg', 'special', 'legendary', 5, 'count', '{"metric": "user_level", "target": 100}', 'legendary', 1000, 74)
ON CONFLICT (slug) DO NOTHING;

-- Secret/Special badges
INSERT INTO badges_v2 (slug, name, description, icon_url, category, requirement_type, requirement_config, rarity, is_secret, reveal_hint, xp_reward, sort_order) VALUES
    ('night_owl', 'Night Owl', 'Complete an activity after midnight', '/badges/night-owl.svg', 'special', 'manual', '{"trigger": "activity_after_midnight"}', 'rare', true, 'The quiet hours hold secrets...', 100, 80),
    ('early_bird', 'Early Bird', 'Complete an activity before 6am', '/badges/early-bird.svg', 'special', 'manual', '{"trigger": "activity_before_6am"}', 'rare', true, 'The early bird catches the badge!', 100, 81),
    ('perfect_week', 'Perfect Week', 'Complete all quests in a week', '/badges/perfect-week.svg', 'special', 'manual', '{"trigger": "perfect_week"}', 'epic', true, 'Consistency is key...', 250, 82),
    ('comeback_kid', 'Comeback Kid', 'Return after 7+ days away', '/badges/comeback.svg', 'special', 'manual', '{"trigger": "returned_after_7_days"}', 'uncommon', true, 'Sometimes we all need a break', 75, 83),
    ('founding_member', 'Founding Member', 'Joined during launch week', '/badges/founding-member.svg', 'special', 'manual', '{"trigger": "founding_member"}', 'legendary', false, NULL, 500, 84)
ON CONFLICT (slug) DO NOTHING;

-- ============================================================================
-- SEED DATA: SKILL TREE NODES (sample nodes for each tree)
-- ============================================================================

-- Mindfulness Tree Nodes
INSERT INTO skill_tree_nodes (tree_id, slug, name, description, tier, position, unlock_type, unlock_config, xp_reward) VALUES
    ((SELECT id FROM skill_trees WHERE slug = 'mindfulness'), 'breath_awareness', 'Breath Awareness', 'Learn to focus on your breath', 1, 1, 'xp', '{"xp_required": 0}', 25),
    ((SELECT id FROM skill_trees WHERE slug = 'mindfulness'), 'body_scan', 'Body Scan', 'Develop body awareness', 1, 2, 'xp', '{"xp_required": 100}', 50),
    ((SELECT id FROM skill_trees WHERE slug = 'mindfulness'), 'present_moment', 'Present Moment', 'Stay grounded in the now', 2, 1, 'xp', '{"xp_required": 300}', 75),
    ((SELECT id FROM skill_trees WHERE slug = 'mindfulness'), 'thought_observer', 'Thought Observer', 'Watch thoughts without judgment', 2, 2, 'xp', '{"xp_required": 500}', 100),
    ((SELECT id FROM skill_trees WHERE slug = 'mindfulness'), 'mindful_master', 'Mindful Master', 'Achieve mindfulness mastery', 3, 1, 'xp', '{"xp_required": 1000}', 250)
ON CONFLICT (tree_id, slug) DO NOTHING;

-- Resilience Tree Nodes
INSERT INTO skill_tree_nodes (tree_id, slug, name, description, tier, position, unlock_type, unlock_config, xp_reward) VALUES
    ((SELECT id FROM skill_trees WHERE slug = 'resilience'), 'bounce_back', 'Bounce Back', 'Learn to recover from setbacks', 1, 1, 'xp', '{"xp_required": 0}', 25),
    ((SELECT id FROM skill_trees WHERE slug = 'resilience'), 'stress_shield', 'Stress Shield', 'Build defenses against stress', 1, 2, 'xp', '{"xp_required": 100}', 50),
    ((SELECT id FROM skill_trees WHERE slug = 'resilience'), 'growth_mindset', 'Growth Mindset', 'Embrace challenges as opportunities', 2, 1, 'xp', '{"xp_required": 300}', 75),
    ((SELECT id FROM skill_trees WHERE slug = 'resilience'), 'inner_strength', 'Inner Strength', 'Discover your core resilience', 2, 2, 'xp', '{"xp_required": 500}', 100),
    ((SELECT id FROM skill_trees WHERE slug = 'resilience'), 'unshakeable', 'Unshakeable', 'Achieve ultimate resilience', 3, 1, 'xp', '{"xp_required": 1000}', 250)
ON CONFLICT (tree_id, slug) DO NOTHING;

-- Connection Tree Nodes
INSERT INTO skill_tree_nodes (tree_id, slug, name, description, tier, position, unlock_type, unlock_config, xp_reward) VALUES
    ((SELECT id FROM skill_trees WHERE slug = 'connection'), 'open_heart', 'Open Heart', 'Open yourself to connection', 1, 1, 'xp', '{"xp_required": 0}', 25),
    ((SELECT id FROM skill_trees WHERE slug = 'connection'), 'active_listener', 'Active Listener', 'Learn deep listening skills', 1, 2, 'xp', '{"xp_required": 100}', 50),
    ((SELECT id FROM skill_trees WHERE slug = 'connection'), 'empathy_bridge', 'Empathy Bridge', 'Build bridges through empathy', 2, 1, 'xp', '{"xp_required": 300}', 75),
    ((SELECT id FROM skill_trees WHERE slug = 'connection'), 'authentic_self', 'Authentic Self', 'Show up as your true self', 2, 2, 'xp', '{"xp_required": 500}', 100),
    ((SELECT id FROM skill_trees WHERE slug = 'connection'), 'connection_catalyst', 'Connection Catalyst', 'Master meaningful relationships', 3, 1, 'xp', '{"xp_required": 1000}', 250)
ON CONFLICT (tree_id, slug) DO NOTHING;

-- Self-Care Tree Nodes
INSERT INTO skill_tree_nodes (tree_id, slug, name, description, tier, position, unlock_type, unlock_config, xp_reward) VALUES
    ((SELECT id FROM skill_trees WHERE slug = 'self_care'), 'basic_needs', 'Basic Needs', 'Honor your fundamental needs', 1, 1, 'xp', '{"xp_required": 0}', 25),
    ((SELECT id FROM skill_trees WHERE slug = 'self_care'), 'rest_ritual', 'Rest Ritual', 'Develop healthy rest habits', 1, 2, 'xp', '{"xp_required": 100}', 50),
    ((SELECT id FROM skill_trees WHERE slug = 'self_care'), 'boundary_setter', 'Boundary Setter', 'Learn to set healthy boundaries', 2, 1, 'xp', '{"xp_required": 300}', 75),
    ((SELECT id FROM skill_trees WHERE slug = 'self_care'), 'joy_finder', 'Joy Finder', 'Discover sources of daily joy', 2, 2, 'xp', '{"xp_required": 500}', 100),
    ((SELECT id FROM skill_trees WHERE slug = 'self_care'), 'self_love_champion', 'Self-Love Champion', 'Master self-compassion', 3, 1, 'xp', '{"xp_required": 1000}', 250)
ON CONFLICT (tree_id, slug) DO NOTHING;

-- Growth Tree Nodes
INSERT INTO skill_tree_nodes (tree_id, slug, name, description, tier, position, unlock_type, unlock_config, xp_reward) VALUES
    ((SELECT id FROM skill_trees WHERE slug = 'growth'), 'comfort_edge', 'Comfort Edge', 'Explore your comfort zone edges', 1, 1, 'xp', '{"xp_required": 0}', 25),
    ((SELECT id FROM skill_trees WHERE slug = 'growth'), 'fear_friend', 'Fear Friend', 'Make friends with fear', 1, 2, 'xp', '{"xp_required": 100}', 50),
    ((SELECT id FROM skill_trees WHERE slug = 'growth'), 'habit_hacker', 'Habit Hacker', 'Master the science of habits', 2, 1, 'xp', '{"xp_required": 300}', 75),
    ((SELECT id FROM skill_trees WHERE slug = 'growth'), 'goal_getter', 'Goal Getter', 'Set and achieve meaningful goals', 2, 2, 'xp', '{"xp_required": 500}', 100),
    ((SELECT id FROM skill_trees WHERE slug = 'growth'), 'limitless', 'Limitless', 'Transcend perceived limitations', 3, 1, 'xp', '{"xp_required": 1000}', 250)
ON CONFLICT (tree_id, slug) DO NOTHING;
