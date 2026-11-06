-- Exact Postgres Changes dependencies in AgentService, FamilyService,
-- PeerSupportService, LiveService and ThreadView. Broadcasts need no table publication.
-- The paired restoration rollback assumes none of these six tables was published.
-- Reject a different baseline before changing membership, preserving existing entries.
DO $$
DECLARE name text;
BEGIN
  IF EXISTS (
    SELECT FROM pg_catalog.pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
      AND tablename = ANY (ARRAY['agent_actions','together_participants','support_messages','circle_room_participants','user_presence','forum_replies'])
  ) THEN
    RAISE EXCEPTION 'Required Realtime tables must have zero publication membership before this migration';
  END IF;

  FOREACH name IN ARRAY ARRAY['agent_actions','together_participants','support_messages','circle_room_participants','user_presence','forum_replies'] LOOP
    EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', name);
  END LOOP;
END $$;
