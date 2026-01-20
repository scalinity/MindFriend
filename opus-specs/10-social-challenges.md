# Social Challenges & Leaderboards

> Drive engagement through friendly competition and group accountability.

**Priority:** P1 - High Value
**Effort:** Medium (3-4 weeks)
**Impact:** Viral engagement; increased retention

---

## 1. Overview

Weekly challenges users can join with friends or the community, with opt-in leaderboards showing progress. Builds on existing circles feature.

### Success Metrics

| Metric                        | Target              |
| ----------------------------- | ------------------- |
| Challenge participation       | 25% of active users |
| Challenge completion          | 60%+                |
| Viral invites from challenges | 10% invite friends  |

---

## 2. Functional Requirements

### 2.1 Challenge Types

| Type                | Description              | Duration |
| ------------------- | ------------------------ | -------- |
| Streak Challenge    | Maintain daily streak    | 7 days   |
| Meditation Minutes  | Accumulate exercise time | 7 days   |
| Mood Check-in       | Log mood daily           | 7 days   |
| Quest Champion      | Complete all quests      | 7 days   |
| Gratitude Challenge | Journal gratitude daily  | 7 days   |

### 2.2 Core Features

| ID    | Requirement                             | Priority |
| ----- | --------------------------------------- | -------- |
| CC-01 | Join public community challenges        | Must     |
| CC-02 | Create private circle challenges        | Must     |
| CC-03 | View real-time leaderboard              | Must     |
| CC-04 | See friends' progress                   | Must     |
| CC-05 | Earn bonus XP for challenge completion  | Must     |
| CC-06 | Share challenge completion on social    | Should   |
| CC-07 | Invite friends to challenge             | Must     |
| CC-08 | Privacy option to hide from leaderboard | Must     |

### 2.3 Rewards

| Placement  | Reward                       |
| ---------- | ---------------------------- |
| 1st Place  | 500 XP + Gold Badge          |
| 2nd Place  | 300 XP + Silver Badge        |
| 3rd Place  | 200 XP + Bronze Badge        |
| Completion | 100 XP + Participation Badge |

---

## 3. Technical Requirements

```sql
-- Challenge definitions
CREATE TABLE challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    challenge_type TEXT NOT NULL, -- 'streak', 'minutes', 'mood', etc.
    target_value INTEGER NOT NULL, -- 7 days, 100 minutes, etc.
    duration_days INTEGER NOT NULL DEFAULT 7,
    is_public BOOLEAN DEFAULT true,
    circle_id UUID REFERENCES circles(id), -- NULL for public
    created_by UUID REFERENCES auth.users(id),
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Challenge participants
CREATE TABLE challenge_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenge_id UUID NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    current_progress INTEGER DEFAULT 0,
    completed BOOLEAN DEFAULT false,
    completed_at TIMESTAMPTZ,
    final_rank INTEGER,
    show_on_leaderboard BOOLEAN DEFAULT true,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(challenge_id, user_id)
);

-- RLS
ALTER TABLE challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE challenge_participants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public challenges visible"
    ON challenges FOR SELECT
    USING (is_public = true OR circle_id IN (
        SELECT circle_id FROM circle_members WHERE user_id = auth.uid()
    ));

CREATE POLICY "Participants visible within challenge"
    ON challenge_participants FOR SELECT
    USING (challenge_id IN (
        SELECT id FROM challenges WHERE is_public = true
    ) OR user_id = auth.uid());
```

---

## 4. UI/UX

### Challenge Card

```
┌─────────────────────────────────┐
│ 🏆 7-Day Streak Challenge       │
│ 234 participants • Ends in 3d   │
│                                 │
│ Your Progress: 4/7 days         │
│ ████████░░░░ 57%               │
│                                 │
│ Leaderboard                     │
│ 1. 🥇 Sarah      7/7 ✓         │
│ 2. 🥈 Mike       6/7            │
│ 3. 🥉 You        4/7   ← You   │
│ 4.    Alex       4/7            │
│                                 │
│ [Invite Friends] [View All]     │
└─────────────────────────────────┘
```

---

## 5. Acceptance Criteria

- [ ] Users can join public challenges
- [ ] Users can create circle challenges
- [ ] Leaderboard updates in real-time
- [ ] Privacy option hides user from leaderboard
- [ ] XP awarded on completion
- [ ] Badges awarded for top 3

---

## 6. Rollout Plan

### Phase 1 (Week 1-2)

- Challenge data model
- Join/leave flow
- Progress tracking

### Phase 2 (Week 3-4)

- Leaderboards
- Badge awards
- Social sharing
- Circle challenges
