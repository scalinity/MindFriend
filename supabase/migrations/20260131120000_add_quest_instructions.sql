-- Migration: Add instructions column to quest_templates and populate for original 22 templates
-- Instructions format: [{"step": 1, "text": "...", "duration_seconds": 30}, ...]

-- Step 1: Add instructions column if it doesn't exist
ALTER TABLE quest_templates ADD COLUMN IF NOT EXISTS instructions JSONB DEFAULT '[]'::jsonb;

-- =============================================================================
-- MINDFULNESS TEMPLATES (Original 5: a0000001-...-001 to 005)
-- =============================================================================

-- Morning Meditation
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find a quiet, comfortable place to sit", "duration_seconds": 30},
  {"step": 2, "text": "Close your eyes and take 3 deep breaths", "duration_seconds": 30},
  {"step": 3, "text": "Focus on the sensation of breathing in and out", "duration_seconds": 120},
  {"step": 4, "text": "When thoughts arise, gently return focus to your breath", "duration_seconds": 90},
  {"step": 5, "text": "Slowly open your eyes and set an intention for the day", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000001';

-- Deep Breathing Exercise
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Sit or stand in a comfortable position", "duration_seconds": 20},
  {"step": 2, "text": "Inhale slowly through your nose for 4 counts", "duration_seconds": 30},
  {"step": 3, "text": "Hold your breath for 4 counts", "duration_seconds": 30},
  {"step": 4, "text": "Exhale slowly through your mouth for 4 counts", "duration_seconds": 30},
  {"step": 5, "text": "Hold empty for 4 counts", "duration_seconds": 30},
  {"step": 6, "text": "Repeat the box breathing pattern 4 more times", "duration_seconds": 160}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000002';

-- Body Scan Relaxation
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Lie down or sit comfortably and close your eyes", "duration_seconds": 30},
  {"step": 2, "text": "Focus on the top of your head, noticing any tension", "duration_seconds": 60},
  {"step": 3, "text": "Move attention to your face, jaw, and neck - let them soften", "duration_seconds": 60},
  {"step": 4, "text": "Scan your shoulders, arms, and hands - release any tightness", "duration_seconds": 90},
  {"step": 5, "text": "Notice your chest, abdomen, and back - breathe into any tension", "duration_seconds": 90},
  {"step": 6, "text": "Bring awareness to your hips, legs, and feet", "duration_seconds": 90},
  {"step": 7, "text": "Feel your whole body as one relaxed unit", "duration_seconds": 60},
  {"step": 8, "text": "Take 3 deep breaths and slowly open your eyes", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000003';

-- Mindful Walking
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Stand still and take 3 deep breaths", "duration_seconds": 30},
  {"step": 2, "text": "Begin walking slowly, feeling each foot touch the ground", "duration_seconds": 180},
  {"step": 3, "text": "Notice the sensation of lifting, moving, and placing each foot", "duration_seconds": 180},
  {"step": 4, "text": "If your mind wanders, gently return focus to your steps", "duration_seconds": 180},
  {"step": 5, "text": "Gradually slow down and stand still again", "duration_seconds": 60},
  {"step": 6, "text": "Take 3 deep breaths and notice how you feel", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000004';

-- Evening Wind Down
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find a comfortable position in a dimly lit space", "duration_seconds": 30},
  {"step": 2, "text": "Close your eyes and take 5 slow, deep breaths", "duration_seconds": 45},
  {"step": 3, "text": "Reflect on 3 good things that happened today", "duration_seconds": 120},
  {"step": 4, "text": "Release any worries by imagining them floating away", "duration_seconds": 120},
  {"step": 5, "text": "Visualize a peaceful, calming scene", "duration_seconds": 120},
  {"step": 6, "text": "Let your breathing become natural and slow", "duration_seconds": 90},
  {"step": 7, "text": "When ready, gently open your eyes", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000005';

-- =============================================================================
-- GRATITUDE TEMPLATES (Original 3: a0000002-...-001 to 003)
-- =============================================================================

-- Gratitude Journal
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find a quiet space with pen and paper or a notes app", "duration_seconds": 30},
  {"step": 2, "text": "Take 3 deep breaths to center yourself", "duration_seconds": 30},
  {"step": 3, "text": "Write down the first thing you are grateful for today", "duration_seconds": 60},
  {"step": 4, "text": "Write down a second thing - it can be big or small", "duration_seconds": 60},
  {"step": 5, "text": "Write down a third thing you appreciate", "duration_seconds": 60},
  {"step": 6, "text": "Read over your list and feel the gratitude", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000001';

-- Thank Someone
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of someone who helped you recently", "duration_seconds": 60},
  {"step": 2, "text": "Reflect on what they did and how it affected you", "duration_seconds": 120},
  {"step": 3, "text": "Compose a heartfelt thank you message", "duration_seconds": 240},
  {"step": 4, "text": "Send the message via text, email, or voice note", "duration_seconds": 60},
  {"step": 5, "text": "Notice how expressing gratitude makes you feel", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000002';

-- Appreciation Moment
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Look around your current environment", "duration_seconds": 30},
  {"step": 2, "text": "Choose one thing to focus your appreciation on", "duration_seconds": 30},
  {"step": 3, "text": "Study it closely - notice colors, textures, details", "duration_seconds": 90},
  {"step": 4, "text": "Think about how this thing enriches your life", "duration_seconds": 90},
  {"step": 5, "text": "Say silently or aloud: I appreciate you", "duration_seconds": 30},
  {"step": 6, "text": "Carry this feeling of appreciation with you", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000003';

-- =============================================================================
-- SOCIAL TEMPLATES (Original 3: a0000003-...-001 to 003)
-- =============================================================================

-- Connect with a Friend
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of a friend you have not talked to recently", "duration_seconds": 60},
  {"step": 2, "text": "Recall a positive memory you share with them", "duration_seconds": 60},
  {"step": 3, "text": "Reach out via call, text, or social media", "duration_seconds": 120},
  {"step": 4, "text": "Ask how they are doing and share something about yourself", "duration_seconds": 480},
  {"step": 5, "text": "Make a plan to connect again soon", "duration_seconds": 120}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000001';

-- Compliment Someone
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of someone you will see or interact with today", "duration_seconds": 60},
  {"step": 2, "text": "Notice something genuine you appreciate about them", "duration_seconds": 60},
  {"step": 3, "text": "Give them a specific, sincere compliment", "duration_seconds": 60},
  {"step": 4, "text": "Observe their reaction and how it makes you feel", "duration_seconds": 60},
  {"step": 5, "text": "Reflect on the power of kind words", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000002';

-- Active Listening
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find someone to have a conversation with", "duration_seconds": 120},
  {"step": 2, "text": "Put away distractions and give full attention", "duration_seconds": 30},
  {"step": 3, "text": "Ask an open-ended question about their day or feelings", "duration_seconds": 60},
  {"step": 4, "text": "Listen without planning your response", "duration_seconds": 300},
  {"step": 5, "text": "Reflect back what you heard to show understanding", "duration_seconds": 120},
  {"step": 6, "text": "Ask a follow-up question based on what they shared", "duration_seconds": 300},
  {"step": 7, "text": "Thank them for sharing with you", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000003';

-- =============================================================================
-- PHYSICAL TEMPLATES (Original 3: a0000004-...-001 to 003)
-- =============================================================================

-- Morning Stretch
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Stand tall with feet hip-width apart", "duration_seconds": 20},
  {"step": 2, "text": "Reach both arms overhead and stretch upward", "duration_seconds": 30},
  {"step": 3, "text": "Gently bend to each side, holding 15 seconds each", "duration_seconds": 40},
  {"step": 4, "text": "Roll your shoulders forward and backward 5 times each", "duration_seconds": 40},
  {"step": 5, "text": "Gently turn your head side to side", "duration_seconds": 30},
  {"step": 6, "text": "Bend forward at the waist, reaching toward your toes", "duration_seconds": 45},
  {"step": 7, "text": "Slowly roll back up to standing and take a deep breath", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000001';

-- Take a Walk
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Put on comfortable shoes and step outside", "duration_seconds": 60},
  {"step": 2, "text": "Begin walking at a comfortable pace", "duration_seconds": 180},
  {"step": 3, "text": "Notice 5 things you can see around you", "duration_seconds": 120},
  {"step": 4, "text": "Feel the air on your skin and the ground beneath your feet", "duration_seconds": 180},
  {"step": 5, "text": "Increase your pace slightly for 2 minutes", "duration_seconds": 120},
  {"step": 6, "text": "Slow back down and enjoy the final stretch home", "duration_seconds": 180},
  {"step": 7, "text": "Take 3 deep breaths before going back inside", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000002';

-- Dance Break
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Choose a song that makes you want to move", "duration_seconds": 30},
  {"step": 2, "text": "Find a space where you can move freely", "duration_seconds": 20},
  {"step": 3, "text": "Start by moving just your head and shoulders", "duration_seconds": 30},
  {"step": 4, "text": "Let the movement spread to your arms and hips", "duration_seconds": 60},
  {"step": 5, "text": "Dance freely without judgment - no one is watching!", "duration_seconds": 120},
  {"step": 6, "text": "Let the music guide your body", "duration_seconds": 60},
  {"step": 7, "text": "As the song ends, slow down and take a bow", "duration_seconds": 20}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000003';

-- =============================================================================
-- CREATIVE TEMPLATES (Original 3: a0000005-...-001 to 003)
-- =============================================================================

-- Doodle Time
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Grab paper and a pen, pencil, or marker", "duration_seconds": 30},
  {"step": 2, "text": "Start by making simple shapes or lines", "duration_seconds": 60},
  {"step": 3, "text": "Let your hand move without planning what to draw", "duration_seconds": 180},
  {"step": 4, "text": "Add details, patterns, or shading as inspiration strikes", "duration_seconds": 180},
  {"step": 5, "text": "There is no wrong way - embrace imperfection", "duration_seconds": 120},
  {"step": 6, "text": "Sign and date your creation", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000001';

-- Write a Poem
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find a quiet place with paper or a notes app", "duration_seconds": 30},
  {"step": 2, "text": "Close your eyes and notice how you feel right now", "duration_seconds": 60},
  {"step": 3, "text": "Write down the first word or image that comes to mind", "duration_seconds": 30},
  {"step": 4, "text": "Build on that word - what sounds, smells, or feelings connect?", "duration_seconds": 180},
  {"step": 5, "text": "Write 4-8 lines without worrying about rhyme or structure", "duration_seconds": 300},
  {"step": 6, "text": "Read your poem aloud to yourself", "duration_seconds": 60},
  {"step": 7, "text": "Give it a title and save it", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000002';

-- Music Moment
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Choose a piece of music you love or want to explore", "duration_seconds": 30},
  {"step": 2, "text": "Put on headphones if possible for full immersion", "duration_seconds": 20},
  {"step": 3, "text": "Close your eyes and press play", "duration_seconds": 10},
  {"step": 4, "text": "Focus on the different instruments or sounds", "duration_seconds": 180},
  {"step": 5, "text": "Notice how the music makes you feel in your body", "duration_seconds": 180},
  {"step": 6, "text": "When the piece ends, sit in silence for a moment", "duration_seconds": 60},
  {"step": 7, "text": "Reflect on what the music meant to you today", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000003';

-- =============================================================================
-- REFLECTION TEMPLATES (Original 5: a0000006-...-001 to 005)
-- =============================================================================

-- Daily Reflection
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find a quiet moment at the end of your day", "duration_seconds": 30},
  {"step": 2, "text": "Ask yourself: What went well today?", "duration_seconds": 120},
  {"step": 3, "text": "Ask yourself: What challenged me?", "duration_seconds": 120},
  {"step": 4, "text": "Ask yourself: What did I learn?", "duration_seconds": 120},
  {"step": 5, "text": "Write down or mentally note your answers", "duration_seconds": 120},
  {"step": 6, "text": "Set one intention for tomorrow", "duration_seconds": 60},
  {"step": 7, "text": "Take 3 deep breaths to close", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000001';

-- Goal Check-In
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Write down your current top 3 goals", "duration_seconds": 90},
  {"step": 2, "text": "For each goal, rate your progress from 1-10", "duration_seconds": 90},
  {"step": 3, "text": "Identify one obstacle for each goal", "duration_seconds": 120},
  {"step": 4, "text": "Brainstorm one action to overcome each obstacle", "duration_seconds": 120},
  {"step": 5, "text": "Celebrate any progress, no matter how small", "duration_seconds": 60},
  {"step": 6, "text": "Commit to one specific action for this week", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000002';

-- Self-Affirmation
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Stand or sit in a confident posture", "duration_seconds": 20},
  {"step": 2, "text": "Take 3 deep breaths to center yourself", "duration_seconds": 30},
  {"step": 3, "text": "Say aloud: I am capable and worthy", "duration_seconds": 30},
  {"step": 4, "text": "Say aloud: I choose to focus on what I can control", "duration_seconds": 30},
  {"step": 5, "text": "Say aloud: I deserve compassion, especially from myself", "duration_seconds": 30},
  {"step": 6, "text": "Create your own affirmation that feels true", "duration_seconds": 90},
  {"step": 7, "text": "Repeat your personal affirmation 3 times", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000003';

-- Strength Recognition
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think back over your day or week", "duration_seconds": 60},
  {"step": 2, "text": "Identify a moment when you showed resilience", "duration_seconds": 90},
  {"step": 3, "text": "Identify a moment when you showed kindness", "duration_seconds": 90},
  {"step": 4, "text": "Identify a moment when you showed creativity or problem-solving", "duration_seconds": 90},
  {"step": 5, "text": "Write down these three strengths", "duration_seconds": 60},
  {"step": 6, "text": "Acknowledge yourself for using these strengths", "duration_seconds": 60},
  {"step": 7, "text": "Consider how you might use them tomorrow", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000004';

-- Progress Celebration
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of something you accomplished this week", "duration_seconds": 60},
  {"step": 2, "text": "It can be small - even getting through a tough day counts", "duration_seconds": 30},
  {"step": 3, "text": "Say aloud: I did this, and I am proud", "duration_seconds": 30},
  {"step": 4, "text": "Do a small celebration - smile, fist pump, or happy dance", "duration_seconds": 30},
  {"step": 5, "text": "Think about what helped you succeed", "duration_seconds": 90},
  {"step": 6, "text": "Consider sharing your win with someone supportive", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000005';
