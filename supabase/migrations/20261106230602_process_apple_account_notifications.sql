BEGIN;

CREATE OR REPLACE FUNCTION public.process_apple_account_event(
  p_subject text, p_type text, p_event_time bigint, p_email text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_users uuid[];
  v_user_id uuid;
  v_metadata jsonb;
  v_relay_email text;
  v_event_at timestamptz;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Unauthorized' USING ERRCODE = '42501';
  END IF;
  IF p_subject IS NULL OR btrim(p_subject) = '' OR length(p_subject) > 255
    OR p_type IS NULL OR p_type NOT IN ('email-disabled','email-enabled','consent-revoked','account-deleted')
    OR p_event_time IS NULL OR p_event_time <= 0 OR p_event_time > extract(epoch FROM now()) + 300 THEN
    RAISE EXCEPTION 'Invalid Apple account event' USING ERRCODE = '22023';
  END IF;
  SELECT array_agg(DISTINCT i.user_id) INTO v_users FROM auth.identities i
    WHERE i.provider = 'apple' AND i.identity_data->>'sub' = p_subject;
  IF coalesce(array_length(v_users, 1), 0) = 0 THEN RETURN NULL; END IF;
  IF array_length(v_users, 1) <> 1 THEN
    RAISE EXCEPTION 'Ambiguous Apple provider identity' USING ERRCODE = '23505';
  END IF;
  v_user_id := v_users[1];
  SELECT coalesce(raw_app_meta_data, '{}'::jsonb) INTO v_metadata
    FROM auth.users WHERE id = v_user_id FOR UPDATE;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT lower(i.identity_data->>'email') INTO v_relay_email FROM auth.identities i
    WHERE i.user_id = v_user_id AND i.provider = 'apple' AND i.identity_data->>'sub' = p_subject
      AND lower(i.identity_data->>'email') LIKE '%@privaterelay.appleid.com'
    LIMIT 1;
  -- A later signed event may have a relay newer than the provider identity.
  -- Events such as account-deleted omit email; keep that trusted current address.
  IF lower(v_metadata->>'apple_relay_email') LIKE '%@privaterelay.appleid.com' THEN
    v_relay_email := lower(v_metadata->>'apple_relay_email');
  END IF;
  IF lower(p_email) LIKE '%@privaterelay.appleid.com' THEN v_relay_email := lower(p_email); END IF;
  v_event_at := to_timestamp(p_event_time);

  IF p_type IN ('email-disabled','email-enabled','account-deleted') AND
     p_event_time > coalesce((v_metadata->>'apple_email_event_time')::bigint, 0) THEN
    v_metadata := v_metadata || jsonb_build_object(
      'apple_email_disabled', p_type <> 'email-enabled',
      'apple_email_event_time', p_event_time,
      'apple_relay_email', v_relay_email
    );
  END IF;
  IF p_type IN ('consent-revoked','account-deleted') THEN
    -- This is the Auth server's logout mechanism. A delayed/replayed Apple event
    -- must not sign out sessions created after the user authenticated again.
    DELETE FROM auth.sessions WHERE user_id = v_user_id
      AND (created_at IS NULL OR created_at < v_event_at + interval '1 second');
    DELETE FROM auth.refresh_tokens WHERE user_id = v_user_id::text
      AND (created_at IS NULL OR created_at < v_event_at + interval '1 second');
    IF p_event_time > coalesce((v_metadata->>'apple_credentials_revoked_at')::bigint, 0) THEN
      v_metadata := v_metadata || jsonb_build_object('apple_credentials_revoked_at', p_event_time);
    END IF;
    IF p_type = 'account-deleted' THEN
      v_metadata := v_metadata || jsonb_build_object('apple_account_deleted', true);
    END IF;
  END IF;
  -- Apple account deletion is not a request to delete the MindFriend account or
  -- another linked provider. Preserve application data and permit fresh sign-in.
  UPDATE auth.users SET raw_app_meta_data = v_metadata WHERE id = v_user_id;
  RETURN v_user_id;
END $$;
REVOKE ALL ON FUNCTION public.process_apple_account_event(text,text,bigint,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_apple_account_event(text,text,bigint,text) TO service_role;

COMMIT;
