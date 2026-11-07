-- Content-free history metadata lets a new device filter saved steps/completed activities and
-- avoid duplicating canonical records before opening every session. No new record store.
BEGIN;
CREATE OR REPLACE FUNCTION public.support_session_summary(p_user uuid, p_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = pg_catalog, public, pg_temp AS $$
  SELECT jsonb_build_object(
    'id', s.id, 'conversation_id', s.conversation_id, 'previous_session_id', s.previous_session_id,
    'title', s.title, 'status', s.status, 'context_scope', s.context_scope, 'revision', s.revision,
    'selected_activity_id', s.selected_activity_id, 'created_at', s.created_at, 'updated_at', s.updated_at,
    'closed_at', s.closed_at, 'deleted_at', s.deleted_at,
    'unfinished_count', (SELECT count(*) FROM public.support_activities a
                         WHERE a.support_session_id = s.id AND a.user_id = p_user
                           AND a.status IN ('ready', 'in_progress', 'paused')),
    'selected_activity', (SELECT jsonb_build_object('id', a.id, 'template_key', a.template_key, 'status', a.status)
                          FROM public.support_activities a WHERE a.id = s.selected_activity_id AND a.user_id = p_user),
    'activity_count', (SELECT count(*) FROM public.support_activities a
                        WHERE a.support_session_id = s.id AND a.user_id = p_user),
    'saved_step_count', (SELECT count(*) FROM public.support_activities a
                         WHERE a.support_session_id = s.id AND a.user_id = p_user AND a.kind = 'next_step'
                           AND a.status IN ('ready', 'in_progress', 'paused') AND a.checkpoint #>> '{step,state}' = 'saved'
                           AND a.content_scrubbed_at IS NULL),
    'canonical_references', (SELECT coalesce(jsonb_agg(jsonb_build_object('kind', refs.kind, 'id', refs.id)
                                                       ORDER BY refs.kind, refs.id), '[]'::jsonb)
                             FROM (SELECT DISTINCT a.canonical_ref_type AS kind, a.canonical_ref_id AS id
                                    FROM public.support_activities a WHERE a.support_session_id = s.id AND a.user_id = p_user
                                      AND a.canonical_ref_id IS NOT NULL) refs))
  FROM public.support_work_sessions s WHERE s.id = p_id AND s.user_id = p_user;
$$;
-- Keep the helper private; support_list_sessions already authenticates and supplies its owner.
REVOKE ALL ON FUNCTION public.support_session_summary(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
