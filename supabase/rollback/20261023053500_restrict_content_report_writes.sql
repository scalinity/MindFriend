-- Security rollback restores the audited permissive write surface.
-- Use only after explicit security review; no report rows are modified.
BEGIN;
ALTER POLICY "Service role inserts content reports" ON public.gen_content_flags
  TO public WITH CHECK (true);
ALTER POLICY "Service role inserts content reports" ON public.gen_content_flags
  RENAME TO "Users can flag gen content";
GRANT INSERT ON public.gen_content_flags TO anon, authenticated;
COMMIT;
