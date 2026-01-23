-- Migration: Optimize Family RLS with Helper Function
-- Address P2 Performance issue: Move complex repeated subqueries to SECURITY DEFINER function

-- 1. Create helper function for family membership check
-- Checks if user is either the Family Admin OR an Active Member
CREATE OR REPLACE FUNCTION public.is_family_member(check_family_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT 
    -- User is the admin of the family group
    EXISTS (
      SELECT 1 FROM family_groups
      WHERE id = check_family_id
      AND admin_user_id = auth.uid()
    )
    OR
    -- OR user is an active member of the family
    EXISTS (
      SELECT 1 FROM family_members
      WHERE family_id = check_family_id
      AND user_id = auth.uid()
      AND status = 'active'
    );
$$;

GRANT EXECUTE ON FUNCTION public.is_family_member(uuid) TO authenticated;

-- 2. Optimize family_activity_summaries policies
DO $$ BEGIN
  DROP POLICY IF EXISTS "Family members can insert summaries" ON family_activity_summaries;
  DROP POLICY IF EXISTS "Family members can view summaries" ON family_activity_summaries;
  
  -- Recreate using optimized function
  CREATE POLICY "Family members can insert summaries"
    ON family_activity_summaries FOR INSERT
    WITH CHECK (public.is_family_member(family_id));
    
  CREATE POLICY "Family members can view summaries"
    ON family_activity_summaries FOR SELECT
    USING (public.is_family_member(family_id));
END $$;

-- 3. Optimize family_alerts policies
-- Note: family_alerts uses for_parent_id for insert, but viewing might be family-wide or parent-specific
-- Inspecting typical usage: Alerts are usually per-user, but let's check if there are family-wide policies.
-- Existing policy "Parents can receive alerts for themselves" checks `for_parent_id = auth.uid()`. This is fine.
-- Let's check "Family members can view alerts".

DO $$ BEGIN
  -- If there's a policy checking family membership for alerts, optimize it
  IF EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'family_alerts' AND policyname = 'Family members can view alerts') THEN
    DROP POLICY "Family members can view alerts" ON family_alerts;
    
    CREATE POLICY "Family members can view alerts"
      ON family_alerts FOR SELECT
      USING (public.is_family_member(family_id));
  END IF;
END $$;

-- 4. Optimize family_wellness_goals policies (if exists)
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'family_wellness_goals') THEN
    DROP POLICY IF EXISTS "Family members can view goals" ON family_wellness_goals;
    DROP POLICY IF EXISTS "Family members can manage goals" ON family_wellness_goals;
    
    CREATE POLICY "Family members can view goals"
      ON family_wellness_goals FOR SELECT
      USING (public.is_family_member(family_id));
      
    CREATE POLICY "Family members can manage goals"
      ON family_wellness_goals FOR ALL
      USING (public.is_family_member(family_id));
  END IF;
END $$;

-- 5. Audit log
DO $$ BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'audit_log') THEN
    INSERT INTO audit_log (table_name, operation, description, change_date)
    VALUES (
      'family_members',
      'OPTIMIZATION',
      'Implemented is_family_member SECURITY DEFINER function for RLS performance',
      NOW()
    );
  END IF;
EXCEPTION WHEN UNDEFINED_TABLE THEN
  NULL;
END $$;
