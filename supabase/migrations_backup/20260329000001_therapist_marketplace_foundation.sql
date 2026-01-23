-- Therapist/Coach Marketplace - Phase 1: Foundation
-- Creates therapist profiles table, RLS policies, storage bucket, and indexes

-- =============================================================================
-- TABLE: therapist_profiles
-- =============================================================================

CREATE TABLE IF NOT EXISTS therapist_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
    profile_type TEXT NOT NULL CHECK (profile_type IN ('therapist', 'coach')),

    -- Professional info
    display_name TEXT NOT NULL,
    bio TEXT NOT NULL,
    photo_url TEXT,
    credentials TEXT[] NOT NULL DEFAULT '{}',
    specialties TEXT[] NOT NULL DEFAULT '{}',
    approaches TEXT[] DEFAULT '{}',
    languages TEXT[] NOT NULL DEFAULT ARRAY['English'],

    -- License (for therapists)
    license_number TEXT,
    license_state TEXT,

    -- Verification (Phase 1: manual admin approval via Supabase Dashboard)
    verified BOOLEAN NOT NULL DEFAULT false,
    verified_at TIMESTAMPTZ,
    background_check_passed BOOLEAN DEFAULT false,

    -- Application workflow
    application_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (application_status IN ('pending', 'approved', 'rejected')),
    application_submitted_at TIMESTAMPTZ DEFAULT NOW(),

    -- Rates (Phase 2+ for booking)
    rate_30_min DECIMAL(10,2),
    rate_45_min DECIMAL(10,2),
    rate_60_min DECIMAL(10,2),

    -- Settings
    accepts_new_clients BOOLEAN NOT NULL DEFAULT true,

    -- Stats (Phase 3+ for reviews)
    rating_average DECIMAL(3,2),
    rating_count INTEGER NOT NULL DEFAULT 0,
    sessions_completed INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- INDEXES for search performance
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_therapist_profiles_verified
    ON therapist_profiles(verified) WHERE verified = true;

CREATE INDEX IF NOT EXISTS idx_therapist_profiles_specialties
    ON therapist_profiles USING GIN(specialties);

CREATE INDEX IF NOT EXISTS idx_therapist_profiles_rating
    ON therapist_profiles(rating_average DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_therapist_profiles_user_id
    ON therapist_profiles(user_id);

CREATE INDEX IF NOT EXISTS idx_therapist_profiles_application_status
    ON therapist_profiles(application_status);

-- =============================================================================
-- TRIGGER for updated_at
-- =============================================================================

-- Create the trigger function if it doesn't exist
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_therapist_profiles_updated_at ON therapist_profiles;

CREATE TRIGGER update_therapist_profiles_updated_at
    BEFORE UPDATE ON therapist_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

ALTER TABLE therapist_profiles ENABLE ROW LEVEL SECURITY;

-- Policy: Verified therapists accepting new clients are publicly readable
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Verified therapists are public' AND tablename = 'therapist_profiles') THEN
        CREATE POLICY "Verified therapists are public"
            ON therapist_profiles FOR SELECT
            USING (verified = true AND accepts_new_clients = true);
    END IF;
END $$;

-- Policy: Users can read their own profile (even if not verified)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can read own therapist profile' AND tablename = 'therapist_profiles') THEN
        CREATE POLICY "Users can read own therapist profile"
            ON therapist_profiles FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Policy: Users can create their own application (limited to pending status)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can create own application' AND tablename = 'therapist_profiles') THEN
        CREATE POLICY "Users can create own application"
            ON therapist_profiles FOR INSERT
            WITH CHECK (auth.uid() = user_id AND application_status = 'pending');
    END IF;
END $$;

-- Policy: Users can update their own profile (but not verified/application_status)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can update own profile' AND tablename = 'therapist_profiles') THEN
        CREATE POLICY "Users can update own profile"
            ON therapist_profiles FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- =============================================================================
-- STORAGE BUCKET for therapist photos
-- =============================================================================

-- Create storage bucket (idempotent - uses INSERT ON CONFLICT)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'therapist-photos',
    'therapist-photos',
    true,
    5242880, -- 5MB limit
    ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Storage policies
DO $$
BEGIN
    -- Policy: Therapists can upload their own photos
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Therapists can upload own photo' AND tablename = 'objects' AND schemaname = 'storage') THEN
        CREATE POLICY "Therapists can upload own photo"
            ON storage.objects FOR INSERT
            WITH CHECK (
                bucket_id = 'therapist-photos'
                AND auth.uid() IS NOT NULL
            );
    END IF;

    -- Policy: Therapists can update their own photos
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Therapists can update own photo' AND tablename = 'objects' AND schemaname = 'storage') THEN
        CREATE POLICY "Therapists can update own photo"
            ON storage.objects FOR UPDATE
            USING (
                bucket_id = 'therapist-photos'
                AND auth.uid() IS NOT NULL
            );
    END IF;

    -- Policy: Therapists can delete their own photos
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Therapists can delete own photo' AND tablename = 'objects' AND schemaname = 'storage') THEN
        CREATE POLICY "Therapists can delete own photo"
            ON storage.objects FOR DELETE
            USING (
                bucket_id = 'therapist-photos'
                AND auth.uid() IS NOT NULL
            );
    END IF;

    -- Policy: Public can read all therapist photos
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Public can read therapist photos' AND tablename = 'objects' AND schemaname = 'storage') THEN
        CREATE POLICY "Public can read therapist photos"
            ON storage.objects FOR SELECT
            USING (bucket_id = 'therapist-photos');
    END IF;
END $$;

-- =============================================================================
-- COMMENTS for documentation
-- =============================================================================

COMMENT ON TABLE therapist_profiles IS 'Therapist and coach profiles for the marketplace feature. Phase 1 focuses on profile creation and discovery.';
COMMENT ON COLUMN therapist_profiles.profile_type IS 'Either therapist (licensed) or coach (certified but not licensed)';
COMMENT ON COLUMN therapist_profiles.verified IS 'Admin-approved flag. Phase 1 uses manual approval via Supabase Dashboard.';
COMMENT ON COLUMN therapist_profiles.application_status IS 'Workflow state: pending (submitted), approved (can practice), rejected (denied)';
COMMENT ON COLUMN therapist_profiles.credentials IS 'Array of credential codes like LMFT, LCSW, PsyD, etc.';
COMMENT ON COLUMN therapist_profiles.specialties IS 'Array of specialty areas like anxiety, depression, trauma, etc.';
