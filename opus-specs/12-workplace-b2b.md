# Workplace Wellness (B2B)

> Enterprise module for employer-sponsored wellness programs.

**Priority:** P2 - Enhancement
**Effort:** High (8-10 weeks)
**Impact:** Enterprise revenue; predictable recurring revenue

---

## 1. Overview

B2B platform allowing employers to:

- Sponsor MindFriend premium for employees
- View aggregate (anonymized) wellness metrics
- Launch company-wide challenges
- Integrate with HR systems

### Why It Exists

- Employer wellness budgets are $50B+ market
- Calm for Business, Headspace for Work growing fast
- Predictable B2B revenue complements consumer

---

## 2. Functional Requirements

### 2.1 Admin Portal

| ID    | Requirement                                  | Priority |
| ----- | -------------------------------------------- | -------- |
| AP-01 | Company admin dashboard                      | Must     |
| AP-02 | Employee onboarding (invite links, CSV, SSO) | Must     |
| AP-03 | Aggregate wellness reports (anonymized)      | Must     |
| AP-04 | License management (add/remove seats)        | Must     |
| AP-05 | Billing management                           | Must     |
| AP-06 | Launch company challenges                    | Should   |

### 2.2 Employee Experience

| ID    | Requirement                                      | Priority |
| ----- | ------------------------------------------------ | -------- |
| EE-01 | Seamless onboarding via company link             | Must     |
| EE-02 | Full premium access included                     | Must     |
| EE-03 | Privacy guarantee (individual data never shared) | Must     |
| EE-04 | Company challenges visible                       | Should   |
| EE-05 | SSO login (SAML/OIDC)                            | Should   |

### 2.3 Reporting

| ID    | Requirement                                    | Priority |
| ----- | ---------------------------------------------- | -------- |
| RP-01 | Active user count                              | Must     |
| RP-02 | Engagement metrics (sessions, exercises, etc.) | Must     |
| RP-03 | Aggregate mood trends (anonymized)             | Should   |
| RP-04 | Challenge participation rates                  | Should   |
| RP-05 | Monthly/quarterly PDF reports                  | Should   |

---

## 3. Technical Requirements

```sql
-- Organizations (companies)
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    domain TEXT, -- For email domain matching
    logo_url TEXT,
    plan TEXT DEFAULT 'business', -- 'business', 'enterprise'
    seat_count INTEGER NOT NULL,
    billing_email TEXT,
    stripe_customer_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Organization admins
CREATE TABLE organization_admins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    role TEXT DEFAULT 'admin', -- 'admin', 'viewer'
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Organization members (employees)
CREATE TABLE organization_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    user_id UUID NOT NULL REFERENCES auth.users(id),
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT true,
    UNIQUE(organization_id, user_id)
);

-- Organization invites
CREATE TABLE organization_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    invite_code TEXT NOT NULL UNIQUE,
    max_uses INTEGER,
    uses INTEGER DEFAULT 0,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Aggregate metrics (computed daily, anonymized)
CREATE TABLE organization_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id),
    metric_date DATE NOT NULL,

    -- Engagement
    active_users INTEGER,
    total_sessions INTEGER,
    total_exercise_minutes INTEGER,

    -- Wellness (aggregated, min 5 users for privacy)
    avg_mood_score DECIMAL(3,1),
    mood_trend TEXT, -- 'improving', 'stable', 'declining'

    -- Challenge participation
    challenge_participants INTEGER,

    UNIQUE(organization_id, metric_date)
);
```

---

## 4. Admin Dashboard UI

```
┌─────────────────────────────────────────────────────┐
│ Acme Corp Dashboard                    Admin ▼      │
├─────────────────────────────────────────────────────┤
│                                                     │
│ Overview                                            │
│ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐    │
│ │  142    │ │  89%    │ │  7.2    │ │ 1,240   │    │
│ │Active   │ │Engage-  │ │ Avg     │ │Exercise │    │
│ │Users    │ │ment     │ │ Mood    │ │ Minutes │    │
│ └─────────┘ └─────────┘ └─────────┘ └─────────┘    │
│                                                     │
│ Engagement Over Time                                │
│ ┌─────────────────────────────────────────────────┐ │
│ │   [Chart: Weekly active users over 3 months]    │ │
│ └─────────────────────────────────────────────────┘ │
│                                                     │
│ Quick Actions                                       │
│ [+ Invite Employees] [Launch Challenge] [Reports]  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## 5. Pricing Model

| Plan       | Seats  | Price      | Features                    |
| ---------- | ------ | ---------- | --------------------------- |
| Business   | 10-100 | $8/user/mo | Core features + reports     |
| Enterprise | 100+   | Custom     | SSO, API, dedicated support |

---

## 6. Acceptance Criteria

- [ ] Admins can invite employees
- [ ] Employees get premium access
- [ ] Aggregate reports are anonymized (min 5 users)
- [ ] Individual data NEVER shared with employer
- [ ] SSO integration works
- [ ] Billing via Stripe

---

## 7. Rollout Plan

### Phase 1 (Week 1-4)

- Organization data model
- Admin portal shell
- Employee onboarding

### Phase 2 (Week 5-7)

- Aggregate reporting
- Company challenges
- Billing integration

### Phase 3 (Week 8-10)

- SSO integration
- API access
- White-label options
