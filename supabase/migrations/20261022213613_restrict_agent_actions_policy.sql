-- The existing owner policies continue to permit reading and acknowledging own actions.
-- The ALL policy must not participate in anon/authenticated policy evaluation.
ALTER POLICY "Service role manages agent actions" ON public.agent_actions
  TO service_role;

-- TRUNCATE bypasses row policies and is never part of the client workflow.
REVOKE TRUNCATE ON public.agent_actions FROM anon, authenticated;
