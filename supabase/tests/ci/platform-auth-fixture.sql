-- Isolated synthetic platform fixture only, not an application migration.
-- Bare postgres image has legacy auth.users and auth.refresh_tokens but no
-- auth.identities/auth.sessions, no email_confirmed_at and no session_id FK.
-- Minimal columns needed by verified-email and Apple notification regressions.
-- Ownership/ACLs mirror this image's existing auth.users/auth.refresh_tokens.
BEGIN;
ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz;
CREATE TABLE auth.identities (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 provider_id text NOT NULL,
 provider text NOT NULL,
 identity_data jsonb NOT NULL
);
CREATE TABLE auth.sessions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 created_at timestamptz
);
ALTER TABLE auth.refresh_tokens ADD COLUMN session_id uuid
 REFERENCES auth.sessions(id) ON DELETE CASCADE;
ALTER TABLE auth.identities OWNER TO supabase_auth_admin;
ALTER TABLE auth.sessions OWNER TO supabase_auth_admin;
GRANT ALL ON auth.identities,auth.sessions TO dashboard_user,postgres;
COMMIT;
