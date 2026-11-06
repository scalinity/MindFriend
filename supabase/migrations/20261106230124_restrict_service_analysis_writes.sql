BEGIN;
ALTER POLICY "Service role manages agent learnings" ON public.agent_learnings
  TO service_role USING (true) WITH CHECK (true);
ALTER POLICY "Service role inserts agent signals" ON public.agent_signals TO service_role;
ALTER POLICY "Service role inserts agent decisions" ON public.agent_decisions TO service_role;
ALTER POLICY "Service role can insert briefings" ON public.daily_briefings TO service_role;
ALTER POLICY "Service role can insert journal analyses" ON public.journal_analyses TO service_role;
ALTER POLICY "service_insert_voice_analysis" ON public.voice_journal_analysis TO service_role;
ALTER POLICY "Service role inserts feedback" ON public.rehearsal_feedback TO service_role;
ALTER POLICY "Service role can insert billing events" ON public.billing_events TO service_role;

REVOKE ALL ON public.agent_learnings, public.agent_signals, public.agent_decisions,
  public.daily_briefings, public.journal_analyses, public.voice_journal_analysis,
  public.rehearsal_feedback, public.billing_events FROM PUBLIC, anon;
REVOKE INSERT ON public.agent_learnings, public.agent_signals, public.agent_decisions,
  public.daily_briefings, public.journal_analyses, public.voice_journal_analysis,
  public.rehearsal_feedback, public.billing_events FROM authenticated;
REVOKE UPDATE, DELETE ON public.agent_learnings FROM authenticated;
-- Keep owner-scoped SELECT and the existing briefing viewed-state UPDATE.
GRANT SELECT ON public.agent_learnings, public.agent_signals, public.agent_decisions,
  public.daily_briefings, public.journal_analyses, public.voice_journal_analysis,
  public.rehearsal_feedback, public.billing_events TO authenticated;
COMMIT;
