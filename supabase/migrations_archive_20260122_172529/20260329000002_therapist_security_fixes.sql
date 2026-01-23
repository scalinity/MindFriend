-- Therapist Marketplace - Security Fixes
-- Addresses P0 critical vulnerabilities identified in code review:
-- 1. RLS UPDATE policy allows users to modify sensitive fields (verified, application_status)
-- 2. Storage bucket policy allows any authenticated user to modify any file

-- =============================================================================
-- FIX #1: Trigger to protect sensitive columns from user modification
-- =============================================================================

-- Create a function that prevents users from modifying sensitive fields
CREATE OR REPLACE FUNCTION protect_therapist_sensitive_fields()
RETURNS TRIGGER AS $$
BEGIN
    -- Only allow admins (service role) to modify these sensitive fields
    -- Regular users (authenticated via RLS) cannot change them

    -- Check if any sensitive field is being changed
    IF (OLD.verified IS DISTINCT FROM NEW.verified) OR
       (OLD.verified_at IS DISTINCT FROM NEW.verified_at) OR
       (OLD.background_check_passed IS DISTINCT FROM NEW.background_check_passed) OR
       (OLD.application_status IS DISTINCT FROM NEW.application_status) OR
       (OLD.rating_average IS DISTINCT FROM NEW.rating_average) OR
       (OLD.rating_count IS DISTINCT FROM NEW.rating_count) OR
       (OLD.sessions_completed IS DISTINCT FROM NEW.sessions_completed) THEN

        -- Check if this is being called via service role (admin)
        -- Service role bypasses RLS, so we check the current_setting
        IF current_setting('request.jwt.claims', true)::jsonb->>'role' = 'service_role' THEN
            -- Admin operation - allow all changes
            RETURN NEW;
        END IF;

        -- Regular user trying to modify sensitive fields - block the changes
        -- Reset sensitive fields to their original values
        NEW.verified := OLD.verified;
        NEW.verified_at := OLD.verified_at;
        NEW.background_check_passed := OLD.background_check_passed;
        NEW.application_status := OLD.application_status;
        NEW.rating_average := OLD.rating_average;
        NEW.rating_count := OLD.rating_count;
        NEW.sessions_completed := OLD.sessions_completed;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing trigger if exists and create new one
DROP TRIGGER IF EXISTS protect_therapist_sensitive_fields_trigger ON therapist_profiles;

CREATE TRIGGER protect_therapist_sensitive_fields_trigger
    BEFORE UPDATE ON therapist_profiles
    FOR EACH ROW
    EXECUTE FUNCTION protect_therapist_sensitive_fields();

-- =============================================================================
-- FIX #2: Storage policies - enforce user-specific paths
-- =============================================================================

-- Drop existing permissive policies
DROP POLICY IF EXISTS "Therapists can upload own photo" ON storage.objects;
DROP POLICY IF EXISTS "Therapists can update own photo" ON storage.objects;
DROP POLICY IF EXISTS "Therapists can delete own photo" ON storage.objects;

-- Recreate with proper path-based ownership checks
-- Path format: {user_id}/photo.{extension}

-- Policy: Therapists can upload ONLY to their own path
CREATE POLICY "Therapists can upload own photo"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'therapist-photos'
        AND auth.uid() IS NOT NULL
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- Policy: Therapists can update ONLY their own photos
CREATE POLICY "Therapists can update own photo"
    ON storage.objects FOR UPDATE
    USING (
        bucket_id = 'therapist-photos'
        AND auth.uid() IS NOT NULL
        AND (storage.foldername(name))[1] = auth.uid()::text
    )
    WITH CHECK (
        bucket_id = 'therapist-photos'
        AND auth.uid() IS NOT NULL
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- Policy: Therapists can delete ONLY their own photos
CREATE POLICY "Therapists can delete own photo"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'therapist-photos'
        AND auth.uid() IS NOT NULL
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- =============================================================================
-- FIX #3: Add missing indexes for performance (from P1 review findings)
-- =============================================================================

-- Index for rate-based sorting (searching by price)
CREATE INDEX IF NOT EXISTS idx_therapist_profiles_rate_60_min
    ON therapist_profiles(rate_60_min ASC NULLS LAST)
    WHERE verified = true AND accepts_new_clients = true;

-- Index for created_at sorting (newest first)
CREATE INDEX IF NOT EXISTS idx_therapist_profiles_created_at
    ON therapist_profiles(created_at DESC);

-- Composite index for profile_type filtering with verification
CREATE INDEX IF NOT EXISTS idx_therapist_profiles_type_verified
    ON therapist_profiles(profile_type, verified)
    WHERE verified = true;

-- =============================================================================
-- COMMENTS for documentation
-- =============================================================================

COMMENT ON FUNCTION protect_therapist_sensitive_fields() IS
    'Security trigger that prevents regular users from modifying sensitive fields like verified, application_status, ratings, etc. Only service_role (admin) can modify these.';
