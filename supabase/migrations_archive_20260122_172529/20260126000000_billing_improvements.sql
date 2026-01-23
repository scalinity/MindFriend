-- Billing Improvements Migration
-- Adds atomic seat claiming, billing audit table, and fixes transaction safety

-- ============================================================================
-- Part 1: Billing Events Audit Table (P1-A1)
-- ============================================================================

CREATE TABLE IF NOT EXISTS billing_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type TEXT NOT NULL CHECK (event_type IN (
        'purchase_verified',
        'subscription_created',
        'subscription_renewed',
        'subscription_expired',
        'subscription_cancelled',
        'family_seat_claimed',
        'family_seat_released',
        'family_member_added',
        'family_member_removed',
        'invite_sent',
        'invite_accepted',
        'invite_expired'
    )),
    user_id UUID REFERENCES auth.users(id),
    subscription_id UUID REFERENCES subscriptions(id),
    family_id UUID REFERENCES family_groups(id),
    payload JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for billing_events
CREATE INDEX idx_billing_events_user_id ON billing_events(user_id);
CREATE INDEX idx_billing_events_event_type ON billing_events(event_type);
CREATE INDEX idx_billing_events_created_at ON billing_events(created_at DESC);
CREATE INDEX idx_billing_events_family_id ON billing_events(family_id) WHERE family_id IS NOT NULL;

-- RLS for billing_events (immutable - no updates/deletes)
ALTER TABLE billing_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own billing events" ON billing_events
    FOR SELECT USING (auth.uid() = user_id);

-- Service role can insert (Edge Functions use service role)
CREATE POLICY "Service role can insert billing events" ON billing_events
    FOR INSERT WITH CHECK (true);


-- ============================================================================
-- Part 2: Atomic Seat Claiming RPC (P0-P1)
-- ============================================================================

-- Atomic function to claim a family seat
-- Returns JSON with success status and message
CREATE OR REPLACE FUNCTION claim_family_seat(
    p_family_id UUID,
    p_user_id UUID,
    p_invited_email TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin_sub RECORD;
    v_existing_member RECORD;
    v_seats_available INT;
    v_result JSONB;
BEGIN
    -- Lock the admin subscription row for update to prevent race conditions
    SELECT *
    INTO v_admin_sub
    FROM subscriptions
    WHERE family_id = p_family_id
      AND is_family_admin = true
      AND status = 'active'
    FOR UPDATE;

    IF v_admin_sub IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Family subscription not found or inactive',
            'code', 'NO_ACTIVE_SUBSCRIPTION'
        );
    END IF;

    -- Calculate available seats
    v_seats_available := v_admin_sub.seats_total - v_admin_sub.seats_used;

    IF v_seats_available <= 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'No seats available in this family plan',
            'code', 'NO_SEATS_AVAILABLE',
            'seats_used', v_admin_sub.seats_used,
            'seats_total', v_admin_sub.seats_total
        );
    END IF;

    -- Check if user is already an active member
    SELECT *
    INTO v_existing_member
    FROM family_members
    WHERE family_id = p_family_id
      AND user_id = p_user_id
      AND status = 'active';

    IF v_existing_member IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'User is already an active member of this family',
            'code', 'ALREADY_MEMBER'
        );
    END IF;

    -- Atomically increment seats_used
    UPDATE subscriptions
    SET seats_used = seats_used + 1,
        updated_at = now()
    WHERE id = v_admin_sub.id
      AND seats_used < seats_total;  -- Double-check constraint

    IF NOT FOUND THEN
        -- Race condition occurred - another request claimed the last seat
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Seat was claimed by another request',
            'code', 'SEAT_RACE_CONDITION'
        );
    END IF;

    -- Check for existing inactive member to reactivate
    SELECT *
    INTO v_existing_member
    FROM family_members
    WHERE family_id = p_family_id
      AND user_id = p_user_id;

    IF v_existing_member IS NOT NULL THEN
        -- Reactivate existing membership
        UPDATE family_members
        SET status = 'active',
            joined_at = now(),
            removed_at = NULL
        WHERE id = v_existing_member.id;
    ELSE
        -- Create new family member
        INSERT INTO family_members (family_id, user_id, invited_email, status, joined_at)
        VALUES (p_family_id, p_user_id, p_invited_email, 'active', now());
    END IF;

    -- Log the event
    INSERT INTO billing_events (event_type, user_id, family_id, payload)
    VALUES (
        'family_seat_claimed',
        p_user_id,
        p_family_id,
        jsonb_build_object(
            'seats_used', v_admin_sub.seats_used + 1,
            'seats_total', v_admin_sub.seats_total,
            'admin_subscription_id', v_admin_sub.id
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Seat claimed successfully',
        'seats_used', v_admin_sub.seats_used + 1,
        'seats_total', v_admin_sub.seats_total,
        'admin_subscription_id', v_admin_sub.id
    );
END;
$$;


-- Atomic function to release a family seat
CREATE OR REPLACE FUNCTION release_family_seat(
    p_family_id UUID,
    p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin_sub RECORD;
    v_member RECORD;
BEGIN
    -- Lock the admin subscription row for update
    SELECT *
    INTO v_admin_sub
    FROM subscriptions
    WHERE family_id = p_family_id
      AND is_family_admin = true
    FOR UPDATE;

    IF v_admin_sub IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Family subscription not found',
            'code', 'NO_SUBSCRIPTION'
        );
    END IF;

    -- Find the member
    SELECT *
    INTO v_member
    FROM family_members
    WHERE family_id = p_family_id
      AND user_id = p_user_id
      AND status = 'active';

    IF v_member IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'User is not an active member of this family',
            'code', 'NOT_A_MEMBER'
        );
    END IF;

    -- Mark member as removed
    UPDATE family_members
    SET status = 'removed',
        removed_at = now()
    WHERE id = v_member.id;

    -- Decrement seats_used (but don't go below 1 - admin always counts)
    UPDATE subscriptions
    SET seats_used = GREATEST(1, seats_used - 1),
        updated_at = now()
    WHERE id = v_admin_sub.id;

    -- Log the event
    INSERT INTO billing_events (event_type, user_id, family_id, payload)
    VALUES (
        'family_seat_released',
        p_user_id,
        p_family_id,
        jsonb_build_object(
            'seats_used', GREATEST(1, v_admin_sub.seats_used - 1),
            'seats_total', v_admin_sub.seats_total
        )
    );

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Seat released successfully',
        'seats_used', GREATEST(1, v_admin_sub.seats_used - 1),
        'seats_total', v_admin_sub.seats_total
    );
END;
$$;


-- ============================================================================
-- Part 3: Fix Transaction Safety in Revoke Trigger (P1-A2)
-- ============================================================================

-- Drop and recreate the trigger function with proper transaction safety
CREATE OR REPLACE FUNCTION revoke_family_premium_on_expiry()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_member RECORD;
BEGIN
    -- Only act when an admin subscription becomes inactive/expired
    IF NEW.is_family_admin = true
       AND OLD.status = 'active'
       AND NEW.status IN ('expired', 'cancelled', 'inactive') THEN

        -- Use advisory lock to prevent concurrent modifications
        PERFORM pg_advisory_xact_lock(hashtext('family_revoke_' || NEW.family_id::text));

        -- Revoke premium for all non-admin family members
        FOR v_member IN
            SELECT fm.user_id, fm.id as member_id
            FROM family_members fm
            WHERE fm.family_id = NEW.family_id
              AND fm.user_id != NEW.user_id
              AND fm.status = 'active'
        LOOP
            -- Update member's subscription status
            UPDATE subscriptions
            SET status = 'expired',
                expires_at = now(),
                updated_at = now()
            WHERE user_id = v_member.user_id
              AND family_id = NEW.family_id
              AND is_family_admin = false;

            -- Downgrade member's profile
            UPDATE profiles
            SET subscription_tier = 'free',
                daily_ai_quota = 20
            WHERE id = v_member.user_id;

            -- Log the event
            INSERT INTO billing_events (event_type, user_id, family_id, subscription_id, payload)
            VALUES (
                'subscription_expired',
                v_member.user_id,
                NEW.family_id,
                NEW.id,
                jsonb_build_object(
                    'reason', 'admin_subscription_expired',
                    'admin_user_id', NEW.user_id
                )
            );
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$;

-- Ensure trigger exists
DROP TRIGGER IF EXISTS tr_revoke_family_premium ON subscriptions;
CREATE TRIGGER tr_revoke_family_premium
    AFTER UPDATE ON subscriptions
    FOR EACH ROW
    EXECUTE FUNCTION revoke_family_premium_on_expiry();


-- ============================================================================
-- Part 4: Additional Constraints and Indexes (P2)
-- ============================================================================

-- Add constraint to ensure seats_used <= seats_total
ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS chk_seats_used_lte_total;
ALTER TABLE subscriptions ADD CONSTRAINT chk_seats_used_lte_total
    CHECK (seats_used <= seats_total OR seats_total = 0);

-- Add composite index for family member lookups
CREATE INDEX IF NOT EXISTS idx_family_members_family_status
    ON family_members(family_id, status);

-- Add index for subscription lookups by family
CREATE INDEX IF NOT EXISTS idx_subscriptions_family_admin
    ON subscriptions(family_id, is_family_admin) WHERE family_id IS NOT NULL;


-- ============================================================================
-- Part 5: Grant Permissions
-- ============================================================================

-- Allow Edge Functions to call the atomic RPC functions
GRANT EXECUTE ON FUNCTION claim_family_seat(UUID, UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION release_family_seat(UUID, UUID) TO service_role;

-- Allow authenticated users to read billing_events for their own records
GRANT SELECT ON billing_events TO authenticated;
GRANT INSERT ON billing_events TO service_role;
