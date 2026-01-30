-- Security hardening for quest stats trigger (SA1 Security recommendation)
-- Note: In Supabase, function ownership cannot be changed from postgres.
-- Instead, we ensure security through:
-- 1. SECURITY DEFINER with locked search_path (already in function)
-- 2. RLS policies on upstream tables (quests) prevent unauthorized triggers
-- 3. Input validation within the function
-- 4. Advisory locks prevent concurrent manipulation

-- Verify RLS is enabled on user_stats (defense in depth)
ALTER TABLE public.user_stats ENABLE ROW LEVEL SECURITY;

-- Ensure the function has appropriate grants (revoke public, grant only to authenticated)
REVOKE ALL ON FUNCTION public.update_stats_on_quest_completion() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_stats_on_quest_completion() TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_stats_on_quest_completion() TO service_role;

-- Document security measures in function comment
COMMENT ON FUNCTION public.update_stats_on_quest_completion() IS
  'Trigger function to update user_stats when a quest is completed. '
  'Security: SECURITY DEFINER with locked search_path, RLS on upstream tables, '
  'input validation, advisory locks. Execute granted only to authenticated/service_role. '
  'Fixed 2026-01-30: DATE comparisons, concurrency safety, fail-fast validation.';
