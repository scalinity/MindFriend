-- Complete fix for handle_new_user trigger
-- This ensures ALL required fields are set for new users

-- Update the trigger function to set ALL required fields
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

    -- Create profile with ALL required fields
    INSERT INTO public.profiles (
        id,
        email,
        display_name,
        handle,
        timezone,
        subscription_tier,
        daily_ai_used,
        daily_ai_quota,
        quota_reset_at,
        created_at,
        updated_at
    )
    VALUES (
        new.id,
        new.email,
        COALESCE(
            new.raw_user_meta_data->>'full_name',
            new.raw_user_meta_data->>'name',
            split_part(new.email, '@', 1)
        ),
        random_handle,
        'UTC',  -- Default timezone
        'free', -- Default subscription tier
        0,
        10,
        NOW(),
        NOW(),
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

-- Backfill existing profiles that are missing required fields
UPDATE public.profiles
SET
    handle = COALESCE(handle, 'user_' || substr(md5(id::text), 1, 8)),
    display_name = COALESCE(display_name, 'MindFriend User'),
    timezone = COALESCE(timezone, 'UTC'),
    subscription_tier = COALESCE(subscription_tier, 'free'),
    daily_ai_used = COALESCE(daily_ai_used, 0),
    daily_ai_quota = COALESCE(daily_ai_quota, 10),
    quota_reset_at = COALESCE(quota_reset_at, NOW()),
    updated_at = COALESCE(updated_at, NOW())
WHERE
    handle IS NULL
    OR display_name IS NULL
    OR timezone IS NULL
    OR subscription_tier IS NULL
    OR daily_ai_used IS NULL
    OR daily_ai_quota IS NULL;

-- Ensure ALL existing auth users have profiles, settings, and stats
-- First, create missing profiles
INSERT INTO public.profiles (
    id,
    email,
    display_name,
    handle,
    timezone,
    subscription_tier,
    daily_ai_used,
    daily_ai_quota,
    quota_reset_at,
    created_at,
    updated_at
)
SELECT
    au.id,
    au.email,
    COALESCE(
        au.raw_user_meta_data->>'full_name',
        au.raw_user_meta_data->>'name',
        split_part(au.email, '@', 1),
        'MindFriend User'
    ),
    'user_' || substr(md5(au.id::text), 1, 8),
    'UTC',
    'free',
    0,
    10,
    NOW(),
    au.created_at,
    NOW()
FROM auth.users au
WHERE au.id NOT IN (SELECT id FROM public.profiles)
ON CONFLICT (id) DO NOTHING;

-- Create missing user_settings
INSERT INTO public.user_settings (user_id)
SELECT id FROM auth.users
WHERE id NOT IN (SELECT user_id FROM public.user_settings)
ON CONFLICT (user_id) DO NOTHING;

-- Create missing user_stats
INSERT INTO public.user_stats (user_id)
SELECT id FROM auth.users
WHERE id NOT IN (SELECT user_id FROM public.user_stats)
ON CONFLICT (user_id) DO NOTHING;
