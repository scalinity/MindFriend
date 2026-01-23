-- Migration: Create couples_exercises table with seed data
-- Purpose: Library of 12 couples exercises (8 free + 4 premium)
-- Status: CRITICAL PATH - Foundation

CREATE TABLE IF NOT EXISTS couples_exercises (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(128) NOT NULL,
    description TEXT NOT NULL,
    type VARCHAR(32) NOT NULL CHECK (type IN ('communication', 'intimacy', 'goal-setting', 'mindfulness')),
    difficulty VARCHAR(16) NOT NULL DEFAULT 'beginner' CHECK (difficulty IN ('beginner', 'intermediate', 'advanced')),
    duration_minutes SMALLINT NOT NULL CHECK (duration_minutes > 0 AND duration_minutes <= 120),
    instructions JSONB NOT NULL,
    requires_premium BOOLEAN NOT NULL DEFAULT false,
    requires_both_partners BOOLEAN NOT NULL DEFAULT true,
    can_do_solo BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_couples_exercises_type ON couples_exercises(type);
CREATE INDEX IF NOT EXISTS idx_couples_exercises_difficulty ON couples_exercises(difficulty);
CREATE INDEX IF NOT EXISTS idx_couples_exercises_requires_premium ON couples_exercises(requires_premium);

-- Enable RLS
ALTER TABLE couples_exercises ENABLE ROW LEVEL SECURITY;

CREATE POLICY "All authenticated users can view exercises"
    ON couples_exercises FOR SELECT
    USING (auth.role() = 'authenticated');

-- Seed data: 12 exercises
-- Communication: 3 free + 1 premium = 4
-- Intimacy: 2 free + 1 premium = 3
-- Goal-Setting: 2 free + 1 premium = 3
-- Mindfulness: 1 free + 1 premium = 2
INSERT INTO couples_exercises (name, description, type, difficulty, duration_minutes, instructions, requires_premium, requires_both_partners, can_do_solo)
VALUES
-- Communication (3 free)
('Active Listening', 'Learn to listen without judgment and reflect back what you hear.', 'communication', 'beginner', 20, '{"steps": [{"order": 1, "title": "Setup", "description": "Sit facing each other", "durationSeconds": 60}, {"order": 2, "title": "Partner A talks", "description": "Share a thought or feeling for 3 minutes", "durationSeconds": 180, "roleSpecific": {"partner_1": "Speak openly", "partner_2": "Listen without interrupting"}}, {"order": 3, "title": "Partner B reflects", "description": "Reflect back what you heard", "durationSeconds": 180}], "tips": "Focus on understanding, not fixing"}', false, true, false),
('Appreciation Exchange', 'Share specific appreciations about each other.', 'communication', 'beginner', 15, '{"steps": [{"order": 1, "title": "Prepare", "description": "Think of 3 things you appreciate about your partner", "durationSeconds": 180}, {"order": 2, "title": "Share", "description": "Take turns sharing appreciations", "durationSeconds": 540}], "tips": "Be specific and genuine"}', false, true, false),
('Gratitude Ritual', 'Daily gratitude sharing practice.', 'communication', 'beginner', 10, '{"steps": [{"order": 1, "title": "Gather", "description": "Sit close together", "durationSeconds": 60}, {"order": 2, "title": "Share", "description": "Each share one thing you are grateful for", "durationSeconds": 480}], "tips": "Do this at dinner time"}', false, true, false),

-- Intimacy (2 free)
('Vulnerability Practice', 'Build emotional intimacy through vulnerability.', 'intimacy', 'intermediate', 25, '{"steps": [{"order": 1, "title": "Get comfortable", "description": "Sit close, maybe hold hands", "durationSeconds": 60}, {"order": 2, "title": "Share vulnerably", "description": "Share something you usually hide about yourself", "durationSeconds": 1440}], "tips": "Take turns being the sharer and listener"}', false, true, false),
('Eye Gazing', 'Deep connection through gentle eye contact.', 'intimacy', 'intermediate', 10, '{"steps": [{"order": 1, "title": "Setup", "description": "Sit facing each other in dim light", "durationSeconds": 30}, {"order": 2, "title": "Gaze", "description": "Maintain soft eye contact", "durationSeconds": 570}], "tips": "Let emotions surface naturally"}', false, true, false),

-- Goal-Setting (2 free)
('Values Alignment', 'Discuss and align on shared values.', 'goal-setting', 'intermediate', 30, '{"steps": [{"order": 1, "title": "Reflect individually", "description": "Write down your top 5 values", "durationSeconds": 600}, {"order": 2, "title": "Share and discuss", "description": "Compare and find common ground", "durationSeconds": 1200}], "tips": "Be curious about differences"}', false, true, false),
('Future Planning', 'Vision your future together.', 'goal-setting', 'intermediate', 30, '{"steps": [{"order": 1, "title": "Imagine", "description": "Think about your ideal future together (1-5 years)", "durationSeconds": 600}, {"order": 2, "title": "Share vision", "description": "Describe your vision to each other", "durationSeconds": 1200}], "tips": "Dream big and specific"}', false, true, false),

-- Mindfulness (1 free)
('Couples Meditation', 'Mindfulness meditation done together.', 'mindfulness', 'beginner', 15, '{"steps": [{"order": 1, "title": "Settle", "description": "Sit comfortably", "durationSeconds": 60}, {"order": 2, "title": "Meditate", "description": "Follow guided breathing together", "durationSeconds": 840}], "tips": "Start with 5 minutes if new to meditation"}', false, true, false),

-- Premium exercises (4 premium)
-- Communication Premium
('Conflict Resolution Mastery', 'Advanced techniques for resolving disagreements constructively.', 'communication', 'advanced', 45, '{"steps": [{"order": 1, "title": "Identify issue", "description": "Agree on what to discuss", "durationSeconds": 300}, {"order": 2, "title": "Listen and validate", "description": "Each person fully shares perspective", "durationSeconds": 1200}, {"order": 3, "title": "Collaborate on solution", "description": "Work together on resolution", "durationSeconds": 1200}], "tips": "Remember the goal is connection, not winning"}', true, true, false),

-- Intimacy Premium
('Gratitude Ritual Couples', 'Advanced appreciation with depth and presence.', 'intimacy', 'intermediate', 20, '{"steps": [{"order": 1, "title": "Create sacred space", "description": "Set mood with candles or music", "durationSeconds": 180}, {"order": 2, "title": "Exchange gifts of appreciation", "description": "Give small gifts or write love notes", "durationSeconds": 1020}], "tips": "This can be done weekly"}', true, true, false),

-- Goal-Setting Premium
('Relationship Goals Workshop', 'Deep planning for relationship milestones.', 'goal-setting', 'advanced', 45, '{"steps": [{"order": 1, "title": "Review past", "description": "Celebrate what you have accomplished", "durationSeconds": 600}, {"order": 2, "title": "Plan future", "description": "Set specific relationship goals", "durationSeconds": 1800}], "tips": "Revisit quarterly"}', true, true, false),

-- Mindfulness Premium
('Heart-to-Heart Meditation', 'Connect at the heart center.', 'mindfulness', 'intermediate', 20, '{"steps": [{"order": 1, "title": "Position hands", "description": "Place hands on each other hearts", "durationSeconds": 60}, {"order": 2, "title": "Feel connection", "description": "Feel heartbeats synchronizing", "durationSeconds": 1140}], "tips": "A deeply intimate practice"}', true, true, false);
