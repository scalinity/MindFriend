-- Migration: Wave 1 instructions - Social, Physical, Creative, Reflection

-- =============================================================================
-- SOCIAL (Wave 1: 004-011 = 14 templates)
-- =============================================================================

-- Smile Mission (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Set an intention to smile at 3 people today", "duration_seconds": 30},
  {"step": 2, "text": "Find your first person and make gentle eye contact", "duration_seconds": 60},
  {"step": 3, "text": "Offer a genuine, warm smile", "duration_seconds": 30},
  {"step": 4, "text": "Notice their reaction - did they smile back?", "duration_seconds": 30},
  {"step": 5, "text": "Repeat with two more people", "duration_seconds": 120},
  {"step": 6, "text": "Reflect on how spreading smiles made you feel", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000004';

-- Voice Note Love (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of someone you care about", "duration_seconds": 30},
  {"step": 2, "text": "Open your messaging app and start a voice recording", "duration_seconds": 20},
  {"step": 3, "text": "Say hi and tell them you are thinking of them", "duration_seconds": 60},
  {"step": 4, "text": "Share something you appreciate about them", "duration_seconds": 60},
  {"step": 5, "text": "Wish them a good day", "duration_seconds": 30},
  {"step": 6, "text": "Send the message and feel the connection", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000005';

-- Positive Comment (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Open social media or think of someone nearby", "duration_seconds": 30},
  {"step": 2, "text": "Find something genuinely positive to say", "duration_seconds": 60},
  {"step": 3, "text": "Leave your first genuine compliment or kind comment", "duration_seconds": 60},
  {"step": 4, "text": "Find a second person and do the same", "duration_seconds": 60},
  {"step": 5, "text": "Leave a third positive comment", "duration_seconds": 60},
  {"step": 6, "text": "Notice how spreading positivity feels", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000006';

-- Kindness Planning (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think about tomorrow and who you will see", "duration_seconds": 60},
  {"step": 2, "text": "Choose one person to show kindness to", "duration_seconds": 45},
  {"step": 3, "text": "Decide what act of kindness you will do", "duration_seconds": 60},
  {"step": 4, "text": "Write down: Who, What, and When", "duration_seconds": 60},
  {"step": 5, "text": "Visualize yourself doing this kind act", "duration_seconds": 45},
  {"step": 6, "text": "Commit to following through tomorrow", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000007';

-- Quick Check-In (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of someone you have not heard from lately", "duration_seconds": 45},
  {"step": 2, "text": "Open your messaging app", "duration_seconds": 15},
  {"step": 3, "text": "Type a simple message: Hey, thinking of you!", "duration_seconds": 60},
  {"step": 4, "text": "Add something personal - a memory or question", "duration_seconds": 90},
  {"step": 5, "text": "Send it with no expectation of reply", "duration_seconds": 30},
  {"step": 6, "text": "Feel good about maintaining connection", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000008';

-- Meaningful Question (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find someone to talk with - in person or by call", "duration_seconds": 60},
  {"step": 2, "text": "Ask them: How are you really doing?", "duration_seconds": 30},
  {"step": 3, "text": "Wait for their full answer without interrupting", "duration_seconds": 180},
  {"step": 4, "text": "Show you heard by reflecting back what they said", "duration_seconds": 60},
  {"step": 5, "text": "Ask a follow-up question to go deeper", "duration_seconds": 180},
  {"step": 6, "text": "Thank them for sharing with you", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000009';

-- Shared Memory (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of a friend and a positive memory together", "duration_seconds": 90},
  {"step": 2, "text": "Write out the memory in a message", "duration_seconds": 180},
  {"step": 3, "text": "Share why it still makes you smile", "duration_seconds": 120},
  {"step": 4, "text": "Send the message to them", "duration_seconds": 30},
  {"step": 5, "text": "Wait for their response or reminisce on your own", "duration_seconds": 120}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-00000000000a';

-- Appreciation Call (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Choose someone important to you", "duration_seconds": 30},
  {"step": 2, "text": "Call them (text to schedule if needed)", "duration_seconds": 60},
  {"step": 3, "text": "Tell them specifically why you are calling", "duration_seconds": 60},
  {"step": 4, "text": "Share what you appreciate about them", "duration_seconds": 180},
  {"step": 5, "text": "Tell them how they have positively affected your life", "duration_seconds": 180},
  {"step": 6, "text": "Let them respond and receive their reaction", "duration_seconds": 90}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-00000000000b';

-- Mentor Moment (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of something you have learned or experienced", "duration_seconds": 60},
  {"step": 2, "text": "Identify someone who could benefit from this wisdom", "duration_seconds": 60},
  {"step": 3, "text": "Reach out to them with your insight", "duration_seconds": 120},
  {"step": 4, "text": "Share the lesson in an encouraging way", "duration_seconds": 180},
  {"step": 5, "text": "Offer to talk more if they want support", "duration_seconds": 90},
  {"step": 6, "text": "Feel good about paying it forward", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-00000000000c';

-- Conflict Repair (10 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of a small tension with someone", "duration_seconds": 60},
  {"step": 2, "text": "Consider their perspective genuinely", "duration_seconds": 90},
  {"step": 3, "text": "Decide on a peace offering - apology or kind gesture", "duration_seconds": 60},
  {"step": 4, "text": "Reach out with openness and humility", "duration_seconds": 120},
  {"step": 5, "text": "Express that you value the relationship", "duration_seconds": 120},
  {"step": 6, "text": "Listen to their response without defensiveness", "duration_seconds": 120},
  {"step": 7, "text": "Feel relief from extending the olive branch", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-00000000000d';

-- Deep Listening Call (15 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Call someone and set an intention to truly listen", "duration_seconds": 60},
  {"step": 2, "text": "Ask an open question about their life", "duration_seconds": 30},
  {"step": 3, "text": "Listen without planning what to say next", "duration_seconds": 180},
  {"step": 4, "text": "Ask follow-up questions that show understanding", "duration_seconds": 180},
  {"step": 5, "text": "Resist sharing your own stories - keep focus on them", "duration_seconds": 180},
  {"step": 6, "text": "Summarize what you heard them say", "duration_seconds": 90},
  {"step": 7, "text": "Thank them for sharing and say goodbye warmly", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-00000000000e';

-- Family Video Call (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Choose a family member you have not connected with recently", "duration_seconds": 30},
  {"step": 2, "text": "Schedule or initiate a video call", "duration_seconds": 60},
  {"step": 3, "text": "Start with genuine interest in how they are", "duration_seconds": 120},
  {"step": 4, "text": "Share updates about your life too", "duration_seconds": 180},
  {"step": 5, "text": "Ask about other family members if appropriate", "duration_seconds": 180},
  {"step": 6, "text": "Express appreciation for the connection", "duration_seconds": 120},
  {"step": 7, "text": "Make a plan to talk again soon", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-00000000000f';

-- Boundary Practice (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of something small you want to say no to", "duration_seconds": 60},
  {"step": 2, "text": "Write out a kind but clear decline", "duration_seconds": 120},
  {"step": 3, "text": "Practice saying it aloud to yourself", "duration_seconds": 90},
  {"step": 4, "text": "When the moment comes, deliver your no with warmth", "duration_seconds": 180},
  {"step": 5, "text": "Notice any guilt and let it pass", "duration_seconds": 120},
  {"step": 6, "text": "Appreciate yourself for honoring your limits", "duration_seconds": 90},
  {"step": 7, "text": "Reflect on how it felt to set a boundary", "duration_seconds": 90}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000010';

-- Quality Time Block (20 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Choose someone important to spend time with", "duration_seconds": 30},
  {"step": 2, "text": "Put away all devices - phones, tablets, etc", "duration_seconds": 30},
  {"step": 3, "text": "Give them your complete, undivided attention", "duration_seconds": 300},
  {"step": 4, "text": "Engage in whatever they want to do or talk about", "duration_seconds": 360},
  {"step": 5, "text": "Be fully present - notice details about them", "duration_seconds": 300},
  {"step": 6, "text": "Express gratitude for this quality time together", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000011';

-- =============================================================================
-- PHYSICAL (Wave 1: 004-011 = 14 templates)
-- =============================================================================

-- Desk Stretches (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Sit tall in your chair or stand up", "duration_seconds": 15},
  {"step": 2, "text": "Roll your neck slowly in circles - 5 each direction", "duration_seconds": 40},
  {"step": 3, "text": "Shrug shoulders up to ears, hold, release - 5 times", "duration_seconds": 40},
  {"step": 4, "text": "Rotate wrists in circles - 10 each direction", "duration_seconds": 40},
  {"step": 5, "text": "Twist your torso gently left and right", "duration_seconds": 50},
  {"step": 6, "text": "Reach arms overhead and stretch side to side", "duration_seconds": 50},
  {"step": 7, "text": "Take 3 deep breaths and feel refreshed", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000004';

-- Posture Reset (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Stand with feet hip-width apart", "duration_seconds": 20},
  {"step": 2, "text": "Feel your feet rooted to the ground", "duration_seconds": 30},
  {"step": 3, "text": "Imagine a string pulling your head toward the ceiling", "duration_seconds": 45},
  {"step": 4, "text": "Roll your shoulders back and down", "duration_seconds": 45},
  {"step": 5, "text": "Engage your core gently", "duration_seconds": 30},
  {"step": 6, "text": "Take 5 deep breaths in this aligned posture", "duration_seconds": 75},
  {"step": 7, "text": "Memorize this feeling for the rest of your day", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000005';

-- Shake It Out (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Stand with space around you", "duration_seconds": 15},
  {"step": 2, "text": "Start shaking your hands vigorously", "duration_seconds": 30},
  {"step": 3, "text": "Let the shaking travel up your arms", "duration_seconds": 30},
  {"step": 4, "text": "Shake your shoulders and torso", "duration_seconds": 30},
  {"step": 5, "text": "Shake your legs and feet", "duration_seconds": 30},
  {"step": 6, "text": "Shake your whole body - look silly, feel great", "duration_seconds": 60},
  {"step": 7, "text": "Slow down and stand completely still", "duration_seconds": 30},
  {"step": 8, "text": "Notice the tingling energy in your body", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000006';

-- Balance Challenge (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Stand near a wall for support if needed", "duration_seconds": 15},
  {"step": 2, "text": "Fix your gaze on a point in front of you", "duration_seconds": 15},
  {"step": 3, "text": "Lift your right foot and balance on your left", "duration_seconds": 45},
  {"step": 4, "text": "Hold as long as you can, up to 30 seconds", "duration_seconds": 30},
  {"step": 5, "text": "Lower and switch to the other foot", "duration_seconds": 45},
  {"step": 6, "text": "Try again with eyes closed for extra challenge", "duration_seconds": 60},
  {"step": 7, "text": "Notice how your body found stability", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000007';

-- Power Pose (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Stand tall with feet apart", "duration_seconds": 15},
  {"step": 2, "text": "Place hands on hips like a superhero", "duration_seconds": 45},
  {"step": 3, "text": "Hold this pose and breathe deeply", "duration_seconds": 45},
  {"step": 4, "text": "Raise your arms in a V for victory", "duration_seconds": 45},
  {"step": 5, "text": "Feel confident energy building", "duration_seconds": 45},
  {"step": 6, "text": "Try one more pose that makes you feel powerful", "duration_seconds": 60},
  {"step": 7, "text": "Lower your arms and notice your energy shift", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000008';

-- Sun Salutations (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Stand at the front of your mat or clear space", "duration_seconds": 30},
  {"step": 2, "text": "Inhale, raise arms overhead", "duration_seconds": 20},
  {"step": 3, "text": "Exhale, fold forward to touch toes or shins", "duration_seconds": 20},
  {"step": 4, "text": "Inhale, lift halfway with flat back", "duration_seconds": 15},
  {"step": 5, "text": "Exhale, step or jump back to plank", "duration_seconds": 20},
  {"step": 6, "text": "Lower to floor, inhale to cobra or upward dog", "duration_seconds": 25},
  {"step": 7, "text": "Exhale, lift hips to downward dog", "duration_seconds": 30},
  {"step": 8, "text": "Hold for 5 breaths", "duration_seconds": 40},
  {"step": 9, "text": "Step forward and rise to standing", "duration_seconds": 20},
  {"step": 10, "text": "Repeat 3-5 more times at your own pace", "duration_seconds": 360}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000009';

-- Energizing Walk (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Put on shoes and step outside", "duration_seconds": 30},
  {"step": 2, "text": "Start walking at a comfortable pace", "duration_seconds": 60},
  {"step": 3, "text": "Gradually increase your speed", "duration_seconds": 90},
  {"step": 4, "text": "Swing your arms and lengthen your stride", "duration_seconds": 120},
  {"step": 5, "text": "Walk briskly - you should feel slightly breathless", "duration_seconds": 180},
  {"step": 6, "text": "Maintain this pace, enjoying the movement", "duration_seconds": 90},
  {"step": 7, "text": "Slow down gradually as you head back", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-00000000000a';

-- Progressive Stretching (10 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Stand or sit comfortably", "duration_seconds": 20},
  {"step": 2, "text": "Stretch your calves - push against a wall or step", "duration_seconds": 60},
  {"step": 3, "text": "Stretch your thighs - quad pulls or lunges", "duration_seconds": 60},
  {"step": 4, "text": "Stretch your hips - pigeon pose or figure four", "duration_seconds": 90},
  {"step": 5, "text": "Stretch your back - cat-cow or spinal twist", "duration_seconds": 90},
  {"step": 6, "text": "Stretch your shoulders - cross-body arm pulls", "duration_seconds": 60},
  {"step": 7, "text": "Stretch your neck - gentle head tilts", "duration_seconds": 60},
  {"step": 8, "text": "Take 3 deep breaths and feel looser", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-00000000000b';

-- Stair Climbing (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find a staircase - indoor or outdoor", "duration_seconds": 30},
  {"step": 2, "text": "Walk up one flight slowly, feeling each step", "duration_seconds": 60},
  {"step": 3, "text": "Notice your muscles working", "duration_seconds": 30},
  {"step": 4, "text": "Walk down and then climb again at a faster pace", "duration_seconds": 90},
  {"step": 5, "text": "Continue climbing for several minutes", "duration_seconds": 240},
  {"step": 6, "text": "Slow down for your final climb", "duration_seconds": 60},
  {"step": 7, "text": "Rest at the top and notice your heart beating", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-00000000000c';

-- Gentle Core Work (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Lie on your back with knees bent", "duration_seconds": 20},
  {"step": 2, "text": "Engage your core and flatten your lower back", "duration_seconds": 30},
  {"step": 3, "text": "Hold a plank for 20-30 seconds", "duration_seconds": 40},
  {"step": 4, "text": "Rest, then do bird-dog: extend opposite arm and leg", "duration_seconds": 90},
  {"step": 5, "text": "Try dead bugs: opposite arm and leg lower", "duration_seconds": 90},
  {"step": 6, "text": "Return to plank for another 20-30 seconds", "duration_seconds": 40},
  {"step": 7, "text": "Rest and feel your core activation", "duration_seconds": 90}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-00000000000d';

-- Mindful Nature Walk (15 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Step outside into a natural area if possible", "duration_seconds": 60},
  {"step": 2, "text": "Begin walking slowly and deliberately", "duration_seconds": 60},
  {"step": 3, "text": "Feel your feet connecting with the earth", "duration_seconds": 120},
  {"step": 4, "text": "Observe plants, trees, or any nature around you", "duration_seconds": 180},
  {"step": 5, "text": "Listen for natural sounds - birds, wind, water", "duration_seconds": 120},
  {"step": 6, "text": "Breathe deeply and smell the fresh air", "duration_seconds": 90},
  {"step": 7, "text": "Feel gratitude for the natural world", "duration_seconds": 90},
  {"step": 8, "text": "Return home carrying this peace with you", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-00000000000e';

-- Strength Circuit (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find a clear space and warm up with marching", "duration_seconds": 60},
  {"step": 2, "text": "Do 10-15 squats at your own pace", "duration_seconds": 90},
  {"step": 3, "text": "Rest briefly, then do 10-15 push-ups (knees ok)", "duration_seconds": 90},
  {"step": 4, "text": "Do 10 lunges on each leg", "duration_seconds": 90},
  {"step": 5, "text": "Hold a plank for 30 seconds", "duration_seconds": 45},
  {"step": 6, "text": "Repeat the circuit one more time", "duration_seconds": 300},
  {"step": 7, "text": "Cool down with gentle stretching", "duration_seconds": 90}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-00000000000f';

-- Full Body Flow (20 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Start with 2 minutes of gentle marching or jumping jacks", "duration_seconds": 120},
  {"step": 2, "text": "Do arm circles and leg swings to loosen up", "duration_seconds": 90},
  {"step": 3, "text": "Move through a stretching sequence", "duration_seconds": 180},
  {"step": 4, "text": "Do bodyweight exercises: squats, lunges, push-ups", "duration_seconds": 300},
  {"step": 5, "text": "Add some core work: planks and crunches", "duration_seconds": 180},
  {"step": 6, "text": "Finish with a 2-minute cool-down stretch", "duration_seconds": 120},
  {"step": 7, "text": "Lie still and feel your body buzzing with energy", "duration_seconds": 90}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000010';

-- Walking Meditation (20 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find a quiet path where you can walk slowly", "duration_seconds": 60},
  {"step": 2, "text": "Stand still and take 3 centering breaths", "duration_seconds": 30},
  {"step": 3, "text": "Begin walking very slowly", "duration_seconds": 120},
  {"step": 4, "text": "Feel each foot lift off the ground", "duration_seconds": 180},
  {"step": 5, "text": "Notice the movement through space", "duration_seconds": 180},
  {"step": 6, "text": "Feel each foot touch down again", "duration_seconds": 180},
  {"step": 7, "text": "Continue this mindful pace for the duration", "duration_seconds": 300},
  {"step": 8, "text": "Stop and stand still for a final breath", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000011';

-- =============================================================================
-- CREATIVE (Wave 1: 004-010 = 13 templates)
-- =============================================================================

-- Word Association (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get paper or open a blank document", "duration_seconds": 20},
  {"step": 2, "text": "Pick a random word - book, cloud, journey, anything", "duration_seconds": 20},
  {"step": 3, "text": "Write that word at the top", "duration_seconds": 10},
  {"step": 4, "text": "Start writing whatever comes to mind", "duration_seconds": 180},
  {"step": 5, "text": "Do not stop, edit, or judge - just flow", "duration_seconds": 60},
  {"step": 6, "text": "Read what you wrote with curiosity", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000004';

-- Quick Sketch (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Grab paper and pen or pencil", "duration_seconds": 20},
  {"step": 2, "text": "Look around and pick the first object you see", "duration_seconds": 15},
  {"step": 3, "text": "Begin drawing it without worrying about quality", "duration_seconds": 180},
  {"step": 4, "text": "Focus on basic shapes and lines", "duration_seconds": 60},
  {"step": 5, "text": "Add a few details if time allows", "duration_seconds": 30},
  {"step": 6, "text": "Sign and date your quick sketch", "duration_seconds": 15}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000005';

-- Haiku Challenge (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Take a moment to notice how you feel right now", "duration_seconds": 30},
  {"step": 2, "text": "A haiku has 3 lines: 5 syllables, 7 syllables, 5 syllables", "duration_seconds": 20},
  {"step": 3, "text": "Write your first line - 5 syllables about this moment", "duration_seconds": 60},
  {"step": 4, "text": "Write your second line - 7 syllables continuing the thought", "duration_seconds": 90},
  {"step": 5, "text": "Write your third line - 5 syllables to close", "duration_seconds": 60},
  {"step": 6, "text": "Read your haiku aloud and enjoy your creation", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000006';

-- Color Hunt (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Pick a color - any color that appeals to you", "duration_seconds": 15},
  {"step": 2, "text": "Start looking for that color everywhere around you", "duration_seconds": 60},
  {"step": 3, "text": "Notice different shades and variations", "duration_seconds": 60},
  {"step": 4, "text": "Count how many instances you can find", "duration_seconds": 90},
  {"step": 5, "text": "Appreciate how this color shows up in unexpected places", "duration_seconds": 60},
  {"step": 6, "text": "Notice if you see this color differently now", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000007';

-- Sound Creation (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Look around for objects that could make sounds", "duration_seconds": 30},
  {"step": 2, "text": "Tap, shake, or scrape different surfaces", "duration_seconds": 60},
  {"step": 3, "text": "Find at least 3 interesting sounds", "duration_seconds": 60},
  {"step": 4, "text": "Create a simple rhythm using these sounds", "duration_seconds": 90},
  {"step": 5, "text": "Try adding a melody or pattern", "duration_seconds": 45},
  {"step": 6, "text": "Perform your composition for yourself", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000008';

-- Story Starter (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get paper or open a document", "duration_seconds": 20},
  {"step": 2, "text": "Think of a character - give them a name", "duration_seconds": 45},
  {"step": 3, "text": "Write the opening scene - where are they?", "duration_seconds": 120},
  {"step": 4, "text": "Introduce a problem or mystery", "duration_seconds": 120},
  {"step": 5, "text": "End on something intriguing", "duration_seconds": 120},
  {"step": 6, "text": "You can continue this story later or let it rest", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000009';

-- Photography Walk (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get your phone camera ready", "duration_seconds": 20},
  {"step": 2, "text": "Step outside or explore your space", "duration_seconds": 30},
  {"step": 3, "text": "Look for beauty in unexpected places", "duration_seconds": 90},
  {"step": 4, "text": "Take your first meaningful photo", "duration_seconds": 60},
  {"step": 5, "text": "Find and capture 4 more interesting subjects", "duration_seconds": 300},
  {"step": 6, "text": "Review your photos and pick a favorite", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-00000000000a';

-- Playlist Curation (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Open your music app", "duration_seconds": 20},
  {"step": 2, "text": "Think about your current mood or desired mood", "duration_seconds": 30},
  {"step": 3, "text": "Create a new playlist with a meaningful name", "duration_seconds": 30},
  {"step": 4, "text": "Add songs that capture this feeling", "duration_seconds": 300},
  {"step": 5, "text": "Aim for 5-10 songs that flow well together", "duration_seconds": 180},
  {"step": 6, "text": "Save and play the first song to test the vibe", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-00000000000b';

-- Memory Drawing (10 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get paper and something to draw with", "duration_seconds": 20},
  {"step": 2, "text": "Close your eyes and recall a happy memory", "duration_seconds": 60},
  {"step": 3, "text": "Focus on the scene - what did you see?", "duration_seconds": 60},
  {"step": 4, "text": "Start drawing this memory on paper", "duration_seconds": 240},
  {"step": 5, "text": "Do not worry about skill - focus on feeling", "duration_seconds": 120},
  {"step": 6, "text": "Add any words or labels that enhance the memory", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-00000000000c';

-- Nature Art (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Go outside or find natural materials indoors", "duration_seconds": 60},
  {"step": 2, "text": "Collect leaves, sticks, stones, flowers, etc", "duration_seconds": 180},
  {"step": 3, "text": "Find a flat surface to work on", "duration_seconds": 30},
  {"step": 4, "text": "Arrange your materials into a pattern or design", "duration_seconds": 180},
  {"step": 5, "text": "Create a mandala, face, or abstract art", "duration_seconds": 90},
  {"step": 6, "text": "Take a photo to remember your creation", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-00000000000d';

-- Letter to Self (15 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Decide: write to past self or future self", "duration_seconds": 30},
  {"step": 2, "text": "Get paper or open a document", "duration_seconds": 20},
  {"step": 3, "text": "Begin with Dear Past/Future Me", "duration_seconds": 20},
  {"step": 4, "text": "Share what you want them to know", "duration_seconds": 300},
  {"step": 5, "text": "Offer compassion, advice, or encouragement", "duration_seconds": 240},
  {"step": 6, "text": "Close with love and sign your name", "duration_seconds": 60},
  {"step": 7, "text": "Save this letter somewhere meaningful", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-00000000000e';

-- Collage Creation (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Decide: digital collage or physical cutouts", "duration_seconds": 30},
  {"step": 2, "text": "Gather images that represent your theme", "duration_seconds": 180},
  {"step": 3, "text": "Choose 5-10 images that speak to you", "duration_seconds": 120},
  {"step": 4, "text": "Arrange them on paper or in an app", "duration_seconds": 240},
  {"step": 5, "text": "Play with placement until it feels right", "duration_seconds": 180},
  {"step": 6, "text": "Add any words or embellishments", "duration_seconds": 90},
  {"step": 7, "text": "Save or display your finished collage", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-00000000000f';

-- Creative Writing Session (20 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get comfortable with paper or keyboard", "duration_seconds": 30},
  {"step": 2, "text": "Set a timer for 20 minutes", "duration_seconds": 15},
  {"step": 3, "text": "Pick a prompt: a word, image, or feeling", "duration_seconds": 30},
  {"step": 4, "text": "Begin writing without stopping or editing", "duration_seconds": 600},
  {"step": 5, "text": "Let whatever wants to emerge come through", "duration_seconds": 300},
  {"step": 6, "text": "When the timer sounds, finish your thought", "duration_seconds": 120},
  {"step": 7, "text": "Read what you wrote with compassion", "duration_seconds": 90}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000010';

-- =============================================================================
-- REFLECTION (Wave 1: 006-011 = 12 templates)
-- =============================================================================

-- Values Check (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of 3 core values important to you", "duration_seconds": 45},
  {"step": 2, "text": "Reflect on your day so far", "duration_seconds": 30},
  {"step": 3, "text": "Did you honor your first value today? How?", "duration_seconds": 60},
  {"step": 4, "text": "What about your second value?", "duration_seconds": 60},
  {"step": 5, "text": "And your third?", "duration_seconds": 60},
  {"step": 6, "text": "Choose one value to focus on tomorrow", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000006';

-- Energy Audit (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think back through your day", "duration_seconds": 30},
  {"step": 2, "text": "List 2-3 things that gave you energy", "duration_seconds": 90},
  {"step": 3, "text": "List 2-3 things that drained your energy", "duration_seconds": 90},
  {"step": 4, "text": "Notice any patterns", "duration_seconds": 45},
  {"step": 5, "text": "Identify one energy-giving activity to do more of", "duration_seconds": 30},
  {"step": 6, "text": "Identify one draining activity to reduce", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000007';

-- Intention Setting (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Take a deep breath and clear your mind", "duration_seconds": 20},
  {"step": 2, "text": "Think about tomorrow", "duration_seconds": 30},
  {"step": 3, "text": "What one thing would make tomorrow meaningful?", "duration_seconds": 60},
  {"step": 4, "text": "Write down a clear, specific intention", "duration_seconds": 90},
  {"step": 5, "text": "Read it aloud: Tomorrow I will...", "duration_seconds": 30},
  {"step": 6, "text": "Visualize yourself accomplishing this intention", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000008';

-- Mood Check (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Pause and take 3 deep breaths", "duration_seconds": 30},
  {"step": 2, "text": "Ask yourself: How am I feeling right now?", "duration_seconds": 30},
  {"step": 3, "text": "Name the emotion without judging it", "duration_seconds": 45},
  {"step": 4, "text": "Notice where you feel it in your body", "duration_seconds": 45},
  {"step": 5, "text": "Accept this feeling as valid information", "duration_seconds": 60},
  {"step": 6, "text": "Ask: What does this emotion need from me?", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000009';

-- Week Review (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find a quiet moment to reflect", "duration_seconds": 30},
  {"step": 2, "text": "What were the highlights of this week?", "duration_seconds": 120},
  {"step": 3, "text": "What challenged you the most?", "duration_seconds": 90},
  {"step": 4, "text": "What did you learn or realize?", "duration_seconds": 120},
  {"step": 5, "text": "What are you grateful for from this week?", "duration_seconds": 90},
  {"step": 6, "text": "What do you want next week to bring?", "duration_seconds": 90}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-00000000000a';

-- Emotion Processing (10 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of a recent strong emotion you felt", "duration_seconds": 30},
  {"step": 2, "text": "Name it precisely - not just sad but disappointed, lonely, grieving", "duration_seconds": 60},
  {"step": 3, "text": "Where do you feel it in your body?", "duration_seconds": 60},
  {"step": 4, "text": "What triggered this emotion?", "duration_seconds": 90},
  {"step": 5, "text": "What need or value is connected to it?", "duration_seconds": 120},
  {"step": 6, "text": "What would help you process or release it?", "duration_seconds": 120},
  {"step": 7, "text": "Take 3 breaths and thank the emotion for its message", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-00000000000b';

-- Decision Reflection (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of a recent decision you made", "duration_seconds": 30},
  {"step": 2, "text": "What factors influenced your choice?", "duration_seconds": 120},
  {"step": 3, "text": "What was the outcome?", "duration_seconds": 90},
  {"step": 4, "text": "Looking back, was it the right decision?", "duration_seconds": 90},
  {"step": 5, "text": "What would you do differently next time?", "duration_seconds": 120},
  {"step": 6, "text": "What did this decision teach you about yourself?", "duration_seconds": 90}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-00000000000c';

-- Growth Spotting (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think back over the past few months", "duration_seconds": 30},
  {"step": 2, "text": "Identify one way you have grown", "duration_seconds": 120},
  {"step": 3, "text": "What helped you grow in this way?", "duration_seconds": 90},
  {"step": 4, "text": "How does this growth show up in your daily life?", "duration_seconds": 120},
  {"step": 5, "text": "What further growth would you like to see?", "duration_seconds": 90},
  {"step": 6, "text": "Acknowledge yourself for your progress", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-00000000000d';

-- Life Domain Review (15 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Rate your health and wellbeing 1-10", "duration_seconds": 90},
  {"step": 2, "text": "Rate your relationships 1-10", "duration_seconds": 90},
  {"step": 3, "text": "Rate your work or purpose 1-10", "duration_seconds": 90},
  {"step": 4, "text": "Rate your personal growth 1-10", "duration_seconds": 90},
  {"step": 5, "text": "Rate your fun and recreation 1-10", "duration_seconds": 90},
  {"step": 6, "text": "Which area needs the most attention?", "duration_seconds": 120},
  {"step": 7, "text": "What one action could improve that area?", "duration_seconds": 120},
  {"step": 8, "text": "Commit to taking that action this week", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-00000000000e';

-- Fear Inventory (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get paper and take a centering breath", "duration_seconds": 30},
  {"step": 2, "text": "List fears that are holding you back", "duration_seconds": 180},
  {"step": 3, "text": "Choose the biggest one", "duration_seconds": 30},
  {"step": 4, "text": "Ask: What is the worst that could happen?", "duration_seconds": 90},
  {"step": 5, "text": "How likely is that outcome really?", "duration_seconds": 90},
  {"step": 6, "text": "What small action could you take to face this fear?", "duration_seconds": 120},
  {"step": 7, "text": "Write down one tiny step you will take this week", "duration_seconds": 90},
  {"step": 8, "text": "Feel courage building within you", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-00000000000f';

-- Future Visioning (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Close your eyes and take 5 deep breaths", "duration_seconds": 45},
  {"step": 2, "text": "Imagine yourself 5 years from now", "duration_seconds": 60},
  {"step": 3, "text": "Where do you wake up? Describe the place", "duration_seconds": 120},
  {"step": 4, "text": "What does your ideal day look like?", "duration_seconds": 180},
  {"step": 5, "text": "Who is with you? What relationships do you have?", "duration_seconds": 120},
  {"step": 6, "text": "What work or purpose fills your time?", "duration_seconds": 120},
  {"step": 7, "text": "Open your eyes and write down key elements", "duration_seconds": 120},
  {"step": 8, "text": "What one step today moves you toward this vision?", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000010';

-- Monthly Retrospective (20 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get paper or journal and settle in", "duration_seconds": 30},
  {"step": 2, "text": "List your accomplishments this month, big and small", "duration_seconds": 240},
  {"step": 3, "text": "What challenges did you face?", "duration_seconds": 150},
  {"step": 4, "text": "What lessons did you learn?", "duration_seconds": 150},
  {"step": 5, "text": "What are you most grateful for?", "duration_seconds": 120},
  {"step": 6, "text": "What do you want to release from this month?", "duration_seconds": 90},
  {"step": 7, "text": "Set 3 intentions for next month", "duration_seconds": 180},
  {"step": 8, "text": "Close with appreciation for your journey", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000011';
