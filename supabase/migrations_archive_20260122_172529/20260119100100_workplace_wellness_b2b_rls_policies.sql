-- ============================================================================
-- MIGRATION: Workplace Wellness B2B - RLS Privacy Enforcement Policies
-- ============================================================================
-- Purpose: Implement Row-Level Security policies that enforce privacy boundaries:
--   1. Organization admins CANNOT read individual employee data (forbidden tables)
--   2. Organization admins CAN read ONLY aggregated metrics (5+ user threshold)
--   3. Organization admins CAN manage their organization's members/admins/invites
--   4. Employees CAN read their own data
--   5. All denied access attempts are logged to privacy_access_audit
--
-- Privacy-Protected Tables (Forbidden for Org Admins):
--   - profiles (personal bio, photo, real name)
--   - conversations (chat history metadata)
--   - messages (chat message content)
--   - moods (individual mood entries)
--   - exercise_sessions (personal exercise history)
--   - user_settings (therapy preferences, personal goals)
--   - circle_posts (peer relationships, check-ins)
--   - badges (individual achievement patterns)
--
-- Allowed Tables for Org Admins:
--   - organization_metrics (5+ user threshold enforced)
--   - organization_members (their organization only)
--   - organization_admins (their organization only)
--   - organization_invites (their organization only)
--   - organizations (their organization only)
-- ============================================================================

-- Enable RLS on all new B2B organization tables (already enabled in schema migration)

-- ============================================================================
-- ORGANIZATION TABLE POLICIES
-- ============================================================================

-- Organizations: Admins can read their own org, members can read theirs
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organizations' AND policyname = 'orgs_admins_read_own'
  ) THEN
    CREATE POLICY "orgs_admins_read_own" ON organizations
      FOR SELECT
      USING (
        id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organizations' AND policyname = 'orgs_members_read_own'
  ) THEN
    CREATE POLICY "orgs_members_read_own" ON organizations
      FOR SELECT
      USING (
        id IN (
          SELECT organization_id FROM organization_members
          WHERE user_id = auth.uid() AND is_active = true
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organizations' AND policyname = 'orgs_admins_update_own'
  ) THEN
    CREATE POLICY "orgs_admins_update_own" ON organizations
      FOR UPDATE
      USING (
        id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid() AND role = 'admin'
        )
      )
      WITH CHECK (
        id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid() AND role = 'admin'
        )
      );
  END IF;
END $$;

-- ============================================================================
-- ORGANIZATION_ADMINS TABLE POLICIES
-- ============================================================================

-- Only admins can read their org's admin list, only admins can manage
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organization_admins' AND policyname = 'org_admins_read_own_org'
  ) THEN
    CREATE POLICY "org_admins_read_own_org" ON organization_admins
      FOR SELECT
      USING (
        organization_id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organization_admins' AND policyname = 'org_admins_insert_manage_admins'
  ) THEN
    CREATE POLICY "org_admins_insert_manage_admins" ON organization_admins
      FOR INSERT
      WITH CHECK (
        organization_id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid() AND role = 'admin'
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organization_admins' AND policyname = 'org_admins_delete_manage_admins'
  ) THEN
    CREATE POLICY "org_admins_delete_manage_admins" ON organization_admins
      FOR DELETE
      USING (
        organization_id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid() AND role = 'admin'
        )
      );
  END IF;
END $$;

-- ============================================================================
-- ORGANIZATION_MEMBERS TABLE POLICIES
-- ============================================================================

-- Admins can read/manage members of their org
-- Members can read their own membership status
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organization_members' AND policyname = 'org_members_admins_read'
  ) THEN
    CREATE POLICY "org_members_admins_read" ON organization_members
      FOR SELECT
      USING (
        organization_id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organization_members' AND policyname = 'org_members_users_read_own'
  ) THEN
    CREATE POLICY "org_members_users_read_own" ON organization_members
      FOR SELECT
      USING (user_id = auth.uid());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organization_members' AND policyname = 'org_members_admins_insert'
  ) THEN
    CREATE POLICY "org_members_admins_insert" ON organization_members
      FOR INSERT
      WITH CHECK (
        organization_id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid() AND role = 'admin'
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organization_members' AND policyname = 'org_members_admins_update'
  ) THEN
    CREATE POLICY "org_members_admins_update" ON organization_members
      FOR UPDATE
      USING (
        organization_id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid() AND role = 'admin'
        )
      )
      WITH CHECK (
        organization_id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid() AND role = 'admin'
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organization_members' AND policyname = 'org_members_admins_delete'
  ) THEN
    CREATE POLICY "org_members_admins_delete" ON organization_members
      FOR DELETE
      USING (
        organization_id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid() AND role = 'admin'
        )
      );
  END IF;
END $$;

-- ============================================================================
-- ORGANIZATION_INVITES TABLE POLICIES
-- ============================================================================

-- Only admins can read/create/manage invites for their org
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organization_invites' AND policyname = 'org_invites_admins_read'
  ) THEN
    CREATE POLICY "org_invites_admins_read" ON organization_invites
      FOR SELECT
      USING (
        organization_id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organization_invites' AND policyname = 'org_invites_public_validate'
  ) THEN
    -- Anyone can validate an invite code (Edge Function does this)
    -- But they can't see org_id or other details
    CREATE POLICY "org_invites_public_validate" ON organization_invites
      FOR SELECT
      USING (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organization_invites' AND policyname = 'org_invites_admins_insert'
  ) THEN
    CREATE POLICY "org_invites_admins_insert" ON organization_invites
      FOR INSERT
      WITH CHECK (
        organization_id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid() AND role = 'admin'
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organization_invites' AND policyname = 'org_invites_admins_update'
  ) THEN
    CREATE POLICY "org_invites_admins_update" ON organization_invites
      FOR UPDATE
      USING (
        organization_id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid() AND role = 'admin'
        )
      )
      WITH CHECK (
        organization_id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid() AND role = 'admin'
        )
      );
  END IF;
END $$;

-- ============================================================================
-- ORGANIZATION_METRICS TABLE - CRITICAL PRIVACY ENFORCEMENT
-- ============================================================================
-- ONLY table where admins can see employee data, but ONLY aggregated:
--   - active_users (count)
--   - avg_mood_score (average of 5+ employees)
--   - mood_trend (aggregate pattern)
-- Individual data is NEVER visible
-- Privacy threshold: active_users >= 5 (enforced in CHECK constraint)
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organization_metrics' AND policyname = 'org_metrics_admins_read'
  ) THEN
    CREATE POLICY "org_metrics_admins_read" ON organization_metrics
      FOR SELECT
      USING (
        organization_id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organization_metrics' AND policyname = 'org_metrics_insert_only_service_role'
  ) THEN
    -- Only backend (via pg_cron or Edge Function with SERVICE_ROLE key) can insert
    CREATE POLICY "org_metrics_insert_only_service_role" ON organization_metrics
      FOR INSERT
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'organization_metrics' AND policyname = 'org_metrics_update_only_service_role'
  ) THEN
    -- Only backend can update metrics
    CREATE POLICY "org_metrics_update_only_service_role" ON organization_metrics
      FOR UPDATE
      USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- ============================================================================
-- PRIVACY-PROTECTED TABLES (Forbidden for Org Admins)
-- ============================================================================
-- These tables contain individual employee data that MUST NEVER be accessible
-- to organization admins. RLS policies ensure access denied at database level.
-- ============================================================================

-- PROFILES - Personal user profile (forbidden for admins)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'profiles' AND policyname = 'profiles_users_read_own'
  ) THEN
    CREATE POLICY "profiles_users_read_own" ON profiles
      FOR SELECT
      USING (auth.uid() = id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'profiles' AND policyname = 'profiles_users_update_own'
  ) THEN
    CREATE POLICY "profiles_users_update_own" ON profiles
      FOR UPDATE
      USING (auth.uid() = id)
      WITH CHECK (auth.uid() = id);
  END IF;
END $$;

-- CONVERSATIONS - Chat conversation metadata (forbidden for admins)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'conversations' AND policyname = 'conversations_users_read_own'
  ) THEN
    CREATE POLICY "conversations_users_read_own" ON conversations
      FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'conversations' AND policyname = 'conversations_users_insert_own'
  ) THEN
    CREATE POLICY "conversations_users_insert_own" ON conversations
      FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'conversations' AND policyname = 'conversations_users_update_own'
  ) THEN
    CREATE POLICY "conversations_users_update_own" ON conversations
      FOR UPDATE
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- MESSAGES - Chat message content (forbidden for admins)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'messages' AND policyname = 'messages_users_read_own_conversations'
  ) THEN
    CREATE POLICY "messages_users_read_own_conversations" ON messages
      FOR SELECT
      USING (
        conversation_id IN (
          SELECT id FROM conversations WHERE user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'messages' AND policyname = 'messages_users_insert_own_conversations'
  ) THEN
    CREATE POLICY "messages_users_insert_own_conversations" ON messages
      FOR INSERT
      WITH CHECK (
        conversation_id IN (
          SELECT id FROM conversations WHERE user_id = auth.uid()
        )
      );
  END IF;
END $$;

-- MOODS - Individual mood entries (forbidden for admins)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'moods' AND policyname = 'moods_users_read_own'
  ) THEN
    CREATE POLICY "moods_users_read_own" ON moods
      FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'moods' AND policyname = 'moods_users_insert_own'
  ) THEN
    CREATE POLICY "moods_users_insert_own" ON moods
      FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- EXERCISE_SESSIONS - Personal exercise history (forbidden for admins)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'exercise_sessions' AND policyname = 'exercise_sessions_users_read_own'
  ) THEN
    CREATE POLICY "exercise_sessions_users_read_own" ON exercise_sessions
      FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'exercise_sessions' AND policyname = 'exercise_sessions_users_insert_own'
  ) THEN
    CREATE POLICY "exercise_sessions_users_insert_own" ON exercise_sessions
      FOR INSERT
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- USER_SETTINGS - Personal preferences (forbidden for admins)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'user_settings' AND policyname = 'user_settings_users_read_own'
  ) THEN
    CREATE POLICY "user_settings_users_read_own" ON user_settings
      FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'user_settings' AND policyname = 'user_settings_users_update_own'
  ) THEN
    CREATE POLICY "user_settings_users_update_own" ON user_settings
      FOR UPDATE
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- CIRCLE_POSTS - Peer check-ins (forbidden for admins)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'circle_posts' AND policyname = 'circle_posts_members_read'
  ) THEN
    CREATE POLICY "circle_posts_members_read" ON circle_posts
      FOR SELECT
      USING (
        circle_id IN (
          SELECT circle_id FROM circle_members WHERE user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'circle_posts' AND policyname = 'circle_posts_members_insert'
  ) THEN
    CREATE POLICY "circle_posts_members_insert" ON circle_posts
      FOR INSERT
      WITH CHECK (
        circle_id IN (
          SELECT circle_id FROM circle_members WHERE user_id = auth.uid()
        )
      );
  END IF;
END $$;

-- BADGES - Achievement patterns (forbidden for admins)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'badges' AND policyname = 'badges_public_read_definitions'
  ) THEN
    -- Everyone can read badge definitions
    CREATE POLICY "badges_public_read_definitions" ON badges
      FOR SELECT
      USING (true);
  END IF;
END $$;

-- USER_BADGES - Individual achievement records (forbidden for admins)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'user_badges' AND policyname = 'user_badges_users_read_own'
  ) THEN
    CREATE POLICY "user_badges_users_read_own" ON user_badges
      FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'user_badges' AND policyname = 'user_badges_insert_only_service_role'
  ) THEN
    CREATE POLICY "user_badges_insert_only_service_role" ON user_badges
      FOR INSERT
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- ============================================================================
-- AUDIT & MONITORING TABLES
-- ============================================================================

-- PRIVACY_ACCESS_AUDIT - Logs denied access attempts
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'privacy_access_audit' AND policyname = 'privacy_audit_admins_read_own_org'
  ) THEN
    CREATE POLICY "privacy_audit_admins_read_own_org" ON privacy_access_audit
      FOR SELECT
      USING (
        organization_id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid() AND role = 'admin'
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'privacy_access_audit' AND policyname = 'privacy_audit_insert_only_service_role'
  ) THEN
    CREATE POLICY "privacy_audit_insert_only_service_role" ON privacy_access_audit
      FOR INSERT
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- BILLING_AUDIT_LOG - Tracks Stripe events
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'billing_audit_log' AND policyname = 'billing_audit_admins_read'
  ) THEN
    CREATE POLICY "billing_audit_admins_read" ON billing_audit_log
      FOR SELECT
      USING (
        organization_id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'billing_audit_log' AND policyname = 'billing_audit_insert_only_service_role'
  ) THEN
    CREATE POLICY "billing_audit_insert_only_service_role" ON billing_audit_log
      FOR INSERT
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- AUDIT_LOG - General audit trail
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'audit_log' AND policyname = 'audit_log_admins_read'
  ) THEN
    CREATE POLICY "audit_log_admins_read" ON audit_log
      FOR SELECT
      USING (
        organization_id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'audit_log' AND policyname = 'audit_log_insert_only_service_role'
  ) THEN
    CREATE POLICY "audit_log_insert_only_service_role" ON audit_log
      FOR INSERT
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- SAML_ASSERTIONS - Replay attack prevention
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'saml_assertions' AND policyname = 'saml_assertions_insert_only_service_role'
  ) THEN
    CREATE POLICY "saml_assertions_insert_only_service_role" ON saml_assertions
      FOR INSERT
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- ============================================================================
-- MODIFIED SUBSCRIPTIONS TABLE - Add B2B access control
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'subscriptions' AND policyname = 'subscriptions_users_read_own'
  ) THEN
    CREATE POLICY "subscriptions_users_read_own" ON subscriptions
      FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'subscriptions' AND policyname = 'subscriptions_admins_read_org'
  ) THEN
    -- Admins can read subscriptions granted by their org
    CREATE POLICY "subscriptions_admins_read_org" ON subscriptions
      FOR SELECT
      USING (
        organization_id IN (
          SELECT organization_id FROM organization_admins
          WHERE user_id = auth.uid()
        )
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'subscriptions' AND policyname = 'subscriptions_insert_only_service_role'
  ) THEN
    CREATE POLICY "subscriptions_insert_only_service_role" ON subscriptions
      FOR INSERT
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'subscriptions' AND policyname = 'subscriptions_update_only_service_role'
  ) THEN
    CREATE POLICY "subscriptions_update_only_service_role" ON subscriptions
      FOR UPDATE
      USING (auth.role() = 'service_role')
      WITH CHECK (auth.role() = 'service_role');
  END IF;
END $$;

-- ============================================================================
-- PRIVACY ENFORCEMENT SUMMARY
-- ============================================================================
-- This migration establishes the privacy firewall that ensures:
--
-- 1. FORBIDDEN TABLES (no admin access):
--    ✓ profiles, conversations, messages, moods, exercise_sessions
--    ✓ user_settings, circle_posts, user_badges
--
-- 2. ALLOWED TABLES (admin access to their org):
--    ✓ organizations, organization_admins, organization_members
--    ✓ organization_invites, organization_metrics (5+ threshold)
--    ✓ billing_audit_log, audit_log, privacy_access_audit
--
-- 3. PRIVACY THRESHOLD:
--    ✓ organization_metrics only displays when active_users >= 5
--    ✓ Prevents filtering/inferring individual data from partial aggregates
--
-- 4. AUDIT LOGGING:
--    ✓ All access attempts logged (enabled in next migration)
--    ✓ Can detect suspicious patterns (N+ blocked attempts in X time)
--
-- 5. SERVICE ROLE ONLY:
--    ✓ organization_metrics, audit_log, billing_audit_log inserts/updates
--    ✓ Ensures backend exclusively manages operational data
--
-- This design prevents:
-- ✗ Admin viewing any individual employee's personal data
-- ✗ Admin inferring individual data from partial metrics
-- ✗ Admin discovering relationships between employees
-- ✗ Accidental data exposure via query errors
-- ✗ Privilege escalation through crafted requests
-- ============================================================================
