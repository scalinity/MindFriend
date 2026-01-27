-- Longitudinal Mental Health Intelligence (F027)
-- Aggregates wellness data over months/years to identify patterns and trends

-- ============================================================================
-- TABLES
-- ============================================================================

-- Weekly aggregated statistics
CREATE TABLE IF NOT EXISTS longitudinal_weekly_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    week_start TIMESTAMPTZ NOT NULL, -- Sunday 00:00:00 UTC
    avg_mood NUMERIC(3,2) CHECK (avg_mood >= 1 AND avg_mood <= 5),
    mood_variance NUMERIC(5,3) CHECK (mood_variance >= 0),
    active_days INTEGER CHECK (active_days >= 0 AND active_days <= 7),
    exercises_completed INTEGER DEFAULT 0 CHECK (exercises_completed >= 0),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, week_start)
);

-- Monthly aggregated statistics
CREATE TABLE IF NOT EXISTS longitudinal_monthly_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    month_start TIMESTAMPTZ NOT NULL, -- 1st of month 00:00:00 UTC
    avg_mood NUMERIC(3,2) CHECK (avg_mood >= 1 AND avg_mood <= 5),
    mood_trend TEXT CHECK (mood_trend IN ('improving', 'declining', 'stable', 'baseline')),
    active_days_pct NUMERIC(5,2) CHECK (active_days_pct >= 0 AND active_days_pct <= 100),
    notable_events JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, month_start)
);

-- Yearly aggregated statistics
CREATE TABLE IF NOT EXISTS longitudinal_yearly_stats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    year INTEGER NOT NULL CHECK (year >= 2020 AND year <= 2100),
    quarterly_moods JSONB, -- [q1_avg, q2_avg, q3_avg, q4_avg]
    seasonal_patterns JSONB, -- {winter, spring, summer, fall, lowest_season, highest_season}
    yearly_comparison JSONB, -- {mood_delta, active_days_delta, exercises_delta}
    milestones_achieved JSONB DEFAULT '[]'::jsonb,
    is_partial BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, year)
);

-- Detected patterns
CREATE TABLE IF NOT EXISTS longitudinal_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    pattern_type TEXT NOT NULL CHECK (pattern_type IN ('seasonal_mood', 'weekly_rhythm', 'event_response', 'improvement_trend')),
    pattern_description TEXT NOT NULL,
    confidence NUMERIC(4,3) CHECK (confidence >= 0 AND confidence <= 1),
    first_detected TIMESTAMPTZ DEFAULT now(),
    last_detected TIMESTAMPTZ DEFAULT now(),
    occurrences INTEGER DEFAULT 1 CHECK (occurrences >= 1),
    is_active BOOLEAN DEFAULT true,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Life events for tracking major life changes
CREATE TABLE IF NOT EXISTS longitudinal_life_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (event_type IN ('relationship_change', 'career_change', 'health_issue', 'loss', 'achievement', 'relocation', 'other')),
    event_date DATE NOT NULL,
    impact_score NUMERIC(4,2) CHECK (impact_score >= -5 AND impact_score <= 5),
    before_metrics JSONB, -- {avg_mood, active_days, exercises_completed}
    after_metrics JSONB,
    recovery_days INTEGER CHECK (recovery_days >= 0),
    is_ongoing BOOLEAN DEFAULT false,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Generated longitudinal reports
CREATE TABLE IF NOT EXISTS longitudinal_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    report_type TEXT NOT NULL CHECK (report_type IN ('quarterly', 'annual', 'custom')),
    time_period JSONB NOT NULL, -- {start, end}
    content_json JSONB NOT NULL, -- {summary, key_insights[], charts_data, recommendations[]}
    generated_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_weekly_stats_user_week
    ON longitudinal_weekly_stats(user_id, week_start DESC);

CREATE INDEX IF NOT EXISTS idx_monthly_stats_user_month
    ON longitudinal_monthly_stats(user_id, month_start DESC);

CREATE INDEX IF NOT EXISTS idx_yearly_stats_user_year
    ON longitudinal_yearly_stats(user_id, year DESC);

CREATE INDEX IF NOT EXISTS idx_patterns_user_active
    ON longitudinal_patterns(user_id, is_active) WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_patterns_user_type
    ON longitudinal_patterns(user_id, pattern_type);

CREATE INDEX IF NOT EXISTS idx_life_events_user_date
    ON longitudinal_life_events(user_id, event_date DESC);

CREATE INDEX IF NOT EXISTS idx_reports_user_type
    ON longitudinal_reports(user_id, report_type, generated_at DESC);

CREATE INDEX IF NOT EXISTS idx_reports_expiry
    ON longitudinal_reports(expires_at) WHERE expires_at IS NOT NULL;

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE longitudinal_weekly_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE longitudinal_monthly_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE longitudinal_yearly_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE longitudinal_patterns ENABLE ROW LEVEL SECURITY;
ALTER TABLE longitudinal_life_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE longitudinal_reports ENABLE ROW LEVEL SECURITY;

-- Weekly Stats policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users read own weekly stats') THEN
        CREATE POLICY "Users read own weekly stats" ON longitudinal_weekly_stats
            FOR SELECT USING (auth.uid() = user_id);
    END IF;
END $$;

-- Monthly Stats policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users read own monthly stats') THEN
        CREATE POLICY "Users read own monthly stats" ON longitudinal_monthly_stats
            FOR SELECT USING (auth.uid() = user_id);
    END IF;
END $$;

-- Yearly Stats policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users read own yearly stats') THEN
        CREATE POLICY "Users read own yearly stats" ON longitudinal_yearly_stats
            FOR SELECT USING (auth.uid() = user_id);
    END IF;
END $$;

-- Patterns policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users read own patterns') THEN
        CREATE POLICY "Users read own patterns" ON longitudinal_patterns
            FOR SELECT USING (auth.uid() = user_id);
    END IF;
END $$;

-- Life Events policies (users can read, insert, update, delete their own)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users read own life events') THEN
        CREATE POLICY "Users read own life events" ON longitudinal_life_events
            FOR SELECT USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users insert own life events') THEN
        CREATE POLICY "Users insert own life events" ON longitudinal_life_events
            FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users update own life events') THEN
        CREATE POLICY "Users update own life events" ON longitudinal_life_events
            FOR UPDATE USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users delete own life events') THEN
        CREATE POLICY "Users delete own life events" ON longitudinal_life_events
            FOR DELETE USING (auth.uid() = user_id);
    END IF;
END $$;

-- Reports policies
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users read own reports') THEN
        CREATE POLICY "Users read own reports" ON longitudinal_reports
            FOR SELECT USING (auth.uid() = user_id);
    END IF;
END $$;

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

CREATE OR REPLACE FUNCTION update_longitudinal_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_weekly_stats_updated_at ON longitudinal_weekly_stats;
CREATE TRIGGER trigger_weekly_stats_updated_at
    BEFORE UPDATE ON longitudinal_weekly_stats
    FOR EACH ROW
    EXECUTE FUNCTION update_longitudinal_updated_at();

-- ============================================================================
-- PG_CRON SCHEDULES (requires pg_cron extension)
-- ============================================================================

-- Note: These jobs call Edge Functions via pg_net or internal HTTP
-- Actual scheduling is configured in Supabase Dashboard or via cron extension

-- Weekly aggregation: Sunday 02:00 UTC
-- SELECT cron.schedule('aggregate-weekly-stats', '0 2 * * 0',
--     $$SELECT net.http_post(
--         url := current_setting('app.settings.supabase_url') || '/functions/v1/aggregate-weekly-stats',
--         headers := jsonb_build_object('Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'))
--     )$$
-- );

-- Monthly aggregation: 1st of month 03:00 UTC
-- SELECT cron.schedule('aggregate-monthly-stats', '0 3 1 * *', ...);

-- Yearly aggregation: January 1st 04:00 UTC
-- SELECT cron.schedule('aggregate-yearly-stats', '0 4 1 1 *', ...);

-- Pattern detection: Sunday 05:00 UTC
-- SELECT cron.schedule('detect-patterns', '0 5 * * 0', ...);

COMMENT ON TABLE longitudinal_weekly_stats IS 'Weekly aggregated wellness statistics for longitudinal analysis';
COMMENT ON TABLE longitudinal_monthly_stats IS 'Monthly aggregated wellness statistics with trend detection';
COMMENT ON TABLE longitudinal_yearly_stats IS 'Yearly aggregated statistics with seasonal patterns';
COMMENT ON TABLE longitudinal_patterns IS 'Detected patterns in user wellness data (statistical analysis)';
COMMENT ON TABLE longitudinal_life_events IS 'User-logged significant life events for impact analysis';
COMMENT ON TABLE longitudinal_reports IS 'Generated longitudinal wellness reports (quarterly/annual)';
