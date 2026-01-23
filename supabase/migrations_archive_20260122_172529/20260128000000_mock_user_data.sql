-- Mock User Data for Testing Weekly Insights
-- User: 9f4fcd09-2684-4a85-924f-3e2c81554f50
-- Creates 30 days of realistic activity with detectable patterns
-- Note: Only runs if the test user exists in auth.users

DO $$
DECLARE
  v_user_id UUID := '9f4fcd09-2684-4a85-924f-3e2c81554f50';
  v_user_exists BOOLEAN;
  v_day DATE;
  v_mood_score INT;
  v_day_of_week INT;
  v_base_mood FLOAT;
  v_quest_templates UUID[] := ARRAY[
    '0440d865-39f6-41ab-a5f4-b76f1b748472'::UUID,  -- Morning Gratitude
    '8959bd9b-06a9-4367-a9ed-c81ac41d2574'::UUID,  -- Mindful Breathing
    '5ba16f2d-6791-4fb8-8106-3ee612d51311'::UUID   -- Reach Out
  ];
  v_exercises UUID[] := ARRAY[
    'cb442133-a6f4-4da5-bd96-e69e4682655d'::UUID,  -- Box Breathing
    'b9f9de71-4d38-49a9-9837-8f46b2010478'::UUID,  -- 4-7-8 Breathing
    '6f5c677b-1ce5-42f7-81f7-950744498c62'::UUID,  -- Body Scan Meditation
    'ecd91710-1daf-4f06-8282-d00299690265'::UUID,  -- Loving Kindness
    '19c8cff7-0d4c-4450-8afd-6f830d713302'::UUID   -- 5-4-3-2-1 Grounding
  ];
  v_mood_notes TEXT[] := ARRAY[
    'Feeling low today, hard to get started',
    'A bit tired but managing',
    'Okay day, nothing special',
    'Feeling pretty good!',
    'Had a rough morning',
    'Productive and calm',
    'Great energy today',
    'Feeling peaceful after meditation',
    'Work stress getting to me',
    'Nice walk helped my mood',
    'Grateful for small wins',
    'Anxious but working through it',
    'Solid day overall',
    'Really positive interactions today',
    'Feeling centered and focused'
  ];
  v_template_idx INT;
  v_exercise_idx INT;
  v_week_num INT;
  v_completed BOOLEAN;
  v_did_exercise BOOLEAN;
  v_exercise_hour INT;
BEGIN
  -- Check if test user exists
  SELECT EXISTS (SELECT 1 FROM auth.users WHERE id = v_user_id) INTO v_user_exists;

  IF NOT v_user_exists THEN
    RAISE NOTICE 'Test user % does not exist, skipping mock data creation', v_user_id;
    RETURN;
  END IF;

  -- Clear existing data for this user (idempotent)
  DELETE FROM moods WHERE user_id = v_user_id;
  DELETE FROM quests WHERE user_id = v_user_id;
  DELETE FROM exercise_sessions WHERE user_id = v_user_id;

  -- Generate 30 days of data
  FOR i IN 0..29 LOOP
    v_day := CURRENT_DATE - (29 - i);
    v_day_of_week := EXTRACT(DOW FROM v_day)::INT;  -- 0=Sunday, 1=Monday, etc.
    v_week_num := (i / 7) + 1;  -- Week 1-5

    -- Base mood improves over time (simulating user progress)
    -- Week 1: 2.8, Week 2: 3.1, Week 3: 3.4, Week 4+: 3.7
    v_base_mood := 2.8 + (v_week_num - 1) * 0.3;

    -- Day of week adjustment (Monday blues, Friday high)
    CASE v_day_of_week
      WHEN 1 THEN v_base_mood := v_base_mood - 0.4;  -- Monday: lower
      WHEN 5 THEN v_base_mood := v_base_mood + 0.3;  -- Friday: higher
      WHEN 0, 6 THEN v_base_mood := v_base_mood + 0.2;  -- Weekend: slightly higher
      ELSE NULL;
    END CASE;

    -- Determine if exercise today (more likely in later weeks)
    v_did_exercise := random() < (0.3 + v_week_num * 0.1);

    -- If exercise, boost mood and record session
    IF v_did_exercise THEN
      v_base_mood := v_base_mood + 0.4;
      v_exercise_hour := 7 + floor(random() * 4)::INT;  -- 7-10 AM
      v_exercise_idx := 1 + floor(random() * 5)::INT;

      INSERT INTO exercise_sessions (user_id, exercise_id, started_at, ended_at, completed, rating, note, created_at)
      VALUES (
        v_user_id,
        v_exercises[v_exercise_idx],
        (v_day + (v_exercise_hour || ' hours')::INTERVAL)::TIMESTAMPTZ,
        (v_day + ((v_exercise_hour + (5 + floor(random() * 15)::INT) / 60.0) || ' hours')::INTERVAL)::TIMESTAMPTZ,
        true,
        3 + floor(random() * 3)::INT,  -- Rating 3-5
        CASE floor(random() * 3)::INT
          WHEN 0 THEN 'Felt calming'
          WHEN 1 THEN 'Good session'
          ELSE 'Needed this today'
        END,
        (v_day + (v_exercise_hour || ' hours')::INTERVAL)::TIMESTAMPTZ
      );
    END IF;

    -- Clamp mood to valid range and add randomness
    v_mood_score := LEAST(5, GREATEST(1, round(v_base_mood + (random() - 0.5))::INT));

    -- Insert daily mood (one per day due to unique constraint)
    INSERT INTO moods (user_id, local_date, mood_score, note, created_at)
    VALUES (
      v_user_id,
      v_day,
      v_mood_score,
      v_mood_notes[1 + floor(random() * array_length(v_mood_notes, 1))::INT],
      (v_day + '9 hours'::INTERVAL + (random() * 4 || ' hours')::INTERVAL)::TIMESTAMPTZ
    );

    -- Quest assignment and completion
    v_template_idx := 1 + floor(random() * 3)::INT;
    -- Completion rate improves over weeks: 60% -> 75% -> 85% -> 95%
    v_completed := random() < (0.6 + (v_week_num - 1) * 0.12);

    -- Skip some days in week 1 (no quest assigned)
    IF v_week_num = 1 AND random() < 0.3 THEN
      CONTINUE;
    END IF;

    INSERT INTO quests (user_id, template_id, local_date, status, assigned_at, completed_at, created_at)
    VALUES (
      v_user_id,
      v_quest_templates[v_template_idx],
      v_day::TEXT,
      CASE WHEN v_completed THEN 'completed' ELSE 'assigned' END,
      (v_day + '6 hours'::INTERVAL)::TIMESTAMPTZ,
      CASE WHEN v_completed THEN (v_day + (8 + floor(random() * 10)::INT || ' hours')::INTERVAL)::TIMESTAMPTZ ELSE NULL END,
      (v_day + '6 hours'::INTERVAL)::TIMESTAMPTZ
    );
  END LOOP;

  -- Update user profile with streak data
  UPDATE profiles
  SET
    current_streak_days = 12,
    longest_streak_days = 12,
    timezone = 'America/Los_Angeles',
    display_name = COALESCE(display_name, 'Test User')
  WHERE id = v_user_id;

  -- Update user_stats if exists
  INSERT INTO user_stats (user_id, current_streak_days, longest_streak_days, total_quests_completed, total_exercises_completed)
  VALUES (v_user_id, 12, 12, 25, 15)
  ON CONFLICT (user_id) DO UPDATE SET
    current_streak_days = 12,
    longest_streak_days = 12,
    total_quests_completed = 25,
    total_exercises_completed = 15;

END $$;
