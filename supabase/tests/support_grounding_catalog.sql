\set ON_ERROR_STOP on
BEGIN;
DO $$ DECLARE mapped uuid;
BEGIN
  IF current_database()<>'restoration_synthetic' OR EXISTS(SELECT FROM auth.users) THEN
    RAISE EXCEPTION 'Catalog check requires the empty owned restoration_synthetic database';
  END IF;
  SELECT exercise_id INTO mapped FROM public.support_template_catalog
    WHERE template_key='ground_present_v1' AND template_version=1 AND kind='grounding' AND enabled;
  IF mapped IS NULL OR NOT EXISTS(SELECT FROM public.exercises WHERE id=mapped AND type='grounding') THEN
    RAISE EXCEPTION 'Grounding has no real canonical exercise mapping';
  END IF;
  IF NOT EXISTS(SELECT FROM public.support_template_catalog WHERE template_key='untangle_thought_v1' AND exercise_id IS NULL)
     OR NOT EXISTS(SELECT FROM public.support_template_catalog WHERE template_key='choose_step_v1' AND exercise_id IS NULL) THEN
    RAISE EXCEPTION 'Untangle or next step incorrectly gained exercise ownership';
  END IF;
END $$;
ROLLBACK;
