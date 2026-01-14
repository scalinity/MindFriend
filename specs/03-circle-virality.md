# Viral Loop for Circles

## Overview

**Goal:** Make sharing and engagement in circles feel natural, not forced. Add social mechanics that create organic growth through genuine connection.

**Why it matters:** Circles are MindFriend's unique social feature, but manual invites have high friction. Social triggers like "send a hug," streak celebrations, and group challenges create reasons for users to engage daily and invite friends organically.

**Impact:** P3 priority - Solves growth AND retention

---

## User Stories

- As a circle member, I want to send encouragement to friends so that I can show I care without needing words
- As a user, I want my streak milestones shared automatically so that my friends can celebrate with me
- As a circle owner, I want to create challenges so that we all stay motivated together
- As an invited user, I want to know who's waiting for me so that I feel compelled to join

---

## Product Requirements

### Must Have (MVP)

1. **Send a Hug**
   - One-tap action on any circle member
   - Recipient gets push notification: "Danny sent you a hug 🤗"
   - Optional: Quick "hug back" response
   - Limit: 5 hugs per person per day

2. **Streak Sharing**
   - Automatic post when user hits milestone (7, 14, 30, 60, 100 days)
   - Post format: "🔥 Danny just hit 30 days! Keep it up!"
   - Circle members can react with emoji

3. **Circle Challenges**
   - Owner creates challenge: "Everyone do a breathing exercise today"
   - 24-hour challenges only (MVP)
   - Shows completion status for each member
   - Badge/XP reward for completing

4. **Pending Invite Nudges**
   - When inviting someone: "Sarah is waiting for you to join"
   - Notification after 24h if not joined
   - Show pending invites on circle detail

### Nice to Have (V2)

- Hug animations/effects
- Multi-day challenges
- Challenge templates ("Weekly meditation challenge")
- Reaction history
- "Most supportive" badges
- Invite via Messages/WhatsApp deep link

### Out of Scope

- Public challenges
- Challenge leaderboards
- Hug streaks
- Voice messages in circles

---

## Technical Design

### Data Model Changes

```sql
-- Migration: 20260117_circle_virality.sql

-- Table: circle_hugs
CREATE TABLE circle_hugs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),

  -- Prevent spam
  CONSTRAINT unique_hug_per_day UNIQUE (sender_id, recipient_id, (created_at::date))
);

CREATE INDEX idx_hugs_recipient ON circle_hugs(recipient_id, created_at DESC);
CREATE INDEX idx_hugs_circle ON circle_hugs(circle_id, created_at DESC);

-- Table: circle_challenges
CREATE TABLE circle_challenges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  challenge_type TEXT NOT NULL CHECK (challenge_type IN ('exercise', 'mood_checkin', 'quest', 'custom')),
  title TEXT NOT NULL,
  description TEXT,
  target_exercise_id UUID REFERENCES exercises(id),
  starts_at TIMESTAMPTZ DEFAULT NOW(),
  ends_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),

  CONSTRAINT valid_timeframe CHECK (ends_at > starts_at)
);

CREATE INDEX idx_challenges_circle ON circle_challenges(circle_id, ends_at DESC);

-- Table: challenge_completions
CREATE TABLE challenge_completions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id UUID NOT NULL REFERENCES circle_challenges(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  completed_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(challenge_id, user_id)
);

CREATE INDEX idx_completions_challenge ON challenge_completions(challenge_id);

-- Table: circle_reactions (for streak posts)
CREATE TABLE circle_reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID NOT NULL REFERENCES circle_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  emoji TEXT NOT NULL CHECK (emoji IN ('🎉', '👏', '💪', '❤️', '🔥')),
  created_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(post_id, user_id)
);

-- Add milestone posts to circle_posts
ALTER TABLE circle_posts ADD COLUMN post_type TEXT DEFAULT 'checkin'
  CHECK (post_type IN ('checkin', 'milestone', 'challenge_complete'));

-- Table: pending_invites (track who's been invited)
CREATE TABLE circle_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  circle_id UUID NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  inviter_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  invitee_email TEXT,
  invitee_phone TEXT,
  invite_code TEXT NOT NULL,
  sent_at TIMESTAMPTZ DEFAULT NOW(),
  accepted_at TIMESTAMPTZ,
  reminder_sent_at TIMESTAMPTZ,

  CHECK (invitee_email IS NOT NULL OR invitee_phone IS NOT NULL)
);

CREATE INDEX idx_invites_pending ON circle_invites(circle_id) WHERE accepted_at IS NULL;

-- RLS Policies
ALTER TABLE circle_hugs ENABLE ROW LEVEL SECURITY;
ALTER TABLE circle_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE challenge_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE circle_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE circle_invites ENABLE ROW LEVEL SECURITY;

-- Hugs: members can send/receive within their circles
CREATE POLICY "Members can send hugs in their circles"
  ON circle_hugs FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM circle_members WHERE circle_id = circle_hugs.circle_id AND user_id = auth.uid())
  );

CREATE POLICY "Members can see hugs in their circles"
  ON circle_hugs FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM circle_members WHERE circle_id = circle_hugs.circle_id AND user_id = auth.uid())
  );

-- Challenges: members can view, owner can create
CREATE POLICY "Members can view circle challenges"
  ON circle_challenges FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM circle_members WHERE circle_id = circle_challenges.circle_id AND user_id = auth.uid())
  );

CREATE POLICY "Owner can create challenges"
  ON circle_challenges FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM circles WHERE id = circle_challenges.circle_id AND owner_id = auth.uid())
  );

-- Completions: members can mark their own
CREATE POLICY "Members can mark completion"
  ON challenge_completions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Members can view completions"
  ON challenge_completions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM circle_challenges c
      JOIN circle_members m ON m.circle_id = c.circle_id
      WHERE c.id = challenge_completions.challenge_id AND m.user_id = auth.uid()
    )
  );
```

### iOS Implementation

**New Models** (`Core/Models.swift`):

```swift
struct CircleHug: Identifiable, Codable {
    let id: UUID
    let senderId: UUID
    let recipientId: UUID
    let circleId: UUID
    let createdAt: Date

    var senderName: String?  // Joined from profiles
}

struct CircleChallenge: Identifiable, Codable {
    let id: UUID
    let circleId: UUID
    let createdBy: UUID
    let challengeType: ChallengeType
    let title: String
    let description: String?
    let targetExerciseId: UUID?
    let startsAt: Date
    let endsAt: Date

    var completions: [ChallengeCompletion]?
    var creatorName: String?

    enum ChallengeType: String, Codable {
        case exercise, moodCheckin = "mood_checkin", quest, custom
    }

    var isActive: Bool {
        let now = Date()
        return now >= startsAt && now <= endsAt
    }

    var timeRemaining: String {
        let remaining = endsAt.timeIntervalSince(Date())
        let hours = Int(remaining / 3600)
        if hours > 0 {
            return "\(hours)h left"
        }
        let minutes = Int(remaining / 60)
        return "\(minutes)m left"
    }
}

struct ChallengeCompletion: Identifiable, Codable {
    let id: UUID
    let challengeId: UUID
    let userId: UUID
    let completedAt: Date

    var userName: String?
}

struct CircleReaction: Identifiable, Codable {
    let id: UUID
    let postId: UUID
    let userId: UUID
    let emoji: String
    let createdAt: Date
}

enum ReactionEmoji: String, CaseIterable {
    case party = "🎉"
    case clap = "👏"
    case strong = "💪"
    case heart = "❤️"
    case fire = "🔥"
}
```

**Service Methods** (`Networking/Services/SupabaseDataService.swift`):

```swift
// MARK: - Circle Hugs

func sendHug(to recipientId: UUID, in circleId: UUID) async throws {
    try await supabase
        .from("circle_hugs")
        .insert([
            "sender_id": try await getCurrentUserId(),
            "recipient_id": recipientId,
            "circle_id": circleId
        ])
        .execute()

    // Trigger push notification (via Edge Function)
    try await supabase.functions.invoke("send-notification", options: .init(body: [
        "type": "hug",
        "recipientId": recipientId.uuidString,
        "senderId": try await getCurrentUserId().uuidString
    ]))
}

func getHugsReceived(since: Date) async throws -> [CircleHug] {
    try await supabase
        .from("circle_hugs")
        .select("*, sender:profiles!sender_id(display_name)")
        .eq("recipient_id", try await getCurrentUserId())
        .gte("created_at", since.ISO8601Format())
        .order("created_at", ascending: false)
        .execute()
        .value
}

// MARK: - Circle Challenges

func createChallenge(in circleId: UUID, type: CircleChallenge.ChallengeType, title: String, exerciseId: UUID? = nil) async throws -> CircleChallenge {
    let endsAt = Calendar.current.date(byAdding: .hour, value: 24, to: Date())!

    let challenge: CircleChallenge = try await supabase
        .from("circle_challenges")
        .insert([
            "circle_id": circleId,
            "created_by": try await getCurrentUserId(),
            "challenge_type": type.rawValue,
            "title": title,
            "target_exercise_id": exerciseId?.uuidString,
            "ends_at": endsAt.ISO8601Format()
        ])
        .select()
        .single()
        .execute()
        .value

    return challenge
}

func getActiveChallenge(for circleId: UUID) async throws -> CircleChallenge? {
    let now = Date().ISO8601Format()

    let challenges: [CircleChallenge] = try await supabase
        .from("circle_challenges")
        .select("*, completions:challenge_completions(*)")
        .eq("circle_id", circleId)
        .gte("ends_at", now)
        .order("created_at", ascending: false)
        .limit(1)
        .execute()
        .value

    return challenges.first
}

func completeChallenge(id: UUID) async throws {
    try await supabase
        .from("challenge_completions")
        .insert([
            "challenge_id": id,
            "user_id": try await getCurrentUserId()
        ])
        .execute()
}

// MARK: - Reactions

func addReaction(to postId: UUID, emoji: ReactionEmoji) async throws {
    try await supabase
        .from("circle_reactions")
        .upsert([
            "post_id": postId,
            "user_id": try await getCurrentUserId(),
            "emoji": emoji.rawValue
        ])
        .execute()
}

func getReactions(for postId: UUID) async throws -> [CircleReaction] {
    try await supabase
        .from("circle_reactions")
        .select()
        .eq("post_id", postId)
        .execute()
        .value
}
```

**New Views**:

```swift
// SendHugButton.swift
struct SendHugButton: View {
    let member: CircleMember
    let circleId: UUID
    @EnvironmentObject var container: DependencyContainer
    @State private var isSending = false
    @State private var showSentAnimation = false

    var body: some View {
        Button {
            sendHug()
        } label: {
            Image(systemName: showSentAnimation ? "heart.fill" : "heart")
                .font(.title2)
                .foregroundColor(showSentAnimation ? .red : .accentColor)
                .scaleEffect(showSentAnimation ? 1.2 : 1.0)
                .animation(.spring(response: 0.3), value: showSentAnimation)
        }
        .disabled(isSending)
    }

    func sendHug() {
        isSending = true
        Task {
            try await container.supabaseDataService.sendHug(to: member.userId, in: circleId)
            showSentAnimation = true
            try await Task.sleep(for: .seconds(1))
            showSentAnimation = false
            isSending = false
        }
    }
}

// ChallengeCard.swift
struct ChallengeCard: View {
    let challenge: CircleChallenge
    let members: [CircleMember]
    @EnvironmentObject var container: DependencyContainer
    @State private var isCompleting = false

    var completedUserIds: Set<UUID> {
        Set(challenge.completions?.map { $0.userId } ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(challenge.title)
                        .font(.headline)
                    Text(challenge.timeRemaining)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "flag.fill")
                    .foregroundColor(.orange)
            }

            // Member completion status
            HStack(spacing: -8) {
                ForEach(members) { member in
                    ZStack {
                        Circle()
                            .fill(completedUserIds.contains(member.userId) ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 32, height: 32)

                        if completedUserIds.contains(member.userId) {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundColor(.white)
                        } else {
                            Text(member.displayName?.prefix(1) ?? "?")
                                .font(.caption)
                        }
                    }
                }
            }

            if !completedUserIds.contains(container.appState.currentUser?.id ?? UUID()) {
                Button {
                    completeChallenge()
                } label: {
                    Text("Mark Complete")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(isCompleting)
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Completed!")
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    func completeChallenge() {
        isCompleting = true
        Task {
            try await container.supabaseDataService.completeChallenge(id: challenge.id)
        }
    }
}
```

### Backend Implementation

**Streak Milestone Auto-Post** (`supabase/functions/assign-quest/index.ts`):

```typescript
// After completing a quest, check for streak milestones
async function checkStreakMilestone(
  supabase: SupabaseClient,
  userId: string,
  newStreak: number,
) {
  const milestones = [7, 14, 30, 60, 100, 365];

  if (!milestones.includes(newStreak)) return;

  // Get user's circles
  const { data: memberships } = await supabase
    .from("circle_members")
    .select("circle_id")
    .eq("user_id", userId);

  if (!memberships?.length) return;

  // Get user's display name
  const { data: profile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", userId)
    .single();

  const name = profile?.display_name || "Someone";

  // Post milestone to each circle
  for (const membership of memberships) {
    await supabase.from("circle_posts").insert({
      circle_id: membership.circle_id,
      user_id: userId,
      post_type: "milestone",
      mood_emoji: "🔥",
      body_text: `${name} just hit ${newStreak} days! Keep it up!`,
    });
  }
}
```

**Hug Notification** (`supabase/functions/send-notification/index.ts`):

```typescript
// Add handler for hug notifications
if (type === "hug") {
  const { data: sender } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", senderId)
    .single();

  const senderName = sender?.display_name || "Someone";

  await sendPushNotification(recipientId, {
    title: "You got a hug! 🤗",
    body: `${senderName} sent you some love`,
    data: { type: "hug", senderId },
  });
}
```

---

## UI/UX

### Circle Detail with Challenges

```
┌─────────────────────────────────────┐
│ < Circles     Wellness Squad        │
├─────────────────────────────────────┤
│                                     │
│  🎯 TODAY'S CHALLENGE               │
│  ┌─────────────────────────────────┐│
│  │ Do a breathing exercise        ││
│  │ 18h left                       ││
│  │                                ││
│  │ 👤✓ 👤✓ 👤○ 👤○               ││
│  │                                ││
│  │ ┌─────────────────────────┐   ││
│  │ │    Mark Complete        │   ││
│  │ └─────────────────────────┘   ││
│  └─────────────────────────────────┘│
│                                     │
│  📋 RECENT ACTIVITY                 │
│                                     │
│  🔥 Danny just hit 30 days!         │
│     Keep it up!                     │
│     [🎉 2] [👏 3] [💪 1]  + react   │
│                                     │
│  😊 Sarah: "Feeling good today"     │
│     2h ago                          │
│                                     │
│  💙 Mike: "Grateful for this group" │
│     5h ago                          │
│                                     │
└─────────────────────────────────────┘
```

### Member Card with Hug

```
┌─────────────────────────────────────┐
│  👤 Danny                      [❤️] │  ← Tap to send hug
│  🔥 14 day streak                   │
└─────────────────────────────────────┘
```

---

## Verification

### Manual Testing

1. **Send Hug:**
   - Open circle, tap hug button on member
   - Verify recipient gets push notification
   - Verify can't send more than 5/day to same person

2. **Streak Milestone:**
   - Complete quest to hit milestone (7/14/30 days)
   - Verify milestone post appears in all circles
   - Verify other members can react with emoji

3. **Challenge:**
   - Circle owner creates challenge
   - Verify all members see challenge card
   - Complete challenge, verify checkmark appears
   - Verify completion shows for all members

4. **Pending Invites:**
   - Invite someone via email/phone
   - Verify pending invite shows on circle detail
   - Verify reminder notification after 24h

---

## Dependencies

- Circles feature complete
- Push notifications working
- Quest completion tracking

---

## Risks & Mitigations

| Risk              | Likelihood | Impact | Mitigation                           |
| ----------------- | ---------- | ------ | ------------------------------------ |
| Hug spam          | Medium     | Low    | Rate limit 5/day per recipient       |
| Challenge fatigue | Medium     | Medium | One active challenge per circle max  |
| Milestone spam    | Low        | Low    | Only post for meaningful milestones  |
| Privacy concerns  | Low        | Medium | Hugs only within circles, not public |

---

## Implementation Estimate

| Task               | Effort       |
| ------------------ | ------------ |
| Database migration | 1 hour       |
| iOS Models         | 1 hour       |
| Send Hug feature   | 3 hours      |
| Challenge system   | 5 hours      |
| Streak milestones  | 2 hours      |
| Reactions          | 2 hours      |
| Push notifications | 2 hours      |
| Testing            | 2 hours      |
| **Total**          | **18 hours** |
