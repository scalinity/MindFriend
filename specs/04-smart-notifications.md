# Push Notifications That Don't Annoy

## Overview

**Goal:** Send notifications that users actually want to receive. Replace generic reminders with social triggers, smart timing, and loss aversion messaging that brings users back without feeling spammy.

**Why it matters:** Notifications are the #1 retention lever, but bad notifications cause uninstalls. MindFriend needs to earn notification permission by sending valuable, well-timed messages that feel helpful rather than nagging.

**Impact:** P4 priority - Brings users back without annoying

---

## User Stories

- As a user, I want to know when my friends share something so that I can support them
- As a user, I want reminders that respect my schedule so that I don't get bothered at bad times
- As a user, I want to feel motivated to maintain my streak so that I don't lose my progress
- As a user, I want a weekly summary so that I can see my progress without daily interruptions

---

## Product Requirements

### Must Have (MVP)

1. **Social Triggers**
   - "[Name] shared how they're feeling" → circle activity
   - "[Name] sent you a hug 🤗" → direct engagement
   - "[Name] completed today's challenge" → group motivation

2. **Loss Aversion Messaging**
   - "You've been consistent for 6 days. Tomorrow is day 7!" → streak protection
   - "Your streak is at risk - check in to keep it going" → day before break
   - "Don't lose your [X] day streak!" → on break day

3. **Smart Timing**
   - Learn when user typically opens app (track in profile)
   - Send notifications at preferred time ±30min
   - Respect quiet hours absolutely

4. **Weekly "Quiet Wins" Summary**
   - Sunday evening notification
   - "This week: 5 check-ins, 3 quests completed, mood improved 20%"
   - Deep link to insights screen

5. **Notification Preferences Screen**
   - Toggle each notification type
   - Set preferred notification time
   - Configure quiet hours

### Nice to Have (V2)

- A/B test notification copy
- Notification frequency caps (max 3/day)
- "Best time to reach you" ML model
- Rich notifications with actions
- Notification digest mode

### Out of Scope

- In-app notification center
- Email notifications
- SMS notifications
- Marketing/promotional notifications

---

## Technical Design

### Data Model Changes

```sql
-- Migration: 20260118_smart_notifications.sql

-- Track typical active time
ALTER TABLE profiles ADD COLUMN typical_active_hour INT CHECK (typical_active_hour >= 0 AND typical_active_hour <= 23);
ALTER TABLE profiles ADD COLUMN notification_timezone TEXT DEFAULT 'America/Los_Angeles';

-- Notification preferences (extend user_settings or create new table)
ALTER TABLE user_settings ADD COLUMN notify_circle_activity BOOLEAN DEFAULT TRUE;
ALTER TABLE user_settings ADD COLUMN notify_hugs BOOLEAN DEFAULT TRUE;
ALTER TABLE user_settings ADD COLUMN notify_streak_risk BOOLEAN DEFAULT TRUE;
ALTER TABLE user_settings ADD COLUMN notify_weekly_summary BOOLEAN DEFAULT TRUE;
ALTER TABLE user_settings ADD COLUMN notify_challenges BOOLEAN DEFAULT TRUE;
ALTER TABLE user_settings ADD COLUMN preferred_notify_hour INT DEFAULT 9;  -- 9 AM default

-- Notification history for analytics
CREATE TABLE notification_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  notification_type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  sent_at TIMESTAMPTZ DEFAULT NOW(),
  opened_at TIMESTAMPTZ,
  action_taken BOOLEAN DEFAULT FALSE,
  deep_link TEXT,
  metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_notification_user ON notification_history(user_id, sent_at DESC);
CREATE INDEX idx_notification_type ON notification_history(notification_type, sent_at DESC);

-- Weekly insights (for summary notification)
CREATE TABLE weekly_summaries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  week_start DATE NOT NULL,
  checkin_count INT DEFAULT 0,
  quest_count INT DEFAULT 0,
  exercise_count INT DEFAULT 0,
  avg_mood FLOAT,
  mood_trend TEXT CHECK (mood_trend IN ('improving', 'stable', 'declining')),
  generated_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id, week_start)
);

-- RLS
ALTER TABLE notification_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE weekly_summaries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users see own notifications" ON notification_history
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users see own summaries" ON weekly_summaries
  FOR SELECT USING (auth.uid() = user_id);
```

### iOS Implementation

**Update Models** (`Core/Models.swift`):

```swift
extension UserSettings {
    var notifyCircleActivity: Bool
    var notifyHugs: Bool
    var notifyStreakRisk: Bool
    var notifyWeeklySummary: Bool
    var notifyChallenges: Bool
    var preferredNotifyHour: Int  // 0-23
}

struct WeeklySummary: Codable {
    let id: UUID
    let userId: UUID
    let weekStart: Date
    let checkinCount: Int
    let questCount: Int
    let exerciseCount: Int
    let avgMood: Double?
    let moodTrend: MoodTrend?
    let generatedAt: Date

    enum MoodTrend: String, Codable {
        case improving, stable, declining

        var emoji: String {
            switch self {
            case .improving: return "📈"
            case .stable: return "➡️"
            case .declining: return "📉"
            }
        }

        var message: String {
            switch self {
            case .improving: return "Your mood is trending up!"
            case .stable: return "Your mood has been steady."
            case .declining: return "It's been a tough week. We're here for you."
            }
        }
    }
}
```

**New View** (`Features/Profile/NotificationSettingsView.swift`):

```swift
struct NotificationSettingsView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var settings: UserSettings?
    @State private var isLoading = true

    var body: some View {
        Form {
            Section(header: Text("Social")) {
                Toggle("Circle activity", isOn: binding(\.notifyCircleActivity))
                Toggle("Hugs received", isOn: binding(\.notifyHugs))
                Toggle("Challenge updates", isOn: binding(\.notifyChallenges))
            }

            Section(header: Text("Motivation")) {
                Toggle("Streak at risk", isOn: binding(\.notifyStreakRisk))
                Toggle("Weekly summary", isOn: binding(\.notifyWeeklySummary))
            }

            Section(header: Text("Timing")) {
                Picker("Preferred time", selection: $preferredHour) {
                    ForEach(6..<22) { hour in
                        Text(formatHour(hour)).tag(hour)
                    }
                }

                NavigationLink("Quiet hours") {
                    QuietHoursView()
                }
            }
        }
        .navigationTitle("Notifications")
        .task { await loadSettings() }
        .onChange(of: settings) { _, newValue in
            Task { await saveSettings() }
        }
    }

    func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
        return formatter.string(from: date)
    }
}
```

**Update NotificationManager** (`Core/Observability/NotificationManager.swift`):

```swift
extension NotificationManager {
    // Track notification opens
    func handleNotificationOpen(userInfo: [AnyHashable: Any]) {
        guard let notificationId = userInfo["notification_id"] as? String else { return }

        Task {
            try await container?.supabaseDataService.markNotificationOpened(id: UUID(uuidString: notificationId)!)
        }
    }

    // Track app open time for smart timing
    func trackAppOpen() {
        let hour = Calendar.current.component(.hour, from: Date())

        Task {
            try await container?.supabaseDataService.updateTypicalActiveHour(hour)
        }
    }
}
```

**Service Methods**:

```swift
// MARK: - Notification Tracking

func markNotificationOpened(id: UUID) async throws {
    try await supabase
        .from("notification_history")
        .update(["opened_at": Date().ISO8601Format()])
        .eq("id", id)
        .execute()
}

func updateTypicalActiveHour(_ hour: Int) async throws {
    // Rolling average approach
    let userId = try await getCurrentUserId()

    let { data: profile } = try await supabase
        .from("profiles")
        .select("typical_active_hour")
        .eq("id", userId)
        .single()
        .execute()

    let currentHour = profile?.typical_active_hour ?? hour
    let newHour = (currentHour + hour) / 2  // Simple average

    try await supabase
        .from("profiles")
        .update(["typical_active_hour": newHour])
        .eq("id", userId)
        .execute()
}

func getWeeklySummary() async throws -> WeeklySummary? {
    let weekStart = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!

    let summaries: [WeeklySummary] = try await supabase
        .from("weekly_summaries")
        .select()
        .eq("user_id", try await getCurrentUserId())
        .eq("week_start", weekStart.ISO8601Format())
        .execute()
        .value

    return summaries.first
}
```

### Backend Implementation

**Smart Notification Edge Function** (`supabase/functions/send-notification/index.ts`):

```typescript
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as apns from "./apns.ts";

interface NotificationRequest {
  type:
    | "circle_activity"
    | "hug"
    | "streak_risk"
    | "weekly_summary"
    | "challenge";
  recipientId: string;
  data: Record<string, any>;
}

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { type, recipientId, data } = (await req.json()) as NotificationRequest;

  // Get user's notification preferences
  const { data: settings } = await supabase
    .from("user_settings")
    .select("*")
    .eq("user_id", recipientId)
    .single();

  // Check if this notification type is enabled
  const typeToSetting: Record<string, string> = {
    circle_activity: "notify_circle_activity",
    hug: "notify_hugs",
    streak_risk: "notify_streak_risk",
    weekly_summary: "notify_weekly_summary",
    challenge: "notify_challenges",
  };

  if (settings && !settings[typeToSetting[type]]) {
    return new Response(JSON.stringify({ skipped: true, reason: "disabled" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  // Check quiet hours
  const { data: profile } = await supabase
    .from("profiles")
    .select("timezone, typical_active_hour")
    .eq("id", recipientId)
    .single();

  const userTimezone = profile?.timezone || "America/Los_Angeles";
  const now = new Date();
  const userHour = getHourInTimezone(now, userTimezone);

  const quietStart = settings?.quiet_hours_start_local || 22;
  const quietEnd = settings?.quiet_hours_end_local || 8;

  if (isInQuietHours(userHour, quietStart, quietEnd)) {
    // Queue for later
    return new Response(
      JSON.stringify({ queued: true, reason: "quiet_hours" }),
      {
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  // Build notification content
  const { title, body, deepLink } = buildNotificationContent(type, data);

  // Get push token
  const { data: device } = await supabase
    .from("push_tokens")
    .select("token")
    .eq("user_id", recipientId)
    .single();

  if (!device?.token) {
    return new Response(JSON.stringify({ skipped: true, reason: "no_token" }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  // Send via APNs
  const notificationId = crypto.randomUUID();
  await apns.send(device.token, {
    alert: { title, body },
    sound: "default",
    data: {
      notification_id: notificationId,
      type,
      deep_link: deepLink,
      ...data,
    },
  });

  // Log notification
  await supabase.from("notification_history").insert({
    id: notificationId,
    user_id: recipientId,
    notification_type: type,
    title,
    body,
    deep_link: deepLink,
    metadata: data,
  });

  return new Response(JSON.stringify({ sent: true, id: notificationId }), {
    headers: { "Content-Type": "application/json" },
  });
});

function buildNotificationContent(type: string, data: Record<string, any>) {
  switch (type) {
    case "circle_activity":
      return {
        title: "Circle Update",
        body: `${data.senderName} shared how they're feeling`,
        deepLink: `mindfriend://circle/${data.circleId}`,
      };

    case "hug":
      return {
        title: "You got a hug! 🤗",
        body: `${data.senderName} sent you some love`,
        deepLink: `mindfriend://circle/${data.circleId}`,
      };

    case "streak_risk":
      const messages = [
        `You've been consistent for ${data.streak} days. Tomorrow is day ${data.streak + 1}!`,
        `Your ${data.streak} day streak is at risk - check in to keep it going`,
        `Don't lose your ${data.streak} day streak!`,
      ];
      return {
        title: "🔥 Streak Alert",
        body: messages[data.urgency] || messages[0],
        deepLink: "mindfriend://quest",
      };

    case "weekly_summary":
      return {
        title: "Your Week in Review 📊",
        body: `${data.checkins} check-ins, ${data.quests} quests. ${data.moodMessage}`,
        deepLink: "mindfriend://insights",
      };

    case "challenge":
      return {
        title: "Challenge Update 🎯",
        body: `${data.completedCount}/${data.totalMembers} completed today's challenge`,
        deepLink: `mindfriend://circle/${data.circleId}`,
      };

    default:
      return {
        title: "MindFriend",
        body: "Check in with yourself today",
        deepLink: "mindfriend://",
      };
  }
}

function isInQuietHours(
  currentHour: number,
  start: number,
  end: number,
): boolean {
  if (start < end) {
    return currentHour >= start || currentHour < end;
  } else {
    return currentHour >= start && currentHour < end;
  }
}
```

**Streak Risk Cron** (`supabase/functions/check-streak-risk/index.ts`):

```typescript
// Run daily at 6 PM user local time
// For users who haven't checked in today and have a streak > 0

serve(async () => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Get users with active streaks who haven't checked in today
  const { data: atRiskUsers } = await supabase.rpc("get_streak_at_risk_users"); // Custom function

  for (const user of atRiskUsers || []) {
    await supabase.functions.invoke("send-notification", {
      body: {
        type: "streak_risk",
        recipientId: user.id,
        data: {
          streak: user.current_streak_days,
          urgency: 0, // 0 = encouraging, 1 = warning, 2 = urgent
        },
      },
    });
  }

  return new Response(JSON.stringify({ processed: atRiskUsers?.length || 0 }));
});
```

**Weekly Summary Cron** (`supabase/functions/generate-weekly-summary/index.ts`):

```typescript
// Run Sunday 6 PM user local time

serve(async () => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Get all users with weekly summary enabled
  const { data: users } = await supabase
    .from("user_settings")
    .select("user_id")
    .eq("notify_weekly_summary", true);

  const weekStart = getWeekStart();
  const weekEnd = new Date();

  for (const { user_id } of users || []) {
    // Calculate stats
    const { data: moods } = await supabase
      .from("moods")
      .select("mood_score")
      .eq("user_id", user_id)
      .gte("created_at", weekStart.toISOString())
      .lte("created_at", weekEnd.toISOString());

    const { data: quests } = await supabase
      .from("quests")
      .select("id")
      .eq("user_id", user_id)
      .eq("status", "completed")
      .gte("completed_at", weekStart.toISOString());

    const avgMood = moods?.length
      ? moods.reduce((sum, m) => sum + m.mood_score, 0) / moods.length
      : null;

    // Determine trend (compare to last week)
    const trend = await calculateMoodTrend(supabase, user_id, avgMood);

    // Save summary
    await supabase.from("weekly_summaries").upsert({
      user_id,
      week_start: weekStart.toISOString().split("T")[0],
      checkin_count: moods?.length || 0,
      quest_count: quests?.length || 0,
      avg_mood: avgMood,
      mood_trend: trend,
    });

    // Send notification
    await supabase.functions.invoke("send-notification", {
      body: {
        type: "weekly_summary",
        recipientId: user_id,
        data: {
          checkins: moods?.length || 0,
          quests: quests?.length || 0,
          moodMessage: getMoodTrendMessage(trend),
        },
      },
    });
  }

  return new Response(JSON.stringify({ processed: users?.length || 0 }));
});
```

---

## UI/UX

### Notification Preferences

```
┌─────────────────────────────────────┐
│ < Settings     Notifications        │
├─────────────────────────────────────┤
│                                     │
│  SOCIAL                             │
│  ┌─────────────────────────────┐   │
│  │ Circle activity        [✓] │   │
│  │ Hugs received          [✓] │   │
│  │ Challenge updates      [✓] │   │
│  └─────────────────────────────┘   │
│                                     │
│  MOTIVATION                         │
│  ┌─────────────────────────────┐   │
│  │ Streak at risk         [✓] │   │
│  │ Weekly summary         [✓] │   │
│  └─────────────────────────────┘   │
│                                     │
│  TIMING                             │
│  ┌─────────────────────────────┐   │
│  │ Preferred time     [9:00 AM]│   │
│  │ Quiet hours           10p-8a│ > │
│  └─────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

### Notification Examples

| Type            | Title                  | Body                                                  |
| --------------- | ---------------------- | ----------------------------------------------------- |
| Circle activity | Circle Update          | Sarah shared how they're feeling                      |
| Hug             | You got a hug! 🤗      | Danny sent you some love                              |
| Streak risk     | 🔥 Streak Alert        | You've been consistent for 6 days. Tomorrow is day 7! |
| Weekly summary  | Your Week in Review 📊 | 5 check-ins, 3 quests. Your mood is trending up!      |
| Challenge       | Challenge Update 🎯    | 3/4 completed today's challenge                       |

---

## Verification

### Manual Testing

1. **Social Notifications:**
   - Have friend post in circle
   - Verify notification received
   - Verify notification settings respected
   - Verify deep link works

2. **Streak Risk:**
   - Have streak > 0
   - Don't check in for a day
   - Verify notification at 6 PM
   - Verify copy matches streak length

3. **Weekly Summary:**
   - Wait until Sunday 6 PM
   - Verify summary notification
   - Verify stats are accurate
   - Verify mood trend correct

4. **Quiet Hours:**
   - Set quiet hours
   - Trigger notification during quiet hours
   - Verify NOT received until quiet hours end

5. **Preferences:**
   - Disable specific notification type
   - Trigger that type
   - Verify NOT received

---

## Dependencies

- Push notifications registered
- Circles feature working
- Streak tracking working
- APNs configuration complete

---

## Risks & Mitigations

| Risk                            | Likelihood | Impact | Mitigation                              |
| ------------------------------- | ---------- | ------ | --------------------------------------- |
| Users disable all notifications | Medium     | High   | Default to on, make valuable from start |
| Too many notifications          | Medium     | High   | Cap at 3/day, prioritize social         |
| Wrong timezone calculation      | Low        | Medium | Use profile timezone, test edge cases   |
| Notification fatigue            | Medium     | Medium | Weekly summary reduces daily noise      |

---

## Implementation Estimate

| Task                            | Effort       |
| ------------------------------- | ------------ |
| Database migration              | 1 hour       |
| iOS notification settings UI    | 3 hours      |
| iOS notification tracking       | 2 hours      |
| send-notification Edge Function | 4 hours      |
| streak-risk cron                | 2 hours      |
| weekly-summary cron             | 3 hours      |
| Testing                         | 3 hours      |
| **Total**                       | **18 hours** |
