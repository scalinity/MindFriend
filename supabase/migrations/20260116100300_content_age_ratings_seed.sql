-- Spec 11: Family Wellness - Content Age Ratings Seed
-- Populates content_age_ratings table for 45 exercises and templates

-- =============================================================================
-- MARK: - Seed Exercise Age Ratings (45 exercises)
-- =============================================================================

-- Default all exercises to adult (18+) - conservative approach
INSERT INTO content_age_ratings (content_type, content_id, minimum_age, rating_category, requires_reading, complexity_level)
SELECT DISTINCT
    'exercise',
    id,
    18,
    'adult',
    CASE WHEN type = 'journaling' THEN true ELSE false END,
    CASE
        WHEN duration_seconds <= 180 THEN 'simple'
        WHEN duration_seconds <= 420 THEN 'moderate'
        ELSE 'complex'
    END
FROM exercises
ON CONFLICT (content_type, content_id) DO NOTHING;

-- Tag breathing exercises as all ages (4+)
UPDATE content_age_ratings
SET minimum_age = 4, rating_category = 'all_ages', contains_heavy_topics = false, complexity_level = 'simple'
WHERE content_type = 'exercise' AND content_id IN (
    SELECT id FROM exercises WHERE
        type = 'breathing' AND
        title NOT IN ('4-7-8 Relaxing Breath - Advanced', 'Wim Hof Method')
);

-- Tag grounding exercises as all ages (4+) for simple ones
UPDATE content_age_ratings
SET minimum_age = 4, rating_category = 'all_ages', contains_heavy_topics = false, complexity_level = 'simple'
WHERE content_type = 'exercise' AND content_id IN (
    SELECT id FROM exercises WHERE
        type = 'grounding' AND
        (title LIKE '%Senses%' OR title LIKE '%Feet%' OR title LIKE '%Object%') AND
        duration_seconds <= 300
);

-- Tag simple movement exercises as kids (6+)
UPDATE content_age_ratings
SET minimum_age = 6, rating_category = 'kids', contains_heavy_topics = false, complexity_level = 'simple'
WHERE content_type = 'exercise' AND content_id IN (
    SELECT id FROM exercises WHERE
        type = 'movement' AND
        duration_seconds <= 300 AND
        title NOT LIKE '%Advanced%' AND
        title NOT LIKE '%Complex%'
);

-- Tag guided meditation basics as kids (6+)
UPDATE content_age_ratings
SET minimum_age = 6, rating_category = 'kids', contains_heavy_topics = false, complexity_level = 'simple'
WHERE content_type = 'exercise' AND content_id IN (
    SELECT id FROM exercises WHERE
        type = 'meditation' AND
        duration_seconds <= 300 AND
        (title LIKE '%Breath%' OR title LIKE '%Basic%' OR title LIKE '%Simple%' OR title LIKE '%Children%')
);

-- Tag moderate exercises as teens (13+)
UPDATE content_age_ratings
SET minimum_age = 13, rating_category = 'teen', contains_heavy_topics = false, complexity_level = 'moderate'
WHERE content_type = 'exercise' AND content_id IN (
    SELECT id FROM exercises WHERE
        type IN ('meditation', 'journaling') AND
        duration_seconds BETWEEN 300 AND 600
);

-- Mark exercises with heavy/difficult topics as adult only
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

-- =============================================================================
-- MARK: - Seed Together Template Age Ratings
-- =============================================================================

-- Together templates - meditation (all ages)
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

-- Together templates - gratitude (kids, 6+)
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

-- Together templates - breathing (all ages)
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

-- Together templates - check-in (teens, 13+)
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

-- Together templates - movement (kids, 6+)
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

-- Default any remaining together templates to teen (13+)
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
