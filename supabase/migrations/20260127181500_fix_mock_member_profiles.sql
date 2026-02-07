-- Fix: Create profiles for mock circle members that are missing them

DO $$
DECLARE
    v_main_user_id UUID;
    v_circle_id UUID;
    v_member RECORD;
    v_member_count INT := 0;
    v_mock_names TEXT[] := ARRAY['Sarah', 'Mike', 'Emma', 'Alex'];
BEGIN
    -- Get the main user ID for beta-tester@example.com
    SELECT id INTO v_main_user_id FROM auth.users WHERE email = 'beta-tester@example.com';

    IF v_main_user_id IS NULL THEN
        RAISE NOTICE 'User beta-tester@example.com not found, skipping';
        RETURN;
    END IF;

    -- Get the demo circle
    SELECT id INTO v_circle_id FROM circles WHERE invite_code = 'DEMO01';

    IF v_circle_id IS NULL THEN
        RAISE NOTICE 'Demo circle not found, skipping';
        RETURN;
    END IF;

    -- Find circle members without profiles and create profiles for them
    FOR v_member IN
        SELECT cm.user_id
        FROM circle_members cm
        LEFT JOIN profiles p ON p.id = cm.user_id
        WHERE cm.circle_id = v_circle_id
          AND cm.user_id != v_main_user_id
          AND p.id IS NULL
    LOOP
        -- Create profile for this user
        INSERT INTO profiles (id, display_name, created_at, updated_at)
        VALUES (
            v_member.user_id,
            v_mock_names[v_member_count + 1],
            NOW(),
            NOW()
        )
        ON CONFLICT (id) DO NOTHING;

        v_member_count := v_member_count + 1;
        RAISE NOTICE 'Created profile for member: %', v_mock_names[v_member_count];
    END LOOP;

    RAISE NOTICE 'Created % profiles for circle members', v_member_count;
END $$;
