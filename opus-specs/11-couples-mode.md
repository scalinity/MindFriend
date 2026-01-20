# Partner/Couples Mode

> Shared experience for couples to improve relationship health together.

**Priority:** P2 - Enhancement
**Effort:** Medium (4-5 weeks)
**Impact:** Market expansion; underserved segment

---

## 1. Overview

A couples feature allowing partners to:

- Link accounts for shared experience
- Track relationship health together
- Do couples exercises (communication, appreciation)
- See each other's mood (with consent)
- Get relationship-focused prompts

### Why It Exists

- Relationship stress is a top mental health trigger
- Couples apps (Paired, Lasting) show market demand
- NO mental health app does couples well
- Extends naturally from existing circles feature

---

## 2. Functional Requirements

### 2.1 Partner Linking

| ID    | Requirement                       | Priority |
| ----- | --------------------------------- | -------- |
| PL-01 | Send partner invite via link/code | Must     |
| PL-02 | Accept/decline partner request    | Must     |
| PL-03 | Unlink partner anytime            | Must     |
| PL-04 | Only one linked partner at a time | Must     |

### 2.2 Shared Features

| ID    | Requirement                                  | Priority |
| ----- | -------------------------------------------- | -------- |
| SF-01 | Shared mood visibility (opt-in)              | Must     |
| SF-02 | Daily relationship check-in                  | Should   |
| SF-03 | Couples exercises library                    | Must     |
| SF-04 | Shared journal prompts                       | Should   |
| SF-05 | Appreciation prompts ("Tell X one thing...") | Should   |
| SF-06 | Conflict resolution exercises                | Should   |

### 2.3 Privacy Controls

| ID    | Requirement                                  | Priority |
| ----- | -------------------------------------------- | -------- |
| PC-01 | Choose what to share (mood, exercises, etc.) | Must     |
| PC-02 | Private entries stay private                 | Must     |
| PC-03 | Revoke sharing anytime                       | Must     |
| PC-04 | No notification to partner on unshare        | Must     |

---

## 3. Technical Requirements

```sql
-- Partner relationships
CREATE TABLE partner_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_a_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    user_b_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'ended')),
    invited_by UUID NOT NULL,

    -- Sharing permissions (user A's settings)
    user_a_share_mood BOOLEAN DEFAULT true,
    user_a_share_exercises BOOLEAN DEFAULT false,

    -- Sharing permissions (user B's settings)
    user_b_share_mood BOOLEAN DEFAULT true,
    user_b_share_exercises BOOLEAN DEFAULT false,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    ended_at TIMESTAMPTZ,

    CONSTRAINT different_users CHECK (user_a_id != user_b_id),
    CONSTRAINT unique_active_link UNIQUE (user_a_id, user_b_id, status)
);

-- Couples exercises
CREATE TABLE couples_exercises (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT, -- 'communication', 'appreciation', 'conflict', 'intimacy'
    duration_minutes INTEGER,
    instructions JSONB NOT NULL,
    is_premium BOOLEAN DEFAULT false
);

-- Completed couples exercises
CREATE TABLE couples_exercise_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    partner_link_id UUID NOT NULL REFERENCES partner_links(id),
    exercise_id UUID NOT NULL REFERENCES couples_exercises(id),
    completed_at TIMESTAMPTZ DEFAULT NOW(),
    notes TEXT
);
```

---

## 4. UI/UX

### Partner Dashboard

```
┌─────────────────────────────────┐
│ You & Alex                  ⚙️  │
├─────────────────────────────────┤
│                                 │
│ ┌─────────┐    ┌─────────┐     │
│ │   You   │ ❤️ │  Alex   │     │
│ │   🙂    │    │   😊    │     │
│ └─────────┘    └─────────┘     │
│                                 │
│ Connected for 45 days           │
│ 12 exercises completed together │
│                                 │
│ Today's Prompt                  │
│ ┌─────────────────────────────┐ │
│ │ Tell Alex one thing you     │ │
│ │ appreciated about them today│ │
│ │                             │ │
│ │ [Share with Alex]           │ │
│ └─────────────────────────────┘ │
│                                 │
│ Exercises                       │
│ ┌─────────────────────────────┐ │
│ │ 💬 Active Listening         │ │
│ │    15 min • Communication   │ │
│ │                [Start →]    │ │
│ └─────────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

---

## 5. Acceptance Criteria

- [ ] Users can link with one partner
- [ ] Partner can accept/decline invite
- [ ] Mood sharing is opt-in
- [ ] Users can do couples exercises together
- [ ] Users can unlink without notifying partner
- [ ] Privacy controls work correctly

---

## 6. Rollout Plan

### Phase 1 (Week 1-2)

- Partner linking system
- Basic shared view

### Phase 2 (Week 3-4)

- Couples exercises library
- Appreciation prompts
- Privacy controls

### Phase 3 (Week 5)

- Relationship check-ins
- Exercise completion tracking
