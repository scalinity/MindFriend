-- Create audio storage bucket for meditation and exercise audio files
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'audio',
  'audio',
  true,  -- Public bucket for audio streaming
  52428800,  -- 50MB max file size
  ARRAY['audio/mpeg', 'audio/mp3', 'audio/wav', 'audio/ogg', 'audio/aac']
)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users to read audio files
CREATE POLICY "Anyone can read audio files"
ON storage.objects FOR SELECT
USING (bucket_id = 'audio');

-- Allow authenticated users to upload audio files to their own folder only
CREATE POLICY "Users can upload audio to own folder"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'audio'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- Allow authenticated users to update their own audio files
CREATE POLICY "Users can update own audio files"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'audio'
  AND auth.uid()::text = (storage.foldername(name))[1]
);
