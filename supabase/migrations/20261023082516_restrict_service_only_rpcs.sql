-- Call sites: chat uses its admin client for AI quota; voice-token uses its admin
-- client to create sessions; end_voice_session invokes usage accounting as owner.
-- These helpers have no direct iOS RPC caller and accept privileged caller input.
REVOKE ALL ON FUNCTION public.check_and_increment_ai_quota(uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_voice_session(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.increment_voice_usage(uuid, double precision, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_increment_ai_quota(uuid, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.create_voice_session(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.increment_voice_usage(uuid, double precision, date) TO service_role;
