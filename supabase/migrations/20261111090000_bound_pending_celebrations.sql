-- 2.0.0 is the first release that presents celebration_events. Earlier releases never
-- marked one as shown, so every milestone since sign-up was still pending and the first
-- 2.0 launch replayed them as a run of full-screen covers. Only recent milestones are
-- celebrated now; the backlog and streak milestones (which the app no longer shows) are
-- marked as shown so they stop accumulating.

UPDATE public.celebration_events
SET shown_at = now()
WHERE shown_at IS NULL
  AND (celebration_type = 'streak_milestone' OR created_at < now() - interval '2 days');

CREATE OR REPLACE FUNCTION public.get_pending_celebrations(p_user_id uuid)
RETURNS TABLE(id uuid, celebration_type text, value integer, badge_id uuid, badge_title text,
              badge_description text, badge_icon_name text, created_at timestamp with time zone)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ce.id,
    ce.celebration_type,
    ce.value,
    ce.badge_id,
    b.title AS badge_title,
    b.description AS badge_description,
    b.icon_name AS badge_icon_name,
    ce.created_at
  FROM celebration_events ce
  LEFT JOIN badges b ON b.id = ce.badge_id
  WHERE ce.user_id = p_user_id
    AND ce.shown_at IS NULL
    AND ce.celebration_type <> 'streak_milestone'
    AND ce.created_at > now() - interval '2 days'
  ORDER BY ce.created_at ASC
  LIMIT 10;
END;
$$;
