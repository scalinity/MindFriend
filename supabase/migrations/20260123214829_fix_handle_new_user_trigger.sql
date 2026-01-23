-- Fix handle_new_user to also create user_settings and user_stats rows
-- This fixes the "user not found" error when signing in with Apple

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    random_handle TEXT;
BEGIN
    -- Generate a random handle
    random_handle := 'user_' || substr(md5(random()::text), 1, 8);

    -- Create profile
    INSERT INTO public.profiles (id, email, display_name, handle, daily_ai_used, daily_ai_quota, quota_reset_at)
    VALUES (
        new.id,
        new.email,
        COALESCE(
            new.raw_user_meta_data->>'full_name',
            new.raw_user_meta_data->>'name',
            split_part(new.email, '@', 1)
        ),
        random_handle,
        0,
        10,
        NOW()
    );

    -- Create user_settings with defaults
    INSERT INTO public.user_settings (user_id)
    VALUES (new.id)
    ON CONFLICT (user_id) DO NOTHING;

    -- Create user_stats with defaults
    INSERT INTO public.user_stats (user_id)
    VALUES (new.id)
    ON CONFLICT (user_id) DO NOTHING;

    RETURN new;
END;
$$;

-- Also backfill any existing users who are missing settings/stats
-- This handles users who signed up before this fix
INSERT INTO public.user_settings (user_id)
SELECT id FROM auth.users
WHERE id NOT IN (SELECT user_id FROM public.user_settings)
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO public.user_stats (user_id)
SELECT id FROM auth.users
WHERE id NOT IN (SELECT user_id FROM public.user_stats)
ON CONFLICT (user_id) DO NOTHING;
