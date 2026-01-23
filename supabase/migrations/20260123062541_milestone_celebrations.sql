-- Migration: Milestone Celebrations Table
-- Stores AI-generated personalized narratives for major level milestones (5, 10, 25, 50, 100)

CREATE TABLE IF NOT EXISTS milestone_celebrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    level_reached INT NOT NULL CHECK (level_reached IN (5, 10, 25, 50, 100)),
    narrative TEXT NOT NULL CHECK (char_length(narrative) BETWEEN 100 AND 500),
    journey_stats JSONB NOT NULL,
    generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    viewed BOOLEAN NOT NULL DEFAULT false,
    shared BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, level_reached)
);

-- Indexes
CREATE INDEX idx_milestone_celebrations_user
    ON milestone_celebrations(user_id, level_reached DESC);

CREATE INDEX idx_milestone_celebrations_unviewed
    ON milestone_celebrations(user_id, viewed) WHERE NOT viewed;

-- RLS Policies
ALTER TABLE milestone_celebrations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own milestones"
    ON milestone_celebrations FOR ALL
    USING (auth.uid() = user_id);

-- Table comment
COMMENT ON TABLE milestone_celebrations IS
    'Stores AI-generated personalized narratives for major level milestones (5, 10, 25, 50, 100)';
