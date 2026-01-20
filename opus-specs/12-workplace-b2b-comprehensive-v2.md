# Workplace Wellness (B2B) — Comprehensive Technical Specification v2.0

> Enterprise module for employer-sponsored wellness programs.
>
> **Priority:** P2 - Enhancement
> **Effort:** High (22 weeks estimated with full implementation)
> **Impact:** Enterprise revenue; predictable recurring revenue; competitive parity with Calm for Business, Headspace for Work

---

## Executive Summary

MindFriend B2B enables employers to sponsor premium wellness access for their employees while maintaining strict privacy and individual data protection. Employers receive anonymized, aggregated wellness insights (5+ user minimum threshold) without ever accessing individual employee data. The platform generates predictable recurring revenue through per-seat subscription billing while deepening employee engagement in the core consumer product.

---

## 1. Functional Requirements

### 1.1 Admin Portal (Web-Based Dashboard)

**Technology Stack Decision:**

- Framework: Next.js 14 App Router
- UI Library: shadcn/ui + Tailwind CSS
- State Management: React Server Components + client-side Zustand for ephemeral state
- Deployment: Vercel
- Authentication: Supabase Auth (existing infrastructure reuse)
- Reasoning: React Server Components provide seamless data fetching, Vercel ensures zero-config deployment, shadcn/ui enables rapid accessible development, reduces operational overhead vs separate API server

#### 1.1.1 Company Admin Dashboard

| ID     | Requirement                              | Priority | Notes                                                                         |
| ------ | ---------------------------------------- | -------- | ----------------------------------------------------------------------------- |
| AP-01  | Company admin dashboard                  | Must     | Real-time active user count, engagement trending, revenue display             |
| AP-01a | Aggregate wellness metrics visualization | Must     | Charts for active users, mood trends (5+ users only), challenge participation |
| AP-01b | Revenue and seat utilization display     | Must     | Current monthly spend, seats purchased vs used, cost per active user          |
| AP-01c | Quick actions panel                      | Must     | Invite employees, view reports, manage billing, launch challenges             |

**Dashboard Layout:**

```
┌─────────────────────────────────────────────────────────┐
│ Acme Corp Dashboard                    Admin ▼           │
├─────────────────────────────────────────────────────────┤
│ Overview                                                 │
│ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐    │
│ │  142     │ │  89%     │ │  $4,240  │ │  28 days │    │
│ │ Active   │ │Engagement│ │ Monthly  │ │ Streak   │    │
│ │ Users    │ │ Rate     │ │ Spend    │ │ Avg      │    │
│ └──────────┘ └──────────┘ └──────────┘ └──────────┘    │
│                                                          │
│ Engagement Trends (Last 90 Days)                         │
│ ┌────────────────────────────────────────────────────┐  │
│ │ [Area chart: Weekly active users, sessions, exercises]│
│ └────────────────────────────────────────────────────┘  │
│                                                          │
│ Quick Actions                                            │
│ [+ Invite Employees] [Launch Challenge] [View Reports] │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

#### 1.1.2 Employee Onboarding Management

| ID     | Requirement                                  | Priority | Notes                                                                   |
| ------ | -------------------------------------------- | -------- | ----------------------------------------------------------------------- |
| AP-02  | Employee onboarding (invite links, CSV, SSO) | Must     | Three onboarding pathways                                               |
| AP-02a | Generate invite codes with restrictions      | Must     | Set max uses, expiration date, per-code tracking                        |
| AP-02b | Bulk CSV import/invite                       | Must     | Email list import, validate email format, track bulk operation status   |
| AP-02c | SSO (SAML 2.0) configuration                 | Should   | Manage IdP metadata, test connection, provision users on login          |
| AP-02d | Employee directory with lifecycle tracking   | Must     | View active/inactive members, removal date, join date, activity summary |

**Invite Code Management Interface:**

```
┌─────────────────────────────────────────────────────────┐
│ Employee Onboarding                                      │
├─────────────────────────────────────────────────────────┤
│ [+ Generate Invite Code]  [Bulk CSV Import]  [SSO Setup]│
│                                                          │
│ Active Invite Codes                                      │
│ Code       │ Created    │ Max Uses │ Used │ Expires    │
│ ACME-XK9P  │ 2025-01-15 │ 50       │ 23   │ 2025-02-15 │
│ ACME-2M7Q  │ 2025-01-14 │ —        │ 12   │ Unlimited  │
│ ACME-9V4W  │ 2025-01-13 │ 100      │ 98   │ 2025-02-28 │
└─────────────────────────────────────────────────────────┘
```

#### 1.1.3 License and Seat Management

| ID     | Requirement                           | Priority | Notes                                                                             |
| ------ | ------------------------------------- | -------- | --------------------------------------------------------------------------------- |
| AP-04  | License management (add/remove seats) | Must     | Purchase additional seats mid-cycle, track seat utilization                       |
| AP-04a | Seat allocation model                 | Must     | Seats purchased vs active members, grace period for inactive removal              |
| AP-04b | Member removal with audit trail       | Must     | Record who removed, when, optional reason                                         |
| AP-04c | Seat reallocation and optimization    | Should   | Suggest consolidation if utilization <50%, recommend Enterprise tier if >80 seats |

**Seat Management View:**

```
Plan: Business (10-100 seats) @ $8/user/month

Seats Purchased: 50
Seats Active: 42
Seats Available: 8
Utilization: 84%

[Add 10 Seats] [Upgrade to Enterprise]

Recent Changes:
- 2025-01-15: +5 seats added by alice@acme.com
- 2025-01-10: janedoe@acme.com removed (inactive 60 days)
```

#### 1.1.4 Aggregate Reporting

| ID     | Requirement                             | Priority | Notes                                                              |
| ------ | --------------------------------------- | -------- | ------------------------------------------------------------------ |
| AP-03  | Aggregate wellness reports (anonymized) | Must     | Daily/weekly/monthly reports with privacy thresholds               |
| AP-03a | Engagement metrics by date range        | Must     | Active users, sessions, exercise minutes, challenge participation  |
| AP-03b | Mood trend analysis (5+ user minimum)   | Must     | Aggregate mood score, trend direction (improving/stable/declining) |
| AP-03c | Challenge participation tracking        | Must     | # participants, completion rate, time to completion                |
| AP-03d | Export and scheduled reports            | Should   | PDF/CSV export, email scheduling (weekly/monthly digest)           |

**Key Privacy Enforcement:**

- **SQL-Level Enforcement**: All queries include `HAVING COUNT(DISTINCT user_id) >= 5` to prevent threshold bypass
- **NULL Masking**: Metrics display NULL/"-" when contributor count < 5, no alternative numbers shown
- **Audit Logging**: Every access to organization_metrics logged with admin ID, timestamp, report type
- **No Row-Level Access**: Admins cannot query individual moods, conversations, or exercises; only pre-aggregated tables accessible

**Reporting Query Pattern (Pseudocode):**

```sql
SELECT
  metric_date,
  active_users,
  CASE WHEN active_users >= 5 THEN avg_mood_score ELSE NULL END as avg_mood,
  CASE WHEN active_users >= 5 THEN mood_trend ELSE NULL END as mood_trend,
  total_sessions,
  total_exercise_minutes,
  challenge_participants
FROM organization_metrics
WHERE organization_id = ? AND metric_date BETWEEN ? AND ?
HAVING active_users >= 5
ORDER BY metric_date DESC;
```

#### 1.1.5 Billing Management

| ID     | Requirement                | Priority | Notes                                                          |
| ------ | -------------------------- | -------- | -------------------------------------------------------------- |
| AP-05  | Billing management         | Must     | View invoices, update payment method, manage subscription plan |
| AP-05a | Stripe integration UI      | Must     | Embedded billing portal, update card, view invoice history     |
| AP-05b | Subscription plan details  | Must     | Current plan, renewal date, next billing date, cost breakdown  |
| AP-05c | Upgrade/downgrade workflow | Must     | Switch Business ↔ Enterprise, proration, effective date        |

#### 1.1.6 Company Challenges

| ID     | Requirement                        | Priority | Notes                                                                     |
| ------ | ---------------------------------- | -------- | ------------------------------------------------------------------------- |
| AP-06  | Launch company challenges          | Should   | Create wellness challenges, set duration, define success metrics          |
| AP-06a | Challenge configuration            | Should   | Name, description, duration, goal (# users, # sessions, mood improvement) |
| AP-06b | Challenge tracking and leaderboard | Should   | Aggregate participation (no individual scores visible), trending          |

---

### 1.2 Employee Experience (iOS App Integration)

| ID    | Requirement                                      | Priority | Notes                                                                      |
| ----- | ------------------------------------------------ | -------- | -------------------------------------------------------------------------- |
| EE-01 | Seamless onboarding via company link             | Must     | Recognize invite code, auto-link to organization, request org permission   |
| EE-02 | Full premium access included                     | Must     | Unlimited AI chat quota, all exercises unlocked, all features enabled      |
| EE-03 | Privacy guarantee (individual data never shared) | Must     | Clear UI disclosure: "Your company can only see anonymous wellness trends" |
| EE-04 | Company challenges visible                       | Should   | See active challenges, track progress, receive challenge notifications     |
| EE-05 | SSO login (SAML/OIDC)                            | Should   | Optional SSO button on signin, JIT user creation for new employees         |

**iOS Onboarding Screen (New):**

```
┌─────────────────────────────────────────┐
│ Join Acme Corp Wellness Program          │
│                                          │
│ [Acme Corp Logo]                         │
│                                          │
│ Your company has provided premium        │
│ access to MindFriend at no cost.         │
│                                          │
│ [Enter Code] [Or use SSO]                │
│                                          │
│ Privacy Protected ✓                      │
│ Acme can only see anonymous wellness    │
│ trends, never your personal data.       │
│                                          │
│ [Join as Acme Employee]                  │
│                                          │
│ Privacy Policy · FAQ                     │
└─────────────────────────────────────────┘
```

---

### 1.3 Detailed Privacy & Data Access Specification

**CRITICAL: This section defines the absolute enforcement boundaries that prevent any individual-level data leakage to organization admins.**

#### 1.3.1 Tables Forbidden to Organization Admins

These tables must NEVER be queryable by organization admins, even in aggregated form:

| Table               | Why Hidden                                                                       | Impact                                     |
| ------------------- | -------------------------------------------------------------------------------- | ------------------------------------------ |
| `profiles`          | Contains personal bio, profile photo, real name                                  | Prevents identity linking to wellness data |
| `user_settings`     | Therapy preferences, notification schedules, personal goals                      | Highly sensitive behavioral data           |
| `conversations`     | Chat conversation metadata, AI chat history                                      | Therapeutic relationship confidentiality   |
| `messages`          | Actual chat content from AI conversations                                        | Core therapeutic data                      |
| `moods`             | Individual mood entries and scores                                               | Directly ties to personal mental state     |
| `exercise_sessions` | Individual exercise history, duration, frequency                                 | Personal behavioral tracking               |
| `circle_posts`      | Circle check-ins, friend activity, social network                                | Peer relationship data                     |
| `badges`            | While badge definitions OK, individual earned badges reveals completion patterns |                                            |

**Implementation:**

1. **RLS Policies**: Every forbidden table has RLS policy denying `organization_admin` role SELECT/INSERT/UPDATE/DELETE
2. **No Views**: Do NOT create views exposing these tables even in masked form
3. **No Aggregate Endpoints**: Do NOT add APIs that return "anonymized" versions of these tables
4. **Audit Trail**: Every admin query attempt logged; suspicious pattern (repeated attempts) triggers security alert

#### 1.3.2 RLS Policy Examples (Required SQL)

```sql
-- All forbidden tables include this policy pattern:
CREATE POLICY "organization_admins_cannot_read" ON profiles
  FOR SELECT USING (
    NOT EXISTS (
      SELECT 1 FROM organization_admins
      WHERE user_id = auth.uid()
    )
  );

-- For conversations table (example critical table):
CREATE POLICY "organization_admins_cannot_read_conversations" ON conversations
  FOR SELECT USING (
    auth.uid() = user_id AND NOT EXISTS (
      SELECT 1 FROM organization_admins
      WHERE user_id = auth.uid()
    )
  );

-- Similar policies for INSERT, UPDATE, DELETE with organization_admin role checks
```

#### 1.3.3 Metrics-Only Access: The organization_metrics Table

**This is the ONLY table organization admins can read:**

```sql
CREATE TABLE organization_metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  metric_date DATE NOT NULL,

  -- Engagement (no user identifiers)
  active_users INTEGER NOT NULL CHECK (active_users >= 5),
  total_sessions INTEGER,
  total_exercise_minutes INTEGER,

  -- Mood (aggregated with privacy threshold)
  mood_contributor_count INTEGER CHECK (mood_contributor_count >= 5),
  avg_mood_score DECIMAL(3,1),
  mood_trend TEXT CHECK (mood_trend IN ('improving', 'stable', 'declining')),

  -- Challenge (aggregated)
  challenge_participants INTEGER,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(organization_id, metric_date)
);

-- RLS Policy: Only organization admins of matching org can read
CREATE POLICY "org_admins_read_own_metrics" ON organization_metrics
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM organization_admins
      WHERE user_id = auth.uid()
        AND organization_id = organization_metrics.organization_id
    )
  );
```

#### 1.3.4 Metrics Computation with Privacy Threshold Enforcement

**Cron Job (runs daily at 2:00 AM UTC):**

```sql
-- Daily metrics aggregation (pg_cron scheduled function)
SELECT cron.schedule(
  'compute_organization_metrics_daily',
  '0 2 * * *',  -- 2:00 AM UTC daily
  $$
    INSERT INTO organization_metrics (
      organization_id, metric_date, active_users, total_sessions,
      total_exercise_minutes, mood_contributor_count, avg_mood_score,
      mood_trend, challenge_participants
    )
    SELECT
      org.id,
      CURRENT_DATE - INTERVAL '1 day' as metric_date,
      COUNT(DISTINCT om.user_id) as active_users,
      SUM(CASE WHEN qc.completed_at::DATE = CURRENT_DATE - INTERVAL '1 day' THEN 1 ELSE 0 END) as total_sessions,
      SUM(CASE WHEN es.completed_at::DATE = CURRENT_DATE - INTERVAL '1 day'
        THEN EXTRACT(MINUTE FROM es.duration) ELSE 0 END) as total_exercise_minutes,
      COUNT(DISTINCT CASE WHEN m.created_at::DATE = CURRENT_DATE - INTERVAL '1 day' THEN m.user_id END) as mood_contributor_count,
      CASE
        WHEN COUNT(DISTINCT CASE WHEN m.created_at::DATE = CURRENT_DATE - INTERVAL '1 day' THEN m.user_id END) >= 5
        THEN ROUND(AVG(m.mood_score)::NUMERIC, 1)
        ELSE NULL
      END as avg_mood_score,
      CASE
        WHEN COUNT(DISTINCT CASE WHEN m.created_at::DATE = CURRENT_DATE - INTERVAL '1 day' THEN m.user_id END) >= 5
        THEN CASE
          WHEN AVG(m.mood_score) > (SELECT AVG(mood_score) FROM moods WHERE created_at::DATE = CURRENT_DATE - INTERVAL '8 days' AND created_at::DATE <= CURRENT_DATE - INTERVAL '1 day') THEN 'improving'
          WHEN AVG(m.mood_score) < (SELECT AVG(mood_score) FROM moods WHERE created_at::DATE = CURRENT_DATE - INTERVAL '8 days' AND created_at::DATE <= CURRENT_DATE - INTERVAL '1 day') THEN 'declining'
          ELSE 'stable'
        END
        ELSE NULL
      END as mood_trend,
      COUNT(DISTINCT CASE WHEN cc.completed_at::DATE = CURRENT_DATE - INTERVAL '1 day' THEN cc.user_id END) as challenge_participants
    FROM organizations org
    LEFT JOIN organization_members om ON om.organization_id = org.id AND om.is_active = true
    LEFT JOIN quests qc ON qc.user_id = om.user_id
    LEFT JOIN exercise_sessions es ON es.user_id = om.user_id
    LEFT JOIN moods m ON m.user_id = om.user_id
    LEFT JOIN challenge_completions cc ON cc.user_id = om.user_id
    GROUP BY org.id
    HAVING COUNT(DISTINCT om.user_id) >= 5  -- Privacy threshold enforced at aggregation level
    ON CONFLICT (organization_id, metric_date) DO UPDATE
    SET
      active_users = EXCLUDED.active_users,
      total_sessions = EXCLUDED.total_sessions,
      total_exercise_minutes = EXCLUDED.total_exercise_minutes,
      mood_contributor_count = EXCLUDED.mood_contributor_count,
      avg_mood_score = EXCLUDED.avg_mood_score,
      mood_trend = EXCLUDED.mood_trend,
      challenge_participants = EXCLUDED.challenge_participants,
      created_at = NOW();
  $$
);
```

#### 1.3.5 Privacy Violation Audit Trail

```sql
CREATE TABLE privacy_access_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id UUID NOT NULL REFERENCES auth.users(id),
  organization_id UUID NOT NULL REFERENCES organizations(id),

  attempted_table TEXT,  -- Which forbidden table was accessed
  query_type TEXT,       -- SELECT, INSERT, UPDATE, DELETE
  status TEXT CHECK (status IN ('blocked', 'logged')),
  reason TEXT,           -- Why blocked (e.g., "RLS policy denies access")

  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Alert trigger: 5+ failed attempts in 1 hour = security flag
CREATE OR REPLACE FUNCTION flag_suspicious_privacy_access()
RETURNS TRIGGER AS $$
BEGIN
  IF (
    SELECT COUNT(*) FROM privacy_access_audit
    WHERE admin_id = NEW.admin_id
      AND organization_id = NEW.organization_id
      AND status = 'blocked'
      AND created_at > NOW() - INTERVAL '1 hour'
  ) >= 5 THEN
    -- Trigger alert (log to security monitoring system)
    INSERT INTO security_alerts (alert_type, organization_id, admin_id, severity, message)
    VALUES ('privacy_violation_pattern', NEW.organization_id, NEW.admin_id, 'high',
            'Organization admin attempted to access forbidden data 5+ times in 1 hour');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

---

## 2. Employee Lifecycle Specification

### 2.1 Joining an Organization

**Step 1: Employee receives invite code (via email, SMS, or in-person sharing)**

```
Subject: Join Acme Corp on MindFriend
Body:
  Use this code to get free premium access to MindFriend:
  CODE: ACME-XK9P

  Open the app and select "Join Organization" to get started.
```

**Step 2: Employee opens iOS app and enters code**

```swift
// iOS flow
1. User taps "Join Organization"
2. User enters code: ACME-XK9P
3. iOS calls Edge Function: validate-invite-code(code)
   - Validates code exists, not expired, under max_uses limit
   - Increments uses counter
   - Returns organization_id, organization_name, plan details
4. If user not authenticated:
   - Prompt sign-up (email/Apple/Google)
   - After auth, auto-join organization
5. If user already authenticated:
   - Create organization_members record linking user to org
6. Grant premium access (update subscription status)
7. Display success screen with organization name and premium features unlocked
```

**Step 3: Backend creates records**

```sql
-- Create organization membership
INSERT INTO organization_members (organization_id, user_id, joined_at, is_active)
VALUES ($1, $2, NOW(), true);

-- Update user subscription to premium (B2B sponsored)
UPDATE subscriptions
SET
  tier = 'premium',
  access_source = 'organization_sponsored',
  organization_id = $1,
  started_at = NOW(),
  valid_until = NULL  -- Never expires while member
WHERE user_id = $2;

-- Log the join event
INSERT INTO audit_log (organization_id, event_type, actor_id, target_user_id, changes)
VALUES ($1, 'member_joined', $2, $2, jsonb_build_object(
  'join_method', 'invite_code',
  'invite_code', $3,
  'timestamp', NOW()
));
```

### 2.2 Active Membership

**Premium Access Active:**

- Unlimited AI chat quota (no daily limits)
- All 45 exercises available
- All premium badges visible
- Circle functionality fully enabled
- No "upgrade" prompts or paywall screens

**Organization Features Available:**

- View company challenges
- See organization badge (e.g., "Acme Corp" next to profile name)
- Receive organization-specific notifications (challenge reminders)
- Export personal wellness data

### 2.3 Member Removal by Organization Admin

**Admin initiates removal:**

```
Admin clicks [Remove] next to janedoe@acme.com in directory
System shows: "This user will be removed effective immediately"
Admin confirms removal
System logs: "alice@acme.com removed janedoe@acme.com at 2025-01-15 14:32 UTC"
```

**Grace Period (24 hours):**

- User can still open app
- Premium features remain accessible (24-hour grace)
- Email notification sent: "Your organization membership ended. You have 24 hours to export data."
- User can view/download personal data, conversation history, mood logs

**After Grace Period:**

- Cron job (runs daily at 3:00 AM UTC) finalizes offboarding
- `organization_members.is_active` set to false
- Subscription tier reverted to free (if user had no personal subscription)
- If user had personal subscription (pre-org), restore personal subscription
- Access to premium features blocked
- RLS policies prevent data re-access by organization

**Data Retention:**

- All personal user data retained indefinitely (user owns their data)
- Individual mood entries: retained, not accessible to organization
- Conversations: retained, not accessible to organization
- Exercise history: retained, not accessible to organization
- Individual contribution to organization_metrics: removed in next day's aggregation
- audit_log entries: retained with removed user marked as "former_member"

```sql
-- Offboarding cron job
SELECT cron.schedule(
  'finalize_organization_offboarding_daily',
  '0 3 * * *',  -- 3:00 AM UTC daily
  $$
    -- Update subscriptions for members marked for removal
    UPDATE subscriptions s
    SET
      tier = CASE
        WHEN (SELECT COUNT(*) FROM subscriptions s2 WHERE s2.user_id = s.user_id AND s2.tier = 'premium' AND s2.access_source = 'personal') > 0
        THEN 'premium'  -- User has personal subscription, keep it
        ELSE 'free'     -- Revert to free
      END,
      organization_id = NULL,
      ended_at = NOW()
    WHERE access_source = 'organization_sponsored'
      AND user_id IN (
        SELECT om.user_id FROM organization_members om
        WHERE om.is_active = false
          AND om.removed_at < NOW() - INTERVAL '24 hours'
          AND om.finalized_at IS NULL
      );

    -- Mark offboarding as finalized
    UPDATE organization_members
    SET finalized_at = NOW()
    WHERE is_active = false
      AND removed_at < NOW() - INTERVAL '24 hours'
      AND finalized_at IS NULL;
  $$
);
```

---

## 3. Account Linking & Personal-to-B2B Migration

**Scenario:** Alice created personal MindFriend account (alice@company.com). Later, her company (Acme Corp) sets up B2B program. She needs to link her personal account to the organization.

**Current Implementation (MVP):**

- User creates new account for organization membership (separate account)
- Personal and B2B accounts remain separate
- User can manually copy data between accounts if desired
- Rationale: Simplifies billing (B2B subscription doesn't interfere with personal subscription)

**Future Enhancement (Post-MVP):**

- Account merging UI: user authorizes linking personal account to B2B
- Subscription consolidation: B2B access takes precedence while member
- Data consolidation: unified mood history, challenge history, exercise history
- Timeline: Post-MVP enhancement, complex auth/subscription coordination needed

---

## 4. SSO (SAML 2.0) Integration

### 4.1 Architecture Overview

**Decision:** SAML 2.0 (vs OIDC)

- Rationale: Older enterprise requirement compatibility, better attribute mapping control
- Backup: Support OIDC (OpenID Connect) for modern IdPs (Okta, Azure AD, Google Workspace)

**Protocol Flow: SP-Initiated (Recommended)**

```
1. User lands on MindFriend iOS app or web login
2. User selects "Sign in with Company SSO"
3. App/web opens: https://www.mindfriend.app/auth/sso/login
4. Backend generates SAML AuthnRequest (signed)
5. User redirected to company's Identity Provider (IdP)
6. IdP prompts for credentials (if not already logged in)
7. User authenticates at IdP
8. IdP creates SAML Assertion (signed, encrypted)
9. Browser POSTs assertion back to MindFriend ACS endpoint:
   https://www.mindfriend.app/auth/sso/acs
10. Backend validates assertion signature, decrypts, parses attributes
11. JIT (Just-In-Time) provisioning:
    - If user doesn't exist: create profile + link to organization
    - If user exists: update profile, link to organization
12. Create Supabase session token
13. Redirect to iOS app or web dashboard

```

### 4.2 SAML Attribute Mapping

**Required Attributes from IdP:**

| SAML Attribute                              | MindFriend Field          | Cardinality | Example        |
| ------------------------------------------- | ------------------------- | ----------- | -------------- |
| `urn:oid:0.9.2342.19200300.100.1.3` (email) | profiles.email            | 1           | alice@acme.com |
| `urn:oid:2.5.4.42` (givenName)              | profiles.first_name       | 1           | Alice          |
| `urn:oid:2.5.4.4` (sn)                      | profiles.last_name        | 1           | Johnson        |
| `urn:oid:2.5.4.12` (cn)                     | profiles.name             | 1           | Alice Johnson  |
| `urn:oid:2.5.4.11` (ou)                     | user_metadata.department  | 0..1        | Engineering    |
| `urn:oid:0.9.2342.19200300.100.1.11` (uid)  | user_metadata.employee_id | 0..1        | EMP12345       |
| Custom: `urn:oid:mindfriend:organization`   | —                         | 1           | acme-corp      |

**Attribute Matching Logic:**

- Email is the unique identifier for user lookup/creation
- Organization OID attribute (custom) is matched against `organizations.domain` or `organizations.saml_org_id`
- If user exists with email but organization differs: update organization_members record (role in org may change)

### 4.3 JIT Provisioning Flow

```typescript
// Edge Function: auth/sso/acs
export async function handleSAMLAssertion(request: Request) {
  const samlAssertion = request.body.SAMLResponse; // Base64-encoded

  // 1. Validate signature
  const assertion = validateAndDecodeAssertion(samlAssertion, idpPublicCert);

  // 2. Check assertion not replayed (using assertion_id uniqueness)
  const existingAssertion = await supabase
    .from("saml_assertions")
    .select("id")
    .eq("assertion_id", assertion.id)
    .single();

  if (existingAssertion) {
    throw new Error("Assertion already processed (replay attack attempt)");
  }

  // 3. Extract attributes
  const email = assertion.getAttributeValue("email");
  const firstName = assertion.getAttributeValue("givenName");
  const lastName = assertion.getAttributeValue("sn");
  const department = assertion.getAttributeValue("ou");
  const organizationId = assertion.getAttributeValue(
    "urn:oid:mindfriend:organization",
  );

  // 4. Look up organization by SSO ID
  const org = await supabase
    .from("organizations")
    .select("id")
    .eq("saml_org_id", organizationId)
    .single();

  if (!org) {
    throw new Error(`Organization not found: ${organizationId}`);
  }

  // 5. JIT provisioning
  let user = await supabase.auth.getUserByEmail(email);

  if (!user) {
    // Create user (email/password: SSO users can't sign in with password)
    user = await supabase.auth.signUp({
      email: email,
      password: crypto.randomUUID(), // Random, unused password
      options: {
        data: {
          first_name: firstName,
          last_name: lastName,
          department: department,
          sso_provider: "saml",
        },
      },
    });
  } else {
    // Update profile if changed
    await supabase
      .from("profiles")
      .update({
        first_name: firstName,
        last_name: lastName,
      })
      .eq("id", user.id);
  }

  // 6. Link to organization
  const existingMember = await supabase
    .from("organization_members")
    .select("id")
    .eq("organization_id", org.id)
    .eq("user_id", user.id)
    .single();

  if (!existingMember) {
    await supabase.from("organization_members").insert({
      organization_id: org.id,
      user_id: user.id,
      joined_at: new Date(),
    });
  }

  // 7. Grant premium subscription if not already held
  const subscription = await supabase
    .from("subscriptions")
    .select("tier")
    .eq("user_id", user.id)
    .eq("organization_id", org.id)
    .single();

  if (!subscription || subscription.tier !== "premium") {
    await supabase.from("subscriptions").upsert({
      user_id: user.id,
      organization_id: org.id,
      tier: "premium",
      access_source: "organization_sponsored",
      started_at: new Date(),
    });
  }

  // 8. Record assertion (prevent replay)
  await supabase.from("saml_assertions").insert({
    assertion_id: assertion.id,
    organization_id: org.id,
    user_id: user.id,
    processed_at: new Date(),
  });

  // 9. Create session and redirect
  const session = await supabase.auth.createSession(user.id);
  return redirectToApp(session.token, "ios://login-success");
}
```

### 4.4 IdP Configuration Examples

**Okta:**

```xml
<!-- Okta SAML App Configuration -->
Single Sign On URL: https://www.mindfriend.app/auth/sso/acs
Recipient URL Validator: https://www.mindfriend.app/auth/sso/acs
Audience (Entity ID): https://www.mindfriend.app
Name ID Format: Email
```

**Microsoft Entra ID (Azure AD):**

```
Identifier (Entity ID): https://www.mindfriend.app
Reply URL: https://www.mindfriend.app/auth/sso/acs
Sign on URL: https://www.mindfriend.app/auth/sso/login
```

---

## 5. Stripe Billing Integration

### 5.1 Stripe Subscription Model

**Product Configuration:**

| Product               | SKU                   | Seats  | Price                     | Billing           | Features                                                           |
| --------------------- | --------------------- | ------ | ------------------------- | ----------------- | ------------------------------------------------------------------ |
| MindFriend Business   | SKU_BUSINESS_ANNUAL   | 10-100 | $8/user/mo or $80/user/yr | Monthly or Annual | Admin portal, basic reports, invite codes                          |
| MindFriend Enterprise | SKU_ENTERPRISE_ANNUAL | 100+   | Custom                    | Annual            | Admin portal, advanced reports, SSO, API access, dedicated support |

**Stripe Setup:**

- Metered billing for "Active Seats" (tracked in real-time)
- Proration enabled: add 5 seats mid-month = prorated charge for remainder
- Automatic reconciliation: audit organization_members count vs Stripe seat count nightly

### 5.2 Subscription Lifecycle

#### 5.2.1 Initial Signup

```typescript
// Edge Function: billing/create-subscription
export async function createOrganizationSubscription(request: Request) {
  const { organizationId, seatCount, plan, billingEmail } = request.body;

  // Create Stripe customer
  const customer = await stripe.customers.create({
    email: billingEmail,
    metadata: {
      organization_id: organizationId,
      plan: plan,
    },
  });

  // Create subscription with metered billing
  const subscription = await stripe.subscriptions.create({
    customer: customer.id,
    items: [
      {
        price:
          plan === "business"
            ? "price_business_monthly"
            : "price_enterprise_custom",
        quantity: seatCount,
        billing_thresholds: {
          usage_gte: seatCount + 5, // Alert if usage exceeds seat count + 5
        },
      },
    ],
    off_session: false,
    collection_method: "charge_automatically",
  });

  // Store subscription details in database
  await supabase
    .from("organizations")
    .update({
      stripe_customer_id: customer.id,
      stripe_subscription_id: subscription.id,
      billing_email: billingEmail,
      plan: plan,
      seat_count: seatCount,
      subscription_status: "active",
    })
    .eq("id", organizationId);

  return { stripeCustomerId: customer.id, subscriptionId: subscription.id };
}
```

#### 5.2.2 Seat Adjustments

**Scenario: Admin adds 5 seats mid-cycle**

```typescript
export async function addSeats(organizationId: string, seatsToAdd: number) {
  const org = await supabase
    .from("organizations")
    .select("stripe_subscription_id, seat_count")
    .eq("id", organizationId)
    .single();

  // Update subscription with new quantity
  const updated = await stripe.subscriptions.update(
    org.stripe_subscription_id,
    {
      items: [
        {
          id: subscription.items.data[0].id,
          quantity: org.seat_count + seatsToAdd,
          billing_thresholds: {
            usage_gte: org.seat_count + seatsToAdd + 5,
          },
        },
      ],
      // Proration: Stripe automatically calculates prorated charge for remaining month
      proration_behavior: "create_prorations",
    },
  );

  // Update local record
  await supabase
    .from("organizations")
    .update({ seat_count: org.seat_count + seatsToAdd })
    .eq("id", organizationId);

  // Log change
  await logBillingChange(organizationId, "seats_added", seatsToAdd);

  return { newSeatCount: org.seat_count + seatsToAdd, proratedCharge: "..." };
}
```

#### 5.2.3 Nightly Reconciliation

```sql
-- Cron job: reconcile Stripe seat count vs actual organization members
SELECT cron.schedule(
  'reconcile_stripe_seats_nightly',
  '0 4 * * *',  -- 4:00 AM UTC daily
  $$
    WITH seat_counts AS (
      SELECT
        o.id as organization_id,
        o.stripe_subscription_id,
        COUNT(om.user_id) as actual_active_members
      FROM organizations o
      LEFT JOIN organization_members om ON om.organization_id = o.id AND om.is_active = true
      WHERE o.subscription_status = 'active'
      GROUP BY o.id
    )
    UPDATE organizations o
    SET seat_count = sc.actual_active_members
    FROM seat_counts sc
    WHERE o.id = sc.organization_id
      AND o.seat_count != sc.actual_active_members;

    -- Log discrepancies to audit trail
    INSERT INTO billing_audit_log (organization_id, event_type, message)
    SELECT
      o.id,
      'seat_count_mismatch',
      'Stripe seat count ' || o.seat_count || ' vs actual members ' || COUNT(om.user_id)
    FROM organizations o
    LEFT JOIN organization_members om ON om.organization_id = o.id AND om.is_active = true
    WHERE o.subscription_status = 'active'
      AND o.seat_count != COUNT(om.user_id)
    GROUP BY o.id;
  $$
);
```

### 5.3 Webhook Handling

**Stripe Webhook Endpoint:** `https://www.mindfriend.app/webhooks/stripe`

**Events to Monitor:**

| Event                            | Action                                            |
| -------------------------------- | ------------------------------------------------- |
| `customer.subscription.updated`  | Update org subscription status, seat count        |
| `customer.subscription.deleted`  | Mark org as past_due, disable premium access      |
| `invoice.payment_failed`         | Send admin alert, queue retry, start grace period |
| `invoice.payment_succeeded`      | Log transaction, clear past_due status            |
| `billing_portal.session.created` | (Future: embedded billing portal for admins)      |

```typescript
export async function handleStripeWebhook(request: Request) {
  const sig = request.headers.get("stripe-signature")!;
  const event = stripe.webhooks.constructEvent(
    request.body,
    sig,
    process.env.STRIPE_WEBHOOK_SECRET!,
  );

  switch (event.type) {
    case "customer.subscription.updated": {
      const subscription = event.data.object;
      const org = await supabase
        .from("organizations")
        .select("id")
        .eq("stripe_subscription_id", subscription.id)
        .single();

      await supabase
        .from("organizations")
        .update({
          subscription_status: subscription.status,
          seat_count: subscription.items.data[0].quantity,
        })
        .eq("id", org.id);
      break;
    }

    case "customer.subscription.deleted": {
      const subscription = event.data.object;
      const org = await supabase
        .from("organizations")
        .select("id")
        .eq("stripe_subscription_id", subscription.id)
        .single();

      // Disable premium access for all members
      await supabase
        .from("subscriptions")
        .update({ tier: "free", organization_id: null })
        .eq("organization_id", org.id);

      await supabase
        .from("organizations")
        .update({ subscription_status: "canceled" })
        .eq("id", org.id);

      // Alert admin
      await sendEmail(org.billing_email, "Subscription Canceled", "...");
      break;
    }

    case "invoice.payment_failed": {
      const invoice = event.data.object;
      const customer = await stripe.customers.retrieve(
        invoice.customer as string,
      );
      const org = await supabase
        .from("organizations")
        .select("id, billing_email")
        .eq("stripe_customer_id", customer.id as string)
        .single();

      // Start grace period (7 days)
      await supabase
        .from("organizations")
        .update({
          subscription_status: "past_due",
          grace_period_ends_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
        })
        .eq("id", org.id);

      // Email admin with retry info
      await sendEmail(
        org.billing_email,
        "Payment Failed",
        `Payment for ${org.seat_count} seats failed. Retry in 3 days. Update payment method: [link]`,
      );

      // Schedule cron to disable access after grace period
      await scheduleAccessDisable(org.id);
      break;
    }
  }

  return new Response("Webhook handled", { status: 200 });
}
```

---

## 6. Edge Functions Specification

### 6.1 Existing Functions (Reuse)

| Function            | Location                        | Purpose                                                                            |
| ------------------- | ------------------------------- | ---------------------------------------------------------------------------------- |
| `chat`              | `/functions/chat/`              | Existing AI conversation handler; update to check organization quota limits        |
| `send-notification` | `/functions/send-notification/` | Existing push notification sender; add organization-level notification preferences |

### 6.2 New Functions

#### 6.2.1 validate-invite-code

**Endpoint:** POST `/functions/v1/validate-invite-code`

**Request:**

```json
{
  "inviteCode": "ACME-XK9P"
}
```

**Response (Success):**

```json
{
  "organizationId": "uuid-acme-corp",
  "organizationName": "Acme Corp",
  "plan": "business",
  "isValid": true,
  "remainingUses": 27
}
```

**Implementation:**

```typescript
export async function validateInviteCode(request: Request) {
  const { inviteCode } = await request.json();

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: invite, error } = await supabase
    .from("organization_invites")
    .select("*, organizations(id, name, plan)")
    .eq("invite_code", inviteCode)
    .single();

  if (error || !invite) {
    return new Response(
      JSON.stringify({ isValid: false, error: "Invite code not found" }),
      {
        status: 404,
      },
    );
  }

  // Check expiration
  if (invite.expires_at && new Date(invite.expires_at) < new Date()) {
    return new Response(
      JSON.stringify({ isValid: false, error: "Invite code expired" }),
      {
        status: 410,
      },
    );
  }

  // Check uses
  if (invite.max_uses && invite.uses >= invite.max_uses) {
    return new Response(
      JSON.stringify({ isValid: false, error: "Invite code exhausted" }),
      {
        status: 410,
      },
    );
  }

  return new Response(
    JSON.stringify({
      organizationId: invite.organizations.id,
      organizationName: invite.organizations.name,
      plan: invite.organizations.plan,
      isValid: true,
      remainingUses: invite.max_uses ? invite.max_uses - invite.uses : null,
    }),
  );
}
```

#### 6.2.2 join-organization

**Endpoint:** POST `/functions/v1/join-organization`

**Request:**

```json
{
  "organizationId": "uuid-acme-corp",
  "inviteCode": "ACME-XK9P"
}
```

**Response (Success):**

```json
{
  "membershipCreated": true,
  "subscriptionGranted": "premium",
  "organizationName": "Acme Corp"
}
```

**Implementation:**

```typescript
export async function joinOrganization(request: Request) {
  const authHeader = request.headers.get("Authorization")!;
  const { organizationId, inviteCode } = await request.json();

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Get authenticated user
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
    });
  }

  // Validate invite
  const { data: invite, error: inviteError } = await supabase
    .from("organization_invites")
    .select("*")
    .eq("invite_code", inviteCode)
    .eq("organization_id", organizationId)
    .single();

  if (inviteError || !invite) {
    return new Response(JSON.stringify({ error: "Invalid invite code" }), {
      status: 400,
    });
  }

  // Check if already member
  const { data: existingMember } = await supabase
    .from("organization_members")
    .select("id")
    .eq("organization_id", organizationId)
    .eq("user_id", user.id)
    .single();

  if (existingMember) {
    return new Response(
      JSON.stringify({ error: "Already a member of this organization" }),
      {
        status: 409,
      },
    );
  }

  // Create membership
  const { error: memberError } = await supabase
    .from("organization_members")
    .insert({
      organization_id: organizationId,
      user_id: user.id,
      joined_at: new Date(),
    });

  if (memberError) {
    return new Response(
      JSON.stringify({ error: "Failed to create membership" }),
      { status: 500 },
    );
  }

  // Grant premium subscription
  const { error: subscriptionError } = await supabase
    .from("subscriptions")
    .upsert({
      user_id: user.id,
      organization_id: organizationId,
      tier: "premium",
      access_source: "organization_sponsored",
      started_at: new Date(),
    });

  if (subscriptionError) {
    return new Response(
      JSON.stringify({ error: "Failed to grant subscription" }),
      { status: 500 },
    );
  }

  // Increment invite uses
  await supabase
    .from("organization_invites")
    .update({ uses: invite.uses + 1 })
    .eq("id", invite.id);

  // Log event
  await supabase.from("audit_log").insert({
    organization_id: organizationId,
    event_type: "member_joined",
    actor_id: user.id,
    target_user_id: user.id,
    changes: { join_method: "invite_code", timestamp: new Date() },
  });

  const org = await supabase
    .from("organizations")
    .select("name")
    .eq("id", organizationId)
    .single();

  return new Response(
    JSON.stringify({
      membershipCreated: true,
      subscriptionGranted: "premium",
      organizationName: org.data?.name,
    }),
  );
}
```

#### 6.2.3 compute-organization-metrics

**Trigger:** Cron (daily at 2:00 AM UTC)
**Purpose:** Calculate daily aggregated metrics for all organizations

**Implementation:** (See section 1.3.4 above for SQL)

#### 6.2.4 generate-monthly-report

**Endpoint:** POST `/functions/v1/generate-monthly-report`

**Request:**

```json
{
  "organizationId": "uuid-acme-corp",
  "month": "2025-01",
  "format": "pdf"
}
```

**Response:** PDF file or JSON summary

**Implementation Notes:**

- Aggregate metrics from organization_metrics table
- Generate PDF with charts, trends, insights
- Send email to admin with report link
- Store report in Supabase Storage for later retrieval

---

## 7. Database Schema (Complete SQL)

### 7.1 Core Tables

```sql
-- Organizations table
CREATE TABLE IF NOT EXISTS organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  domain TEXT UNIQUE,  -- For email domain matching (optional)
  logo_url TEXT,
  plan TEXT NOT NULL DEFAULT 'business' CHECK (plan IN ('business', 'enterprise')),
  seat_count INTEGER NOT NULL DEFAULT 10,
  max_seats INTEGER,  -- Plan limit (100 for business, NULL for enterprise = unlimited)

  -- Billing
  stripe_customer_id TEXT,
  stripe_subscription_id TEXT,
  billing_email TEXT NOT NULL,
  subscription_status TEXT DEFAULT 'active' CHECK (subscription_status IN ('active', 'past_due', 'canceled', 'inactive')),
  grace_period_ends_at TIMESTAMPTZ,

  -- SSO
  saml_org_id TEXT UNIQUE,  -- For SAML configuration
  saml_entity_id TEXT,
  saml_acs_url TEXT,
  saml_sso_url TEXT,
  saml_certificate_fingerprint TEXT,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT valid_seat_count CHECK (seat_count > 0 AND seat_count <= max_seats OR max_seats IS NULL)
);

-- Organization Admins
CREATE TABLE IF NOT EXISTS organization_admins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'admin' CHECK (role IN ('admin', 'viewer')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(organization_id, user_id)
);

-- Organization Members (Employees)
CREATE TABLE IF NOT EXISTS organization_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  removed_at TIMESTAMPTZ,
  finalized_at TIMESTAMPTZ,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(organization_id, user_id)
);

-- Organization Invites
CREATE TABLE IF NOT EXISTS organization_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  invite_code TEXT NOT NULL UNIQUE,
  max_uses INTEGER,  -- NULL = unlimited
  uses INTEGER DEFAULT 0,
  expires_at TIMESTAMPTZ,
  created_by_admin_id UUID NOT NULL REFERENCES organization_admins(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CHECK (uses >= 0 AND (max_uses IS NULL OR uses <= max_uses))
);

-- Organization Metrics (Aggregated, Privacy-Protected)
CREATE TABLE IF NOT EXISTS organization_metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  metric_date DATE NOT NULL,

  -- Engagement
  active_users INTEGER NOT NULL CHECK (active_users >= 5),
  total_sessions INTEGER,
  total_exercise_minutes INTEGER,

  -- Mood (aggregated with privacy threshold)
  mood_contributor_count INTEGER CHECK (mood_contributor_count >= 5),
  avg_mood_score DECIMAL(3,1),
  mood_trend TEXT CHECK (mood_trend IN ('improving', 'stable', 'declining', NULL)),

  -- Challenges
  challenge_participants INTEGER,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(organization_id, metric_date)
);

-- Privacy Access Audit Trail
CREATE TABLE IF NOT EXISTS privacy_access_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id UUID NOT NULL REFERENCES auth.users(id),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  attempted_table TEXT,
  query_type TEXT CHECK (query_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE')),
  status TEXT CHECK (status IN ('blocked', 'logged')),
  reason TEXT,
  ip_address INET,
  user_agent TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Billing Audit Log
CREATE TABLE IF NOT EXISTS billing_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  event_type TEXT,  -- 'seat_added', 'seat_removed', 'payment_received', 'payment_failed', etc.
  message TEXT,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- SAML Assertion Tracking (Replay Prevention)
CREATE TABLE IF NOT EXISTS saml_assertions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  assertion_id TEXT NOT NULL UNIQUE,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  processed_at TIMESTAMPTZ DEFAULT NOW()
);

-- Audit Log (General)
CREATE TABLE IF NOT EXISTS audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  event_type TEXT,  -- 'member_joined', 'member_removed', 'report_viewed', etc.
  actor_id UUID NOT NULL REFERENCES auth.users(id),
  target_user_id UUID REFERENCES auth.users(id),
  changes JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### 7.2 RLS Policies

```sql
-- Enable RLS on all organization-related tables
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE privacy_access_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

-- Organization Admins: Can only read/write own admins records
CREATE POLICY "organization_admins_select" ON organization_admins
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM organization_admins oa
      WHERE oa.organization_id = organization_admins.organization_id
        AND oa.user_id = auth.uid()
    )
  );

CREATE POLICY "organization_admins_insert" ON organization_admins
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM organization_admins oa
      WHERE oa.organization_id = organization_admins.organization_id
        AND oa.user_id = auth.uid()
        AND oa.role = 'admin'  -- Only admins can add other admins
    )
  );

-- Organization Members: Employees can see own membership, admins can see their org's members
CREATE POLICY "organization_members_select" ON organization_members
  FOR SELECT USING (
    auth.uid() = user_id  -- Users see own membership
    OR EXISTS (
      SELECT 1 FROM organization_admins
      WHERE organization_id = organization_members.organization_id
        AND user_id = auth.uid()
    )  -- Admins see org members
  );

-- Organization Metrics: Only org admins can read
CREATE POLICY "organization_metrics_select" ON organization_metrics
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM organization_admins
      WHERE organization_id = organization_metrics.organization_id
        AND user_id = auth.uid()
    )
  );

-- Privacy Audit: Only admins and service role can read
CREATE POLICY "privacy_access_audit_select" ON privacy_access_audit
  FOR SELECT USING (
    current_user_id = 'postgres'  -- Only service role
  );

-- Billing Audit: Admins of org can read billing audit for their org
CREATE POLICY "billing_audit_log_select" ON billing_audit_log
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM organization_admins
      WHERE organization_id = billing_audit_log.organization_id
        AND user_id = auth.uid()
    )
  );
```

---

## 8. iOS Integration Points

### 8.1 New Views/ViewModels

**OrganizationJoinView:**

- Displays organization info after code validation
- "Join as [Organization Name] Employee" confirmation button
- Privacy disclosure: "Your individual data remains private; company sees only anonymous trends"

**OrganizationProfileView:**

- Shows user's organization membership (if active)
- Option to leave organization (triggers removal workflow)
- View organization challenges
- Organization name/logo badge

**OrganizationChallengesView:**

- Display active challenges launched by organization
- Join/leave challenge
- Progress tracking (aggregate only, no individual scores visible)

### 8.2 Updated ViewModels

**ChatViewModel:**

- Check user subscription tier before each message
- If `organization_sponsored` premium and membership inactive: show grace period message
- Enforce quota limits per plan tier

**QuestViewModel:**

- Display company challenges if user is organization member
- Track participation in organization challenges

### 8.3 Updated DependencyContainer

```swift
@MainActor
final class DependencyContainer: ObservableObject {
  // ... existing

  lazy var organizationService = OrganizationService(
    supabase: supabase,
    authService: supabaseAuthService
  )
}
```

---

## 9. Web Admin Portal (Next.js Implementation)

### 9.1 Project Structure

```
web/
  app/
    auth/
      signin/
      sso/
        callback.tsx
        login.tsx
    admin/
      layout.tsx
      dashboard/
        page.tsx
      members/
        page.tsx
        [id].tsx
      invites/
        page.tsx
      reports/
        page.tsx
      billing/
        page.tsx
      settings/
        page.tsx
    api/
      auth/
        sso/
          acs/
      webhooks/
        stripe.ts
  lib/
    supabase-client.ts
    stripe.ts
    saml.ts
  components/
    admin/
      DashboardCard.tsx
      MetricsChart.tsx
      MemberList.tsx
    auth/
      AuthLayout.tsx
```

### 9.2 Key Components

**Dashboard:**

- 4-card overview: Active Users, Engagement %, Monthly Spend, Streak Avg
- Area chart: Engagement trends over 90 days
- Quick action buttons

**Members Page:**

- Searchable table of org members
- Columns: Name, Email, Joined Date, Activity Status, Actions (Remove)
- Bulk CSV import button
- Add/remove individual members

**Invites Page:**

- List of active invite codes
- Copy button, expiration display, uses counter
- Generate new code button
- Delete/disable code button

**Reports Page:**

- Date range picker
- Engagement metrics, mood trends (if 5+ contributors), challenge participation
- Export to PDF/CSV
- Schedule weekly/monthly email reports

**Billing Page:**

- Plan selection, seat count, current spend
- Add/remove seats
- View invoices
- Update payment method (Stripe embedded)
- Upgrade to Enterprise button

---

## 10. Testing Strategy

### 10.1 iOS Tests

```swift
// Tests for OrganizationJoinView
func testValidInviteCodeAccepted()
func testExpiredInviteCodeRejected()
func testAlreadyMemberCheckPrevents Duplicate()
func testPremiumAccessGrantedAfterJoin()
func testGracePeriodDisplaysAfterRemoval()

// Tests for privacy
func testOrganizationAdminCannotAccessIndividualMoods()
func testOrganizationAdminCanReadAggregatedMetrics()
func testOrganizationMetricsNullWhenLessThan5Contributors()
```

### 10.2 Edge Function Tests

```typescript
// validate-invite-code tests
test("Returns valid invitation with remaining uses");
test("Rejects expired invitation");
test("Rejects exhausted invitation");

// join-organization tests
test("Creates membership and grants premium subscription");
test("Prevents duplicate membership");
test("Logs audit event");

// SAML tests
test("Validates SAML assertion signature");
test("Rejects replayed assertions");
test("JIT-provisions new user");
test("Updates existing user profile");
```

### 10.3 Database Tests

```sql
-- Test privacy threshold enforcement
SELECT COUNT(*) FROM organization_metrics WHERE mood_contributor_count < 5;
-- Should return 0 rows (privacy threshold enforced)

-- Test RLS policies
SET ROLE organization_admin;
SELECT * FROM profiles;  -- Should fail (RLS denies access)

SELECT * FROM organization_metrics WHERE organization_id = ?;  -- Should succeed (admin's org)
```

---

## 11. Implementation Timeline (22 Weeks)

### Phase 1: Core Infrastructure (Weeks 1-4)

- [ ] Database schema creation + migrations
- [ ] RLS policies + privacy audit logging
- [ ] Organization table + basic admin CRUD
- [ ] Stripe product/pricing configuration
- [ ] Organization invite code generation

### Phase 2: Employee Onboarding (Weeks 5-9)

- [ ] iOS: OrganizationJoinView + invite code entry
- [ ] Edge Function: validate-invite-code, join-organization
- [ ] Subscription auto-grant (premium access)
- [ ] CSV bulk import for admins
- [ ] iOS: Grace period notification + offboarding flow

### Phase 3: Admin Portal (Weeks 10-14)

- [ ] Next.js setup + authentication
- [ ] Dashboard (metrics visualization, KPIs)
- [ ] Members management page
- [ ] Invite code management
- [ ] Billing UI (Stripe Embedded)

### Phase 4: Metrics & Reporting (Weeks 15-19)

- [ ] organization_metrics table + pg_cron daily job
- [ ] Privacy-threshold enforcement (5+ user minimum)
- [ ] Reports page (engagement, mood trends, challenges)
- [ ] PDF/CSV export
- [ ] Email scheduling for reports

### Phase 5: SSO & Polish (Weeks 20-22)

- [ ] SAML 2.0 integration (auth/sso/acs endpoint)
- [ ] IdP configuration guides (Okta, Entra ID, Google)
- [ ] Security audit + penetration testing
- [ ] Documentation + runbooks
- [ ] Beta testing with pilot customers

---

## 12. Acceptance Criteria

- [ ] Admins can generate invite codes with configurable max uses and expiration
- [ ] Employees can join organization via code and get premium access automatically
- [ ] Organization_metrics only displays when 5+ active members contribute
- [ ] Individual employee data (moods, conversations, exercises) never accessible to org admins (verified by RLS policy testing)
- [ ] Stripe per-seat billing works with proration on mid-cycle seat additions
- [ ] SAML authentication creates/updates user and links to organization
- [ ] Employee removal triggers 24-hour grace period followed by subscription reversion
- [ ] Audit logs track all admin actions (member add/remove, report access, SSO logins)
- [ ] Dashboard displays real-time metrics and trends
- [ ] Privacy access attempt logging detects suspicious pattern (5+ failed accesses/hour)
- [ ] All tests pass (iOS, Edge Functions, SQL policies)

---

## 13. Known Risks & Mitigations

| Risk                                                     | Likelihood | Impact   | Mitigation                                                                           |
| -------------------------------------------------------- | ---------- | -------- | ------------------------------------------------------------------------------------ |
| Privacy threshold bypass (admin queries raw moods)       | Medium     | Critical | RLS policies + audit logging, quarterly security audit                               |
| Seat count desync (Stripe vs database)                   | Low        | High     | Nightly reconciliation cron + alerts                                                 |
| SSO assertion replay                                     | Low        | High     | assertion_id uniqueness constraint + timestamp validation                            |
| Employee offboarding delay (premium access revoked late) | Low        | Medium   | 24-hour grace period + automated cron finalization                                   |
| Stripe webhook failures (payment not recorded)           | Low        | Medium   | Retry queue + daily reconciliation job                                               |
| Admin portal security (XSS, CSRF, session fixation)      | Medium     | High     | OWASP Top 10 code review, Content Security Policy headers, secure session management |

---

**Version:** 2.0 (Comprehensive)
**Last Updated:** 2025-01-19
**Author:** MindFriend Development Team
**Status:** Ready for Phase 0.2 (Architecture Design)
