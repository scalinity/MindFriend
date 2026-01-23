-- Sensory Regulation Toolkit Achievement Badge Seeds
-- Inserts the 5 badges for sensory toolkit usage milestones

INSERT INTO badges (id, code, title, description, icon_name, category)
VALUES
    (
        gen_random_uuid(),
        'sensory_first_session',
        '🌟 First Steps',
        'Complete your first sensory session',
        '🌟',
        'getting_started'
    ),
    (
        gen_random_uuid(),
        'sensory_ten_sessions',
        '💫 Regular Practice',
        'Complete 10 sensory sessions',
        '💫',
        'milestones'
    ),
    (
        gen_random_uuid(),
        'sensory_all_modalities',
        '🎨 Sensory Explorer',
        'Try all three modalities (tactile, visual, audio)',
        '🎨',
        'exploration'
    ),
    (
        gen_random_uuid(),
        'sensory_thirty_minute',
        '⏳ Deep Focus',
        'Complete a 30-minute sensory session',
        '⏳',
        'endurance'
    ),
    (
        gen_random_uuid(),
        'sensory_seven_day_streak',
        '🔥 Consistency Champion',
        'Use the toolkit for 7 days in a row',
        '🔥',
        'streaks'
    )
ON CONFLICT (code) DO NOTHING;
