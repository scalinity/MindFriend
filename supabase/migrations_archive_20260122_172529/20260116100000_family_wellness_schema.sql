-- Spec 11: Family Wellness - Database Schema
-- Extends existing family tables and creates 10 new tables for family wellness features

-- =============================================================================
-- MARK: - Create base family tables if they don't exist
-- =============================================================================

-- Create family_groups base table if it doesn't exist
CREATE TABLE IF NOT EXISTS family_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT DEFAULT 'My Family',
  admin_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  circle_id UUID REFERENCES circles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_family_groups_admin ON family_groups(admin_user_id);
ALTER TABLE family_groups ENABLE ROW LEVEL SECURITY;

-- Create family_members base table if it doesn't exist
CREATE TABLE IF NOT EXISTS family_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES family_groups(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT unique_family_member UNIQUE (family_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_family_members_family ON family_members(family_id);
CREATE INDEX IF NOT EXISTS idx_family_members_user ON family_members(user_id);
ALTER TABLE family_members ENABLE ROW LEVEL SECURITY;

-- Create family_invitations base table if it doesn't exist
CREATE TABLE IF NOT EXISTS family_invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES family_groups(id) ON DELETE CASCADE,
  inviter_id UUID NOT NULL REFERENCES auth.users(id),
  invitee_email TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_family_invitations_family ON family_invitations(family_id);
ALTER TABLE family_invitations ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- MARK: - Extend existing family_groups table
-- =============================================================================

ALTER TABLE family_groups ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE family_groups ADD COLUMN IF NOT EXISTS invite_code TEXT UNIQUE;
ALTER TABLE family_groups ADD COLUMN IF NOT EXISTS default_child_age_filter INTEGER DEFAULT 12;
ALTER TABLE family_groups ADD COLUMN IF NOT EXISTS require_parent_approval_for_content BOOLEAN DEFAULT false;
ALTER TABLE family_groups ADD COLUMN IF NOT EXISTS share_activity_by_default BOOLEAN DEFAULT true;
ALTER TABLE family_groups ADD COLUMN IF NOT EXISTS max_members INTEGER DEFAULT 6;

-- Generate invite codes for existing groups without one
UPDATE family_groups
SET invite_code = 'LEGACY' || SUBSTR(MD5(CAST(id AS TEXT)), 1, 8)
WHERE invite_code IS NULL;

-- =============================================================================
-- MARK: - Extend existing family_members table
-- =============================================================================

ALTER TABLE family_members ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';
ALTER TABLE family_members ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'child';
ALTER TABLE family_members ADD COLUMN IF NOT EXISTS nickname TEXT;
ALTER TABLE family_members ADD COLUMN IF NOT EXISTS avatar_emoji TEXT;
ALTER TABLE family_members ADD COLUMN IF NOT EXISTS birth_date DATE;
ALTER TABLE family_members ADD COLUMN IF NOT EXISTS age_filter_override INTEGER;
ALTER TABLE family_members ADD COLUMN IF NOT EXISTS share_mood_with_family BOOLEAN DEFAULT true;
ALTER TABLE family_members ADD COLUMN IF NOT EXISTS share_activity_with_family BOOLEAN DEFAULT true;
ALTER TABLE family_members ADD COLUMN IF NOT EXISTS share_achievements_with_family BOOLEAN DEFAULT true;
ALTER TABLE family_members ADD COLUMN IF NOT EXISTS invited_by UUID REFERENCES auth.users(id);

-- Add status constraint
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'valid_family_member_status') THEN
    ALTER TABLE family_members ADD CONSTRAINT valid_family_member_status
      CHECK (status IN ('active', 'inactive', 'removed'));
  END IF;
END $$;

-- Add role constraint
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'valid_family_role') THEN
    ALTER TABLE family_members ADD CONSTRAINT valid_family_role
      CHECK (role IN ('admin', 'parent', 'teen', 'child'));
  END IF;
END $$;

-- Set existing admins to admin role based on family_groups.admin_user_id
UPDATE family_members fm
SET role = 'admin'
FROM family_groups fg
WHERE fm.family_id = fg.id
  AND fm.user_id = fg.admin_user_id
  AND fm.role = 'child';

-- =============================================================================
-- MARK: - Extend existing family_invitations table
-- =============================================================================

ALTER TABLE family_invitations ADD COLUMN IF NOT EXISTS intended_role TEXT DEFAULT 'child';
ALTER TABLE family_invitations ADD COLUMN IF NOT EXISTS intended_birth_date DATE;
ALTER TABLE family_invitations ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending';

-- Add status constraint
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'valid_invitation_status') THEN
    ALTER TABLE family_invitations ADD CONSTRAINT valid_invitation_status
      CHECK (status IN ('pending', 'accepted', 'declined', 'expired'));
  END IF;
END $$;

-- =============================================================================
-- MARK: - Helper Functions for Wellness Features
-- =============================================================================

-- Function to generate random invite codes (alphanumeric, 8 chars, no vowels to avoid confusion)
CREATE OR REPLACE FUNCTION generate_invite_code()
RETURNS TEXT AS $$
DECLARE
    chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    result TEXT := '';
    i INTEGER;
BEGIN
    FOR i IN 1..8 LOOP
        result := result || substr(chars, floor(random() * length(chars) + 1)::integer, 1);
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate age from birth date
CREATE OR REPLACE FUNCTION calculate_age(birth_date DATE)
RETURNS INTEGER AS $$
BEGIN
    RETURN EXTRACT(YEAR FROM age(CURRENT_DATE, birth_date))::INTEGER;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Function to get effective age filter for a member (handles override)
CREATE OR REPLACE FUNCTION get_effective_age_filter(member_id UUID)
RETURNS INTEGER AS $$
DECLARE
    member_record RECORD;
    calculated_age INTEGER;
BEGIN
    SELECT * INTO member_record FROM family_members WHERE id = member_id;

    IF member_record.birth_date IS NOT NULL THEN
        calculated_age := calculate_age(member_record.birth_date);
    ELSE
        calculated_age := 18; -- Default to adult if no birth date
    END IF;

    -- Use override if set and higher than calculated age
    IF member_record.age_filter_override IS NOT NULL AND
       member_record.age_filter_override > calculated_age THEN
        RETURN member_record.age_filter_override;
    END IF;

    RETURN calculated_age;
END;
$$ LANGUAGE plpgsql STABLE;

-- =============================================================================
-- MARK: - Family Challenges (New Table)
-- =============================================================================

CREATE TABLE IF NOT EXISTS family_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id UUID NOT NULL REFERENCES family_groups(id) ON DELETE CASCADE,

    -- Challenge details
    title TEXT NOT NULL,
    description TEXT,
    challenge_type TEXT NOT NULL CHECK (challenge_type IN ('streak', 'cumulative', 'event', 'custom')),

    -- Goals
    target_value INTEGER NOT NULL,
    minimum_participants INTEGER DEFAULT 1,

    -- Timing
    start_date DATE NOT NULL,
    end_date DATE,

    -- Rules
    requires_all_members BOOLEAN DEFAULT false,
    allow_makeup_activities BOOLEAN DEFAULT true,

    -- Status
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'completed', 'failed', 'cancelled')),
    current_progress INTEGER DEFAULT 0,

    -- Rewards
    badge_id UUID REFERENCES badges(id),
    reward_description TEXT,

    created_by UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_family_challenges_family ON family_challenges(family_id);
CREATE INDEX idx_family_challenges_status ON family_challenges(family_id, status);

-- =============================================================================
-- MARK: - Family Challenge Templates (New Table)
-- =============================================================================

CREATE TABLE IF NOT EXISTS family_challenge_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    title TEXT NOT NULL,
    description TEXT NOT NULL,
    challenge_type TEXT NOT NULL CHECK (challenge_type IN ('streak', 'cumulative', 'event', 'custom')),
    target_value INTEGER NOT NULL,
    suggested_duration_days INTEGER,

    -- Content
    icon_name TEXT,
    category TEXT NOT NULL CHECK (category IN ('meditation', 'gratitude', 'movement', 'connection')),
    difficulty TEXT DEFAULT 'medium' CHECK (difficulty IN ('easy', 'medium', 'hard')),

    -- Restrictions
    minimum_age INTEGER DEFAULT 4,
    requires_premium BOOLEAN DEFAULT false,

    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- MARK: - Family Challenge Participation (New Table)
-- =============================================================================

CREATE TABLE IF NOT EXISTS family_challenge_participation (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenge_id UUID NOT NULL REFERENCES family_challenges(id) ON DELETE CASCADE,
    member_id UUID NOT NULL REFERENCES family_members(id) ON DELETE CASCADE,

    -- Progress
    contribution_count INTEGER DEFAULT 0,
    last_contribution_at TIMESTAMPTZ,

    -- Daily tracking (for streaks)
    contribution_dates DATE[] DEFAULT ARRAY[]::DATE[],

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_challenge_participation UNIQUE (challenge_id, member_id)
);

CREATE INDEX idx_family_challenge_participation_challenge ON family_challenge_participation(challenge_id);
CREATE INDEX idx_family_challenge_participation_member ON family_challenge_participation(member_id);

-- =============================================================================
-- MARK: - Together Templates (New Table)
-- =============================================================================

CREATE TABLE IF NOT EXISTS together_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    title TEXT NOT NULL,
    description TEXT,
    category TEXT NOT NULL CHECK (category IN ('meditation', 'gratitude', 'breathing', 'checkin', 'movement')),

    -- Content
    content_type TEXT NOT NULL CHECK (content_type IN ('guided_audio', 'interactive', 'round_robin')),
    duration_minutes INTEGER NOT NULL,
    audio_url TEXT,

    -- Participants
    minimum_participants INTEGER DEFAULT 2,
    maximum_participants INTEGER DEFAULT 10,
    minimum_age INTEGER DEFAULT 4,

    -- Configuration (JSON for flexibility)
    configuration JSONB DEFAULT '{}',

    is_active BOOLEAN DEFAULT true,
    is_premium BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- MARK: - Together Sessions (New Table)
-- =============================================================================

CREATE TABLE IF NOT EXISTS together_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id UUID NOT NULL REFERENCES family_groups(id) ON DELETE CASCADE,

    -- Content
    exercise_id UUID REFERENCES exercises(id),
    together_template_id UUID REFERENCES together_templates(id),
    title TEXT NOT NULL,

    -- Timing
    scheduled_for TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    duration_seconds INTEGER,

    -- Participation
    minimum_participants INTEGER DEFAULT 2,

    -- Status
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'cancelled')),
    sync_mode TEXT DEFAULT 'realtime' CHECK (sync_mode IN ('realtime', 'async_window')),
    async_window_hours INTEGER DEFAULT 24,

    created_by UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_together_sessions_family ON together_sessions(family_id);
CREATE INDEX idx_together_sessions_status ON together_sessions(family_id, status);

-- =============================================================================
-- MARK: - Together Participants (New Table)
-- =============================================================================

CREATE TABLE IF NOT EXISTS together_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES together_sessions(id) ON DELETE CASCADE,
    member_id UUID NOT NULL REFERENCES family_members(id) ON DELETE CASCADE,

    -- Status
    status TEXT DEFAULT 'invited' CHECK (status IN ('invited', 'joined', 'completed', 'declined')),
    joined_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,

    -- For round-robin activities
    turn_order INTEGER,
    turn_completed BOOLEAN DEFAULT false,
    contribution TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_session_participant UNIQUE (session_id, member_id)
);

CREATE INDEX idx_together_participants_session ON together_participants(session_id);
CREATE INDEX idx_together_participants_member ON together_participants(member_id);

-- =============================================================================
-- MARK: - Content Age Ratings (New Table)
-- =============================================================================

CREATE TABLE IF NOT EXISTS content_age_ratings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_type TEXT NOT NULL CHECK (content_type IN ('exercise', 'audio', 'micro_moment', 'together_template')),
    content_id UUID NOT NULL,

    -- Ratings
    minimum_age INTEGER NOT NULL DEFAULT 4,
    maximum_age INTEGER,
    rating_category TEXT NOT NULL CHECK (rating_category IN ('all_ages', 'kids', 'teen', 'adult')),

    -- Content flags
    contains_heavy_topics BOOLEAN DEFAULT false,
    requires_reading BOOLEAN DEFAULT false,
    complexity_level TEXT DEFAULT 'simple' CHECK (complexity_level IN ('simple', 'moderate', 'complex')),

    -- Review
    reviewed_by UUID REFERENCES auth.users(id),
    reviewed_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_content_age_rating UNIQUE (content_type, content_id)
);

CREATE INDEX IF NOT EXISTS idx_content_age_ratings_content ON content_age_ratings(content_type, content_id);

-- =============================================================================
-- MARK: - Family Activity Summaries (New Table - Denormalized for Performance)
-- =============================================================================

CREATE TABLE IF NOT EXISTS family_activity_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id UUID NOT NULL REFERENCES family_groups(id) ON DELETE CASCADE,
    member_id UUID NOT NULL REFERENCES family_members(id) ON DELETE CASCADE,

    -- Time period
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,

    -- Activity metrics
    sessions_completed INTEGER DEFAULT 0,
    total_duration_minutes INTEGER DEFAULT 0,
    streak_days INTEGER DEFAULT 0,

    -- Mood summary (aggregated, not individual)
    mood_trend TEXT CHECK (mood_trend IN ('improving', 'stable', 'declining')),
    average_mood_score DECIMAL(3,2),

    -- Achievements
    badges_earned INTEGER DEFAULT 0,
    challenges_contributed INTEGER DEFAULT 0,

    -- Engagement
    days_active INTEGER DEFAULT 0,
    most_used_category TEXT,

    calculated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_activity_summary UNIQUE (family_id, member_id, period_start)
);

CREATE INDEX idx_family_activity_summaries_member ON family_activity_summaries(member_id, period_start);

-- =============================================================================
-- MARK: - Family Alerts (New Table - For Parental Notifications)
-- =============================================================================

CREATE TABLE IF NOT EXISTS family_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id UUID NOT NULL REFERENCES family_groups(id) ON DELETE CASCADE,
    about_member_id UUID NOT NULL REFERENCES family_members(id) ON DELETE CASCADE,
    for_parent_id UUID NOT NULL REFERENCES auth.users(id),

    -- Alert details
    alert_type TEXT NOT NULL CHECK (alert_type IN ('mood_concern', 'inactivity', 'achievement', 'milestone')),
    severity TEXT DEFAULT 'info' CHECK (severity IN ('info', 'attention', 'concern')),
    title TEXT NOT NULL,
    message TEXT NOT NULL,

    -- Actionable
    action_type TEXT CHECK (action_type IN ('start_conversation', 'check_in', 'celebrate')),
    action_data JSONB,
    conversation_starters TEXT[],

    -- Status
    was_read BOOLEAN DEFAULT false,
    was_acted_upon BOOLEAN DEFAULT false,
    read_at TIMESTAMPTZ,

    expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '7 days',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_family_alerts_parent ON family_alerts(for_parent_id, was_read);

-- =============================================================================
-- MARK: - Family Screen Time (New Table - Optional ScreenTime Integration)
-- =============================================================================

CREATE TABLE IF NOT EXISTS family_screen_time (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL REFERENCES family_members(id) ON DELETE CASCADE,

    -- Date
    date DATE NOT NULL,

    -- Time tracking
    wellness_minutes INTEGER DEFAULT 0,
    total_app_minutes INTEGER DEFAULT 0,

    -- Limits
    daily_limit_minutes INTEGER,
    limit_reached BOOLEAN DEFAULT false,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_screen_time UNIQUE (member_id, date)
);

-- =============================================================================
-- MARK: - COPPA Parental Consent (New Table - For COPPA Compliance)
-- =============================================================================

CREATE TABLE IF NOT EXISTS parental_consents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    child_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    parent_user_id UUID NOT NULL REFERENCES auth.users(id),
    parent_email TEXT NOT NULL,

    -- Consent tracking
    consent_type TEXT NOT NULL CHECK (consent_type IN ('initial', 'annual_renewal')),
    verification_code TEXT,
    verified_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '1 year',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_child_consent UNIQUE (child_user_id, consent_type)
);

CREATE INDEX idx_parental_consents_child ON parental_consents(child_user_id);
CREATE INDEX idx_parental_consents_parent ON parental_consents(parent_user_id);
