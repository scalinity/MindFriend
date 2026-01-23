-- Create profile-pictures storage bucket
-- Migration: 20260124030000_create_profile_pictures_bucket
-- Purpose: Enable profile picture uploads with RLS policies

-- Create storage bucket for profile pictures
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'profile-pictures',
  'profile-pictures',
  TRUE,  -- Public bucket (avatars are publicly viewable)
  10485760,  -- 10MB limit (pre-compression)
  ARRAY['image/jpeg', 'image/png', 'image/heic']
)
ON CONFLICT (id) DO NOTHING;

-- RLS Policies for profile-pictures bucket

-- Users can upload their own profile pictures
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
    AND tablename = 'objects'
    AND policyname = 'Users can upload own avatars'
  ) THEN
    CREATE POLICY "Users can upload own avatars"
    ON storage.objects FOR INSERT
    WITH CHECK (
      bucket_id = 'profile-pictures' AND
      (storage.foldername(name))[1] = auth.uid()::text
    );
  END IF;
END
$$;

-- Users can update their own profile pictures
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
    AND tablename = 'objects'
    AND policyname = 'Users can update own avatars'
  ) THEN
    CREATE POLICY "Users can update own avatars"
    ON storage.objects FOR UPDATE
    USING (
      bucket_id = 'profile-pictures' AND
      (storage.foldername(name))[1] = auth.uid()::text
    )
    WITH CHECK (
      bucket_id = 'profile-pictures' AND
      (storage.foldername(name))[1] = auth.uid()::text
    );
  END IF;
END
$$;

-- Users can delete their own profile pictures
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
    AND tablename = 'objects'
    AND policyname = 'Users can delete own avatars'
  ) THEN
    CREATE POLICY "Users can delete own avatars"
    ON storage.objects FOR DELETE
    USING (
      bucket_id = 'profile-pictures' AND
      (storage.foldername(name))[1] = auth.uid()::text
    );
  END IF;
END
$$;

-- Anyone can read profile pictures (public avatars)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
    AND tablename = 'objects'
    AND policyname = 'Public read access for avatars'
  ) THEN
    CREATE POLICY "Public read access for avatars"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'profile-pictures');
  END IF;
END
$$;

-- Ensure profiles.avatar_url can be updated by users
-- (RLS policy should already exist, but verify)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'profiles'
    AND policyname = 'Users can update own profile'
  ) THEN
    CREATE POLICY "Users can update own profile"
    ON profiles FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);
  END IF;
END
$$;
