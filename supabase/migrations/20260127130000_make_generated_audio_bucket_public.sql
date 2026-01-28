-- Migration: Make generated-audio bucket public
-- Purpose: Enable public access to generated audio files for streaming playback
-- Author: dev-pipeline
-- Date: 2026-01-27
--
-- The bucket was created as private, but the edge function uses getPublicUrl()
-- which doesn't work for private buckets. Audio content is user-generated wellness
-- content (meditations, sleep stories) that doesn't contain sensitive information.

-- Update the bucket to be public (idempotent)
UPDATE storage.buckets
SET public = true
WHERE id = 'generated-audio';
