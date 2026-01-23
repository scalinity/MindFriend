-- Backfill missing profiles for all auth users
-- This runs as a one-time fix for users created before trigger was fixed

-- Create missing profiles for ALL auth users
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
    COALESCE(au.created_at, NOW()),
    NOW()
FROM auth.users au
WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = au.id)
ON CONFLICT (id) DO NOTHING;

-- Create missing user_settings
INSERT INTO public.user_settings (user_id)
SELECT au.id FROM auth.users au
WHERE NOT EXISTS (SELECT 1 FROM public.user_settings us WHERE us.user_id = au.id)
ON CONFLICT (user_id) DO NOTHING;

-- Create missing user_stats
INSERT INTO public.user_stats (user_id)
SELECT au.id FROM auth.users au
WHERE NOT EXISTS (SELECT 1 FROM public.user_stats ust WHERE ust.user_id = au.id)
ON CONFLICT (user_id) DO NOTHING;
