-- Seed Assessment Templates: PHQ-9 and GAD-7
-- These are validated clinical screening instruments

-- Ensure unique constraint exists on code column
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'assessment_templates_code_key'
    ) THEN
        ALTER TABLE assessment_templates ADD CONSTRAINT assessment_templates_code_key UNIQUE (code);
    END IF;
END $$;

-- PHQ-9: Patient Health Questionnaire-9 (Depression Screening)
INSERT INTO assessment_templates (code, name, description, questions, scoring_ranges, recommended_frequency_days, is_active)
VALUES (
    'PHQ9',
    'Patient Health Questionnaire-9',
    'A validated 9-item screening tool and severity measure for depression. Each question asks about symptoms over the past 2 weeks.',
    '[
        {"id": "1", "number": 1, "text": "Little interest or pleasure in doing things", "response_options": ["Not at all", "Several days", "More than half the days", "Nearly every day"], "is_crisis_indicator": false},
        {"id": "2", "number": 2, "text": "Feeling down, depressed, or hopeless", "response_options": ["Not at all", "Several days", "More than half the days", "Nearly every day"], "is_crisis_indicator": false},
        {"id": "3", "number": 3, "text": "Trouble falling or staying asleep, or sleeping too much", "response_options": ["Not at all", "Several days", "More than half the days", "Nearly every day"], "is_crisis_indicator": false},
        {"id": "4", "number": 4, "text": "Feeling tired or having little energy", "response_options": ["Not at all", "Several days", "More than half the days", "Nearly every day"], "is_crisis_indicator": false},
        {"id": "5", "number": 5, "text": "Poor appetite or overeating", "response_options": ["Not at all", "Several days", "More than half the days", "Nearly every day"], "is_crisis_indicator": false},
        {"id": "6", "number": 6, "text": "Feeling bad about yourself - or that you are a failure or have let yourself or your family down", "response_options": ["Not at all", "Several days", "More than half the days", "Nearly every day"], "is_crisis_indicator": false},
        {"id": "7", "number": 7, "text": "Trouble concentrating on things, such as reading the newspaper or watching television", "response_options": ["Not at all", "Several days", "More than half the days", "Nearly every day"], "is_crisis_indicator": false},
        {"id": "8", "number": 8, "text": "Moving or speaking so slowly that other people could have noticed? Or the opposite - being so fidgety or restless that you have been moving around a lot more than usual", "response_options": ["Not at all", "Several days", "More than half the days", "Nearly every day"], "is_crisis_indicator": false},
        {"id": "9", "number": 9, "text": "Thoughts that you would be better off dead, or of hurting yourself in some way", "response_options": ["Not at all", "Several days", "More than half the days", "Nearly every day"], "is_crisis_indicator": true}
    ]'::jsonb,
    '[
        {"min": 0, "max": 4, "level": "minimal", "label": "Minimal Depression", "recommendations": ["Continue monitoring", "Practice self-care"]},
        {"min": 5, "max": 9, "level": "mild", "label": "Mild Depression", "recommendations": ["Consider watchful waiting", "Explore coping strategies", "Repeat PHQ-9 in 2 weeks"]},
        {"min": 10, "max": 14, "level": "moderate", "label": "Moderate Depression", "recommendations": ["Consider counseling or therapy", "Discuss treatment options with a provider"]},
        {"min": 15, "max": 19, "level": "moderately_severe", "label": "Moderately Severe Depression", "recommendations": ["Seek professional support", "Consider therapy and/or medication"]},
        {"min": 20, "max": 27, "level": "severe", "label": "Severe Depression", "recommendations": ["Immediate treatment recommended", "Consult mental health professional", "Consider intensive treatment options"]}
    ]'::jsonb,
    14,
    true
)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    questions = EXCLUDED.questions,
    scoring_ranges = EXCLUDED.scoring_ranges,
    recommended_frequency_days = EXCLUDED.recommended_frequency_days,
    is_active = EXCLUDED.is_active,
    updated_at = now();

-- GAD-7: Generalized Anxiety Disorder-7 (Anxiety Screening)
INSERT INTO assessment_templates (code, name, description, questions, scoring_ranges, recommended_frequency_days, is_active)
VALUES (
    'GAD7',
    'Generalized Anxiety Disorder-7',
    'A validated 7-item screening tool and severity measure for generalized anxiety disorder. Each question asks about symptoms over the past 2 weeks.',
    '[
        {"id": "1", "number": 1, "text": "Feeling nervous, anxious, or on edge", "response_options": ["Not at all", "Several days", "More than half the days", "Nearly every day"], "is_crisis_indicator": false},
        {"id": "2", "number": 2, "text": "Not being able to stop or control worrying", "response_options": ["Not at all", "Several days", "More than half the days", "Nearly every day"], "is_crisis_indicator": false},
        {"id": "3", "number": 3, "text": "Worrying too much about different things", "response_options": ["Not at all", "Several days", "More than half the days", "Nearly every day"], "is_crisis_indicator": false},
        {"id": "4", "number": 4, "text": "Trouble relaxing", "response_options": ["Not at all", "Several days", "More than half the days", "Nearly every day"], "is_crisis_indicator": false},
        {"id": "5", "number": 5, "text": "Being so restless that it is hard to sit still", "response_options": ["Not at all", "Several days", "More than half the days", "Nearly every day"], "is_crisis_indicator": false},
        {"id": "6", "number": 6, "text": "Becoming easily annoyed or irritable", "response_options": ["Not at all", "Several days", "More than half the days", "Nearly every day"], "is_crisis_indicator": false},
        {"id": "7", "number": 7, "text": "Feeling afraid, as if something awful might happen", "response_options": ["Not at all", "Several days", "More than half the days", "Nearly every day"], "is_crisis_indicator": false}
    ]'::jsonb,
    '[
        {"min": 0, "max": 4, "level": "minimal", "label": "Minimal Anxiety", "recommendations": ["Continue monitoring", "Practice relaxation techniques"]},
        {"min": 5, "max": 9, "level": "mild", "label": "Mild Anxiety", "recommendations": ["Consider watchful waiting", "Explore coping strategies", "Repeat GAD-7 in 2 weeks"]},
        {"min": 10, "max": 14, "level": "moderate", "label": "Moderate Anxiety", "recommendations": ["Consider counseling or therapy", "Discuss treatment options with a provider"]},
        {"min": 15, "max": 21, "level": "severe", "label": "Severe Anxiety", "recommendations": ["Seek professional support", "Consider therapy and/or medication", "Consult mental health professional"]}
    ]'::jsonb,
    14,
    true
)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    questions = EXCLUDED.questions,
    scoring_ranges = EXCLUDED.scoring_ranges,
    recommended_frequency_days = EXCLUDED.recommended_frequency_days,
    is_active = EXCLUDED.is_active,
    updated_at = now();

-- Log successful seeding
DO $$
BEGIN
    RAISE NOTICE 'Assessment templates seeded: PHQ-9, GAD-7';
END $$;
