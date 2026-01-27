-- Migration: Life Transition Pathways (F015)
-- Created: 2026-01-25
-- Purpose: Add structured support programs for major life transitions

-- Table 1: Transition pathway definitions
CREATE TABLE IF NOT EXISTS transition_pathways (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL CHECK (length(name) BETWEEN 3 AND 50),
    description TEXT NOT NULL CHECK (length(description) BETWEEN 10 AND 200),
    category TEXT NOT NULL CHECK (category IN (
        'career', 'relationship', 'loss', 'family', 'health', 'life_stage'
    )),
    duration_weeks INTEGER NOT NULL CHECK (duration_weeks BETWEEN 4 AND 12),
    phases JSONB NOT NULL,
    is_premium BOOLEAN NOT NULL DEFAULT true,
    icon_name TEXT NOT NULL,
    color TEXT NOT NULL CHECK (color ~ '^#[0-9A-F]{6}$'),
    crisis_resources JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Table 2: Pathway phases content
CREATE TABLE IF NOT EXISTS pathway_phases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pathway_id UUID NOT NULL REFERENCES transition_pathways(id) ON DELETE CASCADE,
    phase_number INTEGER NOT NULL CHECK (phase_number BETWEEN 1 AND 4),
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    duration_days INTEGER NOT NULL CHECK (duration_days BETWEEN 7 AND 28),
    objectives TEXT[] NOT NULL,
    daily_themes JSONB NOT NULL,
    exercises TEXT[] NOT NULL,
    journal_prompts TEXT[] NOT NULL,
    milestones JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(pathway_id, phase_number)
);

-- Table 3: User pathway enrollments
CREATE TABLE IF NOT EXISTS user_pathways (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    pathway_id UUID NOT NULL REFERENCES transition_pathways(id),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    current_phase INTEGER NOT NULL DEFAULT 1 CHECK (current_phase BETWEEN 1 AND 4),
    current_day INTEGER NOT NULL DEFAULT 1 CHECK (current_day > 0),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN (
        'active', 'paused', 'completed', 'abandoned'
    )),
    paused_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    personalization JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT unique_active_pathway UNIQUE(user_id, pathway_id, status)
);

-- Table 4: Daily progress and check-ins
CREATE TABLE IF NOT EXISTS pathway_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_pathway_id UUID NOT NULL REFERENCES user_pathways(id) ON DELETE CASCADE,
    day_number INTEGER NOT NULL CHECK (day_number > 0),
    phase_number INTEGER NOT NULL CHECK (phase_number BETWEEN 1 AND 4),
    check_in_completed BOOLEAN NOT NULL DEFAULT false,
    check_in_data JSONB,
    exercises_completed TEXT[] NOT NULL DEFAULT ARRAY[]::text[],
    journal_entry TEXT CHECK (length(journal_entry) <= 10000),
    milestones_achieved TEXT[] NOT NULL DEFAULT ARRAY[]::text[],
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_pathway_id, day_number)
);

-- Table 5: Pathway milestones
CREATE TABLE IF NOT EXISTS pathway_milestones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_pathway_id UUID NOT NULL REFERENCES user_pathways(id) ON DELETE CASCADE,
    milestone_key TEXT NOT NULL,
    achieved_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    phase_number INTEGER NOT NULL CHECK (phase_number BETWEEN 1 AND 4),
    celebration_shown BOOLEAN NOT NULL DEFAULT false,
    UNIQUE(user_pathway_id, milestone_key)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_transition_pathways_category ON transition_pathways(category);
CREATE INDEX IF NOT EXISTS idx_user_pathways_user ON user_pathways(user_id);
CREATE INDEX IF NOT EXISTS idx_user_pathways_active ON user_pathways(user_id, status) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_pathway_progress_user ON pathway_progress(user_pathway_id, day_number);
CREATE INDEX IF NOT EXISTS idx_pathway_milestones_user ON pathway_milestones(user_pathway_id);

-- RLS Policies
ALTER TABLE transition_pathways ENABLE ROW LEVEL SECURITY;
ALTER TABLE pathway_phases ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_pathways ENABLE ROW LEVEL SECURITY;
ALTER TABLE pathway_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE pathway_milestones ENABLE ROW LEVEL SECURITY;

-- RLS: Anyone can view pathways
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'transition_pathways' AND policyname = 'Anyone can view pathways'
    ) THEN
        CREATE POLICY "Anyone can view pathways" ON transition_pathways
            FOR SELECT USING (true);
    END IF;
END $$;

-- RLS: Anyone can view phases
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'pathway_phases' AND policyname = 'Anyone can view phases'
    ) THEN
        CREATE POLICY "Anyone can view phases" ON pathway_phases
            FOR SELECT USING (true);
    END IF;
END $$;

-- RLS: Users can manage own pathways
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'user_pathways' AND policyname = 'Users can manage own pathways'
    ) THEN
        CREATE POLICY "Users can manage own pathways" ON user_pathways
            FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- RLS: Users can manage own progress
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'pathway_progress' AND policyname = 'Users can manage own progress'
    ) THEN
        CREATE POLICY "Users can manage own progress" ON pathway_progress
            FOR ALL USING (
                user_pathway_id IN (
                    SELECT id FROM user_pathways WHERE user_id = auth.uid()
                )
            );
    END IF;
END $$;

-- RLS: Users can view own milestones
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE tablename = 'pathway_milestones' AND policyname = 'Users can view own milestones'
    ) THEN
        CREATE POLICY "Users can view own milestones" ON pathway_milestones
            FOR ALL USING (
                user_pathway_id IN (
                    SELECT id FROM user_pathways WHERE user_id = auth.uid()
                )
            );
    END IF;
END $$;

-- Add active_transition column to profiles if not exists
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'profiles' AND column_name = 'active_transition'
    ) THEN
        ALTER TABLE profiles ADD COLUMN active_transition TEXT;
    END IF;
END $$;

-- Seed Data: Transition Pathways

-- Job Loss / Career Transition
INSERT INTO transition_pathways (key, name, description, category, duration_weeks, phases, icon_name, color, crisis_resources)
VALUES (
    'job_loss',
    'Career Transition',
    'Navigate job loss or career change with structured support',
    'career',
    8,
    '[
       {"number": 1, "name": "Acknowledge", "focus": "Processing the change and initial emotions"},
       {"number": 2, "name": "Stabilize", "focus": "Creating routine and self-care foundation"},
       {"number": 3, "name": "Reflect", "focus": "Understanding what you want next"},
       {"number": 4, "name": "Rebuild", "focus": "Taking action toward your goals"}
     ]'::jsonb,
    'briefcase.fill',
    '#5C6BC0',
    '{"hotline": "211", "resources": ["unemployment_benefits", "career_counseling"]}'::jsonb
)
ON CONFLICT (key) DO NOTHING;

-- Relationship Ending
INSERT INTO transition_pathways (key, name, description, category, duration_weeks, phases, icon_name, color)
VALUES (
    'breakup',
    'Relationship Ending',
    'Heal and grow after a breakup or divorce',
    'relationship',
    10,
    '[
       {"number": 1, "name": "Acknowledge", "focus": "Allowing yourself to feel"},
       {"number": 2, "name": "Grieve", "focus": "Processing loss and memories"},
       {"number": 3, "name": "Rediscover", "focus": "Reconnecting with yourself"},
       {"number": 4, "name": "Grow", "focus": "Building your new chapter"}
     ]'::jsonb,
    'heart.slash.fill',
    '#EC407A'
)
ON CONFLICT (key) DO NOTHING;

-- Grief and Loss
INSERT INTO transition_pathways (key, name, description, category, duration_weeks, phases, icon_name, color, crisis_resources)
VALUES (
    'grief',
    'Grief Journey',
    'Compassionate support through loss of a loved one',
    'loss',
    12,
    '[
       {"number": 1, "name": "Shock", "focus": "Gentle support through initial grief"},
       {"number": 2, "name": "Feel", "focus": "Space for all emotions"},
       {"number": 3, "name": "Remember", "focus": "Honoring memories and connection"},
       {"number": 4, "name": "Adapt", "focus": "Finding a new normal"}
     ]'::jsonb,
    'leaf.fill',
    '#78909C',
    '{"hotline": "988", "resources": ["grief_counseling", "support_groups"]}'::jsonb
)
ON CONFLICT (key) DO NOTHING;

-- New Parent
INSERT INTO transition_pathways (key, name, description, category, duration_weeks, phases, icon_name, color)
VALUES (
    'new_parent',
    'New Parent Journey',
    'Support through the transition to parenthood',
    'family',
    12,
    '[
       {"number": 1, "name": "Adjust", "focus": "Adapting to your new reality"},
       {"number": 2, "name": "Bond", "focus": "Building connection and confidence"},
       {"number": 3, "name": "Balance", "focus": "Finding your rhythm"},
       {"number": 4, "name": "Thrive", "focus": "Growing into your role"}
     ]'::jsonb,
    'figure.and.child.holdinghands',
    '#66BB6A'
)
ON CONFLICT (key) DO NOTHING;

-- Major Move / Relocation
INSERT INTO transition_pathways (key, name, description, category, duration_weeks, phases, icon_name, color)
VALUES (
    'relocation',
    'New Beginnings',
    'Navigate a major move or relocation',
    'life_stage',
    6,
    '[
       {"number": 1, "name": "Farewell", "focus": "Honoring what you''re leaving"},
       {"number": 2, "name": "Settle", "focus": "Creating comfort in the new"},
       {"number": 3, "name": "Explore", "focus": "Discovering your new environment"},
       {"number": 4, "name": "Root", "focus": "Building community and belonging"}
     ]'::jsonb,
    'house.fill',
    '#42A5F5'
)
ON CONFLICT (key) DO NOTHING;

-- Health Diagnosis
INSERT INTO transition_pathways (key, name, description, category, duration_weeks, phases, icon_name, color, crisis_resources)
VALUES (
    'health_diagnosis',
    'Health Journey',
    'Support through a new health diagnosis',
    'health',
    8,
    '[
       {"number": 1, "name": "Process", "focus": "Understanding and accepting"},
       {"number": 2, "name": "Learn", "focus": "Building knowledge and support"},
       {"number": 3, "name": "Adapt", "focus": "Adjusting your life"},
       {"number": 4, "name": "Live", "focus": "Moving forward with purpose"}
     ]'::jsonb,
    'heart.text.square.fill',
    '#EF5350',
    '{"hotline": "988", "resources": ["patient_advocacy", "support_groups"]}'::jsonb
)
ON CONFLICT (key) DO NOTHING;
