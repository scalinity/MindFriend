-- A device token belongs to the account currently registering that exact device.
CREATE SCHEMA IF NOT EXISTS private;
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE OR REPLACE FUNCTION private.register_current_device(p_device_token text, p_platform text DEFAULT 'ios')
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_owner uuid := auth.uid();
  v_token text := lower(p_device_token);
BEGIN
  IF v_owner IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  IF v_token IS NULL OR length(v_token) NOT BETWEEN 2 AND 1024
     OR length(v_token) % 2 <> 0 OR v_token !~ '^[0-9a-f]+$'
     OR p_platform IS DISTINCT FROM 'ios' THEN
    RAISE EXCEPTION 'Invalid device registration' USING ERRCODE = '22023';
  END IF;
  -- Serialize account switches for the same token without locking other devices.
  PERFORM pg_advisory_xact_lock(hashtextextended('push-token:' || v_token, 0));
  DELETE FROM public.push_tokens
  WHERE lower(device_token) = v_token AND (user_id <> v_owner OR device_token <> v_token);
  INSERT INTO public.push_tokens(user_id, device_token, platform, updated_at)
  VALUES (v_owner, v_token, p_platform, now())
  ON CONFLICT (user_id, device_token) DO UPDATE SET platform = EXCLUDED.platform, updated_at = EXCLUDED.updated_at;
  RETURN v_owner;
END;
$$;
REVOKE ALL ON FUNCTION private.register_current_device(text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.register_current_device(text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.register_current_device(p_device_token text, p_platform text DEFAULT 'ios')
RETURNS uuid
LANGUAGE sql SECURITY INVOKER
SET search_path = pg_catalog, public, pg_temp
AS $$ SELECT private.register_current_device(p_device_token, p_platform); $$;
REVOKE ALL ON FUNCTION public.register_current_device(text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_current_device(text,text) TO authenticated;
