-- Insight Lab: 7-day experiments with adherence tracking and outcome reports
-- Created: 2026-01-20

-- Create insight_experiments table
CREATE TABLE IF NOT EXISTS insight_experiments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    action_type TEXT NOT NULL CHECK (action_type IN (
        'morning_walk',
        'meditation_daily',
        'no_phone_before_bed',
        'gratitude_journaling',
        'cold_shower',
        'digital_detox_evening',
        'exercise_30min'
    )),
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'cancelled')),
    baseline_mood_avg DECIMAL(3,2),
    baseline_energy_avg DECIMAL(3,2),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create unique index for one active experiment per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_one_active_experiment
    ON insight_experiments(user_id)
    WHERE status = 'active';

-- Create index for user lookups
CREATE INDEX IF NOT EXISTS idx_insight_experiments_user_id
    ON insight_experiments(user_id);

-- Create insight_experiment_days table
CREATE TABLE IF NOT EXISTS insight_experiment_days (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    experiment_id UUID NOT NULL REFERENCES insight_experiments(id) ON DELETE CASCADE,
    day_index INTEGER NOT NULL CHECK (day_index >= 1 AND day_index <= 7),
    completed BOOLEAN NOT NULL DEFAULT FALSE,
    completed_at TIMESTAMPTZ,
    mood_score INTEGER CHECK (mood_score IS NULL OR (mood_score >= 1 AND mood_score <= 5)),
    energy_score INTEGER CHECK (energy_score IS NULL OR (energy_score >= 1 AND energy_score <= 5)),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(experiment_id, day_index)
);

-- Create index for experiment day lookups
CREATE INDEX IF NOT EXISTS idx_insight_experiment_days_experiment_id
    ON insight_experiment_days(experiment_id);

-- Enable RLS
ALTER TABLE insight_experiments ENABLE ROW LEVEL SECURITY;
ALTER TABLE insight_experiment_days ENABLE ROW LEVEL SECURITY;

-- RLS Policies for insight_experiments
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can view own experiments' AND tablename = 'insight_experiments') THEN
        CREATE POLICY "Users can view own experiments"
            ON insight_experiments FOR SELECT
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can insert own experiments' AND tablename = 'insight_experiments') THEN
        CREATE POLICY "Users can insert own experiments"
            ON insight_experiments FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can update own experiments' AND tablename = 'insight_experiments') THEN
        CREATE POLICY "Users can update own experiments"
            ON insight_experiments FOR UPDATE
            USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can delete own experiments' AND tablename = 'insight_experiments') THEN
        CREATE POLICY "Users can delete own experiments"
            ON insight_experiments FOR DELETE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- RLS Policies for insight_experiment_days
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can view own experiment days' AND tablename = 'insight_experiment_days') THEN
        CREATE POLICY "Users can view own experiment days"
            ON insight_experiment_days FOR SELECT
            USING (
                EXISTS (
                    SELECT 1 FROM insight_experiments
                    WHERE insight_experiments.id = experiment_id
                    AND insight_experiments.user_id = auth.uid()
                )
            );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can insert own experiment days' AND tablename = 'insight_experiment_days') THEN
        CREATE POLICY "Users can insert own experiment days"
            ON insight_experiment_days FOR INSERT
            WITH CHECK (
                EXISTS (
                    SELECT 1 FROM insight_experiments
                    WHERE insight_experiments.id = experiment_id
                    AND insight_experiments.user_id = auth.uid()
                )
            );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can update own experiment days' AND tablename = 'insight_experiment_days') THEN
        CREATE POLICY "Users can update own experiment days"
            ON insight_experiment_days FOR UPDATE
            USING (
                EXISTS (
                    SELECT 1 FROM insight_experiments
                    WHERE insight_experiments.id = experiment_id
                    AND insight_experiments.user_id = auth.uid()
                )
            );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can delete own experiment days' AND tablename = 'insight_experiment_days') THEN
        CREATE POLICY "Users can delete own experiment days"
            ON insight_experiment_days FOR DELETE
            USING (
                EXISTS (
                    SELECT 1 FROM insight_experiments
                    WHERE insight_experiments.id = experiment_id
                    AND insight_experiments.user_id = auth.uid()
                )
            );
    END IF;
END $$;

-- Create updated_at trigger function if not exists
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for updated_at
DROP TRIGGER IF EXISTS update_insight_experiments_updated_at ON insight_experiments;
CREATE TRIGGER update_insight_experiments_updated_at
    BEFORE UPDATE ON insight_experiments
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_insight_experiment_days_updated_at ON insight_experiment_days;
CREATE TRIGGER update_insight_experiment_days_updated_at
    BEFORE UPDATE ON insight_experiment_days
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Add energy_score column to moods table if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'moods' AND column_name = 'energy_score'
    ) THEN
        ALTER TABLE moods ADD COLUMN energy_score INTEGER CHECK (energy_score IS NULL OR (energy_score >= 1 AND energy_score <= 5));
    END IF;
END $$;
