-- Migration: Wave 2 instructions - Social, Physical, Creative, Reflection

-- =============================================================================
-- SOCIAL (Wave 2: 012-01e = 13 templates)
-- =============================================================================

-- Genuine Interest (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find someone to talk with", "duration_seconds": 60},
  {"step": 2, "text": "Ask them a question about their life", "duration_seconds": 30},
  {"step": 3, "text": "Listen to their answer with full attention", "duration_seconds": 120},
  {"step": 4, "text": "Be genuinely curious - ask a follow-up", "duration_seconds": 60},
  {"step": 5, "text": "Resist the urge to talk about yourself", "duration_seconds": 30},
  {"step": 6, "text": "Thank them for sharing", "duration_seconds": 20}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000012';

-- Encourage Someone (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of someone facing a challenge", "duration_seconds": 45},
  {"step": 2, "text": "What specific strength do they have?", "duration_seconds": 45},
  {"step": 3, "text": "Compose a message of encouragement", "duration_seconds": 120},
  {"step": 4, "text": "Be specific about their strengths", "duration_seconds": 60},
  {"step": 5, "text": "Send the message", "duration_seconds": 20},
  {"step": 6, "text": "Feel good about lifting someone up", "duration_seconds": 20}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000013';

-- Reconnect Thought (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of someone you have lost touch with", "duration_seconds": 60},
  {"step": 2, "text": "Remember something good about your connection", "duration_seconds": 60},
  {"step": 3, "text": "Compose a brief hello message", "duration_seconds": 120},
  {"step": 4, "text": "Keep it simple - just reaching out", "duration_seconds": 45},
  {"step": 5, "text": "Send it without overthinking", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000014';

-- Pay It Forward (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Decide on a small act of kindness for a stranger", "duration_seconds": 45},
  {"step": 2, "text": "Options: hold a door, compliment, buy coffee", "duration_seconds": 30},
  {"step": 3, "text": "Look for your opportunity", "duration_seconds": 90},
  {"step": 4, "text": "Do the kind act without expecting anything", "duration_seconds": 60},
  {"step": 5, "text": "Notice how random kindness feels", "duration_seconds": 60},
  {"step": 6, "text": "Carry this energy into the rest of your day", "duration_seconds": 20}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000015';

-- Empathy Practice (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of someone whose views differ from yours", "duration_seconds": 60},
  {"step": 2, "text": "Set aside your own perspective temporarily", "duration_seconds": 30},
  {"step": 3, "text": "Imagine their life experiences", "duration_seconds": 120},
  {"step": 4, "text": "What might have shaped their views?", "duration_seconds": 120},
  {"step": 5, "text": "Find one thing you can understand about their position", "duration_seconds": 120},
  {"step": 6, "text": "Notice any shift in your feelings toward them", "duration_seconds": 90},
  {"step": 7, "text": "Practice holding space for different perspectives", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000016';

-- Celebration Message (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of someone who achieved something recently", "duration_seconds": 60},
  {"step": 2, "text": "It can be big or small", "duration_seconds": 30},
  {"step": 3, "text": "Write a message celebrating their achievement", "duration_seconds": 180},
  {"step": 4, "text": "Be specific about what they accomplished", "duration_seconds": 90},
  {"step": 5, "text": "Express genuine happiness for them", "duration_seconds": 90},
  {"step": 6, "text": "Send the celebration message", "duration_seconds": 30},
  {"step": 7, "text": "Notice how celebrating others feels", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000017';

-- Forgiveness Practice (10 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of someone who wronged you - start small", "duration_seconds": 60},
  {"step": 2, "text": "Acknowledge the pain they caused", "duration_seconds": 90},
  {"step": 3, "text": "Remember: forgiveness is for your peace", "duration_seconds": 60},
  {"step": 4, "text": "Silently say: I release this resentment", "duration_seconds": 60},
  {"step": 5, "text": "Wish them well in your mind", "duration_seconds": 90},
  {"step": 6, "text": "This does not mean approving what they did", "duration_seconds": 60},
  {"step": 7, "text": "Feel the weight of resentment lighten", "duration_seconds": 90},
  {"step": 8, "text": "Thank yourself for choosing peace", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000018';

-- Ask for Help (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of something small you need help with", "duration_seconds": 60},
  {"step": 2, "text": "Identify someone who could help", "duration_seconds": 45},
  {"step": 3, "text": "Reach out and make your request clearly", "duration_seconds": 120},
  {"step": 4, "text": "Be specific about what you need", "duration_seconds": 90},
  {"step": 5, "text": "Practice receiving their response gracefully", "duration_seconds": 120},
  {"step": 6, "text": "Express genuine gratitude whether yes or no", "duration_seconds": 60},
  {"step": 7, "text": "Reflect on the courage it takes to ask for help", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-000000000019';

-- Vulnerability Share (15 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think about how you are really feeling lately", "duration_seconds": 90},
  {"step": 2, "text": "Choose someone you trust deeply", "duration_seconds": 60},
  {"step": 3, "text": "Reach out and ask if they have time to listen", "duration_seconds": 60},
  {"step": 4, "text": "Share honestly about your struggles or feelings", "duration_seconds": 300},
  {"step": 5, "text": "Let yourself be seen without performing", "duration_seconds": 180},
  {"step": 6, "text": "Receive their response with openness", "duration_seconds": 120},
  {"step": 7, "text": "Thank them for holding space for you", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-00000000001a';

-- Teach Something (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of a skill or knowledge you have", "duration_seconds": 60},
  {"step": 2, "text": "Find someone who might want to learn it", "duration_seconds": 60},
  {"step": 3, "text": "Offer to share what you know", "duration_seconds": 60},
  {"step": 4, "text": "Explain it clearly and patiently", "duration_seconds": 300},
  {"step": 5, "text": "Answer their questions thoughtfully", "duration_seconds": 180},
  {"step": 6, "text": "Notice how teaching deepens your own understanding", "duration_seconds": 90},
  {"step": 7, "text": "Feel good about sharing your gifts", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-00000000001b';

-- Memory Sharing (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of a good memory with a specific person", "duration_seconds": 90},
  {"step": 2, "text": "Call or arrange to meet them", "duration_seconds": 120},
  {"step": 3, "text": "Bring up the memory: Remember when...", "duration_seconds": 60},
  {"step": 4, "text": "Reminisce together about the details", "duration_seconds": 240},
  {"step": 5, "text": "Share what that time meant to you", "duration_seconds": 180},
  {"step": 6, "text": "Invite them to share their memories too", "duration_seconds": 150},
  {"step": 7, "text": "Enjoy this shared moment of connection", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-00000000001c';

-- Undivided Attention (20 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Arrange a face-to-face conversation", "duration_seconds": 120},
  {"step": 2, "text": "Put away all phones and devices", "duration_seconds": 30},
  {"step": 3, "text": "Make eye contact as you talk", "duration_seconds": 180},
  {"step": 4, "text": "Listen without thinking about your response", "duration_seconds": 240},
  {"step": 5, "text": "Notice nonverbal cues - body language, tone", "duration_seconds": 180},
  {"step": 6, "text": "Be fully present with this person", "duration_seconds": 240},
  {"step": 7, "text": "Express appreciation for this quality time", "duration_seconds": 120}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-00000000001d';

-- Community Contribution (20 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Choose a way to benefit your community", "duration_seconds": 60},
  {"step": 2, "text": "Options: pick up litter, help neighbor, volunteer", "duration_seconds": 60},
  {"step": 3, "text": "Begin your contribution", "duration_seconds": 300},
  {"step": 4, "text": "Focus on the good you are creating", "duration_seconds": 300},
  {"step": 5, "text": "Continue for the full time", "duration_seconds": 300},
  {"step": 6, "text": "Appreciate your role in the community", "duration_seconds": 90},
  {"step": 7, "text": "Notice how service affects your wellbeing", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000003-0000-0000-0000-00000000001e';

-- =============================================================================
-- PHYSICAL (Wave 2: 012-01e = 13 templates)
-- =============================================================================

-- Joint Circles (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Stand comfortably with space around you", "duration_seconds": 15},
  {"step": 2, "text": "Rotate your ankles in circles - 10 each way", "duration_seconds": 40},
  {"step": 3, "text": "Circle your knees gently - 10 each direction", "duration_seconds": 40},
  {"step": 4, "text": "Make hip circles - 10 each way", "duration_seconds": 40},
  {"step": 5, "text": "Circle your shoulders - 10 forward, 10 backward", "duration_seconds": 40},
  {"step": 6, "text": "Rotate your wrists - 10 each direction", "duration_seconds": 40},
  {"step": 7, "text": "Gently circle your neck - 5 each way", "duration_seconds": 40},
  {"step": 8, "text": "Stand still and feel the looseness", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000012';

-- Wall Push-Ups (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Stand arm length from a wall", "duration_seconds": 15},
  {"step": 2, "text": "Place hands on wall at shoulder height", "duration_seconds": 15},
  {"step": 3, "text": "Bend elbows to lower chest toward wall", "duration_seconds": 30},
  {"step": 4, "text": "Push back to starting position", "duration_seconds": 20},
  {"step": 5, "text": "Complete 10-15 push-ups slowly", "duration_seconds": 120},
  {"step": 6, "text": "Focus on controlled movement and breathing", "duration_seconds": 60},
  {"step": 7, "text": "Rest and feel your muscles engaged", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000013';

-- Toe Touches (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Stand tall with feet hip-width apart", "duration_seconds": 15},
  {"step": 2, "text": "Slowly bend forward at the waist", "duration_seconds": 30},
  {"step": 3, "text": "Reach toward your toes - do not force", "duration_seconds": 45},
  {"step": 4, "text": "Hold the stretch for 30 seconds", "duration_seconds": 40},
  {"step": 5, "text": "Slowly roll back up", "duration_seconds": 20},
  {"step": 6, "text": "Repeat, going a little deeper each time", "duration_seconds": 120},
  {"step": 7, "text": "Final stretch - breathe into it", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000014';

-- Shoulder Rolls (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Stand or sit with good posture", "duration_seconds": 15},
  {"step": 2, "text": "Roll shoulders forward slowly - 10 times", "duration_seconds": 60},
  {"step": 3, "text": "Pause and feel the difference", "duration_seconds": 20},
  {"step": 4, "text": "Roll shoulders backward slowly - 10 times", "duration_seconds": 60},
  {"step": 5, "text": "Shrug shoulders up high, hold 5 seconds", "duration_seconds": 30},
  {"step": 6, "text": "Release and feel tension melt away", "duration_seconds": 30},
  {"step": 7, "text": "Repeat the shrug 3 more times", "duration_seconds": 60},
  {"step": 8, "text": "Notice your shoulders feeling looser", "duration_seconds": 20}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000015';

-- Dance Party (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Choose your favorite upbeat song", "duration_seconds": 30},
  {"step": 2, "text": "Find a space where you can move freely", "duration_seconds": 20},
  {"step": 3, "text": "Press play and start moving to the beat", "duration_seconds": 180},
  {"step": 4, "text": "Let loose - no one is watching", "duration_seconds": 120},
  {"step": 5, "text": "Try different movements - silly is good!", "duration_seconds": 120},
  {"step": 6, "text": "If another song comes on, keep going", "duration_seconds": 120},
  {"step": 7, "text": "Wind down and catch your breath", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000016';

-- Balance Sequence (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Stand near a wall or chair for support", "duration_seconds": 20},
  {"step": 2, "text": "Stand on your right foot for 30 seconds", "duration_seconds": 40},
  {"step": 3, "text": "Switch to left foot for 30 seconds", "duration_seconds": 40},
  {"step": 4, "text": "Try tree pose: foot on inner calf or thigh", "duration_seconds": 90},
  {"step": 5, "text": "Switch sides in tree pose", "duration_seconds": 90},
  {"step": 6, "text": "Challenge: close your eyes while balancing", "duration_seconds": 90},
  {"step": 7, "text": "Stand on both feet and notice stability", "duration_seconds": 90}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000017';

-- Desk Yoga (10 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Sit tall in your chair", "duration_seconds": 20},
  {"step": 2, "text": "Seated twist: turn right, hold 30 seconds", "duration_seconds": 40},
  {"step": 3, "text": "Seated twist left, hold 30 seconds", "duration_seconds": 40},
  {"step": 4, "text": "Neck stretch: ear to shoulder each side", "duration_seconds": 60},
  {"step": 5, "text": "Wrist circles and finger stretches", "duration_seconds": 60},
  {"step": 6, "text": "Seated forward fold over your legs", "duration_seconds": 90},
  {"step": 7, "text": "Chest opener: clasp hands behind back", "duration_seconds": 60},
  {"step": 8, "text": "Return to neutral and take 3 deep breaths", "duration_seconds": 90}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000018';

-- Jumping Jacks (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find a clear space with room to move", "duration_seconds": 20},
  {"step": 2, "text": "Warm up with marching in place", "duration_seconds": 60},
  {"step": 3, "text": "Do 20 jumping jacks at your pace", "duration_seconds": 90},
  {"step": 4, "text": "Rest and catch your breath", "duration_seconds": 45},
  {"step": 5, "text": "Do another set of 20 jumping jacks", "duration_seconds": 90},
  {"step": 6, "text": "Rest briefly", "duration_seconds": 45},
  {"step": 7, "text": "Final set of 20 jumping jacks", "duration_seconds": 90},
  {"step": 8, "text": "Cool down with slow marching", "duration_seconds": 60},
  {"step": 9, "text": "Notice your heart pumping and energy up", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-000000000019';

-- Restorative Yoga (15 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Gather props: pillows, blankets if available", "duration_seconds": 60},
  {"step": 2, "text": "Come into childs pose and rest 3 minutes", "duration_seconds": 200},
  {"step": 3, "text": "Move to legs up the wall for 4 minutes", "duration_seconds": 260},
  {"step": 4, "text": "Lie flat in supine twist each side 2 minutes", "duration_seconds": 260},
  {"step": 5, "text": "Final rest in savasana", "duration_seconds": 120},
  {"step": 6, "text": "Slowly roll to your side and sit up", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-00000000001a';

-- Walking Intervals (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Start walking at a comfortable pace", "duration_seconds": 60},
  {"step": 2, "text": "Walk briskly for 2 minutes", "duration_seconds": 120},
  {"step": 3, "text": "Slow down to an easy pace for 2 minutes", "duration_seconds": 120},
  {"step": 4, "text": "Speed up again - brisk walk", "duration_seconds": 120},
  {"step": 5, "text": "Slow back down - easy pace", "duration_seconds": 120},
  {"step": 6, "text": "One more brisk interval", "duration_seconds": 120},
  {"step": 7, "text": "Final slow cool-down walk", "duration_seconds": 120},
  {"step": 8, "text": "Stop and notice how your body responded", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-00000000001b';

-- Floor Stretching (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Lie on your back on the floor", "duration_seconds": 30},
  {"step": 2, "text": "Hug knees to chest and rock gently", "duration_seconds": 90},
  {"step": 3, "text": "Stretch hip flexors with figure-four", "duration_seconds": 120},
  {"step": 4, "text": "Extend legs for hamstring stretch each side", "duration_seconds": 120},
  {"step": 5, "text": "Spinal twist to each side", "duration_seconds": 120},
  {"step": 6, "text": "Flip to stomach for chest and back stretch", "duration_seconds": 120},
  {"step": 7, "text": "Return to back for final relaxation", "duration_seconds": 120},
  {"step": 8, "text": "Slowly stand up and feel the difference", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-00000000001c';

-- Active Recovery (20 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Begin with very gentle walking in place", "duration_seconds": 120},
  {"step": 2, "text": "Add gentle arm swings", "duration_seconds": 120},
  {"step": 3, "text": "Move into easy stretching", "duration_seconds": 180},
  {"step": 4, "text": "Do slow swimming motions with your arms", "duration_seconds": 120},
  {"step": 5, "text": "Gentle hip circles and leg swings", "duration_seconds": 180},
  {"step": 6, "text": "Light walking again", "duration_seconds": 180},
  {"step": 7, "text": "Finish with calming stretches", "duration_seconds": 180},
  {"step": 8, "text": "Rest and appreciate recovery", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-00000000001d';

-- Bodyweight Circuit (20 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Warm up with jumping jacks or marching", "duration_seconds": 120},
  {"step": 2, "text": "10-15 squats", "duration_seconds": 90},
  {"step": 3, "text": "10 lunges each leg", "duration_seconds": 120},
  {"step": 4, "text": "10-15 push-ups (modify as needed)", "duration_seconds": 90},
  {"step": 5, "text": "30 second plank", "duration_seconds": 45},
  {"step": 6, "text": "20 mountain climbers", "duration_seconds": 60},
  {"step": 7, "text": "Rest 60 seconds", "duration_seconds": 75},
  {"step": 8, "text": "Repeat the circuit one more time", "duration_seconds": 420},
  {"step": 9, "text": "Cool down stretch", "duration_seconds": 90}
]'::jsonb WHERE id = 'a0000004-0000-0000-0000-00000000001e';

-- =============================================================================
-- CREATIVE (Wave 2: 011-01d = 13 templates)
-- =============================================================================

-- Random Object Story (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Look around and pick any ordinary object", "duration_seconds": 20},
  {"step": 2, "text": "What is its secret life when no one watches?", "duration_seconds": 30},
  {"step": 3, "text": "Imagine its adventures at night", "duration_seconds": 90},
  {"step": 4, "text": "Give it a personality and desires", "duration_seconds": 90},
  {"step": 5, "text": "Write or tell a short story about it", "duration_seconds": 60},
  {"step": 6, "text": "Enjoy the silliness of imagination", "duration_seconds": 20}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000011';

-- Scribble Art (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get paper and a pen or marker", "duration_seconds": 20},
  {"step": 2, "text": "Close your eyes and make a random scribble", "duration_seconds": 30},
  {"step": 3, "text": "Open your eyes and look at the shape", "duration_seconds": 30},
  {"step": 4, "text": "Turn it into something recognizable", "duration_seconds": 150},
  {"step": 5, "text": "Add details to complete your creation", "duration_seconds": 60},
  {"step": 6, "text": "Appreciate what emerged from chaos", "duration_seconds": 20}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000012';

-- Opposite Hand Drawing (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get paper and a pen", "duration_seconds": 20},
  {"step": 2, "text": "Hold the pen in your non-dominant hand", "duration_seconds": 15},
  {"step": 3, "text": "Choose something simple to draw", "duration_seconds": 20},
  {"step": 4, "text": "Draw it slowly with your weak hand", "duration_seconds": 180},
  {"step": 5, "text": "Embrace the imperfection - it is charming", "duration_seconds": 45},
  {"step": 6, "text": "Notice how focusing changes with difficulty", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000013';

-- Sound Story (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Close your eyes and listen to surrounding sounds", "duration_seconds": 45},
  {"step": 2, "text": "Identify 3-5 distinct sounds", "duration_seconds": 45},
  {"step": 3, "text": "Create a narrative connecting them all", "duration_seconds": 120},
  {"step": 4, "text": "Who made that sound? Why?", "duration_seconds": 60},
  {"step": 5, "text": "Weave a story that explains everything", "duration_seconds": 45},
  {"step": 6, "text": "Enjoy your creative interpretation of sound", "duration_seconds": 20}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000014';

-- Six Word Memoir (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think about a period of your life", "duration_seconds": 60},
  {"step": 2, "text": "Summarize it in exactly six words", "duration_seconds": 120},
  {"step": 3, "text": "Read it aloud - does it capture the feeling?", "duration_seconds": 30},
  {"step": 4, "text": "Try another version with different words", "duration_seconds": 120},
  {"step": 5, "text": "Write 2-3 more six word memoirs", "duration_seconds": 180},
  {"step": 6, "text": "Choose your favorite and save it", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000015';

-- Found Poetry (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Find any text: article, book, menu", "duration_seconds": 60},
  {"step": 2, "text": "Read through and mark interesting words", "duration_seconds": 120},
  {"step": 3, "text": "Select 10-20 words that speak to you", "duration_seconds": 120},
  {"step": 4, "text": "Arrange them into a poem", "duration_seconds": 180},
  {"step": 5, "text": "Adjust the order until it feels right", "duration_seconds": 60},
  {"step": 6, "text": "Read your found poem aloud", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000016';

-- Emotion Colors (10 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get paper and colored pens or pencils", "duration_seconds": 30},
  {"step": 2, "text": "Think about how you feel right now", "duration_seconds": 45},
  {"step": 3, "text": "Assign a color to your primary emotion", "duration_seconds": 45},
  {"step": 4, "text": "What secondary emotions are present? Colors?", "duration_seconds": 60},
  {"step": 5, "text": "Create an abstract representation of your inner state", "duration_seconds": 240},
  {"step": 6, "text": "Use shapes, lines, and colors to express feelings", "duration_seconds": 120},
  {"step": 7, "text": "Step back and observe your emotional landscape", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000017';

-- Reimagine a Song (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of a song you know well", "duration_seconds": 45},
  {"step": 2, "text": "Imagine it in a completely different genre", "duration_seconds": 60},
  {"step": 3, "text": "A rock song as jazz? A pop song as opera?", "duration_seconds": 60},
  {"step": 4, "text": "How would the tempo change?", "duration_seconds": 90},
  {"step": 5, "text": "What instruments would be used?", "duration_seconds": 90},
  {"step": 6, "text": "Hum or imagine the new version", "duration_seconds": 180},
  {"step": 7, "text": "Appreciate your creative reimagining", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000018';

-- Dream Journal (15 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get paper and settle somewhere comfortable", "duration_seconds": 30},
  {"step": 2, "text": "Think of a dream you remember", "duration_seconds": 60},
  {"step": 3, "text": "Or create a dream you wish you had", "duration_seconds": 60},
  {"step": 4, "text": "Write it in vivid, sensory detail", "duration_seconds": 300},
  {"step": 5, "text": "Describe colors, sounds, feelings, textures", "duration_seconds": 180},
  {"step": 6, "text": "Add any symbols or meanings you sense", "duration_seconds": 120},
  {"step": 7, "text": "Read your dream story and wonder about it", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-000000000019';

-- Character Creation (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get paper to create a fictional character", "duration_seconds": 30},
  {"step": 2, "text": "Give them a name and basic appearance", "duration_seconds": 90},
  {"step": 3, "text": "What is their personality like?", "duration_seconds": 120},
  {"step": 4, "text": "What are their biggest fears?", "duration_seconds": 90},
  {"step": 5, "text": "What are their dreams and desires?", "duration_seconds": 90},
  {"step": 6, "text": "Give them a secret no one else knows", "duration_seconds": 120},
  {"step": 7, "text": "Write a paragraph about their typical day", "duration_seconds": 240},
  {"step": 8, "text": "Your character is alive in your imagination", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-00000000001a';

-- Texture Rubbing Art (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Gather paper and crayon or pencil", "duration_seconds": 30},
  {"step": 2, "text": "Find interesting textures around you", "duration_seconds": 90},
  {"step": 3, "text": "Place paper over a texture and rub gently", "duration_seconds": 120},
  {"step": 4, "text": "Watch the pattern emerge on paper", "duration_seconds": 60},
  {"step": 5, "text": "Find 4-5 more interesting textures", "duration_seconds": 300},
  {"step": 6, "text": "Create a collection of texture rubbings", "duration_seconds": 180},
  {"step": 7, "text": "Arrange them into an artistic composition", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-00000000001b';

-- Worldbuilding (20 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get paper to create an imaginary place", "duration_seconds": 30},
  {"step": 2, "text": "Name your world and describe its geography", "duration_seconds": 180},
  {"step": 3, "text": "Who lives there? Describe the inhabitants", "duration_seconds": 180},
  {"step": 4, "text": "What are the rules of this world?", "duration_seconds": 150},
  {"step": 5, "text": "What is the culture like?", "duration_seconds": 150},
  {"step": 6, "text": "Draw a rough map if you want", "duration_seconds": 180},
  {"step": 7, "text": "Add one unique feature that makes it special", "duration_seconds": 120},
  {"step": 8, "text": "Your world exists now in imagination", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-00000000001c';

-- Personal Mythology (20 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get paper for a creative writing exercise", "duration_seconds": 30},
  {"step": 2, "text": "Think of a challenge you have overcome", "duration_seconds": 90},
  {"step": 3, "text": "Retell it as an ancient myth or legend", "duration_seconds": 300},
  {"step": 4, "text": "You are the hero on a quest", "duration_seconds": 180},
  {"step": 5, "text": "What monsters or obstacles did you face?", "duration_seconds": 180},
  {"step": 6, "text": "What magic or help did you receive?", "duration_seconds": 150},
  {"step": 7, "text": "How did you triumph in the end?", "duration_seconds": 150},
  {"step": 8, "text": "Read your myth and honor your journey", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000005-0000-0000-0000-00000000001d';

-- =============================================================================
-- REFLECTION (Wave 2: 012-01e = 13 templates)
-- =============================================================================

-- One Word Check-In (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Pause and take 3 deep breaths", "duration_seconds": 30},
  {"step": 2, "text": "Ask yourself: How do I feel right now?", "duration_seconds": 30},
  {"step": 3, "text": "Choose one word that describes it", "duration_seconds": 45},
  {"step": 4, "text": "Sit with that word for a moment", "duration_seconds": 60},
  {"step": 5, "text": "Why did you choose this word?", "duration_seconds": 90},
  {"step": 6, "text": "What does this word tell you about your needs?", "duration_seconds": 60}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000012';

-- Belief Examination (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Identify one belief you hold about yourself", "duration_seconds": 60},
  {"step": 2, "text": "Where did this belief come from?", "duration_seconds": 60},
  {"step": 3, "text": "Is this belief actually true?", "duration_seconds": 60},
  {"step": 4, "text": "Is this belief serving you well?", "duration_seconds": 60},
  {"step": 5, "text": "If not, what belief would serve you better?", "duration_seconds": 60},
  {"step": 6, "text": "Try on the new belief for a moment", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000013';

-- Priority Check (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Write your top 3 priorities in life", "duration_seconds": 60},
  {"step": 2, "text": "Think about how you spent today", "duration_seconds": 60},
  {"step": 3, "text": "Did your time align with priority 1?", "duration_seconds": 45},
  {"step": 4, "text": "What about priority 2 and 3?", "duration_seconds": 45},
  {"step": 5, "text": "Note any gaps between priorities and actions", "duration_seconds": 60},
  {"step": 6, "text": "What one change could improve alignment?", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000014';

-- Needs Assessment (5 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Sit quietly and tune inward", "duration_seconds": 30},
  {"step": 2, "text": "Ask: What do I need physically right now?", "duration_seconds": 60},
  {"step": 3, "text": "What do I need emotionally?", "duration_seconds": 60},
  {"step": 4, "text": "What do I need mentally?", "duration_seconds": 60},
  {"step": 5, "text": "What do I need spiritually or soulfully?", "duration_seconds": 60},
  {"step": 6, "text": "Choose one need to address today", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000015';

-- Pattern Recognition (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of a recurring challenge in your life", "duration_seconds": 90},
  {"step": 2, "text": "When does it typically show up?", "duration_seconds": 90},
  {"step": 3, "text": "What triggers it?", "duration_seconds": 90},
  {"step": 4, "text": "How do you usually respond?", "duration_seconds": 90},
  {"step": 5, "text": "What pattern do you notice?", "duration_seconds": 90},
  {"step": 6, "text": "What could interrupt this pattern?", "duration_seconds": 90},
  {"step": 7, "text": "Commit to trying one new response next time", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000016';

-- Joy Mapping (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "List activities that bring you genuine joy", "duration_seconds": 150},
  {"step": 2, "text": "For each one, note when you last did it", "duration_seconds": 120},
  {"step": 3, "text": "Notice which have been neglected", "duration_seconds": 60},
  {"step": 4, "text": "Why have these joys been put aside?", "duration_seconds": 90},
  {"step": 5, "text": "Choose one to do in the next few days", "duration_seconds": 60},
  {"step": 6, "text": "Schedule it now if possible", "duration_seconds": 60},
  {"step": 7, "text": "Commit to regular joy maintenance", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000017';

-- Shadow Work Light (10 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of a trait in others that really bothers you", "duration_seconds": 90},
  {"step": 2, "text": "Name it clearly: is it selfishness? Weakness?", "duration_seconds": 60},
  {"step": 3, "text": "Now look honestly: do you have any version of this?", "duration_seconds": 120},
  {"step": 4, "text": "When does this trait show up in you?", "duration_seconds": 90},
  {"step": 5, "text": "Why might it be hard to acknowledge?", "duration_seconds": 90},
  {"step": 6, "text": "Can you accept this part of yourself?", "duration_seconds": 90},
  {"step": 7, "text": "Integration brings peace", "duration_seconds": 30}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000018';

-- Boundary Review (10 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think about your personal boundaries", "duration_seconds": 60},
  {"step": 2, "text": "Where have you maintained them well recently?", "duration_seconds": 120},
  {"step": 3, "text": "Acknowledge yourself for those successes", "duration_seconds": 60},
  {"step": 4, "text": "Where have boundaries been crossed?", "duration_seconds": 120},
  {"step": 5, "text": "What made it hard to enforce them?", "duration_seconds": 90},
  {"step": 6, "text": "What boundary needs strengthening most?", "duration_seconds": 90},
  {"step": 7, "text": "Plan one step to reinforce that boundary", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-000000000019';

-- Values Clarification (15 min - PREMIUM)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Write down your top 5 values", "duration_seconds": 90},
  {"step": 2, "text": "For each value, write why it matters to you", "duration_seconds": 180},
  {"step": 3, "text": "How did you honor value 1 recently?", "duration_seconds": 90},
  {"step": 4, "text": "How could you honor it more?", "duration_seconds": 90},
  {"step": 5, "text": "Repeat for each remaining value", "duration_seconds": 300},
  {"step": 6, "text": "Notice which values need more attention", "duration_seconds": 90},
  {"step": 7, "text": "Commit to one values-aligned action this week", "duration_seconds": 45}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-00000000001a';

-- Inner Critic Dialogue (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get paper for a written dialogue", "duration_seconds": 30},
  {"step": 2, "text": "Write what your inner critic often says", "duration_seconds": 150},
  {"step": 3, "text": "Now write a response from your wise self", "duration_seconds": 150},
  {"step": 4, "text": "Let the critic respond", "duration_seconds": 120},
  {"step": 5, "text": "Let your wise self reply with compassion", "duration_seconds": 150},
  {"step": 6, "text": "Continue until the critic softens", "duration_seconds": 120},
  {"step": 7, "text": "End with your wise self having the final word", "duration_seconds": 90}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-00000000001b';

-- Regret Processing (15 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Think of something you regret", "duration_seconds": 60},
  {"step": 2, "text": "Write about what happened honestly", "duration_seconds": 180},
  {"step": 3, "text": "What would you do differently now?", "duration_seconds": 120},
  {"step": 4, "text": "What did you learn from this experience?", "duration_seconds": 120},
  {"step": 5, "text": "How has this shaped who you are today?", "duration_seconds": 150},
  {"step": 6, "text": "Can you forgive yourself?", "duration_seconds": 90},
  {"step": 7, "text": "Write a statement of self-forgiveness", "duration_seconds": 90}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-00000000001c';

-- Life Chapters (20 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get paper for a reflective exercise", "duration_seconds": 30},
  {"step": 2, "text": "Divide your life into chapters", "duration_seconds": 120},
  {"step": 3, "text": "Give each chapter a title", "duration_seconds": 180},
  {"step": 4, "text": "Write a brief summary of each", "duration_seconds": 360},
  {"step": 5, "text": "What chapter are you in now?", "duration_seconds": 90},
  {"step": 6, "text": "What do you want this chapter to be about?", "duration_seconds": 120},
  {"step": 7, "text": "What title would you give the next chapter?", "duration_seconds": 90}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-00000000001d';

-- Ideal Self Portrait (20 min)
UPDATE quest_templates SET instructions = '[
  {"step": 1, "text": "Get comfortable for a visualization exercise", "duration_seconds": 30},
  {"step": 2, "text": "Imagine your ideal self in vivid detail", "duration_seconds": 150},
  {"step": 3, "text": "What habits does your ideal self have?", "duration_seconds": 150},
  {"step": 4, "text": "What relationships do they maintain?", "duration_seconds": 150},
  {"step": 5, "text": "What have they achieved?", "duration_seconds": 150},
  {"step": 6, "text": "What is their mindset and attitude?", "duration_seconds": 150},
  {"step": 7, "text": "Write a detailed description", "duration_seconds": 180},
  {"step": 8, "text": "What small step today moves you toward this?", "duration_seconds": 90}
]'::jsonb WHERE id = 'a0000006-0000-0000-0000-00000000001e';
