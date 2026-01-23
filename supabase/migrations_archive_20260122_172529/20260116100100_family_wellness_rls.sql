-- Spec 11: Family Wellness - Row Level Security Policies
-- Complete RLS coverage for all family wellness tables

-- =============================================================================
-- MARK: - Enable RLS on all new tables
-- =============================================================================

ALTER TABLE family_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE family_challenge_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE family_challenge_participation ENABLE ROW LEVEL SECURITY;
ALTER TABLE together_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE together_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE together_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_age_ratings ENABLE ROW LEVEL SECURITY;
ALTER TABLE family_activity_summaries ENABLE ROW LEVEL SECURITY;
ALTER TABLE family_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE family_screen_time ENABLE ROW LEVEL SECURITY;
ALTER TABLE parental_consents ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- MARK: - Helper Functions for RLS
-- =============================================================================

-- Check if user is an active family member
CREATE OR REPLACE FUNCTION is_family_member(p_family_id UUID, p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM family_members
    WHERE family_id = p_family_id
      AND user_id = p_user_id
      AND status = 'active'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Check if user is a parent/admin in family
CREATE OR REPLACE FUNCTION is_family_parent(p_family_id UUID, p_user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM family_members
    WHERE family_id = p_family_id
      AND user_id = p_user_id
      AND status = 'active'
      AND role IN ('admin', 'parent')
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- =============================================================================
-- MARK: - family_challenges Policies
-- =============================================================================

CREATE POLICY "Family members can view their challenges"
  ON family_challenges FOR SELECT
  USING (is_family_member(family_id));

CREATE POLICY "Parents can create challenges"
  ON family_challenges FOR INSERT
  WITH CHECK (is_family_parent(family_id) AND created_by = auth.uid());

CREATE POLICY "Parents can update challenges"
  ON family_challenges FOR UPDATE
  USING (is_family_parent(family_id));

CREATE POLICY "Parents can delete challenges"
  ON family_challenges FOR DELETE
  USING (is_family_parent(family_id));

-- =============================================================================
-- MARK: - family_challenge_templates Policies
-- =============================================================================

CREATE POLICY "Anyone can view active challenge templates"
  ON family_challenge_templates FOR SELECT
  USING (is_active = true);

-- =============================================================================
-- MARK: - family_challenge_participation Policies
-- =============================================================================

CREATE POLICY "Family members can view participation"
  ON family_challenge_participation FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM family_challenges fc
      WHERE fc.id = challenge_id AND is_family_member(fc.family_id)
    )
  );

CREATE POLICY "Members can insert own participation"
  ON family_challenge_participation FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM family_members fm
      WHERE fm.id = member_id AND fm.user_id = auth.uid() AND fm.status = 'active'
    )
  );

CREATE POLICY "Members can update own participation"
  ON family_challenge_participation FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM family_members fm
      WHERE fm.id = member_id AND fm.user_id = auth.uid() AND fm.status = 'active'
    )
  );

-- =============================================================================
-- MARK: - together_templates Policies
-- =============================================================================

CREATE POLICY "Anyone can view active together templates"
  ON together_templates FOR SELECT
  USING (is_active = true);

-- =============================================================================
-- MARK: - together_sessions Policies
-- =============================================================================

CREATE POLICY "Family members can view their sessions"
  ON together_sessions FOR SELECT
  USING (is_family_member(family_id));

CREATE POLICY "Family members can create sessions"
  ON together_sessions FOR INSERT
  WITH CHECK (is_family_member(family_id) AND created_by = auth.uid());

CREATE POLICY "Session creators can update their sessions"
  ON together_sessions FOR UPDATE
  USING (created_by = auth.uid());

CREATE POLICY "Parents can delete sessions"
  ON together_sessions FOR DELETE
  USING (is_family_parent(family_id));

-- =============================================================================
-- MARK: - together_participants Policies
-- =============================================================================

CREATE POLICY "Participants can view session participants"
  ON together_participants FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM together_sessions ts
      WHERE ts.id = session_id AND is_family_member(ts.family_id)
    )
  );

CREATE POLICY "Session creator can add participants"
  ON together_participants FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM together_sessions ts
      WHERE ts.id = session_id AND ts.created_by = auth.uid()
    )
  );

CREATE POLICY "Participants can update own status"
  ON together_participants FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM family_members fm
      WHERE fm.id = member_id AND fm.user_id = auth.uid() AND fm.status = 'active'
    )
  );

-- =============================================================================
-- MARK: - content_age_ratings Policies
-- =============================================================================

CREATE POLICY "Anyone can view content age ratings"
  ON content_age_ratings FOR SELECT
  USING (true);

-- =============================================================================
-- MARK: - family_activity_summaries Policies
-- =============================================================================

CREATE POLICY "Parents can view family summaries"
  ON family_activity_summaries FOR SELECT
  USING (is_family_parent(family_id));

CREATE POLICY "Members can view own summaries"
  ON family_activity_summaries FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM family_members fm
      WHERE fm.id = member_id AND fm.user_id = auth.uid() AND fm.status = 'active'
    )
  );

CREATE POLICY "System can insert summaries"
  ON family_activity_summaries FOR INSERT
  WITH CHECK (true); -- Inserted by cron/functions

-- =============================================================================
-- MARK: - family_alerts Policies
-- =============================================================================

CREATE POLICY "Parents can view their alerts"
  ON family_alerts FOR SELECT
  USING (for_parent_id = auth.uid());

CREATE POLICY "Parents can update their alerts"
  ON family_alerts FOR UPDATE
  USING (for_parent_id = auth.uid());

CREATE POLICY "System can insert alerts"
  ON family_alerts FOR INSERT
  WITH CHECK (true); -- Inserted by generate-family-alerts function

-- =============================================================================
-- MARK: - family_screen_time Policies
-- =============================================================================

CREATE POLICY "Parents can view family screen time"
  ON family_screen_time FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM family_members fm
      WHERE fm.id = member_id
        AND is_family_parent(fm.family_id)
    )
  );

CREATE POLICY "Members can view own screen time"
  ON family_screen_time FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM family_members fm
      WHERE fm.id = member_id AND fm.user_id = auth.uid() AND fm.status = 'active'
    )
  );

CREATE POLICY "Members can insert own screen time"
  ON family_screen_time FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM family_members fm
      WHERE fm.id = member_id AND fm.user_id = auth.uid() AND fm.status = 'active'
    )
  );

CREATE POLICY "Members can update own screen time"
  ON family_screen_time FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM family_members fm
      WHERE fm.id = member_id AND fm.user_id = auth.uid() AND fm.status = 'active'
    )
  );

-- =============================================================================
-- MARK: - parental_consents Policies
-- =============================================================================

CREATE POLICY "Parents can view consent for their children"
  ON parental_consents FOR SELECT
  USING (parent_user_id = auth.uid());

CREATE POLICY "Parents can create consent"
  ON parental_consents FOR INSERT
  WITH CHECK (parent_user_id = auth.uid());

CREATE POLICY "Parents can update consent"
  ON parental_consents FOR UPDATE
  USING (parent_user_id = auth.uid());

-- Children can view their own consent status
CREATE POLICY "Children can view their consent"
  ON parental_consents FOR SELECT
  USING (child_user_id = auth.uid());
