-- Migration: Wave 2 instructions - Mindfulness & Gratitude (26 templates)

-- =============================================================================
-- MINDFULNESS (Wave 2: 012-01e = 13 templates)
-- =============================================================================

-- Grounding Touch (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find a solid surface - table, wall, or floor", "duration_seconds": 15},
  {"step": 2, "text": "Place both hands flat on the surface", "duration_seconds": 20},
  {"step": 3, "text": "Notice the temperature - is it cool or warm?", "duration_seconds": 45},
  {"step": 4, "text": "Feel the texture beneath your palms", "duration_seconds": 45},
  {"step": 5, "text": "Press down gently and feel its stability", "duration_seconds": 45},
  {"step": 6, "text": "Let this stability anchor you to the present", "duration_seconds": 90},
  {"step": 7, "text": "Take 3 deep breaths while maintaining contact", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000012';

-- Cloud Watching (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find a spot where you can see the sky", "duration_seconds": 30},
  {"step": 2, "text": "Lie down or sit comfortably", "duration_seconds": 20},
  {"step": 3, "text": "Look up at the clouds without labeling them", "duration_seconds": 60},
  {"step": 4, "text": "Watch their slow movement across the sky", "duration_seconds": 90},
  {"step": 5, "text": "Resist naming shapes - just observe", "duration_seconds": 60},
  {"step": 6, "text": "Let your thoughts drift like the clouds", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000013';

-- Finger Breathing (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Hold one hand up, fingers spread", "duration_seconds": 15},
  {"step": 2, "text": "With your other finger, trace up your thumb - breathe in", "duration_seconds": 20},
  {"step": 3, "text": "Trace down your thumb - breathe out", "duration_seconds": 20},
  {"step": 4, "text": "Continue up each finger (inhale) and down (exhale)", "duration_seconds": 100},
  {"step": 5, "text": "Complete all five fingers on one hand", "duration_seconds": 60},
  {"step": 6, "text": "Switch hands and repeat the pattern", "duration_seconds": 100}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000014';

-- Silent Sitting (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Put away your phone and all devices", "duration_seconds": 20},
  {"step": 2, "text": "Sit comfortably with nothing to do", "duration_seconds": 20},
  {"step": 3, "text": "Simply be present with whatever arises", "duration_seconds": 90},
  {"step": 4, "text": "Notice any urges to check something - let them pass", "duration_seconds": 90},
  {"step": 5, "text": "Continue sitting in stillness", "duration_seconds": 60},
  {"step": 6, "text": "Appreciate this moment of pure being", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000015';

-- Candle Gazing (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Light a candle in a safe location", "duration_seconds": 30},
  {"step": 2, "text": "Sit comfortably about 2 feet from the flame", "duration_seconds": 20},
  {"step": 3, "text": "Soften your gaze and focus on the flame", "duration_seconds": 120},
  {"step": 4, "text": "Notice the colors, movement, and light", "duration_seconds": 120},
  {"step": 5, "text": "When your mind wanders, return to the flame", "duration_seconds": 120},
  {"step": 6, "text": "Let the light fill your awareness", "duration_seconds": 120},
  {"step": 7, "text": "Close your eyes and see the after-image", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000016';

-- Compassion Meditation (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Sit comfortably and close your eyes", "duration_seconds": 30},
  {"step": 2, "text": "Take 3 deep breaths to settle", "duration_seconds": 30},
  {"step": 3, "text": "Bring to mind someone who is struggling", "duration_seconds": 60},
  {"step": 4, "text": "Imagine them clearly - their face, their pain", "duration_seconds": 90},
  {"step": 5, "text": "Say silently: May you be free from suffering", "duration_seconds": 60},
  {"step": 6, "text": "May you find peace and healing", "duration_seconds": 60},
  {"step": 7, "text": "May you know you are not alone", "duration_seconds": 60},
  {"step": 8, "text": "Feel compassion radiating from your heart", "duration_seconds": 90},
  {"step": 9, "text": "Take a breath and open your eyes", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000017';

-- Texture Exploration (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Gather 5 objects with different textures", "duration_seconds": 90},
  {"step": 2, "text": "Close your eyes", "duration_seconds": 15},
  {"step": 3, "text": "Pick up the first object and explore with fingertips", "duration_seconds": 75},
  {"step": 4, "text": "Notice temperature, smoothness, weight", "duration_seconds": 60},
  {"step": 5, "text": "Move to the second object - explore fully", "duration_seconds": 75},
  {"step": 6, "text": "Continue with the remaining objects", "duration_seconds": 180},
  {"step": 7, "text": "Open your eyes and appreciate your sense of touch", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000018';

-- Breath Awareness (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Sit or lie in a comfortable position", "duration_seconds": 30},
  {"step": 2, "text": "Close your eyes and relax your body", "duration_seconds": 30},
  {"step": 3, "text": "Notice your natural breath - do not change it", "duration_seconds": 90},
  {"step": 4, "text": "Observe the rhythm - is it fast or slow?", "duration_seconds": 90},
  {"step": 5, "text": "Notice the depth - shallow or deep?", "duration_seconds": 90},
  {"step": 6, "text": "Feel the temperature of air entering and leaving", "duration_seconds": 90},
  {"step": 7, "text": "Simply witness your breath as it is", "duration_seconds": 120},
  {"step": 8, "text": "Take one intentional deep breath and open your eyes", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-000000000019';

-- Forest Bathing (15 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Go to a place with trees, or visualize a forest", "duration_seconds": 60},
  {"step": 2, "text": "Stand still and take 5 deep breaths", "duration_seconds": 45},
  {"step": 3, "text": "Look at the trees - notice colors, shapes, movement", "duration_seconds": 120},
  {"step": 4, "text": "Listen for forest sounds - wind, birds, rustling", "duration_seconds": 120},
  {"step": 5, "text": "Touch a tree - feel the bark texture", "duration_seconds": 90},
  {"step": 6, "text": "Smell the air - earth, leaves, nature", "duration_seconds": 90},
  {"step": 7, "text": "Walk slowly, absorbing the forest energy", "duration_seconds": 180},
  {"step": 8, "text": "Stand still once more and thank the trees", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-00000000001a';

-- Mindful Cleaning (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Choose one small cleaning task", "duration_seconds": 30},
  {"step": 2, "text": "Set an intention to clean mindfully", "duration_seconds": 20},
  {"step": 3, "text": "Begin slowly, focusing on each motion", "duration_seconds": 180},
  {"step": 4, "text": "Notice the sensation of cleaning - the pressure, movement", "duration_seconds": 180},
  {"step": 5, "text": "See the transformation from dirty to clean", "duration_seconds": 180},
  {"step": 6, "text": "If your mind wanders, return to the sensations", "duration_seconds": 180},
  {"step": 7, "text": "Complete the task and appreciate your work", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-00000000001b';

-- Gratitude Body Scan (15 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Lie down comfortably and close your eyes", "duration_seconds": 30},
  {"step": 2, "text": "Take 5 deep breaths to relax", "duration_seconds": 45},
  {"step": 3, "text": "Focus on your head - thank it for your thoughts", "duration_seconds": 90},
  {"step": 4, "text": "Move to eyes and ears - grateful for senses", "duration_seconds": 90},
  {"step": 5, "text": "Thank your heart for pumping life through you", "duration_seconds": 90},
  {"step": 6, "text": "Appreciate your lungs for every breath", "duration_seconds": 90},
  {"step": 7, "text": "Thank your stomach for processing nourishment", "duration_seconds": 90},
  {"step": 8, "text": "Grateful for legs that carry you", "duration_seconds": 90},
  {"step": 9, "text": "Thank your whole body for supporting your life", "duration_seconds": 120},
  {"step": 10, "text": "Open your eyes filled with body gratitude", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-00000000001c';

-- Silence Practice (20 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Turn off all devices and sources of sound", "duration_seconds": 30},
  {"step": 2, "text": "Find a quiet space and sit comfortably", "duration_seconds": 30},
  {"step": 3, "text": "Simply be in the silence", "duration_seconds": 240},
  {"step": 4, "text": "Notice sounds that remain - heartbeat, breath", "duration_seconds": 180},
  {"step": 5, "text": "Let silence wash over you like a wave", "duration_seconds": 180},
  {"step": 6, "text": "If thoughts arise, let them float in the quiet", "duration_seconds": 240},
  {"step": 7, "text": "Rest in this space of stillness", "duration_seconds": 240},
  {"step": 8, "text": "Slowly return to normal awareness", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-00000000001d';

-- Mindful Crafting (20 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Choose a simple craft: folding paper, organizing, arranging", "duration_seconds": 60},
  {"step": 2, "text": "Gather your materials mindfully", "duration_seconds": 60},
  {"step": 3, "text": "Begin with full attention on each movement", "duration_seconds": 180},
  {"step": 4, "text": "Notice the textures and colors you work with", "duration_seconds": 180},
  {"step": 5, "text": "Focus on precision and care in each action", "duration_seconds": 240},
  {"step": 6, "text": "If your mind wanders, return to the craft", "duration_seconds": 240},
  {"step": 7, "text": "Complete your creation with appreciation", "duration_seconds": 180},
  {"step": 8, "text": "Reflect on how mindful activity felt", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000001-0000-0000-0000-00000000001e';

-- =============================================================================
-- GRATITUDE (Wave 2: 011-01d = 13 templates)
-- =============================================================================

-- Sensory Gratitude (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Pause and take a deep breath", "duration_seconds": 15},
  {"step": 2, "text": "Look around - what are you grateful to see?", "duration_seconds": 45},
  {"step": 3, "text": "Listen - what sound are you grateful to hear?", "duration_seconds": 45},
  {"step": 4, "text": "Reach out - what texture are you grateful to feel?", "duration_seconds": 45},
  {"step": 5, "text": "Breathe in - what scent are you grateful to smell?", "duration_seconds": 45},
  {"step": 6, "text": "Notice your mouth - what taste are you grateful for?", "duration_seconds": 45},
  {"step": 7, "text": "Thank your senses for connecting you to life", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000011';

-- Hardship Appreciation (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of a past difficulty you overcame", "duration_seconds": 60},
  {"step": 2, "text": "Remember how hard it felt at the time", "duration_seconds": 45},
  {"step": 3, "text": "Ask: What strength did this build in me?", "duration_seconds": 60},
  {"step": 4, "text": "What did I learn that I could not learn another way?", "duration_seconds": 60},
  {"step": 5, "text": "Write one sentence of gratitude for this hardship", "duration_seconds": 60},
  {"step": 6, "text": "Thank the difficulty for helping you grow", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000012';

-- Ordinary Magic (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Look around for something ordinary you usually ignore", "duration_seconds": 45},
  {"step": 2, "text": "Choose one object - a pen, a cup, a light switch", "duration_seconds": 30},
  {"step": 3, "text": "Really look at it - notice every detail", "duration_seconds": 60},
  {"step": 4, "text": "Think about how it came to exist", "duration_seconds": 60},
  {"step": 5, "text": "Consider all the people involved in making it", "duration_seconds": 60},
  {"step": 6, "text": "Appreciate this ordinary magic in your life", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000013';

-- Morning Thanks (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Before getting out of bed, pause", "duration_seconds": 20},
  {"step": 2, "text": "Take 3 deep breaths", "duration_seconds": 30},
  {"step": 3, "text": "Think of one thing you look forward to today", "duration_seconds": 60},
  {"step": 4, "text": "Think of a second thing to anticipate", "duration_seconds": 60},
  {"step": 5, "text": "Think of a third thing, however small", "duration_seconds": 60},
  {"step": 6, "text": "Say thank you for this new day", "duration_seconds": 30},
  {"step": 7, "text": "Rise with this grateful energy", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000014';

-- Gratitude Walk (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Step outside and begin walking slowly", "duration_seconds": 30},
  {"step": 2, "text": "Find your first thing to be grateful for", "duration_seconds": 45},
  {"step": 3, "text": "Say a silent thank you and continue walking", "duration_seconds": 30},
  {"step": 4, "text": "Find 9 more things along your walk", "duration_seconds": 420},
  {"step": 5, "text": "Each time, pause and feel genuine gratitude", "duration_seconds": 60},
  {"step": 6, "text": "Return home carrying this grateful awareness", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000015';

-- Ancestor Appreciation (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of someone from a previous generation", "duration_seconds": 60},
  {"step": 2, "text": "A parent, grandparent, or other ancestor", "duration_seconds": 30},
  {"step": 3, "text": "Imagine what their daily life was like", "duration_seconds": 90},
  {"step": 4, "text": "What sacrifices did they make?", "duration_seconds": 90},
  {"step": 5, "text": "What did they pass down to you?", "duration_seconds": 90},
  {"step": 6, "text": "Write a few sentences of appreciation", "duration_seconds": 120},
  {"step": 7, "text": "Thank them silently for their role in your life", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000016';

-- Service Gratitude (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of people who serve your community", "duration_seconds": 60},
  {"step": 2, "text": "Mail carriers who deliver regardless of weather", "duration_seconds": 60},
  {"step": 3, "text": "Cleaners who keep spaces healthy", "duration_seconds": 60},
  {"step": 4, "text": "Drivers who move goods and people safely", "duration_seconds": 60},
  {"step": 5, "text": "Grocery workers who stock shelves", "duration_seconds": 60},
  {"step": 6, "text": "Write appreciation for these often-invisible workers", "duration_seconds": 180},
  {"step": 7, "text": "Commit to thanking one service worker today", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000017';

-- Health Inventory (10 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Sit quietly and tune into your body", "duration_seconds": 30},
  {"step": 2, "text": "List aspects of your health you take for granted", "duration_seconds": 120},
  {"step": 3, "text": "Your heart beats without you thinking about it", "duration_seconds": 60},
  {"step": 4, "text": "Your lungs breathe, your stomach digests", "duration_seconds": 60},
  {"step": 5, "text": "Your immune system fights off threats daily", "duration_seconds": 60},
  {"step": 6, "text": "Express gratitude for each system working", "duration_seconds": 120},
  {"step": 7, "text": "If something is not working well, thank what is", "duration_seconds": 90},
  {"step": 8, "text": "Commit to honoring your health today", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000018';

-- Gratitude Collage (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Decide: digital collage or cut from magazines", "duration_seconds": 30},
  {"step": 2, "text": "Search for images representing gratitude", "duration_seconds": 180},
  {"step": 3, "text": "Find images of people you appreciate", "duration_seconds": 120},
  {"step": 4, "text": "Find images of places that bring joy", "duration_seconds": 120},
  {"step": 5, "text": "Find images of things that support your life", "duration_seconds": 120},
  {"step": 6, "text": "Arrange them into a collage", "duration_seconds": 240},
  {"step": 7, "text": "Save or display your gratitude collage", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-000000000019';

-- Timeline of Blessings (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Draw a horizontal line across your paper", "duration_seconds": 30},
  {"step": 2, "text": "Mark key periods of your life along the line", "duration_seconds": 90},
  {"step": 3, "text": "For childhood: what blessings occurred?", "duration_seconds": 120},
  {"step": 4, "text": "For teenage years: what good things happened?", "duration_seconds": 120},
  {"step": 5, "text": "For young adulthood: what opportunities arose?", "duration_seconds": 120},
  {"step": 6, "text": "For recent years: what are you grateful for?", "duration_seconds": 120},
  {"step": 7, "text": "Look at your timeline and see how blessed you are", "duration_seconds": 120},
  {"step": 8, "text": "Add a blessing you hope for in the future", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-00000000001a';

-- Gratitude Interview (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find someone close to you - friend or family", "duration_seconds": 60},
  {"step": 2, "text": "Ask them: What are you grateful for today?", "duration_seconds": 30},
  {"step": 3, "text": "Listen fully to their answer", "duration_seconds": 180},
  {"step": 4, "text": "Ask a follow-up: Why does that matter to you?", "duration_seconds": 150},
  {"step": 5, "text": "Share what you are grateful for today", "duration_seconds": 180},
  {"step": 6, "text": "Discuss how gratitude affects your lives", "duration_seconds": 180},
  {"step": 7, "text": "Thank them for this gratitude exchange", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-00000000001b';

-- Gratitude Meditation Journey (20 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Lie down comfortably and close your eyes", "duration_seconds": 30},
  {"step": 2, "text": "Take 10 slow, deep breaths", "duration_seconds": 90},
  {"step": 3, "text": "Visualize a place you are grateful for", "duration_seconds": 180},
  {"step": 4, "text": "Spend time there in your mind - notice details", "duration_seconds": 180},
  {"step": 5, "text": "Now visualize a person you appreciate", "duration_seconds": 180},
  {"step": 6, "text": "Silently thank them for being in your life", "duration_seconds": 120},
  {"step": 7, "text": "Visualize a positive experience you had", "duration_seconds": 180},
  {"step": 8, "text": "Relive the joy of that moment", "duration_seconds": 120},
  {"step": 9, "text": "Let gratitude fill your entire being", "duration_seconds": 90},
  {"step": 10, "text": "Slowly return and open your eyes", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-00000000001c';

-- Thank You Letter Send (20 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Choose someone who deserves your thanks", "duration_seconds": 60},
  {"step": 2, "text": "Get paper or open your email/messages", "duration_seconds": 30},
  {"step": 3, "text": "Begin with a warm greeting", "duration_seconds": 30},
  {"step": 4, "text": "Write specifically what they did", "duration_seconds": 180},
  {"step": 5, "text": "Explain how it impacted you", "duration_seconds": 180},
  {"step": 6, "text": "Share what they mean to you", "duration_seconds": 180},
  {"step": 7, "text": "Close with heartfelt appreciation", "duration_seconds": 120},
  {"step": 8, "text": "Take a breath and actually send it", "duration_seconds": 60},
  {"step": 9, "text": "Notice how expressing gratitude feels", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000002-0000-0000-0000-00000000001d';
