-- Apply only after the compatible iOS release is available and production approval.
-- Existing clients construct public creative URLs; changing visibility before release
-- would break their gallery/history. No objects or conversation records are changed.
BEGIN;
UPDATE storage.buckets SET public=false WHERE id IN ('creative-works','generated-audio');
-- The voice journal uploader uses audio/m4a; the live bucket currently allows images only.
UPDATE storage.buckets SET allowed_mime_types=ARRAY[
 'image/png','image/jpeg','image/webp','image/gif',
 'audio/m4a','audio/x-m4a','audio/mp4','audio/aac','audio/mpeg','audio/wav'
] WHERE id='creative-works';
DROP POLICY "Public read access for creative works" ON storage.objects;
ALTER POLICY "Users can read own creative works" ON storage.objects TO authenticated
 USING (bucket_id='creative-works' AND lower((storage.foldername(name))[1])=(SELECT auth.uid())::text);
ALTER POLICY "Users can upload to own folder" ON storage.objects TO authenticated
 WITH CHECK (bucket_id='creative-works' AND lower((storage.foldername(name))[1])=(SELECT auth.uid())::text);
CREATE POLICY "Users can delete own creative works" ON storage.objects FOR DELETE TO authenticated
 USING (bucket_id='creative-works' AND lower((storage.foldername(name))[1])=(SELECT auth.uid())::text);
ALTER POLICY "Users can read own generated audio" ON storage.objects TO authenticated
 USING (bucket_id='generated-audio' AND lower((storage.foldername(name))[1])=(SELECT auth.uid())::text);
ALTER POLICY "Users can delete own generated audio" ON storage.objects TO authenticated
 USING (bucket_id='generated-audio' AND lower((storage.foldername(name))[1])=(SELECT auth.uid())::text);
ALTER POLICY "Users can update own generated audio" ON storage.objects TO authenticated
 USING (bucket_id='generated-audio' AND lower((storage.foldername(name))[1])=(SELECT auth.uid())::text)
 WITH CHECK (bucket_id='generated-audio' AND lower((storage.foldername(name))[1])=(SELECT auth.uid())::text);
ALTER POLICY "Users can upload own generated audio" ON storage.objects TO authenticated
 WITH CHECK (bucket_id='generated-audio' AND lower((storage.foldername(name))[1])=(SELECT auth.uid())::text);
COMMIT;
