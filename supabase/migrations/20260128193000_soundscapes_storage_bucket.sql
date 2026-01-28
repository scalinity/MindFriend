-- Create soundscapes storage bucket for background sounds
-- Used by the generative content feature for ambient audio mixing

-- Create the public bucket for soundscape audio files
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'soundscapes',
    'soundscapes',
    true,
    52428800, -- 50MB limit
    ARRAY['audio/mpeg', 'audio/mp3', 'audio/wav', 'audio/x-wav', 'audio/m4a', 'audio/mp4']
)
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = 52428800;

-- Allow public read access (bucket is public)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'objects'
        AND policyname = 'Soundscapes public read'
    ) THEN
        CREATE POLICY "Soundscapes public read"
        ON storage.objects FOR SELECT
        USING (bucket_id = 'soundscapes');
    END IF;
END $$;

-- Only service role can upload (admin only)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'objects'
        AND policyname = 'Soundscapes admin upload'
    ) THEN
        CREATE POLICY "Soundscapes admin upload"
        ON storage.objects FOR INSERT
        WITH CHECK (
            bucket_id = 'soundscapes' AND
            (SELECT auth.role()) = 'service_role'
        );
    END IF;
END $$;
