-- Increase Sleep Content Storage Bucket Size Limit
-- ============================================================================
-- The downloaded CC0 audio files are larger than the initial 50MB limit.
-- Increase to 500MB to accommodate long-duration ambient soundscapes (1-3 hours).
-- ============================================================================

UPDATE storage.buckets
SET file_size_limit = 524288000 -- 500MB
WHERE id = 'sleep-content';
