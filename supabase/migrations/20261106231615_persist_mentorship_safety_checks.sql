-- Record each automated check once, including safe messages, so bounded batches advance.
ALTER TABLE public.mentorship_messages ADD COLUMN safety_checked_at timestamptz;
CREATE INDEX mentorship_messages_unchecked_idx ON public.mentorship_messages(created_at,id)
  WHERE safety_checked_at IS NULL;

CREATE OR REPLACE FUNCTION public.protect_mentorship_safety_check_state()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  IF auth.jwt()->>'role' IS DISTINCT FROM 'service_role' AND
     ((TG_OP='INSERT' AND NEW.safety_checked_at IS NOT NULL) OR
      (TG_OP='UPDATE' AND NEW.safety_checked_at IS DISTINCT FROM OLD.safety_checked_at)) THEN
    RAISE EXCEPTION 'Only the safety checker can record a completed check' USING ERRCODE='42501';
  END IF;
  IF TG_OP='UPDATE' AND NEW.content IS DISTINCT FROM OLD.content THEN NEW.safety_checked_at=NULL; END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER protect_mentorship_safety_check_state BEFORE INSERT OR UPDATE ON public.mentorship_messages
  FOR EACH ROW EXECUTE FUNCTION public.protect_mentorship_safety_check_state();

-- Automated escalations have no human reporter. Keep their source message identity.
CREATE TABLE public.mentorship_escalations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL UNIQUE REFERENCES public.mentorship_messages(id) ON DELETE CASCADE,
  match_id uuid NOT NULL REFERENCES public.mentorship_matches(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  severity text NOT NULL CHECK (severity = 'critical'),
  reasons text[] NOT NULL CHECK (cardinality(reasons) > 0),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','reviewed','resolved')),
  created_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  action text
);
ALTER TABLE public.mentorship_escalations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.mentorship_escalations FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.mentorship_escalations TO service_role;

CREATE OR REPLACE FUNCTION public.record_mentorship_safety_check(
  p_message_id uuid, p_expected_content text, p_reasons text[], p_severity text
) RETURNS boolean
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE
  v_message public.mentorship_messages%ROWTYPE;
BEGIN
  IF auth.jwt()->>'role' IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Service role required' USING ERRCODE='42501';
  END IF;
  IF p_reasons IS NULL OR p_severity IS NULL OR
      p_severity NOT IN ('low','medium','high','critical') OR
      (p_severity='critical' AND cardinality(p_reasons)=0) THEN
    RAISE EXCEPTION 'Invalid safety result' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_message FROM public.mentorship_messages
    WHERE id=p_message_id FOR UPDATE;
  IF NOT FOUND OR v_message.content IS DISTINCT FROM p_expected_content THEN RETURN false; END IF;
  -- A competing checker already committed this exact message; its result is authoritative.
  IF v_message.safety_checked_at IS NOT NULL THEN RETURN false; END IF;

  IF p_severity='critical' THEN
    INSERT INTO public.mentorship_escalations(message_id,match_id,sender_id,severity,reasons)
      VALUES(v_message.id,v_message.match_id,v_message.sender_id,p_severity,p_reasons)
      ON CONFLICT(message_id) DO NOTHING;
  END IF;
  UPDATE public.mentorship_messages SET
    safety_checked_at=now(),
    flagged=flagged OR cardinality(p_reasons)>0,
    flag_reason=CASE WHEN cardinality(p_reasons)>0
      THEN concat_ws('; ',nullif(flag_reason,''),array_to_string(p_reasons,'; ')) ELSE flag_reason END
    WHERE id=v_message.id;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.record_mentorship_safety_check(uuid,text,text[],text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_mentorship_safety_check(uuid,text,text[],text) TO service_role;
