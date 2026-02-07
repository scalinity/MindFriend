-- Mock Circles Members & Reactions for App Store Screenshots
-- Adds other existing users as circle members and their reactions to posts

DO $$
DECLARE
    v_main_user_id UUID;
    v_circle_id UUID;
    v_other_user RECORD;
    v_post RECORD;
    v_member_count INT := 0;
    v_reaction_emojis TEXT[] := ARRAY['🎉', '👏', '💪', '❤️', '🔥'];
    v_mock_names TEXT[] := ARRAY['Sarah', 'Mike', 'Emma', 'Alex'];
    v_emoji_idx INT;
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

    -- Find other users (up to 4) and add them as members
    FOR v_other_user IN
        SELECT u.id, p.display_name
        FROM auth.users u
        LEFT JOIN profiles p ON p.id = u.id
        WHERE u.id != v_main_user_id
        LIMIT 4
    LOOP
        -- Ensure profile exists for this user (create if missing)
        INSERT INTO profiles (id, display_name, created_at, updated_at)
        VALUES (
            v_other_user.id,
            COALESCE(v_other_user.display_name, v_mock_names[v_member_count + 1]),
            NOW(),
            NOW()
        )
        ON CONFLICT (id) DO UPDATE SET
            display_name = COALESCE(profiles.display_name, EXCLUDED.display_name);

        -- Add as member if not already
        INSERT INTO circle_members (circle_id, user_id, role, joined_at)
        VALUES (v_circle_id, v_other_user.id, 'member', NOW() - INTERVAL '10 days' + (v_member_count || ' days')::interval)
        ON CONFLICT (circle_id, user_id) DO NOTHING;

        v_member_count := v_member_count + 1;
        RAISE NOTICE 'Added member: %', COALESCE(v_other_user.display_name, v_mock_names[v_member_count]);
    END LOOP;

    -- Add reactions from other members to the posts
    v_emoji_idx := 1;
    FOR v_post IN
        SELECT id FROM circle_posts
        WHERE circle_id = v_circle_id
        ORDER BY created_at DESC
    LOOP
        -- Add reactions from each other member
        FOR v_other_user IN
            SELECT user_id FROM circle_members
            WHERE circle_id = v_circle_id AND user_id != v_main_user_id
        LOOP
            -- Add a reaction with a rotating emoji
            INSERT INTO circle_reactions (post_id, user_id, emoji, created_at)
            VALUES (
                v_post.id,
                v_other_user.user_id,
                v_reaction_emojis[((v_emoji_idx - 1) % 5) + 1],
                NOW() - INTERVAL '1 hour' * v_emoji_idx
            )
            ON CONFLICT (post_id, user_id) DO NOTHING;

            v_emoji_idx := v_emoji_idx + 1;
        END LOOP;
    END LOOP;

    RAISE NOTICE 'Added % members and their reactions to the demo circle', v_member_count;
END $$;
