\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database() <> 'restoration_synthetic' OR EXISTS (SELECT FROM auth.users) THEN
    RAISE EXCEPTION 'This test requires the empty restoration_synthetic database';
  END IF;
END $$;
INSERT INTO public.supported_languages(code,name,native_name,is_active)
VALUES ('en','English','English',true) ON CONFLICT DO NOTHING;
INSERT INTO public.level_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO public.skill_thresholds(level,xp_required,title) VALUES (1,0,'Synthetic beginner') ON CONFLICT DO NOTHING;
INSERT INTO auth.users(id,aud,role,email,raw_user_meta_data,created_at,updated_at)
VALUES ('11111111-1111-4111-8111-111111111111','authenticated','authenticated','notification-fixture@example.invalid','{}',now(),now());
DO $test$
DECLARE
  category text;
  violation text;
BEGIN
  FOREACH category IN ARRAY ARRAY[
    'circle_activity',
    'hug',
    'streak_risk',
    'weekly_summary',
    'challenge',
    'family_member_joined',
    'together_invitation',
    'family_alert',
    'family_challenge_progress',
    'parental_consent_request',
    'shield_used',
    'shield_reset',
    'recovery_available',
    'reengagement_gentle',
    'reengagement_social',
    'reengagement_progress',
    'reengagement_fresh_start',
    'proactive_mood_decline',
    'proactive_streak_risk',
    'proactive_milestone',
    'proactive_reengagement',
    'proactive_pattern_insight',
    'assessment_reminder',
    'buddy_encouragement',
    'couples_exercise_invite',
    'agent_action'
  ] LOOP
    INSERT INTO public.notification_history(user_id,notification_type,title,body)
    VALUES ('11111111-1111-4111-8111-111111111111',category,'Synthetic','No notification is sent');
  END LOOP;
  IF (SELECT count(*) FROM public.notification_history) <> 26 THEN
    RAISE EXCEPTION 'Expected all 26 existing notification categories';
  END IF;
  FOREACH category IN ARRAY ARRAY['','unknown','agent_action_extra','reengagement_other','proactive_other','AGENT_ACTION'] LOOP
    BEGIN
      INSERT INTO public.notification_history(user_id,notification_type,title,body)
      VALUES ('11111111-1111-4111-8111-111111111111',category,'Synthetic','No notification is sent');
      RAISE EXCEPTION 'Unsupported notification category was accepted: %', category;
    EXCEPTION WHEN check_violation THEN
      GET STACKED DIAGNOSTICS violation = CONSTRAINT_NAME;
      IF violation <> 'notification_history_notification_type_check' THEN RAISE; END IF;
    END;
  END LOOP;
END;
$test$;
SELECT 'PASS: 26 existing categories accepted; 6 invalid categories rejected; no sends';
ROLLBACK;
