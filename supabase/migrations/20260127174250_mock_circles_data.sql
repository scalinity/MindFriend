-- Mock Circles Data for App Store Screenshots
-- Uses b@gmail.com as the primary user
-- Creates a circle with posts from the user to demonstrate features

DO $$
DECLARE
    v_user_id UUID;
    v_circle_id UUID;
    v_post1_id UUID;
    v_post2_id UUID;
    v_post3_id UUID;
BEGIN
    -- Get the user ID for b@gmail.com
    SELECT id INTO v_user_id FROM auth.users WHERE email = 'b@gmail.com';

    IF v_user_id IS NULL THEN
        RAISE NOTICE 'User b@gmail.com not found, skipping mock data';
        RETURN;
    END IF;

    -- Check if we already have mock data
    IF EXISTS (SELECT 1 FROM circles WHERE invite_code = 'DEMO01') THEN
        RAISE NOTICE 'Mock data already exists, skipping';
        RETURN;
    END IF;

    -- Create the demo circle
    INSERT INTO circles (id, name, description, invite_code, owner_id, created_at)
    VALUES (
        gen_random_uuid(),
        'Wellness Warriors',
        'Supporting each other on our mental health journey',
        'DEMO01',
        v_user_id,
        NOW() - INTERVAL '14 days'
    )
    RETURNING id INTO v_circle_id;

    -- Add user as owner of the circle
    INSERT INTO circle_members (circle_id, user_id, role, joined_at)
    VALUES (v_circle_id, v_user_id, 'owner', NOW() - INTERVAL '14 days');

    -- Create check-in posts showing a week of activity
    -- Post 1: Morning meditation
    INSERT INTO circle_posts (id, circle_id, user_id, kind, post_type, mood_emoji, body_text, local_date, created_at)
    VALUES (
        gen_random_uuid(),
        v_circle_id,
        v_user_id,
        'checkin',
        'checkin',
        '😊',
        'Started my day with a 10-minute meditation. Feeling centered and ready for whatever comes!',
        CURRENT_DATE::text,
        NOW() - INTERVAL '2 hours'
    )
    RETURNING id INTO v_post1_id;

    -- Post 2: Afternoon reflection
    INSERT INTO circle_posts (id, circle_id, user_id, kind, post_type, mood_emoji, body_text, local_date, created_at)
    VALUES (
        gen_random_uuid(),
        v_circle_id,
        v_user_id,
        'checkin',
        'checkin',
        '💪',
        'Completed my daily quest and hit a 7-day streak! Small consistent steps are adding up.',
        (CURRENT_DATE - INTERVAL '1 day')::date::text,
        NOW() - INTERVAL '26 hours'
    )
    RETURNING id INTO v_post2_id;

    -- Post 3: Evening gratitude
    INSERT INTO circle_posts (id, circle_id, user_id, kind, post_type, mood_emoji, body_text, local_date, created_at)
    VALUES (
        gen_random_uuid(),
        v_circle_id,
        v_user_id,
        'checkin',
        'checkin',
        '😌',
        'Grateful for taking time to focus on my mental health. The breathing exercises really helped today.',
        (CURRENT_DATE - INTERVAL '2 days')::date::text,
        NOW() - INTERVAL '50 hours'
    )
    RETURNING id INTO v_post3_id;

    -- Create a scheduled ritual for the circle
    INSERT INTO circle_rituals (circle_id, created_by, title, ritual_type, scheduled_for, duration_seconds, status, created_at)
    VALUES (
        v_circle_id,
        v_user_id,
        'Evening Gratitude Circle',
        'gratitude',
        (CURRENT_DATE + INTERVAL '1 day' + INTERVAL '18 hours')::timestamptz,
        300,
        'scheduled',
        NOW()
    );

    RAISE NOTICE 'Mock circles data created successfully for user %', v_user_id;
END $$;
