-- Guarded each ALTER POLICY to run only where the policy exists (six were created outside migrations in production); production applied the original text.
-- Swift UUID strings are uppercase by default; UUID ownership is case-insensitive.
-- Preserve each existing policy role and bucket, and match the same owner.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_policies WHERE schemaname = 'storage'
      AND tablename = 'objects' AND policyname = 'Therapists can delete own photo') THEN
    ALTER POLICY "Therapists can delete own photo" ON storage.objects TO "public" USING (((bucket_id = 'therapist-photos'::text) AND (auth.uid() IS NOT NULL) AND (lower((storage.foldername(name))[1]) = (auth.uid())::text)));
  END IF;
END
$$;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_policies WHERE schemaname = 'storage'
      AND tablename = 'objects' AND policyname = 'Therapists can update own photo') THEN
    ALTER POLICY "Therapists can update own photo" ON storage.objects TO "public" USING (((bucket_id = 'therapist-photos'::text) AND (auth.uid() IS NOT NULL) AND (lower((storage.foldername(name))[1]) = (auth.uid())::text))) WITH CHECK (((bucket_id = 'therapist-photos'::text) AND (auth.uid() IS NOT NULL) AND (lower((storage.foldername(name))[1]) = (auth.uid())::text)));
  END IF;
END
$$;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_policies WHERE schemaname = 'storage'
      AND tablename = 'objects' AND policyname = 'Therapists can upload own photo') THEN
    ALTER POLICY "Therapists can upload own photo" ON storage.objects TO "public" WITH CHECK (((bucket_id = 'therapist-photos'::text) AND (auth.uid() IS NOT NULL) AND (lower((storage.foldername(name))[1]) = (auth.uid())::text)));
  END IF;
END
$$;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_policies WHERE schemaname = 'storage'
      AND tablename = 'objects' AND policyname = 'Users can delete own avatars') THEN
    ALTER POLICY "Users can delete own avatars" ON storage.objects TO "public" USING (((bucket_id = 'profile-pictures'::text) AND (lower(lower((storage.foldername(name))[1])) = lower((auth.uid())::text))));
  END IF;
END
$$;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_policies WHERE schemaname = 'storage'
      AND tablename = 'objects' AND policyname = 'Users can delete own capsule media') THEN
    ALTER POLICY "Users can delete own capsule media" ON storage.objects TO "authenticated" USING (((bucket_id = 'capsule-media'::text) AND (lower((storage.foldername(name))[1]) = (auth.uid())::text)));
  END IF;
END
$$;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_policies WHERE schemaname = 'storage'
      AND tablename = 'objects' AND policyname = 'Users can delete own photos') THEN
    ALTER POLICY "Users can delete own photos" ON storage.objects TO "public" USING (((bucket_id = 'mood-photos'::text) AND ((auth.uid())::text = lower((storage.foldername(name))[1]))));
  END IF;
END
$$;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_policies WHERE schemaname = 'storage'
      AND tablename = 'objects' AND policyname = 'Users can read own capsule media') THEN
    ALTER POLICY "Users can read own capsule media" ON storage.objects TO "authenticated" USING (((bucket_id = 'capsule-media'::text) AND (lower((storage.foldername(name))[1]) = (auth.uid())::text)));
  END IF;
END
$$;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_policies WHERE schemaname = 'storage'
      AND tablename = 'objects' AND policyname = 'Users can update own avatars') THEN
    ALTER POLICY "Users can update own avatars" ON storage.objects TO "public" USING (((bucket_id = 'profile-pictures'::text) AND (lower(lower((storage.foldername(name))[1])) = lower((auth.uid())::text)))) WITH CHECK (((bucket_id = 'profile-pictures'::text) AND (lower(lower((storage.foldername(name))[1])) = lower((auth.uid())::text))));
  END IF;
END
$$;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_policies WHERE schemaname = 'storage'
      AND tablename = 'objects' AND policyname = 'Users can upload capsule media') THEN
    ALTER POLICY "Users can upload capsule media" ON storage.objects TO "authenticated" WITH CHECK (((bucket_id = 'capsule-media'::text) AND (lower((storage.foldername(name))[1]) = (auth.uid())::text)));
  END IF;
END
$$;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_policies WHERE schemaname = 'storage'
      AND tablename = 'objects' AND policyname = 'Users can upload own avatars') THEN
    ALTER POLICY "Users can upload own avatars" ON storage.objects TO "public" WITH CHECK (((bucket_id = 'profile-pictures'::text) AND (lower(lower((storage.foldername(name))[1])) = lower((auth.uid())::text))));
  END IF;
END
$$;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_policies WHERE schemaname = 'storage'
      AND tablename = 'objects' AND policyname = 'Users can upload own photos') THEN
    ALTER POLICY "Users can upload own photos" ON storage.objects TO "public" WITH CHECK (((bucket_id = 'mood-photos'::text) AND ((auth.uid())::text = lower((storage.foldername(name))[1]))));
  END IF;
END
$$;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_policies WHERE schemaname = 'storage'
      AND tablename = 'objects' AND policyname = 'Users can view own photos') THEN
    ALTER POLICY "Users can view own photos" ON storage.objects TO "public" USING (((bucket_id = 'mood-photos'::text) AND ((auth.uid())::text = lower((storage.foldername(name))[1]))));
  END IF;
END
$$;
