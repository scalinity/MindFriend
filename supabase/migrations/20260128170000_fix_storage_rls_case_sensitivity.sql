-- Fix storage RLS policies for case-insensitive UUID comparison
-- Migration: 20260128170000_fix_storage_rls_case_sensitivity
-- 
-- Issue: Swift's UUID.uuidString returns uppercase (e.g., E96D8E5E-4403-4764-BAFC-5147EDCDBA5C)
-- but Supabase's auth.uid()::text returns lowercase (e.g., e96d8e5e-4403-4764-bafc-5147edcdba5c)
-- This causes RLS policy failures on storage uploads.
--
-- Fix: Use LOWER() on both sides of the comparison.

-- Drop existing storage policies for profile-pictures bucket
DROP POLICY IF EXISTS "Users can upload own avatars" ON storage.objects;
DROP POLICY IF EXISTS "Users can update own avatars" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own avatars" ON storage.objects;
DROP POLICY IF EXISTS "Public read access for avatars" ON storage.objects;

-- Recreate policies with case-insensitive comparison

-- Users can upload their own profile pictures (INSERT)
CREATE POLICY "Users can upload own avatars"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'profile-pictures' AND
    LOWER((storage.foldername(name))[1]) = LOWER(auth.uid()::text)
);

-- Users can update their own profile pictures (UPDATE)
CREATE POLICY "Users can update own avatars"
ON storage.objects FOR UPDATE
USING (
    bucket_id = 'profile-pictures' AND
    LOWER((storage.foldername(name))[1]) = LOWER(auth.uid()::text)
)
WITH CHECK (
    bucket_id = 'profile-pictures' AND
    LOWER((storage.foldername(name))[1]) = LOWER(auth.uid()::text)
);

-- Users can delete their own profile pictures (DELETE)
CREATE POLICY "Users can delete own avatars"
ON storage.objects FOR DELETE
USING (
    bucket_id = 'profile-pictures' AND
    LOWER((storage.foldername(name))[1]) = LOWER(auth.uid()::text)
);

-- Anyone can read profile pictures - public avatars (SELECT)
CREATE POLICY "Public read access for avatars"
ON storage.objects FOR SELECT
USING (bucket_id = 'profile-pictures');

-- Also ensure the bucket exists and is properly configured
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'profile-pictures',
    'profile-pictures',
    TRUE,
    524288,  -- 512KB limit
    ARRAY['image/jpeg']
)
ON CONFLICT (id) DO UPDATE SET
    public = TRUE,
    file_size_limit = 524288,
    allowed_mime_types = ARRAY['image/jpeg'];
