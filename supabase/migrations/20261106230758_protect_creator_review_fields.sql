BEGIN;
REVOKE INSERT, UPDATE ON public.creators, public.creator_content FROM PUBLIC, anon, authenticated;
GRANT INSERT (user_id,display_name,bio,profile_image_url,website_url,social_links,credentials,credential_documents)
  ON public.creators TO authenticated;
GRANT UPDATE (display_name,bio,profile_image_url,website_url,social_links)
  ON public.creators TO authenticated;

GRANT INSERT (creator_id,content_type,format,title,description,duration_seconds,difficulty,
  media_url,cover_image_url,thumbnail_url,category,tags,target_audience,transcript,transcript_url,
  has_captions,captions_url,trigger_warnings,age_rating,series_id,series_order,status,is_premium,allow_download)
  ON public.creator_content TO authenticated;
GRANT UPDATE (content_type,format,title,description,duration_seconds,difficulty,
  media_url,cover_image_url,thumbnail_url,category,tags,target_audience,transcript,transcript_url,
  has_captions,captions_url,trigger_warnings,age_rating,series_id,series_order,is_premium,allow_download)
  ON public.creator_content TO authenticated;

-- These trigger-only functions derive counters from RLS-authorized source rows.
-- Keep those writes privileged without granting clients editable counters or
-- publication fields, and prevent attaching them to attacker-created triggers.
ALTER FUNCTION public.update_content_rating_average() SECURITY DEFINER;
ALTER FUNCTION public.update_content_rating_average() SET search_path TO pg_catalog, public, pg_temp;
ALTER FUNCTION public.update_creator_content_metrics() SECURITY DEFINER;
ALTER FUNCTION public.update_creator_content_metrics() SET search_path TO pg_catalog, public, pg_temp;
ALTER FUNCTION public.update_creator_follower_count() SECURITY DEFINER;
ALTER FUNCTION public.update_creator_follower_count() SET search_path TO pg_catalog, public, pg_temp;
REVOKE ALL ON FUNCTION public.update_content_rating_average(), public.update_creator_content_metrics(),
  public.update_creator_follower_count() FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.protect_creator_draft_edits() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
  IF current_user IN ('anon','authenticated') THEN
    IF TG_OP = 'INSERT' THEN
      IF NEW.status IS DISTINCT FROM 'draft' THEN
        RAISE EXCEPTION 'New content must be a draft' USING ERRCODE='42501';
      END IF;
    ELSE
      IF OLD.status NOT IN ('draft','needs_changes','rejected') OR OLD.status IS NULL THEN
        RAISE EXCEPTION 'Only drafts or returned content can be edited' USING ERRCODE='42501';
      END IF;
      -- A revised returned draft must be submitted and reviewed again.
      NEW.status := 'draft';
      NEW.submitted_at := NULL;
      NEW.reviewed_at := NULL;
      NEW.reviewer_id := NULL;
      NEW.published_at := NULL;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.protect_creator_draft_edits() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER protect_creator_draft_edits BEFORE INSERT OR UPDATE ON public.creator_content
  FOR EACH ROW EXECUTE FUNCTION public.protect_creator_draft_edits();
COMMIT;
