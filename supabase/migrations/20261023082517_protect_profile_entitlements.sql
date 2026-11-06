-- Row ownership alone permits self-upgrading the subscription and quota fields.
-- Keep profile editing/onboarding available, while server helpers retain their grants.
REVOKE INSERT, UPDATE ON public.profiles FROM PUBLIC, anon, authenticated;
REVOKE INSERT (subscription_tier,daily_ai_quota,daily_ai_used,quota_reset_at),
       UPDATE (subscription_tier,daily_ai_quota,daily_ai_used,quota_reset_at)
  ON public.profiles FROM PUBLIC, anon, authenticated;
DO $$
DECLARE columns text;
BEGIN
  SELECT string_agg(format('%I',attname), ',' ORDER BY attnum) INTO columns
    FROM pg_attribute
    WHERE attrelid='public.profiles'::regclass AND attnum>0 AND NOT attisdropped
      AND attname NOT IN ('subscription_tier','daily_ai_quota','daily_ai_used','quota_reset_at');
  EXECUTE format('GRANT INSERT (%s), UPDATE (%s) ON public.profiles TO authenticated', columns, columns);
END $$;
