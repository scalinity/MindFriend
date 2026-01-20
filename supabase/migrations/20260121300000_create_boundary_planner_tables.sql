-- Boundary & Needs Planner Feature
-- Migration: Create tables, RLS policies, indexes, triggers
-- Date: 2026-01-21

-- ============================================================================
-- TABLES
-- ============================================================================

-- Needs Assessments
CREATE TABLE IF NOT EXISTS needs_assessments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    assessment_type TEXT NOT NULL CHECK (assessment_type IN ('work', 'relationships', 'family', 'friends')),
    responses JSONB NOT NULL,
    top_needs TEXT[],
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Defined Boundaries
CREATE TABLE IF NOT EXISTS defined_boundaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    needs_assessment_id UUID REFERENCES needs_assessments(id),
    boundary_type TEXT NOT NULL CHECK (boundary_type IN ('time', 'emotional', 'digital', 'physical', 'financial')),
    statement_text TEXT NOT NULL CHECK (char_length(statement_text) >= 10),
    why_matters TEXT,
    stakeholder TEXT,
    expected_impact TEXT,
    status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'ready', 'practiced', 'set', 'adjusted', 'archived')),
    scripts JSONB,
    practice_count INTEGER DEFAULT 0 NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Boundary Follow-Ups
CREATE TABLE IF NOT EXISTS boundary_follow_ups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    boundary_id UUID REFERENCES defined_boundaries(id) ON DELETE CASCADE NOT NULL,
    check_in_at TIMESTAMPTZ NOT NULL,
    outcome TEXT CHECK (outcome IN ('successful', 'partially_successful', 'challenged', 'ignored')),
    notes TEXT,
    user_reflection TEXT,
    next_action TEXT,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Script Templates
CREATE TABLE IF NOT EXISTS boundary_script_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    boundary_type TEXT NOT NULL,
    relationship_type TEXT NOT NULL,
    template_variation TEXT NOT NULL CHECK (template_variation IN ('direct', 'gentle', 'assertive', 'collaborative')),
    template_text TEXT NOT NULL,
    tone_description TEXT,
    example_context TEXT,
    locale TEXT NOT NULL DEFAULT 'en' CHECK (locale IN ('en', 'es', 'pt')),
    is_premium BOOLEAN DEFAULT false NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_needs_assessments_user_created
    ON needs_assessments(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_defined_boundaries_user_created
    ON defined_boundaries(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_defined_boundaries_status
    ON defined_boundaries(user_id, status);

CREATE INDEX IF NOT EXISTS idx_boundary_follow_ups_boundary
    ON boundary_follow_ups(boundary_id);

CREATE INDEX IF NOT EXISTS idx_boundary_follow_ups_pending
    ON boundary_follow_ups(check_in_at)
    WHERE completed_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_script_templates_lookup
    ON boundary_script_templates(boundary_type, relationship_type, locale);

CREATE INDEX IF NOT EXISTS idx_script_templates_premium
    ON boundary_script_templates(is_premium)
    WHERE is_premium = true;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Updated_at trigger function (idempotent)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
DROP TRIGGER IF EXISTS update_needs_assessments_updated_at ON needs_assessments;
CREATE TRIGGER update_needs_assessments_updated_at
    BEFORE UPDATE ON needs_assessments
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_defined_boundaries_updated_at ON defined_boundaries;
CREATE TRIGGER update_defined_boundaries_updated_at
    BEFORE UPDATE ON defined_boundaries
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- CONVERSATION REHEARSAL INTEGRATION
-- ============================================================================

-- Extend custom_scenarios table for practice tracking
-- Note: custom_scenarios table must exist from Conversation Rehearsal feature
ALTER TABLE custom_scenarios
ADD COLUMN IF NOT EXISTS source_feature TEXT,
ADD COLUMN IF NOT EXISTS source_id UUID;

CREATE INDEX IF NOT EXISTS idx_custom_scenarios_source
    ON custom_scenarios(source_feature, source_id);

-- Practice count synchronization trigger
CREATE OR REPLACE FUNCTION increment_boundary_practice_count()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.source_feature = 'boundary_planner' THEN
        UPDATE defined_boundaries
        SET practice_count = practice_count + 1,
            updated_at = NOW()
        WHERE id = NEW.source_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS sync_boundary_practice_count ON custom_scenarios;
CREATE TRIGGER sync_boundary_practice_count
AFTER INSERT ON custom_scenarios
FOR EACH ROW
WHEN (NEW.source_feature = 'boundary_planner')
EXECUTE FUNCTION increment_boundary_practice_count();

-- ============================================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================================

-- Enable RLS
ALTER TABLE needs_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE defined_boundaries ENABLE ROW LEVEL SECURITY;
ALTER TABLE boundary_follow_ups ENABLE ROW LEVEL SECURITY;
ALTER TABLE boundary_script_templates ENABLE ROW LEVEL SECURITY;

-- needs_assessments policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'needs_assessments' AND policyname = 'Users can read own assessments'
    ) THEN
        CREATE POLICY "Users can read own assessments"
            ON needs_assessments FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'needs_assessments' AND policyname = 'Users can insert own assessments'
    ) THEN
        CREATE POLICY "Users can insert own assessments"
            ON needs_assessments FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'needs_assessments' AND policyname = 'Users can update own assessments'
    ) THEN
        CREATE POLICY "Users can update own assessments"
            ON needs_assessments FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'needs_assessments' AND policyname = 'Users can delete own assessments'
    ) THEN
        CREATE POLICY "Users can delete own assessments"
            ON needs_assessments FOR DELETE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- defined_boundaries policies
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'defined_boundaries' AND policyname = 'Users can read own boundaries'
    ) THEN
        CREATE POLICY "Users can read own boundaries"
            ON defined_boundaries FOR SELECT
            USING (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'defined_boundaries' AND policyname = 'Users can insert own boundaries'
    ) THEN
        CREATE POLICY "Users can insert own boundaries"
            ON defined_boundaries FOR INSERT
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'defined_boundaries' AND policyname = 'Users can update own boundaries'
    ) THEN
        CREATE POLICY "Users can update own boundaries"
            ON defined_boundaries FOR UPDATE
            USING (auth.uid() = user_id)
            WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'defined_boundaries' AND policyname = 'Users can delete own boundaries'
    ) THEN
        CREATE POLICY "Users can delete own boundaries"
            ON defined_boundaries FOR DELETE
            USING (auth.uid() = user_id);
    END IF;
END $$;

-- boundary_follow_ups policies (JOIN-based access control)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'boundary_follow_ups' AND policyname = 'Users can read follow-ups for own boundaries'
    ) THEN
        CREATE POLICY "Users can read follow-ups for own boundaries"
            ON boundary_follow_ups FOR SELECT
            USING (EXISTS (
                SELECT 1 FROM defined_boundaries
                WHERE defined_boundaries.id = boundary_follow_ups.boundary_id
                AND defined_boundaries.user_id = auth.uid()
            ));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'boundary_follow_ups' AND policyname = 'Users can insert follow-ups for own boundaries'
    ) THEN
        CREATE POLICY "Users can insert follow-ups for own boundaries"
            ON boundary_follow_ups FOR INSERT
            WITH CHECK (EXISTS (
                SELECT 1 FROM defined_boundaries
                WHERE defined_boundaries.id = boundary_follow_ups.boundary_id
                AND defined_boundaries.user_id = auth.uid()
            ));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'boundary_follow_ups' AND policyname = 'Users can update own boundary follow-ups'
    ) THEN
        CREATE POLICY "Users can update own boundary follow-ups"
            ON boundary_follow_ups FOR UPDATE
            USING (EXISTS (
                SELECT 1 FROM defined_boundaries
                WHERE defined_boundaries.id = boundary_follow_ups.boundary_id
                AND defined_boundaries.user_id = auth.uid()
            ))
            WITH CHECK (EXISTS (
                SELECT 1 FROM defined_boundaries
                WHERE defined_boundaries.id = boundary_follow_ups.boundary_id
                AND defined_boundaries.user_id = auth.uid()
            ));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'boundary_follow_ups' AND policyname = 'Users can delete own boundary follow-ups'
    ) THEN
        CREATE POLICY "Users can delete own boundary follow-ups"
            ON boundary_follow_ups FOR DELETE
            USING (EXISTS (
                SELECT 1 FROM defined_boundaries
                WHERE defined_boundaries.id = boundary_follow_ups.boundary_id
                AND defined_boundaries.user_id = auth.uid()
            ));
    END IF;
END $$;

-- boundary_script_templates policies (read-only for authenticated users)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'boundary_script_templates' AND policyname = 'Authenticated users can read templates'
    ) THEN
        CREATE POLICY "Authenticated users can read templates"
            ON boundary_script_templates FOR SELECT
            TO authenticated
            USING (true);
    END IF;
END $$;
