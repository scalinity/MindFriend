-- Create storage bucket for capsule media with RLS policies

-- Create capsule-media bucket if it doesn't exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'capsule-media',
    'capsule-media',
    false, -- Private bucket
    10485760, -- 10MB file size limit
    ARRAY[
        'audio/mpeg',
        'audio/mp4',
        'audio/m4a',
        'audio/x-m4a',
        'image/jpeg',
        'image/jpg',
        'image/png',
        'image/heic',
        'image/heif',
        'video/mp4',
        'video/quicktime'
    ]
)
ON CONFLICT (id) DO NOTHING;

-- RLS Policies for capsule-media bucket

-- Allow users to upload media for their own capsules
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
        AND tablename = 'objects'
        AND policyname = 'Users can upload capsule media'
    ) THEN
        CREATE POLICY "Users can upload capsule media" ON storage.objects
            FOR INSERT TO authenticated
            WITH CHECK (
                bucket_id = 'capsule-media' AND
                (storage.foldername(name))[1] = auth.uid()::text
            );
    END IF;
END $$;

-- Allow users to read their own capsule media
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
        AND tablename = 'objects'
        AND policyname = 'Users can read own capsule media'
    ) THEN
        CREATE POLICY "Users can read own capsule media" ON storage.objects
            FOR SELECT TO authenticated
            USING (
                bucket_id = 'capsule-media' AND
                (storage.foldername(name))[1] = auth.uid()::text
            );
    END IF;
END $$;

-- Allow users to delete their own capsule media
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
        AND tablename = 'objects'
        AND policyname = 'Users can delete own capsule media'
    ) THEN
        CREATE POLICY "Users can delete own capsule media" ON storage.objects
            FOR DELETE TO authenticated
            USING (
                bucket_id = 'capsule-media' AND
                (storage.foldername(name))[1] = auth.uid()::text
            );
    END IF;
END $$;

-- Service role has full access
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage'
        AND tablename = 'objects'
        AND policyname = 'Service role has full access to capsule media'
    ) THEN
        CREATE POLICY "Service role has full access to capsule media" ON storage.objects
            FOR ALL TO service_role
            USING (bucket_id = 'capsule-media')
            WITH CHECK (bucket_id = 'capsule-media');
    END IF;
END $$;
