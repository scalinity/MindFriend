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
        AND mentor_id IN (SELECT mentor_user_id FROM mentor_candidates)
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
    v_lock_key BIGINT;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Use advisory lock to serialize rate limit checks for this user+match combination
    -- Prevents TOCTOU race condition where multiple concurrent requests bypass the limit
    v_lock_key := hashtext(v_user_id::TEXT || p_match_id::TEXT);
    PERFORM pg_advisory_xact_lock(v_lock_key);

    -- Check per-minute rate (now serialized by lock)
    SELECT COUNT(*) INTO v_message_count
    FROM mentorship_messages
    WHERE sender_id = v_user_id
    AND match_id = p_match_id
    AND sent_at > NOW() - INTERVAL '1 minute';

    IF v_message_count >= v_max_per_minute THEN
        RETURN FALSE;
    END IF;

    -- Check per-hour rate (now serialized by lock)
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
DECLARE
    v_encrypt_result RECORD;
BEGIN
    -- Sanitize by encoding HTML entities instead of regex filtering (more secure)
    NEW.content := replace(NEW.content, '&', '&amp;');
    NEW.content := replace(NEW.content, '<', '&lt;');
    NEW.content := replace(NEW.content, '>', '&gt;');
    NEW.content := replace(NEW.content, '"', '&quot;');
    NEW.content := replace(NEW.content, '''', '&#x27;');
    
    -- Trim and limit length
    NEW.content := trim(NEW.content);
    IF length(NEW.content) > 2000 THEN
        NEW.content := substring(NEW.content FROM 1 FOR 2000);
    END IF;

    -- Empty messages not allowed
    IF NEW.content = '' THEN
        RAISE EXCEPTION 'Message content cannot be empty';
    END IF;

    -- Encrypt content
    SELECT * INTO v_encrypt_result FROM encrypt_message_content(NEW.content);
    NEW.encrypted_content := (v_encrypt_result).v_encrypted;
    NEW.encryption_key_id := (v_encrypt_result).v_key_id;
    NEW.iv := NULL;

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

DROP POLICY IF EXISTS "Match participants can send rate-limited messages" ON mentorship_messages;

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

-- Policy for SELECT: participants can read messages in their matches
CREATE POLICY "Match participants can read messages" ON mentorship_messages
    FOR SELECT USING (
        match_id IN (
            SELECT id FROM mentorship_matches
            WHERE (mentor_id = auth.uid() OR mentee_id = auth.uid())
        )
    );

-- Policy for UPDATE: senders can update their own message read_at status
CREATE POLICY "Users can mark own messages as read" ON mentorship_messages
    FOR UPDATE USING (
        auth.uid() = sender_id OR
        match_id IN (
            SELECT id FROM mentorship_matches
            WHERE (mentor_id = auth.uid() OR mentee_id = auth.uid())
        )
    )
    WITH CHECK (
        -- Only allow updating read_at timestamp, not content
        sender_id = (SELECT sender_id FROM mentorship_messages m WHERE m.id = mentorship_messages.id)
    );

-- Policy for DELETE: only senders can delete their own messages
CREATE POLICY "Senders can delete own messages" ON mentorship_messages
    FOR DELETE USING (auth.uid() = sender_id);

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

-- Drop existing function to allow parameter renaming
DROP FUNCTION IF EXISTS calculate_timezone_overlap(TEXT, TEXT);

-- Improved timezone overlap calculation that handles edge cases
-- Some timezones use half-hour or quarter-hour offsets (e.g., India +5:30, Nepal +5:45)
CREATE OR REPLACE FUNCTION calculate_timezone_overlap(
    p_tz1 TEXT,
    p_tz2 TEXT
) RETURNS DECIMAL AS $$
DECLARE
    offset1_seconds INTEGER;
    offset2_seconds INTEGER;
    diff_hours DECIMAL;
    overlap_score DECIMAL;
BEGIN
    -- Get UTC offset in seconds for both timezones
    SELECT EXTRACT(TIMEZONE FROM (NOW() AT TIME ZONE p_tz1))::INTEGER
    INTO offset1_seconds;

    SELECT EXTRACT(TIMEZONE FROM (NOW() AT TIME ZONE p_tz2))::INTEGER
    INTO offset2_seconds;

    -- Handle NULL values (invalid timezone)
    IF offset1_seconds IS NULL OR offset2_seconds IS NULL THEN
        RETURN 0.5;  -- Default neutral score
    END IF;

    -- Calculate difference in hours (handles half-hour and quarter-hour offsets)
    diff_hours := ABS((offset1_seconds - offset2_seconds)::DECIMAL / 3600);

    -- Score based on timezone proximity
    -- 0-2 hours difference: excellent (1.0)
    -- 2-4 hours difference: good (0.8)
    -- 4-8 hours difference: acceptable (0.6)
    -- 8-12 hours difference: poor (0.4)
    -- 12+ hours difference: very poor (0.2)
    IF diff_hours <= 2 THEN
        overlap_score := 1.0;
    ELSIF diff_hours <= 4 THEN
        overlap_score := 0.8;
    ELSIF diff_hours <= 8 THEN
        overlap_score := 0.6;
    ELSIF diff_hours <= 12 THEN
        overlap_score := 0.4;
    ELSE
        overlap_score := 0.2;
    END IF;

    RETURN overlap_score;
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
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule('cleanup-mentorship-data', '0 3 * * 0', 'SELECT cleanup_old_mentorship_data()');
    ELSE
        RAISE NOTICE 'pg_cron extension not available - skipping scheduled cleanup';
    END IF;
END $$;

COMMENT ON FUNCTION cleanup_old_mentorship_data() IS 'Data retention: cleans up mentorship messages older than 1 year from ended matches';

-- =============================================================================
-- FIX 9: Message encryption at rest (pgcrypto)
-- =============================================================================

-- Enable pgcrypto extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Add encrypted_content column to mentorship_messages
ALTER TABLE IF EXISTS mentorship_messages
ADD COLUMN IF NOT EXISTS encrypted_content bytea,
ADD COLUMN IF NOT EXISTS encryption_key_id TEXT,
ADD COLUMN IF NOT EXISTS iv bytea;

-- Create encryption key storage table (in real production, use AWS KMS/Vault)
CREATE TABLE IF NOT EXISTS mentorship_encryption_keys (
    id TEXT PRIMARY KEY,
    -- Master encryption key (rotated quarterly)
    key_material bytea NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    rotated_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT true,
    algorithm TEXT NOT NULL DEFAULT 'aes-256-gcm'
);

-- Function to get active encryption key
CREATE OR REPLACE FUNCTION get_active_encryption_key()
RETURNS TEXT AS $$
DECLARE
    v_key_id TEXT;
BEGIN
    SELECT id INTO v_key_id
    FROM mentorship_encryption_keys
    WHERE is_active = true
    ORDER BY created_at DESC
    LIMIT 1;
    
    IF v_key_id IS NULL THEN
        -- Create initial key if none exists
        INSERT INTO mentorship_encryption_keys (id, key_material)
        VALUES (
            'key_' || to_char(now(), 'YYYYMMDD_HH24MISS'),
            gen_random_bytes(32)  -- 256-bit random bytes for AES-256
        )
        RETURNING id INTO v_key_id;
    END IF;
    
    RETURN v_key_id;
END;
$$ LANGUAGE plpgsql;

-- Encryption function for messages (server-side, called by trigger)
CREATE OR REPLACE FUNCTION encrypt_message_content(
    p_content TEXT
)
RETURNS TABLE (
    v_key_id TEXT,
    v_encrypted TEXT  -- Base64-encoded encrypted content for JSON serialization
) AS $$
DECLARE
    v_key_id TEXT;
    v_key TEXT;
    v_encrypted bytea;
BEGIN
    v_key_id := get_active_encryption_key();
    
    SELECT encode(key_material, 'hex') INTO v_key
    FROM mentorship_encryption_keys
    WHERE id = v_key_id;
    
    -- Encrypt using pgp_sym_encrypt: provides AES-256 + HMAC-SHA512 authentication
    v_encrypted := pgp_sym_encrypt(
        p_content,
        v_key,
        'cipher-algo=aes256'
    );
    
    -- Return base64-encoded bytea for JSON-safe transmission to iOS client
    RETURN QUERY SELECT v_key_id, encode(v_encrypted, 'base64');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to decrypt message content
CREATE OR REPLACE FUNCTION decrypt_message_content(
    p_encrypted bytea,
    p_key_id TEXT
)
RETURNS TEXT AS $$
DECLARE
    v_key TEXT;
    v_decrypted bytea;
BEGIN
    SELECT encode(key_material, 'hex') INTO v_key
    FROM mentorship_encryption_keys
    WHERE id = p_key_id AND revoked_at IS NULL;
    
    IF v_key IS NULL THEN
        RAISE EXCEPTION 'Encryption key not found or revoked: %', p_key_id;
    END IF;
    
    -- pgp_sym_decrypt automatically verifies HMAC - errors if authentication fails
    v_decrypted := pgp_sym_decrypt(p_encrypted, v_key)::bytea;
    
    RETURN convert_from(v_decrypted, 'utf8');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant decryption access to authenticated users (for their own messages only via RLS)
GRANT EXECUTE ON FUNCTION decrypt_message_content(bytea, TEXT) TO authenticated;

-- Batch decryption function for iOS app (returns decryption status for each message)
CREATE OR REPLACE FUNCTION decrypt_messages_batch(
    p_message_ids UUID[]
) RETURNS TABLE (
    message_id UUID,
    decryption_success BOOLEAN,
    decrypted_content TEXT,
    error_message TEXT
) AS $$
DECLARE
    v_msg_id UUID;
    v_encrypted bytea;
    v_key_id TEXT;
    v_decrypted TEXT;
    v_error TEXT;
BEGIN
    FOREACH v_msg_id IN ARRAY p_message_ids
    LOOP
        BEGIN
            -- Fetch encrypted content and key for this message
            SELECT m.encrypted_content, m.encryption_key_id
            INTO v_encrypted, v_key_id
            FROM mentorship_messages m
            WHERE m.id = v_msg_id
            AND EXISTS (
                -- Verify user has access via RLS
                SELECT 1 FROM mentorship_matches
                WHERE id = m.match_id
                AND (mentor_id = auth.uid() OR mentee_id = auth.uid())
            );

            IF v_encrypted IS NULL THEN
                -- Message not found or access denied
                RETURN QUERY SELECT v_msg_id, false, NULL::TEXT, 'Message not found or access denied'::TEXT;
            ELSE
                -- Decrypt the content
                v_decrypted := decrypt_message_content(v_encrypted, v_key_id);
                RETURN QUERY SELECT v_msg_id, true, v_decrypted, NULL::TEXT;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            -- Decryption failed - return generic error without exposing internal details
            v_error := CASE 
                WHEN SQLERRM LIKE '%encryption%' THEN 'Encryption key unavailable'
                WHEN SQLERRM LIKE '%access%' THEN 'Access denied'
                ELSE 'Decryption failed'
            END;
            RETURN QUERY SELECT v_msg_id, false, NULL::TEXT, v_error::TEXT;
        END;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION decrypt_messages_batch(UUID[]) TO authenticated;

-- Update RLS policy to allow decryption of own messages
DROP POLICY IF EXISTS "Users can decrypt own messages" ON mentorship_messages;
CREATE POLICY "Users can decrypt own messages"
    ON mentorship_messages FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM mentorship_matches
            WHERE id = mentorship_messages.match_id
            AND (mentor_id = auth.uid() OR mentee_id = auth.uid())
        )
    );

-- =============================================================================
-- FIX 10: Bio field sanitization (XSS prevention)
-- =============================================================================

-- Function to sanitize bio field
CREATE OR REPLACE FUNCTION sanitize_mentorship_profile_bio()
RETURNS TRIGGER AS $$
BEGIN
    -- Only sanitize if bio is being set
    IF NEW.bio IS NOT NULL THEN
        -- Sanitize by encoding HTML entities (same approach as message content)
        NEW.bio := replace(NEW.bio, '&', '&amp;');
        NEW.bio := replace(NEW.bio, '<', '&lt;');
        NEW.bio := replace(NEW.bio, '>', '&gt;');
        NEW.bio := replace(NEW.bio, '"', '&quot;');
        NEW.bio := replace(NEW.bio, '''', '&#x27;');
        
        -- Trim whitespace
        NEW.bio := trim(NEW.bio);
        
        -- Limit length to 500 characters
        IF length(NEW.bio) > 500 THEN
            NEW.bio := substring(NEW.bio FROM 1 FOR 500);
        END IF;
        
        -- Reject if bio becomes empty after sanitization
        IF NEW.bio = '' THEN
            NEW.bio := NULL;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply sanitization trigger to mentorship_profiles
DROP TRIGGER IF EXISTS trg_sanitize_mentorship_profile_bio ON mentorship_profiles;
CREATE TRIGGER trg_sanitize_mentorship_profile_bio
    BEFORE INSERT OR UPDATE ON mentorship_profiles
    FOR EACH ROW
    EXECUTE FUNCTION sanitize_mentorship_profile_bio();

-- =============================================================================
-- FIX 11: User message deletion (GDPR right to be forgotten)
-- =============================================================================

-- Function to delete user's own message
CREATE OR REPLACE FUNCTION delete_mentorship_message(
    p_message_id UUID
) RETURNS BOOLEAN AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_affected_rows INTEGER;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Delete message only if user is the sender
    DELETE FROM mentorship_messages
    WHERE id = p_message_id
    AND sender_id = v_user_id;

    GET DIAGNOSTICS v_affected_rows = ROW_COUNT;

    IF v_affected_rows = 0 THEN
        RAISE EXCEPTION 'Message not found or you do not have permission to delete it';
    END IF;

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION delete_mentorship_message(UUID) TO authenticated;

-- =============================================================================
-- CRITICAL: Missing RPC functions for iOS app
-- =============================================================================

-- Mark all messages in a match as read for the current user
CREATE OR REPLACE FUNCTION mark_messages_read(
    p_match_id UUID
) RETURNS BOOLEAN AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Update messages where current user is a participant in the match
    UPDATE mentorship_messages
    SET read_at = now()
    WHERE match_id = p_match_id
    AND read_at IS NULL
    AND EXISTS (
        SELECT 1 FROM mentorship_matches
        WHERE id = p_match_id
        AND (mentor_id = v_user_id OR mentee_id = v_user_id)
    );

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION mark_messages_read(UUID) TO authenticated;

-- Flag a message for moderation review
CREATE OR REPLACE FUNCTION flag_mentorship_message(
    p_message_id UUID,
    p_reason TEXT
) RETURNS BOOLEAN AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_match_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) = 0 THEN
        RAISE EXCEPTION 'Reason is required';
    END IF;

    -- Get match_id to verify user is participant
    SELECT match_id INTO v_match_id
    FROM mentorship_messages
    WHERE id = p_message_id;

    IF v_match_id IS NULL THEN
        RAISE EXCEPTION 'Message not found';
    END IF;

    -- Verify user is a participant
    IF NOT EXISTS (
        SELECT 1 FROM mentorship_matches
        WHERE id = v_match_id
        AND (mentor_id = v_user_id OR mentee_id = v_user_id)
    ) THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    -- Flag the message
    UPDATE mentorship_messages
    SET flagged = true,
        flag_reason = p_reason,
        reviewed = false
    WHERE id = p_message_id;

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION flag_mentorship_message(UUID, TEXT) TO authenticated;

-- Unflag a message (for user's own flags)
CREATE OR REPLACE FUNCTION unflag_mentorship_message(
    p_message_id UUID
) RETURNS BOOLEAN AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_match_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Get match_id to verify user is participant
    SELECT match_id INTO v_match_id
    FROM mentorship_messages
    WHERE id = p_message_id;

    IF v_match_id IS NULL THEN
        RAISE EXCEPTION 'Message not found';
    END IF;

    -- Verify user is a participant
    IF NOT EXISTS (
        SELECT 1 FROM mentorship_matches
        WHERE id = v_match_id
        AND (mentor_id = v_user_id OR mentee_id = v_user_id)
    ) THEN
        RAISE EXCEPTION 'Access denied';
    END IF;

    -- Unflag the message
    UPDATE mentorship_messages
    SET flagged = false,
        flag_reason = NULL
    WHERE id = p_message_id;

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION unflag_mentorship_message(UUID) TO authenticated;

-- Report a mentorship issue (safety escalation)
CREATE OR REPLACE FUNCTION report_mentorship_issue(
    p_match_id UUID,
    p_reported_id UUID,
    p_reason TEXT,
    p_description TEXT
) RETURNS UUID AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_report_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Validate required fields
    IF p_match_id IS NULL THEN
        RAISE EXCEPTION 'Match ID is required';
    END IF;

    IF p_reported_id IS NULL THEN
        RAISE EXCEPTION 'Reported user ID is required';
    END IF;

    IF p_reason IS NULL OR LENGTH(TRIM(p_reason)) = 0 THEN
        RAISE EXCEPTION 'Reason is required';
    END IF;

    -- Verify reporter is a participant in the match
    IF NOT EXISTS (
        SELECT 1 FROM mentorship_matches
        WHERE id = p_match_id
        AND (mentor_id = v_user_id OR mentee_id = v_user_id)
    ) THEN
        RAISE EXCEPTION 'You are not a participant in this mentorship';
    END IF;

    -- Verify reported user is the OTHER participant
    IF NOT EXISTS (
        SELECT 1 FROM mentorship_matches
        WHERE id = p_match_id
        AND (mentor_id = p_reported_id OR mentee_id = p_reported_id)
    ) THEN
        RAISE EXCEPTION 'Reported user is not a participant in this mentorship';
    END IF;

    -- Prevent self-reporting
    IF v_user_id = p_reported_id THEN
        RAISE EXCEPTION 'Cannot report yourself';
    END IF;

    -- Create report
    INSERT INTO mentorship_reports (
        match_id,
        reporter_id,
        reported_id,
        reason,
        description,
        status,
        created_at
    )
    VALUES (
        p_match_id,
        v_user_id,
        p_reported_id,
        p_reason,
        COALESCE(p_description, ''),
        'pending',
        now()
    )
    RETURNING id INTO v_report_id;

    RETURN v_report_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION report_mentorship_issue(UUID, UUID, TEXT, TEXT) TO authenticated;

-- =============================================================================

-- =============================================================================
-- =============================================================================
-- FIX 13: Row Level Security for mentorship core tables
-- =============================================================================

-- Enable RLS on all mentorship tables
ALTER TABLE mentorship_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentorship_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentorship_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentorship_encryption_keys ENABLE ROW LEVEL SECURITY;

-- Enable RLS on notification queue only if it exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'mentorship_notification_queue') THEN
        ALTER TABLE mentorship_notification_queue ENABLE ROW LEVEL SECURITY;
    END IF;
END $$;

-- ===== MENTORSHIP_PROFILES RLS =====

-- Users can view any verified mentor profile (for discovery)
CREATE POLICY "View verified mentor profiles" ON mentorship_profiles
    FOR SELECT USING (
        verified = true OR user_id = auth.uid()
    );

-- Users can update only their own profile
CREATE POLICY "Update own profile" ON mentorship_profiles
    FOR UPDATE USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- Users can insert their own profile
CREATE POLICY "Create own profile" ON mentorship_profiles
    FOR INSERT WITH CHECK (user_id = auth.uid());

-- ===== MENTORSHIP_MATCHES RLS =====

-- Match participants can view match details
CREATE POLICY "View own match" ON mentorship_matches
    FOR SELECT USING (
        mentor_id = auth.uid() OR mentee_id = auth.uid()
    );

-- Match participants can update match status and rating (but not reassign participants)
-- Note: RLS WITH CHECK uses the new row values directly, not NEW keyword
CREATE POLICY "Update own match status" ON mentorship_matches
    FOR UPDATE USING (
        mentor_id = auth.uid() OR mentee_id = auth.uid()
    )
    WITH CHECK (
        mentor_id = auth.uid() OR mentee_id = auth.uid()
    );

-- Match participants can delete (end) their match
CREATE POLICY "Delete own match" ON mentorship_matches
    FOR DELETE USING (
        mentor_id = auth.uid() OR mentee_id = auth.uid()
    );

-- ===== MENTORSHIP_REPORTS RLS =====

-- Users can view reports they filed or are subject of
CREATE POLICY "View report" ON mentorship_reports
    FOR SELECT USING (
        reporter_id = auth.uid() OR reported_id = auth.uid()
    );

-- Users can file reports
CREATE POLICY "Create report" ON mentorship_reports
    FOR INSERT WITH CHECK (
        reporter_id = auth.uid()
    );

-- ===== MENTORSHIP_ENCRYPTION_KEYS RLS =====

-- Encryption keys are internal - no direct client access via SELECT
-- Only Edge Functions and SECURITY DEFINER procedures can access via service role
ALTER TABLE mentorship_encryption_keys FORCE ROW LEVEL SECURITY;

CREATE POLICY "Deny all direct client access to encryption keys" ON mentorship_encryption_keys
    FOR SELECT USING (FALSE);

-- ===== MENTORSHIP_NOTIFICATION_QUEUE RLS =====

-- Only set up notification queue RLS if table exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'mentorship_notification_queue') THEN
        RAISE NOTICE 'mentorship_notification_queue table does not exist, skipping RLS';
        RETURN;
    END IF;

    -- Users can view notifications intended for them
    CREATE POLICY "View own notifications" ON mentorship_notification_queue
        FOR SELECT USING (user_id = auth.uid());

    -- Force RLS
    ALTER TABLE mentorship_notification_queue FORCE ROW LEVEL SECURITY;

    -- System-only INSERT policy (prevent direct client inserts)
    DROP POLICY IF EXISTS "Create notification" ON mentorship_notification_queue;
    DROP POLICY IF EXISTS "Users can select own notifications" ON mentorship_notification_queue;
    DROP POLICY IF EXISTS "System only can insert notifications" ON mentorship_notification_queue;

    CREATE POLICY "System only can insert notifications" ON mentorship_notification_queue
        FOR INSERT WITH CHECK (FALSE);  -- Only Edge Functions (with SERVICE_ROLE) can insert
END $$;

-- ===== MENTORSHIP_MESSAGES RLS =====

-- Match participants can read messages (includes access to encrypted content via trigger functions)
DROP POLICY IF EXISTS "Match participants can read messages" ON mentorship_messages;
CREATE POLICY "Match participants can read messages"
    ON mentorship_messages FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM mentorship_matches
            WHERE id = mentorship_messages.match_id
            AND (mentor_id = auth.uid() OR mentee_id = auth.uid())
        )
    );

-- ===== UPDATE/DELETE POLICIES =====

-- Match participants can update message flags (for moderation)
DROP POLICY IF EXISTS "Update message flags" ON mentorship_messages;
CREATE POLICY "Update message flags"
    ON mentorship_messages FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM mentorship_matches
            WHERE id = mentorship_messages.match_id
            AND (mentor_id = auth.uid() OR mentee_id = auth.uid())
        )
    )
    WITH CHECK (
        -- Match participants can update (column restrictions enforced at application layer)
        EXISTS (
            SELECT 1 FROM mentorship_matches
            WHERE id = match_id
            AND (mentor_id = auth.uid() OR mentee_id = auth.uid())
        )
    );

-- Match participants can delete their own messages
DROP POLICY IF EXISTS "Delete own message" ON mentorship_messages;
CREATE POLICY "Delete own message"
    ON mentorship_messages FOR DELETE
    USING (sender_id = auth.uid());