-- Badge Seeds for Challenge Rewards
-- Inserts the 4 badges for challenge placement and completion

INSERT INTO badges (id, code, title, description, icon_name, category)
VALUES
    (
        gen_random_uuid(),
        'challenge_gold',
        '🥇 Challenge Champion',
        'Won 1st place in a challenge',
        '🥇',
        'competition'
    ),
    (
        gen_random_uuid(),
        'challenge_silver',
        '🥈 Challenge Runner-Up',
        'Won 2nd place in a challenge',
        '🥈',
        'competition'
    ),
    (
        gen_random_uuid(),
        'challenge_bronze',
        '🥉 Challenge Contender',
        'Won 3rd place in a challenge',
        '🥉',
        'competition'
    ),
    (
        gen_random_uuid(),
        'challenge_participant',
        '🎯 Challenge Participant',
        'Completed a challenge',
        '🎯',
        'participation'
    )
ON CONFLICT (code) DO NOTHING;
