-- Run against the disposable fully migrated fixture plus modern Auth tables.
BEGIN;
SET LOCAL statement_timeout = '20s';
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
SELECT set_config('request.jwt.claim.role','service_role',true);
INSERT INTO auth.users(id,email,raw_user_meta_data,raw_app_meta_data) VALUES
 ('18100000-0000-4000-8000-000000000001','relay@privaterelay.appleid.com','{}','{"existing":"preserve"}'),
 ('18100000-0000-4000-8000-000000000002','other@example.invalid','{"sub":"synthetic.apple.subject"}','{}');
INSERT INTO public.profiles(id) SELECT id FROM auth.users WHERE id::text LIKE '18100000-%' ON CONFLICT(id) DO NOTHING;
INSERT INTO auth.identities(id,user_id,provider,identity_data) VALUES
 ('18100000-0000-4000-8000-000000000011','18100000-0000-4000-8000-000000000001','apple','{"sub":"synthetic.apple.subject","email":"relay@privaterelay.appleid.com"}'),
 ('18100000-0000-4000-8000-000000000012','18100000-0000-4000-8000-000000000001','google','{"sub":"google.subject"}'),
 ('18100000-0000-4000-8000-000000000013','18100000-0000-4000-8000-000000000002','apple','{"sub":"other.apple.subject","email":"other@example.invalid"}');
-- Use events in the recent past so ordering and later sign-ins are testable.
CREATE TEMP TABLE apple_event_clock AS SELECT floor(extract(epoch FROM now()))::bigint - 100 AS event_time;
INSERT INTO auth.sessions(id,user_id,created_at) VALUES
 ('18100000-0000-4000-8000-000000000021','18100000-0000-4000-8000-000000000001',now()-interval '1 day'),
 ('18100000-0000-4000-8000-000000000022','18100000-0000-4000-8000-000000000001',now()-interval '10 seconds'),
 ('18100000-0000-4000-8000-000000000023','18100000-0000-4000-8000-000000000002',now()-interval '1 day');
INSERT INTO auth.refresh_tokens(token,user_id,created_at,session_id) VALUES
 ('synthetic-old','18100000-0000-4000-8000-000000000001',now()-interval '1 day','18100000-0000-4000-8000-000000000021'),
 ('synthetic-new','18100000-0000-4000-8000-000000000001',now()-interval '10 seconds','18100000-0000-4000-8000-000000000022'),
 ('synthetic-other','18100000-0000-4000-8000-000000000002',now()-interval '1 day','18100000-0000-4000-8000-000000000023'),
 ('synthetic-legacy','18100000-0000-4000-8000-000000000001',now()-interval '1 day',NULL);
DO $$ DECLARE t bigint; result uuid; metadata jsonb; BEGIN
 SELECT event_time INTO t FROM apple_event_clock;
 result := public.process_apple_account_event('synthetic.apple.subject','email-disabled',t);
 IF result IS DISTINCT FROM '18100000-0000-4000-8000-000000000001'::uuid THEN RAISE EXCEPTION 'Apple subject did not resolve trusted identity'; END IF;
 SELECT raw_app_meta_data INTO metadata FROM auth.users WHERE id=result;
 IF metadata->>'apple_email_disabled' IS DISTINCT FROM 'true' OR metadata->>'apple_relay_email' IS DISTINCT FROM 'relay@privaterelay.appleid.com' OR metadata->>'existing' IS DISTINCT FROM 'preserve' THEN RAISE EXCEPTION 'Trusted email state missing or unrelated metadata lost'; END IF;
 IF EXISTS(SELECT 1 FROM auth.users WHERE id='18100000-0000-4000-8000-000000000002' AND raw_app_meta_data ? 'apple_email_disabled') THEN RAISE EXCEPTION 'Client-editable sub selected another account'; END IF;
 IF (SELECT count(*) FROM auth.sessions WHERE user_id=result) <> 2 THEN RAISE EXCEPTION 'Email change revoked sessions'; END IF;
 PERFORM public.process_apple_account_event('synthetic.apple.subject','email-enabled',t-1);
 IF (SELECT raw_app_meta_data->>'apple_email_disabled' FROM auth.users WHERE id=result) <> 'true' THEN RAISE EXCEPTION 'Old email event overrode new state'; END IF;
 PERFORM public.process_apple_account_event('synthetic.apple.subject','email-enabled',t+1,'updated@privaterelay.appleid.com');
 IF (SELECT raw_app_meta_data->>'apple_email_disabled' FROM auth.users WHERE id=result) <> 'false' OR
    (SELECT raw_app_meta_data->>'apple_relay_email' FROM auth.users WHERE id=result) <> 'updated@privaterelay.appleid.com' THEN RAISE EXCEPTION 'New signed email forwarding change ignored'; END IF;
 PERFORM public.process_apple_account_event('synthetic.apple.subject','consent-revoked',t+2);
 IF EXISTS(SELECT 1 FROM auth.sessions WHERE id='18100000-0000-4000-8000-000000000021') OR
    EXISTS(SELECT 1 FROM auth.refresh_tokens WHERE token IN ('synthetic-old','synthetic-legacy')) THEN RAISE EXCEPTION 'Revocation retained old sessions/tokens'; END IF;
 IF (SELECT count(*) FROM auth.sessions WHERE id IN ('18100000-0000-4000-8000-000000000022','18100000-0000-4000-8000-000000000023')) <> 2 OR
    (SELECT count(*) FROM auth.refresh_tokens WHERE token IN ('synthetic-new','synthetic-other')) <> 2 THEN RAISE EXCEPTION 'Revocation removed newer or unrelated sessions'; END IF;
 PERFORM public.process_apple_account_event('synthetic.apple.subject','consent-revoked',t+2);
 PERFORM public.process_apple_account_event('synthetic.apple.subject','account-deleted',t+3);
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=result) OR NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=result) OR
    NOT EXISTS(SELECT 1 FROM auth.identities WHERE user_id=result AND provider='google') THEN RAISE EXCEPTION 'Apple deletion removed app account/data/other provider'; END IF;
 IF (SELECT raw_app_meta_data->>'apple_account_deleted' FROM auth.users WHERE id=result) <> 'true' OR
    (SELECT raw_app_meta_data->>'apple_email_disabled' FROM auth.users WHERE id=result) <> 'true' THEN RAISE EXCEPTION 'Apple deletion state missing'; END IF;
 IF public.process_apple_account_event('unknown.subject','account-deleted',t) IS NOT NULL THEN RAISE EXCEPTION 'Unknown Apple identity resolved'; END IF;
 IF has_function_privilege('anon','public.process_apple_account_event(text,text,bigint,text)','EXECUTE') OR
    has_function_privilege('authenticated','public.process_apple_account_event(text,text,bigint,text)','EXECUTE') THEN RAISE EXCEPTION 'Client can forge Apple events'; END IF;
END $$;
-- Ambiguous trusted identities fail rather than picking an arbitrary account.
INSERT INTO auth.identities(id,user_id,provider,identity_data) VALUES
 ('18100000-0000-4000-8000-000000000014','18100000-0000-4000-8000-000000000002','apple','{"sub":"synthetic.apple.subject"}');
DO $$ BEGIN
 BEGIN
  PERFORM public.process_apple_account_event('synthetic.apple.subject','account-deleted',(SELECT event_time FROM apple_event_clock));
  RAISE EXCEPTION 'Ambiguous identity accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
END $$;
DELETE FROM auth.identities WHERE id='18100000-0000-4000-8000-000000000014';
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"18100000-0000-4000-8000-000000000001"}',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 BEGIN
  PERFORM public.process_apple_account_event('synthetic.apple.subject','account-deleted',1);
  RAISE EXCEPTION 'Authenticated caller forged Apple event';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT 'PASS: identity binding, email ordering, consent/session revocation, replay, account preservation and service-only authorization';
ROLLBACK;
