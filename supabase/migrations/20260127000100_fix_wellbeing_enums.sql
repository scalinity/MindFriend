-- Fix wellbeing_transactions enum constraints to match Swift models

-- Drop old constraints and add new ones with expanded values

-- Category constraint
ALTER TABLE wellbeing_transactions DROP CONSTRAINT IF EXISTS wellbeing_transactions_category_check;
ALTER TABLE wellbeing_transactions ADD CONSTRAINT wellbeing_transactions_category_check CHECK (category IN (
  -- Deposits
  'sleep_quality', 'exercise', 'exercise_completion', 'social_connection',
  'meditation', 'outdoor_time', 'quest_completion', 'positive_event',
  -- Withdrawals
  'poor_sleep', 'missed_sleep', 'work_stress', 'conflict',
  'social_isolation', 'mood_negative', 'negative_mood', 'health_issue',
  'circadian_misalignment', 'circadian_disruption'
));

-- Source constraint
ALTER TABLE wellbeing_transactions DROP CONSTRAINT IF EXISTS wellbeing_transactions_source_check;
ALTER TABLE wellbeing_transactions ADD CONSTRAINT wellbeing_transactions_source_check CHECK (source IN (
  'healthkit', 'mood_log', 'exercise_session', 'exercise_sessions',
  'circle', 'circle_posts', 'quest', 'quests',
  'circadian_engine', 'circadian_shield', 'user_logged', 'auto_detected', 'inferred'
));
