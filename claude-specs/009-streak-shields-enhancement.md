# F007: Streak Shields Enhancement

## Overview

### Summary

Advanced streak protection system that prevents discouragement from broken streaks through shield mechanics, grace periods, and streak recovery options.

### Business Value

- Reduces churn from streak loss frustration (30-40% of users quit after losing long streaks)
- Increases long-term retention by providing safety nets
- Premium feature driver for unlimited shields

### User Benefit

- Protection from losing hard-earned progress due to life circumstances
- Reduced anxiety around maintaining perfect streaks
- Ability to recover from temporary setbacks

### Dependencies

- F005: Dynamic Difficulty Adjustment (for capacity-aware shield recommendations)

---

## Requirements

### Functional Requirements

| ID     | Requirement                                                                                           | Priority    |
| ------ | ----------------------------------------------------------------------------------------------------- | ----------- |
| FR-001 | Users earn streak shields through consistent activity (7-day streaks = 1 shield, max 3 for free tier) | Must Have   |
| FR-002 | Shields automatically activate when user misses a day                                                 | Must Have   |
| FR-003 | Premium users get unlimited shields and can manually bank them                                        | Should Have |
| FR-004 | 48-hour grace period allows retroactive quest completion                                              | Must Have   |
| FR-005 | Streak recovery purchase option for lapsed streaks (up to 3 days)                                     | Should Have |
| FR-006 | Visual shield inventory displayed on profile and home screen                                          | Must Have   |
| FR-007 | Notification before shield is consumed (at end of day)                                                | Should Have |
| FR-008 | "Freeze streak" option for planned breaks (vacation mode)                                             | Could Have  |

### Non-Functional Requirements

| ID      | Requirement                               | Target         |
| ------- | ----------------------------------------- | -------------- |
| NFR-001 | Shield calculation at midnight local time | < 1s latency   |
| NFR-002 | Shield state sync across devices          | Real-time      |
| NFR-003 | Offline shield display                    | Cached locally |

### Acceptance Criteria

```gherkin
Feature: Streak Shield Protection

Scenario: Automatic shield activation
  Given user has 3 shields and a 14-day streak
  And user misses completing today's quest
  When the streak calculation runs at midnight
  Then one shield should be consumed
  And streak should remain at 14 days
  And user should receive notification of shield usage

Scenario: Shield earning
  Given user has 2 shields
  And user completes 7 consecutive days of quests
  Then user should earn 1 new shield
  And shield count should be 3

Scenario: Grace period recovery
  Given user missed yesterday's quest
  And user is within 48-hour grace period
  When user completes yesterday's quest retroactively
  Then no shield should be consumed
  And streak should be preserved

Scenario: Streak recovery purchase
  Given user's streak was broken 2 days ago
  And user has premium subscription
  When user purchases streak recovery
  Then streak should be restored to pre-break value
  And recovery should be logged for analytics
```

---

## Technical Design

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    iOS Application                       │
├─────────────────────────────────────────────────────────┤
│  StreakShieldService                                    │
│  ├── Shield inventory management                        │
│  ├── Grace period tracking                              │
│  └── Local shield state cache                           │
├─────────────────────────────────────────────────────────┤
│  StreakShieldView                                       │
│  ├── Shield display component                           │
│  ├── Recovery purchase flow                             │
│  └── Vacation mode toggle                               │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│              Supabase Edge Functions                     │
├─────────────────────────────────────────────────────────┤
│  calculate-streaks (cron)                               │
│  ├── Midnight streak evaluation                         │
│  ├── Shield consumption logic                           │
│  └── Shield earning logic                               │
├─────────────────────────────────────────────────────────┤
│  recover-streak (HTTP)                                  │
│  ├── Validate recovery eligibility                      │
│  ├── Process premium entitlement                        │
│  └── Restore streak state                               │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                  PostgreSQL Tables                       │
├─────────────────────────────────────────────────────────┤
│  streak_shields │ shield_events │ streak_freezes        │
└─────────────────────────────────────────────────────────┘
```

### Data Models

#### Database Schema

```sql
-- Streak shields inventory
CREATE TABLE streak_shields (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    shield_count INTEGER NOT NULL DEFAULT 0,
    max_shields INTEGER NOT NULL DEFAULT 3,
    shields_earned_total INTEGER NOT NULL DEFAULT 0,
    shields_used_total INTEGER NOT NULL DEFAULT 0,
    last_earned_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT shield_count_valid CHECK (shield_count >= 0 AND shield_count <= max_shields)
);

-- Shield usage and earning events
CREATE TABLE shield_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (event_type IN ('earned', 'consumed', 'purchased', 'expired', 'recovered')),
    streak_day INTEGER NOT NULL,
    shield_count_before INTEGER NOT NULL,
    shield_count_after INTEGER NOT NULL,
    reason TEXT,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Streak freeze periods (vacation mode)
CREATE TABLE streak_freezes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    reason TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT valid_freeze_period CHECK (end_date >= start_date),
    CONSTRAINT max_freeze_duration CHECK (end_date - start_date <= 14)
);

-- Grace period tracking
CREATE TABLE grace_period_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    missed_date DATE NOT NULL,
    grace_expires_at TIMESTAMPTZ NOT NULL,
    recovered BOOLEAN NOT NULL DEFAULT false,
    recovered_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, missed_date)
);

-- Streak recovery purchases
CREATE TABLE streak_recoveries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    streak_before INTEGER NOT NULL,
    streak_restored INTEGER NOT NULL,
    days_recovered INTEGER NOT NULL,
    cost_type TEXT NOT NULL CHECK (cost_type IN ('premium_feature', 'coins', 'shield')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_streak_shields_user ON streak_shields(user_id);
CREATE INDEX idx_shield_events_user_date ON shield_events(user_id, created_at DESC);
CREATE INDEX idx_streak_freezes_active ON streak_freezes(user_id, is_active) WHERE is_active = true;
CREATE INDEX idx_grace_period_user ON grace_period_entries(user_id, missed_date);

-- RLS Policies
ALTER TABLE streak_shields ENABLE ROW LEVEL SECURITY;
ALTER TABLE shield_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE streak_freezes ENABLE ROW LEVEL SECURITY;
ALTER TABLE grace_period_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE streak_recoveries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own shields" ON streak_shields
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can view own shield events" ON shield_events
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own freezes" ON streak_freezes
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view own grace periods" ON grace_period_entries
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can view own recoveries" ON streak_recoveries
    FOR SELECT USING (auth.uid() = user_id);
```

#### Swift Models

```swift
// MARK: - Streak Shield Models

struct StreakShield: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var shieldCount: Int
    let maxShields: Int
    let shieldsEarnedTotal: Int
    let shieldsUsedTotal: Int
    let lastEarnedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    var canEarnShield: Bool {
        shieldCount < maxShields
    }

    var shieldProgress: Double {
        Double(shieldCount) / Double(maxShields)
    }
}

enum ShieldEventType: String, Codable {
    case earned
    case consumed
    case purchased
    case expired
    case recovered
}

struct ShieldEvent: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let eventType: ShieldEventType
    let streakDay: Int
    let shieldCountBefore: Int
    let shieldCountAfter: Int
    let reason: String?
    let metadata: [String: AnyCodable]?
    let createdAt: Date
}

struct StreakFreeze: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let startDate: Date
    let endDate: Date
    let reason: String?
    var isActive: Bool
    let createdAt: Date

    var daysRemaining: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
    }

    var isCurrentlyFrozen: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.startOfDay(for: endDate)
        return isActive && today >= start && today <= end
    }
}

struct GracePeriodEntry: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let missedDate: Date
    let graceExpiresAt: Date
    var recovered: Bool
    let recoveredAt: Date?
    let createdAt: Date

    var isExpired: Bool {
        Date() > graceExpiresAt
    }

    var hoursRemaining: Int {
        let interval = graceExpiresAt.timeIntervalSince(Date())
        return max(0, Int(interval / 3600))
    }
}

struct StreakRecovery: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let streakBefore: Int
    let streakRestored: Int
    let daysRecovered: Int
    let costType: RecoveryCostType
    let createdAt: Date
}

enum RecoveryCostType: String, Codable {
    case premiumFeature = "premium_feature"
    case coins
    case shield
}
```

### API Contracts

#### Get Shield Status

```
GET /rest/v1/streak_shields?user_id=eq.{userId}

Response 200:
{
  "id": "uuid",
  "user_id": "uuid",
  "shield_count": 2,
  "max_shields": 3,
  "shields_earned_total": 5,
  "shields_used_total": 3,
  "last_earned_at": "2024-01-15T00:00:00Z"
}
```

#### Activate Streak Freeze

```
POST /functions/v1/activate-streak-freeze

Request:
{
  "startDate": "2024-01-20",
  "endDate": "2024-01-25",
  "reason": "vacation"
}

Response 200:
{
  "success": true,
  "freeze": {
    "id": "uuid",
    "startDate": "2024-01-20",
    "endDate": "2024-01-25",
    "daysCount": 6
  }
}
```

#### Recover Streak

```
POST /functions/v1/recover-streak

Request:
{
  "daysToRecover": 2
}

Response 200:
{
  "success": true,
  "recovery": {
    "streakBefore": 0,
    "streakRestored": 14,
    "daysRecovered": 2,
    "costType": "premium_feature"
  }
}

Response 400:
{
  "error": "recovery_not_eligible",
  "message": "Streak can only be recovered within 3 days of breaking"
}
```

#### Grace Period Recovery

```
POST /functions/v1/complete-grace-quest

Request:
{
  "questId": "uuid",
  "missedDate": "2024-01-15"
}

Response 200:
{
  "success": true,
  "graceRecovered": true,
  "shieldConsumed": false,
  "currentStreak": 14
}
```

---

## Implementation Details

### Step-by-Step Approach

1. **Database Setup**
   - Create migration for shield tables
   - Add streak_shields row on user creation (trigger)
   - Seed max_shields based on subscription tier

2. **Shield Earning Logic**
   - Modify calculate-streaks cron to check 7-day milestones
   - Award shield when milestone reached and inventory not full
   - Log shield_event for each award

3. **Shield Consumption Logic**
   - Check for active freeze before consuming
   - Check for grace period entries
   - Consume shield only if no other protection active
   - Send notification when shield used

4. **Grace Period System**
   - Create grace_period_entry when quest missed
   - Allow retroactive quest completion within 48 hours
   - Mark entry as recovered when quest completed

5. **Vacation Mode**
   - UI for setting freeze dates
   - Validate max 14 days
   - Skip streak calculation during freeze

6. **Streak Recovery**
   - Validate within 3-day recovery window
   - Check premium entitlement
   - Restore streak to pre-break value

### File Structure

```
apps/ios/MindFriendApp/
├── Features/
│   └── Streaks/
│       ├── StreakShieldService.swift
│       ├── StreakShieldView.swift
│       ├── ShieldInventoryView.swift
│       ├── VacationModeSheet.swift
│       ├── StreakRecoverySheet.swift
│       └── GracePeriodBanner.swift
│
supabase/
├── functions/
│   ├── calculate-streaks/      # Modified
│   ├── activate-streak-freeze/
│   ├── recover-streak/
│   └── complete-grace-quest/
├── migrations/
│   └── YYYYMMDD_streak_shields.sql
```

### Key Algorithms

#### Shield Earning Check (TypeScript)

```typescript
async function checkShieldEarning(
  supabase: SupabaseClient,
  userId: string,
  currentStreak: number,
): Promise<void> {
  // Check if streak is at 7-day milestone
  if (currentStreak > 0 && currentStreak % 7 === 0) {
    const { data: shields } = await supabase
      .from("streak_shields")
      .select("*")
      .eq("user_id", userId)
      .single();

    if (shields && shields.shield_count < shields.max_shields) {
      // Award new shield
      await supabase
        .from("streak_shields")
        .update({
          shield_count: shields.shield_count + 1,
          shields_earned_total: shields.shields_earned_total + 1,
          last_earned_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("user_id", userId);

      // Log event
      await supabase.from("shield_events").insert({
        user_id: userId,
        event_type: "earned",
        streak_day: currentStreak,
        shield_count_before: shields.shield_count,
        shield_count_after: shields.shield_count + 1,
        reason: `Earned at ${currentStreak}-day streak milestone`,
      });

      // Send notification
      await sendNotification(userId, {
        title: "Shield Earned! 🛡️",
        body: `You earned a streak shield for your ${currentStreak}-day streak!`,
      });
    }
  }
}
```

#### Streak Protection Check (TypeScript)

```typescript
async function evaluateStreakProtection(
  supabase: SupabaseClient,
  userId: string,
  missedDate: Date,
): Promise<{ protected: boolean; method: string }> {
  // 1. Check for active freeze
  const { data: freeze } = await supabase
    .from("streak_freezes")
    .select("*")
    .eq("user_id", userId)
    .eq("is_active", true)
    .lte("start_date", missedDate.toISOString().split("T")[0])
    .gte("end_date", missedDate.toISOString().split("T")[0])
    .single();

  if (freeze) {
    return { protected: true, method: "freeze" };
  }

  // 2. Check for grace period (48 hours haven't passed)
  const graceExpiry = new Date(missedDate);
  graceExpiry.setHours(graceExpiry.getHours() + 48);

  if (new Date() < graceExpiry) {
    // Create grace period entry
    await supabase.from("grace_period_entries").upsert({
      user_id: userId,
      missed_date: missedDate.toISOString().split("T")[0],
      grace_expires_at: graceExpiry.toISOString(),
      recovered: false,
    });
    return { protected: true, method: "grace_period" };
  }

  // 3. Try to use shield
  const { data: shields } = await supabase
    .from("streak_shields")
    .select("*")
    .eq("user_id", userId)
    .single();

  if (shields && shields.shield_count > 0) {
    await supabase
      .from("streak_shields")
      .update({
        shield_count: shields.shield_count - 1,
        shields_used_total: shields.shields_used_total + 1,
        updated_at: new Date().toISOString(),
      })
      .eq("user_id", userId);

    await supabase.from("shield_events").insert({
      user_id: userId,
      event_type: "consumed",
      streak_day: 0, // Will be filled with actual streak
      shield_count_before: shields.shield_count,
      shield_count_after: shields.shield_count - 1,
      reason: "Auto-consumed to protect streak",
    });

    return { protected: true, method: "shield" };
  }

  // No protection available
  return { protected: false, method: "none" };
}
```

---

## Dependencies

### Internal Dependencies

- **F005 Dynamic Difficulty Adjustment**: For capacity-aware shield recommendations
- **Existing streak system**: Modify calculate-streaks function
- **Notification system**: For shield usage alerts

### External Dependencies

- None (uses existing Supabase infrastructure)

### Infrastructure Requirements

- Cron job modification for calculate-streaks
- Real-time subscription for shield updates

---

## Edge Cases & Error Handling

| Scenario                                 | Handling                                                              |
| ---------------------------------------- | --------------------------------------------------------------------- |
| User misses multiple consecutive days    | Grace period only for first day; shields consumed for subsequent days |
| Shield consumed during grace period      | Check grace first before consuming shield                             |
| Freeze overlaps with existing freeze     | Merge or reject based on overlap type                                 |
| Freeze set in past                       | Reject; only future/current dates allowed                             |
| Recovery requested beyond 3 days         | Return eligibility error                                              |
| Free user tries unlimited shields        | Enforce max_shields limit, show upgrade prompt                        |
| Timezone edge case at midnight           | Use user's local timezone from profile                                |
| Device offline during shield consumption | Sync on reconnect; server is source of truth                          |

---

## Testing Requirements

### Unit Tests

```swift
// StreakShieldServiceTests.swift

func testShieldEarningAt7Days() async throws {
    let service = StreakShieldService(supabase: mockSupabase)

    // Simulate 7-day streak completion
    let result = try await service.checkStreakMilestone(streak: 7)

    XCTAssertTrue(result.shieldEarned)
    XCTAssertEqual(result.newShieldCount, 1)
}

func testShieldNotEarnedWhenFull() async throws {
    let service = StreakShieldService(supabase: mockSupabase)

    // Set shields to max
    mockSupabase.setShieldCount(3, maxShields: 3)

    let result = try await service.checkStreakMilestone(streak: 14)

    XCTAssertFalse(result.shieldEarned)
}

func testGracePeriodWithin48Hours() async throws {
    let service = StreakShieldService(supabase: mockSupabase)

    let missedDate = Calendar.current.date(byAdding: .hour, value: -24, to: Date())!
    let result = try await service.checkProtection(missedDate: missedDate)

    XCTAssertEqual(result.method, .gracePeriod)
    XCTAssertTrue(result.protected)
}

func testShieldConsumedAfterGraceExpires() async throws {
    let service = StreakShieldService(supabase: mockSupabase)
    mockSupabase.setShieldCount(2, maxShields: 3)

    let missedDate = Calendar.current.date(byAdding: .hour, value: -50, to: Date())!
    let result = try await service.checkProtection(missedDate: missedDate)

    XCTAssertEqual(result.method, .shield)
    XCTAssertEqual(mockSupabase.currentShieldCount, 1)
}

func testFreezeProtection() async throws {
    let service = StreakShieldService(supabase: mockSupabase)

    // Set active freeze
    mockSupabase.setActiveFreeze(
        startDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
        endDate: Calendar.current.date(byAdding: .day, value: 5, to: Date())!
    )

    let result = try await service.checkProtection(missedDate: Date())

    XCTAssertEqual(result.method, .freeze)
    XCTAssertTrue(result.protected)
}

func testStreakRecoveryEligibility() async throws {
    let service = StreakShieldService(supabase: mockSupabase)
    mockSupabase.setStreakBrokenDate(daysAgo: 2)
    mockSupabase.setPremiumStatus(true)

    let eligibility = try await service.checkRecoveryEligibility()

    XCTAssertTrue(eligibility.eligible)
    XCTAssertEqual(eligibility.daysToRecover, 2)
}

func testRecoveryNotEligibleAfter3Days() async throws {
    let service = StreakShieldService(supabase: mockSupabase)
    mockSupabase.setStreakBrokenDate(daysAgo: 4)

    let eligibility = try await service.checkRecoveryEligibility()

    XCTAssertFalse(eligibility.eligible)
}
```

### Integration Tests

```typescript
// supabase/functions/calculate-streaks/test.ts

Deno.test("shield consumed when quest missed after grace period", async () => {
  const userId = await createTestUser();
  await setShieldCount(userId, 2);

  // Create quest that expired 50 hours ago
  const missedDate = new Date(Date.now() - 50 * 60 * 60 * 1000);
  await createExpiredQuest(userId, missedDate);

  await invokeFunction("calculate-streaks");

  const shields = await getShieldCount(userId);
  assertEquals(shields, 1);

  const events = await getShieldEvents(userId);
  assertEquals(events[0].event_type, "consumed");
});

Deno.test("streak freeze prevents shield consumption", async () => {
  const userId = await createTestUser();
  await setShieldCount(userId, 2);
  await createActiveFreeze(userId);
  await createExpiredQuest(userId, new Date());

  await invokeFunction("calculate-streaks");

  const shields = await getShieldCount(userId);
  assertEquals(shields, 2); // Shield not consumed
});
```

### UI Tests

```swift
func testShieldInventoryDisplay() {
    let view = ShieldInventoryView(shieldCount: 2, maxShields: 3)

    let rendered = try view.inspect()

    XCTAssertEqual(rendered.findAll(ShieldIcon.self).count, 3)
    XCTAssertEqual(rendered.findAll(ShieldIcon.self, where: { $0.isFilled }).count, 2)
}

func testGracePeriodBannerCountdown() {
    let expiresIn = Date().addingTimeInterval(3600) // 1 hour
    let banner = GracePeriodBanner(expiresAt: expiresIn)

    let rendered = try banner.inspect()

    XCTAssertTrue(rendered.find(text: "1 hour").exists)
}
```
