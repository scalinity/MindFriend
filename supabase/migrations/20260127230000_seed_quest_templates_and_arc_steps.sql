-- Seed quest templates for use in quest arcs
-- These are reusable templates that can be assigned to different arc days

-- Create quest templates
INSERT INTO quest_templates (id, title, description, category, estimated_minutes, xp_reward, is_premium, is_active)
VALUES
  -- Mindfulness templates
  ('a0000001-0000-0000-0000-000000000001', 'Morning Meditation', 'Start your day with a 5-minute guided meditation', 'mindfulness', 5, 50, false, true),
  ('a0000001-0000-0000-0000-000000000002', 'Deep Breathing Exercise', 'Practice box breathing for calm and focus', 'mindfulness', 5, 50, false, true),
  ('a0000001-0000-0000-0000-000000000003', 'Body Scan Relaxation', 'Progressive muscle relaxation from head to toe', 'mindfulness', 10, 75, false, true),
  ('a0000001-0000-0000-0000-000000000004', 'Mindful Walking', 'Take a slow, mindful walk focusing on each step', 'mindfulness', 15, 75, false, true),
  ('a0000001-0000-0000-0000-000000000005', 'Evening Wind Down', 'Calm evening meditation to prepare for sleep', 'mindfulness', 10, 75, false, true),

  -- Gratitude templates
  ('a0000002-0000-0000-0000-000000000001', 'Gratitude Journal', 'Write three things you are grateful for today', 'gratitude', 5, 50, false, true),
  ('a0000002-0000-0000-0000-000000000002', 'Thank Someone', 'Send a thank you message to someone who helped you', 'gratitude', 10, 75, false, true),
  ('a0000002-0000-0000-0000-000000000003', 'Appreciation Moment', 'Spend 5 minutes appreciating something in your environment', 'gratitude', 5, 50, false, true),

  -- Social templates
  ('a0000003-0000-0000-0000-000000000001', 'Connect with a Friend', 'Reach out to a friend you have not talked to recently', 'social', 15, 100, false, true),
  ('a0000003-0000-0000-0000-000000000002', 'Compliment Someone', 'Give a genuine compliment to someone today', 'social', 5, 50, false, true),
  ('a0000003-0000-0000-0000-000000000003', 'Active Listening', 'Have a conversation focusing on truly listening', 'social', 20, 100, false, true),

  -- Physical templates
  ('a0000004-0000-0000-0000-000000000001', 'Morning Stretch', '5-minute gentle stretching routine', 'physical', 5, 50, false, true),
  ('a0000004-0000-0000-0000-000000000002', 'Take a Walk', 'Go for a 15-minute walk outside', 'physical', 15, 75, false, true),
  ('a0000004-0000-0000-0000-000000000003', 'Dance Break', 'Dance to your favorite song', 'physical', 5, 50, false, true),

  -- Creative templates
  ('a0000005-0000-0000-0000-000000000001', 'Doodle Time', 'Spend 10 minutes doodling or drawing', 'creative', 10, 75, false, true),
  ('a0000005-0000-0000-0000-000000000002', 'Write a Poem', 'Write a short poem about your feelings', 'creative', 15, 100, false, true),
  ('a0000005-0000-0000-0000-000000000003', 'Music Moment', 'Listen mindfully to a piece of music', 'creative', 10, 75, false, true),

  -- Reflection templates
  ('a0000006-0000-0000-0000-000000000001', 'Daily Reflection', 'Reflect on your day and write your thoughts', 'reflection', 10, 75, false, true),
  ('a0000006-0000-0000-0000-000000000002', 'Goal Check-In', 'Review your goals and progress', 'reflection', 10, 75, false, true),
  ('a0000006-0000-0000-0000-000000000003', 'Self-Affirmation', 'Write and speak three positive affirmations', 'reflection', 5, 50, false, true),
  ('a0000006-0000-0000-0000-000000000004', 'Strength Recognition', 'Identify three personal strengths you used today', 'reflection', 10, 75, false, true),
  ('a0000006-0000-0000-0000-000000000005', 'Progress Celebration', 'Celebrate a small win from this week', 'reflection', 5, 50, false, true)
ON CONFLICT (id) DO NOTHING;

-- Now create arc steps for each quest arc
-- We need to link each arc to its daily quest templates

-- Function to create steps for an arc
DO $$
DECLARE
  arc_record RECORD;
  day_num INTEGER;
  template_id UUID;
  templates UUID[];
BEGIN
  -- Define template pools for different arc categories
  -- Stress arcs use mindfulness templates
  -- Sleep arcs use mindfulness (evening focus)
  -- Confidence arcs use reflection/gratitude
  -- Focus arcs use mindfulness
  -- Resilience arcs use reflection/physical

  FOR arc_record IN SELECT id, category, duration_days, milestone_days FROM quest_arcs LOOP
    -- Create a step for each day of the arc
    FOR day_num IN 1..arc_record.duration_days LOOP
      -- Select appropriate template based on category and day
      CASE arc_record.category
        WHEN 'stress' THEN
          templates := ARRAY[
            'a0000001-0000-0000-0000-000000000001'::UUID,  -- Morning Meditation
            'a0000001-0000-0000-0000-000000000002'::UUID,  -- Deep Breathing
            'a0000001-0000-0000-0000-000000000003'::UUID,  -- Body Scan
            'a0000001-0000-0000-0000-000000000004'::UUID,  -- Mindful Walking
            'a0000001-0000-0000-0000-000000000005'::UUID   -- Evening Wind Down
          ];
        WHEN 'sleep' THEN
          templates := ARRAY[
            'a0000001-0000-0000-0000-000000000005'::UUID,  -- Evening Wind Down
            'a0000001-0000-0000-0000-000000000003'::UUID,  -- Body Scan
            'a0000001-0000-0000-0000-000000000002'::UUID,  -- Deep Breathing
            'a0000001-0000-0000-0000-000000000001'::UUID,  -- Morning Meditation
            'a0000006-0000-0000-0000-000000000001'::UUID   -- Daily Reflection
          ];
        WHEN 'confidence' THEN
          templates := ARRAY[
            'a0000006-0000-0000-0000-000000000003'::UUID,  -- Self-Affirmation
            'a0000006-0000-0000-0000-000000000004'::UUID,  -- Strength Recognition
            'a0000006-0000-0000-0000-000000000005'::UUID,  -- Progress Celebration
            'a0000002-0000-0000-0000-000000000001'::UUID,  -- Gratitude Journal
            'a0000006-0000-0000-0000-000000000002'::UUID   -- Goal Check-In
          ];
        WHEN 'focus' THEN
          templates := ARRAY[
            'a0000001-0000-0000-0000-000000000001'::UUID,  -- Morning Meditation
            'a0000001-0000-0000-0000-000000000002'::UUID,  -- Deep Breathing
            'a0000005-0000-0000-0000-000000000003'::UUID,  -- Music Moment
            'a0000001-0000-0000-0000-000000000004'::UUID,  -- Mindful Walking
            'a0000006-0000-0000-0000-000000000001'::UUID   -- Daily Reflection
          ];
        WHEN 'resilience' THEN
          templates := ARRAY[
            'a0000006-0000-0000-0000-000000000004'::UUID,  -- Strength Recognition
            'a0000004-0000-0000-0000-000000000002'::UUID,  -- Take a Walk
            'a0000006-0000-0000-0000-000000000003'::UUID,  -- Self-Affirmation
            'a0000003-0000-0000-0000-000000000001'::UUID,  -- Connect with Friend
            'a0000006-0000-0000-0000-000000000002'::UUID   -- Goal Check-In
          ];
        ELSE
          templates := ARRAY[
            'a0000001-0000-0000-0000-000000000001'::UUID,
            'a0000002-0000-0000-0000-000000000001'::UUID,
            'a0000006-0000-0000-0000-000000000001'::UUID
          ];
      END CASE;

      -- Cycle through templates
      template_id := templates[((day_num - 1) % array_length(templates, 1)) + 1];

      -- Insert the step
      INSERT INTO quest_arc_steps (arc_id, day_number, quest_template_id, is_milestone, milestone_xp_bonus)
      VALUES (
        arc_record.id,
        day_num,
        template_id,
        day_num = ANY(arc_record.milestone_days),
        CASE WHEN day_num = ANY(arc_record.milestone_days) THEN 100 ELSE 0 END
      )
      ON CONFLICT DO NOTHING;
    END LOOP;
  END LOOP;
END $$;
