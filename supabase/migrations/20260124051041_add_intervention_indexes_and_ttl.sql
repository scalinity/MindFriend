-- Add Performance Indexes for Intervention System
-- Created: 2026-01-24
-- Purpose: Improve query performance and add TTL policy

-- Index for dismissed_at queries (cooldown checks)
CREATE INDEX IF NOT EXISTS idx_intervention_deliveries_dismissed_at
ON intervention_deliveries (user_id, dismissed_at)
WHERE dismissed_at IS NOT NULL;

-- Index for rating aggregation queries
CREATE INDEX IF NOT EXISTS idx_intervention_deliveries_rating
ON intervention_deliveries (user_id, intervention_id, rating)
WHERE rating IS NOT NULL;

-- Composite index for date range queries (daily limit, recent deliveries)
CREATE INDEX IF NOT EXISTS idx_intervention_deliveries_user_date
ON intervention_deliveries (user_id, delivered_at DESC);

-- Add TTL policy: Delete intervention deliveries older than 90 days
-- This prevents table bloat while retaining recent history for personalization

DO $outer$
BEGIN
    -- Check if the job already exists
    IF NOT EXISTS (
        SELECT 1
        FROM cron.job
        WHERE jobname = 'cleanup_old_intervention_deliveries'
    ) THEN
        -- Schedule daily cleanup at 3 AM UTC
        PERFORM cron.schedule(
            'cleanup_old_intervention_deliveries',
            '0 3 * * *', -- Every day at 3 AM
            $inner$
            DELETE FROM intervention_deliveries
            WHERE delivered_at < NOW() - INTERVAL '90 days'
            $inner$
        );
    END IF;
END $outer$;

-- Add comment explaining the TTL
COMMENT ON TABLE intervention_deliveries IS
'Stores intervention delivery history. Automatically cleaned up after 90 days via cron job.';
