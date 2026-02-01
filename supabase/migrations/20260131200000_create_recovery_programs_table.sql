-- Create recovery_programs table to persist generated recovery programs
CREATE TABLE IF NOT EXISTS recovery_programs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    target_debt_reduction DECIMAL(10,2) NOT NULL,
    daily_actions JSONB NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'abandoned')),
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for querying user's programs
CREATE INDEX idx_recovery_programs_user_id ON recovery_programs(user_id);
CREATE INDEX idx_recovery_programs_status ON recovery_programs(user_id, status);

-- RLS
ALTER TABLE recovery_programs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own recovery programs"
    ON recovery_programs FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own recovery programs"
    ON recovery_programs FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own recovery programs"
    ON recovery_programs FOR UPDATE
    USING (auth.uid() = user_id);

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION update_recovery_programs_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_recovery_programs_updated_at
    BEFORE UPDATE ON recovery_programs
    FOR EACH ROW
    EXECUTE FUNCTION update_recovery_programs_updated_at();
