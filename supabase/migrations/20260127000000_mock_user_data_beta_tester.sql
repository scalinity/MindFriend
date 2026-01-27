-- Mock User Data for Test User b@gmail.com
-- Creates 35+ days of realistic activity to simulate a month+ of app usage
-- Idempotent: safe to run multiple times

DO $$
DECLARE
  v_user_id UUID;
  v_day DATE;
  v_mood_score INT;
  v_anxiety_score INT;
  v_energy_score INT;
  v_day_of_week INT;
  v_base_mood FLOAT;
  v_week_num INT;
  v_completed BOOLEAN;
  v_did_exercise BOOLEAN;
  v_exercise_hour INT;
  v_template_idx INT;
  v_exercise_idx INT;
  v_conv_id UUID;
  v_badge_id UUID;

  -- Quest templates (will be populated dynamically)
  v_quest_templates UUID[];

  -- Exercises (will be populated dynamically)
  v_exercises UUID[];

  -- Mood notes for variety
  v_mood_notes TEXT[] := ARRAY[
    'Feeling a bit overwhelmed today',
    'Tired but managing',
    'Okay day, nothing special',
    'Feeling pretty good!',
    'Had a rough morning but getting better',
    'Productive and calm',
    'Great energy today',
    'Feeling peaceful after meditation',
    'Work stress getting to me',
    'Nice walk helped my mood',
    'Grateful for small wins today',
    'Anxious but working through it',
    'Solid day overall',
    'Really positive interactions today',
    'Feeling centered and focused',
    'Slept well, feeling refreshed',
    'A bit scattered but staying positive',
    'Making progress on my goals',
    'Took time for self-care today',
    'Feeling more resilient lately'
  ];

  -- Quest reflection notes
  v_quest_notes TEXT[] := ARRAY[
    'Felt good to complete this',
    'Took more effort than expected but worth it',
    'This is becoming a habit!',
    'Really helped my mood today',
    'Need to do this more often',
    'Simple but effective',
    'Getting better at this each time',
    'Noticed real benefits from this practice'
  ];

  -- Exercise notes
  v_exercise_notes TEXT[] := ARRAY[
    'Felt calming',
    'Good session',
    'Needed this today',
    'Really relaxing',
    'Helped clear my mind',
    'Great way to start the day'
  ];

  -- Conversation starters (user messages)
  v_user_messages TEXT[] := ARRAY[
    'I''ve been feeling stressed about work lately',
    'How can I sleep better at night?',
    'I want to build better habits',
    'Sometimes I feel overwhelmed by everything',
    'What are some quick ways to calm down?'
  ];

  -- AI responses
  v_ai_responses TEXT[] := ARRAY[
    'I hear you. Work stress can really take a toll. Let''s explore some strategies that might help. What specifically about work has been most challenging?',
    'Sleep is so important for our wellbeing. There are several evidence-based techniques we can try. Have you noticed any patterns in your sleep difficulties?',
    'Building habits is a wonderful goal! The key is starting small and being consistent. What habit would you most like to develop?',
    'Feeling overwhelmed is very common, and it''s okay to acknowledge that. Let''s break things down together. What feels most pressing right now?',
    'Great question! Quick calming techniques can be really valuable. Deep breathing, the 5-4-3-2-1 grounding exercise, or even a brief walk can help. Would you like to try one together?'
  ];

BEGIN
  -- Temporarily disable the challenge progress trigger (it references a non-existent column)
  ALTER TABLE exercise_sessions DISABLE TRIGGER trigger_exercise_to_challenge_progress;

  -- Get user_id for b@gmail.com
  SELECT id INTO v_user_id FROM auth.users WHERE email = 'b@gmail.com' LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE NOTICE 'User b@gmail.com not found. Skipping mock data generation.';
    -- Re-enable trigger before returning
    ALTER TABLE exercise_sessions ENABLE TRIGGER trigger_exercise_to_challenge_progress;
    RETURN;
  END IF;

  RAISE NOTICE 'Generating mock data for user %', v_user_id;

  -- Get quest template IDs (select a few different ones)
  SELECT ARRAY_AGG(id) INTO v_quest_templates
  FROM (
    SELECT id FROM quest_templates
    WHERE title IN ('Box Breathing', 'Mindful Walk', 'Gratitude List', 'Appreciation Message', 'Morning Stretch', 'Single-Task Focus')
    LIMIT 6
  ) sq;

  -- Fallback: if no templates found, try to get any templates
  IF v_quest_templates IS NULL OR array_length(v_quest_templates, 1) IS NULL THEN
    SELECT ARRAY_AGG(id) INTO v_quest_templates FROM (SELECT id FROM quest_templates LIMIT 6) sq;
  END IF;

  -- Get exercise IDs
  SELECT ARRAY_AGG(id) INTO v_exercises
  FROM (
    SELECT id FROM exercises
    WHERE title IN ('4-7-8 Relaxing Breath', 'Loving Kindness', 'Body Scan Meditation', '5-4-3-2-1 Senses', 'Breath Awareness', 'Mindful Awareness')
    LIMIT 6
  ) sq;

  -- Fallback: if no exercises found, try to get any exercises
  IF v_exercises IS NULL OR array_length(v_exercises, 1) IS NULL THEN
    SELECT ARRAY_AGG(id) INTO v_exercises FROM (SELECT id FROM exercises LIMIT 6) sq;
  END IF;

  -- Clear existing data for this user (idempotent)
  DELETE FROM messages WHERE conversation_id IN (SELECT id FROM conversations WHERE user_id = v_user_id);
  DELETE FROM conversations WHERE user_id = v_user_id;
  DELETE FROM moods WHERE user_id = v_user_id;
  DELETE FROM quests WHERE user_id = v_user_id;
  DELETE FROM exercise_sessions WHERE user_id = v_user_id;
  DELETE FROM user_badges_v2 WHERE user_id = v_user_id;

  RAISE NOTICE 'Cleared existing data. Generating 35 days of activity...';

  -- Generate 35 days of data (5 weeks)
  FOR i IN 0..34 LOOP
    v_day := CURRENT_DATE - (34 - i);
    v_day_of_week := EXTRACT(DOW FROM v_day)::INT;  -- 0=Sunday, 1=Monday, etc.
    v_week_num := (i / 7) + 1;  -- Week 1-5

    -- Base mood improves over time (simulating user progress on 1-10 scale)
    -- Week 1: 3.5, Week 2: 4.5, Week 3: 5.5, Week 4: 6.2, Week 5+: 6.8
    v_base_mood := 3.5 + (v_week_num - 1) * 0.85;

    -- Day of week adjustment (Monday blues, Friday high)
    CASE v_day_of_week
      WHEN 1 THEN v_base_mood := v_base_mood - 0.8;  -- Monday: lower
      WHEN 5 THEN v_base_mood := v_base_mood + 0.6;  -- Friday: higher
      WHEN 0, 6 THEN v_base_mood := v_base_mood + 0.4;  -- Weekend: slightly higher
      ELSE NULL;
    END CASE;

    -- Determine if exercise today (more likely in later weeks)
    v_did_exercise := random() < (0.25 + v_week_num * 0.08);

    -- If exercise, boost mood and record session
    IF v_did_exercise AND v_exercises IS NOT NULL AND array_length(v_exercises, 1) > 0 THEN
      v_base_mood := v_base_mood + 0.5;
      v_exercise_hour := 7 + floor(random() * 4)::INT;  -- 7-10 AM
      v_exercise_idx := 1 + floor(random() * array_length(v_exercises, 1))::INT;

      -- Ensure index is within bounds
      IF v_exercise_idx > array_length(v_exercises, 1) THEN
        v_exercise_idx := array_length(v_exercises, 1);
      END IF;

      INSERT INTO exercise_sessions (user_id, exercise_id, started_at, ended_at, completed, rating, note, created_at)
      VALUES (
        v_user_id,
        v_exercises[v_exercise_idx],
        (v_day + (v_exercise_hour || ' hours')::INTERVAL)::TIMESTAMPTZ,
        (v_day + ((v_exercise_hour * 60 + 5 + floor(random() * 15)::INT) || ' minutes')::INTERVAL)::TIMESTAMPTZ,
        true,
        3 + floor(random() * 3)::INT,  -- Rating 3-5
        v_exercise_notes[1 + floor(random() * array_length(v_exercise_notes, 1))::INT],
        (v_day + (v_exercise_hour || ' hours')::INTERVAL)::TIMESTAMPTZ
      );
    END IF;

    -- Clamp mood to valid range (1-10) and add randomness
    v_mood_score := LEAST(10, GREATEST(1, round(v_base_mood + (random() * 2 - 1))::INT));
    v_anxiety_score := LEAST(10, GREATEST(1, round(10 - v_base_mood + (random() * 2 - 1))::INT));  -- Inverse of mood
    v_energy_score := LEAST(10, GREATEST(1, round(v_base_mood - 1 + (random() * 2))::INT));

    -- Insert daily mood
    INSERT INTO moods (user_id, local_date, mood_score, anxiety_score, energy_score, note, created_at)
    VALUES (
      v_user_id,
      v_day,
      v_mood_score,
      v_anxiety_score,
      v_energy_score,
      v_mood_notes[1 + floor(random() * array_length(v_mood_notes, 1))::INT],
      (v_day + '9 hours'::INTERVAL + (random() * 4 || ' hours')::INTERVAL)::TIMESTAMPTZ
    )
    ON CONFLICT (user_id, local_date) DO NOTHING;

    -- Quest assignment and completion
    IF v_quest_templates IS NOT NULL AND array_length(v_quest_templates, 1) > 0 THEN
      v_template_idx := 1 + floor(random() * array_length(v_quest_templates, 1))::INT;

      -- Ensure index is within bounds
      IF v_template_idx > array_length(v_quest_templates, 1) THEN
        v_template_idx := array_length(v_quest_templates, 1);
      END IF;

      -- Completion rate improves over weeks: 60% -> 70% -> 80% -> 88% -> 92%
      v_completed := random() < (0.6 + (v_week_num - 1) * 0.08);

      -- Skip some days in week 1 (user getting started)
      IF v_week_num = 1 AND random() < 0.2 THEN
        CONTINUE;
      END IF;

      INSERT INTO quests (user_id, template_id, local_date, status, assigned_at, completed_at, reflection_note, rating, created_at)
      VALUES (
        v_user_id,
        v_quest_templates[v_template_idx],
        v_day::TEXT,
        CASE WHEN v_completed THEN 'completed' ELSE 'assigned' END,
        (v_day + '6 hours'::INTERVAL)::TIMESTAMPTZ,
        CASE WHEN v_completed THEN (v_day + (8 + floor(random() * 10)::INT || ' hours')::INTERVAL)::TIMESTAMPTZ ELSE NULL END,
        CASE WHEN v_completed THEN v_quest_notes[1 + floor(random() * array_length(v_quest_notes, 1))::INT] ELSE NULL END,
        CASE WHEN v_completed THEN 3 + floor(random() * 3)::INT ELSE NULL END,
        (v_day + '6 hours'::INTERVAL)::TIMESTAMPTZ
      )
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;

  RAISE NOTICE 'Generated daily activity. Creating conversations...';

  -- Create 4 conversations with messages spread over the period
  FOR i IN 1..4 LOOP
    v_conv_id := gen_random_uuid();

    INSERT INTO conversations (id, user_id, title, created_at, updated_at)
    VALUES (
      v_conv_id,
      v_user_id,
      CASE i
        WHEN 1 THEN 'Dealing with work stress'
        WHEN 2 THEN 'Improving my sleep'
        WHEN 3 THEN 'Building better habits'
        WHEN 4 THEN 'Managing overwhelm'
      END,
      (CURRENT_DATE - (35 - i * 8) + '14 hours'::INTERVAL)::TIMESTAMPTZ,
      (CURRENT_DATE - (35 - i * 8) + '15 hours'::INTERVAL)::TIMESTAMPTZ
    );

    -- Add user message
    INSERT INTO messages (conversation_id, role, content, created_at)
    VALUES (
      v_conv_id,
      'user',
      v_user_messages[i],
      (CURRENT_DATE - (35 - i * 8) + '14 hours'::INTERVAL)::TIMESTAMPTZ
    );

    -- Add AI response
    INSERT INTO messages (conversation_id, role, content, created_at)
    VALUES (
      v_conv_id,
      'assistant',
      v_ai_responses[i],
      (CURRENT_DATE - (35 - i * 8) + '14 hours 30 seconds'::INTERVAL)::TIMESTAMPTZ
    );

    -- Add follow-up exchange for some conversations
    IF i <= 2 THEN
      INSERT INTO messages (conversation_id, role, content, created_at)
      VALUES (
        v_conv_id,
        'user',
        CASE i WHEN 1 THEN 'Deadlines and too many meetings' ELSE 'I often wake up at 3am and can''t fall back asleep' END,
        (CURRENT_DATE - (35 - i * 8) + '14 hours 2 minutes'::INTERVAL)::TIMESTAMPTZ
      );

      INSERT INTO messages (conversation_id, role, content, created_at)
      VALUES (
        v_conv_id,
        'assistant',
        CASE i
          WHEN 1 THEN 'Meeting overload is exhausting! Have you tried time-blocking your calendar to protect focus time? Even 30-minute blocks can help. What times of day do you feel most productive?'
          ELSE 'Middle-of-the-night waking is common. It could be related to stress, caffeine, or sleep environment. When did this pattern start? And what usually goes through your mind when you wake up?'
        END,
        (CURRENT_DATE - (35 - i * 8) + '14 hours 2 minutes 30 seconds'::INTERVAL)::TIMESTAMPTZ
      );
    END IF;
  END LOOP;

  RAISE NOTICE 'Created conversations. Awarding badges...';

  -- Award badges based on activity (using slugs to find badge IDs)
  -- First quest badge
  SELECT id INTO v_badge_id FROM badges_v2 WHERE slug = 'first_quest' LIMIT 1;
  IF v_badge_id IS NOT NULL THEN
    INSERT INTO user_badges_v2 (user_id, badge_id, is_earned, earned_at, progress_current, progress_target)
    VALUES (v_user_id, v_badge_id, true, CURRENT_DATE - 34, 1, 1)
    ON CONFLICT DO NOTHING;
  END IF;

  -- First mood badge
  SELECT id INTO v_badge_id FROM badges_v2 WHERE slug = 'first_mood' LIMIT 1;
  IF v_badge_id IS NOT NULL THEN
    INSERT INTO user_badges_v2 (user_id, badge_id, is_earned, earned_at, progress_current, progress_target)
    VALUES (v_user_id, v_badge_id, true, CURRENT_DATE - 34, 1, 1)
    ON CONFLICT DO NOTHING;
  END IF;

  -- First exercise badge
  SELECT id INTO v_badge_id FROM badges_v2 WHERE slug = 'first_exercise' LIMIT 1;
  IF v_badge_id IS NOT NULL THEN
    INSERT INTO user_badges_v2 (user_id, badge_id, is_earned, earned_at, progress_current, progress_target)
    VALUES (v_user_id, v_badge_id, true, CURRENT_DATE - 32, 1, 1)
    ON CONFLICT DO NOTHING;
  END IF;

  -- 10 quests badge
  SELECT id INTO v_badge_id FROM badges_v2 WHERE slug = 'quests_10' LIMIT 1;
  IF v_badge_id IS NOT NULL THEN
    INSERT INTO user_badges_v2 (user_id, badge_id, is_earned, earned_at, progress_current, progress_target)
    VALUES (v_user_id, v_badge_id, true, CURRENT_DATE - 22, 10, 10)
    ON CONFLICT DO NOTHING;
  END IF;

  -- 25 quests badge
  SELECT id INTO v_badge_id FROM badges_v2 WHERE slug = 'quests_25' LIMIT 1;
  IF v_badge_id IS NOT NULL THEN
    INSERT INTO user_badges_v2 (user_id, badge_id, is_earned, earned_at, progress_current, progress_target)
    VALUES (v_user_id, v_badge_id, true, CURRENT_DATE - 5, 25, 25)
    ON CONFLICT DO NOTHING;
  END IF;

  -- 10 moods badge
  SELECT id INTO v_badge_id FROM badges_v2 WHERE slug = 'moods_10' LIMIT 1;
  IF v_badge_id IS NOT NULL THEN
    INSERT INTO user_badges_v2 (user_id, badge_id, is_earned, earned_at, progress_current, progress_target)
    VALUES (v_user_id, v_badge_id, true, CURRENT_DATE - 25, 10, 10)
    ON CONFLICT DO NOTHING;
  END IF;

  -- 30 moods badge
  SELECT id INTO v_badge_id FROM badges_v2 WHERE slug = 'moods_30' LIMIT 1;
  IF v_badge_id IS NOT NULL THEN
    INSERT INTO user_badges_v2 (user_id, badge_id, is_earned, earned_at, progress_current, progress_target)
    VALUES (v_user_id, v_badge_id, true, CURRENT_DATE - 3, 30, 30)
    ON CONFLICT DO NOTHING;
  END IF;

  -- 7-day streak badge
  SELECT id INTO v_badge_id FROM badges_v2 WHERE slug = 'streak_7' LIMIT 1;
  IF v_badge_id IS NOT NULL THEN
    INSERT INTO user_badges_v2 (user_id, badge_id, is_earned, earned_at, progress_current, progress_target)
    VALUES (v_user_id, v_badge_id, true, CURRENT_DATE - 28, 7, 7)
    ON CONFLICT DO NOTHING;
  END IF;

  -- 14-day streak badge
  SELECT id INTO v_badge_id FROM badges_v2 WHERE slug = 'streak_14' LIMIT 1;
  IF v_badge_id IS NOT NULL THEN
    INSERT INTO user_badges_v2 (user_id, badge_id, is_earned, earned_at, progress_current, progress_target)
    VALUES (v_user_id, v_badge_id, true, CURRENT_DATE - 21, 14, 14)
    ON CONFLICT DO NOTHING;
  END IF;

  -- 30-day streak badge
  SELECT id INTO v_badge_id FROM badges_v2 WHERE slug = 'streak_30' LIMIT 1;
  IF v_badge_id IS NOT NULL THEN
    INSERT INTO user_badges_v2 (user_id, badge_id, is_earned, earned_at, progress_current, progress_target)
    VALUES (v_user_id, v_badge_id, true, CURRENT_DATE - 4, 30, 30)
    ON CONFLICT DO NOTHING;
  END IF;

  -- 10 exercises badge
  SELECT id INTO v_badge_id FROM badges_v2 WHERE slug = 'exercises_10' LIMIT 1;
  IF v_badge_id IS NOT NULL THEN
    INSERT INTO user_badges_v2 (user_id, badge_id, is_earned, earned_at, progress_current, progress_target)
    VALUES (v_user_id, v_badge_id, true, CURRENT_DATE - 10, 10, 10)
    ON CONFLICT DO NOTHING;
  END IF;

  RAISE NOTICE 'Badges awarded. Updating profile and stats...';

  -- Update user profile with stats and settings
  UPDATE profiles
  SET
    current_streak_days = 30,
    longest_streak_days = 30,
    total_quests_completed = 28,
    total_exercises_completed = 18,
    timezone = 'America/Los_Angeles',
    display_name = COALESCE(display_name, 'Beta Tester'),
    wellness_focus = 'stress',
    onboarding_completed_at = COALESCE(onboarding_completed_at, CURRENT_DATE - 35),
    ai_tone = 'friendly',
    daily_quest_time_local = '09:00:00',
    reminders_enabled = true,
    last_session_at = NOW(),
    session_count = COALESCE(session_count, 0) + 45
  WHERE id = v_user_id;

  -- Update user_stats
  INSERT INTO user_stats (user_id, current_streak_days, longest_streak_days, total_quests_completed, total_exercises_completed, xp_total, xp_this_week, level, level_title, last_quest_date)
  VALUES (
    v_user_id,
    30,
    30,
    28,
    18,
    1850,  -- XP from quests + exercises + badges
    320,   -- This week's XP
    4,     -- Level 4
    'Practitioner',
    CURRENT_DATE::TEXT
  )
  ON CONFLICT (user_id) DO UPDATE SET
    current_streak_days = 30,
    longest_streak_days = 30,
    total_quests_completed = 28,
    total_exercises_completed = 18,
    xp_total = 1850,
    xp_this_week = 320,
    level = 4,
    level_title = 'Practitioner',
    last_quest_date = CURRENT_DATE::TEXT;

  RAISE NOTICE 'Mock data generation complete for user b@gmail.com!';
  RAISE NOTICE 'Generated: 35 moods, ~28 quests, ~18 exercises, 4 conversations, 11 badges';

  -- Re-enable the trigger
  ALTER TABLE exercise_sessions ENABLE TRIGGER trigger_exercise_to_challenge_progress;

END $$;
