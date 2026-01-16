-- Spec 11: Family Wellness - Content Age Ratings Seed
-- Populates content_age_ratings table for 45 exercises and templates

-- =============================================================================
-- MARK: - Seed Exercise Age Ratings (45 exercises)
-- =============================================================================

-- Default all exercises to adult (18+) - conservative approach
-- Only run if exercises table exists with duration_seconds column
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_name = 'exercises'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns WHERE table_name = 'exercises' AND column_name = 'duration_seconds'
  ) THEN
    INSERT INTO content_age_ratings (content_type, content_id, minimum_age, rating_category, requires_reading, complexity_level)
    SELECT DISTINCT
        'exercise',
        id,
        18,
        'adult',
        CASE WHEN type = 'journaling' THEN true ELSE false END,
        CASE
            WHEN COALESCE(duration_seconds, 0) <= 180 THEN 'simple'
            WHEN COALESCE(duration_seconds, 0) <= 420 THEN 'moderate'
            ELSE 'complex'
        END
    FROM exercises
    ON CONFLICT (content_type, content_id) DO NOTHING;
  END IF;
END $$;

-- Tag breathing exercises as all ages (4+) - only if exercises table exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'exercises') THEN
    UPDATE content_age_ratings
    SET minimum_age = 4, rating_category = 'all_ages', contains_heavy_topics = false, complexity_level = 'simple'
    WHERE content_type = 'exercise' AND content_id IN (
        SELECT id FROM exercises WHERE
            type = 'breathing' AND
            title NOT IN ('4-7-8 Relaxing Breath - Advanced', 'Wim Hof Method')
    );
  END IF;
END $$;

-- Tag grounding exercises as all ages (4+) for simple ones - only if exercises table exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_name = 'exercises'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns WHERE table_name = 'exercises' AND column_name = 'duration_seconds'
  ) THEN
    UPDATE content_age_ratings
    SET minimum_age = 4, rating_category = 'all_ages', contains_heavy_topics = false, complexity_level = 'simple'
    WHERE content_type = 'exercise' AND content_id IN (
        SELECT id FROM exercises WHERE
            type = 'grounding' AND
            (title LIKE '%Senses%' OR title LIKE '%Feet%' OR title LIKE '%Object%') AND
            COALESCE(duration_seconds, 0) <= 300
    );
  END IF;
END $$;

-- Tag simple movement exercises as kids (6+) - only if exercises table exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_name = 'exercises'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns WHERE table_name = 'exercises' AND column_name = 'duration_seconds'
  ) THEN
    UPDATE content_age_ratings
    SET minimum_age = 6, rating_category = 'kids', contains_heavy_topics = false, complexity_level = 'simple'
    WHERE content_type = 'exercise' AND content_id IN (
        SELECT id FROM exercises WHERE
            type = 'movement' AND
            COALESCE(duration_seconds, 0) <= 300 AND
            title NOT LIKE '%Advanced%' AND
            title NOT LIKE '%Complex%'
    );
  END IF;
END $$;

-- Tag guided meditation basics as kids (6+) - only if exercises table exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_name = 'exercises'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns WHERE table_name = 'exercises' AND column_name = 'duration_seconds'
  ) THEN
    UPDATE content_age_ratings
    SET minimum_age = 6, rating_category = 'kids', contains_heavy_topics = false, complexity_level = 'simple'
    WHERE content_type = 'exercise' AND content_id IN (
        SELECT id FROM exercises WHERE
            type = 'meditation' AND
            COALESCE(duration_seconds, 0) <= 300 AND
            (title LIKE '%Breath%' OR title LIKE '%Basic%' OR title LIKE '%Simple%' OR title LIKE '%Children%')
    );
  END IF;
END $$;

-- Tag moderate exercises as teens (13+) - only if exercises table exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_name = 'exercises'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns WHERE table_name = 'exercises' AND column_name = 'duration_seconds'
  ) THEN
    UPDATE content_age_ratings
    SET minimum_age = 13, rating_category = 'teen', contains_heavy_topics = false, complexity_level = 'moderate'
    WHERE content_type = 'exercise' AND content_id IN (
        SELECT id FROM exercises WHERE
            type IN ('meditation', 'journaling') AND
            COALESCE(duration_seconds, 0) BETWEEN 300 AND 600
    );
  END IF;
END $$;

-- Mark exercises with heavy/difficult topics as adult only - only if exercises table exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'exercises') THEN
    UPDATE content_age_ratings
    SET minimum_age = 18, rating_category = 'adult', contains_heavy_topics = true, complexity_level = 'complex'
    WHERE content_type = 'exercise' AND content_id IN (
        SELECT id FROM exercises WHERE
            title IN (
                'Worry Dump',
                'Processing Difficult Emotions',
                'Trauma-Informed Grounding',
                'Anxiety Release',
                'Panic Management',
                'Grief Processing'
            )
    );
  END IF;
END $$;

-- =============================================================================
-- MARK: - Seed Together Template Age Ratings
-- =============================================================================

-- Together templates - meditation (all ages) - only if together_templates table exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'together_templates') THEN
    INSERT INTO content_age_ratings (content_type, content_id, minimum_age, rating_category, contains_heavy_topics, complexity_level)
    SELECT DISTINCT
        'together_template',
        id,
        4,
        'all_ages',
        false,
        'simple'
    FROM together_templates
    WHERE category = 'meditation' AND duration_minutes <= 10
    ON CONFLICT (content_type, content_id) DO NOTHING;
  END IF;
END $$;

-- Together templates - gratitude (kids, 6+) - only if together_templates table exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'together_templates') THEN
    INSERT INTO content_age_ratings (content_type, content_id, minimum_age, rating_category, contains_heavy_topics, complexity_level)
    SELECT DISTINCT
        'together_template',
        id,
        6,
        'kids',
        false,
        'simple'
    FROM together_templates
    WHERE category = 'gratitude'
    ON CONFLICT (content_type, content_id) DO NOTHING;
  END IF;
END $$;

-- Together templates - breathing (all ages) - only if together_templates table exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'together_templates') THEN
    INSERT INTO content_age_ratings (content_type, content_id, minimum_age, rating_category, contains_heavy_topics, complexity_level)
    SELECT DISTINCT
        'together_template',
        id,
        4,
        'all_ages',
        false,
        'simple'
    FROM together_templates
    WHERE category = 'breathing'
    ON CONFLICT (content_type, content_id) DO NOTHING;
  END IF;
END $$;

-- Together templates - check-in (teens, 13+) - only if together_templates table exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'together_templates') THEN
    INSERT INTO content_age_ratings (content_type, content_id, minimum_age, rating_category, contains_heavy_topics, complexity_level)
    SELECT DISTINCT
        'together_template',
        id,
        13,
        'teen',
        false,
        'moderate'
    FROM together_templates
    WHERE category = 'checkin'
    ON CONFLICT (content_type, content_id) DO NOTHING;
  END IF;
END $$;

-- Together templates - movement (kids, 6+) - only if together_templates table exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'together_templates') THEN
    INSERT INTO content_age_ratings (content_type, content_id, minimum_age, rating_category, contains_heavy_topics, complexity_level)
    SELECT DISTINCT
        'together_template',
        id,
        6,
        'kids',
        false,
        'simple'
    FROM together_templates
    WHERE category = 'movement'
    ON CONFLICT (content_type, content_id) DO NOTHING;
  END IF;
END $$;

-- Default any remaining together templates to teen (13+) - only if together_templates table exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'together_templates') THEN
    INSERT INTO content_age_ratings (content_type, content_id, minimum_age, rating_category, contains_heavy_topics, complexity_level)
    SELECT DISTINCT
        'together_template',
        id,
        13,
        'teen',
        false,
        'simple'
    FROM together_templates
    WHERE NOT EXISTS (
        SELECT 1 FROM content_age_ratings
        WHERE content_type = 'together_template' AND content_id = together_templates.id
    )
    ON CONFLICT (content_type, content_id) DO NOTHING;
  END IF;
END $$;
