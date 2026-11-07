-- Production prerequisite: release the signed-URL-compatible iOS client before
-- applying this migration, as required by operations/20261022_private_media.sql.
-- Older installed clients construct public URLs and cannot read private buckets.
-- This forward migration changes access only; it deletes no media or records.
UPDATE storage.buckets SET public = false
WHERE id IN ('creative-works', 'generated-audio');

UPDATE storage.buckets SET allowed_mime_types = ARRAY[
  'image/png', 'image/jpeg', 'image/webp', 'image/gif',
  'audio/m4a', 'audio/x-m4a', 'audio/mp4', 'audio/aac', 'audio/mpeg', 'audio/wav'
] WHERE id = 'creative-works';

DROP POLICY IF EXISTS "Public read access for creative works" ON storage.objects;
DROP POLICY IF EXISTS "Users can read own creative works" ON storage.objects;
CREATE POLICY "Users can read own creative works" ON storage.objects
FOR SELECT TO authenticated
USING (bucket_id = 'creative-works' AND lower((storage.foldername(name))[1]) = (SELECT auth.uid())::text);

DROP POLICY IF EXISTS "Users can upload to own folder" ON storage.objects;
CREATE POLICY "Users can upload to own folder" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'creative-works' AND lower((storage.foldername(name))[1]) = (SELECT auth.uid())::text);

DROP POLICY IF EXISTS "Users can delete own creative works" ON storage.objects;
CREATE POLICY "Users can delete own creative works" ON storage.objects
FOR DELETE TO authenticated
USING (bucket_id = 'creative-works' AND lower((storage.foldername(name))[1]) = (SELECT auth.uid())::text);

DROP POLICY IF EXISTS "Users can read own generated audio" ON storage.objects;
CREATE POLICY "Users can read own generated audio" ON storage.objects
FOR SELECT TO authenticated
USING (bucket_id = 'generated-audio' AND lower((storage.foldername(name))[1]) = (SELECT auth.uid())::text);

DROP POLICY IF EXISTS "Users can delete own generated audio" ON storage.objects;
CREATE POLICY "Users can delete own generated audio" ON storage.objects
FOR DELETE TO authenticated
USING (bucket_id = 'generated-audio' AND lower((storage.foldername(name))[1]) = (SELECT auth.uid())::text);

DROP POLICY IF EXISTS "Users can update own generated audio" ON storage.objects;
CREATE POLICY "Users can update own generated audio" ON storage.objects
FOR UPDATE TO authenticated
USING (bucket_id = 'generated-audio' AND lower((storage.foldername(name))[1]) = (SELECT auth.uid())::text)
WITH CHECK (bucket_id = 'generated-audio' AND lower((storage.foldername(name))[1]) = (SELECT auth.uid())::text);

DROP POLICY IF EXISTS "Users can upload own generated audio" ON storage.objects;
CREATE POLICY "Users can upload own generated audio" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'generated-audio' AND lower((storage.foldername(name))[1]) = (SELECT auth.uid())::text);
