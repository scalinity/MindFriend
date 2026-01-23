-- Social Challenges & Leaderboards - Main Schema
-- Includes: challenges table, challenge_participants table, indexes, RLS policies, triggers, functions

-- Create enum for challenge types
CREATE TYPE challenge_type_enum AS ENUM ('streak', 'minutes', 'mood', 'quest');

-- Create challenges table
CREATE TABLE IF NOT EXISTS challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    challenge_type challenge_type_enum NOT NULL,
    target_value INTEGER NOT NULL,
    duration_days INTEGER NOT NULL DEFAULT 7,
    is_public BOOLEAN DEFAULT true,
    circle_id UUID REFERENCES circles(id) ON DELETE SET NULL,
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    exercise_type TEXT, -- For 'minutes' type challenges (breathing, meditation, grounding, journaling, movement)
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    finalized BOOLEAN DEFAULT false,
    finalized_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT valid_dates CHECK (ends_at > starts_at),
    CONSTRAINT valid_target CHECK (target_value > 0),
    CONSTRAINT valid_duration CHECK (duration_days > 0),
    CONSTRAINT exercise_type_required_for_minutes CHECK (
        challenge_type != 'minutes' OR exercise_type IS NOT NULL
    )
);

-- Create challenge_participants table with microsecond precision for tie-breaking
CREATE TABLE IF NOT EXISTS challenge_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenge_id UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    current_progress INTEGER DEFAULT 0,
    completed BOOLEAN DEFAULT false,
    completed_at TIMESTAMPTZ,
    final_rank INTEGER,
    show_on_leaderboard BOOLEAN DEFAULT true,
    joined_at TIMESTAMPTZ(6) DEFAULT NOW(), -- Microsecond precision for deterministic tie-breaking
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(challenge_id, user_id),
    CONSTRAINT valid_progress CHECK (current_progress >= 0)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_challenges_public_active 
    ON challenges(is_public, starts_at, ends_at);

CREATE INDEX IF NOT EXISTS idx_challenges_circle 
    ON challenges(circle_id, starts_at, ends_at);

CREATE INDEX IF NOT EXISTS idx_challenges_status 
    ON challenges(created_by, ends_at DESC);

CREATE INDEX IF NOT EXISTS idx_challenges_finalization 
    ON challenges(finalized, ends_at);

CREATE INDEX IF NOT EXISTS idx_challenge_participants_user 
    ON challenge_participants(user_id, challenge_id);

CREATE INDEX IF NOT EXISTS idx_leaderboard_query 
    ON challenge_participants(challenge_id, current_progress DESC, joined_at ASC, show_on_leaderboard);

-- Enable Row Level Security
ALTER TABLE challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE challenge_participants ENABLE ROW LEVEL SECURITY;

-- RLS Policies for challenges table
CREATE POLICY "Public challenges visible to all authenticated users"
    ON challenges FOR SELECT
    USING (
        auth.role() = 'authenticated' AND (
            is_public = true
            OR circle_id IN (
                SELECT circle_id FROM circle_members WHERE user_id = auth.uid()
            )
        )
    );

CREATE POLICY "Users can create challenges"
    ON challenges FOR INSERT
    WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Users can update their own challenges"
    ON challenges FOR UPDATE
    USING (auth.uid() = created_by)
    WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Only system can finalize challenges"
    ON challenges FOR UPDATE
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- RLS Policies for challenge_participants table
CREATE POLICY "Participants visible in public challenges"
    ON challenge_participants FOR SELECT
    USING (
        auth.role() = 'authenticated' AND (
            challenge_id IN (
                SELECT id FROM challenges WHERE is_public = true
            )
            OR challenge_id IN (
                SELECT c.id FROM challenges c 
                WHERE c.circle_id IN (
                    SELECT circle_id FROM circle_members WHERE user_id = auth.uid()
                )
            )
            OR user_id = auth.uid()
        )
    );

CREATE POLICY "Users can only see their own participation initially"
    ON challenge_participants FOR SELECT
    USING (
        auth.uid() = user_id
        OR challenge_id IN (
            SELECT id FROM challenges WHERE is_public = true
        )
        OR challenge_id IN (
            SELECT c.id FROM challenges c 
            WHERE c.circle_id IN (
                SELECT circle_id FROM circle_members WHERE user_id = auth.uid()
            )
        )
    );

CREATE POLICY "Users can join challenges"
    ON challenge_participants FOR INSERT
    WITH CHECK (
        auth.uid() = user_id
        AND challenge_id IN (
            SELECT id FROM challenges 
            WHERE (is_public = true OR circle_id IN (
                SELECT circle_id FROM circle_members WHERE user_id = auth.uid()
            ))
            AND ends_at > NOW()
        )
    );

CREATE POLICY "Users can update their own participation"
    ON challenge_participants FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id AND (
        SELECT ends_at FROM challenges WHERE id = challenge_id
    ) > NOW());

CREATE POLICY "Users can leave challenges"
    ON challenge_participants FOR DELETE
    USING (auth.uid() = user_id);

CREATE POLICY "System can update rankings and mark completed"
    ON challenge_participants FOR UPDATE
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- Function to calculate leaderboard with tie-breaking
CREATE OR REPLACE FUNCTION get_challenge_leaderboard(
    p_challenge_id UUID,
    p_user_id UUID,
    p_limit INT DEFAULT 50,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    rank_position INT,
    user_id UUID,
    user_display_name TEXT,
    user_avatar_url TEXT,
    current_progress INT,
    joined_at TIMESTAMPTZ,
    show_on_leaderboard BOOLEAN,
    is_tied BOOLEAN
) AS $$
DECLARE
    v_tie_threshold INTERVAL := INTERVAL '1 second';
    v_has_access BOOLEAN;
BEGIN
    -- Check if user has access to view this challenge leaderboard
    -- User has access if:
    -- 1. Challenge is public, OR
    -- 2. Challenge is in a circle the user is a member of, OR
    -- 3. User is a participant in the challenge
    SELECT EXISTS (
        SELECT 1 FROM challenges c
        WHERE c.id = p_challenge_id
        AND (
            c.is_public = true
            OR EXISTS (
                SELECT 1 FROM circle_members cm
                WHERE cm.circle_id = c.circle_id
                AND cm.user_id = p_user_id
            )
            OR EXISTS (
                SELECT 1 FROM challenge_participants cp
                WHERE cp.challenge_id = c.id
                AND cp.user_id = p_user_id
            )
        )
    ) INTO v_has_access;

    IF NOT v_has_access THEN
        RAISE EXCEPTION 'User does not have permission to view this leaderboard';
    END IF;

    RETURN QUERY
    WITH ranked_participants AS (
        SELECT
            cp.user_id,
            p.display_name AS user_display_name,
            p.avatar_url AS user_avatar_url,
            cp.current_progress,
            cp.joined_at,
            cp.show_on_leaderboard,
            ROW_NUMBER() OVER (
                ORDER BY cp.current_progress DESC, cp.joined_at ASC
            ) as rn,
            RANK() OVER (
                ORDER BY cp.current_progress DESC, 
                CASE 
                    WHEN LAG(cp.joined_at) OVER (ORDER BY cp.current_progress DESC, cp.joined_at ASC) 
                        IS NULL THEN cp.joined_at
                    WHEN LAG(cp.joined_at) OVER (ORDER BY cp.current_progress DESC, cp.joined_at ASC) 
                        > (cp.joined_at - v_tie_threshold) THEN cp.joined_at
                    ELSE LAG(cp.joined_at) OVER (ORDER BY cp.current_progress DESC, cp.joined_at ASC)
                END
            ) as tie_rank
        FROM challenge_participants cp
        JOIN profiles p ON cp.user_id = p.id
        WHERE cp.challenge_id = p_challenge_id
        AND cp.show_on_leaderboard = true
        ORDER BY cp.current_progress DESC, cp.joined_at ASC
    )
    SELECT
        tie_rank::INT,
        user_id,
        user_display_name,
        user_avatar_url,
        current_progress,
        joined_at,
        show_on_leaderboard,
        (LAG(current_progress) OVER (ORDER BY rn) = current_progress 
         OR LEAD(current_progress) OVER (ORDER BY rn) = current_progress)::BOOLEAN
    FROM ranked_participants
    WHERE rn > p_offset
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to check challenge creation rate limit (5 per day for free tier)
CREATE OR REPLACE FUNCTION check_challenge_creation_rate_limit(p_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_count INT;
    v_is_premium BOOLEAN;
BEGIN
    -- Check if user is premium
    SELECT (s.subscription_tier != 'free')
    INTO v_is_premium
    FROM subscriptions s
    WHERE s.user_id = p_user_id
    ORDER BY s.updated_at DESC
    LIMIT 1;

    -- If not premium, enforce 5 per day limit
    IF v_is_premium IS NOT TRUE THEN
        SELECT COUNT(*)
        INTO v_count
        FROM challenges
        WHERE created_by = p_user_id
        AND created_at > NOW() - INTERVAL '1 day';

        RETURN v_count < 5;
    END IF;

    -- Premium users have no limit
    RETURN true;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to check join/leave rate limit (10 per hour for free tier)
CREATE OR REPLACE FUNCTION check_join_rate_limit(p_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_count INT;
    v_is_premium BOOLEAN;
BEGIN
    -- Check if user is premium
    SELECT (s.subscription_tier != 'free')
    INTO v_is_premium
    FROM subscriptions s
    WHERE s.user_id = p_user_id
    ORDER BY s.updated_at DESC
    LIMIT 1;

    -- If not premium, enforce 10 per hour limit
    IF v_is_premium IS NOT TRUE THEN
        SELECT COUNT(*)
        INTO v_count
        FROM challenge_participants
        WHERE user_id = p_user_id
        AND joined_at > NOW() - INTERVAL '1 hour';

        RETURN v_count < 10;
    END IF;

    -- Premium users have no limit
    RETURN true;
END;
$$ LANGUAGE plpgsql STABLE;

-- Trigger function to update challenges.updated_at
CREATE OR REPLACE FUNCTION update_challenges_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_challenges_updated_at
    BEFORE UPDATE ON challenges
    FOR EACH ROW
    EXECUTE FUNCTION update_challenges_updated_at();

-- Trigger function to update challenge_participants.updated_at
CREATE OR REPLACE FUNCTION update_challenge_participants_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_challenge_participants_updated_at
    BEFORE UPDATE ON challenge_participants
    FOR EACH ROW
    EXECUTE FUNCTION update_challenge_participants_updated_at();

-- Trigger to update challenge progress on quest completion
CREATE OR REPLACE FUNCTION update_challenge_progress_on_quest()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.completed = true AND OLD.completed = false THEN
        UPDATE challenge_participants
        SET current_progress = CASE 
            WHEN c.challenge_type = 'quest' THEN current_progress + 1
            WHEN c.challenge_type = 'streak' THEN (
                SELECT COUNT(DISTINCT DATE(completed_at))
                FROM quests
                WHERE user_id = NEW.user_id 
                AND completed = true
                AND completed_at > NOW() - INTERVAL '7 days'
            )
            ELSE current_progress
        END
        FROM challenges c
        WHERE challenge_participants.challenge_id = c.id
        AND challenge_participants.user_id = NEW.user_id
        AND c.challenge_type IN ('quest', 'streak')
        AND c.ends_at > NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_quest_to_challenge_progress
    AFTER UPDATE ON quests
    FOR EACH ROW
    EXECUTE FUNCTION update_challenge_progress_on_quest();

-- Trigger to update challenge progress on mood logging
CREATE OR REPLACE FUNCTION update_challenge_progress_on_mood()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE challenge_participants
    SET current_progress = (
        SELECT COUNT(DISTINCT DATE(logged_at))
        FROM moods
        WHERE user_id = NEW.user_id
        AND logged_at > NOW() - INTERVAL '7 days'
    )
    WHERE challenge_id IN (
        SELECT id FROM challenges 
        WHERE challenge_type = 'mood' 
        AND ends_at > NOW()
    )
    AND user_id = NEW.user_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_mood_to_challenge_progress
    AFTER INSERT OR UPDATE ON moods
    FOR EACH ROW
    EXECUTE FUNCTION update_challenge_progress_on_mood();

-- Trigger to update challenge progress on exercise completion
CREATE OR REPLACE FUNCTION update_challenge_progress_on_exercise()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE challenge_participants
    SET current_progress = current_progress + NEW.duration_minutes
    WHERE challenge_id IN (
        SELECT c.id FROM challenges c
        WHERE c.challenge_type = 'minutes'
        AND c.exercise_type = (
            SELECT exercise_type FROM exercises WHERE id = NEW.exercise_id
        )
        AND c.ends_at > NOW()
    )
    AND user_id = NEW.user_id
    AND EXISTS (
        SELECT 1 FROM challenges c
        WHERE c.id = challenge_id
        AND c.exercise_type = (
            SELECT exercise_type FROM exercises WHERE id = NEW.exercise_id
        )
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_exercise_to_challenge_progress
    AFTER INSERT ON exercise_sessions
    FOR EACH ROW
    EXECUTE FUNCTION update_challenge_progress_on_exercise();

-- Batch RPC Functions to fix N+1 query patterns

-- Function to get public challenges with user participation and participant counts
CREATE OR REPLACE FUNCTION get_public_challenges_with_participation(p_user_id UUID)
RETURNS TABLE (
    id UUID,
    title TEXT,
    description TEXT,
    challenge_type challenge_type_enum,
    target_value INT,
    created_by UUID,
    circle_id UUID,
    is_public BOOLEAN,
    created_at TIMESTAMPTZ,
    starts_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ,
    exercise_type TEXT,
    user_participated BOOLEAN,
    user_current_progress INT,
    user_joined_at TIMESTAMPTZ,
    user_show_on_leaderboard BOOLEAN,
    participant_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id,
        c.title,
        c.description,
        c.challenge_type,
        c.target_value,
        c.created_by,
        c.circle_id,
        c.is_public,
        c.created_at,
        c.starts_at,
        c.ends_at,
        c.exercise_type,
        (cp.user_id IS NOT NULL) AS user_participated,
        COALESCE(cp.current_progress, 0) AS user_current_progress,
        cp.joined_at AS user_joined_at,
        COALESCE(cp.show_on_leaderboard, false) AS user_show_on_leaderboard,
        COALESCE(participant_counts.count, 0) AS participant_count
    FROM challenges c
    LEFT JOIN challenge_participants cp 
        ON c.id = cp.challenge_id AND cp.user_id = p_user_id
    LEFT JOIN LATERAL (
        SELECT COUNT(*) as count
        FROM challenge_participants
        WHERE challenge_id = c.id
    ) participant_counts ON true
    WHERE c.is_public = true
    AND c.ends_at > NOW();
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Function to get circle challenges with user participation and participant counts
CREATE OR REPLACE FUNCTION get_circle_challenges_with_participation(p_user_id UUID)
RETURNS TABLE (
    id UUID,
    title TEXT,
    description TEXT,
    challenge_type challenge_type_enum,
    target_value INT,
    created_by UUID,
    circle_id UUID,
    is_public BOOLEAN,
    created_at TIMESTAMPTZ,
    starts_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ,
    exercise_type TEXT,
    user_participated BOOLEAN,
    user_current_progress INT,
    user_joined_at TIMESTAMPTZ,
    user_show_on_leaderboard BOOLEAN,
    participant_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id,
        c.title,
        c.description,
        c.challenge_type,
        c.target_value,
        c.created_by,
        c.circle_id,
        c.is_public,
        c.created_at,
        c.starts_at,
        c.ends_at,
        c.exercise_type,
        (cp.user_id IS NOT NULL) AS user_participated,
        COALESCE(cp.current_progress, 0) AS user_current_progress,
        cp.joined_at AS user_joined_at,
        COALESCE(cp.show_on_leaderboard, false) AS user_show_on_leaderboard,
        COALESCE(participant_counts.count, 0) AS participant_count
    FROM challenges c
    INNER JOIN circle_members cm ON c.circle_id = cm.circle_id
    LEFT JOIN challenge_participants cp 
        ON c.id = cp.challenge_id AND cp.user_id = p_user_id
    LEFT JOIN LATERAL (
        SELECT COUNT(*) as count
        FROM challenge_participants
        WHERE challenge_id = c.id
    ) participant_counts ON true
    WHERE cm.user_id = p_user_id
    AND c.circle_id IS NOT NULL
    AND c.ends_at > NOW();
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Function to get joined challenges with full details
CREATE OR REPLACE FUNCTION get_joined_challenges_with_details(p_user_id UUID)
RETURNS TABLE (
    id UUID,
    title TEXT,
    description TEXT,
    challenge_type challenge_type_enum,
    target_value INT,
    created_by UUID,
    circle_id UUID,
    is_public BOOLEAN,
    created_at TIMESTAMPTZ,
    starts_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ,
    exercise_type TEXT,
    user_participated BOOLEAN,
    user_current_progress INT,
    user_joined_at TIMESTAMPTZ,
    user_show_on_leaderboard BOOLEAN,
    participant_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id,
        c.title,
        c.description,
        c.challenge_type,
        c.target_value,
        c.created_by,
        c.circle_id,
        c.is_public,
        c.created_at,
        c.starts_at,
        c.ends_at,
        c.exercise_type,
        true AS user_participated,
        cp.current_progress AS user_current_progress,
        cp.joined_at AS user_joined_at,
        cp.show_on_leaderboard AS user_show_on_leaderboard,
        COALESCE(participant_counts.count, 0) AS participant_count
    FROM challenges c
    INNER JOIN challenge_participants cp 
        ON c.id = cp.challenge_id
    LEFT JOIN LATERAL (
        SELECT COUNT(*) as count
        FROM challenge_participants
        WHERE challenge_id = c.id
    ) participant_counts ON true
    WHERE cp.user_id = p_user_id
    AND c.ends_at > NOW();
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
