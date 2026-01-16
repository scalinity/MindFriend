# Re-engagement Flows for Lapsed Users

## Overview

**Goal:** Create specialized experiences that bring back users who have stopped using the app, with empathetic messaging that acknowledges the gap without judgment.

**Why it matters:** 70-80% of users who install a wellness app become inactive within 30 days. Re-engagement flows can recover 15-30% of these lapsed users. The key is meeting them where they are emotionally—breaks happen, and the app should feel welcoming, not guilt-inducing.

**Impact:** P2 priority - Critical for long-term retention

---

## User Stories

- As a lapsed user, I want to feel welcomed back without judgment so that I don't feel guilty about my break
- As a returning user, I want a fresh start option so that I can begin again without feeling behind
- As a lapsed user, I want to know my friends missed me so that I feel connected to the community
- As someone returning after hardship, I want the AI to acknowledge my absence with empathy

---

## Product Requirements

### Must Have (MVP)

1. **Lapse Detection**
   - Track `last_session_at` timestamp
   - Define lapse tiers:
     - 3-6 days: "Brief break"
     - 7-13 days: "Extended break"
     - 14-29 days: "Long absence"
     - 30+ days: "Returning after hiatus"

2. **Welcome Back Modal**
   - Appears on first app open after 3+ day absence
   - Warm, non-judgmental messaging
   - Options: "Pick up where I left off" or "Fresh Start"
   - Shows what they missed (circle activity, streaks by friends)
   - Never mentions lost streak in a negative way

3. **Fresh Start Option**
   - Resets streak display to 0 (historical data preserved)
   - Assigns a new "welcome back" quest (shorter, 3-5 min)
   - Fresh Start bonus: Start at Day 2 instead of Day 1
   - Optional: Reset mood history view (data still stored)

4. **Social Re-engagement Hooks**
   - "Sarah sent you 3 hugs while you were away"
   - "Your circle had 12 check-ins - they'd love to hear from you"
   - "Mike just hit a 30-day streak - send him congrats!"

5. **AI Companion Acknowledgment**
   - AI's first message after absence acknowledges gap naturally
   - "It's been a little while - no pressure, but I'm here when you need me"
   - If user previously mentioned hardship, AI recalls with empathy
   - Never asks "where have you been?" in accusatory way

6. **Re-engagement Notifications**
   - Day 3: Gentle check-in ("We miss your check-ins")
   - Day 7: Social hook ("[Friend] sent you a hug")
   - Day 14: Loss aversion ("Your progress is still saved")
   - Day 30: Fresh start offer ("Ready for a fresh start?")

### Nice to Have (V2)

- "Catch up" mode: See timeline of what you missed
- Re-engagement rewards: Bonus XP for returning
- "Life happened" quick reasons (illness, travel, busy)
- Gradual difficulty ramp-down for returning users
- Personalized re-engagement based on why they left

### Out of Scope

- Automatic account deletion after inactivity
- Win-back email campaigns (separate marketing initiative)
- In-app messaging from support team
- Incentivized re-engagement (gift cards, etc.)

---

## Technical Design

### Data Model Changes

```sql
-- Migration: 20260117_reengagement_flows.sql

-- Track session history
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS last_session_at TIMESTAMPTZ;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS session_count INT DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS last_absence_days INT DEFAULT 0;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS fresh_start_used_at TIMESTAMPTZ;

-- Re-engagement events tracking
CREATE TABLE reengagement_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN (
    'welcome_back_shown',
    'welcome_back_dismissed',
    'fresh_start_chosen',
    'continue_chosen',
    'notification_sent',
    'notification_opened'
  )),
  absence_days INT NOT NULL,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_reengagement_user ON reengagement_events(user_id, created_at DESC);
CREATE INDEX idx_reengagement_type ON reengagement_events(event_type, created_at DESC);

-- Missed activity summary (cached for performance)
CREATE TABLE missed_activity_summaries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  since_date DATE NOT NULL,
  hugs_received INT DEFAULT 0,
  circle_posts_count INT DEFAULT 0,
  friend_milestones JSONB DEFAULT '[]'::jsonb, -- [{name, milestone, type}]
  challenges_missed INT DEFAULT 0,
  generated_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(user_id, since_date)
);

CREATE INDEX idx_missed_activity_user ON missed_activity_summaries(user_id);

-- RLS
ALTER TABLE reengagement_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE missed_activity_summaries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users see own reengagement events" ON reengagement_events
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users see own missed activity" ON missed_activity_summaries
  FOR SELECT USING (auth.uid() = user_id);

-- Function to calculate absence and generate summary
CREATE OR REPLACE FUNCTION calculate_user_absence(p_user_id UUID)
RETURNS TABLE(
  absence_days INT,
  lapse_tier TEXT,
  hugs_received INT,
  circle_posts INT,
  friend_milestones JSONB
) AS $$
DECLARE
  v_last_session TIMESTAMPTZ;
  v_days INT;
  v_tier TEXT;
  v_hugs INT;
  v_posts INT;
  v_milestones JSONB;
BEGIN
  -- Get last session
  SELECT last_session_at INTO v_last_session FROM profiles WHERE id = p_user_id;

  -- Calculate days absent
  v_days := COALESCE(EXTRACT(DAY FROM NOW() - v_last_session)::INT, 0);

  -- Determine tier
  v_tier := CASE
    WHEN v_days < 3 THEN 'active'
    WHEN v_days < 7 THEN 'brief_break'
    WHEN v_days < 14 THEN 'extended_break'
    WHEN v_days < 30 THEN 'long_absence'
    ELSE 'hiatus'
  END;

  -- Count hugs received since last session
  SELECT COUNT(*) INTO v_hugs
  FROM circle_hugs
  WHERE recipient_id = p_user_id
    AND created_at > COALESCE(v_last_session, NOW() - INTERVAL '30 days');

  -- Count circle posts
  SELECT COUNT(*) INTO v_posts
  FROM circle_posts cp
  JOIN circle_members cm ON cm.circle_id = cp.circle_id
  WHERE cm.user_id = p_user_id
    AND cp.user_id != p_user_id
    AND cp.created_at > COALESCE(v_last_session, NOW() - INTERVAL '30 days');

  -- Get friend milestones
  SELECT json_agg(json_build_object(
    'name', p.display_name,
    'milestone', cp.body_text,
    'streak', CASE WHEN cp.body_text LIKE '%streak%' THEN TRUE ELSE FALSE END
  )) INTO v_milestones
  FROM circle_posts cp
  JOIN profiles p ON p.id = cp.user_id
  JOIN circle_members cm ON cm.circle_id = cp.circle_id
  WHERE cm.user_id = p_user_id
    AND cp.post_type = 'milestone'
    AND cp.created_at > COALESCE(v_last_session, NOW() - INTERVAL '30 days')
  LIMIT 5;

  RETURN QUERY SELECT v_days, v_tier, v_hugs, v_posts, COALESCE(v_milestones, '[]'::jsonb);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update last_session_at on app open
CREATE OR REPLACE FUNCTION update_session_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE profiles SET
    last_session_at = NOW(),
    session_count = session_count + 1,
    last_absence_days = COALESCE(EXTRACT(DAY FROM NOW() - last_session_at)::INT, 0)
  WHERE id = NEW.user_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### iOS Implementation

**New Models** (`Core/Models.swift`):

```swift
enum LapseTier: String, Codable {
    case active = "active"
    case briefBreak = "brief_break"
    case extendedBreak = "extended_break"
    case longAbsence = "long_absence"
    case hiatus = "hiatus"

    var welcomeMessage: String {
        switch self {
        case .active:
            return ""
        case .briefBreak:
            return "Good to see you!"
        case .extendedBreak:
            return "Welcome back! We missed you."
        case .longAbsence:
            return "It's great to have you back."
        case .hiatus:
            return "Welcome back, friend. We're glad you're here."
        }
    }

    var subMessage: String {
        switch self {
        case .active:
            return ""
        case .briefBreak:
            return "Ready to continue your wellness journey?"
        case .extendedBreak:
            return "Life gets busy sometimes. No judgment here."
        case .longAbsence:
            return "Whatever brought you back, we're here for you."
        case .hiatus:
            return "Every moment is a chance for a fresh start. Your progress is still saved."
        }
    }

    var showFreshStart: Bool {
        switch self {
        case .active, .briefBreak:
            return false
        case .extendedBreak, .longAbsence, .hiatus:
            return true
        }
    }
}

struct AbsenceSummary: Codable {
    let absenceDays: Int
    let lapseTier: LapseTier
    let hugsReceived: Int
    let circlePosts: Int
    let friendMilestones: [FriendMilestone]

    struct FriendMilestone: Codable {
        let name: String
        let milestone: String
        let streak: Bool
    }

    var hasActivity: Bool {
        hugsReceived > 0 || circlePosts > 0 || !friendMilestones.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case absenceDays = "absence_days"
        case lapseTier = "lapse_tier"
        case hugsReceived = "hugs_received"
        case circlePosts = "circle_posts"
        case friendMilestones = "friend_milestones"
    }
}

struct ReengagementEvent: Codable {
    let userId: UUID
    let eventType: ReengagementEventType
    let absenceDays: Int
    let metadata: [String: String]

    enum ReengagementEventType: String, Codable {
        case welcomeBackShown = "welcome_back_shown"
        case welcomeBackDismissed = "welcome_back_dismissed"
        case freshStartChosen = "fresh_start_chosen"
        case continueChosen = "continue_chosen"
        case notificationSent = "notification_sent"
        case notificationOpened = "notification_opened"
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case eventType = "event_type"
        case absenceDays = "absence_days"
        case metadata
    }
}
```

**Service Methods** (`Networking/Services/SupabaseDataService.swift`):

```swift
// MARK: - Re-engagement

func checkUserAbsence() async throws -> AbsenceSummary? {
    let userId = try await getCurrentUserId()

    let results: [AbsenceSummary] = try await supabase
        .rpc("calculate_user_absence", params: ["p_user_id": userId])
        .execute()
        .value

    return results.first
}

func recordSessionStart() async throws {
    let userId = try await getCurrentUserId()

    try await supabase
        .from("profiles")
        .update([
            "last_session_at": Date().ISO8601Format(),
            "session_count": "session_count + 1" // Raw SQL increment
        ])
        .eq("id", userId)
        .execute()
}

func logReengagementEvent(type: ReengagementEvent.ReengagementEventType, absenceDays: Int, metadata: [String: String] = [:]) async throws {
    let userId = try await getCurrentUserId()

    try await supabase
        .from("reengagement_events")
        .insert([
            "user_id": userId.uuidString,
            "event_type": type.rawValue,
            "absence_days": absenceDays,
            "metadata": metadata
        ])
        .execute()
}

func performFreshStart() async throws {
    let userId = try await getCurrentUserId()

    // Reset visible streak but preserve history
    try await supabase
        .from("profiles")
        .update([
            "current_streak_days": 2, // Fresh start bonus: start at day 2
            "fresh_start_used_at": Date().ISO8601Format()
        ])
        .eq("id", userId)
        .execute()

    // Log the event
    try await logReengagementEvent(type: .freshStartChosen, absenceDays: 0)

    // Assign a short welcome-back quest
    try await supabase.functions.invoke("assign-quest", options: .init(body: [
        "type": "welcome_back",
        "userId": userId.uuidString
    ]))
}

func getAIWelcomeBackContext() async throws -> String? {
    let absence = try await checkUserAbsence()
    guard let absence = absence, absence.absenceDays >= 3 else { return nil }

    var context = "The user hasn't opened the app in \(absence.absenceDays) days. "
    context += "Acknowledge this gently without being pushy or guilt-inducing. "
    context += "Express that you're glad they're back. "

    if absence.hugsReceived > 0 {
        context += "Mention that their friends sent them \(absence.hugsReceived) hugs while they were away. "
    }

    return context
}
```

**New Views**:

```swift
// WelcomeBackView.swift
struct WelcomeBackView: View {
    @EnvironmentObject var container: DependencyContainer
    @Binding var isPresented: Bool

    let absenceSummary: AbsenceSummary

    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Welcome illustration
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.accentColor)

            // Welcome message
            VStack(spacing: 8) {
                Text(absenceSummary.lapseTier.welcomeMessage)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(absenceSummary.lapseTier.subMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // What you missed section
            if absenceSummary.hasActivity {
                WhatYouMissedCard(summary: absenceSummary)
            }

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                Button {
                    Task { await continuePath() }
                } label: {
                    Text("Continue My Journey")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }

                if absenceSummary.lapseTier.showFreshStart {
                    Button {
                        Task { await freshStart() }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Fresh Start")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.accentColor)
                    }

                    Text("Start fresh with a bonus - begin at Day 2!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 32)
        }
        .padding()
        .onAppear {
            Task {
                try? await container.supabaseDataService.logReengagementEvent(
                    type: .welcomeBackShown,
                    absenceDays: absenceSummary.absenceDays
                )
            }
        }
    }

    func continuePath() async {
        isLoading = true
        defer { isLoading = false }

        try? await container.supabaseDataService.logReengagementEvent(
            type: .continueChosen,
            absenceDays: absenceSummary.absenceDays
        )

        isPresented = false
    }

    func freshStart() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await container.supabaseDataService.performFreshStart()
            isPresented = false
        } catch {
            print("Fresh start failed: \(error)")
        }
    }
}

// WhatYouMissedCard.swift
struct WhatYouMissedCard: View {
    let summary: AbsenceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("While you were away...")
                .font(.subheadline.bold())

            VStack(alignment: .leading, spacing: 8) {
                if summary.hugsReceived > 0 {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                        Text("You received \(summary.hugsReceived) hugs from friends")
                            .font(.subheadline)
                    }
                }

                if summary.circlePosts > 0 {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(.blue)
                        Text("\(summary.circlePosts) new posts in your circles")
                            .font(.subheadline)
                    }
                }

                ForEach(summary.friendMilestones.prefix(3), id: \.name) { milestone in
                    HStack {
                        Image(systemName: milestone.streak ? "flame.fill" : "star.fill")
                            .foregroundStyle(milestone.streak ? .orange : .yellow)
                        Text("\(milestone.name) hit a milestone!")
                            .font(.subheadline)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// Integration in AppState or RootView
extension AppState {
    func checkReengagement() async {
        guard authState == .authenticated else { return }

        do {
            let summary = try await container.supabaseDataService.checkUserAbsence()

            if let summary = summary, summary.absenceDays >= 3 {
                // Show welcome back modal
                await MainActor.run {
                    self.pendingReengagement = summary
                    self.showWelcomeBack = true
                }
            }

            // Always record session start
            try await container.supabaseDataService.recordSessionStart()
        } catch {
            print("Reengagement check failed: \(error)")
        }
    }
}
```

### Backend Implementation

**Re-engagement Notification Cron** (`supabase/functions/check-lapsed-users/index.ts`):

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Run daily at 6 PM
serve(async () => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const now = new Date();

  // Get users who need re-engagement notifications
  const lapseConfigs = [
    { days: 3, type: "gentle_checkin", message: "We miss your check-ins 💙" },
    { days: 7, type: "social_hook", message: null }, // Custom message with social data
    {
      days: 14,
      type: "progress_saved",
      message:
        "Your wellness journey progress is still saved. Ready to continue?",
    },
    {
      days: 30,
      type: "fresh_start",
      message: "Ready for a fresh start? Your data is waiting for you.",
    },
  ];

  for (const config of lapseConfigs) {
    const targetDate = new Date(
      now.getTime() - config.days * 24 * 60 * 60 * 1000,
    );
    const dayBefore = new Date(targetDate.getTime() - 24 * 60 * 60 * 1000);

    // Get users who were last active on target date (exactly N days ago)
    const { data: users } = await supabase
      .from("profiles")
      .select("id, display_name")
      .gte("last_session_at", dayBefore.toISOString())
      .lt("last_session_at", targetDate.toISOString());

    for (const user of users || []) {
      let message = config.message;

      // For social hook, get personalized message
      if (config.type === "social_hook") {
        const { data: hugs } = await supabase
          .from("circle_hugs")
          .select("sender_id, profiles!sender_id(display_name)")
          .eq("recipient_id", user.id)
          .gte("created_at", targetDate.toISOString())
          .limit(1);

        if (hugs?.length) {
          message = `${hugs[0].profiles?.display_name} sent you a hug 🤗`;
        } else {
          message = "Your circle friends are wondering how you're doing";
        }
      }

      // Check if we already sent this notification
      const { data: existing } = await supabase
        .from("reengagement_events")
        .select("id")
        .eq("user_id", user.id)
        .eq("event_type", "notification_sent")
        .eq("metadata->>notification_type", config.type)
        .single();

      if (existing) continue; // Already sent

      // Send notification
      await supabase.functions.invoke("send-notification", {
        body: {
          type: "reengagement",
          recipientId: user.id,
          data: {
            title: "MindFriend",
            body: message,
            notificationType: config.type,
            absenceDays: config.days,
          },
        },
      });

      // Log the sent notification
      await supabase.from("reengagement_events").insert({
        user_id: user.id,
        event_type: "notification_sent",
        absence_days: config.days,
        metadata: { notification_type: config.type },
      });
    }
  }

  return new Response(JSON.stringify({ success: true }));
});
```

**AI Context Injection** (update `supabase/functions/chat/index.ts`):

```typescript
// Add to chat function before generating response

async function getReengagementContext(
  supabase: SupabaseClient,
  userId: string,
): Promise<string> {
  const { data: profile } = await supabase
    .from("profiles")
    .select("last_session_at, display_name")
    .eq("id", userId)
    .single();

  if (!profile?.last_session_at) return "";

  const lastSession = new Date(profile.last_session_at);
  const daysSince = Math.floor(
    (Date.now() - lastSession.getTime()) / (1000 * 60 * 60 * 24),
  );

  if (daysSince < 3) return "";

  // Check if this is first message since returning
  const { data: recentMessages } = await supabase
    .from("messages")
    .select("id")
    .eq("user_id", userId)
    .gte("created_at", new Date(Date.now() - 60000).toISOString()) // Last minute
    .limit(2);

  if (recentMessages && recentMessages.length > 1) return ""; // Not first message

  // Get hugs received
  const { count: hugCount } = await supabase
    .from("circle_hugs")
    .select("id", { count: "exact" })
    .eq("recipient_id", userId)
    .gte("created_at", lastSession.toISOString());

  let context = `\n\n[IMPORTANT CONTEXT: ${profile.display_name || "This user"} is returning after ${daysSince} days away. `;
  context += "This is their first message back. ";
  context +=
    "Warmly acknowledge their return without being pushy or making them feel guilty. ";
  context += "Be supportive and express that you're glad they're back. ";

  if (hugCount && hugCount > 0) {
    context += `Their friends sent them ${hugCount} hugs while they were away - you could mention this positively. `;
  }

  context += "Do NOT ask 'where have you been' in an accusatory way. ";
  context +=
    "Keep it brief - one sentence of acknowledgment, then focus on being helpful.]";

  return context;
}

// In main handler:
const reengagementContext = await getReengagementContext(
  supabaseAdmin,
  user.id,
);
const systemPromptWithContext =
  SYSTEM_PROMPT + memoryContext + reengagementContext;
```

---

## UI/UX

### Welcome Back Modal (7+ day absence)

```
┌─────────────────────────────────────────┐
│                                         │
│              💜                         │
│                                         │
│      Welcome back, friend.              │
│      We're glad you're here.            │
│                                         │
│   Whatever brought you back, we're      │
│   here for you. Life gets busy          │
│   sometimes. No judgment here.          │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │ While you were away...          │   │
│   │ 💗 3 hugs from friends          │   │
│   │ 💬 8 new posts in your circles  │   │
│   │ 🔥 Sarah hit a 30-day streak!   │   │
│   └─────────────────────────────────┘   │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │     Continue My Journey         │   │
│   └─────────────────────────────────┘   │
│                                         │
│          🔄 Fresh Start                 │
│   Start fresh with a bonus - Day 2!    │
│                                         │
└─────────────────────────────────────────┘
```

### Re-engagement Notification Sequence

| Day | Title      | Body                                             |
| --- | ---------- | ------------------------------------------------ |
| 3   | MindFriend | We miss your check-ins 💙                        |
| 7   | MindFriend | Sarah sent you a hug 🤗                          |
| 14  | MindFriend | Your progress is still saved. Ready to continue? |
| 30  | MindFriend | Ready for a fresh start? Your data is waiting.   |

### AI Response Examples

**Good (empathetic):**

> "It's really nice to hear from you again! I'm glad you're back. What's on your mind today?"

**Good (mentions hugs):**

> "Hey! Your friends sent you some hugs while you were away - they were thinking of you. How are you feeling today?"

**Bad (guilt-inducing):**

> "You've been away for a while! Why didn't you check in?"

**Bad (too focused on absence):**

> "It's been 14 days since we talked. What happened?"

---

## Verification

### Manual Testing

1. **Lapse Detection:**
   - Set `last_session_at` to 7 days ago
   - Open app
   - Verify welcome back modal appears
   - Verify correct tier messaging

2. **Fresh Start:**
   - Choose "Fresh Start" option
   - Verify streak shows as Day 2
   - Verify welcome-back quest assigned
   - Verify historical data still accessible in insights

3. **Continue Path:**
   - Choose "Continue My Journey"
   - Verify no changes to streak
   - Verify normal app experience

4. **Social Hooks:**
   - Have friend send hugs/posts while "away"
   - Verify "What you missed" shows correct data
   - Verify AI mentions hugs if relevant

5. **Notifications:**
   - Set `last_session_at` to exact threshold dates
   - Run cron manually
   - Verify appropriate notification sent
   - Verify no duplicate notifications

6. **AI Acknowledgment:**
   - Return after 7+ days
   - Send chat message
   - Verify AI warmly acknowledges return
   - Verify subsequent messages don't mention absence

---

## Dependencies

- Push notifications working
- Circle hugs feature working
- AI chat working
- Profile table with timestamps

---

## Risks & Mitigations

| Risk                      | Likelihood | Impact | Mitigation                               |
| ------------------------- | ---------- | ------ | ---------------------------------------- |
| Welcome modal annoying    | Medium     | Medium | Only show once per absence, easy dismiss |
| Fresh start abuse         | Low        | Low    | Only affects display, data preserved     |
| Notifications feel spammy | Medium     | High   | Limit to one per tier, respectful copy   |
| AI sounds robotic         | Medium     | Medium | Careful prompt engineering, A/B test     |

---

## Implementation Estimate

| Task                 | Effort       |
| -------------------- | ------------ |
| Database migration   | 2 hours      |
| iOS Models           | 1 hour       |
| Service methods      | 2 hours      |
| Welcome Back UI      | 4 hours      |
| Notification cron    | 3 hours      |
| AI context injection | 2 hours      |
| Testing              | 3 hours      |
| **Total**            | **17 hours** |

---

## Success Metrics

| Metric                               | Current | Target              |
| ------------------------------------ | ------- | ------------------- |
| D7 return rate (3-6 day lapsed)      | Measure | 40%                 |
| D14 return rate (7-13 day lapsed)    | Measure | 25%                 |
| D30 return rate (14-29 day lapsed)   | Measure | 15%                 |
| Fresh start usage rate               | N/A     | 20-30% of returners |
| Re-engagement notification open rate | N/A     | >15%                |
| AI acknowledgment satisfaction       | N/A     | >4.0/5 rating       |
