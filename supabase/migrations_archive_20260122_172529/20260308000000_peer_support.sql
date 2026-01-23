-- Migration: Peer Support & Giving Back Feature
-- Adds listener training, support sessions, mentorships, and gratitude system

-- ============================================================================
-- LISTENER TRAINING AND CERTIFICATION
-- ============================================================================

-- Listeners table
CREATE TABLE IF NOT EXISTS listeners (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,

    -- Status
    status TEXT NOT NULL DEFAULT 'applicant', -- 'applicant', 'training', 'active', 'inactive', 'suspended'

    -- Training progress
    training_started_at TIMESTAMPTZ,
    training_completed_at TIMESTAMPTZ,
    certification_score INTEGER,
    certification_passed BOOLEAN,

    -- Specializations
    specializations TEXT[] NOT NULL DEFAULT '{}', -- 'anxiety', 'depression', 'grief', 'stress', etc.
    languages TEXT[] NOT NULL DEFAULT ARRAY['en'],

    -- Availability
    is_available BOOLEAN NOT NULL DEFAULT false,
    available_hours JSONB, -- {mon: [{start: "09:00", end: "17:00"}], ...}
    max_sessions_per_week INTEGER NOT NULL DEFAULT 5,

    -- Stats
    total_sessions INTEGER NOT NULL DEFAULT 0,
    total_hours DECIMAL(10,2) NOT NULL DEFAULT 0,
    average_rating DECIMAL(3,2),
    rating_count INTEGER NOT NULL DEFAULT 0,

    -- Settings
    accepts_voice_calls BOOLEAN NOT NULL DEFAULT false,
    accepts_crisis_bridge BOOLEAN NOT NULL DEFAULT false,
    bio TEXT,
    display_name TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_listener_user UNIQUE (user_id)
);

-- Training module progress
CREATE TABLE IF NOT EXISTS listener_training_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listener_id UUID NOT NULL REFERENCES listeners(id) ON DELETE CASCADE,
    module_id TEXT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    score INTEGER,
    attempts INTEGER NOT NULL DEFAULT 1,

    CONSTRAINT unique_module_progress UNIQUE (listener_id, module_id)
);

-- Listener availability slots
CREATE TABLE IF NOT EXISTS listener_availability (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listener_id UUID NOT NULL REFERENCES listeners(id) ON DELETE CASCADE,

    day_of_week INTEGER NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    timezone TEXT NOT NULL DEFAULT 'UTC',

    is_active BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT unique_availability_slot UNIQUE (listener_id, day_of_week, start_time)
);

-- ============================================================================
-- PEER SUPPORT SESSIONS
-- ============================================================================

-- Support sessions
CREATE TABLE IF NOT EXISTS support_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Participants
    seeker_id UUID NOT NULL REFERENCES profiles(id),
    listener_id UUID REFERENCES listeners(id),

    -- Session details
    session_type TEXT NOT NULL, -- 'quick', 'deep', 'crisis_bridge', 'group'
    status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'matched', 'active', 'completed', 'cancelled', 'escalated'

    -- Matching
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    matched_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,

    -- Context (for matching)
    topic_tags TEXT[],
    seeker_mood_before INTEGER,
    seeker_notes TEXT, -- What they want to talk about

    -- Post-session
    seeker_mood_after INTEGER,
    duration_minutes INTEGER,

    -- Escalation
    was_escalated BOOLEAN NOT NULL DEFAULT false,
    escalation_reason TEXT,
    escalated_at TIMESTAMPTZ,

    -- Anonymous mode
    is_anonymous BOOLEAN NOT NULL DEFAULT false,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Session messages
CREATE TABLE IF NOT EXISTS support_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES support_sessions(id) ON DELETE CASCADE,
    sender_type TEXT NOT NULL, -- 'seeker', 'listener', 'system'
    content TEXT NOT NULL,
    is_flagged BOOLEAN NOT NULL DEFAULT false, -- AI safety flag
    flag_reason TEXT,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Session ratings and feedback
CREATE TABLE IF NOT EXISTS session_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES support_sessions(id) ON DELETE CASCADE,
    from_user_id UUID NOT NULL REFERENCES profiles(id),

    rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    felt_heard BOOLEAN,
    felt_supported BOOLEAN,
    would_recommend BOOLEAN,
    feedback_text TEXT,

    -- For listeners reviewing seekers (optional)
    seeker_engagement TEXT, -- 'engaged', 'distracted', 'resistant'

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_session_feedback UNIQUE (session_id, from_user_id)
);

-- Support queue for matching
CREATE TABLE IF NOT EXISTS support_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seeker_id UUID NOT NULL REFERENCES profiles(id),
    session_type TEXT NOT NULL,
    topic_tags TEXT[],
    is_anonymous BOOLEAN NOT NULL DEFAULT false,
    preferred_language TEXT DEFAULT 'en',
    preferred_gender TEXT, -- Optional preference

    queued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    matched_session_id UUID REFERENCES support_sessions(id),

    CONSTRAINT unique_queue_entry UNIQUE (seeker_id, session_type)
);

-- ============================================================================
-- MENTORSHIP PROGRAM
-- ============================================================================

-- Mentorship relationships
CREATE TABLE IF NOT EXISTS mentorships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    mentor_id UUID NOT NULL REFERENCES profiles(id),
    mentee_id UUID NOT NULL REFERENCES profiles(id),

    -- Status
    status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'active', 'paused', 'completed', 'cancelled'

    -- Matching context
    matched_on_challenges TEXT[], -- What they were matched for
    compatibility_score DECIMAL(3,2),

    -- Timeline
    started_at TIMESTAMPTZ,
    last_interaction_at TIMESTAMPTZ,
    next_checkin_due TIMESTAMPTZ,
    ends_at TIMESTAMPTZ, -- Initial 3-month commitment

    -- Settings
    checkin_frequency TEXT NOT NULL DEFAULT 'weekly', -- 'daily', 'weekly', 'biweekly'
    mentor_can_see_progress BOOLEAN NOT NULL DEFAULT true,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT unique_mentorship UNIQUE (mentor_id, mentee_id),
    CONSTRAINT no_self_mentor CHECK (mentor_id != mentee_id)
);

-- Mentorship check-ins
CREATE TABLE IF NOT EXISTS mentorship_checkins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mentorship_id UUID NOT NULL REFERENCES mentorships(id) ON DELETE CASCADE,

    initiated_by UUID NOT NULL REFERENCES profiles(id),
    checkin_type TEXT NOT NULL, -- 'scheduled', 'spontaneous', 'celebration', 'support_request'

    -- Content
    message TEXT,
    mood_shared INTEGER,
    wins_shared TEXT[],
    challenges_shared TEXT[],
    goals_discussed TEXT[],

    -- Response
    responded_at TIMESTAMPTZ,
    response_message TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- GRATITUDE & GIVING BACK
-- ============================================================================

-- Gratitude actions
CREATE TABLE IF NOT EXISTS gratitude_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    from_user_id UUID NOT NULL REFERENCES profiles(id),
    to_user_id UUID REFERENCES profiles(id), -- Null for anonymous community actions
    action_type TEXT NOT NULL, -- 'thank_listener', 'community_hug', 'wisdom_share', 'story_spotlight', 'donation'

    -- Content
    message TEXT,
    is_public BOOLEAN NOT NULL DEFAULT false,

    -- Reference
    session_id UUID REFERENCES support_sessions(id),
    mentorship_id UUID REFERENCES mentorships(id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Community wisdom/tips
CREATE TABLE IF NOT EXISTS community_wisdom (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id),

    -- Content
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    category TEXT NOT NULL, -- 'coping', 'motivation', 'technique', 'perspective'
    tags TEXT[],

    -- Moderation
    status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'approved', 'rejected'
    moderated_at TIMESTAMPTZ,
    moderation_notes TEXT,

    -- Engagement
    helpful_count INTEGER NOT NULL DEFAULT 0,
    save_count INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- ANONYMOUS SUPPORT ROOMS
-- ============================================================================

-- Anonymous support rooms
CREATE TABLE IF NOT EXISTS anonymous_rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    topic TEXT NOT NULL, -- 'grief', 'addiction', 'trauma', 'relationship', etc.

    -- Settings
    max_participants INTEGER NOT NULL DEFAULT 20,
    is_moderated BOOLEAN NOT NULL DEFAULT true,
    requires_listener BOOLEAN NOT NULL DEFAULT true,

    -- Schedule
    is_always_open BOOLEAN NOT NULL DEFAULT false,
    schedule JSONB, -- Recurring schedule

    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Anonymous room participants (temporary identities)
CREATE TABLE IF NOT EXISTS anonymous_room_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL REFERENCES anonymous_rooms(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id),

    -- Temporary identity
    anonymous_name TEXT NOT NULL, -- Generated: "Gentle Butterfly", "Calm Ocean", etc.
    anonymous_avatar TEXT, -- Generated avatar

    -- Session
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    left_at TIMESTAMPTZ,

    CONSTRAINT unique_room_participant UNIQUE (room_id, user_id)
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_listeners_available ON listeners(status, is_available) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_listeners_specializations ON listeners USING GIN(specializations);
CREATE INDEX IF NOT EXISTS idx_support_sessions_seeker ON support_sessions(seeker_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_sessions_listener ON support_sessions(listener_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_sessions_pending ON support_sessions(status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_support_queue_active ON support_queue(queued_at) WHERE matched_session_id IS NULL;
CREATE INDEX IF NOT EXISTS idx_mentorships_mentor ON mentorships(mentor_id, status);
CREATE INDEX IF NOT EXISTS idx_mentorships_mentee ON mentorships(mentee_id, status);
CREATE INDEX IF NOT EXISTS idx_gratitude_to_user ON gratitude_actions(to_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_community_wisdom_status ON community_wisdom(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_messages_session ON support_messages(session_id, sent_at);
CREATE INDEX IF NOT EXISTS idx_mentorship_checkins_mentorship ON mentorship_checkins(mentorship_id, created_at DESC);

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE listeners ENABLE ROW LEVEL SECURITY;
ALTER TABLE listener_training_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE listener_availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentorships ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentorship_checkins ENABLE ROW LEVEL SECURITY;
ALTER TABLE gratitude_actions ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_wisdom ENABLE ROW LEVEL SECURITY;
ALTER TABLE anonymous_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE anonymous_room_participants ENABLE ROW LEVEL SECURITY;

-- Listener policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own listener profile' AND tablename = 'listeners') THEN
        CREATE POLICY "Users manage own listener profile"
            ON listeners FOR ALL
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Public can view active listeners' AND tablename = 'listeners') THEN
        CREATE POLICY "Public can view active listeners"
            ON listeners FOR SELECT
            USING (status = 'active' AND is_available = true);
    END IF;
END $$;

-- Training progress policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own training progress' AND tablename = 'listener_training_progress') THEN
        CREATE POLICY "Users manage own training progress"
            ON listener_training_progress FOR ALL
            USING (
                EXISTS (
                    SELECT 1 FROM listeners
                    WHERE listeners.id = listener_training_progress.listener_id
                    AND listeners.user_id = auth.uid()
                )
            );
    END IF;
END $$;

-- Listener availability policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Listeners manage own availability' AND tablename = 'listener_availability') THEN
        CREATE POLICY "Listeners manage own availability"
            ON listener_availability FOR ALL
            USING (
                EXISTS (
                    SELECT 1 FROM listeners
                    WHERE listeners.id = listener_availability.listener_id
                    AND listeners.user_id = auth.uid()
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Availability visible for matching' AND tablename = 'listener_availability') THEN
        CREATE POLICY "Availability visible for matching"
            ON listener_availability FOR SELECT
            USING (is_active = true);
    END IF;
END $$;

-- Support sessions policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Participants can view sessions' AND tablename = 'support_sessions') THEN
        CREATE POLICY "Participants can view sessions"
            ON support_sessions FOR SELECT
            USING (
                seeker_id = auth.uid() OR
                EXISTS (
                    SELECT 1 FROM listeners
                    WHERE listeners.id = support_sessions.listener_id
                    AND listeners.user_id = auth.uid()
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can create support sessions' AND tablename = 'support_sessions') THEN
        CREATE POLICY "Users can create support sessions"
            ON support_sessions FOR INSERT
            WITH CHECK (seeker_id = auth.uid());
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Participants can update sessions' AND tablename = 'support_sessions') THEN
        CREATE POLICY "Participants can update sessions"
            ON support_sessions FOR UPDATE
            USING (
                seeker_id = auth.uid() OR
                EXISTS (
                    SELECT 1 FROM listeners
                    WHERE listeners.id = support_sessions.listener_id
                    AND listeners.user_id = auth.uid()
                )
            );
    END IF;
END $$;

-- Support messages policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Participants can view messages' AND tablename = 'support_messages') THEN
        CREATE POLICY "Participants can view messages"
            ON support_messages FOR SELECT
            USING (
                EXISTS (
                    SELECT 1 FROM support_sessions
                    WHERE support_sessions.id = support_messages.session_id
                    AND (
                        support_sessions.seeker_id = auth.uid() OR
                        EXISTS (
                            SELECT 1 FROM listeners
                            WHERE listeners.id = support_sessions.listener_id
                            AND listeners.user_id = auth.uid()
                        )
                    )
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Participants can send messages' AND tablename = 'support_messages') THEN
        CREATE POLICY "Participants can send messages"
            ON support_messages FOR INSERT
            WITH CHECK (
                EXISTS (
                    SELECT 1 FROM support_sessions
                    WHERE support_sessions.id = support_messages.session_id
                    AND support_sessions.status = 'active'
                    AND (
                        support_sessions.seeker_id = auth.uid() OR
                        EXISTS (
                            SELECT 1 FROM listeners
                            WHERE listeners.id = support_sessions.listener_id
                            AND listeners.user_id = auth.uid()
                        )
                    )
                )
            );
    END IF;
END $$;

-- Session feedback policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can submit session feedback' AND tablename = 'session_feedback') THEN
        CREATE POLICY "Users can submit session feedback"
            ON session_feedback FOR INSERT
            WITH CHECK (from_user_id = auth.uid());
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can view own feedback' AND tablename = 'session_feedback') THEN
        CREATE POLICY "Users can view own feedback"
            ON session_feedback FOR SELECT
            USING (from_user_id = auth.uid());
    END IF;
END $$;

-- Support queue policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own queue entries' AND tablename = 'support_queue') THEN
        CREATE POLICY "Users manage own queue entries"
            ON support_queue FOR ALL
            USING (seeker_id = auth.uid());
    END IF;
END $$;

-- Mentorship policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Mentorship participants can view' AND tablename = 'mentorships') THEN
        CREATE POLICY "Mentorship participants can view"
            ON mentorships FOR SELECT
            USING (mentor_id = auth.uid() OR mentee_id = auth.uid());
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Mentorship participants can update' AND tablename = 'mentorships') THEN
        CREATE POLICY "Mentorship participants can update"
            ON mentorships FOR UPDATE
            USING (mentor_id = auth.uid() OR mentee_id = auth.uid());
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can request mentorship' AND tablename = 'mentorships') THEN
        CREATE POLICY "Users can request mentorship"
            ON mentorships FOR INSERT
            WITH CHECK (mentee_id = auth.uid());
    END IF;
END $$;

-- Mentorship checkins policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Mentorship members can view checkins' AND tablename = 'mentorship_checkins') THEN
        CREATE POLICY "Mentorship members can view checkins"
            ON mentorship_checkins FOR SELECT
            USING (
                EXISTS (
                    SELECT 1 FROM mentorships
                    WHERE mentorships.id = mentorship_checkins.mentorship_id
                    AND (mentorships.mentor_id = auth.uid() OR mentorships.mentee_id = auth.uid())
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Mentorship members can create checkins' AND tablename = 'mentorship_checkins') THEN
        CREATE POLICY "Mentorship members can create checkins"
            ON mentorship_checkins FOR INSERT
            WITH CHECK (
                initiated_by = auth.uid() AND
                EXISTS (
                    SELECT 1 FROM mentorships
                    WHERE mentorships.id = mentorship_checkins.mentorship_id
                    AND (mentorships.mentor_id = auth.uid() OR mentorships.mentee_id = auth.uid())
                    AND mentorships.status = 'active'
                )
            );
    END IF;
END $$;

-- Gratitude policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Gratitude visible to recipient' AND tablename = 'gratitude_actions') THEN
        CREATE POLICY "Gratitude visible to recipient"
            ON gratitude_actions FOR SELECT
            USING (
                from_user_id = auth.uid() OR
                to_user_id = auth.uid() OR
                is_public = true
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can create gratitude' AND tablename = 'gratitude_actions') THEN
        CREATE POLICY "Users can create gratitude"
            ON gratitude_actions FOR INSERT
            WITH CHECK (from_user_id = auth.uid());
    END IF;
END $$;

-- Community wisdom policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Approved wisdom is public' AND tablename = 'community_wisdom') THEN
        CREATE POLICY "Approved wisdom is public"
            ON community_wisdom FOR SELECT
            USING (status = 'approved' OR user_id = auth.uid());
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can submit wisdom' AND tablename = 'community_wisdom') THEN
        CREATE POLICY "Users can submit wisdom"
            ON community_wisdom FOR INSERT
            WITH CHECK (user_id = auth.uid());
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can update own wisdom' AND tablename = 'community_wisdom') THEN
        CREATE POLICY "Users can update own wisdom"
            ON community_wisdom FOR UPDATE
            USING (user_id = auth.uid());
    END IF;
END $$;

-- Anonymous rooms policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Anonymous rooms are public' AND tablename = 'anonymous_rooms') THEN
        CREATE POLICY "Anonymous rooms are public"
            ON anonymous_rooms FOR SELECT
            USING (is_active = true);
    END IF;
END $$;

-- Anonymous room participants policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users manage own room participation' AND tablename = 'anonymous_room_participants') THEN
        CREATE POLICY "Users manage own room participation"
            ON anonymous_room_participants FOR ALL
            USING (user_id = auth.uid());
    END IF;
END $$;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Update listener stats after session completion
CREATE OR REPLACE FUNCTION update_listener_stats()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'completed' AND NEW.listener_id IS NOT NULL THEN
        UPDATE listeners
        SET
            total_sessions = total_sessions + 1,
            total_hours = total_hours + COALESCE(NEW.duration_minutes, 0) / 60.0,
            updated_at = NOW()
        WHERE id = NEW.listener_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_session_complete_update_listener_stats ON support_sessions;
CREATE TRIGGER on_session_complete_update_listener_stats
    AFTER UPDATE OF status ON support_sessions
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'completed')
    EXECUTE FUNCTION update_listener_stats();

-- Update listener rating after feedback
CREATE OR REPLACE FUNCTION update_listener_rating()
RETURNS TRIGGER AS $$
DECLARE
    v_listener_id UUID;
BEGIN
    -- Get the listener for this session
    SELECT listener_id INTO v_listener_id
    FROM support_sessions
    WHERE id = NEW.session_id;

    IF v_listener_id IS NOT NULL THEN
        -- Recalculate average rating
        UPDATE listeners
        SET
            average_rating = (
                SELECT AVG(sf.rating)::DECIMAL(3,2)
                FROM session_feedback sf
                JOIN support_sessions ss ON ss.id = sf.session_id
                WHERE ss.listener_id = v_listener_id
            ),
            rating_count = rating_count + 1,
            updated_at = NOW()
        WHERE id = v_listener_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_feedback_update_listener_rating ON session_feedback;
CREATE TRIGGER on_feedback_update_listener_rating
    AFTER INSERT ON session_feedback
    FOR EACH ROW
    EXECUTE FUNCTION update_listener_rating();

-- Update mentorship last interaction
CREATE OR REPLACE FUNCTION update_mentorship_interaction()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE mentorships
    SET
        last_interaction_at = NOW(),
        updated_at = NOW()
    WHERE id = NEW.mentorship_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_checkin_update_mentorship ON mentorship_checkins;
CREATE TRIGGER on_checkin_update_mentorship
    AFTER INSERT ON mentorship_checkins
    FOR EACH ROW
    EXECUTE FUNCTION update_mentorship_interaction();

-- Update wisdom helpful count
CREATE OR REPLACE FUNCTION increment_wisdom_helpful()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.action_type = 'wisdom_share' AND NEW.session_id IS NULL THEN
        -- This is a "helpful" vote, not a share
        -- Find the wisdom post by message content hash (simplified)
        NULL; -- Implement as needed
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- RPC FUNCTIONS
-- ============================================================================

-- Apply to become a listener
CREATE OR REPLACE FUNCTION apply_to_become_listener(
    p_display_name TEXT DEFAULT NULL,
    p_bio TEXT DEFAULT NULL,
    p_specializations TEXT[] DEFAULT ARRAY[]::TEXT[],
    p_languages TEXT[] DEFAULT ARRAY['en']::TEXT[]
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_listener_id UUID;
    v_days_on_platform INTEGER;
    v_exercises_completed INTEGER;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Check eligibility: 30+ days on platform
    SELECT EXTRACT(EPOCH FROM (NOW() - created_at)) / 86400
    INTO v_days_on_platform
    FROM profiles
    WHERE id = v_user_id;

    IF v_days_on_platform < 30 THEN
        RAISE EXCEPTION 'Must have 30+ days on platform to apply';
    END IF;

    -- Check eligibility: 10+ exercises completed
    SELECT COUNT(*)
    INTO v_exercises_completed
    FROM exercise_sessions
    WHERE user_id = v_user_id AND completed_at IS NOT NULL;

    IF v_exercises_completed < 10 THEN
        RAISE EXCEPTION 'Must complete 10+ exercises to apply';
    END IF;

    -- Check if already a listener
    SELECT id INTO v_listener_id
    FROM listeners
    WHERE user_id = v_user_id;

    IF v_listener_id IS NOT NULL THEN
        RAISE EXCEPTION 'Already applied or registered as listener';
    END IF;

    -- Create listener application
    INSERT INTO listeners (
        user_id,
        status,
        display_name,
        bio,
        specializations,
        languages
    )
    VALUES (
        v_user_id,
        'applicant',
        COALESCE(p_display_name, (SELECT display_name FROM profiles WHERE id = v_user_id)),
        p_bio,
        p_specializations,
        p_languages
    )
    RETURNING id INTO v_listener_id;

    RETURN v_listener_id;
END;
$$;

-- Start listener training
CREATE OR REPLACE FUNCTION start_listener_training()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_listener_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT id INTO v_listener_id
    FROM listeners
    WHERE user_id = v_user_id AND status = 'applicant';

    IF v_listener_id IS NULL THEN
        RAISE EXCEPTION 'Not an applicant';
    END IF;

    UPDATE listeners
    SET
        status = 'training',
        training_started_at = NOW(),
        updated_at = NOW()
    WHERE id = v_listener_id;

    RETURN TRUE;
END;
$$;

-- Complete training module
CREATE OR REPLACE FUNCTION complete_training_module(
    p_module_id TEXT,
    p_score INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_listener_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT id INTO v_listener_id
    FROM listeners
    WHERE user_id = v_user_id AND status = 'training';

    IF v_listener_id IS NULL THEN
        RAISE EXCEPTION 'Not in training';
    END IF;

    -- Upsert module progress
    INSERT INTO listener_training_progress (
        listener_id,
        module_id,
        completed_at,
        score
    )
    VALUES (
        v_listener_id,
        p_module_id,
        NOW(),
        p_score
    )
    ON CONFLICT (listener_id, module_id)
    DO UPDATE SET
        completed_at = NOW(),
        score = p_score,
        attempts = listener_training_progress.attempts + 1;

    RETURN TRUE;
END;
$$;

-- Complete certification
CREATE OR REPLACE FUNCTION complete_listener_certification(
    p_final_score INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_listener_id UUID;
    v_passed BOOLEAN;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT id INTO v_listener_id
    FROM listeners
    WHERE user_id = v_user_id AND status = 'training';

    IF v_listener_id IS NULL THEN
        RAISE EXCEPTION 'Not in training';
    END IF;

    -- 80% pass rate required
    v_passed := p_final_score >= 80;

    UPDATE listeners
    SET
        certification_score = p_final_score,
        certification_passed = v_passed,
        training_completed_at = NOW(),
        status = CASE WHEN v_passed THEN 'active' ELSE 'training' END,
        updated_at = NOW()
    WHERE id = v_listener_id;

    RETURN v_passed;
END;
$$;

-- Toggle listener availability
CREATE OR REPLACE FUNCTION toggle_listener_availability(
    p_is_available BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    UPDATE listeners
    SET
        is_available = p_is_available,
        updated_at = NOW()
    WHERE user_id = v_user_id AND status = 'active';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Not an active listener';
    END IF;

    RETURN p_is_available;
END;
$$;

-- Request mentorship
CREATE OR REPLACE FUNCTION request_mentorship(
    p_mentor_id UUID,
    p_challenges TEXT[]
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_mentorship_id UUID;
    v_mentor_days INTEGER;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF v_user_id = p_mentor_id THEN
        RAISE EXCEPTION 'Cannot mentor yourself';
    END IF;

    -- Check mentor has 90+ days
    SELECT EXTRACT(EPOCH FROM (NOW() - created_at)) / 86400
    INTO v_mentor_days
    FROM profiles
    WHERE id = p_mentor_id;

    IF v_mentor_days < 90 THEN
        RAISE EXCEPTION 'Mentor must have 90+ days on platform';
    END IF;

    -- Check for existing mentorship
    IF EXISTS (
        SELECT 1 FROM mentorships
        WHERE mentor_id = p_mentor_id AND mentee_id = v_user_id
        AND status IN ('pending', 'active')
    ) THEN
        RAISE EXCEPTION 'Mentorship already exists';
    END IF;

    -- Create mentorship request
    INSERT INTO mentorships (
        mentor_id,
        mentee_id,
        matched_on_challenges,
        ends_at
    )
    VALUES (
        p_mentor_id,
        v_user_id,
        p_challenges,
        NOW() + INTERVAL '3 months'
    )
    RETURNING id INTO v_mentorship_id;

    RETURN v_mentorship_id;
END;
$$;

-- Accept mentorship
CREATE OR REPLACE FUNCTION accept_mentorship(
    p_mentorship_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    UPDATE mentorships
    SET
        status = 'active',
        started_at = NOW(),
        next_checkin_due = NOW() + INTERVAL '7 days',
        updated_at = NOW()
    WHERE id = p_mentorship_id
    AND mentor_id = v_user_id
    AND status = 'pending';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Mentorship not found or not authorized';
    END IF;

    RETURN TRUE;
END;
$$;

-- Generate anonymous name
CREATE OR REPLACE FUNCTION generate_anonymous_name()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
    adjectives TEXT[] := ARRAY['Gentle', 'Calm', 'Brave', 'Kind', 'Warm', 'Peaceful', 'Hopeful', 'Strong', 'Wise', 'Bright'];
    nouns TEXT[] := ARRAY['Butterfly', 'Ocean', 'Mountain', 'Star', 'River', 'Forest', 'Cloud', 'Sunrise', 'Meadow', 'Phoenix'];
BEGIN
    RETURN adjectives[1 + floor(random() * array_length(adjectives, 1))] || ' ' ||
           nouns[1 + floor(random() * array_length(nouns, 1))];
END;
$$;

-- Join anonymous room
CREATE OR REPLACE FUNCTION join_anonymous_room(
    p_room_id UUID
)
RETURNS TABLE (
    participant_id UUID,
    anonymous_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_participant_id UUID;
    v_anonymous_name TEXT;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Check room is active
    IF NOT EXISTS (SELECT 1 FROM anonymous_rooms WHERE id = p_room_id AND is_active = true) THEN
        RAISE EXCEPTION 'Room not available';
    END IF;

    -- Check if already in room
    SELECT arp.id, arp.anonymous_name
    INTO v_participant_id, v_anonymous_name
    FROM anonymous_room_participants arp
    WHERE arp.room_id = p_room_id AND arp.user_id = v_user_id AND arp.left_at IS NULL;

    IF v_participant_id IS NOT NULL THEN
        RETURN QUERY SELECT v_participant_id, v_anonymous_name;
        RETURN;
    END IF;

    -- Generate anonymous identity and join
    v_anonymous_name := generate_anonymous_name();

    INSERT INTO anonymous_room_participants (
        room_id,
        user_id,
        anonymous_name
    )
    VALUES (
        p_room_id,
        v_user_id,
        v_anonymous_name
    )
    RETURNING id INTO v_participant_id;

    RETURN QUERY SELECT v_participant_id, v_anonymous_name;
END;
$$;

-- Send gratitude
CREATE OR REPLACE FUNCTION send_gratitude(
    p_to_user_id UUID,
    p_action_type TEXT,
    p_message TEXT DEFAULT NULL,
    p_is_public BOOLEAN DEFAULT false,
    p_session_id UUID DEFAULT NULL,
    p_mentorship_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_gratitude_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    INSERT INTO gratitude_actions (
        from_user_id,
        to_user_id,
        action_type,
        message,
        is_public,
        session_id,
        mentorship_id
    )
    VALUES (
        v_user_id,
        p_to_user_id,
        p_action_type,
        p_message,
        p_is_public,
        p_session_id,
        p_mentorship_id
    )
    RETURNING id INTO v_gratitude_id;

    RETURN v_gratitude_id;
END;
$$;

-- Get listener stats
CREATE OR REPLACE FUNCTION get_listener_stats()
RETURNS TABLE (
    listener_id UUID,
    total_sessions INTEGER,
    total_hours DECIMAL,
    average_rating DECIMAL,
    rating_count INTEGER,
    is_available BOOLEAN,
    specializations TEXT[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    RETURN QUERY
    SELECT
        l.id,
        l.total_sessions,
        l.total_hours,
        l.average_rating,
        l.rating_count,
        l.is_available,
        l.specializations
    FROM listeners l
    WHERE l.user_id = v_user_id;
END;
$$;

-- Get my active sessions (seeker or listener)
CREATE OR REPLACE FUNCTION get_my_active_sessions()
RETURNS SETOF support_sessions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    RETURN QUERY
    SELECT ss.*
    FROM support_sessions ss
    LEFT JOIN listeners l ON l.id = ss.listener_id
    WHERE ss.status IN ('pending', 'matched', 'active')
    AND (ss.seeker_id = v_user_id OR l.user_id = v_user_id)
    ORDER BY ss.created_at DESC;
END;
$$;

-- Get my mentorships (mentor or mentee)
CREATE OR REPLACE FUNCTION get_my_mentorships()
RETURNS SETOF mentorships
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    RETURN QUERY
    SELECT *
    FROM mentorships
    WHERE (mentor_id = v_user_id OR mentee_id = v_user_id)
    AND status IN ('pending', 'active')
    ORDER BY created_at DESC;
END;
$$;

-- Atomic listener matching with row-level locking to prevent race conditions
-- This function finds an available listener and claims them atomically
CREATE OR REPLACE FUNCTION claim_listener_for_session(
    p_session_id UUID,
    p_topic_tags TEXT[] DEFAULT NULL,
    p_preferred_language TEXT DEFAULT 'en',
    p_session_type TEXT DEFAULT 'quick',
    p_user_timezone TEXT DEFAULT 'UTC'
)
RETURNS TABLE (
    listener_id UUID,
    user_id UUID,
    display_name TEXT,
    average_rating DECIMAL,
    total_sessions INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_listener RECORD;
    v_day_of_week INTEGER;
    v_current_time TIME;
    v_utc_offset INTERVAL;
BEGIN
    -- Calculate the current time in the listener's timezone context
    -- For simplicity, we convert to UTC and compare against availability
    v_day_of_week := EXTRACT(DOW FROM NOW() AT TIME ZONE p_user_timezone);
    v_current_time := (NOW() AT TIME ZONE p_user_timezone)::TIME;

    -- Find and lock an available listener atomically
    -- FOR UPDATE SKIP LOCKED prevents race conditions - if another transaction
    -- is already processing a listener, we skip to the next one
    FOR v_listener IN
        SELECT l.id, l.user_id, l.display_name, l.average_rating, l.total_sessions
        FROM listeners l
        WHERE l.status = 'active'
        AND l.is_available = true
        -- Check topic specialization match if provided
        AND (p_topic_tags IS NULL OR p_topic_tags = '{}' OR l.specializations && p_topic_tags)
        -- Check language preference
        AND p_preferred_language = ANY(l.languages)
        -- Check crisis bridge capability if needed
        AND (p_session_type != 'crisis_bridge' OR l.accepts_crisis_bridge = true)
        -- Check availability schedule
        AND EXISTS (
            SELECT 1 FROM listener_availability la
            WHERE la.listener_id = l.id
            AND la.is_active = true
            AND la.day_of_week = v_day_of_week
            AND v_current_time BETWEEN la.start_time AND la.end_time
        )
        -- Check no active sessions
        AND NOT EXISTS (
            SELECT 1 FROM support_sessions ss
            WHERE ss.listener_id = l.id
            AND ss.status IN ('matched', 'active')
        )
        ORDER BY l.average_rating DESC NULLS LAST, l.total_sessions ASC
        FOR UPDATE OF l SKIP LOCKED
        LIMIT 1
    LOOP
        -- Found an available listener, claim them for this session
        UPDATE support_sessions
        SET
            listener_id = v_listener.id,
            status = 'matched',
            matched_at = NOW()
        WHERE id = p_session_id
        AND status = 'pending';  -- Only update if still pending

        IF FOUND THEN
            -- Return the matched listener info
            RETURN QUERY SELECT
                v_listener.id,
                v_listener.user_id,
                v_listener.display_name,
                v_listener.average_rating,
                v_listener.total_sessions;
            RETURN;
        END IF;
    END LOOP;

    -- No listener found
    RETURN;
END;
$$;

-- Get anonymous-safe session info (hides seeker_id when anonymous)
CREATE OR REPLACE FUNCTION get_session_for_listener(p_session_id UUID)
RETURNS TABLE (
    id UUID,
    seeker_display_name TEXT,
    session_type TEXT,
    topic_tags TEXT[],
    seeker_mood_before INTEGER,
    seeker_notes TEXT,
    is_anonymous BOOLEAN,
    status TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_is_listener BOOLEAN;
BEGIN
    -- Verify caller is the listener for this session
    SELECT EXISTS (
        SELECT 1 FROM support_sessions ss
        JOIN listeners l ON l.id = ss.listener_id
        WHERE ss.id = p_session_id
        AND l.user_id = v_user_id
    ) INTO v_is_listener;

    IF NOT v_is_listener THEN
        RAISE EXCEPTION 'Not authorized to view this session';
    END IF;

    RETURN QUERY
    SELECT
        ss.id,
        -- Only show display name if NOT anonymous
        CASE
            WHEN ss.is_anonymous THEN 'Anonymous User'
            ELSE COALESCE(p.display_name, 'User')
        END AS seeker_display_name,
        ss.session_type,
        ss.topic_tags,
        ss.seeker_mood_before,
        -- Redact notes if anonymous and contains personal info
        CASE
            WHEN ss.is_anonymous THEN '[Notes hidden for privacy]'
            ELSE ss.seeker_notes
        END AS seeker_notes,
        ss.is_anonymous,
        ss.status,
        ss.created_at
    FROM support_sessions ss
    LEFT JOIN profiles p ON p.id = ss.seeker_id
    WHERE ss.id = p_session_id;
END;
$$;

COMMENT ON TABLE listeners IS 'Certified peer support listeners';
COMMENT ON TABLE support_sessions IS 'One-on-one peer support sessions';
COMMENT ON TABLE mentorships IS 'Long-term mentor-mentee relationships';
COMMENT ON TABLE gratitude_actions IS 'Ways users give back to the community';
COMMENT ON TABLE community_wisdom IS 'User-contributed tips and wisdom';
COMMENT ON TABLE anonymous_rooms IS 'Anonymous group support spaces';
COMMENT ON FUNCTION claim_listener_for_session IS 'Atomically claims an available listener for a session using row-level locking';
COMMENT ON FUNCTION get_session_for_listener IS 'Returns session info with anonymous-safe data for listeners';
