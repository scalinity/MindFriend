-- Migration: Wave 1 instructions - Mindfulness & Gratitude (25 templates)

-- =============================================================================
-- MINDFULNESS (Wave 1: 006-011 = 12 templates)
-- =============================================================================

-- Breath Counting (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Sit comfortably and close your eyes", "duration_seconds": 20},
  {"step": 2, "text": "Take a deep breath in, then exhale - count 1", "duration_seconds": 20},
  {"step": 3, "text": "Continue breathing and counting up to 10", "duration_seconds": 120},
  {"step": 4, "text": "When you lose count, gently return to 1", "duration_seconds": 60},
  {"step": 5, "text": "Continue the practice without judgment", "duration_seconds": 60},
  {"step": 6, "text": "Take a final deep breath and open your eyes", "duration_seconds": 20}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000006';

-- Sensory Check-In (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Pause and take a deep breath", "duration_seconds": 15},
  {"step": 2, "text": "Notice 5 things you can see around you", "duration_seconds": 60},
  {"step": 3, "text": "Listen for 4 sounds in your environment", "duration_seconds": 50},
  {"step": 4, "text": "Feel 3 textures you can touch right now", "duration_seconds": 45},
  {"step": 5, "text": "Notice 2 things you can smell", "duration_seconds": 40},
  {"step": 6, "text": "Become aware of 1 taste in your mouth", "duration_seconds": 30},
  {"step": 7, "text": "Take a deep breath and feel grounded", "duration_seconds": 20}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000007';

-- Mindful Sip (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Prepare a cup of tea, coffee, or water", "duration_seconds": 60},
  {"step": 2, "text": "Hold the cup and feel its warmth or coolness", "duration_seconds": 30},
  {"step": 3, "text": "Notice the color and any steam rising", "duration_seconds": 30},
  {"step": 4, "text": "Take a small sip and hold it in your mouth", "duration_seconds": 30},
  {"step": 5, "text": "Notice the temperature, taste, and texture", "duration_seconds": 60},
  {"step": 6, "text": "Swallow slowly and feel it travel down", "duration_seconds": 30},
  {"step": 7, "text": "Continue sipping mindfully until finished", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000008';

-- One-Minute Reset (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Stop what you are doing and sit or stand still", "duration_seconds": 15},
  {"step": 2, "text": "Close your eyes if comfortable", "duration_seconds": 10},
  {"step": 3, "text": "Take 4 slow breaths, releasing tension on each exhale", "duration_seconds": 60},
  {"step": 4, "text": "Take 4 more breaths, letting your shoulders drop", "duration_seconds": 60},
  {"step": 5, "text": "Take 4 final breaths, feeling calm wash over you", "duration_seconds": 60},
  {"step": 6, "text": "Open your eyes slowly and feel refreshed", "duration_seconds": 15}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000009';

-- Loving Kindness (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Sit comfortably and close your eyes", "duration_seconds": 30},
  {"step": 2, "text": "Place a hand on your heart and breathe deeply", "duration_seconds": 30},
  {"step": 3, "text": "Say: May I be happy, may I be healthy, may I be at peace", "duration_seconds": 90},
  {"step": 4, "text": "Think of someone you love. Send them the same wishes", "duration_seconds": 90},
  {"step": 5, "text": "Think of a neutral person. Send them loving kindness", "duration_seconds": 90},
  {"step": 6, "text": "Expand to all beings everywhere: May all be happy and free", "duration_seconds": 90},
  {"step": 7, "text": "Return to yourself with a final breath of compassion", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-00000000000a';

-- Sound Awareness (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find a comfortable seat and close your eyes", "duration_seconds": 30},
  {"step": 2, "text": "Take 3 deep breaths to settle in", "duration_seconds": 30},
  {"step": 3, "text": "Open your awareness to all sounds around you", "duration_seconds": 120},
  {"step": 4, "text": "Notice distant sounds - traffic, birds, wind", "duration_seconds": 90},
  {"step": 5, "text": "Notice closer sounds - the room, your breathing", "duration_seconds": 90},
  {"step": 6, "text": "Let sounds come and go without labeling them", "duration_seconds": 120},
  {"step": 7, "text": "Take a final breath and gently open your eyes", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-00000000000b';

-- Present Moment Anchor (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Set a timer for 10 minutes", "duration_seconds": 15},
  {"step": 2, "text": "Sit comfortably and focus on your breath", "duration_seconds": 45},
  {"step": 3, "text": "When a thought arises, notice it without judgment", "duration_seconds": 120},
  {"step": 4, "text": "Gently return focus to the sensation of breathing", "duration_seconds": 120},
  {"step": 5, "text": "Thoughts will come - this is normal. Keep returning", "duration_seconds": 120},
  {"step": 6, "text": "Each return to breath strengthens your practice", "duration_seconds": 120},
  {"step": 7, "text": "When the timer sounds, take 3 deep breaths", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-00000000000c';

-- Mindful Eating (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Choose a small snack - a few raisins or nuts work well", "duration_seconds": 30},
  {"step": 2, "text": "Look at it closely. Notice colors, textures, shapes", "duration_seconds": 60},
  {"step": 3, "text": "Smell it. What do you notice?", "duration_seconds": 45},
  {"step": 4, "text": "Place it in your mouth without chewing", "duration_seconds": 45},
  {"step": 5, "text": "Notice the texture and taste on your tongue", "duration_seconds": 60},
  {"step": 6, "text": "Chew slowly, noticing each sensation", "duration_seconds": 90},
  {"step": 7, "text": "Swallow and feel gratitude for this nourishment", "duration_seconds": 60},
  {"step": 8, "text": "Repeat with another piece if you have more", "duration_seconds": 120}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-00000000000d';

-- Visualization Journey (15 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Lie down or sit comfortably in a quiet space", "duration_seconds": 30},
  {"step": 2, "text": "Close your eyes and take 5 deep breaths", "duration_seconds": 45},
  {"step": 3, "text": "Imagine yourself in a peaceful place - a beach, forest, or meadow", "duration_seconds": 60},
  {"step": 4, "text": "See the colors around you in vivid detail", "duration_seconds": 120},
  {"step": 5, "text": "Hear the sounds of this peaceful place", "duration_seconds": 120},
  {"step": 6, "text": "Feel the temperature, the textures beneath you", "duration_seconds": 120},
  {"step": 7, "text": "Let peace and calm fill your entire body", "duration_seconds": 180},
  {"step": 8, "text": "Slowly bring awareness back to your physical surroundings", "duration_seconds": 60},
  {"step": 9, "text": "Open your eyes, carrying this peace with you", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-00000000000e';

-- Nature Connection (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Go outside or find a window with a nature view", "duration_seconds": 60},
  {"step": 2, "text": "Take 3 deep breaths of fresh air", "duration_seconds": 30},
  {"step": 3, "text": "Look at the sky - notice clouds, colors, light", "duration_seconds": 120},
  {"step": 4, "text": "Observe plants or trees - their movement, colors, shapes", "duration_seconds": 150},
  {"step": 5, "text": "Listen for sounds of nature - birds, wind, water", "duration_seconds": 120},
  {"step": 6, "text": "Feel the air on your skin, the ground beneath you", "duration_seconds": 120},
  {"step": 7, "text": "Smell the air - what scents can you detect?", "duration_seconds": 90},
  {"step": 8, "text": "Feel your connection to the natural world", "duration_seconds": 90}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-00000000000f';

-- Body Gratitude Scan (15 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Lie down comfortably and close your eyes", "duration_seconds": 30},
  {"step": 2, "text": "Take 3 deep breaths to relax", "duration_seconds": 30},
  {"step": 3, "text": "Focus on your feet. Thank them for carrying you", "duration_seconds": 90},
  {"step": 4, "text": "Move to your legs. Appreciate their strength", "duration_seconds": 90},
  {"step": 5, "text": "Thank your core and back for supporting you", "duration_seconds": 90},
  {"step": 6, "text": "Appreciate your arms and hands for all they do", "duration_seconds": 90},
  {"step": 7, "text": "Thank your heart for beating without rest", "duration_seconds": 90},
  {"step": 8, "text": "Appreciate your lungs for every breath", "duration_seconds": 90},
  {"step": 9, "text": "Thank your brain for all its amazing work", "duration_seconds": 90},
  {"step": 10, "text": "Feel gratitude for your whole body", "duration_seconds": 90}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000010';

-- Deep Meditation Session (20 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find a quiet, undisturbed space", "duration_seconds": 30},
  {"step": 2, "text": "Sit in a comfortable, upright position", "duration_seconds": 30},
  {"step": 3, "text": "Set a timer for 20 minutes", "duration_seconds": 20},
  {"step": 4, "text": "Close your eyes and take 5 deep breaths", "duration_seconds": 45},
  {"step": 5, "text": "Let your breath return to its natural rhythm", "duration_seconds": 60},
  {"step": 6, "text": "Focus on the sensation of breathing at your nostrils", "duration_seconds": 300},
  {"step": 7, "text": "When thoughts arise, acknowledge them and return to breath", "duration_seconds": 300},
  {"step": 8, "text": "Rest in awareness, letting thoughts pass like clouds", "duration_seconds": 300},
  {"step": 9, "text": "When the timer sounds, take 3 deep breaths", "duration_seconds": 45},
  {"step": 10, "text": "Slowly open your eyes and sit for a moment", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000011';

-- =============================================================================
-- GRATITUDE (Wave 1: 004-010 = 13 templates)
-- =============================================================================

-- Photo Gratitude (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Open your photos and find one that brings joy", "duration_seconds": 60},
  {"step": 2, "text": "Look at it closely - notice every detail", "duration_seconds": 60},
  {"step": 3, "text": "Remember when and where it was taken", "duration_seconds": 45},
  {"step": 4, "text": "Feel the emotions from that moment", "duration_seconds": 60},
  {"step": 5, "text": "Say aloud why this photo means so much to you", "duration_seconds": 45},
  {"step": 6, "text": "Save or share this feeling of gratitude", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000004';

-- Gratitude Snapshot (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Pause and observe this exact moment", "duration_seconds": 30},
  {"step": 2, "text": "Notice where you are and how you feel", "duration_seconds": 45},
  {"step": 3, "text": "Find one thing to appreciate right now", "duration_seconds": 45},
  {"step": 4, "text": "Write one sentence about why you are grateful", "duration_seconds": 90},
  {"step": 5, "text": "Read it aloud to yourself", "duration_seconds": 30},
  {"step": 6, "text": "Carry this appreciation into your next task", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000005';

-- Small Wins List (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get paper or open a notes app", "duration_seconds": 20},
  {"step": 2, "text": "Think back on today so far", "duration_seconds": 30},
  {"step": 3, "text": "Write down one small thing that went right", "duration_seconds": 60},
  {"step": 4, "text": "Write down a second small win", "duration_seconds": 60},
  {"step": 5, "text": "Write down a third positive thing, however minor", "duration_seconds": 60},
  {"step": 6, "text": "Read your list and smile at each one", "duration_seconds": 30},
  {"step": 7, "text": "Say: I celebrate these small wins!", "duration_seconds": 20}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000006';

-- Appreciation Breath (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Sit comfortably and close your eyes", "duration_seconds": 20},
  {"step": 2, "text": "Inhale and think of something you appreciate", "duration_seconds": 30},
  {"step": 3, "text": "Exhale and release something that troubles you", "duration_seconds": 30},
  {"step": 4, "text": "Inhale appreciation, exhale worry - repeat", "duration_seconds": 120},
  {"step": 5, "text": "Let gratitude fill you with each breath in", "duration_seconds": 60},
  {"step": 6, "text": "Let stress leave you with each breath out", "duration_seconds": 60},
  {"step": 7, "text": "Take 3 final grateful breaths and open your eyes", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000007';

-- Gratitude Letter Draft (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of someone who positively impacted your life", "duration_seconds": 60},
  {"step": 2, "text": "Get paper or open a document", "duration_seconds": 20},
  {"step": 3, "text": "Begin: Dear [Name], I want to thank you for...", "duration_seconds": 60},
  {"step": 4, "text": "Write about what they did for you", "duration_seconds": 150},
  {"step": 5, "text": "Write about how it affected your life", "duration_seconds": 150},
  {"step": 6, "text": "Express what they mean to you", "duration_seconds": 120},
  {"step": 7, "text": "You can finish and send this later, or save it", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000008';

-- Relationship Appreciation (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Choose one important relationship in your life", "duration_seconds": 30},
  {"step": 2, "text": "Visualize this person in your mind", "duration_seconds": 30},
  {"step": 3, "text": "Write: One gift they have given me is...", "duration_seconds": 120},
  {"step": 4, "text": "Write: Another gift from them is...", "duration_seconds": 120},
  {"step": 5, "text": "Write: A third gift is...", "duration_seconds": 120},
  {"step": 6, "text": "Read what you wrote and feel the gratitude", "duration_seconds": 90},
  {"step": 7, "text": "Consider sharing this with them", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000009';

-- Memory Lane (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Close your eyes and take 3 deep breaths", "duration_seconds": 30},
  {"step": 2, "text": "Think of a truly happy memory", "duration_seconds": 60},
  {"step": 3, "text": "See the scene in vivid detail - colors, shapes, people", "duration_seconds": 120},
  {"step": 4, "text": "Hear the sounds from that moment", "duration_seconds": 90},
  {"step": 5, "text": "Feel the emotions you felt then", "duration_seconds": 90},
  {"step": 6, "text": "Let yourself smile as you relive it", "duration_seconds": 90},
  {"step": 7, "text": "Open your eyes and carry that joy with you", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-00000000000a';

-- Challenge Reframe (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of a recent challenge you faced", "duration_seconds": 60},
  {"step": 2, "text": "Write down what made it difficult", "duration_seconds": 90},
  {"step": 3, "text": "Now ask: What strength did this reveal in me?", "duration_seconds": 90},
  {"step": 4, "text": "What lesson or skill did I gain?", "duration_seconds": 90},
  {"step": 5, "text": "What unexpected positive came from it?", "duration_seconds": 90},
  {"step": 6, "text": "Write these three hidden gifts", "duration_seconds": 90},
  {"step": 7, "text": "Thank the challenge for helping you grow", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-00000000000b';

-- Body Appreciation (10 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find a quiet place and take a deep breath", "duration_seconds": 30},
  {"step": 2, "text": "Thank your eyes for letting you see beauty", "duration_seconds": 60},
  {"step": 3, "text": "Thank your ears for music and voices you love", "duration_seconds": 60},
  {"step": 4, "text": "Thank your hands for all they create and hold", "duration_seconds": 60},
  {"step": 5, "text": "Thank your heart for beating faithfully", "duration_seconds": 60},
  {"step": 6, "text": "Thank your legs for carrying you through life", "duration_seconds": 60},
  {"step": 7, "text": "Write a short thank you note to your whole body", "duration_seconds": 180}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-00000000000c';

-- Gratitude Meditation (15 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Sit comfortably and close your eyes", "duration_seconds": 30},
  {"step": 2, "text": "Take 5 slow, deep breaths", "duration_seconds": 45},
  {"step": 3, "text": "Bring to mind someone you are grateful for", "duration_seconds": 120},
  {"step": 4, "text": "Feel appreciation filling your heart", "duration_seconds": 120},
  {"step": 5, "text": "Think of an experience you are grateful for", "duration_seconds": 120},
  {"step": 6, "text": "Let that memory warm you from within", "duration_seconds": 120},
  {"step": 7, "text": "Think of something simple you appreciate today", "duration_seconds": 120},
  {"step": 8, "text": "Rest in a state of pure gratitude", "duration_seconds": 120},
  {"step": 9, "text": "Open your eyes and carry this feeling forward", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-00000000000d';

-- Abundance Inventory (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get paper and create columns: Skills, People, Resources", "duration_seconds": 60},
  {"step": 2, "text": "List 5 skills you have (any level counts)", "duration_seconds": 150},
  {"step": 3, "text": "List 5 people who support you", "duration_seconds": 150},
  {"step": 4, "text": "List 5 resources you can access (tools, places, opportunities)", "duration_seconds": 150},
  {"step": 5, "text": "Look at your lists - you have more than you thought", "duration_seconds": 90},
  {"step": 6, "text": "Circle one item from each column to use this week", "duration_seconds": 60},
  {"step": 7, "text": "Feel gratitude for your abundance", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-00000000000e';

-- Future Self Letter (20 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Decide: Write TO your future self or AS your future self", "duration_seconds": 30},
  {"step": 2, "text": "If writing to future self: Begin Dear Future Me", "duration_seconds": 30},
  {"step": 3, "text": "Share your current hopes, dreams, and challenges", "duration_seconds": 300},
  {"step": 4, "text": "Ask questions you hope future you can answer", "duration_seconds": 180},
  {"step": 5, "text": "If writing as future self: Thank your present self", "duration_seconds": 180},
  {"step": 6, "text": "Share what has changed and what stayed true", "duration_seconds": 180},
  {"step": 7, "text": "Offer encouragement and gratitude", "duration_seconds": 180},
  {"step": 8, "text": "Save this letter to read later", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-00000000000f';

-- Gratitude Deep Dive (20 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get paper or open a journal", "duration_seconds": 30},
  {"step": 2, "text": "Write about gratitude for your health - big or small things", "duration_seconds": 240},
  {"step": 3, "text": "Write about gratitude for relationships", "duration_seconds": 240},
  {"step": 4, "text": "Write about opportunities you have had", "duration_seconds": 240},
  {"step": 5, "text": "Write about personal growth you have experienced", "duration_seconds": 240},
  {"step": 6, "text": "Read through what you wrote", "duration_seconds": 120},
  {"step": 7, "text": "Notice how full your life actually is", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000010';
