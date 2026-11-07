-- Qualify candidate identities so output parameters cannot shadow SQL columns.
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
            mp.max_active_mentees
        FROM mentorship_profiles mp
        WHERE mp.is_mentor_available = true
        AND mp.verified = true
        AND mp.training_completed = true
        AND mp.user_id != p_user_id
        -- Filter by expertise overlap
        AND mp.expertise_areas && p_seeking_areas
    ),
    mentor_capacity AS (
        -- Get active mentee count for each mentor in one query
        SELECT
            mentor_id,
            COUNT(*) AS active_mentees
        FROM mentorship_matches
        WHERE status IN ('pending', 'accepted', 'active')
        AND mentor_id IN (SELECT candidate.mentor_user_id FROM mentor_candidates candidate)
        GROUP BY mentor_id
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
    LEFT JOIN mentor_capacity cap ON mc.mentor_user_id = cap.mentor_id
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
    -- FIXED: Use max_active_mentees check with null-safe coalesce
    WHERE COALESCE(cap.active_mentees, 0) < mc.max_active_mentees
    ORDER BY scores.total_score DESC
    LIMIT LEAST(p_limit, 10); -- Cap at 10 for safety
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- AT TIME ZONE returns a wall-clock timestamp, not a value with a TIMEZONE field.
CREATE OR REPLACE FUNCTION public.calculate_timezone_overlap(p_tz1 text, p_tz2 text)
RETURNS decimal LANGUAGE plpgsql STABLE SET search_path = public, pg_temp AS $$
DECLARE diff_hours numeric;
BEGIN
    IF p_tz1 IS NULL OR p_tz2 IS NULL THEN RETURN 0.5; END IF;
    diff_hours := abs(extract(epoch FROM ((now() AT TIME ZONE p_tz1) - (now() AT TIME ZONE p_tz2))) / 3600);
    RETURN CASE WHEN diff_hours <= 2 THEN 1.0
                WHEN diff_hours <= 4 THEN 0.8
                WHEN diff_hours <= 8 THEN 0.6
                WHEN diff_hours <= 12 THEN 0.4
                ELSE 0.2 END;
EXCEPTION WHEN invalid_parameter_value THEN RETURN 0.5;
END;
$$;
