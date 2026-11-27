-- therapist-invite stores only a SHA-256 hash of the invitation token, and therapist-accept
-- matches the incoming token against that hash and clears it on acceptance.
--
-- invitation_token stays because released clients select * from therapy_connections and decode
-- it as optional, but it is cleared and must stay empty: the deployed v26 function wrote raw
-- tokens signed with a known fallback secret into it, and both parties can read the row. The
-- check makes a redeploy of that copy fail instead of storing a raw token again.
ALTER TABLE public.therapy_connections ADD COLUMN IF NOT EXISTS invitation_token_hash text;

UPDATE public.therapy_connections SET invitation_token = NULL WHERE invitation_token IS NOT NULL;

ALTER TABLE public.therapy_connections
  ADD CONSTRAINT therapy_connections_no_raw_invitation_token CHECK (invitation_token IS NULL);
