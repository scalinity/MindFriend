-- Security fixes for mentorship matching feature
-- Addresses: authorization bypass, race conditions, rate limiting, indexes

-- =============================================================================
-- FIX 1: Authorization bypass in find_mentor_matches
-- The function now validates that p_user_id matches auth.uid()
-- =============================================================================

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
    v_auth_uid UUID := auth.uid();
BEGIN
    -- SECURITY: Validate caller is authorized
    IF v_auth_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- SECURITY: Prevent querying matches for other users
    IF v_auth_uid != p_user_id THEN
        RAISE EXCEPTION 'Not authorized to query matches for this user';
    END IF;

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
            mp.max_active_mentees,
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
    -- FIXED: Use max_active_mentees instead of rough calculation
    WHERE mc.active_mentees < mc.max_active_mentees
    ORDER BY scores.total_score DESC
    LIMIT LEAST(p_limit, 10); -- Cap at 10 for safety
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- FIX 2: Race condition in create_mentorship_request
-- Uses advisory lock and handles unique constraint errors
-- =============================================================================

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
    v_lock_key BIGINT;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF v_user_id = p_mentor_id THEN
        RAISE EXCEPTION 'Cannot mentor yourself';
    END IF;

    -- SECURITY: Validate introduction message length
    IF length(p_introduction_message) < 20 THEN
        RAISE EXCEPTION 'Introduction message too short';
    END IF;

    IF length(p_introduction_message) > 1000 THEN
        RAISE EXCEPTION 'Introduction message too long';
    END IF;

    -- FIX: Use advisory lock to prevent race conditions
    -- Hash the mentor_id + mentee_id combo for a unique lock key
    v_lock_key := hashtext(p_mentor_id::TEXT || v_user_id::TEXT);

    -- Wait for lock (blocks other concurrent requests for same pair)
    PERFORM pg_advisory_xact_lock(v_lock_key);

    -- Check mentor is available and verified
    SELECT * INTO mentor_profile
    FROM mentorship_profiles
    WHERE user_id = p_mentor_id
    AND is_mentor_available = true
    AND verified = true
    AND training_completed = true
    FOR UPDATE; -- Lock the mentor profile row

    IF mentor_profile IS NULL THEN
        RAISE EXCEPTION 'Mentor not available';
    END IF;

    -- Check for existing active match (now safe with lock)
    IF EXISTS (
        SELECT 1 FROM mentorship_matches
        WHERE mentor_id = p_mentor_id AND mentee_id = v_user_id
        AND status IN ('pending', 'accepted', 'active')
    ) THEN
        RAISE EXCEPTION 'Match already exists';
    END IF;

    -- Check mentor capacity
    IF (
        SELECT COUNT(*) FROM mentorship_matches
        WHERE mentor_id = p_mentor_id
        AND status IN ('pending', 'accepted', 'active')
    ) >= mentor_profile.max_active_mentees THEN
        RAISE EXCEPTION 'Mentor at capacity';
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

EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Match already exists';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================================================
-- FIX 3: Add message rate limiting function
-- =============================================================================

CREATE OR REPLACE FUNCTION check_message_rate_limit(
    p_match_id UUID
) RETURNS BOOLEAN AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_message_count INTEGER;
    v_max_per_minute INTEGER := 5; -- Max 5 messages per minute
    v_max_per_hour INTEGER := 60; -- Max 60 messages per hour
BEGIN
    IF v_user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Check per-minute rate
    SELECT COUNT(*) INTO v_message_count
    FROM mentorship_messages
    WHERE sender_id = v_user_id
    AND match_id = p_match_id
    AND sent_at > NOW() - INTERVAL '1 minute';

    IF v_message_count >= v_max_per_minute THEN
        RETURN FALSE;
    END IF;

    -- Check per-hour rate
    SELECT COUNT(*) INTO v_message_count
    FROM mentorship_messages
    WHERE sender_id = v_user_id
    AND match_id = p_match_id
    AND sent_at > NOW() - INTERVAL '1 hour';

    IF v_message_count >= v_max_per_hour THEN
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION check_message_rate_limit(UUID) TO authenticated;

-- =============================================================================
-- FIX 4: Add message content sanitization trigger
-- =============================================================================

CREATE OR REPLACE FUNCTION sanitize_mentorship_message()
RETURNS TRIGGER AS $$
BEGIN
    -- Sanitize HTML/script tags to prevent XSS
    NEW.content := regexp_replace(NEW.content, '<[^>]*>', '', 'g');

    -- Remove potential script injections
    NEW.content := regexp_replace(NEW.content, 'javascript:', '', 'gi');
    NEW.content := regexp_replace(NEW.content, 'on\w+\s*=', '', 'gi');

    -- Trim and limit length
    NEW.content := trim(NEW.content);
    IF length(NEW.content) > 2000 THEN
        NEW.content := substring(NEW.content FROM 1 FOR 2000);
    END IF;

    -- Empty messages not allowed
    IF NEW.content = '' THEN
        RAISE EXCEPTION 'Message content cannot be empty';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sanitize_mentorship_message ON mentorship_messages;
CREATE TRIGGER trg_sanitize_mentorship_message
    BEFORE INSERT ON mentorship_messages
    FOR EACH ROW
    EXECUTE FUNCTION sanitize_mentorship_message();

-- =============================================================================
-- FIX 5: Add RLS policy for rate-limited message inserts
-- =============================================================================

DROP POLICY IF EXISTS "Match participants can send messages" ON mentorship_messages;

CREATE POLICY "Match participants can send rate-limited messages" ON mentorship_messages
    FOR INSERT WITH CHECK (
        auth.uid() = sender_id
        AND match_id IN (
            SELECT id FROM mentorship_matches
            WHERE status = 'active'
            AND (mentor_id = auth.uid() OR mentee_id = auth.uid())
        )
        AND check_message_rate_limit(match_id)
    );

-- =============================================================================
-- FIX 6: Add performance indexes
-- =============================================================================

-- Index for rate limit checks
CREATE INDEX IF NOT EXISTS idx_mentorship_messages_rate_limit
    ON mentorship_messages(sender_id, match_id, sent_at DESC);

-- Index for mentor capacity checks
CREATE INDEX IF NOT EXISTS idx_mentorship_matches_mentor_active
    ON mentorship_matches(mentor_id)
    WHERE status IN ('pending', 'accepted', 'active');

-- Index for mentee active matches
CREATE INDEX IF NOT EXISTS idx_mentorship_matches_mentee_active
    ON mentorship_matches(mentee_id)
    WHERE status IN ('pending', 'accepted', 'active');

-- Composite index for match lookups
CREATE INDEX IF NOT EXISTS idx_mentorship_matches_pair_status
    ON mentorship_matches(mentor_id, mentee_id, status);

-- Index for profile matching query
CREATE INDEX IF NOT EXISTS idx_mentorship_profiles_matching
    ON mentorship_profiles(is_mentor_available, verified, training_completed)
    WHERE is_mentor_available = true AND verified = true AND training_completed = true;

-- =============================================================================
-- FIX 7: Improve timezone calculation to handle edge cases
-- =============================================================================

CREATE OR REPLACE FUNCTION calculate_timezone_overlap(
    tz1 TEXT,
    tz2 TEXT
) RETURNS DECIMAL(3,2) AS $$
DECLARE
    offset1 INTERVAL;
    offset2 INTERVAL;
    diff_hours DECIMAL;
BEGIN
    -- Handle null/empty timezones
    IF tz1 IS NULL OR tz1 = '' THEN
        tz1 := 'UTC';
    END IF;
    IF tz2 IS NULL OR tz2 = '' THEN
        tz2 := 'UTC';
    END IF;

    -- Validate timezone names
    BEGIN
        offset1 := (NOW() AT TIME ZONE tz1) - (NOW() AT TIME ZONE 'UTC');
        offset2 := (NOW() AT TIME ZONE tz2) - (NOW() AT TIME ZONE 'UTC');
    EXCEPTION WHEN OTHERS THEN
        -- Invalid timezone, use default
        RETURN 0.5;
    END;

    -- Calculate hour difference
    diff_hours := ABS(EXTRACT(EPOCH FROM (offset1 - offset2)) / 3600);

    -- Handle wrap-around (12 hours max difference)
    IF diff_hours > 12 THEN
        diff_hours := 24 - diff_hours;
    END IF;

    -- Score based on hour difference (0 diff = 1.0, 12 diff = 0)
    RETURN GREATEST(0, 1.0 - (diff_hours / 12));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- =============================================================================
-- FIX 8: Add secure send message function with rate limiting
-- =============================================================================

CREATE OR REPLACE FUNCTION send_mentorship_message(
    p_match_id UUID,
    p_content TEXT
) RETURNS UUID AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_message_id UUID;
    v_match RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Validate content
    IF p_content IS NULL OR trim(p_content) = '' THEN
        RAISE EXCEPTION 'Message content required';
    END IF;

    IF length(p_content) > 2000 THEN
        RAISE EXCEPTION 'Message too long (max 2000 characters)';
    END IF;

    -- Check user is participant in active match
    SELECT * INTO v_match
    FROM mentorship_matches
    WHERE id = p_match_id
    AND status = 'active'
    AND (mentor_id = v_user_id OR mentee_id = v_user_id);

    IF v_match IS NULL THEN
        RAISE EXCEPTION 'Match not found or not active';
    END IF;

    -- Check rate limit
    IF NOT check_message_rate_limit(p_match_id) THEN
        RAISE EXCEPTION 'Rate limit exceeded. Please wait before sending more messages.';
    END IF;

    -- Insert message (trigger will sanitize)
    INSERT INTO mentorship_messages (
        match_id,
        sender_id,
        content
    )
    VALUES (
        p_match_id,
        v_user_id,
        p_content
    )
    RETURNING id INTO v_message_id;

    RETURN v_message_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION send_mentorship_message(UUID, TEXT) TO authenticated;

-- =============================================================================
-- FIX 9: Add data retention policy (messages older than 1 year)
-- =============================================================================

CREATE OR REPLACE FUNCTION cleanup_old_mentorship_data()
RETURNS INTEGER AS $$
DECLARE
    v_deleted_count INTEGER := 0;
BEGIN
    -- Delete messages from ended/completed matches older than 1 year
    WITH deleted AS (
        DELETE FROM mentorship_messages
        WHERE match_id IN (
            SELECT id FROM mentorship_matches
            WHERE status IN ('completed', 'ended', 'declined')
            AND ended_at < NOW() - INTERVAL '1 year'
        )
        RETURNING id
    )
    SELECT COUNT(*) INTO v_deleted_count FROM deleted;

    -- Archive old matches (keep metadata, remove sensitive data)
    UPDATE mentorship_matches
    SET
        introduction_message = '[archived]',
        mentor_response = '[archived]'
    WHERE status IN ('completed', 'ended', 'declined')
    AND ended_at < NOW() - INTERVAL '1 year'
    AND introduction_message != '[archived]';

    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Schedule cleanup (requires pg_cron extension)
-- SELECT cron.schedule('cleanup-mentorship-data', '0 3 * * 0', 'SELECT cleanup_old_mentorship_data()');

COMMENT ON FUNCTION cleanup_old_mentorship_data() IS 'Data retention: cleans up mentorship messages older than 1 year from ended matches';

-- =============================================================================
-- Update permissions
-- =============================================================================

GRANT EXECUTE ON FUNCTION find_mentor_matches(UUID, TEXT[], INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION create_mentorship_request(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION calculate_timezone_overlap(TEXT, TEXT) TO authenticated;
