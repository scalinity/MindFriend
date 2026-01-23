-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Assessment Templates (Define available assessments: PHQ-9, GAD-7, etc.)
CREATE TABLE IF NOT EXISTS assessment_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE, -- 'PHQ9', 'GAD7', 'WHO5', 'PSS10', 'WEMWBS'
    name TEXT NOT NULL,
    description TEXT,
    questions JSONB NOT NULL, -- Array of {id, text}
    scoring_ranges JSONB NOT NULL, -- Array of {min, max, level, label}
    recommended_frequency_days INTEGER NOT NULL DEFAULT 14,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Assessment Responses (User-submitted answers and calculated scores)
CREATE TABLE IF NOT EXISTS assessment_responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    assessment_template_id UUID NOT NULL REFERENCES assessment_templates(id) ON DELETE RESTRICT,
    
    -- Responses
    answers JSONB NOT NULL, -- {question_id: answer_value} where answer is 0-3
    total_score INTEGER NOT NULL,
    severity_level TEXT NOT NULL DEFAULT 'minimal', -- App-side validation (per-assessment enums)
    
    -- Context
    is_baseline BOOLEAN DEFAULT false,
    notes TEXT,
    
    completed_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Ensure score is non-negative
    CONSTRAINT valid_score CHECK (total_score >= 0 AND total_score <= 100)
);

-- Assessment Schedule (Track when each user should complete each assessment)
CREATE TABLE IF NOT EXISTS assessment_schedule (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    assessment_template_id UUID NOT NULL REFERENCES assessment_templates(id) ON DELETE CASCADE,
    
    next_due_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '14 days'),
    last_completed_at TIMESTAMPTZ,
    reminder_sent BOOLEAN DEFAULT false,
    
    -- User preferences
    enabled BOOLEAN DEFAULT true,
    custom_frequency_days INTEGER, -- Override default (if set)
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Each user can have at most one schedule per assessment
    UNIQUE(user_id, assessment_template_id)
);

-- Outcome Goals (User-defined improvement targets based on assessment scores)
CREATE TABLE IF NOT EXISTS outcome_goals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    assessment_template_id UUID NOT NULL REFERENCES assessment_templates(id) ON DELETE CASCADE,
    
    target_score INTEGER NOT NULL,
    target_date DATE,
    baseline_score INTEGER NOT NULL,
    baseline_date DATE NOT NULL,
    
    achieved BOOLEAN DEFAULT false,
    achieved_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Target score must be >= 0
    CONSTRAINT valid_target_score CHECK (target_score >= 0 AND target_score <= 100),
    CONSTRAINT valid_baseline_score CHECK (baseline_score >= 0 AND baseline_score <= 100)
);

-- Crisis Events (Log self-harm risk indicators for clinical audit trail)
CREATE TABLE IF NOT EXISTS assessment_crisis_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    assessment_template_id UUID NOT NULL REFERENCES assessment_templates(id) ON DELETE CASCADE,
    assessment_response_id UUID NOT NULL REFERENCES assessment_responses(id) ON DELETE CASCADE,
    
    event_type TEXT NOT NULL, -- 'phq9_q9_scored', 'anxiety_spike', 'depression_worsening'
    severity TEXT NOT NULL DEFAULT 'low', -- 'low', 'medium', 'high', 'critical'
    context JSONB DEFAULT '{}', -- Any additional context
    
    responded_at TIMESTAMPTZ,
    response_action TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE assessment_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE assessment_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE assessment_schedule ENABLE ROW LEVEL SECURITY;
ALTER TABLE outcome_goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE assessment_crisis_events ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Assessment Templates (readable by all authenticated users)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'assessment_templates'
        AND policyname = 'assessment_templates_read_all'
    ) THEN
        CREATE POLICY "assessment_templates_read_all"
            ON assessment_templates FOR SELECT
            USING (auth.role() = 'authenticated' AND is_active = true);
    END IF;
END $$;

-- RLS Policies: Assessment Responses (users manage own responses)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'assessment_responses'
        AND policyname = 'assessment_responses_users_own'
    ) THEN
        CREATE POLICY "assessment_responses_users_own"
            ON assessment_responses FOR ALL
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- RLS Policies: Assessment Schedule (users manage own schedule)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'assessment_schedule'
        AND policyname = 'assessment_schedule_users_own'
    ) THEN
        CREATE POLICY "assessment_schedule_users_own"
            ON assessment_schedule FOR ALL
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- RLS Policies: Outcome Goals (users manage own goals)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'outcome_goals'
        AND policyname = 'outcome_goals_users_own'
    ) THEN
        CREATE POLICY "outcome_goals_users_own"
            ON outcome_goals FOR ALL
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- RLS Policies: Crisis Events (users can view/insert own events, service role can read all)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'assessment_crisis_events'
        AND policyname = 'assessment_crisis_events_users_own'
    ) THEN
        CREATE POLICY "assessment_crisis_events_users_own"
            ON assessment_crisis_events FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'assessment_crisis_events'
        AND policyname = 'assessment_crisis_events_users_insert'
    ) THEN
        CREATE POLICY "assessment_crisis_events_users_insert"
            ON assessment_crisis_events FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_assessment_responses_user_date 
    ON assessment_responses(user_id, completed_at DESC);

CREATE INDEX IF NOT EXISTS idx_assessment_responses_user_template 
    ON assessment_responses(user_id, assessment_template_id);

CREATE INDEX IF NOT EXISTS idx_assessment_schedule_due 
    ON assessment_schedule(next_due_at) 
    WHERE enabled = true;

CREATE INDEX IF NOT EXISTS idx_assessment_schedule_user_template 
    ON assessment_schedule(user_id, assessment_template_id);

CREATE INDEX IF NOT EXISTS idx_outcome_goals_user_active 
    ON outcome_goals(user_id, achieved) 
    WHERE achieved = false;

CREATE INDEX IF NOT EXISTS idx_assessment_crisis_events_user_date 
    ON assessment_crisis_events(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_assessment_crisis_events_severity 
    ON assessment_crisis_events(severity) 
    WHERE severity IN ('high', 'critical');

-- Add trigger to update updated_at timestamps
CREATE OR REPLACE FUNCTION update_updated_at_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_assessment_templates_updated_at
    BEFORE UPDATE ON assessment_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_timestamp();

CREATE TRIGGER update_assessment_schedule_updated_at
    BEFORE UPDATE ON assessment_schedule
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_timestamp();

CREATE TRIGGER update_outcome_goals_updated_at
    BEFORE UPDATE ON outcome_goals
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_timestamp();
