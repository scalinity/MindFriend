BEGIN;
DROP POLICY "circle_posts_members_insert" ON public.circle_posts;
ALTER POLICY "Members can create posts" ON public.circle_posts TO authenticated
  WITH CHECK (auth.uid() = user_id AND public.is_circle_member(circle_id));
COMMIT;
