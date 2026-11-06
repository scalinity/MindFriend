-- Synthetic platform compatibility only. Not an application migration.
-- The postgres image includes legacy Auth helpers; these accept current JWT claims.
ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz;
CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT COALESCE(NULLIF(current_setting('request.jwt.claim', true), ''),
                 NULLIF(current_setting('request.jwt.claims', true), ''))::jsonb;
$$;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT COALESCE(NULLIF(current_setting('request.jwt.claim.sub', true), ''),
                 auth.jwt()->>'sub')::uuid;
$$;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
 SELECT COALESCE(NULLIF(current_setting('request.jwt.claim.role', true), ''), auth.jwt()->>'role');
$$;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.jwt(),auth.uid(),auth.role() TO anon,authenticated,service_role;
DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_publication WHERE pubname='supabase_realtime') THEN CREATE PUBLICATION supabase_realtime; END IF; END $$;
