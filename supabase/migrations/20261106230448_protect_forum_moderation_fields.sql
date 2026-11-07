BEGIN;
CREATE FUNCTION public.protect_forum_moderation_fields() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path TO pg_catalog, public, pg_temp
AS $$
DECLARE
  trusted_moderator boolean := current_user NOT IN ('anon','authenticated')
    OR public.is_moderator();
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.updated_at := clock_timestamp();
    IF NOT trusted_moderator THEN
      NEW.created_at := NEW.updated_at;
      NEW.status := 'pending';
      NEW.moderation_confidence := NULL;
      NEW.is_crisis := false;
    END IF;
  ELSE
    -- Runs after the existing updated_at triggers. Every revision is generated
    -- by the database, including trusted moderation and counter updates.
    NEW.updated_at := GREATEST(clock_timestamp(), OLD.updated_at + interval '1 microsecond');
    IF current_user IN ('anon','authenticated') AND (
      NEW.id IS DISTINCT FROM OLD.id OR NEW.author_id IS DISTINCT FROM OLD.author_id
      OR NEW.created_at IS DISTINCT FROM OLD.created_at
    ) THEN
      RAISE EXCEPTION 'Forum identity and creation time are immutable' USING ERRCODE='42501';
    END IF;
    IF NOT trusted_moderator THEN
      IF NEW.status IS DISTINCT FROM OLD.status
        OR NEW.moderation_confidence IS DISTINCT FROM OLD.moderation_confidence
        OR NEW.is_crisis IS DISTINCT FROM OLD.is_crisis THEN
        RAISE EXCEPTION 'Moderation fields require a moderator' USING ERRCODE='42501';
      END IF;
      IF NEW.content IS DISTINCT FROM OLD.content
        OR (to_jsonb(NEW)->>'title') IS DISTINCT FROM (to_jsonb(OLD)->>'title') THEN
        NEW.status := 'pending';
        NEW.moderation_confidence := NULL;
        NEW.is_crisis := false;
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.protect_forum_moderation_fields() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER zz_protect_forum_moderation BEFORE INSERT OR UPDATE ON public.forum_threads
  FOR EACH ROW EXECUTE FUNCTION public.protect_forum_moderation_fields();
CREATE TRIGGER zz_protect_forum_moderation BEFORE INSERT OR UPDATE ON public.forum_replies
  FOR EACH ROW EXECUTE FUNCTION public.protect_forum_moderation_fields();
COMMIT;
