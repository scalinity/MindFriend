-- Service-only request receipts prevent reconnect/retry from generating another charge.
CREATE TABLE public.chat_requests (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  request_id uuid NOT NULL,
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  content_hash text NOT NULL,
  response jsonb,
  response_status integer,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, request_id)
);
ALTER TABLE public.chat_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.chat_requests FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.chat_requests TO service_role;
