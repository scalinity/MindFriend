\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database() <> 'restoration_synthetic' OR EXISTS (SELECT FROM auth.users) THEN
    RAISE EXCEPTION 'Requires empty restoration_synthetic fixture';
  END IF;
END $$;
INSERT INTO auth.users(id,aud,role,email,raw_user_meta_data,created_at,updated_at) VALUES
 ('11111111-1111-4111-8111-111111111111','authenticated','authenticated','mentee@example.invalid','{}',now(),now()),
 ('22222222-2222-4222-8222-222222222222','authenticated','authenticated','mentor@example.invalid','{}',now(),now());
INSERT INTO public.mentorship_profiles(user_id,is_mentor_available,verified,training_completed,expertise_areas,languages,timezone)
VALUES ('22222222-2222-4222-8222-222222222222',true,true,true,ARRAY['stress'],ARRAY['en'],'America/New_York');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
SET LOCAL request.jwt.claim.role='authenticated';
INSERT INTO public.mentorship_profiles(user_id,timezone) VALUES (auth.uid(),'America/New_York');
UPDATE public.mentorship_profiles SET seeking_areas=ARRAY['stress'] WHERE user_id=auth.uid();
DO $$ DECLARE candidate record; match_id uuid; BEGIN
  IF public.calculate_timezone_overlap('America/New_York','America/New_York') <> 1.0 OR
     public.calculate_timezone_overlap('UTC','Asia/Kathmandu') <> 0.6 OR
     public.calculate_timezone_overlap('invalid/zone','UTC') <> 0.5 THEN
    RAISE EXCEPTION 'Timezone scoring failed';
  END IF;
  SELECT * INTO STRICT candidate FROM public.find_mentor_matches(auth.uid(),ARRAY['stress'],5);
  IF candidate.mentor_user_id <> '22222222-2222-4222-8222-222222222222' OR candidate.match_reason IS NULL THEN
    RAISE EXCEPTION 'Discovery result does not match client contract';
  END IF;
  match_id := public.create_mentorship_request(candidate.mentor_user_id,'I would appreciate support with managing stress.');
  IF NOT EXISTS(SELECT FROM public.mentorship_matches m WHERE m.id=match_id AND m.status='pending'
                AND m.mentee_id=auth.uid() AND length(m.mentor_alias)>0 AND length(m.mentee_alias)>0) THEN
    RAISE EXCEPTION 'Request did not persist participant identities and aliases';
  END IF;
  BEGIN
    PERFORM public.create_mentorship_request(candidate.mentor_user_id,'I would appreciate support with managing stress.');
    RAISE EXCEPTION 'Duplicate request accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Match already exists' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.find_mentor_matches(candidate.mentor_user_id,ARRAY['stress'],5);
    RAISE EXCEPTION 'Cross-user discovery accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Not authorized to query matches for this user' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK;
