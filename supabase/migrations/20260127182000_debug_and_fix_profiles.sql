-- Debug and fix profiles for mock circle members

DO $$
DECLARE
    v_main_user_id UUID;
    v_circle_id UUID;
    v_member RECORD;
    v_member_count INT := 0;
    v_mock_names TEXT[] := ARRAY['Sarah', 'Mike', 'Emma', 'Alex'];
    v_total_members INT;
BEGIN
    -- Get the main user ID for b@gmail.com
    SELECT id INTO v_main_user_id FROM auth.users WHERE email = 'b@gmail.com';

    IF v_main_user_id IS NULL THEN
        RAISE NOTICE 'User b@gmail.com not found, skipping';
        RETURN;
    END IF;

    -- Get the demo circle
    SELECT id INTO v_circle_id FROM circles WHERE invite_code = 'DEMO01';

    IF v_circle_id IS NULL THEN
        RAISE NOTICE 'Demo circle not found, skipping';
        RETURN;
    END IF;

    -- Count total members
    SELECT COUNT(*) INTO v_total_members FROM circle_members WHERE circle_id = v_circle_id;
    RAISE NOTICE 'Total members in DEMO01 circle: %', v_total_members;

    -- Loop through ALL circle members (except main user) and check/fix profiles
    FOR v_member IN
        SELECT cm.user_id, p.id as profile_id, p.display_name
        FROM circle_members cm
        LEFT JOIN profiles p ON p.id = cm.user_id
        WHERE cm.circle_id = v_circle_id
          AND cm.user_id != v_main_user_id
    LOOP
        RAISE NOTICE 'Member: %, profile_id: %, display_name: %',
            v_member.user_id,
            v_member.profile_id,
            v_member.display_name;

        -- If profile doesn't exist, create it
        IF v_member.profile_id IS NULL THEN
            INSERT INTO profiles (id, display_name, created_at, updated_at)
            VALUES (
                v_member.user_id,
                v_mock_names[v_member_count + 1],
                NOW(),
                NOW()
            );
            v_member_count := v_member_count + 1;
            RAISE NOTICE '  -> Created profile with name: %', v_mock_names[v_member_count];
        -- If profile exists but has no display_name, update it
        ELSIF v_member.display_name IS NULL OR v_member.display_name = '' THEN
            UPDATE profiles
            SET display_name = v_mock_names[v_member_count + 1],
                updated_at = NOW()
            WHERE id = v_member.user_id;
            v_member_count := v_member_count + 1;
            RAISE NOTICE '  -> Updated profile with name: %', v_mock_names[v_member_count];
        ELSE
            RAISE NOTICE '  -> Profile OK';
        END IF;
    END LOOP;

    RAISE NOTICE 'Fixed % profiles for circle members', v_member_count;
END $$;
