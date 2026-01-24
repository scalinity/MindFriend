-- Mentorship Matching Feature Migration
-- Adds intelligent matching algorithm and safety systems

-- =============================================================================
-- MENTORSHIP PROFILES TABLE
-- =============================================================================
-- User profiles for mentor/mentee preferences and availability

CREATE TABLE IF NOT EXISTS mentorship_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Mentor availability
    is_mentor_available BOOLEAN NOT NULL DEFAULT false,

    -- Areas of expertise (for mentors)
    expertise_areas TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],

    -- Areas seeking help with (for mentees)
    seeking_areas TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],

    -- Profile information
    bio TEXT,
    availability_hours_week INTEGER DEFAULT 2,
    languages TEXT[] NOT NULL DEFAULT ARRAY['en']::TEXT[],
    timezone TEXT DEFAULT 'UTC',

    -- Mentor qualifications
    verified BOOLEAN NOT NULL DEFAULT false,
    verified_at TIMESTAMPTZ,
    training_completed BOOLEAN NOT NULL DEFAULT false,
    training_completed_at TIMESTAMPTZ,

    -- Stats
    total_mentorships INTEGER NOT NULL DEFAULT 0,
    avg_rating DECIMAL(3,2),

    -- Preferences
    max_active_mentees INTEGER NOT NULL DEFAULT 2,
    mentorship_style TEXT DEFAULT 'supportive' CHECK (mentorship_style IN (
        'supportive', 'advisory', 'accountability'
    )),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for efficient matching queries
CREATE INDEX IF NOT EXISTS idx_mentorship_profiles_available
    ON mentorship_profiles(is_mentor_available, verified)
    WHERE is_mentor_available = true AND verified = true;

CREATE INDEX IF NOT EXISTS idx_mentorship_profiles_expertise
    ON mentorship_profiles USING GIN (expertise_areas);

CREATE INDEX IF NOT EXISTS idx_mentorship_profiles_seeking
    ON mentorship_profiles USING GIN (seeking_areas);

CREATE INDEX IF NOT EXISTS idx_mentorship_profiles_languages
    ON mentorship_profiles USING GIN (languages);

-- =============================================================================
-- MENTORSHIP MATCHES TABLE
-- =============================================================================
-- Records of mentor-mentee matching with compatibility scores

CREATE TABLE IF NOT EXISTS mentorship_matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mentor_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    mentee_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Matching metadata
    matched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
        'pending', 'accepted', 'active', 'completed', 'declined', 'ended', 'suspended'
    )),

    -- Compatibility scoring
    compatibility_score DECIMAL(5,2),
    match_reason TEXT,
    expertise_match_score DECIMAL(3,2),
    language_match_score DECIMAL(3,2),
    timezone_match_score DECIMAL(3,2),
    availability_match_score DECIMAL(3,2),

    -- Introduction
    introduction_message TEXT,
    mentor_response TEXT,

    -- Lifecycle
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    end_reason TEXT,
    duration_weeks INTEGER DEFAULT 4,

    -- Anonymous aliases for privacy
    mentor_alias TEXT NOT NULL,
    mentee_alias TEXT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Prevent self-mentorship
    CONSTRAINT no_self_mentorship CHECK (mentor_id <> mentee_id),
    -- Unique active match per pair
    CONSTRAINT unique_active_mentorship UNIQUE (mentor_id, mentee_id)
);

CREATE INDEX IF NOT EXISTS idx_mentorship_matches_mentor
    ON mentorship_matches(mentor_id, status);

CREATE INDEX IF NOT EXISTS idx_mentorship_matches_mentee
    ON mentorship_matches(mentee_id, status);

CREATE INDEX IF NOT EXISTS idx_mentorship_matches_active
    ON mentorship_matches(status) WHERE status IN ('pending', 'accepted', 'active');

-- =============================================================================
-- MENTORSHIP MESSAGES TABLE
-- =============================================================================
-- Secure messaging between matched mentors and mentees

CREATE TABLE IF NOT EXISTS mentorship_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id UUID NOT NULL REFERENCES mentorship_matches(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES auth.users(id),

    -- Message content
    content TEXT NOT NULL,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at TIMESTAMPTZ,

    -- Safety moderation
    flagged BOOLEAN NOT NULL DEFAULT false,
    flag_reason TEXT,
    reviewed BOOLEAN NOT NULL DEFAULT false,
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES auth.users(id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mentorship_messages_match
    ON mentorship_messages(match_id, sent_at DESC);

CREATE INDEX IF NOT EXISTS idx_mentorship_messages_flagged
    ON mentorship_messages(flagged, reviewed)
    WHERE flagged = true AND reviewed = false;

-- =============================================================================
-- MENTORSHIP REPORTS TABLE
-- =============================================================================
-- Safety reports for mentorship interactions

CREATE TABLE IF NOT EXISTS mentorship_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL REFERENCES auth.users(id),
    reported_id UUID NOT NULL REFERENCES auth.users(id),
    match_id UUID REFERENCES mentorship_matches(id),

    -- Report details
    reason TEXT NOT NULL CHECK (reason IN (
        'inappropriate_content', 'harassment', 'boundary_violation',
        'unprofessional', 'crisis_mishandling', 'personal_info_request',
        'other'
    )),
    description TEXT,
    message_ids UUID[] DEFAULT ARRAY[]::UUID[],

    -- Resolution
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
        'pending', 'investigating', 'resolved', 'dismissed'
    )),
    resolution TEXT,
    resolved_at TIMESTAMPTZ,
    resolved_by UUID REFERENCES auth.users(id),

    -- Actions taken
    action_taken TEXT CHECK (action_taken IN (
        'warning', 'suspension', 'permanent_ban', 'no_action'
    )),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mentorship_reports_status
    ON mentorship_reports(status) WHERE status IN ('pending', 'investigating');

CREATE INDEX IF NOT EXISTS idx_mentorship_reports_reported
    ON mentorship_reports(reported_id);

-- =============================================================================
-- RLS POLICIES
-- =============================================================================

ALTER TABLE mentorship_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentorship_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentorship_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentorship_reports ENABLE ROW LEVEL SECURITY;

-- Mentorship Profiles policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can view own mentorship profile' AND tablename = 'mentorship_profiles') THEN
        CREATE POLICY "Users can view own mentorship profile" ON mentorship_profiles
            FOR SELECT USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can update own mentorship profile' AND tablename = 'mentorship_profiles') THEN
        CREATE POLICY "Users can update own mentorship profile" ON mentorship_profiles
            FOR UPDATE USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can insert own mentorship profile' AND tablename = 'mentorship_profiles') THEN
        CREATE POLICY "Users can insert own mentorship profile" ON mentorship_profiles
            FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can view available mentors' AND tablename = 'mentorship_profiles') THEN
        CREATE POLICY "Users can view available mentors" ON mentorship_profiles
            FOR SELECT USING (
                is_mentor_available = true
                AND verified = true
            );
    END IF;
END $$;

-- Mentorship Matches policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Participants can view their matches' AND tablename = 'mentorship_matches') THEN
        CREATE POLICY "Participants can view their matches" ON mentorship_matches
            FOR SELECT USING (
                auth.uid() = mentor_id OR auth.uid() = mentee_id
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Mentors can update match status' AND tablename = 'mentorship_matches') THEN
        CREATE POLICY "Mentors can update match status" ON mentorship_matches
            FOR UPDATE USING (
                auth.uid() = mentor_id OR auth.uid() = mentee_id
            );
    END IF;
END $$;

-- Mentorship Messages policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Match participants can view messages' AND tablename = 'mentorship_messages') THEN
        CREATE POLICY "Match participants can view messages" ON mentorship_messages
            FOR SELECT USING (
                match_id IN (
                    SELECT id FROM mentorship_matches
                    WHERE mentor_id = auth.uid() OR mentee_id = auth.uid()
                )
            );
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Match participants can send messages' AND tablename = 'mentorship_messages') THEN
        CREATE POLICY "Match participants can send messages" ON mentorship_messages
            FOR INSERT WITH CHECK (
                auth.uid() = sender_id
                AND match_id IN (
                    SELECT id FROM mentorship_matches
                    WHERE status = 'active'
                    AND (mentor_id = auth.uid() OR mentee_id = auth.uid())
                )
            );
    END IF;
END $$;

-- Mentorship Reports policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can submit reports' AND tablename = 'mentorship_reports') THEN
        CREATE POLICY "Users can submit reports" ON mentorship_reports
            FOR INSERT WITH CHECK (auth.uid() = reporter_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can view own reports' AND tablename = 'mentorship_reports') THEN
        CREATE POLICY "Users can view own reports" ON mentorship_reports
            FOR SELECT USING (auth.uid() = reporter_id);
    END IF;
END $$;

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Generate anonymous mentor alias
CREATE OR REPLACE FUNCTION generate_mentorship_alias()
RETURNS TEXT AS $$
DECLARE
    adjectives TEXT[] := ARRAY['Wise', 'Kind', 'Calm', 'Gentle', 'Steady', 'Warm', 'Patient', 'Caring', 'Brave', 'Strong'];
    nouns TEXT[] := ARRAY['Oak', 'River', 'Mountain', 'Star', 'Moon', 'Sun', 'Cloud', 'Wave', 'Forest', 'Sky'];
BEGIN
    RETURN adjectives[1 + floor(random() * array_length(adjectives, 1))] || ' ' ||
           nouns[1 + floor(random() * array_length(nouns, 1))];
END;
$$ LANGUAGE plpgsql;

-- Calculate timezone overlap score (0-1)
CREATE OR REPLACE FUNCTION calculate_timezone_overlap(
    tz1 TEXT,
    tz2 TEXT
) RETURNS DECIMAL(3,2) AS $$
DECLARE
    offset1 INTEGER;
    offset2 INTEGER;
    diff INTEGER;
BEGIN
    -- Simple timezone offset calculation (hours from UTC)
    -- In production, use proper timezone handling
    SELECT EXTRACT(TIMEZONE FROM (NOW() AT TIME ZONE COALESCE(tz1, 'UTC'))) / 3600 INTO offset1;
    SELECT EXTRACT(TIMEZONE FROM (NOW() AT TIME ZONE COALESCE(tz2, 'UTC'))) / 3600 INTO offset2;

    diff := ABS(offset1 - offset2);

    -- Score based on hour difference (0 diff = 1.0, 12+ diff = 0)
    RETURN GREATEST(0, 1.0 - (diff::DECIMAL / 12));
EXCEPTION WHEN OTHERS THEN
    RETURN 0.5; -- Default score on error
END;
$$ LANGUAGE plpgsql;

-- Calculate mentor match score
CREATE OR REPLACE FUNCTION calculate_mentor_match_score(
    p_mentee_seeking TEXT[],
    p_mentor_expertise TEXT[],
    p_mentee_languages TEXT[],
    p_mentor_languages TEXT[],
    p_mentee_timezone TEXT,
    p_mentor_timezone TEXT,
    p_mentor_availability INTEGER,
    p_mentee_needed_hours INTEGER
) RETURNS TABLE (
    total_score DECIMAL(5,2),
    expertise_score DECIMAL(3,2),
    language_score DECIMAL(3,2),
    timezone_score DECIMAL(3,2),
    availability_score DECIMAL(3,2),
    match_reason TEXT
) AS $$
DECLARE
    expertise_overlap INTEGER;
    expertise_total INTEGER;
    language_overlap INTEGER;
    v_expertise_score DECIMAL(3,2);
    v_language_score DECIMAL(3,2);
    v_timezone_score DECIMAL(3,2);
    v_availability_score DECIMAL(3,2);
    v_total_score DECIMAL(5,2);
    v_match_reason TEXT;
    matched_areas TEXT[];
BEGIN
    -- Expertise match (40% weight)
    SELECT COUNT(*) INTO expertise_overlap
    FROM unnest(p_mentee_seeking) AS s
    WHERE s = ANY(p_mentor_expertise);

    expertise_total := GREATEST(array_length(p_mentee_seeking, 1), 1);
    v_expertise_score := LEAST(expertise_overlap::DECIMAL / expertise_total, 1.0);

    -- Get matched areas for reason
    SELECT array_agg(s) INTO matched_areas
    FROM unnest(p_mentee_seeking) AS s
    WHERE s = ANY(p_mentor_expertise);

    -- Language match (20% weight)
    SELECT COUNT(*) INTO language_overlap
    FROM unnest(p_mentee_languages) AS l
    WHERE l = ANY(p_mentor_languages);

    IF language_overlap > 0 THEN
        v_language_score := 1.0;
    ELSE
        v_language_score := 0.0;
    END IF;

    -- Timezone overlap (20% weight)
    v_timezone_score := calculate_timezone_overlap(p_mentee_timezone, p_mentor_timezone);

    -- Availability match (20% weight)
    IF p_mentor_availability >= p_mentee_needed_hours THEN
        v_availability_score := 1.0;
    ELSE
        v_availability_score := p_mentor_availability::DECIMAL / GREATEST(p_mentee_needed_hours, 1);
    END IF;

    -- Calculate weighted total
    v_total_score := (
        (v_expertise_score * 0.40) +
        (v_language_score * 0.20) +
        (v_timezone_score * 0.20) +
        (v_availability_score * 0.20)
    ) * 100;

    -- Generate match reason
    IF matched_areas IS NOT NULL AND array_length(matched_areas, 1) > 0 THEN
        v_match_reason := 'Experienced in ' || array_to_string(matched_areas, ', ');
    ELSE
        v_match_reason := 'General mentorship support';
    END IF;

    RETURN QUERY SELECT
        v_total_score,
        v_expertise_score,
        v_language_score,
        v_timezone_score,
        v_availability_score,
        v_match_reason;
END;
$$ LANGUAGE plpgsql;

-- Find mentor matches for a user
CREATE OR REPLACE FUNCTION find_mentor_matches(
    p_user_id UUID,
    p_seeking_areas TEXT[],
    p_limit INTEGER DEFAULT 5
) RETURNS TABLE (
    mentor_user_id UUID,
    profile_id UUID,
    bio TEXT,
    expertise_areas TEXT[],
    languages TEXT[],
    mentorship_style TEXT,
    availability_hours_week INTEGER,
    avg_rating DECIMAL(3,2),
    total_mentorships INTEGER,
    compatibility_score DECIMAL(5,2),
    expertise_match_score DECIMAL(3,2),
    language_match_score DECIMAL(3,2),
    timezone_match_score DECIMAL(3,2),
    availability_match_score DECIMAL(3,2),
    match_reason TEXT
) AS $$
DECLARE
    mentee_profile RECORD;
BEGIN
    -- Get mentee's profile
    SELECT
        COALESCE(mp.languages, ARRAY['en']::TEXT[]) AS languages,
        COALESCE(mp.timezone, 'UTC') AS timezone,
        COALESCE(mp.availability_hours_week, 2) AS needed_hours
    INTO mentee_profile
    FROM mentorship_profiles mp
    WHERE mp.user_id = p_user_id;

    -- Use defaults if no profile exists
    IF mentee_profile IS NULL THEN
        mentee_profile := ROW(ARRAY['en']::TEXT[], 'UTC', 2);
    END IF;

    RETURN QUERY
    WITH mentor_candidates AS (
        SELECT
            mp.user_id AS mentor_user_id,
            mp.id AS profile_id,
            mp.bio,
            mp.expertise_areas,
            mp.languages,
            mp.mentorship_style,
            mp.availability_hours_week,
            mp.avg_rating,
            mp.total_mentorships,
            mp.timezone AS mentor_timezone,
            (
                SELECT COUNT(*)
                FROM mentorship_matches mm
                WHERE mm.mentor_id = mp.user_id
                AND mm.status IN ('pending', 'accepted', 'active')
            ) AS active_mentees
        FROM mentorship_profiles mp
        WHERE mp.is_mentor_available = true
        AND mp.verified = true
        AND mp.training_completed = true
        AND mp.user_id != p_user_id
        -- Filter by expertise overlap
        AND mp.expertise_areas && p_seeking_areas
    )
    SELECT
        mc.mentor_user_id,
        mc.profile_id,
        mc.bio,
        mc.expertise_areas,
        mc.languages,
        mc.mentorship_style,
        mc.availability_hours_week,
        mc.avg_rating,
        mc.total_mentorships,
        scores.total_score AS compatibility_score,
        scores.expertise_score AS expertise_match_score,
        scores.language_score AS language_match_score,
        scores.timezone_score AS timezone_match_score,
        scores.availability_score AS availability_match_score,
        scores.match_reason
    FROM mentor_candidates mc
    CROSS JOIN LATERAL calculate_mentor_match_score(
        p_seeking_areas,
        mc.expertise_areas,
        mentee_profile.languages,
        mc.languages,
        mentee_profile.timezone,
        mc.mentor_timezone,
        mc.availability_hours_week,
        mentee_profile.needed_hours
    ) AS scores
    WHERE mc.active_mentees < mc.availability_hours_week / 2 -- Rough capacity check
    ORDER BY scores.total_score DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create a mentorship match request
CREATE OR REPLACE FUNCTION create_mentorship_request(
    p_mentor_id UUID,
    p_introduction_message TEXT
) RETURNS UUID AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_match_id UUID;
    v_mentor_alias TEXT;
    v_mentee_alias TEXT;
    mentee_profile RECORD;
    mentor_profile RECORD;
    score_result RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF v_user_id = p_mentor_id THEN
        RAISE EXCEPTION 'Cannot mentor yourself';
    END IF;

    -- Check mentor is available and verified
    SELECT * INTO mentor_profile
    FROM mentorship_profiles
    WHERE user_id = p_mentor_id
    AND is_mentor_available = true
    AND verified = true
    AND training_completed = true;

    IF mentor_profile IS NULL THEN
        RAISE EXCEPTION 'Mentor not available';
    END IF;

    -- Check for existing active match
    IF EXISTS (
        SELECT 1 FROM mentorship_matches
        WHERE mentor_id = p_mentor_id AND mentee_id = v_user_id
        AND status IN ('pending', 'accepted', 'active')
    ) THEN
        RAISE EXCEPTION 'Match already exists';
    END IF;

    -- Get mentee profile
    SELECT * INTO mentee_profile
    FROM mentorship_profiles
    WHERE user_id = v_user_id;

    -- Calculate match score
    SELECT * INTO score_result
    FROM calculate_mentor_match_score(
        COALESCE(mentee_profile.seeking_areas, ARRAY[]::TEXT[]),
        mentor_profile.expertise_areas,
        COALESCE(mentee_profile.languages, ARRAY['en']::TEXT[]),
        mentor_profile.languages,
        COALESCE(mentee_profile.timezone, 'UTC'),
        mentor_profile.timezone,
        mentor_profile.availability_hours_week,
        COALESCE(mentee_profile.availability_hours_week, 2)
    );

    -- Generate aliases
    v_mentor_alias := generate_mentorship_alias();
    v_mentee_alias := generate_mentorship_alias();

    -- Ensure unique aliases
    WHILE v_mentor_alias = v_mentee_alias LOOP
        v_mentee_alias := generate_mentorship_alias();
    END LOOP;

    -- Create the match
    INSERT INTO mentorship_matches (
        mentor_id,
        mentee_id,
        status,
        compatibility_score,
        match_reason,
        expertise_match_score,
        language_match_score,
        timezone_match_score,
        availability_match_score,
        introduction_message,
        mentor_alias,
        mentee_alias
    )
    VALUES (
        p_mentor_id,
        v_user_id,
        'pending',
        score_result.total_score,
        score_result.match_reason,
        score_result.expertise_score,
        score_result.language_score,
        score_result.timezone_score,
        score_result.availability_score,
        p_introduction_message,
        v_mentor_alias,
        v_mentee_alias
    )
    RETURNING id INTO v_match_id;

    RETURN v_match_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Accept or decline a mentorship request (for mentors)
CREATE OR REPLACE FUNCTION respond_to_mentorship_request(
    p_match_id UUID,
    p_accept BOOLEAN,
    p_response_message TEXT DEFAULT NULL
) RETURNS BOOLEAN AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_match RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Get the match
    SELECT * INTO v_match
    FROM mentorship_matches
    WHERE id = p_match_id
    AND mentor_id = v_user_id
    AND status = 'pending';

    IF v_match IS NULL THEN
        RAISE EXCEPTION 'Match not found or not authorized';
    END IF;

    IF p_accept THEN
        UPDATE mentorship_matches
        SET
            status = 'active',
            mentor_response = p_response_message,
            started_at = NOW(),
            updated_at = NOW()
        WHERE id = p_match_id;

        -- Update mentor stats
        UPDATE mentorship_profiles
        SET
            total_mentorships = total_mentorships + 1,
            updated_at = NOW()
        WHERE user_id = v_user_id;
    ELSE
        UPDATE mentorship_matches
        SET
            status = 'declined',
            mentor_response = p_response_message,
            ended_at = NOW(),
            end_reason = 'declined',
            updated_at = NOW()
        WHERE id = p_match_id;
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- End a mentorship
CREATE OR REPLACE FUNCTION end_mentorship(
    p_match_id UUID,
    p_reason TEXT DEFAULT 'completed'
) RETURNS BOOLEAN AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    UPDATE mentorship_matches
    SET
        status = 'ended',
        ended_at = NOW(),
        end_reason = p_reason,
        updated_at = NOW()
    WHERE id = p_match_id
    AND (mentor_id = v_user_id OR mentee_id = v_user_id)
    AND status = 'active';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Match not found or not authorized';
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get user's mentorship matches
CREATE OR REPLACE FUNCTION get_my_mentorship_matches()
RETURNS SETOF mentorship_matches AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    RETURN QUERY
    SELECT *
    FROM mentorship_matches
    WHERE mentor_id = v_user_id OR mentee_id = v_user_id
    ORDER BY
        CASE WHEN status = 'active' THEN 1
             WHEN status = 'pending' THEN 2
             ELSE 3
        END,
        updated_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Upsert mentorship profile
CREATE OR REPLACE FUNCTION upsert_mentorship_profile(
    p_is_mentor_available BOOLEAN DEFAULT NULL,
    p_expertise_areas TEXT[] DEFAULT NULL,
    p_seeking_areas TEXT[] DEFAULT NULL,
    p_bio TEXT DEFAULT NULL,
    p_availability_hours_week INTEGER DEFAULT NULL,
    p_languages TEXT[] DEFAULT NULL,
    p_timezone TEXT DEFAULT NULL,
    p_mentorship_style TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_profile_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    INSERT INTO mentorship_profiles (
        user_id,
        is_mentor_available,
        expertise_areas,
        seeking_areas,
        bio,
        availability_hours_week,
        languages,
        timezone,
        mentorship_style
    )
    VALUES (
        v_user_id,
        COALESCE(p_is_mentor_available, false),
        COALESCE(p_expertise_areas, ARRAY[]::TEXT[]),
        COALESCE(p_seeking_areas, ARRAY[]::TEXT[]),
        p_bio,
        COALESCE(p_availability_hours_week, 2),
        COALESCE(p_languages, ARRAY['en']::TEXT[]),
        COALESCE(p_timezone, 'UTC'),
        COALESCE(p_mentorship_style, 'supportive')
    )
    ON CONFLICT (user_id) DO UPDATE
    SET
        is_mentor_available = COALESCE(p_is_mentor_available, mentorship_profiles.is_mentor_available),
        expertise_areas = COALESCE(p_expertise_areas, mentorship_profiles.expertise_areas),
        seeking_areas = COALESCE(p_seeking_areas, mentorship_profiles.seeking_areas),
        bio = COALESCE(p_bio, mentorship_profiles.bio),
        availability_hours_week = COALESCE(p_availability_hours_week, mentorship_profiles.availability_hours_week),
        languages = COALESCE(p_languages, mentorship_profiles.languages),
        timezone = COALESCE(p_timezone, mentorship_profiles.timezone),
        mentorship_style = COALESCE(p_mentorship_style, mentorship_profiles.mentorship_style),
        updated_at = NOW()
    RETURNING id INTO v_profile_id;

    RETURN v_profile_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update mentorship messages last interaction
CREATE OR REPLACE FUNCTION update_mentorship_match_interaction()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE mentorship_matches
    SET updated_at = NOW()
    WHERE id = NEW.match_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_mentorship_message_interaction ON mentorship_messages;
CREATE TRIGGER trg_mentorship_message_interaction
    AFTER INSERT ON mentorship_messages
    FOR EACH ROW
    EXECUTE FUNCTION update_mentorship_match_interaction();

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION generate_mentorship_alias() TO authenticated;
GRANT EXECUTE ON FUNCTION calculate_timezone_overlap(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION calculate_mentor_match_score(TEXT[], TEXT[], TEXT[], TEXT[], TEXT, TEXT, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION find_mentor_matches(UUID, TEXT[], INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION create_mentorship_request(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION respond_to_mentorship_request(UUID, BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION end_mentorship(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_my_mentorship_matches() TO authenticated;
GRANT EXECUTE ON FUNCTION upsert_mentorship_profile(BOOLEAN, TEXT[], TEXT[], TEXT, INTEGER, TEXT[], TEXT, TEXT) TO authenticated;

-- Comments
COMMENT ON TABLE mentorship_profiles IS 'User profiles for mentor/mentee preferences and availability';
COMMENT ON TABLE mentorship_matches IS 'Records of mentor-mentee matches with compatibility scores';
COMMENT ON TABLE mentorship_messages IS 'Secure messaging between matched mentors and mentees';
COMMENT ON TABLE mentorship_reports IS 'Safety reports for mentorship interactions';
COMMENT ON FUNCTION find_mentor_matches(UUID, TEXT[], INTEGER) IS 'Find compatible mentors for a user based on expertise, language, timezone, and availability';
COMMENT ON FUNCTION create_mentorship_request(UUID, TEXT) IS 'Create a new mentorship request to a mentor';
