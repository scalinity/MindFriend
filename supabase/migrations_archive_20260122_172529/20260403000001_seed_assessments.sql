-- Seed Assessment Types: PHQ-9 (Patient Health Questionnaire - Depression)
INSERT INTO assessment_templates (code, name, description, questions, scoring_ranges, recommended_frequency_days, is_active)
VALUES (
    'PHQ9',
    'Patient Health Questionnaire-9',
    'A validated 9-item screening tool and severity measure for depression',
    '[
        {"id": 1, "text": "Little interest or pleasure in doing things"},
        {"id": 2, "text": "Feeling down, depressed, or hopeless"},
        {"id": 3, "text": "Trouble falling or staying asleep, or sleeping too much"},
        {"id": 4, "text": "Feeling tired or having little energy"},
        {"id": 5, "text": "Poor appetite or overeating"},
        {"id": 6, "text": "Feeling bad about yourself - or that you are a failure or have let your family down"},
        {"id": 7, "text": "Trouble concentrating on things, such as reading the newspaper or watching television"},
        {"id": 8, "text": "Moving or speaking so slowly that other people could have noticed? Or the opposite - being so fidgety or restless that you have been moving around a lot more than usual"},
        {"id": 9, "text": "Thoughts that you would be better off dead or of hurting yourself in some way"}
    ]'::jsonb,
    '[
        {"min": 0, "max": 4, "level": "minimal", "label": "Minimal Depression"},
        {"min": 5, "max": 9, "level": "mild", "label": "Mild Depression"},
        {"min": 10, "max": 14, "level": "moderate", "label": "Moderate Depression"},
        {"min": 15, "max": 19, "level": "moderately_severe", "label": "Moderately Severe Depression"},
        {"min": 20, "max": 27, "level": "severe", "label": "Severe Depression"}
    ]'::jsonb,
    14,
    true
)
ON CONFLICT (code) DO NOTHING;

-- Seed Assessment Types: GAD-7 (Generalized Anxiety Disorder-7)
INSERT INTO assessment_templates (code, name, description, questions, scoring_ranges, recommended_frequency_days, is_active)
VALUES (
    'GAD7',
    'Generalized Anxiety Disorder-7',
    'A validated 7-item screening tool and severity measure for generalized anxiety disorder',
    '[
        {"id": 1, "text": "Feeling nervous, anxious, or on edge"},
        {"id": 2, "text": "Not being able to stop or control worrying"},
        {"id": 3, "text": "Worrying too much about different things"},
        {"id": 4, "text": "Trouble relaxing"},
        {"id": 5, "text": "Being so restless that it is hard to sit still"},
        {"id": 6, "text": "Becoming easily annoyed or irritable"},
        {"id": 7, "text": "Feeling afraid, as if something awful might happen"}
    ]'::jsonb,
    '[
        {"min": 0, "max": 4, "level": "minimal", "label": "Minimal Anxiety"},
        {"min": 5, "max": 9, "level": "mild", "label": "Mild Anxiety"},
        {"min": 10, "max": 14, "level": "moderate", "label": "Moderate Anxiety"},
        {"min": 15, "max": 21, "level": "severe", "label": "Severe Anxiety"}
    ]'::jsonb,
    14,
    true
)
ON CONFLICT (code) DO NOTHING;
