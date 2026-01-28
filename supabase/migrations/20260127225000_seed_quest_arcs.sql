-- Seed initial quest arcs for each category
INSERT INTO quest_arcs (id, title, description, category, duration_days, difficulty_level, is_premium, milestone_days, icon_name, is_active)
VALUES
  -- Stress category
  (gen_random_uuid(), 'Stress Relief Starter', 'Learn foundational techniques to manage daily stress through breathing and mindfulness.', 'stress', 7, 'easy', false, ARRAY[3, 7], 'brain.head.profile', true),
  (gen_random_uuid(), 'Deep Calm Journey', 'Master advanced relaxation techniques and build lasting stress resilience.', 'stress', 14, 'medium', false, ARRAY[5, 10, 14], 'wind', true),
  (gen_random_uuid(), 'Stress Mastery Program', 'Comprehensive 21-day program to transform your relationship with stress.', 'stress', 21, 'hard', true, ARRAY[7, 14, 21], 'sparkles', true),

  -- Sleep category
  (gen_random_uuid(), 'Better Sleep Basics', 'Establish healthy sleep habits with simple evening routines.', 'sleep', 7, 'easy', false, ARRAY[3, 7], 'moon.zzz.fill', true),
  (gen_random_uuid(), 'Sleep Optimization', 'Fine-tune your sleep environment and routines for deeper rest.', 'sleep', 14, 'medium', false, ARRAY[5, 10, 14], 'bed.double.fill', true),
  (gen_random_uuid(), 'Sleep Transformation', 'Complete overhaul of your sleep patterns for lasting change.', 'sleep', 21, 'hard', true, ARRAY[7, 14, 21], 'moon.stars.fill', true),

  -- Confidence category
  (gen_random_uuid(), 'Confidence Kickstart', 'Build self-belief through daily affirmations and small wins.', 'confidence', 7, 'easy', false, ARRAY[3, 7], 'star.fill', true),
  (gen_random_uuid(), 'Inner Strength Builder', 'Develop unshakeable confidence through proven exercises.', 'confidence', 14, 'medium', false, ARRAY[5, 10, 14], 'figure.stand', true),
  (gen_random_uuid(), 'Confidence Mastery', 'Transform self-doubt into unstoppable self-assurance.', 'confidence', 21, 'hard', true, ARRAY[7, 14, 21], 'crown.fill', true),

  -- Focus category
  (gen_random_uuid(), 'Focus Foundations', 'Learn attention training basics to improve concentration.', 'focus', 7, 'easy', false, ARRAY[3, 7], 'scope', true),
  (gen_random_uuid(), 'Deep Focus Training', 'Build sustained attention through progressive exercises.', 'focus', 14, 'medium', false, ARRAY[5, 10, 14], 'target', true),
  (gen_random_uuid(), 'Peak Performance Focus', 'Achieve flow states and peak mental performance.', 'focus', 21, 'hard', true, ARRAY[7, 14, 21], 'bolt.fill', true),

  -- Resilience category
  (gen_random_uuid(), 'Resilience Starter', 'Build mental toughness through daily resilience practices.', 'resilience', 7, 'easy', false, ARRAY[3, 7], 'shield.fill', true),
  (gen_random_uuid(), 'Bounce Back Stronger', 'Develop the ability to recover quickly from setbacks.', 'resilience', 14, 'medium', false, ARRAY[5, 10, 14], 'arrow.counterclockwise', true),
  (gen_random_uuid(), 'Unbreakable Mind', 'Forge an unshakeable mindset that thrives under pressure.', 'resilience', 21, 'hard', true, ARRAY[7, 14, 21], 'mountain.2.fill', true)
ON CONFLICT DO NOTHING;
