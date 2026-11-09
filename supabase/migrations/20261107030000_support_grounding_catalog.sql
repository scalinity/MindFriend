-- Bind the bundled support grounding version to the existing canonical exercise domain.
-- Retain an already configured valid mapping; never guess a record from a mutable title.
BEGIN;
DO $$
DECLARE
  mapped uuid;
  target CONSTANT uuid := 'c36c39fa-718c-52f3-bc63-9a6bb9cba338';
  expected CONSTANT jsonb := '{"type":"grounding","data":{"technique":"5-4-3-2-1","prompts":[{"sense":"sight","text":"Notice up to five things you can see. You can participate silently or skip this prompt.","count":5},{"sense":"touch","text":"Notice up to four things you can feel. A different neutral detail is fine too.","count":4},{"sense":"hearing","text":"Notice up to three things you can hear, or choose a different neutral detail.","count":3},{"sense":"smell","text":"Notice up to two things you can smell. You can skip this prompt.","count":2},{"sense":"taste","text":"Notice one thing you can taste, or one neutral detail around you.","count":1}]}}'::jsonb;
BEGIN
  SELECT exercise_id INTO mapped FROM public.support_template_catalog
    WHERE template_key='ground_present_v1' AND template_version=1 AND kind='grounding' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Grounding support catalog version 1 is missing'; END IF;
  IF mapped IS NOT NULL THEN
    IF NOT EXISTS(SELECT FROM public.exercises WHERE id=mapped AND type='grounding') THEN
      RAISE EXCEPTION 'Existing grounding catalog mapping is not a grounding exercise';
    END IF;
    RETURN;
  END IF;
  INSERT INTO public.exercises(id,title,description,type,duration_minutes,duration_seconds,instructions,is_premium,evidence_basis,therapist_reviewed)
  VALUES(target,'Notice what is around you','A short optional sensory grounding practice. Skip any prompt or choose a neutral alternative.',
    'grounding',2,120,expected,false,'General',false)
  ON CONFLICT(id) DO NOTHING;
  IF NOT EXISTS(SELECT FROM public.exercises WHERE id=target AND type='grounding' AND instructions=expected AND is_premium=false) THEN
    RAISE EXCEPTION 'Grounding support exercise identity conflicts with an existing catalog record';
  END IF;
  UPDATE public.support_template_catalog SET exercise_id=target WHERE template_key='ground_present_v1';
END $$;
COMMIT;
