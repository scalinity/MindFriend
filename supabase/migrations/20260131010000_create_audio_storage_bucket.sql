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

-- Allow service role to upload audio files (Edge Functions use service role)
CREATE POLICY "Service role can upload audio files"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'audio');

-- Allow service role to update audio files
CREATE POLICY "Service role can update audio files"
ON storage.objects FOR UPDATE
USING (bucket_id = 'audio');
