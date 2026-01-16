# Streak Recovery System

## Overview

**Goal:** Prevent the "what-the-hell effect" where users disengage entirely after losing a streak. Provide grace mechanisms that protect streaks while maintaining their motivational value.

**Why it matters:** Streak loss is the #1 predictor of app abandonment in habit apps. When users lose a long streak, they often feel demoralized and stop using the app entirely. A recovery system increases D7-D30 retention by 15-25% based on industry data while keeping streaks meaningful.

**Impact:** P1 priority - Highest-impact retention lever

---

## User Stories

- As a user, I want protection against accidentally losing my streak so that one bad day doesn't erase weeks of progress
- As a user, I want a chance to recover my streak so that I feel motivated to come back after a miss
- As a free user, I want some streak protection so that I don't feel punished for not being premium
- As a premium user, I want better streak protection so that my subscription feels valuable

---

## Product Requirements

### Must Have (MVP)

1. **Streak Freeze (Shield)**
   - Free users: 1 automatic freeze per week
   - Premium users: 3 freezes per week
   - Freeze activates automatically if user misses a day
   - Freeze preserves streak count (doesn't increment, doesn't reset)
   - Visual indicator shows freeze status on home screen
   - Notification: "Your streak was protected! 🛡️ You have X shields left this week"

2. **Streak Recovery Quest**
   - Available for 24 hours after streak would break (if no freeze available)
   - "Recovery Quest" is slightly longer than normal quest (10-15 min)
   - Completing recovery quest restores streak to previous value
   - Only one recovery attempt per broken streak
   - Premium users get 2 recovery attempts

3. **Streak Shield UI**
   - Shield counter on home screen streak card
   - Shield icon next to streak number
   - Animation when shield is used
   - Warning when shields are depleted: "No shields left - don't break your streak!"

4. **Weekly Shield Reset**
   - Shields reset every Monday at midnight (user's timezone)
   - Unused shields don't carry over
   - Notification: "Your streak shields have been refreshed! 🛡️"

### Nice to Have (V2)

- Purchase additional shields (one-time)
- "Shield Boost" power-up from completing bonus activities
- Retroactive shield application (missed yesterday → apply shield today)
- Shield gifting between circle members
- "Unbreakable Week" challenge (complete 7 days without using shields)

### Out of Scope

- Buying unlimited shields
- Shields that work for multiple days
- Automatic streak restoration without user action
- Streak insurance (pay to guarantee streak)

---

## Technical Design

### Data Model Changes

```sql
-- Migration: 20260116_streak_recovery.sql

-- Track streak shields
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS streak_shields_remaining INT DEFAULT 1;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS streak_shields_max INT DEFAULT 1;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS shields_reset_at TIMESTAMPTZ;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS last_shield_used_at TIMESTAMPTZ;

-- Track recovery quest availability
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS recovery_quest_available BOOLEAN DEFAULT FALSE;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS recovery_quest_expires_at TIMESTAMPTZ;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS streak_before_break INT;

-- Shield usage history (for analytics)
CREATE TABLE streak_shield_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN ('used', 'expired', 'reset', 'purchased')),
  streak_protected INT,
  shields_remaining INT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_shield_events_user ON streak_shield_events(user_id, created_at DESC);

-- Recovery quest attempts
CREATE TABLE recovery_quest_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  streak_to_recover INT NOT NULL,
  quest_template_id UUID REFERENCES quest_templates(id),
  started_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  expired_at TIMESTAMPTZ,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'expired'))
);

CREATE INDEX idx_recovery_attempts_user ON recovery_quest_attempts(user_id, started_at DESC);

-- RLS Policies
ALTER TABLE streak_shield_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE recovery_quest_attempts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users see own shield events" ON streak_shield_events
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users see own recovery attempts" ON recovery_quest_attempts
  FOR SELECT USING (auth.uid() = user_id);

-- Function to check and apply shield
CREATE OR REPLACE FUNCTION check_streak_protection(p_user_id UUID)
RETURNS TABLE(
  streak_protected BOOLEAN,
  new_streak INT,
  shields_remaining INT,
  recovery_available BOOLEAN
) AS $$
DECLARE
  v_profile RECORD;
  v_last_quest_date DATE;
  v_today DATE;
  v_streak_protected BOOLEAN := FALSE;
  v_recovery_available BOOLEAN := FALSE;
BEGIN
  -- Get user profile
  SELECT * INTO v_profile FROM profiles WHERE id = p_user_id;

  -- Get today's date in user timezone (default to UTC)
  v_today := CURRENT_DATE;

  -- Get last completed quest date
  SELECT MAX(completed_at::date) INTO v_last_quest_date
  FROM quests
  WHERE user_id = p_user_id AND status = 'completed';

  -- Check if streak is at risk (missed yesterday)
  IF v_last_quest_date IS NOT NULL AND v_last_quest_date < v_today - INTERVAL '1 day' THEN
    -- Streak would break - try to use shield
    IF v_profile.streak_shields_remaining > 0 THEN
      -- Use shield
      UPDATE profiles SET
        streak_shields_remaining = streak_shields_remaining - 1,
        last_shield_used_at = NOW()
      WHERE id = p_user_id;

      -- Log shield use
      INSERT INTO streak_shield_events (user_id, event_type, streak_protected, shields_remaining)
      VALUES (p_user_id, 'used', v_profile.current_streak_days, v_profile.streak_shields_remaining - 1);

      v_streak_protected := TRUE;
    ELSE
      -- No shields - offer recovery quest
      UPDATE profiles SET
        recovery_quest_available = TRUE,
        recovery_quest_expires_at = NOW() + INTERVAL '24 hours',
        streak_before_break = v_profile.current_streak_days,
        current_streak_days = 0
      WHERE id = p_user_id;

      v_recovery_available := TRUE;
    END IF;
  END IF;

  -- Return current state
  SELECT p.current_streak_days, p.streak_shields_remaining, p.recovery_quest_available
  INTO new_streak, shields_remaining, recovery_available
  FROM profiles p WHERE p.id = p_user_id;

  streak_protected := v_streak_protected;

  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Cron function to reset shields weekly
CREATE OR REPLACE FUNCTION reset_weekly_shields()
RETURNS void AS $$
BEGIN
  UPDATE profiles
  SET
    streak_shields_remaining = streak_shields_max,
    shields_reset_at = NOW()
  WHERE shields_reset_at IS NULL
     OR shields_reset_at < date_trunc('week', NOW());

  -- Log reset events
  INSERT INTO streak_shield_events (user_id, event_type, shields_remaining)
  SELECT id, 'reset', streak_shields_max
  FROM profiles
  WHERE shields_reset_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### iOS Implementation

**New Models** (`Core/Models.swift`):

```swift
struct StreakShieldStatus: Codable {
    let shieldsRemaining: Int
    let shieldsMax: Int
    let shieldsResetAt: Date?
    let lastShieldUsedAt: Date?
    let recoveryQuestAvailable: Bool
    let recoveryQuestExpiresAt: Date?
    let streakBeforeBreak: Int?

    var shieldsUsedThisWeek: Int {
        shieldsMax - shieldsRemaining
    }

    var nextResetIn: String? {
        guard let resetAt = shieldsResetAt else { return nil }
        let nextReset = Calendar.current.nextDate(after: resetAt, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)!
        let days = Calendar.current.dateComponents([.day], from: Date(), to: nextReset).day ?? 0
        return days == 0 ? "Today" : "\(days) days"
    }

    enum CodingKeys: String, CodingKey {
        case shieldsRemaining = "streak_shields_remaining"
        case shieldsMax = "streak_shields_max"
        case shieldsResetAt = "shields_reset_at"
        case lastShieldUsedAt = "last_shield_used_at"
        case recoveryQuestAvailable = "recovery_quest_available"
        case recoveryQuestExpiresAt = "recovery_quest_expires_at"
        case streakBeforeBreak = "streak_before_break"
    }
}

struct RecoveryQuestAttempt: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let streakToRecover: Int
    let questTemplateId: UUID?
    let startedAt: Date
    var completedAt: Date?
    var expiredAt: Date?
    var status: RecoveryStatus

    var questTemplate: QuestTemplate?

    enum RecoveryStatus: String, Codable {
        case pending, inProgress = "in_progress", completed, expired
    }

    var timeRemaining: TimeInterval? {
        guard status == .pending || status == .inProgress else { return nil }
        guard let expiresAt = expiredAt else { return nil }
        return expiresAt.timeIntervalSince(Date())
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case streakToRecover = "streak_to_recover"
        case questTemplateId = "quest_template_id"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case expiredAt = "expired_at"
        case status
        case questTemplate = "quest_templates"
    }
}
```

**Service Methods** (`Networking/Services/SupabaseDataService.swift`):

```swift
// MARK: - Streak Shields

func getShieldStatus() async throws -> StreakShieldStatus {
    let userId = try await getCurrentUserId()

    return try await supabase
        .from("profiles")
        .select("""
            streak_shields_remaining,
            streak_shields_max,
            shields_reset_at,
            last_shield_used_at,
            recovery_quest_available,
            recovery_quest_expires_at,
            streak_before_break
        """)
        .eq("id", userId)
        .single()
        .execute()
        .value
}

func checkStreakProtection() async throws -> (protected: Bool, newStreak: Int, shieldsRemaining: Int, recoveryAvailable: Bool) {
    let userId = try await getCurrentUserId()

    struct ProtectionResult: Codable {
        let streakProtected: Bool
        let newStreak: Int
        let shieldsRemaining: Int
        let recoveryAvailable: Bool

        enum CodingKeys: String, CodingKey {
            case streakProtected = "streak_protected"
            case newStreak = "new_streak"
            case shieldsRemaining = "shields_remaining"
            case recoveryAvailable = "recovery_available"
        }
    }

    let result: [ProtectionResult] = try await supabase
        .rpc("check_streak_protection", params: ["p_user_id": userId])
        .execute()
        .value

    let r = result.first!
    return (r.streakProtected, r.newStreak, r.shieldsRemaining, r.recoveryAvailable)
}

func startRecoveryQuest() async throws -> RecoveryQuestAttempt {
    let userId = try await getCurrentUserId()

    // Get a harder quest template for recovery
    let templates: [QuestTemplate] = try await supabase
        .from("quest_templates")
        .select()
        .gte("estimated_minutes", 10)
        .limit(5)
        .execute()
        .value

    let template = templates.randomElement()!

    let attempt = RecoveryQuestAttempt(
        id: UUID(),
        userId: userId,
        streakToRecover: 0, // Will be set by trigger
        questTemplateId: template.id,
        startedAt: Date(),
        completedAt: nil,
        expiredAt: nil,
        status: .inProgress,
        questTemplate: template
    )

    return try await supabase
        .from("recovery_quest_attempts")
        .insert(attempt)
        .select("*, quest_templates(*)")
        .single()
        .execute()
        .value
}

func completeRecoveryQuest(attemptId: UUID) async throws {
    let userId = try await getCurrentUserId()

    // Mark attempt as completed
    try await supabase
        .from("recovery_quest_attempts")
        .update([
            "status": "completed",
            "completed_at": Date().ISO8601Format()
        ])
        .eq("id", attemptId)
        .execute()

    // Restore streak
    try await supabase.rpc("restore_streak_from_recovery", params: ["p_user_id": userId])
}

func getActiveRecoveryQuest() async throws -> RecoveryQuestAttempt? {
    let userId = try await getCurrentUserId()

    let attempts: [RecoveryQuestAttempt] = try await supabase
        .from("recovery_quest_attempts")
        .select("*, quest_templates(*)")
        .eq("user_id", userId)
        .in("status", ["pending", "in_progress"])
        .order("started_at", ascending: false)
        .limit(1)
        .execute()
        .value

    return attempts.first
}
```

**New Views**:

```swift
// StreakShieldIndicator.swift
struct StreakShieldIndicator: View {
    let shieldsRemaining: Int
    let shieldsMax: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<shieldsMax, id: \.self) { index in
                Image(systemName: index < shieldsRemaining ? "shield.fill" : "shield")
                    .font(.caption)
                    .foregroundStyle(index < shieldsRemaining ? .blue : .gray.opacity(0.4))
            }
        }
        .accessibilityLabel("\(shieldsRemaining) of \(shieldsMax) streak shields remaining")
    }
}

// StreakCardWithShields.swift
struct StreakCardWithShields: View {
    let streak: Int
    let shieldStatus: StreakShieldStatus
    @State private var showShieldUsedAnimation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("\(streak) Day Streak")
                            .font(.headline)
                    }

                    if streak >= 7 {
                        HStack(spacing: 4) {
                            Image(systemName: "trophy.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                            Text("Keep it up!")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Shield indicator
                VStack(alignment: .trailing, spacing: 4) {
                    StreakShieldIndicator(
                        shieldsRemaining: shieldStatus.shieldsRemaining,
                        shieldsMax: shieldStatus.shieldsMax
                    )

                    Text(shieldStatus.shieldsRemaining == 0 ? "No protection" : "Protected")
                        .font(.caption2)
                        .foregroundStyle(shieldStatus.shieldsRemaining == 0 ? .orange : .green)
                }
            }

            // Warning if no shields
            if shieldStatus.shieldsRemaining == 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Complete today's quest to keep your streak!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

// RecoveryQuestBanner.swift
struct RecoveryQuestBanner: View {
    let streakToRecover: Int
    let expiresAt: Date
    let onStart: () -> Void

    @State private var timeRemaining: TimeInterval = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Recover Your Streak!")
                        .font(.headline)
                    Text("Complete a recovery quest to restore your \(streakToRecover)-day streak")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                // Countdown timer
                Label(formatTimeRemaining(), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.orange)

                Spacer()

                Button(action: onStart) {
                    Text("Start Recovery")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .onReceive(timer) { _ in
            timeRemaining = expiresAt.timeIntervalSince(Date())
        }
        .onAppear {
            timeRemaining = expiresAt.timeIntervalSince(Date())
        }
    }

    func formatTimeRemaining() -> String {
        guard timeRemaining > 0 else { return "Expired" }

        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m left"
        }
        return "\(minutes)m left"
    }
}

// RecoveryQuestView.swift
struct RecoveryQuestView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    let attempt: RecoveryQuestAttempt
    @State private var currentStep = 0
    @State private var isCompleting = false

    var quest: QuestTemplate? {
        attempt.questTemplate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.orange)

                        Text("Recovery Quest")
                            .font(.title2.bold())

                        Text("Complete this quest to restore your \(attempt.streakToRecover)-day streak")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)

                    // Quest content
                    if let quest = quest {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(quest.title)
                                .font(.headline)

                            Text(quest.description)
                                .foregroundStyle(.secondary)

                            Divider()

                            // Steps
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Steps")
                                    .font(.subheadline.bold())

                                ForEach(Array(quest.steps.enumerated()), id: \.offset) { index, step in
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: index <= currentStep ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(index <= currentStep ? .green : .gray)

                                        Text(step)
                                            .foregroundStyle(index <= currentStep ? .primary : .secondary)
                                    }
                                    .onTapGesture {
                                        if index == currentStep + 1 {
                                            withAnimation { currentStep = index }
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(16)

                        // Complete button
                        Button {
                            Task { await completeRecovery() }
                        } label: {
                            if isCompleting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Complete & Restore Streak")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(currentStep >= quest.steps.count - 1 ? Color.orange : Color.gray)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                        .disabled(currentStep < quest.steps.count - 1 || isCompleting)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    func completeRecovery() async {
        isCompleting = true
        defer { isCompleting = false }

        do {
            try await container.supabaseDataService.completeRecoveryQuest(attemptId: attempt.id)
            dismiss()
            // Show celebration
        } catch {
            print("Failed to complete recovery: \(error)")
        }
    }
}
```

### Backend Implementation

**Shield Reset Cron** (`supabase/functions/reset-shields/index.ts`):

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Run every Monday at midnight UTC
serve(async () => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Reset shields for all users
  const { data: updated, error } = await supabase
    .from("profiles")
    .update({
      streak_shields_remaining: supabase.raw("streak_shields_max"),
      shields_reset_at: new Date().toISOString(),
    })
    .select("id, streak_shields_max");

  if (error) {
    console.error("Failed to reset shields:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
    });
  }

  // Log reset events
  const events = (updated || []).map((u) => ({
    user_id: u.id,
    event_type: "reset",
    shields_remaining: u.streak_shields_max,
  }));

  if (events.length > 0) {
    await supabase.from("streak_shield_events").insert(events);
  }

  // Send notifications to users who had used shields
  for (const user of updated || []) {
    await supabase.functions.invoke("send-notification", {
      body: {
        type: "shield_reset",
        recipientId: user.id,
        data: { shields: user.streak_shields_max },
      },
    });
  }

  return new Response(JSON.stringify({ processed: updated?.length || 0 }));
});
```

**Update assign-quest to check streak protection**:

```typescript
// In assign-quest/index.ts, at the start of quest assignment
async function checkUserStreakHealth(supabase: SupabaseClient, userId: string) {
  // Check if streak should be protected or broken
  const { data } = await supabase.rpc("check_streak_protection", {
    p_user_id: userId,
  });

  if (data?.[0]?.streak_protected) {
    // Send notification that shield was used
    await supabase.functions.invoke("send-notification", {
      body: {
        type: "shield_used",
        recipientId: userId,
        data: {
          shieldsRemaining: data[0].shields_remaining,
        },
      },
    });
  } else if (data?.[0]?.recovery_available) {
    // Send notification about recovery quest
    await supabase.functions.invoke("send-notification", {
      body: {
        type: "recovery_available",
        recipientId: userId,
        data: {
          streakToRecover: data[0].streak_before_break,
        },
      },
    });
  }

  return data?.[0];
}
```

---

## UI/UX

### Home Screen Streak Card with Shields

```
┌─────────────────────────────────────────┐
│                                         │
│  🔥 14 Day Streak              🛡️🛡️⚪  │
│  🏆 Keep it up!               Protected │
│                                         │
└─────────────────────────────────────────┘
```

### Recovery Quest Banner (when streak broken)

```
┌─────────────────────────────────────────┐
│                                         │
│  🔄 Recover Your Streak!                │
│  Complete a recovery quest to restore   │
│  your 14-day streak                     │
│                                         │
│  ⏰ 23h 45m left    [Start Recovery]    │
│                                         │
└─────────────────────────────────────────┘
```

### Shield Used Notification

```
┌─────────────────────────────────────────┐
│                                         │
│  🛡️ Your streak was protected!         │
│                                         │
│  You missed yesterday, but your streak  │
│  shield saved your 14-day streak.       │
│                                         │
│  Shields remaining: 2/3                 │
│                                         │
└─────────────────────────────────────────┘
```

---

## Verification

### Manual Testing

1. **Shield Auto-Use:**
   - Build up a 3+ day streak
   - Miss a day (don't complete quest)
   - Open app next day
   - Verify shield was used automatically
   - Verify streak is preserved
   - Verify shield count decremented

2. **No Shields Available:**
   - Use all shields
   - Miss a day
   - Verify streak resets to 0
   - Verify recovery quest banner appears
   - Verify recovery expires after 24h

3. **Recovery Quest:**
   - Break streak with no shields
   - Start recovery quest
   - Complete all steps
   - Verify streak is restored
   - Verify can't do another recovery (until next break)

4. **Weekly Reset:**
   - Use all shields
   - Wait until Monday
   - Verify shields are restored
   - Verify notification received

5. **Premium Shields:**
   - Subscribe to premium
   - Verify shields increase from 1 to 3
   - Verify max shields shown correctly

---

## Dependencies

- Quest system working
- Push notifications working
- Profile table exists
- Cron jobs configured

---

## Risks & Mitigations

| Risk                         | Likelihood | Impact | Mitigation                                          |
| ---------------------------- | ---------- | ------ | --------------------------------------------------- |
| Users abuse recovery system  | Low        | Medium | One recovery per break, 24h expiry                  |
| Shield mechanics confusing   | Medium     | Medium | Clear visual indicators, onboarding tooltip         |
| Server timezone issues       | Low        | High   | Use user's timezone, test edge cases                |
| Recovery quest too hard/easy | Medium     | Low    | Use existing 10-15 min quests, adjust based on data |

---

## Implementation Estimate

| Task                          | Effort       |
| ----------------------------- | ------------ |
| Database migration            | 2 hours      |
| iOS Models                    | 1 hour       |
| iOS Service methods           | 2 hours      |
| Shield indicator UI           | 2 hours      |
| Recovery quest UI             | 4 hours      |
| Edge Functions (reset, check) | 3 hours      |
| Notifications                 | 2 hours      |
| Testing                       | 3 hours      |
| **Total**                     | **19 hours** |

---

## Success Metrics

| Metric                           | Current          | Target        |
| -------------------------------- | ---------------- | ------------- |
| D7 retention after streak break  | ~20%             | 50%           |
| D30 retention after streak break | ~10%             | 35%           |
| Average streak length            | Measure baseline | +40%          |
| Recovery quest completion rate   | N/A              | >60%          |
| Shield usage rate                | N/A              | 30-50% weekly |
