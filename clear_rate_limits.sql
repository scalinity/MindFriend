-- Temporary script to clear rate limit data for testing
-- Run this via Supabase Dashboard SQL Editor

-- Check current rate limits
SELECT
    user_id,
    request_count,
    window_start,
    now() - window_start as age
FROM capacity_rate_limits
WHERE user_id = 'D96D0225-D8C1-4906-9827-A4EE2BE9104D'::uuid;

-- Clear rate limit for this user
DELETE FROM capacity_rate_limits
WHERE user_id = 'D96D0225-D8C1-4906-9827-A4EE2BE9104D'::uuid;

-- Or clear all rate limits (use with caution)
-- TRUNCATE TABLE capacity_rate_limits;
