-- Actual migration-chain export qualification. Synthetic accounts from support_session.sql
-- only; the harness creates an owned network-free disposable database and removes it.
\set ON_ERROR_STOP on
RESET ROLE;
DO $$ BEGIN
  IF current_database() <> 'restoration_synthetic'
     OR EXISTS(SELECT FROM auth.users WHERE id NOT IN (
       'aaaaaaaa-0000-4000-8000-000000000001', 'bbbbbbbb-0000-4000-8000-000000000002')) THEN
    RAISE EXCEPTION 'Requires the owned support-session synthetic fixture';
  END IF;
END $$;
INSERT INTO public.conversations(id,user_id,title)
VALUES('c4000000-0000-4000-8000-000000000001','aaaaaaaa-0000-4000-8000-000000000001','Synthetic export pagination');
INSERT INTO public.messages(id,conversation_id,role,content)
SELECT ('f4000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  'c4000000-0000-4000-8000-000000000001', 'user', 'Synthetic export row '||n
FROM generate_series(1,205) n;
INSERT INTO public.messages(id,conversation_id,role,content)
VALUES('f4000000-0000-4000-8000-000000000999','cccccccc-0000-4000-8000-000000000002',
       'user','OTHER_OWNER_EXPORT_SENTINEL');
INSERT INTO public.support_memory_suggestion_requests(user_id,request_id,support_session_id,conversation_id,payload_hash,privacy_revision,
  source_count,status,dispatched_at,finished_at)
SELECT 'aaaaaaaa-0000-4000-8000-000000000001', ('f4800000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  (SELECT id FROM public.support_work_sessions WHERE user_id='aaaaaaaa-0000-4000-8000-000000000001' ORDER BY id LIMIT 1),
  'c4000000-0000-4000-8000-000000000001',repeat('a',64),1,1,'unknown',now(),now()
FROM generate_series(1,205) n;
INSERT INTO public.support_memory_suggestion_requests(user_id,request_id,support_session_id,conversation_id,payload_hash,privacy_revision,
  source_count,status,dispatched_at,finished_at)
SELECT 'bbbbbbbb-0000-4000-8000-000000000002','f4800000-0000-4000-8000-000000000001',id,
  'cccccccc-0000-4000-8000-000000000002',repeat('b',64),1,1,'unknown',now(),now()
FROM public.support_work_sessions WHERE user_id='bbbbbbbb-0000-4000-8000-000000000002' ORDER BY id LIMIT 1;
CREATE TABLE support_test.export_expected AS
SELECT count(*)::integer AS messages FROM public.messages m JOIN public.conversations c ON c.id=m.conversation_id
WHERE c.user_id='aaaaaaaa-0000-4000-8000-000000000001';
GRANT SELECT ON support_test.export_expected TO authenticated;
SELECT support_test.as_user('aaaaaaaa-0000-4000-8000-000000000001');
DO $$
DECLARE
  dataset text; cursor_key text; last_key text; p jsonb; r jsonb;
  seen text[]; total integer; pages integer;
  owner_id constant uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
BEGIN
  FOREACH dataset IN ARRAY ARRAY[
    'profile','user_settings','moods','quests','conversations','messages','circle_memberships',
    'exercise_sessions','subscriptions','crisis_events','companion_memories','memory_fragments',
    'support_privacy_state','support_sessions','support_activities','support_session_events',
    'support_mutation_receipts','support_proposals','support_context_receipts',
    'support_context_receipt_sources','support_privacy_operations','support_suppressions',
    'support_memory_events','support_onboarding_consent','offline_mutation_receipts','support_memory_suggestion_requests'] LOOP
    cursor_key := NULL; last_key := NULL; seen := '{}'; total := 0; pages := 0;
    LOOP
      p := public.export_owner_data_page(owner_id,dataset,cursor_key,100);
      IF p->>'status'<>'available' OR p->>'owner'<>owner_id::text OR p->>'dataset'<>dataset
         OR jsonb_array_length(p->'rows')>100 OR (p->>'row_count')::integer<>jsonb_array_length(p->'rows') THEN
        RAISE EXCEPTION 'Actual-chain export page invalid for %',dataset;
      END IF;
      FOR r IN SELECT * FROM jsonb_array_elements(p->'rows') LOOP
        IF r->>'export_owner_id'<>owner_id::text OR r::text LIKE '%OTHER_OWNER_EXPORT_SENTINEL%'
           OR r->>'export_key'=ANY(seen) OR (last_key IS NOT NULL AND r->>'export_key'<=last_key) THEN
          RAISE EXCEPTION 'Export owner/order/duplicate violation in %',dataset;
        END IF;
        last_key := r->>'export_key'; seen := array_append(seen,last_key); total := total+1;
        IF dataset='support_memory_suggestion_requests' AND
          (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(r) k) IS DISTINCT FROM
          (SELECT array_agg(k ORDER BY k) FROM unnest(ARRAY['user_id','request_id','support_session_id','conversation_id',
           'payload_hash','privacy_revision','source_count','status','failure_code','attempt','candidate_ids','skipped_count',
           'claimed_at','dispatched_at','finished_at','created_at','updated_at','export_owner_id','export_key']) k) THEN
          RAISE EXCEPTION 'Memory request export changed its content-free column set';
        END IF;
        IF dataset='profile' AND (r ? 'push_token' OR r ? 'referred_by') THEN
          RAISE EXCEPTION 'Profile export leaked excluded fields';
        END IF;
        IF dataset='subscriptions' AND (r ? 'original_transaction_id' OR r ? 'last_transaction_id') THEN
          RAISE EXCEPTION 'Subscription export leaked excluded identifiers';
        END IF;
      END LOOP;
      pages := pages+1;
      EXIT WHEN NOT (p->>'has_more')::boolean;
      IF pages>100 OR p->>'next_cursor' IS NULL OR p->>'next_cursor' IS NOT DISTINCT FROM cursor_key THEN
        RAISE EXCEPTION 'Export cursor failed to advance';
      END IF;
      cursor_key := p->>'next_cursor';
    END LOOP;
    IF dataset='messages' AND (total<>(SELECT messages FROM support_test.export_expected) OR pages<3) THEN
      RAISE EXCEPTION 'Actual-chain message pagination incomplete: % rows, % pages',total,pages;
    END IF;
    IF dataset='support_memory_suggestion_requests' AND (total<>205 OR pages<>3) THEN
      RAISE EXCEPTION 'Memory request export omitted, duplicated or leaked owner rows: % rows, % pages',total,pages;
    END IF;
  END LOOP;
  BEGIN
    PERFORM public.export_owner_data_page('bbbbbbbb-0000-4000-8000-000000000002','messages',NULL,100);
    RAISE EXCEPTION 'Wrong expected owner was accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET ROLE anon;
DO $$ BEGIN
  BEGIN
    PERFORM public.export_owner_data_page('aaaaaaaa-0000-4000-8000-000000000001','messages',NULL,100);
    RAISE EXCEPTION 'Anonymous export was accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
\echo 'Actual-chain export: 26 datasets, owner isolation and >100-row message/memory-request pagination passed'
