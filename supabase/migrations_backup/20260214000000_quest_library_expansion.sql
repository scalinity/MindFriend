-- Quest Library Expansion Migration
-- Adds 56 new quest templates to bring total to 66
-- Adds 22 quick variants for busy-day completions
-- Distribution: 11 per category, ~60% easy, ~30% medium, ~10% hard, ~18% premium

-- ============================================================================
-- MINDFULNESS QUESTS (11 total, 8 new)
-- ============================================================================

INSERT INTO quest_templates (title, description, category, estimated_minutes, xp_reward, is_premium)
VALUES
  -- Easy (5)
  ('Box Breathing', 'A calming 4-4-4-4 breathing pattern used by Navy SEALs to reduce stress', 'mindfulness', 5, 50, false),
  ('4-7-8 Relaxing Breath', 'Dr. Andrew Weil''s natural tranquilizer technique for the nervous system', 'mindfulness', 5, 50, false),
  ('Coherent Breathing', 'Breathe at 5 breaths per minute to synchronize your heart and brain rhythms', 'mindfulness', 5, 50, false),
  ('Deep Belly Breathing', 'Diaphragmatic breathing to activate your body''s natural relaxation response', 'mindfulness', 5, 50, false),
  ('Calming Breath Wave', 'Visualize your breath as gentle ocean waves washing away tension', 'mindfulness', 5, 50, false),

  -- Medium (2)
  ('Alternate Nostril Breathing', 'A yogic breathing practice to balance your energy and calm the mind', 'mindfulness', 7, 60, false),
  ('Energizing Breath', 'A stimulating breathing technique to increase alertness and natural energy', 'mindfulness', 5, 60, false),

  -- Premium (1)
  ('Breathing Body Scan', 'Combine deep breathing with progressive body awareness for complete relaxation', 'mindfulness', 10, 80, true)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- GRATITUDE QUESTS (11 total, 10 new)
-- ============================================================================

INSERT INTO quest_templates (title, description, category, estimated_minutes, xp_reward, is_premium)
VALUES
  -- Easy (7)
  ('Three Good Things', 'Write down three positive things that happened today, no matter how small', 'gratitude', 5, 50, false),
  ('Body Gratitude', 'Take a moment to thank your body for all it does for you each day', 'gratitude', 5, 50, false),
  ('Gratitude for the Ordinary', 'Appreciate the everyday things we often take for granted', 'gratitude', 5, 50, false),
  ('Gratitude for Nature', 'Connect with and appreciate the natural world around you', 'gratitude', 7, 50, false),
  ('Gratitude Chain', 'Connect gratitude thoughts together in a flowing appreciation chain', 'gratitude', 5, 50, false),
  ('Photo Memory Gratitude', 'Browse photos and appreciate the happy memories they capture', 'gratitude', 7, 55, false),
  ('Appreciation Message', 'Send a heartfelt thank you message to someone who made a difference', 'gratitude', 5, 50, false),

  -- Medium (2)
  ('Gratitude for Challenges', 'Find the hidden gifts and lessons in a recent difficult experience', 'gratitude', 7, 65, false),
  ('Gratitude Alphabet', 'Find something to be grateful for starting with each letter A-Z', 'gratitude', 10, 70, false),

  -- Premium (1)
  ('Deep Gratitude Meditation', 'A profound meditation on gratitude for existence and connection', 'gratitude', 15, 100, true)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- SOCIAL QUESTS (11 total, 9 new)
-- ============================================================================

INSERT INTO quest_templates (title, description, category, estimated_minutes, xp_reward, is_premium)
VALUES
  -- Easy (6)
  ('Compliment Someone', 'Give a genuine compliment to someone you interact with today', 'social', 5, 50, false),
  ('Check-In Message', 'Send a simple "thinking of you" message to someone you care about', 'social', 5, 50, false),
  ('Active Listening Practice', 'Have a conversation where you focus entirely on understanding the other person', 'social', 10, 65, false),
  ('Share Something Positive', 'Share good news or a positive thought with someone in your life', 'social', 5, 50, false),
  ('Express Appreciation', 'Tell someone specifically why you appreciate having them in your life', 'social', 5, 55, false),
  ('Random Act of Kindness', 'Do something kind for someone without expecting anything in return', 'social', 10, 70, false),

  -- Medium (3)
  ('Forgiveness Reflection', 'Reflect on letting go of resentment toward someone, including yourself', 'social', 10, 75, false),
  ('Connection Call', 'Call someone you haven''t spoken to in a while just to catch up', 'social', 15, 85, false),
  ('Empathy Exercise', 'Try to see a situation from someone else''s perspective completely', 'social', 10, 70, false),

  -- Premium (1)
  ('Gratitude Letter Writing', 'Write a heartfelt letter of thanks to someone who has impacted your life', 'social', 15, 100, true)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- PHYSICAL QUESTS (11 total, 10 new)
-- ============================================================================

INSERT INTO quest_templates (title, description, category, estimated_minutes, xp_reward, is_premium)
VALUES
  -- Easy (6)
  ('Morning Stretch Routine', 'A gentle stretching sequence to wake up your body and mind', 'physical', 7, 55, false),
  ('Desk Stretch Break', 'Quick stretches you can do at your desk to release tension', 'physical', 5, 50, false),
  ('Neck and Shoulder Release', 'Target the tension in your neck and shoulders from stress or screens', 'physical', 5, 50, false),
  ('Mindful Walking', 'A slow, intentional walk focusing on each step and your surroundings', 'physical', 10, 65, false),
  ('Gratitude Walk', 'Walk while reflecting on things you appreciate in your life', 'physical', 10, 65, false),
  ('Cat-Cow Flow', 'A yoga-inspired spine mobility exercise for flexibility and calm', 'physical', 5, 50, false),

  -- Medium (3)
  ('Energizing Power Walk', 'A brisk walk to boost your energy, mood, and circulation', 'physical', 10, 70, false),
  ('Hip Opener Sequence', 'Release tension stored in your hips from prolonged sitting', 'physical', 10, 75, false),
  ('Standing Energy Flow', 'Flowing movements to wake up your entire body and increase vitality', 'physical', 7, 60, false),

  -- Premium (1)
  ('Full Body Stretch Sequence', 'A complete stretching routine targeting every major muscle group', 'physical', 15, 100, true)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- CREATIVE QUESTS (11 total, 10 new)
-- ============================================================================

INSERT INTO quest_templates (title, description, category, estimated_minutes, xp_reward, is_premium)
VALUES
  -- Easy (7)
  ('Morning Pages', 'Free-write your thoughts for 10 minutes to clear your mind', 'creative', 10, 65, false),
  ('Worry Dump', 'Get anxious thoughts out of your head and onto paper to release them', 'creative', 5, 50, false),
  ('Success Log', 'Document your daily wins and accomplishments, no matter how small', 'creative', 5, 50, false),
  ('Positive Affirmations', 'Create personal affirmations to boost your confidence and mood', 'creative', 5, 50, false),
  ('Doodle Break', 'Spend a few minutes drawing whatever comes to mind without judgment', 'creative', 5, 50, false),
  ('Sensory Description', 'Describe your current environment using all five senses in writing', 'creative', 7, 55, false),
  ('Haiku Moment', 'Capture this moment in a simple 5-7-5 syllable poem', 'creative', 5, 50, false),

  -- Medium (2)
  ('Letter to Future Self', 'Write encouragement and wisdom to yourself one year from now', 'creative', 10, 75, false),
  ('Emotion Art', 'Express your current emotions through colors, shapes, or doodles', 'creative', 10, 70, false),

  -- Hard Premium (1)
  ('Shadow Work Journal', 'Explore a difficult emotion or pattern with compassion and curiosity', 'creative', 15, 100, true)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- REFLECTION QUESTS (11 total, 9 new)
-- ============================================================================

INSERT INTO quest_templates (title, description, category, estimated_minutes, xp_reward, is_premium)
VALUES
  -- Easy (6)
  ('Intention Setting', 'Set a clear intention to guide your focus for the next few hours', 'reflection', 5, 50, false),
  ('5-Minute Declutter', 'Clear your immediate space to clear your mind and improve focus', 'reflection', 5, 50, false),
  ('Mind Dump', 'Empty all tasks and thoughts from your head onto paper for clarity', 'reflection', 5, 50, false),
  ('Digital Detox Check', 'Pause to evaluate and reset your relationship with screens', 'reflection', 5, 50, false),
  ('Mindful Listening', 'Practice deep listening to the sounds around you without judgment', 'reflection', 7, 55, false),
  ('Values Check-In', 'Reflect on whether your recent actions align with your core values', 'reflection', 7, 60, false),

  -- Medium (3)
  ('Emotion Exploration', 'Dive deep into understanding and accepting a current emotion', 'reflection', 7, 65, false),
  ('Weekly Review', 'Reflect on your week''s highlights, challenges, and lessons learned', 'reflection', 10, 75, false),
  ('Priority Matrix', 'Organize your tasks by urgency and importance for better focus', 'reflection', 10, 70, false),

  -- Hard Premium (1)
  ('Sustained Focus Challenge', 'Test and strengthen your ability to maintain deep concentration', 'reflection', 15, 100, true)
ON CONFLICT DO NOTHING;

-- ============================================================================
-- QUICK VARIANTS (22 total)
-- These are shortened 2-3 minute versions with 50% XP multiplier
-- ============================================================================

-- Get parent template IDs and insert quick variants
INSERT INTO quest_quick_variants (parent_template_id, title, description, steps, estimated_minutes, xp_multiplier)
SELECT
  qt.id,
  'Quick ' || qt.title,
  'A brief ' || LOWER(qt.category::text) || ' moment when you''re short on time',
  CASE qt.title
    -- Mindfulness quick variants
    WHEN 'Box Breathing' THEN '[{"step":1,"text":"Sit comfortably and close your eyes","durationSeconds":10},{"step":2,"text":"Breathe in for 4 counts, hold for 4, out for 4, hold for 4","durationSeconds":32},{"step":3,"text":"Repeat 2 more times and notice the calm","durationSeconds":70}]'::jsonb
    WHEN '4-7-8 Relaxing Breath' THEN '[{"step":1,"text":"Find a comfortable position","durationSeconds":10},{"step":2,"text":"Inhale for 4, hold for 7, exhale for 8","durationSeconds":19},{"step":3,"text":"Repeat twice more","durationSeconds":50}]'::jsonb
    WHEN 'Coherent Breathing' THEN '[{"step":1,"text":"Sit comfortably","durationSeconds":10},{"step":2,"text":"Breathe in for 6 seconds, out for 6 seconds","durationSeconds":72},{"step":3,"text":"Notice the calm rhythm","durationSeconds":20}]'::jsonb
    WHEN 'Mindful Breathing' THEN '[{"step":1,"text":"Close your eyes","durationSeconds":10},{"step":2,"text":"Take 5 slow, deep breaths","durationSeconds":50},{"step":3,"text":"Notice how you feel","durationSeconds":20}]'::jsonb

    -- Gratitude quick variants
    WHEN 'Morning Gratitude' THEN '[{"step":1,"text":"Pause and take a breath","durationSeconds":10},{"step":2,"text":"Think of one thing you are grateful for right now","durationSeconds":40},{"step":3,"text":"Feel the appreciation fully","durationSeconds":30}]'::jsonb
    WHEN 'Three Good Things' THEN '[{"step":1,"text":"Take a breath","durationSeconds":10},{"step":2,"text":"Name one good thing that happened today","durationSeconds":50},{"step":3,"text":"Appreciate it fully","durationSeconds":30}]'::jsonb
    WHEN 'Body Gratitude' THEN '[{"step":1,"text":"Close your eyes","durationSeconds":10},{"step":2,"text":"Thank one part of your body for what it does","durationSeconds":50},{"step":3,"text":"Send it appreciation","durationSeconds":30}]'::jsonb
    WHEN 'Gratitude Chain' THEN '[{"step":1,"text":"Think of one thing you are grateful for","durationSeconds":20},{"step":2,"text":"Ask what about this are you also grateful for?","durationSeconds":40},{"step":3,"text":"Follow the chain for one more link","durationSeconds":30}]'::jsonb

    -- Social quick variants
    WHEN 'Acts of Kindness' THEN '[{"step":1,"text":"Think of one small kindness you can do today","durationSeconds":30},{"step":2,"text":"Commit to doing it","durationSeconds":30},{"step":3,"text":"Imagine how it will feel","durationSeconds":30}]'::jsonb
    WHEN 'Reach Out' THEN '[{"step":1,"text":"Think of someone you care about","durationSeconds":20},{"step":2,"text":"Send them a quick thinking of you message","durationSeconds":60},{"step":3,"text":"Feel the connection","durationSeconds":20}]'::jsonb
    WHEN 'Check-In Message' THEN '[{"step":1,"text":"Choose someone to reach out to","durationSeconds":15},{"step":2,"text":"Send a brief caring message","durationSeconds":60},{"step":3,"text":"Appreciate the connection","durationSeconds":15}]'::jsonb

    -- Physical quick variants
    WHEN 'Nature Walk' THEN '[{"step":1,"text":"Step outside or to a window","durationSeconds":15},{"step":2,"text":"Take 5 deep breaths while observing nature","durationSeconds":50},{"step":3,"text":"Appreciate what you noticed","durationSeconds":25}]'::jsonb
    WHEN 'Morning Stretch Routine' THEN '[{"step":1,"text":"Stand and reach arms overhead","durationSeconds":20},{"step":2,"text":"Roll shoulders back 5 times","durationSeconds":20},{"step":3,"text":"Gently twist torso left and right","durationSeconds":40}]'::jsonb
    WHEN 'Desk Stretch Break' THEN '[{"step":1,"text":"Roll your neck gently in circles","durationSeconds":20},{"step":2,"text":"Shrug shoulders up, hold, release","durationSeconds":20},{"step":3,"text":"Stretch arms forward with interlaced fingers","durationSeconds":30}]'::jsonb
    WHEN 'Neck and Shoulder Release' THEN '[{"step":1,"text":"Drop chin to chest and hold","durationSeconds":20},{"step":2,"text":"Tilt head to each shoulder","durationSeconds":30},{"step":3,"text":"Roll shoulders back 5 times","durationSeconds":20}]'::jsonb
    WHEN 'Cat-Cow Flow' THEN '[{"step":1,"text":"Come to hands and knees","durationSeconds":15},{"step":2,"text":"Arch back on inhale, round on exhale","durationSeconds":60},{"step":3,"text":"Return to neutral and breathe","durationSeconds":15}]'::jsonb

    -- Creative quick variants
    WHEN 'Journaling' THEN '[{"step":1,"text":"Grab paper or open notes","durationSeconds":15},{"step":2,"text":"Write continuously for 90 seconds","durationSeconds":90},{"step":3,"text":"Take a breath and release","durationSeconds":15}]'::jsonb
    WHEN 'Morning Pages' THEN '[{"step":1,"text":"Open your notes app","durationSeconds":10},{"step":2,"text":"Write whatever comes to mind for 2 minutes","durationSeconds":90},{"step":3,"text":"Notice how your mind feels clearer","durationSeconds":20}]'::jsonb
    WHEN 'Worry Dump' THEN '[{"step":1,"text":"Write down your biggest worry right now","durationSeconds":30},{"step":2,"text":"Ask: Can I control this?","durationSeconds":30},{"step":3,"text":"Take a breath and release it","durationSeconds":30}]'::jsonb
    WHEN 'Positive Affirmations' THEN '[{"step":1,"text":"Write I am followed by a positive trait","durationSeconds":30},{"step":2,"text":"Write I can followed by something you are capable of","durationSeconds":30},{"step":3,"text":"Read them aloud or silently","durationSeconds":30}]'::jsonb

    -- Reflection quick variants
    WHEN 'Evening Reflection' THEN '[{"step":1,"text":"Pause and take a breath","durationSeconds":15},{"step":2,"text":"What was the best moment of your day?","durationSeconds":45},{"step":3,"text":"Appreciate it","durationSeconds":30}]'::jsonb
    WHEN 'Intention Setting' THEN '[{"step":1,"text":"Take a centering breath","durationSeconds":15},{"step":2,"text":"What is most important right now?","durationSeconds":35},{"step":3,"text":"Commit to your intention","durationSeconds":30}]'::jsonb

    ELSE '[{"step":1,"text":"Take a centering breath","durationSeconds":20},{"step":2,"text":"Complete a brief version of this activity","durationSeconds":60},{"step":3,"text":"Notice how you feel","durationSeconds":20}]'::jsonb
  END,
  CASE
    WHEN qt.estimated_minutes <= 5 THEN 2
    WHEN qt.estimated_minutes <= 10 THEN 3
    ELSE 3
  END,
  0.5
FROM quest_templates qt
WHERE qt.title IN (
  -- Mindfulness
  'Box Breathing', '4-7-8 Relaxing Breath', 'Coherent Breathing', 'Mindful Breathing',
  -- Gratitude
  'Morning Gratitude', 'Three Good Things', 'Body Gratitude', 'Gratitude Chain',
  -- Social
  'Acts of Kindness', 'Reach Out', 'Check-In Message',
  -- Physical
  'Nature Walk', 'Morning Stretch Routine', 'Desk Stretch Break', 'Neck and Shoulder Release', 'Cat-Cow Flow',
  -- Creative
  'Journaling', 'Morning Pages', 'Worry Dump', 'Positive Affirmations',
  -- Reflection
  'Evening Reflection', 'Intention Setting'
)
AND NOT EXISTS (
  SELECT 1 FROM quest_quick_variants qv WHERE qv.parent_template_id = qt.id
);

-- ============================================================================
-- VERIFICATION QUERIES (run after migration)
-- ============================================================================
-- SELECT category, COUNT(*) as count FROM quest_templates GROUP BY category ORDER BY category;
-- Should show: creative=11, gratitude=11, mindfulness=11, physical=11, reflection=11, social=11

-- SELECT COUNT(*) FROM quest_quick_variants;
-- Should show: 22+

-- SELECT COUNT(*) FROM quest_templates WHERE is_premium = true;
-- Should show: 12
