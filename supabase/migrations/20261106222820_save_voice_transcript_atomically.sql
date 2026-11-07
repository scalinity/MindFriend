-- One transaction preserves a voice session across partial/lost responses.
CREATE OR REPLACE FUNCTION public.save_voice_transcript(
  p_conversation_id uuid,
  p_title text,
  p_messages jsonb
) RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_owner uuid := auth.uid();
  v_count integer;
BEGIN
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_conversation_id IS NULL OR jsonb_typeof(p_messages) IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_messages) NOT BETWEEN 1 AND 2000
     OR octet_length(p_messages::text) > 4194304 THEN
    RAISE EXCEPTION 'Invalid voice transcript' USING ERRCODE = '22023';
  END IF;

  SELECT count(DISTINCT m.id) INTO v_count
  FROM jsonb_to_recordset(p_messages) AS m(id uuid, role text, content text, created_at timestamptz)
  WHERE m.id IS NOT NULL AND m.role IN ('user', 'assistant')
    AND m.content IS NOT NULL AND length(btrim(m.content)) > 0
    AND m.created_at IS NOT NULL;
  IF v_count <> jsonb_array_length(p_messages) THEN
    RAISE EXCEPTION 'Invalid or duplicate transcript message' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.conversations(id, user_id, title)
  VALUES (p_conversation_id, v_owner, left(coalesce(nullif(p_title, ''), 'Voice conversation'), 120))
  ON CONFLICT (id) DO NOTHING;
  PERFORM 1 FROM public.conversations
  WHERE id = p_conversation_id AND user_id = v_owner FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conversation unavailable' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.messages(id, conversation_id, role, content, created_at)
  SELECT m.id, p_conversation_id, m.role::public.message_role, m.content, m.created_at
  FROM jsonb_to_recordset(p_messages) AS m(id uuid, role text, content text, created_at timestamptz)
  ON CONFLICT (id) DO NOTHING;

  -- A retry may acknowledge only the exact immutable message it originally sent.
  SELECT count(*) INTO v_count
  FROM jsonb_to_recordset(p_messages) AS incoming(id uuid, role text, content text, created_at timestamptz)
  JOIN public.messages saved ON saved.id = incoming.id
    AND saved.conversation_id = p_conversation_id
    AND saved.role::text = incoming.role AND saved.content = incoming.content
    AND saved.created_at = incoming.created_at;
  IF v_count <> jsonb_array_length(p_messages) THEN
    RAISE EXCEPTION 'Transcript message identity conflicts with stored content' USING ERRCODE = '22023';
  END IF;
  RETURN p_conversation_id;
END;
$$;
REVOKE ALL ON FUNCTION public.save_voice_transcript(uuid, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_voice_transcript(uuid, text, jsonb) TO authenticated;
