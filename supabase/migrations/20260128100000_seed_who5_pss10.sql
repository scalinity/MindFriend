-- Seed Assessment Templates: WHO-5 and PSS-10
-- WHO-5: WHO Well-Being Index (positive measure - higher is better)
-- PSS-10: Perceived Stress Scale (negative measure - higher is worse)

-- WHO-5: WHO Well-Being Index
-- 5 questions, 0-5 scoring each (0-25 total), higher = better well-being
-- Interpretation: Raw score × 4 = percentage (0-100%), <50% suggests screening for depression
INSERT INTO assessment_templates (code, name, description, questions, scoring_ranges, recommended_frequency_days, is_active)
VALUES (
    'WHO5',
    'WHO Well-Being Index',
    'A short self-reported measure of current mental well-being. It covers positive mood, vitality, and general interest. Higher scores indicate better well-being.',
    '[
        {"id": "1", "number": 1, "text": "I have felt cheerful and in good spirits", "response_options": ["At no time", "Some of the time", "Less than half the time", "More than half the time", "Most of the time", "All of the time"], "is_crisis_indicator": false},
        {"id": "2", "number": 2, "text": "I have felt calm and relaxed", "response_options": ["At no time", "Some of the time", "Less than half the time", "More than half the time", "Most of the time", "All of the time"], "is_crisis_indicator": false},
        {"id": "3", "number": 3, "text": "I have felt active and vigorous", "response_options": ["At no time", "Some of the time", "Less than half the time", "More than half the time", "Most of the time", "All of the time"], "is_crisis_indicator": false},
        {"id": "4", "number": 4, "text": "I woke up feeling fresh and rested", "response_options": ["At no time", "Some of the time", "Less than half the time", "More than half the time", "Most of the time", "All of the time"], "is_crisis_indicator": false},
        {"id": "5", "number": 5, "text": "My daily life has been filled with things that interest me", "response_options": ["At no time", "Some of the time", "Less than half the time", "More than half the time", "Most of the time", "All of the time"], "is_crisis_indicator": false}
    ]'::jsonb,
    '[
        {"min": 0, "max": 6, "level": "low", "label": "Low Well-Being", "recommendations": ["Consider speaking with a healthcare provider", "Screen for depression with PHQ-9", "Focus on self-care activities"]},
        {"min": 7, "max": 12, "level": "moderate_low", "label": "Moderately Low Well-Being", "recommendations": ["Explore stress management techniques", "Increase pleasurable activities", "Monitor changes weekly"]},
        {"min": 13, "max": 18, "level": "moderate", "label": "Moderate Well-Being", "recommendations": ["Maintain current positive activities", "Continue monitoring well-being", "Build on strengths"]},
        {"min": 19, "max": 22, "level": "good", "label": "Good Well-Being", "recommendations": ["Keep up current practices", "Share strategies with others", "Set new growth goals"]},
        {"min": 23, "max": 25, "level": "excellent", "label": "Excellent Well-Being", "recommendations": ["Maintain your excellent well-being", "Consider mentoring others", "Continue healthy habits"]}
    ]'::jsonb,
    7,
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

-- PSS-10: Perceived Stress Scale
-- 10 questions, 0-4 scoring each (0-40 total), higher = more stress
-- Questions 4, 5, 7, 8 are reverse-scored (positive items)
INSERT INTO assessment_templates (code, name, description, questions, scoring_ranges, recommended_frequency_days, is_active)
VALUES (
    'PSS10',
    'Perceived Stress Scale-10',
    'Measures the degree to which situations in your life are appraised as stressful over the past month. Lower scores indicate lower perceived stress.',
    '[
        {"id": "1", "number": 1, "text": "In the last month, how often have you been upset because of something that happened unexpectedly?", "response_options": ["Never", "Almost never", "Sometimes", "Fairly often", "Very often"], "is_crisis_indicator": false},
        {"id": "2", "number": 2, "text": "In the last month, how often have you felt that you were unable to control the important things in your life?", "response_options": ["Never", "Almost never", "Sometimes", "Fairly often", "Very often"], "is_crisis_indicator": false},
        {"id": "3", "number": 3, "text": "In the last month, how often have you felt nervous and stressed?", "response_options": ["Never", "Almost never", "Sometimes", "Fairly often", "Very often"], "is_crisis_indicator": false},
        {"id": "4", "number": 4, "text": "In the last month, how often have you felt confident about your ability to handle your personal problems?", "response_options": ["Never", "Almost never", "Sometimes", "Fairly often", "Very often"], "is_crisis_indicator": false},
        {"id": "5", "number": 5, "text": "In the last month, how often have you felt that things were going your way?", "response_options": ["Never", "Almost never", "Sometimes", "Fairly often", "Very often"], "is_crisis_indicator": false},
        {"id": "6", "number": 6, "text": "In the last month, how often have you found that you could not cope with all the things that you had to do?", "response_options": ["Never", "Almost never", "Sometimes", "Fairly often", "Very often"], "is_crisis_indicator": false},
        {"id": "7", "number": 7, "text": "In the last month, how often have you been able to control irritations in your life?", "response_options": ["Never", "Almost never", "Sometimes", "Fairly often", "Very often"], "is_crisis_indicator": false},
        {"id": "8", "number": 8, "text": "In the last month, how often have you felt that you were on top of things?", "response_options": ["Never", "Almost never", "Sometimes", "Fairly often", "Very often"], "is_crisis_indicator": false},
        {"id": "9", "number": 9, "text": "In the last month, how often have you been angered because of things that happened that were outside of your control?", "response_options": ["Never", "Almost never", "Sometimes", "Fairly often", "Very often"], "is_crisis_indicator": false},
        {"id": "10", "number": 10, "text": "In the last month, how often have you felt difficulties were piling up so high that you could not overcome them?", "response_options": ["Never", "Almost never", "Sometimes", "Fairly often", "Very often"], "is_crisis_indicator": false}
    ]'::jsonb,
    '[
        {"min": 0, "max": 13, "level": "low", "label": "Low Perceived Stress", "recommendations": ["Maintain current coping strategies", "Continue healthy routines", "Practice preventive self-care"]},
        {"min": 14, "max": 26, "level": "moderate", "label": "Moderate Perceived Stress", "recommendations": ["Explore stress reduction techniques", "Consider time management strategies", "Practice regular relaxation exercises"]},
        {"min": 27, "max": 40, "level": "high", "label": "High Perceived Stress", "recommendations": ["Prioritize stress management", "Consider speaking with a professional", "Identify and address major stressors", "Practice daily stress-relief activities"]}
    ]'::jsonb,
    7,
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
    RAISE NOTICE 'Assessment templates seeded: WHO-5, PSS-10';
END $$;
