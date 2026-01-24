-- Seed capsule templates
-- 6 predefined themes with guided prompts

INSERT INTO capsule_templates (theme, title, prompts, suggested_duration, is_premium, sort_order) VALUES

-- Free templates
('encouragement', 'Letter to Future Me',
 '["What are you proud of right now?", "What challenge are you facing?", "What advice would you give yourself?", "What are you grateful for today?"]'::jsonb,
 '1 year', false, 1),

('goal', 'Goals & Dreams',
 '["What goal are you working toward?", "Why is this goal important to you?", "What steps are you taking?", "How will you feel when you achieve it?"]'::jsonb,
 '6 months', false, 2),

('milestone', 'Celebrate This Moment',
 '["What milestone are you celebrating?", "How did you achieve this?", "Who helped you along the way?", "What''s next for you?"]'::jsonb,
 '1 year', false, 3),

('gratitude', 'Gratitude Capsule',
 '["List 5 things you''re grateful for right now", "Who has positively impacted your life recently?", "What simple pleasure brought you joy today?"]'::jsonb,
 '6 months', false, 4),

-- Premium template
('advice', 'Wisdom for Tomorrow',
 '["What lesson have you learned recently?", "What would you tell someone going through what you''ve been through?", "What truth do you want to remember?"]'::jsonb,
 '1 year', true, 5),

('anniversary', 'Annual Wellness Snapshot',
 '["How would you describe this past year?", "What was your biggest challenge?", "What was your greatest joy?", "What do you hope for next year?"]'::jsonb,
 '1 year', false, 6)

ON CONFLICT DO NOTHING;
