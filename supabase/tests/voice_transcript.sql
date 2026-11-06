-- Run against the migrated schema with auth.uid() accepting request.jwt.claims.
-- All transcript rows roll back; no live account or provider is used.
BEGIN;
DO $$ BEGIN
  IF current_database() NOT IN ('restoration_synthetic', 'ca2_reliability_synthetic')
     OR EXISTS (SELECT FROM auth.users) THEN
    RAISE EXCEPTION 'This test requires an empty isolated synthetic database';
  END IF;
END $$;
DO $$ BEGIN
  IF has_function_privilege('anon', 'public.save_voice_transcript(uuid,text,jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.save_voice_transcript(uuid,text,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Transcript RPC execution grants differ from the authenticated contract';
  END IF;
END $$;
INSERT INTO auth.users(id,aud,role,email,raw_user_meta_data,created_at,updated_at) VALUES
 ('ca200000-0000-4000-8000-000000000001','authenticated','authenticated','voice-a@example.invalid','{}',now(),now()),
 ('ca200000-0000-4000-8000-000000000002','authenticated','authenticated','voice-b@example.invalid','{}',now(),now());
SELECT set_config('request.jwt.claims', '{"sub":"ca200000-0000-4000-8000-000000000001","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
DO $$
DECLARE
  conversation uuid := 'ca200000-0000-4000-8000-000000000010';
  payload jsonb := '[
    {"id":"ca200000-0000-4000-8000-000000000011","role":"user","content":"First thought","created_at":"2026-11-06T12:00:00.123Z"},
    {"id":"ca200000-0000-4000-8000-000000000012","role":"assistant","content":"A reply","created_at":"2026-11-06T12:00:01.456Z"}
  ]';
BEGIN
  -- Failure before any write must leave no conversation.
  BEGIN
    PERFORM public.save_voice_transcript(conversation, 'Voice', '[]');
    RAISE EXCEPTION 'Empty payload unexpectedly accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.conversations WHERE id = conversation) THEN
    RAISE EXCEPTION 'Failed save created conversation';
  END IF;

  PERFORM public.save_voice_transcript(conversation, 'Voice', payload);
  -- Simulate losing a successful response and submitting the exact draft again.
  PERFORM public.save_voice_transcript(conversation, 'Voice', payload);
  IF (SELECT count(*) FROM public.messages WHERE conversation_id = conversation) <> 2 THEN
    RAISE EXCEPTION 'Replay duplicated or omitted messages';
  END IF;

  -- A conflict discovered after inserting a new message must roll back the batch.
  BEGIN
    PERFORM public.save_voice_transcript(conversation, 'Voice', '[
      {"id":"ca200000-0000-4000-8000-000000000013","role":"user","content":"Unsaved suffix","created_at":"2026-11-06T12:00:02Z"},
      {"id":"ca200000-0000-4000-8000-000000000011","role":"user","content":"Changed content","created_at":"2026-11-06T12:00:00.123Z"}
    ]');
    RAISE EXCEPTION 'Conflicting message unexpectedly accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  IF (SELECT count(*) FROM public.messages WHERE conversation_id = conversation) <> 2 THEN
    RAISE EXCEPTION 'Failed batch left a partial suffix';
  END IF;
  IF (SELECT content FROM public.messages WHERE id = 'ca200000-0000-4000-8000-000000000011') <> 'First thought' THEN
    RAISE EXCEPTION 'Retry modified original content';
  END IF;
END;
$$;

SELECT set_config('request.jwt.claims', '{"sub":"ca200000-0000-4000-8000-000000000002","role":"authenticated"}', true);
DO $$
BEGIN
  BEGIN
    PERFORM public.save_voice_transcript('ca200000-0000-4000-8000-000000000010', 'Foreign', '[
      {"id":"ca200000-0000-4000-8000-000000000020","role":"user","content":"Other account","created_at":"2026-11-06T12:00:00Z"}
    ]');
    RAISE EXCEPTION 'Cross-account conversation accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.save_voice_transcript('ca200000-0000-4000-8000-000000000030', 'Foreign', '[
      {"id":"ca200000-0000-4000-8000-000000000011","role":"user","content":"First thought","created_at":"2026-11-06T12:00:00.123Z"}
    ]');
    RAISE EXCEPTION 'Cross-account message identity accepted';
  EXCEPTION WHEN invalid_parameter_value OR insufficient_privilege THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.conversations WHERE id = 'ca200000-0000-4000-8000-000000000030') THEN
    RAISE EXCEPTION 'Cross-account identity conflict left an empty conversation';
  END IF;
END;
$$;
SELECT set_config('request.jwt.claims', '{"role":"authenticated"}', true);
DO $$ BEGIN
  BEGIN
    PERFORM public.save_voice_transcript('ca200000-0000-4000-8000-000000000099', 'Unauthenticated', '[]');
    RAISE EXCEPTION 'Missing authenticated subject accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;
ROLLBACK;
