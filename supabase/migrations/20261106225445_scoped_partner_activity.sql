-- Shared activity is a bounded projection; owner-only mood/quest RLS stays intact.
CREATE SCHEMA IF NOT EXISTS private;
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE OR REPLACE FUNCTION private.get_shared_partner_activity(p_partner_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_owner uuid := auth.uid();
  v_link public.partner_links%ROWTYPE;
  v_partner uuid;
  v_profile public.profiles%ROWTYPE;
  v_share_mood boolean;
  v_share_exercises boolean;
  v_today date;
  v_moods jsonb := '[]'::jsonb;
  v_quest jsonb;
  v_streak integer := 0;
BEGIN
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_link FROM public.partner_links
  WHERE status = 'active' AND user_id_2 IS NOT NULL
    AND v_owner IN (user_id_1, user_id_2)
    AND (p_partner_id IS NULL OR p_partner_id = CASE WHEN user_id_1 = v_owner THEN user_id_2 ELSE user_id_1 END)
  ORDER BY activated_at DESC NULLS LAST, id
  LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;

  v_partner := CASE WHEN v_link.user_id_1 = v_owner THEN v_link.user_id_2 ELSE v_link.user_id_1 END;
  v_share_mood := CASE WHEN v_link.user_id_1 = v_owner THEN v_link.user_2_share_mood ELSE v_link.user_1_share_mood END;
  v_share_exercises := CASE WHEN v_link.user_id_1 = v_owner THEN v_link.user_2_share_exercises ELSE v_link.user_1_share_exercises END;
  SELECT * INTO v_profile FROM public.profiles WHERE id = v_partner;
  IF NOT FOUND THEN RETURN NULL; END IF;
  v_today := (now() AT TIME ZONE coalesce((SELECT name FROM pg_timezone_names WHERE name = v_profile.timezone), 'UTC'))::date;

  IF v_share_mood THEN
    SELECT coalesce(jsonb_agg(to_jsonb(shared) ORDER BY local_date DESC), '[]'::jsonb) INTO v_moods
    FROM (
      SELECT id, user_id, local_date, mood_score, created_at
      FROM public.moods
      WHERE user_id = v_partner AND local_date BETWEEN v_today - 6 AND v_today
      ORDER BY local_date DESC, id LIMIT 7
    ) shared;
  END IF;

  IF v_share_exercises THEN
    SELECT coalesce(current_streak_days, 0) INTO v_streak FROM public.user_stats WHERE user_id = v_partner;
    SELECT jsonb_build_object(
      'id', q.id, 'user_id', q.user_id, 'template_id', q.template_id,
      'local_date', q.local_date, 'status', q.status,
      'assigned_at', q.assigned_at, 'completed_at', q.completed_at,
      'quest_templates', jsonb_build_object(
        'id', t.id, 'title', t.title, 'description', t.description,
        'category', t.category, 'estimated_minutes', t.estimated_minutes,
        'xp_reward', t.xp_reward, 'is_premium', t.is_premium, 'instructions', t.instructions
      )
    ) INTO v_quest
    FROM public.quests q JOIN public.quest_templates t ON t.id = q.template_id
    WHERE q.user_id = v_partner AND q.local_date = v_today::text
    ORDER BY q.assigned_at DESC, q.id LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'partner_id', v_partner, 'partner_name', coalesce(v_profile.display_name, 'Partner'),
    'partner_streak', coalesce(v_streak, 0),
    'has_completed_today', coalesce(v_quest->>'status' = 'completed', false),
    'last_active', coalesce(v_profile.created_at, now()),
    'is_sharing_mood', v_share_mood, 'is_sharing_exercises', v_share_exercises,
    'moods', v_moods, 'quest', v_quest
  );
END;
$$;
REVOKE ALL ON FUNCTION private.get_shared_partner_activity(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.get_shared_partner_activity(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_shared_partner_activity(p_partner_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$ SELECT private.get_shared_partner_activity(p_partner_id); $$;
REVOKE ALL ON FUNCTION public.get_shared_partner_activity(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_shared_partner_activity(uuid) TO authenticated;
