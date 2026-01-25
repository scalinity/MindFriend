-- Migration: Pathway Architecture Improvements
-- Description: Transaction safety, performance optimization, content externalization
-- Date: 2026-01-25

-- ==========================================
-- 1. Add current_phase_day for performance
-- ==========================================

ALTER TABLE user_pathways ADD COLUMN IF NOT EXISTS current_phase_day INT DEFAULT 1 CHECK (current_phase_day > 0);

-- Backfill for existing records (calculate from current_day)
UPDATE user_pathways
SET current_phase_day = 1
WHERE current_phase_day IS NULL;

-- ==========================================
-- 2. Transaction-safe enrollment function
-- ==========================================

CREATE OR REPLACE FUNCTION enroll_user_in_pathway(
    p_user_id UUID,
    p_pathway_id UUID,
    p_personalization JSONB,
    p_context_content TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_pathway_id UUID;
    v_pathway_key TEXT;
    v_result JSONB;
BEGIN
    -- ✅ CRITICAL SECURITY CHECK: Verify user ownership
    IF p_user_id != auth.uid() THEN
        RAISE EXCEPTION 'Unauthorized: Cannot enroll pathway for another user';
    END IF;

    -- Get pathway key for profile update
    SELECT key INTO v_pathway_key FROM transition_pathways WHERE id = p_pathway_id;

    -- 1. Create user_pathways record
    INSERT INTO user_pathways (
        user_id,
        pathway_id,
        current_phase,
        current_day,
        current_phase_day,
        status,
        personalization,
        started_at
    ) VALUES (
        p_user_id,
        p_pathway_id,
        1,
        1,
        1,
        'active',
        p_personalization,
        now()
    )
    RETURNING id INTO v_user_pathway_id;

    -- 2. Update companion memory
    INSERT INTO companion_memory (
        user_id,
        category,
        content,
        importance,
        expires_at
    ) VALUES (
        p_user_id,
        'life_event',
        p_context_content,
        0.95,
        NULL
    );

    -- 3. Update profile
    UPDATE profiles
    SET
        active_transition = v_pathway_key,
        updated_at = now()
    WHERE id = p_user_id;

    -- 4. Create initial progress record
    INSERT INTO pathway_progress (
        user_pathway_id,
        day_number,
        phase_number,
        check_in_completed
    ) VALUES (
        v_user_pathway_id,
        1,
        1,
        false
    );

    -- Return the user pathway ID
    v_result := jsonb_build_object('user_pathway_id', v_user_pathway_id);
    RETURN v_result;

END;
$$;

-- ==========================================
-- 3. Transaction-safe check-in function
-- ==========================================

-- ✅ NOTE: This function is superseded by 20260125090000_fix_phase_advancement_logic.sql
-- Keeping for migration history; later migration adds pathwayCompleted and fixes off-by-one error
CREATE OR REPLACE FUNCTION submit_pathway_checkin(
    p_user_pathway_id UUID,
    p_check_in_data JSONB,
    p_exercises_completed TEXT[],
    p_journal_entry TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_day INT;
    v_current_phase INT;
    v_current_phase_day INT;
    v_pathway_id UUID;
    v_phase_duration INT;
    v_should_advance BOOLEAN := false;
    v_new_phase INT;
    v_new_day INT;
    v_new_phase_day INT;
    v_pathway_completed BOOLEAN := false;
    v_result JSONB;
BEGIN
    -- Get current pathway state
    SELECT current_day, current_phase, current_phase_day, pathway_id
    INTO v_current_day, v_current_phase, v_current_phase_day, v_pathway_id
    FROM user_pathways
    WHERE id = p_user_pathway_id;

    -- Get current phase duration
    SELECT duration_days INTO v_phase_duration
    FROM pathway_phases
    WHERE pathway_id = v_pathway_id
    AND phase_number = v_current_phase;

    -- Calculate new values
    v_new_day := v_current_day + 1;
    v_new_phase := v_current_phase;
    v_new_phase_day := v_current_phase_day + 1;

    -- Check if we should advance phase (NOTE: off-by-one error fixed in later migration)
    IF v_current_phase_day >= v_phase_duration THEN
        v_should_advance := true;
        v_new_phase := v_current_phase + 1;
        v_new_phase_day := 1;
    END IF;

    -- 1. Insert progress record
    INSERT INTO pathway_progress (
        user_pathway_id,
        day_number,
        phase_number,
        check_in_completed,
        check_in_data,
        exercises_completed,
        journal_entry,
        milestones_achieved
    ) VALUES (
        p_user_pathway_id,
        v_current_day,
        v_current_phase,
        true,
        p_check_in_data,
        p_exercises_completed,
        p_journal_entry,
        '{}'::TEXT[]
    );

    -- 2. Update pathway state
    UPDATE user_pathways
    SET
        current_day = v_new_day,
        current_phase = v_new_phase,
        current_phase_day = v_new_phase_day,
        updated_at = now()
    WHERE id = p_user_pathway_id;

    -- Build result
    v_result := jsonb_build_object(
        'success', true,
        'newDay', v_new_day,
        'newPhase', v_new_phase,
        'phaseAdvanced', v_should_advance,
        'pathwayCompleted', v_pathway_completed
    );

    RETURN v_result;

END;
$$;

-- ==========================================
-- 4. Content templates table
-- ==========================================

CREATE TABLE IF NOT EXISTS pathway_content_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category TEXT NOT NULL CHECK (category IN ('checkin_prompt', 'affirmation')),
    phase_name TEXT NOT NULL,
    pathway_key TEXT,
    content TEXT[] NOT NULL,
    locale TEXT DEFAULT 'en',
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(category, phase_name, pathway_key, locale)
);

-- Enable RLS
ALTER TABLE pathway_content_templates ENABLE ROW LEVEL SECURITY;

-- Public read access for all authenticated users
CREATE POLICY "Content templates readable by all authenticated users"
    ON pathway_content_templates FOR SELECT
    TO authenticated
    USING (true);

-- ==========================================
-- 5. Seed check-in prompts
-- ==========================================

INSERT INTO pathway_content_templates (category, phase_name, pathway_key, content) VALUES
('checkin_prompt', 'Acknowledge', NULL, ARRAY[
    'How are you feeling today?',
    'What emotions have come up since yesterday?',
    'How did you sleep last night?',
    'What''s one small thing you did for yourself today?'
]),
('checkin_prompt', 'Stabilize', NULL, ARRAY[
    'What small step forward did you take today?',
    'How are you adjusting to the changes?',
    'What new routine is helping you?',
    'What challenge can you release today?'
]),
('checkin_prompt', 'Process', NULL, ARRAY[
    'What came up for you in reflection yesterday?',
    'How is your body feeling today?',
    'What support do you need right now?',
    'What are you grateful for despite everything?'
]),
('checkin_prompt', 'Grieve', NULL, ARRAY[
    'What came up for you in reflection yesterday?',
    'How is your body feeling today?',
    'What support do you need right now?',
    'What are you grateful for despite everything?'
]),
('checkin_prompt', 'Reflect', NULL, ARRAY[
    'What insights have emerged for you?',
    'What patterns are you noticing?',
    'What do you need more of in your life?',
    'What''s one thing you''re learning about yourself?'
]),
('checkin_prompt', 'Rebuild', NULL, ARRAY[
    'What action are you proud of taking?',
    'What progress have you made this week?',
    'What''s your next small step?',
    'How are you feeling about your future?'
]),
('checkin_prompt', 'Shock', NULL, ARRAY[
    'How are you feeling right now?',
    'What do you need in this moment?',
    'Are you taking care of your basic needs?',
    'Who can you reach out to for support?'
]),
('checkin_prompt', 'Feel', NULL, ARRAY[
    'What emotions showed up today?',
    'How did you honor your feelings?',
    'What helped you cope today?',
    'What are you allowing yourself to feel?'
]),
('checkin_prompt', 'Remember', NULL, ARRAY[
    'What memory brought you comfort?',
    'How are you honoring their presence?',
    'What would you like to remember today?',
    'What connection did you feel?'
]),
('checkin_prompt', 'Adapt', NULL, ARRAY[
    'How are you finding your new rhythm?',
    'What''s working in your new normal?',
    'What adjustment felt right today?',
    'How are you moving forward?'
]),
('checkin_prompt', 'Adjust', NULL, ARRAY[
    'How did you adapt today?',
    'What''s been surprisingly okay?',
    'What support helped you?',
    'What''s one win, no matter how small?'
]),
('checkin_prompt', 'Bond', NULL, ARRAY[
    'What moment of connection did you have?',
    'How did you show up for yourself and others?',
    'What brought you joy today?',
    'What are you learning about this relationship?'
]),
('checkin_prompt', 'Balance', NULL, ARRAY[
    'How did you care for yourself today?',
    'What worked in your routine?',
    'What do you need to let go of?',
    'Where did you find your balance?'
]),
('checkin_prompt', 'Thrive', NULL, ARRAY[
    'What are you proud of?',
    'How has your perspective shifted?',
    'What excites you about the future?',
    'How will you celebrate your growth?'
]),
('checkin_prompt', 'Farewell', NULL, ARRAY[
    'What are you grateful for leaving?',
    'What do you want to carry forward?',
    'How are you honoring this transition?',
    'What are you saying goodbye to?'
]),
('checkin_prompt', 'Settle', NULL, ARRAY[
    'What feels comfortable in your new space?',
    'What made you smile today?',
    'How are you making it yours?',
    'What''s one thing that feels like home?'
]),
('checkin_prompt', 'Explore', NULL, ARRAY[
    'What did you discover today?',
    'What surprised you?',
    'Who did you connect with?',
    'What are you curious about?'
]),
('checkin_prompt', 'Root', NULL, ARRAY[
    'Where are you finding belonging?',
    'Who feels like your people?',
    'What tradition are you starting?',
    'How are you growing roots?'
]),
('checkin_prompt', 'Learn', NULL, ARRAY[
    'What did you learn today?',
    'Who or what supported you?',
    'What questions do you have?',
    'How are you building your knowledge?'
]),
('checkin_prompt', 'Live', NULL, ARRAY[
    'How did you live fully today?',
    'What brought you energy?',
    'What are you moving toward?',
    'How are you thriving?'
]),
('checkin_prompt', 'Rediscover', NULL, ARRAY[
    'What part of yourself did you reconnect with?',
    'What brought you joy independent of the relationship?',
    'What are you learning to love about yourself?',
    'What new interest are you exploring?'
]),
('checkin_prompt', 'Grow', NULL, ARRAY[
    'What growth have you noticed?',
    'How are you different than you were?',
    'What strength have you discovered?',
    'What''s your vision for your future?'
]);

-- ==========================================
-- 6. Seed affirmations
-- ==========================================

INSERT INTO pathway_content_templates (category, phase_name, pathway_key, content) VALUES
('affirmation', 'Acknowledge', 'job_loss', ARRAY['It''s okay to feel uncertain. You are resilient.']),
('affirmation', 'Stabilize', 'job_loss', ARRAY['You are creating a foundation for your next chapter.']),
('affirmation', 'Reflect', 'job_loss', ARRAY['Your worth is not defined by your job title.']),
('affirmation', 'Rebuild', 'job_loss', ARRAY['Every small step is progress. You are moving forward.']),

('affirmation', 'Acknowledge', 'breakup', ARRAY['Your feelings are valid. Healing takes time.']),
('affirmation', 'Grieve', 'breakup', ARRAY['It''s okay to miss what was while embracing what will be.']),
('affirmation', 'Rediscover', 'breakup', ARRAY['You are whole on your own. You are enough.']),
('affirmation', 'Grow', 'breakup', ARRAY['You are stronger and wiser from this experience.']),

('affirmation', 'Shock', 'grief', ARRAY['Take it one moment at a time. You don''t have to be okay.']),
('affirmation', 'Feel', 'grief', ARRAY['All your emotions are welcome here. There is no wrong way to grieve.']),
('affirmation', 'Remember', 'grief', ARRAY['Love never dies. They live on in your heart.']),
('affirmation', 'Adapt', 'grief', ARRAY['Healing doesn''t mean forgetting. You carry them with you.']),

('affirmation', 'Adjust', 'new_parent', ARRAY['You are exactly the parent your baby needs.']),
('affirmation', 'Bond', 'new_parent', ARRAY['Every moment of connection matters, even the small ones.']),
('affirmation', 'Balance', 'new_parent', ARRAY['Rest is productive. You are enough.']),
('affirmation', 'Thrive', 'new_parent', ARRAY['You are learning and growing alongside your child.']),

('affirmation', 'Farewell', 'relocation', ARRAY['Endings make space for beautiful new beginnings.']),
('affirmation', 'Settle', 'relocation', ARRAY['Home is what you create, not just where you are.']),
('affirmation', 'Explore', 'relocation', ARRAY['Every new place holds possibility and adventure.']),
('affirmation', 'Root', 'relocation', ARRAY['You have the power to build community wherever you go.']),

('affirmation', 'Process', 'health_diagnosis', ARRAY['You are more than your diagnosis. You are whole.']),
('affirmation', 'Learn', 'health_diagnosis', ARRAY['Knowledge is power. You are taking control.']),
('affirmation', 'Adapt', 'health_diagnosis', ARRAY['You are adapting with grace and strength.']),
('affirmation', 'Live', 'health_diagnosis', ARRAY['Life is happening now. You are living it fully.']);

-- Default affirmation for any phase/pathway combination not specified
INSERT INTO pathway_content_templates (category, phase_name, pathway_key, content) VALUES
('affirmation', 'default', NULL, ARRAY['You are taking important steps toward healing and growth.']);
