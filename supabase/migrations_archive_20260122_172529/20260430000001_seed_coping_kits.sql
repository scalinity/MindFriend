-- Seed Data: Initial Coping Kits
-- 6 kits: 4 free, 2 premium

-- 1. Grounding 5-4-3-2-1 (anxiety) - FREE
INSERT INTO coping_kits (title, description, context_tag, steps, estimated_minutes, display_order) VALUES (
    '5-4-3-2-1 Grounding',
    'A sensory grounding technique to help you feel present and reduce anxiety.',
    'anxiety',
    '[
        {"type": "grounding", "prompt": "5 things you can SEE around you right now", "duration_seconds": 60},
        {"type": "grounding", "prompt": "4 things you can TOUCH or feel physically", "duration_seconds": 60},
        {"type": "grounding", "prompt": "3 things you can HEAR in your environment", "duration_seconds": 60},
        {"type": "grounding", "prompt": "2 things you can SMELL", "duration_seconds": 60},
        {"type": "grounding", "prompt": "1 thing you can TASTE", "duration_seconds": 60},
        {"type": "chat_checkin", "prompt": "How do you feel now compared to before we started?", "duration_seconds": 60}
    ]'::jsonb,
    8,
    1
);

-- 2. Box Breathing (stress) - FREE
INSERT INTO coping_kits (title, description, context_tag, steps, estimated_minutes, display_order) VALUES (
    'Box Breathing',
    'A simple breathing technique to calm your nervous system and reduce stress.',
    'stress',
    '[
        {"type": "breathing", "breathing_pattern": "box", "duration_cycles": 4, "instructions": "Inhale for 4 seconds, hold for 4 seconds, exhale for 4 seconds, hold for 4 seconds. Repeat for 4 cycles."},
        {"type": "chat_checkin", "prompt": "Notice any changes in your body or mind after this breathing exercise.", "duration_seconds": 60}
    ]'::jsonb,
    5,
    2
);

-- 3. Sadness Compassion Break (sadness) - FREE
INSERT INTO coping_kits (title, description, context_tag, steps, estimated_minutes, display_order) VALUES (
    'Compassion Break',
    'A gentle sequence to acknowledge and work through difficult emotions.',
    'sadness',
    '[
        {"type": "exercise", "exercise_type": "grounding", "prompt": "Place a hand on your heart and take 3 deep breaths, feeling the warmth of your hand.", "duration_seconds": 60},
        {"type": "grounding", "prompt": "Name 3 sensations you notice in your body right now, without judgment", "duration_seconds": 60},
        {"type": "chat_checkin", "prompt": "What emotion are you feeling? Try to name it without trying to change it.", "duration_seconds": 90}
    ]'::jsonb,
    7,
    3
);

-- 4. Sleep Wind-Down (sleep) - PREMIUM
INSERT INTO coping_kits (title, description, context_tag, steps, estimated_minutes, is_premium, display_order) VALUES (
    'Sleep Wind-Down',
    'A relaxing sequence to prepare your body and mind for rest.',
    'sleep',
    '[
        {"type": "breathing", "breathing_pattern": "4-7-8", "duration_cycles": 3, "instructions": "Inhale for 4 seconds, hold for 7 seconds, exhale for 8 seconds. Repeat 3 times for deep relaxation."},
        {"type": "grounding", "prompt": "Starting at your toes, notice and relax each muscle group as you scan up your body", "duration_seconds": 120},
        {"type": "chat_checkin", "prompt": "What is one thing you are grateful for from today?", "duration_seconds": 60}
    ]'::jsonb,
    10,
    true,
    4
);

-- 5. Focus Reset (focus) - FREE
INSERT INTO coping_kits (title, description, context_tag, steps, estimated_minutes, display_order) VALUES (
    'Focus Reset',
    'A quick mental reset to regain clarity and concentration.',
    'focus',
    '[
        {"type": "breathing", "breathing_pattern": "box", "duration_cycles": 2, "instructions": "Box breathing to center yourself and clear your mind", "duration_seconds": 120},
        {"type": "grounding", "prompt": "Name 3 things you need to accomplish today, then choose just one to focus on now", "duration_seconds": 60},
        {"type": "chat_checkin", "prompt": "What is the most important thing on your mind right now?", "duration_seconds": 60}
    ]'::jsonb,
    6,
    5
);

-- 6. Crisis SOS (crisis) - PREMIUM
INSERT INTO coping_kits (title, description, context_tag, steps, estimated_minutes, is_premium, display_order) VALUES (
    'Crisis SOS',
    'Immediate techniques to help you through a difficult moment.',
    'crisis',
    '[
        {"type": "breathing", "breathing_pattern": "4-7-8", "duration_cycles": 2, "instructions": "Calm your nervous system with slow, deep breaths", "duration_seconds": 60},
        {"type": "grounding", "prompt": "5-4-3-2-1: Name 5 things you see, 4 you can feel, 3 you hear, 2 you can smell, 1 you can taste", "duration_seconds": 120},
        {"type": "exercise", "exercise_type": "grounding", "prompt": "Hold something cold, or splash cold water on your face. The cold helps activate your parasympathetic nervous system.", "duration_seconds": 60},
        {"type": "chat_checkin", "prompt": "You are not alone. Would you like to chat with MindFriend about what you are experiencing?", "duration_seconds": 60}
    ]'::jsonb,
    8,
    true,
    6
);
