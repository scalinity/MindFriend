-- Create the creative-works storage bucket for AI art and other creative content
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'creative-works',
  'creative-works', 
  true,
  52428800,  -- 50MB limit
  ARRAY['image/png', 'image/jpeg', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users to upload to their own folder
CREATE POLICY "Users can upload to own folder"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'creative-works' 
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Allow authenticated users to read their own files
CREATE POLICY "Users can read own creative works"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'creative-works'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Allow public read access (since bucket is public)
CREATE POLICY "Public read access for creative works"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'creative-works');

-- Allow service role full access
CREATE POLICY "Service role full access to creative works"
ON storage.objects
FOR ALL
TO service_role
USING (bucket_id = 'creative-works')
WITH CHECK (bucket_id = 'creative-works');
