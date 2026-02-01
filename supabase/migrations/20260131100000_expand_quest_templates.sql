-- Expand quest templates for production-level variety
-- Adds 78 new templates to bring total from 22 to 100
-- ~15% premium (15 templates)

INSERT INTO quest_templates (id, title, description, category, estimated_minutes, xp_reward, is_premium, is_active)
VALUES
  -- ============================================
  -- MINDFULNESS (12 new: 006-017)
  -- ============================================

  -- 5 min / 50 XP
  ('a0000001-0000-0000-0000-000000000006', 'Breath Counting', 'Count your breaths from 1 to 10. When you lose count or get distracted, gently return to 1 and begin again.', 'mindfulness', 5, 50, false, true),
  ('a0000001-0000-0000-0000-000000000007', 'Sensory Check-In', 'Notice 5 things you can see, 4 you can hear, 3 you can feel, 2 you can smell, and 1 you can taste.', 'mindfulness', 5, 50, false, true),
  ('a0000001-0000-0000-0000-000000000008', 'Mindful Sip', 'Prepare a cup of tea or water. Drink it slowly with complete attention, noticing temperature, taste, and sensation.', 'mindfulness', 5, 50, false, true),
  ('a0000001-0000-0000-0000-000000000009', 'One-Minute Reset', 'Close your eyes and take 12 slow, deep breaths. Let each exhale release any tension you are holding.', 'mindfulness', 5, 50, false, true),

  -- 10 min / 75 XP
  ('a0000001-0000-0000-0000-00000000000a', 'Loving Kindness', 'Send well-wishes to yourself, then someone you love, then a neutral person, then all beings everywhere.', 'mindfulness', 10, 75, false, true),
  ('a0000001-0000-0000-0000-00000000000b', 'Sound Awareness', 'Sit quietly and listen to all sounds around you without labeling or judging them. Just observe.', 'mindfulness', 10, 75, false, true),
  ('a0000001-0000-0000-0000-00000000000c', 'Present Moment Anchor', 'Set a timer and return your attention to your breath each time it wanders. Notice thoughts without following them.', 'mindfulness', 10, 75, false, true),
  ('a0000001-0000-0000-0000-00000000000d', 'Mindful Eating', 'Eat a small snack with full attention. Notice colors, textures, flavors, and the experience of chewing and swallowing.', 'mindfulness', 10, 75, false, true),

  -- 15 min / 75 XP (2 premium)
  ('a0000001-0000-0000-0000-00000000000e', 'Visualization Journey', 'Close your eyes and imagine yourself in a peaceful place. Explore it with all your senses, letting calm wash over you.', 'mindfulness', 15, 75, true, true),
  ('a0000001-0000-0000-0000-00000000000f', 'Nature Connection', 'Go outside or look out a window. Observe nature using all your senses without rushing to name or analyze what you see.', 'mindfulness', 15, 75, false, true),
  ('a0000001-0000-0000-0000-000000000010', 'Body Gratitude Scan', 'Slowly scan from head to toe, pausing to thank each body part for what it does for you each day.', 'mindfulness', 15, 75, true, true),

  -- 20 min / 100 XP (1 premium)
  ('a0000001-0000-0000-0000-000000000011', 'Deep Meditation Session', 'Find a quiet space and sit in silent meditation. Focus on your breath and let thoughts pass like clouds.', 'mindfulness', 20, 100, true, true),

  -- ============================================
  -- GRATITUDE (13 new: 004-016)
  -- ============================================

  -- 5 min / 50 XP
  ('a0000002-0000-0000-0000-000000000004', 'Photo Gratitude', 'Find a photo that brings you joy. Spend time looking at it and reflecting on why it means so much to you.', 'gratitude', 5, 50, false, true),
  ('a0000002-0000-0000-0000-000000000005', 'Gratitude Snapshot', 'Write one sentence describing something you appreciate about this exact moment right now.', 'gratitude', 5, 50, false, true),
  ('a0000002-0000-0000-0000-000000000006', 'Small Wins List', 'List 3 small things that went right today, no matter how minor. Celebrate each one.', 'gratitude', 5, 50, false, true),
  ('a0000002-0000-0000-0000-000000000007', 'Appreciation Breath', 'With each inhale, think of something you appreciate. With each exhale, let go of something that troubles you.', 'gratitude', 5, 50, false, true),

  -- 10 min / 75 XP (1 premium)
  ('a0000002-0000-0000-0000-000000000008', 'Gratitude Letter Draft', 'Start writing a thank-you letter to someone who has positively impacted your life. You can finish it later.', 'gratitude', 10, 75, false, true),
  ('a0000002-0000-0000-0000-000000000009', 'Relationship Appreciation', 'Choose one relationship in your life. Write about three specific gifts that person has given you.', 'gratitude', 10, 75, false, true),
  ('a0000002-0000-0000-0000-00000000000a', 'Memory Lane', 'Recall a happy memory in vivid detail. What did you see, hear, and feel? Let yourself smile as you remember.', 'gratitude', 10, 75, false, true),
  ('a0000002-0000-0000-0000-00000000000b', 'Challenge Reframe', 'Think of a recent challenge. Write down three hidden gifts or lessons it has brought you.', 'gratitude', 10, 75, false, true),
  ('a0000002-0000-0000-0000-00000000000c', 'Body Appreciation', 'Write a thank-you note to your body. Appreciate what it does for you every single day.', 'gratitude', 10, 75, true, true),

  -- 15 min / 75 XP (1 premium)
  ('a0000002-0000-0000-0000-00000000000d', 'Gratitude Meditation', 'Sit quietly and bring to mind people, experiences, and things you are grateful for. Feel appreciation in your heart.', 'gratitude', 15, 75, true, true),
  ('a0000002-0000-0000-0000-00000000000e', 'Abundance Inventory', 'List all the resources you have: skills, relationships, opportunities, possessions that support your life.', 'gratitude', 15, 75, false, true),

  -- 20 min / 100 XP
  ('a0000002-0000-0000-0000-00000000000f', 'Future Self Letter', 'Write a letter to your future self, or write as your future self thanking your present self for the work you are doing.', 'gratitude', 20, 100, false, true),
  ('a0000002-0000-0000-0000-000000000010', 'Gratitude Deep Dive', 'Journal extensively about gratitude. Explore different areas of life: health, relationships, opportunities, growth.', 'gratitude', 20, 100, false, true),

  -- ============================================
  -- SOCIAL (14 new: 004-017)
  -- ============================================

  -- 5 min / 50 XP
  ('a0000003-0000-0000-0000-000000000004', 'Smile Mission', 'Make friendly eye contact and smile at 3 people today. Notice how it feels and how they respond.', 'social', 5, 50, false, true),
  ('a0000003-0000-0000-0000-000000000005', 'Voice Note Love', 'Record and send a quick voice message to someone, telling them you are thinking of them.', 'social', 5, 50, false, true),
  ('a0000003-0000-0000-0000-000000000006', 'Positive Comment', 'Leave 3 genuine positive comments on social media or in person. Make someone smile today.', 'social', 5, 50, false, true),
  ('a0000003-0000-0000-0000-000000000007', 'Kindness Planning', 'Plan one specific act of kindness you will do tomorrow. Write down who, what, and when.', 'social', 5, 50, false, true),
  ('a0000003-0000-0000-0000-000000000008', 'Quick Check-In', 'Text someone just to say you are thinking of them. No agenda, just connection.', 'social', 5, 50, false, true),

  -- 10 min / 75 XP (1 premium)
  ('a0000003-0000-0000-0000-000000000009', 'Meaningful Question', 'Ask someone "How are you really doing?" and listen fully to their answer without rushing to respond.', 'social', 10, 75, false, true),
  ('a0000003-0000-0000-0000-00000000000a', 'Shared Memory', 'Text or call someone to reminisce about a positive memory you shared together.', 'social', 10, 75, false, true),
  ('a0000003-0000-0000-0000-00000000000b', 'Appreciation Call', 'Call someone specifically to tell them why they matter to you and what you appreciate about them.', 'social', 10, 75, false, true),
  ('a0000003-0000-0000-0000-00000000000c', 'Mentor Moment', 'Share a piece of advice or encouragement with someone who might benefit from your experience.', 'social', 10, 75, false, true),
  ('a0000003-0000-0000-0000-00000000000d', 'Conflict Repair', 'Reach out to mend a small rift or misunderstanding with someone. Extend an olive branch.', 'social', 10, 75, true, true),

  -- 15 min / 75 XP (1 premium)
  ('a0000003-0000-0000-0000-00000000000e', 'Deep Listening Call', 'Have a phone conversation where you focus entirely on listening. Ask follow-up questions. Resist the urge to talk about yourself.', 'social', 15, 75, true, true),
  ('a0000003-0000-0000-0000-00000000000f', 'Family Video Call', 'Video chat with a family member you have not connected with recently. Share updates and show genuine interest in their life.', 'social', 15, 75, false, true),
  ('a0000003-0000-0000-0000-000000000010', 'Boundary Practice', 'Practice saying no kindly in a low-stakes situation. Notice how it feels to honor your limits.', 'social', 15, 75, false, true),

  -- 20 min / 100 XP
  ('a0000003-0000-0000-0000-000000000011', 'Quality Time Block', 'Spend 20 minutes of dedicated, uninterrupted time with someone important. Put away all devices.', 'social', 20, 100, false, true),

  -- ============================================
  -- PHYSICAL (14 new: 004-017)
  -- ============================================

  -- 5 min / 50 XP
  ('a0000004-0000-0000-0000-000000000004', 'Desk Stretches', 'Do quick stretches right where you are: neck rolls, shoulder shrugs, wrist circles, and seated twists.', 'physical', 5, 50, false, true),
  ('a0000004-0000-0000-0000-000000000005', 'Posture Reset', 'Stand tall with feet hip-width apart. Align your spine, roll shoulders back, and take 5 deep breaths.', 'physical', 5, 50, false, true),
  ('a0000004-0000-0000-0000-000000000006', 'Shake It Out', 'Shake your entire body vigorously for 2 minutes to release tension, then stand still and notice how you feel.', 'physical', 5, 50, false, true),
  ('a0000004-0000-0000-0000-000000000007', 'Balance Challenge', 'Stand on one foot for 30 seconds, then switch. Focus on a fixed point. Notice how your body finds stability.', 'physical', 5, 50, false, true),
  ('a0000004-0000-0000-0000-000000000008', 'Power Pose', 'Hold confident postures for 2 minutes: hands on hips, arms raised in victory. Feel your energy shift.', 'physical', 5, 50, false, true),

  -- 10 min / 75 XP (1 premium)
  ('a0000004-0000-0000-0000-000000000009', 'Sun Salutations', 'Flow through 3-5 yoga sun salutations, connecting breath with movement. Move at your own pace.', 'physical', 10, 75, false, true),
  ('a0000004-0000-0000-0000-00000000000a', 'Energizing Walk', 'Take a brisk 10-minute walk. Let your arms swing and your pace quicken. Get your heart rate up.', 'physical', 10, 75, false, true),
  ('a0000004-0000-0000-0000-00000000000b', 'Progressive Stretching', 'Stretch each major muscle group systematically: calves, thighs, hips, back, shoulders, neck.', 'physical', 10, 75, true, true),
  ('a0000004-0000-0000-0000-00000000000c', 'Stair Climbing', 'Find some stairs and climb them mindfully. Notice your breath, your muscles working, your body moving.', 'physical', 10, 75, false, true),
  ('a0000004-0000-0000-0000-00000000000d', 'Gentle Core Work', 'Do simple core exercises: planks, bird-dogs, and dead bugs. Focus on form over intensity.', 'physical', 10, 75, false, true),

  -- 15 min / 75 XP (1 premium)
  ('a0000004-0000-0000-0000-00000000000e', 'Mindful Nature Walk', 'Walk outside for 15 minutes, noticing nature around you. Feel the ground, observe plants and animals, breathe fresh air.', 'physical', 15, 75, true, true),
  ('a0000004-0000-0000-0000-00000000000f', 'Strength Circuit', 'Do a circuit of bodyweight exercises: squats, push-ups, lunges, and planks. Rest briefly between each.', 'physical', 15, 75, false, true),

  -- 20 min / 100 XP (1 premium)
  ('a0000004-0000-0000-0000-000000000010', 'Full Body Flow', 'Complete a comprehensive movement routine: warm-up, stretching, strength, and cool-down.', 'physical', 20, 100, true, true),
  ('a0000004-0000-0000-0000-000000000011', 'Walking Meditation', 'Walk slowly for 20 minutes, focusing on each step. Feel your foot lift, move, and touch the ground.', 'physical', 20, 100, false, true),

  -- ============================================
  -- CREATIVE (13 new: 004-016)
  -- ============================================

  -- 5 min / 50 XP
  ('a0000005-0000-0000-0000-000000000004', 'Word Association', 'Pick a random word and free-write whatever comes to mind. Do not stop or edit, just let words flow.', 'creative', 5, 50, false, true),
  ('a0000005-0000-0000-0000-000000000005', 'Quick Sketch', 'Draw the first thing you see right now. Do not worry about quality, just observe and create.', 'creative', 5, 50, false, true),
  ('a0000005-0000-0000-0000-000000000006', 'Haiku Challenge', 'Write a haiku (5-7-5 syllables) about your current mood or surroundings.', 'creative', 5, 50, false, true),
  ('a0000005-0000-0000-0000-000000000007', 'Color Hunt', 'Pick a color and spend 5 minutes finding it everywhere around you. Notice shades and variations.', 'creative', 5, 50, false, true),
  ('a0000005-0000-0000-0000-000000000008', 'Sound Creation', 'Make music using objects around you. Tap, shake, scrape. Create a rhythm or melody.', 'creative', 5, 50, false, true),

  -- 10 min / 75 XP (1 premium)
  ('a0000005-0000-0000-0000-000000000009', 'Story Starter', 'Write the opening paragraph of a story. Set a scene, introduce a character. You can continue later or leave it.', 'creative', 10, 75, false, true),
  ('a0000005-0000-0000-0000-00000000000a', 'Photography Walk', 'Take 5 meaningful photos of things around you. Look for beauty, patterns, or interesting details.', 'creative', 10, 75, false, true),
  ('a0000005-0000-0000-0000-00000000000b', 'Playlist Curation', 'Create a playlist that captures your current mood or the mood you want to cultivate.', 'creative', 10, 75, false, true),
  ('a0000005-0000-0000-0000-00000000000c', 'Memory Drawing', 'Draw a happy memory from your past. Do not worry about artistic skill, focus on recalling the feeling.', 'creative', 10, 75, true, true),
  ('a0000005-0000-0000-0000-00000000000d', 'Nature Art', 'Collect natural materials and arrange them into something beautiful. A mandala, a pattern, a sculpture.', 'creative', 10, 75, false, true),

  -- 15 min / 75 XP (1 premium)
  ('a0000005-0000-0000-0000-00000000000e', 'Letter to Self', 'Write a heartfelt letter to your past self or your future self. Be kind and honest.', 'creative', 15, 75, true, true),
  ('a0000005-0000-0000-0000-00000000000f', 'Collage Creation', 'Create a digital or physical collage using images that represent your dreams, values, or current state.', 'creative', 15, 75, false, true),

  -- 20 min / 100 XP (1 premium)
  ('a0000005-0000-0000-0000-000000000010', 'Creative Writing Session', 'Write freely for 20 minutes on any topic. Poetry, fiction, reflections. Let your creativity flow unfiltered.', 'creative', 20, 100, true, true),

  -- ============================================
  -- REFLECTION (12 new: 006-017)
  -- ============================================

  -- 5 min / 50 XP
  ('a0000006-0000-0000-0000-000000000006', 'Values Check', 'Ask yourself: Did I live according to my values today? Which value did I honor? Which did I neglect?', 'reflection', 5, 50, false, true),
  ('a0000006-0000-0000-0000-000000000007', 'Energy Audit', 'Reflect on your day. What activities gave you energy? What drained you? Write a few notes.', 'reflection', 5, 50, false, true),
  ('a0000006-0000-0000-0000-000000000008', 'Intention Setting', 'Set one clear intention for tomorrow. Write it down. Make it specific and achievable.', 'reflection', 5, 50, false, true),
  ('a0000006-0000-0000-0000-000000000009', 'Mood Check', 'Name your current emotional state. Just acknowledge it without trying to change it. What does it tell you?', 'reflection', 5, 50, false, true),

  -- 10 min / 75 XP (1 premium)
  ('a0000006-0000-0000-0000-00000000000a', 'Week Review', 'Look back at your week. What were the highlights? What challenged you? What did you learn?', 'reflection', 10, 75, false, true),
  ('a0000006-0000-0000-0000-00000000000b', 'Emotion Processing', 'Choose a recent emotion you felt strongly. Name it, locate it in your body, explore what triggered it.', 'reflection', 10, 75, true, true),
  ('a0000006-0000-0000-0000-00000000000c', 'Decision Reflection', 'Think about a recent decision you made. What influenced it? How did it turn out? What would you do differently?', 'reflection', 10, 75, false, true),
  ('a0000006-0000-0000-0000-00000000000d', 'Growth Spotting', 'Identify one way you have grown recently. Maybe a skill, a mindset shift, or improved patience.', 'reflection', 10, 75, false, true),

  -- 15 min / 75 XP (1 premium)
  ('a0000006-0000-0000-0000-00000000000e', 'Life Domain Review', 'Check in on different areas of your life: health, relationships, work, growth, fun. Rate each and reflect.', 'reflection', 15, 75, true, true),
  ('a0000006-0000-0000-0000-00000000000f', 'Fear Inventory', 'List fears that are holding you back. For each one, write a small action you could take to face it.', 'reflection', 15, 75, false, true),
  ('a0000006-0000-0000-0000-000000000010', 'Future Visioning', 'Imagine your ideal day 5 years from now. Where do you wake up? What do you do? Who is with you?', 'reflection', 15, 75, false, true),

  -- 20 min / 100 XP
  ('a0000006-0000-0000-0000-000000000011', 'Monthly Retrospective', 'Deeply review the past month. Accomplishments, challenges, lessons, gratitude, and intentions for next month.', 'reflection', 20, 100, false, true)

ON CONFLICT (id) DO NOTHING;
