-- Fix quota race condition with database constraint
-- Prevents TOCTOU vulnerability where multiple concurrent requests bypass quota

-- Add trigger to enforce quota atomically before insert
CREATE OR REPLACE FUNCTION enforce_capsule_quota()
RETURNS TRIGGER AS $$
DECLARE
    v_current_count INTEGER;
    v_current_storage BIGINT;
    v_max_count INTEGER;
    v_max_storage BIGINT;
    v_is_premium BOOLEAN;
BEGIN
    -- Get user's subscription tier
    SELECT
        COALESCE(s.tier = 'premium' AND s.status = 'active' AND s.expires_at > now(), false)
    INTO v_is_premium
    FROM subscriptions s
    WHERE s.user_id = NEW.user_id
    ORDER BY s.created_at DESC
    LIMIT 1;

    -- Set limits based on tier
    IF v_is_premium THEN
        v_max_count := 9999;  -- Effectively unlimited
        v_max_storage := 10737418240;  -- 10GB in bytes
    ELSE
        v_max_count := 5;
        v_max_storage := 104857600;  -- 100MB in bytes
    END IF;

    -- Get current usage with FOR UPDATE to prevent race condition
    SELECT
        COUNT(*),
        COALESCE(SUM(cm.file_size_bytes), 0)
    INTO v_current_count, v_current_storage
    FROM time_capsules tc
    LEFT JOIN capsule_media cm ON cm.capsule_id = tc.id
    WHERE tc.user_id = NEW.user_id
      AND tc.deleted_at IS NULL
    FOR UPDATE OF tc;  -- Lock rows to prevent concurrent inserts

    -- Check capsule count quota
    IF v_current_count >= v_max_count THEN
        RAISE EXCEPTION 'capsule_quota_exceeded: You have reached your capsule limit (% of %)',
            v_current_count, v_max_count
            USING ERRCODE = 'check_violation';
    END IF;

    -- Check storage quota
    IF v_current_storage >= v_max_storage THEN
        RAISE EXCEPTION 'storage_quota_exceeded: You have reached your storage limit (% of % bytes)',
            v_current_storage, v_max_storage
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if exists
DROP TRIGGER IF EXISTS enforce_capsule_quota_trigger ON time_capsules;

-- Create trigger that runs before insert
CREATE TRIGGER enforce_capsule_quota_trigger
    BEFORE INSERT ON time_capsules
    FOR EACH ROW
    EXECUTE FUNCTION enforce_capsule_quota();

-- Update check_capsule_quota to use the same logic (for pre-flight checks)
-- This provides user-friendly error messages before attempting insert
CREATE OR REPLACE FUNCTION check_capsule_quota(p_user_id UUID, p_file_size_bytes INTEGER DEFAULT 0)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_count INTEGER;
    v_current_storage BIGINT;
    v_max_count INTEGER;
    v_max_storage BIGINT;
    v_is_premium BOOLEAN;
    v_result JSONB;
BEGIN
    -- Get subscription tier
    SELECT
        COALESCE(s.tier = 'premium' AND s.status = 'active' AND s.expires_at > now(), false)
    INTO v_is_premium
    FROM subscriptions s
    WHERE s.user_id = p_user_id
    ORDER BY s.created_at DESC
    LIMIT 1;

    -- Set tier limits
    IF v_is_premium THEN
        v_max_count := 9999;
        v_max_storage := 10737418240;  -- 10GB
    ELSE
        v_max_count := 5;
        v_max_storage := 104857600;  -- 100MB
    END IF;

    -- Get current usage (read-only, no lock needed for pre-flight check)
    SELECT
        COUNT(*),
        COALESCE(SUM(cm.file_size_bytes), 0)
    INTO v_current_count, v_current_storage
    FROM time_capsules tc
    LEFT JOIN capsule_media cm ON cm.capsule_id = tc.id
    WHERE tc.user_id = p_user_id
      AND tc.deleted_at IS NULL;

    -- Build response
    v_result := jsonb_build_object(
        'allowed', true,
        'reason', null,
        'message', null,
        'max_count', v_max_count,
        'max_storage', v_max_storage,
        'current_count', v_current_count,
        'current_storage', v_current_storage
    );

    -- Check count quota
    IF v_current_count >= v_max_count THEN
        v_result := jsonb_build_object(
            'allowed', false,
            'reason', 'capsule_quota_exceeded',
            'message', format('You have reached your capsule limit (%s of %s). Upgrade to Premium for unlimited capsules.',
                v_current_count, v_max_count),
            'max_count', v_max_count,
            'max_storage', v_max_storage,
            'current_count', v_current_count,
            'current_storage', v_current_storage
        );
        RETURN v_result;
    END IF;

    -- Check storage quota (including this upload)
    IF (v_current_storage + p_file_size_bytes) > v_max_storage THEN
        v_result := jsonb_build_object(
            'allowed', false,
            'reason', 'storage_quota_exceeded',
            'message', format('This upload would exceed your storage limit. Used: %s MB of %s MB. Upgrade to Premium for 10GB storage.',
                round((v_current_storage + p_file_size_bytes)::numeric / 1048576, 1),
                round(v_max_storage::numeric / 1048576, 1)),
            'max_count', v_max_count,
            'max_storage', v_max_storage,
            'current_count', v_current_count,
            'current_storage', v_current_storage
        );
        RETURN v_result;
    END IF;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION enforce_capsule_quota() IS
'Trigger function that atomically enforces capsule quota before insert. Uses row-level locks to prevent race conditions.';

COMMENT ON FUNCTION check_capsule_quota(UUID, INTEGER) IS
'Pre-flight quota check for user-friendly error messages. Actual enforcement is done by enforce_capsule_quota trigger.';
