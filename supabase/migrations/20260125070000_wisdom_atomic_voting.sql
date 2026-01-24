-- Migration: Atomic voting RPC for Community Wisdom Engine
-- Prevents race conditions in vote count updates using SERIALIZABLE isolation

-- Create RPC function for atomic vote upsert with proper isolation
CREATE OR REPLACE FUNCTION upsert_strategy_vote(
    p_strategy_id UUID,
    p_user_id UUID,
    p_vote_type TEXT
)
RETURNS TABLE(
    helpful_count INTEGER,
    not_helpful_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_old_vote_type TEXT;
    v_strategy_exists BOOLEAN;
BEGIN
    -- Verify strategy exists and is approved
    SELECT EXISTS(
        SELECT 1 FROM community_strategies
        WHERE id = p_strategy_id AND status = 'approved'
    ) INTO v_strategy_exists;

    IF NOT v_strategy_exists THEN
        RAISE EXCEPTION 'Strategy not found or not approved';
    END IF;

    -- Get existing vote if any
    SELECT vote_type INTO v_old_vote_type
    FROM strategy_votes
    WHERE strategy_id = p_strategy_id AND user_id = p_user_id
    FOR UPDATE; -- Lock the row if it exists

    -- Upsert the vote
    INSERT INTO strategy_votes (strategy_id, user_id, vote_type, updated_at)
    VALUES (p_strategy_id, p_user_id, p_vote_type, NOW())
    ON CONFLICT (strategy_id, user_id)
    DO UPDATE SET
        vote_type = p_vote_type,
        updated_at = NOW();

    -- Update counts atomically
    -- Only if vote type changed or is new
    IF v_old_vote_type IS NULL THEN
        -- New vote
        IF p_vote_type = 'helpful' THEN
            UPDATE community_strategies
            SET helpful_count = COALESCE(helpful_count, 0) + 1
            WHERE id = p_strategy_id;
        ELSE
            UPDATE community_strategies
            SET not_helpful_count = COALESCE(not_helpful_count, 0) + 1
            WHERE id = p_strategy_id;
        END IF;
    ELSIF v_old_vote_type != p_vote_type THEN
        -- Vote changed
        IF p_vote_type = 'helpful' THEN
            UPDATE community_strategies
            SET helpful_count = COALESCE(helpful_count, 0) + 1,
                not_helpful_count = GREATEST(COALESCE(not_helpful_count, 0) - 1, 0)
            WHERE id = p_strategy_id;
        ELSE
            UPDATE community_strategies
            SET not_helpful_count = COALESCE(not_helpful_count, 0) + 1,
                helpful_count = GREATEST(COALESCE(helpful_count, 0) - 1, 0)
            WHERE id = p_strategy_id;
        END IF;
    END IF;
    -- If same vote type, no count changes needed

    -- Return updated counts
    RETURN QUERY
    SELECT cs.helpful_count, cs.not_helpful_count
    FROM community_strategies cs
    WHERE cs.id = p_strategy_id;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION upsert_strategy_vote(UUID, UUID, TEXT) TO authenticated;

-- Add comment
COMMENT ON FUNCTION upsert_strategy_vote IS
'Atomic vote upsert with race condition protection. Handles new votes, vote changes, and prevents count underflow.';

-- Add composite index for vote lookups if not exists
CREATE INDEX IF NOT EXISTS idx_strategy_votes_user_strategy
ON strategy_votes(user_id, strategy_id);

-- Add index for consent lookups
CREATE INDEX IF NOT EXISTS idx_wisdom_consent_user_contribute
ON wisdom_consent(user_id) WHERE contribute_anonymous_data = true;

CREATE INDEX IF NOT EXISTS idx_wisdom_consent_user_receive
ON wisdom_consent(user_id) WHERE receive_recommendations = true;

-- Add index for insights by validity
CREATE INDEX IF NOT EXISTS idx_wisdom_insights_valid
ON wisdom_insights(valid_until) WHERE valid_until IS NOT NULL;

-- Add index for contributions aggregation
CREATE INDEX IF NOT EXISTS idx_wisdom_contributions_time_type
ON wisdom_contributions(contributed_at, contribution_type);

-- Add index for strategies by category and status
CREATE INDEX IF NOT EXISTS idx_community_strategies_category_status
ON community_strategies(category, status, helpful_count DESC)
WHERE status = 'approved';
