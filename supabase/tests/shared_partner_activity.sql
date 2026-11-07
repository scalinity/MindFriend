\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database() NOT IN ('ca3_synthetic', 'restoration_synthetic') OR EXISTS (SELECT FROM auth.users) THEN
    RAISE EXCEPTION 'An empty dedicated synthetic database is required';
  END IF;
END $$;
INSERT INTO auth.users(id,aud,role,email,raw_user_meta_data,created_at,updated_at) VALUES
 ('11111111-1111-4111-8111-111111111111','authenticated','authenticated','partner-a@example.invalid','{}',now(),now()),
 ('22222222-2222-4222-8222-222222222222','authenticated','authenticated','partner-b@example.invalid','{}',now(),now()),
 ('33333333-3333-4333-8333-333333333333','authenticated','authenticated','partner-c@example.invalid','{}',now(),now());
UPDATE public.profiles SET timezone = 'Pacific/Kiritimati' WHERE id = '22222222-2222-4222-8222-222222222222';
INSERT INTO public.partner_links(id,user_id_1,user_id_2,created_by,status,activated_at)
VALUES ('44444444-4444-4444-8444-444444444444','11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222',
        '11111111-1111-4111-8111-111111111111','active',now());
INSERT INTO public.moods(user_id,local_date,mood_score,note)
SELECT '22222222-2222-4222-8222-222222222222',(now() AT TIME ZONE 'Pacific/Kiritimati')::date - day,6,'PRIVATE MOOD NOTE'
FROM generate_series(-1,8) AS day;
INSERT INTO public.quest_templates(id,title,description,category)
VALUES ('55555555-5555-4555-8555-555555555555','Synthetic shared quest','Synthetic public instructions','mindfulness');
SET LOCAL request.jwt.claims = '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
INSERT INTO public.quests(user_id,template_id,local_date,status,completed_at,reflection_note,rating)
VALUES ('22222222-2222-4222-8222-222222222222','55555555-5555-4555-8555-555555555555',
        ((now() AT TIME ZONE 'Pacific/Kiritimati')::date)::text,'completed',now(),'PRIVATE QUEST REFLECTION',3);
SET LOCAL ROLE anon;
DO $$ BEGIN
  IF has_function_privilege('public.get_shared_partner_activity(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Anonymous execution remains granted';
  END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
DO $$ DECLARE result jsonb; BEGIN
  result := public.get_shared_partner_activity();
  IF jsonb_array_length(result->'moods') <> 0 OR result->'quest' <> 'null'::jsonb OR (result->>'has_completed_today')::boolean THEN
    RAISE EXCEPTION 'Activity leaked without partner consent';
  END IF;
  IF public.get_shared_partner_activity('33333333-3333-4333-8333-333333333333') IS NOT NULL
     OR public.get_shared_partner_activity('11111111-1111-4111-8111-111111111111') IS NOT NULL THEN
    RAISE EXCEPTION 'Caller selected a different subject';
  END IF;
END $$;
RESET ROLE;
UPDATE public.partner_links SET user_2_share_mood = true, user_2_share_exercises = true
WHERE id = '44444444-4444-4444-8444-444444444444';
SET LOCAL ROLE authenticated;
DO $$ DECLARE result jsonb; BEGIN
  result := public.get_shared_partner_activity('22222222-2222-4222-8222-222222222222');
  IF jsonb_array_length(result->'moods') <> 7 THEN RAISE EXCEPTION 'Expected bounded seven-day mood history'; END IF;
  IF NOT (result->>'has_completed_today')::boolean OR result->'quest'->>'status' <> 'completed'
     OR result->'quest'->'quest_templates'->>'title' <> 'Synthetic shared quest' THEN
    RAISE EXCEPTION 'Consented local-day quest is unavailable';
  END IF;
  IF result::text LIKE '%PRIVATE%' OR result->'quest' ? 'reflection_note' OR result->'quest' ? 'rating'
     OR EXISTS (SELECT FROM jsonb_array_elements(result->'moods') m WHERE m ? 'note' OR m ? 'encrypted_note') THEN
    RAISE EXCEPTION 'Private notes or ratings leaked';
  END IF;
  IF EXISTS (SELECT FROM public.moods WHERE user_id = '22222222-2222-4222-8222-222222222222')
     OR EXISTS (SELECT FROM public.quests WHERE user_id = '22222222-2222-4222-8222-222222222222') THEN
    RAISE EXCEPTION 'Owner-only table policy was widened';
  END IF;
END $$;
SET LOCAL request.jwt.claims = '{"sub":"22222222-2222-4222-8222-222222222222","role":"authenticated"}';
DO $$ DECLARE result jsonb; BEGIN
  result := public.get_shared_partner_activity();
  IF (result->>'is_sharing_mood')::boolean OR (result->>'is_sharing_exercises')::boolean THEN
    RAISE EXCEPTION 'Wrong participant consent was used';
  END IF;
END $$;
SET LOCAL request.jwt.claims = '{"sub":"33333333-3333-4333-8333-333333333333","role":"authenticated"}';
DO $$ BEGIN
  IF public.get_shared_partner_activity('22222222-2222-4222-8222-222222222222') IS NOT NULL THEN RAISE EXCEPTION 'Nonpartner read allowed'; END IF;
END $$;
RESET ROLE;
UPDATE public.partner_links SET user_2_share_mood = false, user_2_share_exercises = false
WHERE id = '44444444-4444-4444-8444-444444444444';
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}';
DO $$ DECLARE result jsonb; BEGIN
  result := public.get_shared_partner_activity();
  IF jsonb_array_length(result->'moods') <> 0 OR result->'quest' <> 'null'::jsonb THEN RAISE EXCEPTION 'Revocation was not honored'; END IF;
END $$;
RESET ROLE;
UPDATE public.partner_links SET status = 'ended' WHERE id = '44444444-4444-4444-8444-444444444444';
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  IF public.get_shared_partner_activity() IS NOT NULL THEN RAISE EXCEPTION 'Ended partnership read allowed'; END IF;
END $$;
RESET ROLE;
SELECT 'PASS: active membership, directional consent, seven-day/local-day boundaries, private-field exclusion, revocation and unchanged owner-only RLS';
ROLLBACK;
