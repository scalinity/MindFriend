-- =============================================================================
-- Migration: Therapeutic Programs (CBT, DBT, ACT)
-- =============================================================================
-- Extends existing programs infrastructure with clinical therapeutic features:
-- - Adds methodology field to programs for CBT/DBT/ACT/MBCT classification
-- - Creates clinical_assessments table for PHQ-9/GAD-7 tracking
-- - Creates thought_records table for CBT thought challenging
-- - Creates emotion_regulation_logs table for DBT skills tracking
-- - Creates values_assessments table for ACT values clarification
-- - Adds safety flagging for PHQ-9 Q9 (suicidal ideation detection)
-- =============================================================================

-- =============================================================================
-- PART 1: Extend existing programs table with therapeutic fields
-- =============================================================================

-- Add methodology field to classify therapeutic programs
ALTER TABLE programs ADD COLUMN IF NOT EXISTS methodology TEXT
    CHECK (methodology IS NULL OR methodology IN ('cbt', 'dbt', 'act', 'mbct', 'mixed'));

-- Add evidence-based information
ALTER TABLE programs ADD COLUMN IF NOT EXISTS evidence_summary TEXT;
ALTER TABLE programs ADD COLUMN IF NOT EXISTS evidence_url TEXT;
ALTER TABLE programs ADD COLUMN IF NOT EXISTS target_conditions TEXT[] DEFAULT '{}';

-- Add baseline assessment requirement
ALTER TABLE programs ADD COLUMN IF NOT EXISTS requires_baseline_assessment BOOLEAN DEFAULT FALSE;
ALTER TABLE programs ADD COLUMN IF NOT EXISTS assessment_type TEXT
    CHECK (assessment_type IS NULL OR assessment_type IN ('phq9', 'gad7'));

-- Add index for therapeutic programs queries
CREATE INDEX IF NOT EXISTS idx_programs_methodology
    ON programs(methodology)
    WHERE methodology IS NOT NULL;

-- Add pause tracking to enrollments for module unlock calculation
ALTER TABLE program_enrollments ADD COLUMN IF NOT EXISTS total_pause_days INT DEFAULT 0;
ALTER TABLE program_enrollments ADD COLUMN IF NOT EXISTS baseline_assessment_id UUID;
ALTER TABLE program_enrollments ADD COLUMN IF NOT EXISTS baseline_assessment_completed_at TIMESTAMPTZ;

-- =============================================================================
-- PART 2: Clinical Assessments Table (PHQ-9, GAD-7)
-- =============================================================================

CREATE TABLE IF NOT EXISTS clinical_assessments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    enrollment_id UUID REFERENCES program_enrollments(id) ON DELETE SET NULL,
    assessment_type TEXT NOT NULL CHECK (assessment_type IN ('phq9', 'gad7', 'weekly_checkin')),
    responses JSONB NOT NULL,  -- Array of 0-3 integers for each question
    total_score INT NOT NULL CHECK (total_score >= 0),
    severity TEXT NOT NULL CHECK (severity IN ('minimal', 'mild', 'moderate', 'moderately_severe', 'severe')),
    flagged_for_review BOOLEAN DEFAULT FALSE,
    assessment_point TEXT CHECK (assessment_point IN ('pre', 'weekly', 'post', 'standalone')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for clinical_assessments
CREATE INDEX IF NOT EXISTS idx_clinical_assessments_user
    ON clinical_assessments(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_clinical_assessments_enrollment
    ON clinical_assessments(enrollment_id);
CREATE INDEX IF NOT EXISTS idx_clinical_assessments_flagged
    ON clinical_assessments(flagged_for_review)
    WHERE flagged_for_review = TRUE;

-- Enable RLS
ALTER TABLE clinical_assessments ENABLE ROW LEVEL SECURITY;

-- RLS Policies for clinical_assessments
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'clinical_assessments' AND policyname = 'Users can view own assessments') THEN
        CREATE POLICY "Users can view own assessments" ON clinical_assessments
            FOR SELECT USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'clinical_assessments' AND policyname = 'Users can insert own assessments') THEN
        CREATE POLICY "Users can insert own assessments" ON clinical_assessments
            FOR INSERT WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

-- Add FK for baseline assessment on program_enrollments
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'fk_baseline_assessment'
        AND table_name = 'program_enrollments'
    ) THEN
        ALTER TABLE program_enrollments
        ADD CONSTRAINT fk_baseline_assessment
        FOREIGN KEY (baseline_assessment_id) REFERENCES clinical_assessments(id);
    END IF;
END $$;

-- =============================================================================
-- PART 3: Thought Records Table (CBT)
-- =============================================================================

CREATE TABLE IF NOT EXISTS thought_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    enrollment_id UUID REFERENCES program_enrollments(id) ON DELETE SET NULL,
    program_day_number INT,

    -- Core ABC model fields
    situation TEXT NOT NULL CHECK (char_length(situation) <= 1000),
    automatic_thought TEXT NOT NULL CHECK (char_length(automatic_thought) <= 2000),
    emotions JSONB NOT NULL, -- [{name: string, intensity: 0-100}]

    -- Evidence and reframing
    evidence_for TEXT CHECK (char_length(evidence_for) <= 2000),
    evidence_against TEXT CHECK (char_length(evidence_against) <= 2000),
    balanced_thought TEXT CHECK (char_length(balanced_thought) <= 2000),
    new_emotion_intensity INT CHECK (new_emotion_intensity IS NULL OR (new_emotion_intensity >= 0 AND new_emotion_intensity <= 100)),

    -- Cognitive distortions identified
    cognitive_distortions TEXT[] DEFAULT '{}',

    -- AI analysis (populated by edge function)
    ai_analysis JSONB,
    ai_analysis_requested_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for thought_records
CREATE INDEX IF NOT EXISTS idx_thought_records_user
    ON thought_records(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_thought_records_enrollment
    ON thought_records(enrollment_id);

-- Enable RLS
ALTER TABLE thought_records ENABLE ROW LEVEL SECURITY;

-- RLS Policies for thought_records
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'thought_records' AND policyname = 'Users can manage own thought records') THEN
        CREATE POLICY "Users can manage own thought records" ON thought_records
            FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- =============================================================================
-- PART 4: Emotion Regulation Logs Table (DBT)
-- =============================================================================

CREATE TABLE IF NOT EXISTS emotion_regulation_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    enrollment_id UUID REFERENCES program_enrollments(id) ON DELETE SET NULL,
    program_day_number INT,

    -- Trigger and emotion tracking
    triggering_event TEXT NOT NULL CHECK (char_length(triggering_event) <= 1000),
    vulnerability_factors TEXT[] DEFAULT '{}',
    emotion TEXT NOT NULL CHECK (char_length(emotion) <= 50),
    intensity_before INT CHECK (intensity_before BETWEEN 0 AND 100),

    -- Skill application
    skill_used TEXT NOT NULL CHECK (char_length(skill_used) <= 100),
    skill_steps TEXT CHECK (char_length(skill_steps) <= 2000),

    -- Outcome
    intensity_after INT CHECK (intensity_after BETWEEN 0 AND 100),
    effectiveness_rating INT CHECK (effectiveness_rating IS NULL OR effectiveness_rating BETWEEN 1 AND 5),
    notes TEXT CHECK (char_length(notes) <= 2000),

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for emotion_regulation_logs
CREATE INDEX IF NOT EXISTS idx_emotion_logs_user
    ON emotion_regulation_logs(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_emotion_logs_enrollment
    ON emotion_regulation_logs(enrollment_id);

-- Enable RLS
ALTER TABLE emotion_regulation_logs ENABLE ROW LEVEL SECURITY;

-- RLS Policies for emotion_regulation_logs
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'emotion_regulation_logs' AND policyname = 'Users can manage own emotion logs') THEN
        CREATE POLICY "Users can manage own emotion logs" ON emotion_regulation_logs
            FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- =============================================================================
-- PART 5: Values Assessments Table (ACT)
-- =============================================================================

CREATE TABLE IF NOT EXISTS values_assessments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    enrollment_id UUID REFERENCES program_enrollments(id) ON DELETE SET NULL,

    -- Life domain being assessed
    life_domain TEXT NOT NULL CHECK (life_domain IN (
        'relationships', 'family', 'parenting', 'friendships',
        'work', 'education', 'recreation', 'spirituality',
        'citizenship', 'health'
    )),

    -- Ratings
    importance_rating INT CHECK (importance_rating BETWEEN 1 AND 10),
    current_alignment INT CHECK (current_alignment BETWEEN 1 AND 10),

    -- Values statement and actions
    values_statement TEXT CHECK (char_length(values_statement) <= 1000),
    committed_actions TEXT[] DEFAULT '{}',
    barriers TEXT CHECK (char_length(barriers) <= 1000),

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for values_assessments
CREATE INDEX IF NOT EXISTS idx_values_user
    ON values_assessments(user_id, life_domain);
CREATE INDEX IF NOT EXISTS idx_values_enrollment
    ON values_assessments(enrollment_id);

-- Enable RLS
ALTER TABLE values_assessments ENABLE ROW LEVEL SECURITY;

-- RLS Policies for values_assessments
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'values_assessments' AND policyname = 'Users can manage own values assessments') THEN
        CREATE POLICY "Users can manage own values assessments" ON values_assessments
            FOR ALL USING (auth.uid() = user_id);
    END IF;
END $$;

-- =============================================================================
-- PART 6: Module Unlock Status Function
-- =============================================================================

CREATE OR REPLACE FUNCTION get_module_unlock_status(
    p_enrollment_id UUID,
    p_week_number INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_enrollment program_enrollments%ROWTYPE;
    v_program programs%ROWTYPE;
    v_is_therapeutic BOOLEAN;
    v_enrollment_date DATE;
    v_pause_days INT;
    v_required_unlock_date DATE;
    v_today DATE;
    v_is_unlocked BOOLEAN;
    v_days_until_unlock INT;
BEGIN
    -- Get enrollment
    SELECT * INTO v_enrollment
    FROM program_enrollments
    WHERE id = p_enrollment_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'error', 'ENROLLMENT_NOT_FOUND',
            'message', 'No enrollment found with the specified ID'
        );
    END IF;

    -- Verify user owns this enrollment
    IF v_enrollment.user_id != auth.uid() THEN
        RETURN jsonb_build_object(
            'error', 'ACCESS_DENIED',
            'message', 'You do not have access to this enrollment'
        );
    END IF;

    -- Get program
    SELECT * INTO v_program
    FROM programs
    WHERE id = v_enrollment.program_id;

    v_is_therapeutic := v_program.methodology IS NOT NULL;
    v_enrollment_date := v_enrollment.started_at::DATE;
    v_pause_days := COALESCE(v_enrollment.total_pause_days, 0);
    v_today := CURRENT_DATE;

    -- Calculate unlock date based on program type
    IF v_is_therapeutic AND v_program.duration_days > 7 THEN
        -- Multi-week therapeutic program: enforce weekly unlocks
        -- Week N unlocks at enrollment_date + ((N-1) * 7) days + pause_days
        v_required_unlock_date := v_enrollment_date + ((p_week_number - 1) * 7) + v_pause_days;
    ELSE
        -- Daily program or short therapeutic: day-based unlock
        v_required_unlock_date := v_enrollment_date + (p_week_number - 1) + v_pause_days;
    END IF;

    v_is_unlocked := v_today >= v_required_unlock_date;
    v_days_until_unlock := GREATEST(0, v_required_unlock_date - v_today);

    RETURN jsonb_build_object(
        'is_unlocked', v_is_unlocked,
        'unlock_date', v_required_unlock_date,
        'days_until_unlock', v_days_until_unlock,
        'is_therapeutic', v_is_therapeutic,
        'week_number', p_week_number,
        'enrollment_start', v_enrollment_date,
        'pause_days', v_pause_days
    );
END;
$$;

-- =============================================================================
-- PART 7: Assessment Score Calculation Function
-- =============================================================================

CREATE OR REPLACE FUNCTION calculate_assessment_severity(
    p_assessment_type TEXT,
    p_total_score INT
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_assessment_type = 'phq9' THEN
        -- PHQ-9 severity levels (max score 27)
        IF p_total_score >= 20 THEN RETURN 'severe';
        ELSIF p_total_score >= 15 THEN RETURN 'moderately_severe';
        ELSIF p_total_score >= 10 THEN RETURN 'moderate';
        ELSIF p_total_score >= 5 THEN RETURN 'mild';
        ELSE RETURN 'minimal';
        END IF;
    ELSIF p_assessment_type = 'gad7' THEN
        -- GAD-7 severity levels (max score 21)
        IF p_total_score >= 15 THEN RETURN 'severe';
        ELSIF p_total_score >= 10 THEN RETURN 'moderate';
        ELSIF p_total_score >= 5 THEN RETURN 'mild';
        ELSE RETURN 'minimal';
        END IF;
    ELSE
        RETURN 'minimal';
    END IF;
END;
$$;

-- =============================================================================
-- PART 8: Submit Assessment Function with Safety Flagging
-- =============================================================================

CREATE OR REPLACE FUNCTION submit_clinical_assessment(
    p_assessment_type TEXT,
    p_responses INT[],
    p_enrollment_id UUID DEFAULT NULL,
    p_assessment_point TEXT DEFAULT 'standalone'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_total_score INT;
    v_severity TEXT;
    v_flagged BOOLEAN;
    v_phq9_q9_score INT;
    v_assessment_id UUID;
    v_crisis_intervention_needed BOOLEAN := FALSE;
BEGIN
    v_user_id := auth.uid();

    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'error', 'NOT_AUTHENTICATED',
            'message', 'User must be authenticated'
        );
    END IF;

    -- Validate assessment type
    IF p_assessment_type NOT IN ('phq9', 'gad7', 'weekly_checkin') THEN
        RETURN jsonb_build_object(
            'error', 'INVALID_ASSESSMENT_TYPE',
            'message', 'Assessment type must be phq9, gad7, or weekly_checkin'
        );
    END IF;

    -- Validate response count
    IF p_assessment_type = 'phq9' AND array_length(p_responses, 1) != 9 THEN
        RETURN jsonb_build_object(
            'error', 'INVALID_RESPONSE_COUNT',
            'message', 'PHQ-9 requires exactly 9 responses'
        );
    END IF;

    IF p_assessment_type = 'gad7' AND array_length(p_responses, 1) != 7 THEN
        RETURN jsonb_build_object(
            'error', 'INVALID_RESPONSE_COUNT',
            'message', 'GAD-7 requires exactly 7 responses'
        );
    END IF;

    -- Calculate total score
    SELECT COALESCE(SUM(val), 0) INTO v_total_score
    FROM unnest(p_responses) AS val;

    -- Calculate severity
    v_severity := calculate_assessment_severity(p_assessment_type, v_total_score);

    -- Check for safety flagging
    -- Flag if: PHQ-9 Q9 >= 1 (suicidal ideation) OR total score >= 15 (moderately severe+)
    v_flagged := FALSE;

    IF p_assessment_type = 'phq9' THEN
        v_phq9_q9_score := p_responses[9];  -- Q9 is the last question (1-indexed in SQL)

        IF v_phq9_q9_score >= 1 THEN
            v_flagged := TRUE;
            v_crisis_intervention_needed := TRUE;

            -- Log crisis event for Q9 positive (suicidal ideation)
            INSERT INTO crisis_events (user_id, trigger_keyword, detected_at, source, severity)
            VALUES (v_user_id, 'PHQ9_Q9_POSITIVE', NOW(), 'assessment',
                CASE
                    WHEN v_phq9_q9_score = 3 THEN 'critical'
                    WHEN v_phq9_q9_score = 2 THEN 'high'
                    ELSE 'moderate'
                END
            );
        END IF;
    END IF;

    -- Also flag if total score indicates moderately severe or worse
    IF v_total_score >= 15 THEN
        v_flagged := TRUE;
    END IF;

    -- Insert the assessment
    INSERT INTO clinical_assessments (
        user_id, enrollment_id, assessment_type, responses,
        total_score, severity, flagged_for_review, assessment_point
    )
    VALUES (
        v_user_id, p_enrollment_id, p_assessment_type, to_jsonb(p_responses),
        v_total_score, v_severity, v_flagged, p_assessment_point
    )
    RETURNING id INTO v_assessment_id;

    -- If this is a baseline assessment, link it to the enrollment
    IF p_enrollment_id IS NOT NULL AND p_assessment_point = 'pre' THEN
        UPDATE program_enrollments
        SET baseline_assessment_id = v_assessment_id,
            baseline_assessment_completed_at = NOW()
        WHERE id = p_enrollment_id AND user_id = v_user_id;
    END IF;

    RETURN jsonb_build_object(
        'id', v_assessment_id,
        'assessment_type', p_assessment_type,
        'total_score', v_total_score,
        'severity', v_severity,
        'flagged_for_review', v_flagged,
        'crisis_intervention_needed', v_crisis_intervention_needed,
        'interpretation', CASE v_severity
            WHEN 'minimal' THEN 'Your score suggests minimal symptoms.'
            WHEN 'mild' THEN 'Your score suggests mild symptoms.'
            WHEN 'moderate' THEN 'Your score suggests moderate symptoms. Consider speaking with a mental health professional.'
            WHEN 'moderately_severe' THEN 'Your score suggests moderately severe symptoms. We recommend speaking with a mental health professional.'
            WHEN 'severe' THEN 'Your score suggests severe symptoms. Please consider reaching out to a mental health professional as soon as possible.'
        END,
        'safety_action', CASE
            WHEN v_crisis_intervention_needed THEN jsonb_build_object(
                'type', 'CRISIS_MODAL',
                'mandatory_display_seconds', 5,
                'resources', jsonb_build_array(
                    jsonb_build_object('name', '988 Suicide & Crisis Lifeline', 'action', 'call', 'value', '988'),
                    jsonb_build_object('name', 'Crisis Text Line', 'action', 'sms', 'value', '741741', 'message', 'HOME')
                )
            )
            WHEN v_severity IN ('severe', 'moderately_severe') THEN jsonb_build_object(
                'type', 'SHOW_RECOMMENDATION',
                'message', 'We recommend speaking with a mental health professional alongside this program.'
            )
            ELSE NULL
        END
    );
END;
$$;

-- =============================================================================
-- PART 9: Therapeutic Program Enrollment Limit Enforcement
-- =============================================================================

-- Use a trigger-based approach since PostgreSQL doesn't allow subqueries in partial index predicates

CREATE OR REPLACE FUNCTION check_therapeutic_enrollment_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_therapeutic BOOLEAN;
    v_existing_count INT;
BEGIN
    -- Only check on INSERT or when status changes to 'active'
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.status = 'active' AND OLD.status != 'active') THEN
        -- Check if the new enrollment is for a therapeutic program
        SELECT methodology IS NOT NULL INTO v_is_therapeutic
        FROM programs
        WHERE id = NEW.program_id;

        IF v_is_therapeutic THEN
            -- Count existing active therapeutic enrollments for this user
            SELECT COUNT(*) INTO v_existing_count
            FROM program_enrollments pe
            JOIN programs p ON pe.program_id = p.id
            WHERE pe.user_id = NEW.user_id
            AND pe.status = 'active'
            AND p.methodology IS NOT NULL
            AND pe.id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);

            IF v_existing_count > 0 THEN
                RAISE EXCEPTION 'User can only have one active therapeutic program enrollment at a time'
                    USING ERRCODE = 'unique_violation';
            END IF;
        ELSE
            -- Count existing active general enrollments for this user
            SELECT COUNT(*) INTO v_existing_count
            FROM program_enrollments pe
            JOIN programs p ON pe.program_id = p.id
            WHERE pe.user_id = NEW.user_id
            AND pe.status = 'active'
            AND p.methodology IS NULL
            AND pe.id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);

            IF v_existing_count > 0 THEN
                RAISE EXCEPTION 'User can only have one active general program enrollment at a time'
                    USING ERRCODE = 'unique_violation';
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- Create the trigger
DROP TRIGGER IF EXISTS enforce_enrollment_limits ON program_enrollments;
CREATE TRIGGER enforce_enrollment_limits
    BEFORE INSERT OR UPDATE ON program_enrollments
    FOR EACH ROW
    EXECUTE FUNCTION check_therapeutic_enrollment_limit();

-- =============================================================================
-- PART 10: Grant execute permissions
-- =============================================================================

GRANT EXECUTE ON FUNCTION get_module_unlock_status(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION calculate_assessment_severity(TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION submit_clinical_assessment(TEXT, INT[], UUID, TEXT) TO authenticated;

-- =============================================================================
-- PART 11: Comments for documentation
-- =============================================================================

COMMENT ON TABLE clinical_assessments IS 'Clinical screening assessments (PHQ-9 for depression, GAD-7 for anxiety) with safety flagging';
COMMENT ON TABLE thought_records IS 'CBT thought records following the ABC model (Activating event, Belief, Consequence)';
COMMENT ON TABLE emotion_regulation_logs IS 'DBT emotion regulation skill usage logs';
COMMENT ON TABLE values_assessments IS 'ACT values clarification and committed action tracking';

COMMENT ON COLUMN clinical_assessments.flagged_for_review IS 'True if PHQ-9 Q9 >= 1 (suicidal ideation) or total score >= 15';
COMMENT ON COLUMN thought_records.cognitive_distortions IS 'Array of distortion types: all_or_nothing, overgeneralization, mental_filter, discounting_positive, jumping_to_conclusions, magnification, emotional_reasoning, should_statements, labeling, personalization';
COMMENT ON COLUMN programs.methodology IS 'Therapeutic methodology: cbt (Cognitive Behavioral Therapy), dbt (Dialectical Behavior Therapy), act (Acceptance & Commitment Therapy), mbct (Mindfulness-Based Cognitive Therapy), mixed';
