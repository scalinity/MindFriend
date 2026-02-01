-- Quest Templates Expansion Wave 2
-- Adds 78 more templates to bring total from 100 to 178
-- ~15% premium (12 new premium templates)

INSERT INTO quest_templates (id, title, description, category, estimated_minutes, xp_reward, is_premium, is_active)
VALUES
  -- ============================================
  -- MINDFULNESS (13 new: 012-024)
  -- ============================================

  -- 5 min / 50 XP
  ('a0000001-0000-0000-0000-000000000012', 'Grounding Touch', 'Place both hands on a solid surface. Feel its temperature, texture, and stability. Let it anchor you to the present.', 'mindfulness', 5, 50, false, true),
  ('a0000001-0000-0000-0000-000000000013', 'Cloud Watching', 'Look up at the sky for 5 minutes. Watch clouds drift by without trying to identify shapes. Just observe movement.', 'mindfulness', 5, 50, false, true),
  ('a0000001-0000-0000-0000-000000000014', 'Finger Breathing', 'Trace your fingers slowly. Breathe in as you trace up, breathe out as you trace down. Complete both hands.', 'mindfulness', 5, 50, false, true),
  ('a0000001-0000-0000-0000-000000000015', 'Silent Sitting', 'Sit in complete stillness for 5 minutes. No phone, no reading. Just be present with whatever arises.', 'mindfulness', 5, 50, false, true),

  -- 10 min / 75 XP
  ('a0000001-0000-0000-0000-000000000016', 'Candle Gazing', 'Light a candle and focus on the flame. When your mind wanders, gently return your attention to the light.', 'mindfulness', 10, 75, false, true),
  ('a0000001-0000-0000-0000-000000000017', 'Compassion Meditation', 'Bring to mind someone who is struggling. Send them wishes for peace, healing, and ease. Feel compassion in your heart.', 'mindfulness', 10, 75, false, true),
  ('a0000001-0000-0000-0000-000000000018', 'Texture Exploration', 'Gather 5 objects with different textures. Close your eyes and explore each one thoroughly with your fingertips.', 'mindfulness', 10, 75, false, true),
  ('a0000001-0000-0000-0000-000000000019', 'Breath Awareness', 'Simply observe your natural breath without trying to change it. Notice the rhythm, depth, and temperature.', 'mindfulness', 10, 75, false, true),

  -- 15 min / 75 XP (2 premium)
  ('a0000001-0000-0000-0000-00000000001a', 'Forest Bathing', 'If possible, spend time among trees. If indoors, visualize a forest. Engage all senses with the natural world.', 'mindfulness', 15, 75, true, true),
  ('a0000001-0000-0000-0000-00000000001b', 'Mindful Cleaning', 'Choose one small cleaning task. Do it slowly and deliberately, focusing entirely on each motion and sensation.', 'mindfulness', 15, 75, false, true),
  ('a0000001-0000-0000-0000-00000000001c', 'Gratitude Body Scan', 'Scan through your body slowly, expressing gratitude for each part and its function in your life.', 'mindfulness', 15, 75, true, true),

  -- 20 min / 100 XP
  ('a0000001-0000-0000-0000-00000000001d', 'Silence Practice', 'Spend 20 minutes in complete silence. No music, no talking, no media. Simply be with the quiet.', 'mindfulness', 20, 100, false, true),
  ('a0000001-0000-0000-0000-00000000001e', 'Mindful Crafting', 'Engage in a simple craft mindfully: folding paper, arranging objects, or organizing something. Focus on each movement.', 'mindfulness', 20, 100, false, true),

  -- ============================================
  -- GRATITUDE (13 new: 011-023)
  -- ============================================

  -- 5 min / 50 XP
  ('a0000002-0000-0000-0000-000000000011', 'Sensory Gratitude', 'List one thing you are grateful for that you can see, hear, touch, smell, and taste right now.', 'gratitude', 5, 50, false, true),
  ('a0000002-0000-0000-0000-000000000012', 'Hardship Appreciation', 'Think of a past difficulty. Write one way it made you stronger or taught you something valuable.', 'gratitude', 5, 50, false, true),
  ('a0000002-0000-0000-0000-000000000013', 'Ordinary Magic', 'Find something ordinary you usually ignore. Spend time appreciating its existence and purpose.', 'gratitude', 5, 50, false, true),
  ('a0000002-0000-0000-0000-000000000014', 'Morning Thanks', 'Before getting out of bed tomorrow, think of three things you are looking forward to today.', 'gratitude', 5, 50, false, true),

  -- 10 min / 75 XP (1 premium)
  ('a0000002-0000-0000-0000-000000000015', 'Gratitude Walk', 'Walk slowly and find 10 things to be grateful for along the way. Say a silent thank you for each.', 'gratitude', 10, 75, false, true),
  ('a0000002-0000-0000-0000-000000000016', 'Ancestor Appreciation', 'Think about someone from a previous generation. Write what you appreciate about their life and sacrifices.', 'gratitude', 10, 75, false, true),
  ('a0000002-0000-0000-0000-000000000017', 'Service Gratitude', 'Think of people who serve your community: mail carriers, cleaners, drivers. Write appreciation for their work.', 'gratitude', 10, 75, false, true),
  ('a0000002-0000-0000-0000-000000000018', 'Health Inventory', 'List aspects of your health you take for granted. Express gratitude for each working system in your body.', 'gratitude', 10, 75, true, true),

  -- 15 min / 75 XP
  ('a0000002-0000-0000-0000-000000000019', 'Gratitude Collage', 'Create a quick collage of images representing things you are grateful for. Digital or cut from magazines.', 'gratitude', 15, 75, false, true),
  ('a0000002-0000-0000-0000-00000000001a', 'Timeline of Blessings', 'Draw a timeline of your life. Mark the key blessings and good things that happened at each stage.', 'gratitude', 15, 75, false, true),
  ('a0000002-0000-0000-0000-00000000001b', 'Gratitude Interview', 'Ask someone close to you what they are grateful for today. Listen fully and share yours too.', 'gratitude', 15, 75, false, true),

  -- 20 min / 100 XP (1 premium)
  ('a0000002-0000-0000-0000-00000000001c', 'Gratitude Meditation Journey', 'Close your eyes and mentally visit places and people you are grateful for. Spend time with each one.', 'gratitude', 20, 100, true, true),
  ('a0000002-0000-0000-0000-00000000001d', 'Thank You Letter Send', 'Write and actually send a thank you letter or message to someone who has impacted your life.', 'gratitude', 20, 100, false, true),

  -- ============================================
  -- SOCIAL (13 new: 012-024)
  -- ============================================

  -- 5 min / 50 XP
  ('a0000003-0000-0000-0000-000000000012', 'Genuine Interest', 'Ask someone a question about their life and actually listen to the answer. Be curious.', 'social', 5, 50, false, true),
  ('a0000003-0000-0000-0000-000000000013', 'Encourage Someone', 'Send a message of encouragement to someone facing a challenge. Be specific about their strengths.', 'social', 5, 50, false, true),
  ('a0000003-0000-0000-0000-000000000014', 'Reconnect Thought', 'Think of someone you have lost touch with. Send them a brief message just to say hello.', 'social', 5, 50, false, true),
  ('a0000003-0000-0000-0000-000000000015', 'Pay It Forward', 'Do a small anonymous act of kindness for a stranger. Hold a door, pay for coffee, leave a kind note.', 'social', 5, 50, false, true),

  -- 10 min / 75 XP (1 premium)
  ('a0000003-0000-0000-0000-000000000016', 'Empathy Practice', 'Think of someone whose views differ from yours. Try to understand their perspective without judgment.', 'social', 10, 75, false, true),
  ('a0000003-0000-0000-0000-000000000017', 'Celebration Message', 'Send a message celebrating someone else''s recent achievement, big or small.', 'social', 10, 75, false, true),
  ('a0000003-0000-0000-0000-000000000018', 'Forgiveness Practice', 'Think of someone who wronged you. Silently wish them well and release resentment. This is for your peace.', 'social', 10, 75, true, true),
  ('a0000003-0000-0000-0000-000000000019', 'Ask for Help', 'Reach out and ask someone for help with something small. Practice receiving support gracefully.', 'social', 10, 75, false, true),

  -- 15 min / 75 XP (1 premium)
  ('a0000003-0000-0000-0000-00000000001a', 'Vulnerability Share', 'Share something honest about how you are really feeling with someone you trust.', 'social', 15, 75, true, true),
  ('a0000003-0000-0000-0000-00000000001b', 'Teach Something', 'Share a skill or piece of knowledge with someone. Teaching deepens our own understanding.', 'social', 15, 75, false, true),
  ('a0000003-0000-0000-0000-00000000001c', 'Memory Sharing', 'Call or meet someone to reminisce about good times you shared. Relive the joy together.', 'social', 15, 75, false, true),

  -- 20 min / 100 XP
  ('a0000003-0000-0000-0000-00000000001d', 'Undivided Attention', 'Have a face-to-face conversation with someone. No phones, no distractions. Just be fully present.', 'social', 20, 100, false, true),
  ('a0000003-0000-0000-0000-00000000001e', 'Community Contribution', 'Do something that benefits your community: pick up litter, help a neighbor, volunteer briefly.', 'social', 20, 100, false, true),

  -- ============================================
  -- PHYSICAL (13 new: 012-024)
  -- ============================================

  -- 5 min / 50 XP
  ('a0000004-0000-0000-0000-000000000012', 'Joint Circles', 'Rotate all your major joints: ankles, knees, hips, shoulders, wrists, neck. Move slowly and deliberately.', 'physical', 5, 50, false, true),
  ('a0000004-0000-0000-0000-000000000013', 'Wall Push-Ups', 'Do 10-15 wall push-ups. Focus on controlled movement and proper breathing.', 'physical', 5, 50, false, true),
  ('a0000004-0000-0000-0000-000000000014', 'Toe Touches', 'Gently stretch toward your toes, holding for 30 seconds. Repeat 3-5 times, going a little deeper each time.', 'physical', 5, 50, false, true),
  ('a0000004-0000-0000-0000-000000000015', 'Shoulder Rolls', 'Roll your shoulders forward 10 times, then backward 10 times. Release tension in your upper body.', 'physical', 5, 50, false, true),

  -- 10 min / 75 XP (1 premium)
  ('a0000004-0000-0000-0000-000000000016', 'Dance Party', 'Put on your favorite upbeat song and dance like nobody is watching. Let your body move freely.', 'physical', 10, 75, false, true),
  ('a0000004-0000-0000-0000-000000000017', 'Balance Sequence', 'Practice standing on each foot, then try tree pose. Challenge your balance with eyes closed.', 'physical', 10, 75, false, true),
  ('a0000004-0000-0000-0000-000000000018', 'Desk Yoga', 'Do a sequence of stretches that can be done at or near your desk: seated twists, neck stretches, wrist rolls.', 'physical', 10, 75, true, true),
  ('a0000004-0000-0000-0000-000000000019', 'Jumping Jacks', 'Do 3 sets of 20 jumping jacks with short rests between. Get your heart pumping.', 'physical', 10, 75, false, true),

  -- 15 min / 75 XP (1 premium)
  ('a0000004-0000-0000-0000-00000000001a', 'Restorative Yoga', 'Hold 3-4 gentle yoga poses for extended time: child''s pose, legs up wall, supine twist.', 'physical', 15, 75, true, true),
  ('a0000004-0000-0000-0000-00000000001b', 'Walking Intervals', 'Alternate between brisk walking and slow walking every 2 minutes. Notice how your body responds.', 'physical', 15, 75, false, true),
  ('a0000004-0000-0000-0000-00000000001c', 'Floor Stretching', 'Lie on the floor and do a full stretching sequence: hip flexors, hamstrings, back, chest.', 'physical', 15, 75, false, true),

  -- 20 min / 100 XP
  ('a0000004-0000-0000-0000-00000000001d', 'Active Recovery', 'Do very light movement: gentle walking, easy stretching, slow swimming motions. Recovery is essential.', 'physical', 20, 100, false, true),
  ('a0000004-0000-0000-0000-00000000001e', 'Bodyweight Circuit', 'Complete a circuit: squats, lunges, push-ups, planks, mountain climbers. Rest as needed.', 'physical', 20, 100, false, true),

  -- ============================================
  -- CREATIVE (13 new: 011-023)
  -- ============================================

  -- 5 min / 50 XP
  ('a0000005-0000-0000-0000-000000000011', 'Random Object Story', 'Pick any object nearby. Make up a short story about its secret life when no one is watching.', 'creative', 5, 50, false, true),
  ('a0000005-0000-0000-0000-000000000012', 'Scribble Art', 'Make a random scribble on paper. Then turn it into something recognizable by adding details.', 'creative', 5, 50, false, true),
  ('a0000005-0000-0000-0000-000000000013', 'Opposite Hand Drawing', 'Draw something simple using your non-dominant hand. Embrace the imperfection.', 'creative', 5, 50, false, true),
  ('a0000005-0000-0000-0000-000000000014', 'Sound Story', 'Listen to the sounds around you. Create a narrative that connects them all into one story.', 'creative', 5, 50, false, true),

  -- 10 min / 75 XP (1 premium)
  ('a0000005-0000-0000-0000-000000000015', 'Six Word Memoir', 'Summarize a period of your life in exactly six words. Try writing several versions.', 'creative', 10, 75, false, true),
  ('a0000005-0000-0000-0000-000000000016', 'Found Poetry', 'Take any text and create a poem by selecting and rearranging words from it.', 'creative', 10, 75, false, true),
  ('a0000005-0000-0000-0000-000000000017', 'Emotion Colors', 'Assign colors to different emotions you are feeling. Create an abstract representation of your inner state.', 'creative', 10, 75, true, true),
  ('a0000005-0000-0000-0000-000000000018', 'Reimagine a Song', 'Take a song you know and imagine it in a completely different genre. How would it sound?', 'creative', 10, 75, false, true),

  -- 15 min / 75 XP (1 premium)
  ('a0000005-0000-0000-0000-000000000019', 'Dream Journal', 'Write about a dream you remember, or create a dream you wish you had. Add vivid details.', 'creative', 15, 75, true, true),
  ('a0000005-0000-0000-0000-00000000001a', 'Character Creation', 'Invent a detailed character: their appearance, personality, fears, dreams, and a secret.', 'creative', 15, 75, false, true),
  ('a0000005-0000-0000-0000-00000000001b', 'Texture Rubbing Art', 'Find interesting textures and create art by placing paper over them and rubbing with crayon or pencil.', 'creative', 15, 75, false, true),

  -- 20 min / 100 XP (1 premium)
  ('a0000005-0000-0000-0000-00000000001c', 'Worldbuilding', 'Create an imaginary place: its geography, inhabitants, rules, and culture. Draw a map if you like.', 'creative', 20, 100, true, true),
  ('a0000005-0000-0000-0000-00000000001d', 'Personal Mythology', 'Write a myth or legend that explains something about your life, told as if you were an ancient hero.', 'creative', 20, 100, false, true),

  -- ============================================
  -- REFLECTION (13 new: 012-024)
  -- ============================================

  -- 5 min / 50 XP
  ('a0000006-0000-0000-0000-000000000012', 'One Word Check-In', 'Choose one word that describes how you feel right now. Sit with that word and explore why you chose it.', 'reflection', 5, 50, false, true),
  ('a0000006-0000-0000-0000-000000000013', 'Belief Examination', 'Identify one belief you hold. Ask: Where did this belief come from? Is it still serving me?', 'reflection', 5, 50, false, true),
  ('a0000006-0000-0000-0000-000000000014', 'Priority Check', 'List your top 3 priorities. Does how you spent today align with them? Note any gaps.', 'reflection', 5, 50, false, true),
  ('a0000006-0000-0000-0000-000000000015', 'Needs Assessment', 'Ask yourself: What do I need right now? Physical, emotional, mental, or spiritual?', 'reflection', 5, 50, false, true),

  -- 10 min / 75 XP (1 premium)
  ('a0000006-0000-0000-0000-000000000016', 'Pattern Recognition', 'Think about a recurring challenge in your life. What patterns do you notice? What triggers it?', 'reflection', 10, 75, false, true),
  ('a0000006-0000-0000-0000-000000000017', 'Joy Mapping', 'List activities that bring you joy. When did you last do each? Plan to do one soon.', 'reflection', 10, 75, false, true),
  ('a0000006-0000-0000-0000-000000000018', 'Shadow Work Light', 'Identify a trait in others that bothers you. Reflect on whether you might have a version of this trait.', 'reflection', 10, 75, true, true),
  ('a0000006-0000-0000-0000-000000000019', 'Boundary Review', 'Think about your boundaries. Where have you maintained them well? Where do they need strengthening?', 'reflection', 10, 75, false, true),

  -- 15 min / 75 XP (1 premium)
  ('a0000006-0000-0000-0000-00000000001a', 'Values Clarification', 'List your top 5 values. For each, write one way you honored it recently and one way to honor it more.', 'reflection', 15, 75, true, true),
  ('a0000006-0000-0000-0000-00000000001b', 'Inner Critic Dialogue', 'Write a dialogue between yourself and your inner critic. Give your wise self the final word.', 'reflection', 15, 75, false, true),
  ('a0000006-0000-0000-0000-00000000001c', 'Regret Processing', 'Write about something you regret. Then write what you learned and how it made you who you are today.', 'reflection', 15, 75, false, true),

  -- 20 min / 100 XP
  ('a0000006-0000-0000-0000-00000000001d', 'Life Chapters', 'Divide your life into chapters. Give each chapter a title and a brief summary. What chapter are you in now?', 'reflection', 20, 100, false, true),
  ('a0000006-0000-0000-0000-00000000001e', 'Ideal Self Portrait', 'Describe your ideal self in detail: habits, relationships, achievements, mindset. What small step can you take today?', 'reflection', 20, 100, false, true)

ON CONFLICT (id) DO NOTHING;
