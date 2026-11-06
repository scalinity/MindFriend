-- Direct circle membership is reserved for the creator; everyone else proves an invite.
BEGIN;
ALTER POLICY "Users can join circles" ON public.circle_members TO authenticated
  WITH CHECK (user_id = auth.uid() AND EXISTS (
    SELECT 1 FROM public.circles AS circle
    WHERE circle.id = circle_members.circle_id AND circle.owner_id = auth.uid()
  ));
-- Both schema roles are valid for the actual creator; the current app omits role
-- and uses its member default. Invite acceptance always inserts member explicitly.

ALTER POLICY "Users can join rituals" ON public.circle_ritual_attendees TO authenticated
  WITH CHECK (user_id = auth.uid() AND EXISTS (
    SELECT 1 FROM public.circle_rituals AS ritual
    WHERE ritual.id = circle_ritual_attendees.ritual_id
      AND ritual.status IN ('scheduled','active') AND public.is_circle_member(ritual.circle_id)
  ));
ALTER POLICY "Users can leave rituals" ON public.circle_ritual_attendees TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid() AND EXISTS (
    SELECT 1 FROM public.circle_rituals AS ritual
    WHERE ritual.id = circle_ritual_attendees.ritual_id AND public.is_circle_member(ritual.circle_id)
  ));
REVOKE UPDATE ON public.circle_ritual_attendees FROM PUBLIC, anon, authenticated;
GRANT UPDATE (left_at) ON public.circle_ritual_attendees TO authenticated;
ALTER POLICY "Users can add reflections" ON public.circle_ritual_reflections TO authenticated
  WITH CHECK (user_id = auth.uid() AND EXISTS (
    SELECT 1 FROM public.circle_rituals AS ritual
    JOIN public.circle_ritual_attendees AS attendee ON attendee.ritual_id = ritual.id
    WHERE ritual.id = circle_ritual_reflections.ritual_id AND ritual.status = 'completed'
      AND public.is_circle_member(ritual.circle_id) AND attendee.user_id = auth.uid()
  ));

CREATE OR REPLACE FUNCTION "public"."join_circle_by_invite_code"("p_invite_code" "text") RETURNS TABLE("circle_id" "uuid", "circle_name" "text", "member_count" integer, "success" boolean, "message" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET search_path TO pg_catalog, public, pg_temp
    AS $$
DECLARE
  v_user_id UUID;
  v_circle_id UUID;
  v_circle_name TEXT;
  v_max_members INT;
  v_current_members INT;
BEGIN
  -- Get the authenticated user
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, NULL::TEXT, 0, false, 'Not authenticated'::TEXT;
    RETURN;
  END IF;

  -- Normalize invite code (uppercase, trim whitespace)
  p_invite_code := UPPER(TRIM(p_invite_code));

  -- Find the circle by invite code
  SELECT c.id, c.name, c.max_members
  INTO v_circle_id, v_circle_name, v_max_members
  FROM circles c
  WHERE c.invite_code = p_invite_code
  FOR UPDATE;

  IF v_circle_id IS NULL THEN
    RETURN QUERY SELECT NULL::UUID, NULL::TEXT, 0, false, 'Invalid invite code'::TEXT;
    RETURN;
  END IF;

  -- Check if user is already a member
  IF EXISTS (
    SELECT 1 FROM circle_members cm
    WHERE cm.circle_id = v_circle_id AND cm.user_id = v_user_id
  ) THEN
    -- Already a member - return success with circle info
    SELECT COUNT(*) INTO v_current_members
    FROM circle_members cm WHERE cm.circle_id = v_circle_id;

    RETURN QUERY SELECT v_circle_id, v_circle_name, v_current_members::INT, true, 'Already a member'::TEXT;
    RETURN;
  END IF;

  -- Check member limit
  SELECT COUNT(*) INTO v_current_members
  FROM circle_members cm WHERE cm.circle_id = v_circle_id;

  IF v_current_members >= v_max_members THEN
    RETURN QUERY SELECT v_circle_id, v_circle_name, v_current_members::INT, false, 'Circle is full'::TEXT;
    RETURN;
  END IF;

  -- Add user as member
  INSERT INTO circle_members (circle_id, user_id, role, joined_at)
  VALUES (v_circle_id, v_user_id, 'member', NOW());

  -- Return success
  RETURN QUERY SELECT v_circle_id, v_circle_name, (v_current_members + 1)::INT, true, 'Joined successfully'::TEXT;
END;
$$;
REVOKE ALL ON FUNCTION public.join_circle_by_invite_code(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_circle_by_invite_code(text) TO authenticated, service_role;
COMMIT;
