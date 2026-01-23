-- Vacation Mode System for Streak Shields Enhancement
-- Allows users to freeze their streak during planned absences (max 14 days)

-- Create vacation_mode table
CREATE TABLE IF NOT EXISTS vacation_mode (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    is_active BOOLEAN NOT NULL DEFAULT true,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    reason TEXT,
    streak_at_start INT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deactivated_at TIMESTAMPTZ,
    CONSTRAINT valid_vacation_period CHECK (end_date >= start_date),
    CONSTRAINT max_vacation_duration CHECK (end_date - start_date <= 14),
    UNIQUE(user_id, start_date) -- Prevent overlapping vacations
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_vacation_mode_user_active
    ON vacation_mode(user_id, is_active)
    WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_vacation_mode_date_range
    ON vacation_mode(user_id, start_date, end_date);

-- Enable Row Level Security
ALTER TABLE vacation_mode ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can only manage their own vacation modes
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'vacation_mode'
        AND policyname = 'Users can manage own vacation modes'
    ) THEN
        CREATE POLICY "Users can manage own vacation modes"
            ON vacation_mode
            FOR ALL
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- Add helpful comments
COMMENT ON TABLE vacation_mode IS 'User-scheduled vacation mode periods that freeze streak progression (max 14 days)';
COMMENT ON COLUMN vacation_mode.is_active IS 'Whether this vacation period is currently active (can be deactivated early)';
COMMENT ON COLUMN vacation_mode.streak_at_start IS 'User streak value when vacation was activated (for reference)';
COMMENT ON COLUMN vacation_mode.deactivated_at IS 'Timestamp when vacation was manually deactivated (null if completed naturally)';
