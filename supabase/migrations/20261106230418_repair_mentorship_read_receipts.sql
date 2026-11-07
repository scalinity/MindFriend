-- Only a message's recipient can advance its read receipt.
CREATE OR REPLACE FUNCTION public.mark_messages_read(p_match_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_user_id uuid := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
    IF NOT EXISTS (SELECT FROM public.mentorship_matches WHERE id=p_match_id
                   AND (mentor_id=v_user_id OR mentee_id=v_user_id)) THEN
        RAISE EXCEPTION 'You are not a participant in this mentorship';
    END IF;
    UPDATE public.mentorship_messages SET read_at=now()
    WHERE match_id=p_match_id AND sender_id<>v_user_id AND read_at IS NULL;
    RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.mark_messages_read(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_messages_read(uuid) TO authenticated;
