-- Migration: RLS helper functions for couples mode
-- Purpose: Support RLS policies and premium tier logic
-- Status: CRITICAL PATH - Foundation

-- Helper 1: Check if user has active premium subscription
CREATE OR REPLACE FUNCTION user_has_premium(user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    has_active_premium BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM subscriptions
        WHERE subscriptions.user_id = $1
        AND status = 'active'
        AND (cancel_at IS NULL OR cancel_at > now())
    ) INTO has_active_premium;
    
    RETURN COALESCE(has_active_premium, false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper 2: Get active partner ID for current user (NULL if no active partner)
CREATE OR REPLACE FUNCTION get_active_partner_id()
RETURNS UUID AS $$
DECLARE
    partner_id UUID;
BEGIN
    SELECT 
        CASE 
            WHEN user_id_1 = auth.uid() THEN user_id_2
            WHEN user_id_2 = auth.uid() THEN user_id_1
        END
    INTO partner_id
    FROM partner_links
    WHERE status = 'active'
    AND (user_id_1 = auth.uid() OR user_id_2 = auth.uid())
    LIMIT 1;
    
    RETURN partner_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper 3: Check if user has active partner
CREATE OR REPLACE FUNCTION user_has_active_partner()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN get_active_partner_id() IS NOT NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper 4: Check if current user is in an active partnership with specific user
CREATE OR REPLACE FUNCTION is_partner_with(other_user_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    is_partnered BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM partner_links
        WHERE status = 'active'
        AND (
            (user_id_1 = auth.uid() AND user_id_2 = $1)
            OR (user_id_2 = auth.uid() AND user_id_1 = $1)
        )
    ) INTO is_partnered;
    
    RETURN COALESCE(is_partnered, false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper 5: Check if current user's partner has enabled mood sharing
CREATE OR REPLACE FUNCTION partner_sharing_mood()
RETURNS BOOLEAN AS $$
DECLARE
    partner_shares_mood BOOLEAN;
    current_user_id UUID := auth.uid();
BEGIN
    SELECT 
        CASE 
            WHEN user_id_1 = current_user_id THEN user_2_share_mood
            WHEN user_id_2 = current_user_id THEN user_1_share_mood
        END
    INTO partner_shares_mood
    FROM partner_links
    WHERE status = 'active'
    AND (user_id_1 = current_user_id OR user_id_2 = current_user_id);
    
    RETURN COALESCE(partner_shares_mood, false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper 6: Check if current user's partner has enabled exercise sharing
CREATE OR REPLACE FUNCTION partner_sharing_exercises()
RETURNS BOOLEAN AS $$
DECLARE
    partner_shares_exercises BOOLEAN;
    current_user_id UUID := auth.uid();
BEGIN
    SELECT 
        CASE 
            WHEN user_id_1 = current_user_id THEN user_2_share_exercises
            WHEN user_id_2 = current_user_id THEN user_1_share_exercises
        END
    INTO partner_shares_exercises
    FROM partner_links
    WHERE status = 'active'
    AND (user_id_1 = current_user_id OR user_id_2 = current_user_id);
    
    RETURN COALESCE(partner_shares_exercises, false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper 7: Check if user or their partner has premium subscription (for exercise access)
CREATE OR REPLACE FUNCTION user_or_partner_has_premium()
RETURNS BOOLEAN AS $$
DECLARE
    current_user_id UUID := auth.uid();
    partner_id UUID;
    current_has_premium BOOLEAN;
    partner_has_premium BOOLEAN;
BEGIN
    -- Check current user's premium status
    current_has_premium := user_has_premium(current_user_id);
    
    IF current_has_premium THEN
        RETURN true;
    END IF;
    
    -- Check partner's premium status if partnered
    partner_id := get_active_partner_id();
    IF partner_id IS NOT NULL THEN
        partner_has_premium := user_has_premium(partner_id);
        RETURN partner_has_premium;
    END IF;
    
    RETURN false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper 8: Get count of active invites created by user in last 24 hours
CREATE OR REPLACE FUNCTION count_invites_24h()
RETURNS BIGINT AS $$
DECLARE
    invite_count BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO invite_count
    FROM partner_links
    WHERE created_by = auth.uid()
    AND status = 'pending'
    AND created_at > (now() - interval '24 hours');
    
    RETURN COALESCE(invite_count, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper 9: Get count of appreciation messages sent by user in last 24 hours
CREATE OR REPLACE FUNCTION count_appreciations_24h()
RETURNS BIGINT AS $$
DECLARE
    message_count BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO message_count
    FROM appreciation_messages
    WHERE from_user_id = auth.uid()
    AND created_at > (now() - interval '24 hours');
    
    RETURN COALESCE(message_count, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper 10: Verify invite code (returns partner_link_id or NULL)
CREATE OR REPLACE FUNCTION verify_invite_code(code_hash VARCHAR(64))
RETURNS UUID AS $$
DECLARE
    link_id UUID;
BEGIN
    SELECT id
    INTO link_id
    FROM partner_links
    WHERE invite_code_hash = $1
    AND status = 'pending'
    AND expires_at > now()
    AND user_id_2 IS NULL
    LIMIT 1;
    
    RETURN link_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper 11: Check if user is already in active partnership
CREATE OR REPLACE FUNCTION user_already_partnered()
RETURNS BOOLEAN AS $$
DECLARE
    is_partnered BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM partner_links
        WHERE status = 'active'
        AND (user_id_1 = auth.uid() OR user_id_2 = auth.uid())
        AND user_id_2 IS NOT NULL
    ) INTO is_partnered;
    
    RETURN COALESCE(is_partnered, false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper 12: Get partner link ID for current user (if active partnership exists)
CREATE OR REPLACE FUNCTION get_active_partner_link_id()
RETURNS UUID AS $$
DECLARE
    link_id UUID;
BEGIN
    SELECT id
    INTO link_id
    FROM partner_links
    WHERE status = 'active'
    AND (user_id_1 = auth.uid() OR user_id_2 = auth.uid())
    AND user_id_2 IS NOT NULL
    LIMIT 1;
    
    RETURN link_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Validate that partner_links, couples_exercises, couples_exercise_sessions, and appreciation_messages exist
-- (These tables are created in prior migrations and referenced here)

-- Grant appropriate permissions on helper functions to authenticated role
GRANT EXECUTE ON FUNCTION user_has_premium(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_active_partner_id() TO authenticated;
GRANT EXECUTE ON FUNCTION user_has_active_partner() TO authenticated;
GRANT EXECUTE ON FUNCTION is_partner_with(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION partner_sharing_mood() TO authenticated;
GRANT EXECUTE ON FUNCTION partner_sharing_exercises() TO authenticated;
GRANT EXECUTE ON FUNCTION user_or_partner_has_premium() TO authenticated;
GRANT EXECUTE ON FUNCTION count_invites_24h() TO authenticated;
GRANT EXECUTE ON FUNCTION count_appreciations_24h() TO authenticated;
GRANT EXECUTE ON FUNCTION verify_invite_code(VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION user_already_partnered() TO authenticated;
GRANT EXECUTE ON FUNCTION get_active_partner_link_id() TO authenticated;
