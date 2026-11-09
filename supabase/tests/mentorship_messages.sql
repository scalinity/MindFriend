\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database() <> 'restoration_synthetic' OR EXISTS (SELECT FROM auth.users) THEN
    RAISE EXCEPTION 'Requires empty restoration_synthetic fixture';
  END IF;
END $$;
INSERT INTO auth.users(id,aud,role,email,raw_user_meta_data,created_at,updated_at) VALUES
 ('11111111-1111-4111-8111-111111111111','authenticated','authenticated','mentee@example.invalid','{}',now(),now()),
 ('22222222-2222-4222-8222-222222222222','authenticated','authenticated','mentor@example.invalid','{}',now(),now()),
 ('33333333-3333-4333-8333-333333333333','authenticated','authenticated','outsider@example.invalid','{}',now(),now());
INSERT INTO public.mentorship_matches(id,mentor_id,mentee_id,status,mentor_alias,mentee_alias) VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','active','Synthetic mentor','Synthetic mentee');
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
SET LOCAL request.jwt.claim.role='authenticated';
INSERT INTO public.mentorship_messages(id,match_id,sender_id,content) VALUES
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',auth.uid(),'Synthetic message from mentee') RETURNING id,read_at,flagged;
SET LOCAL request.jwt.claim.sub='22222222-2222-4222-8222-222222222222';
INSERT INTO public.mentorship_messages(id,match_id,sender_id,content) VALUES
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',auth.uid(),'Synthetic message from mentor') RETURNING id,read_at,flagged;
-- Decryption is service-role only; clients never call it.
DO $$ BEGIN
  PERFORM public.decrypt_message_content('\x00'::bytea,'none');
  RAISE EXCEPTION 'Clients can call decrypt_message_content';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
SET LOCAL ROLE service_role;
DO $$ DECLARE ciphertext bytea; key_id text; decrypted text; BEGIN
  SELECT encrypted_content,encryption_key_id INTO ciphertext,key_id FROM public.mentorship_messages WHERE id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2';
  decrypted := public.decrypt_message_content(ciphertext,key_id);
  IF decrypted <> 'Synthetic message from mentor' THEN RAISE EXCEPTION 'Persisted ciphertext cannot round-trip'; END IF;
END $$;
SET LOCAL ROLE authenticated;
SELECT public.mark_messages_read('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
DO $$ BEGIN
  IF (SELECT read_at FROM public.mentorship_messages WHERE id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1') IS NULL OR
     (SELECT read_at FROM public.mentorship_messages WHERE id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2') IS NOT NULL THEN
    RAISE EXCEPTION 'Read receipts must advance only for incoming messages';
  END IF;
  PERFORM public.flag_mentorship_message('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1','Synthetic safety concern');
  IF NOT EXISTS (SELECT FROM public.mentorship_messages WHERE id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'
                 AND flagged AND flag_reason='Synthetic safety concern') THEN
    RAISE EXCEPTION 'Message flag not persisted';
  END IF;
  BEGIN
    PERFORM public.delete_mentorship_message('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1');
    RAISE EXCEPTION 'Cross-sender deletion accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'Message not found or you do not have permission to delete it' THEN RAISE; END IF;
  END;
END $$;
SET LOCAL request.jwt.claim.sub='33333333-3333-4333-8333-333333333333';
DO $$ BEGIN
  BEGIN
    PERFORM public.mark_messages_read('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    RAISE EXCEPTION 'Nonparticipant receipt accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'You are not a participant in this mentorship' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK;
