# Onboarding Buddy System

## Overview

**Goal:** Encourage new users to invite a friend during or immediately after onboarding, creating social accountability from day one and driving organic growth.

**Why it matters:** Users with at least one friend on the platform have 3x higher retention. A buddy creates accountability, makes the app feel less lonely, and provides a reason to return daily. This also creates a viral loop where each new user potentially brings another.

**Impact:** P4 priority - Retention + viral growth (K-factor improvement)

---

## User Stories

- As a new user, I want to invite a friend so that we can support each other
- As an invited user, I want to know who invited me so that I feel welcomed
- As buddies, we want to see each other's streaks so that we can encourage each other
- As a user who invited friends, I want rewards so that I feel appreciated

---

## Product Requirements

### Must Have (MVP)

1. **Buddy Prompt in Onboarding**
   - After wellness focus quiz: "Know anyone who'd be a great wellness buddy?"
   - Skip option clearly available (no pressure)
   - Single invite field (keep it simple)
   - Success message if sent

2. **Invite Mechanism**
   - Send via SMS or email (user's choice)
   - Personalized message: "[Name] invited you to be their wellness buddy on MindFriend"
   - Unique invite code/link per user
   - Deep link directly to app store / app

3. **Buddy Pairing**
   - When invited user joins, auto-create buddy relationship
   - Auto-create "Buddies" circle with just the two of them
   - Both users notified: "You're now buddies with [Name]!"
   - Welcome bonus for both (extra XP, head start on streak)

4. **Buddy Features**
   - See buddy's streak on home screen (small widget)
   - Send quick encouragement ("You've got this!")
   - Notification when buddy completes quest
   - "Check on your buddy" prompt if they miss a day

5. **Referral Rewards**
   - Inviter gets: +100 XP, "Good Friend" badge after first invite joins
   - Invitee gets: Start at Day 2 streak (fresh start bonus)
   - Both get: Premium badge "Buddy Pair" after 7 days together

### Nice to Have (V2)

- Multiple buddy relationships
- Buddy streaks (both complete same day = buddy streak)
- Buddy challenges (do same quest together)
- Leaderboard between buddies
- Invite via contacts picker
- WhatsApp/iMessage direct share
- Referral tracking dashboard
- Tiered rewards (more invites = better rewards)

### Out of Scope

- Monetary referral rewards
- Public referral links
- MLM-style referral trees
- Competitive buddy features

---

## Technical Design

### Data Model Changes

```sql
-- Migration: 20260121_onboarding_buddy.sql

-- Buddy relationships
CREATE TABLE buddy_relationships (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inviter_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  invitee_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  invite_code TEXT NOT NULL UNIQUE,
  invite_method TEXT CHECK (invite_method IN ('sms', 'email', 'link')),
  invitee_contact TEXT, -- phone or email before they join
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'expired')),
  invited_at TIMESTAMPTZ DEFAULT NOW(),
  accepted_at TIMESTAMPTZ,
  buddy_circle_id UUID REFERENCES circles(id),
  inviter_reward_claimed BOOLEAN DEFAULT FALSE,
  invitee_reward_claimed BOOLEAN DEFAULT FALSE,
  expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '30 days',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_buddy_inviter ON buddy_relationships(inviter_id);
CREATE INDEX idx_buddy_invitee ON buddy_relationships(invitee_id);
CREATE INDEX idx_buddy_code ON buddy_relationships(invite_code);
CREATE INDEX idx_buddy_contact ON buddy_relationships(invitee_contact);

-- Buddy activity (for streak sharing)
CREATE TABLE buddy_activity (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  buddy_relationship_id UUID NOT NULL REFERENCES buddy_relationships(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  activity_type TEXT NOT NULL CHECK (activity_type IN ('quest_complete', 'streak_milestone', 'encouragement_sent')),
  activity_date DATE NOT NULL,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_buddy_activity ON buddy_activity(buddy_relationship_id, activity_date DESC);

-- Quick messages for encouragement
CREATE TABLE buddy_encouragements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  buddy_relationship_id UUID NOT NULL REFERENCES buddy_relationships(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  message_type TEXT DEFAULT 'encouragement' CHECK (message_type IN ('encouragement', 'celebration', 'check_in')),
  message TEXT,
  seen_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_encouragements_recipient ON buddy_encouragements(recipient_id, seen_at);

-- Add buddy_invite_code to profiles for tracking
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS referral_code TEXT UNIQUE;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS referred_by UUID REFERENCES profiles(id);
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS total_referrals INT DEFAULT 0;

-- Generate referral codes for existing users
UPDATE profiles SET referral_code = UPPER(SUBSTRING(MD5(id::TEXT) FROM 1 FOR 8))
WHERE referral_code IS NULL;

-- RLS
ALTER TABLE buddy_relationships ENABLE ROW LEVEL SECURITY;
ALTER TABLE buddy_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE buddy_encouragements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users see own buddy relationships" ON buddy_relationships
  FOR SELECT USING (
    auth.uid() = inviter_id OR auth.uid() = invitee_id
  );

CREATE POLICY "Users can create buddy invites" ON buddy_relationships
  FOR INSERT WITH CHECK (auth.uid() = inviter_id);

CREATE POLICY "Users see own buddy activity" ON buddy_activity
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM buddy_relationships br
      WHERE br.id = buddy_activity.buddy_relationship_id
        AND (br.inviter_id = auth.uid() OR br.invitee_id = auth.uid())
    )
  );

CREATE POLICY "Users can send encouragements" ON buddy_encouragements
  FOR INSERT WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Users see own encouragements" ON buddy_encouragements
  FOR SELECT USING (
    auth.uid() = sender_id OR auth.uid() = recipient_id
  );

-- Function to accept buddy invite
CREATE OR REPLACE FUNCTION accept_buddy_invite(p_invite_code TEXT, p_user_id UUID)
RETURNS buddy_relationships AS $$
DECLARE
  v_relationship buddy_relationships;
  v_circle_id UUID;
  v_inviter_name TEXT;
BEGIN
  -- Find and validate invite
  SELECT * INTO v_relationship FROM buddy_relationships
  WHERE invite_code = p_invite_code
    AND status = 'pending'
    AND expires_at > NOW()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired invite code';
  END IF;

  -- Create buddy circle
  SELECT display_name INTO v_inviter_name FROM profiles WHERE id = v_relationship.inviter_id;

  INSERT INTO circles (name, description, owner_id, max_members)
  VALUES (
    'Buddies',
    'Your wellness buddy circle',
    v_relationship.inviter_id,
    2
  )
  RETURNING id INTO v_circle_id;

  -- Add both as members
  INSERT INTO circle_members (circle_id, user_id, role, status, joined_at)
  VALUES
    (v_circle_id, v_relationship.inviter_id, 'owner', 'active', NOW()),
    (v_circle_id, p_user_id, 'member', 'active', NOW());

  -- Update relationship
  UPDATE buddy_relationships SET
    invitee_id = p_user_id,
    status = 'accepted',
    accepted_at = NOW(),
    buddy_circle_id = v_circle_id
  WHERE id = v_relationship.id
  RETURNING * INTO v_relationship;

  -- Update profiles
  UPDATE profiles SET referred_by = v_relationship.inviter_id WHERE id = p_user_id;
  UPDATE profiles SET total_referrals = total_referrals + 1 WHERE id = v_relationship.inviter_id;

  -- Give invitee fresh start bonus (start at day 2)
  UPDATE profiles SET current_streak_days = 2 WHERE id = p_user_id;

  RETURN v_relationship;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Badges for buddy system
INSERT INTO badges (id, name, description, icon_name, category, unlock_criteria) VALUES
  (gen_random_uuid(), 'Good Friend', 'Invited a buddy who joined', 'person.2.fill', 'social', 'First referral accepts'),
  (gen_random_uuid(), 'Buddy Pair', 'Maintained a buddy streak for 7 days', 'heart.fill', 'social', 'Both buddies complete quests for 7 days'),
  (gen_random_uuid(), 'Social Butterfly', 'Invited 5 friends who joined', 'person.3.fill', 'social', '5 successful referrals');
```

### iOS Implementation

**New Models** (`Core/Models.swift`):

```swift
struct BuddyRelationship: Identifiable, Codable {
    let id: UUID
    let inviterId: UUID
    let inviteeId: UUID?
    let inviteCode: String
    let inviteMethod: InviteMethod?
    let inviteeContact: String?
    var status: BuddyStatus
    let invitedAt: Date
    var acceptedAt: Date?
    let buddyCircleId: UUID?
    let expiresAt: Date

    // Joined data
    var inviter: Profile?
    var invitee: Profile?

    enum InviteMethod: String, Codable {
        case sms, email, link
    }

    enum BuddyStatus: String, Codable {
        case pending, accepted, declined, expired
    }

    var buddyUser: Profile? {
        // Return the other person in the relationship
        inviter // Simplified - would need current user context
    }

    enum CodingKeys: String, CodingKey {
        case id
        case inviterId = "inviter_id"
        case inviteeId = "invitee_id"
        case inviteCode = "invite_code"
        case inviteMethod = "invite_method"
        case inviteeContact = "invitee_contact"
        case status
        case invitedAt = "invited_at"
        case acceptedAt = "accepted_at"
        case buddyCircleId = "buddy_circle_id"
        case expiresAt = "expires_at"
        case inviter, invitee
    }
}

struct BuddyEncouragement: Identifiable, Codable {
    let id: UUID
    let buddyRelationshipId: UUID
    let senderId: UUID
    let recipientId: UUID
    let messageType: MessageType
    let message: String?
    let seenAt: Date?
    let createdAt: Date

    var senderName: String?

    enum MessageType: String, Codable {
        case encouragement, celebration, checkIn = "check_in"
    }

    var displayMessage: String {
        message ?? defaultMessage
    }

    var defaultMessage: String {
        switch messageType {
        case .encouragement: return "You've got this! 💪"
        case .celebration: return "Amazing work! 🎉"
        case .checkIn: return "Hey, checking in on you! 💙"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case buddyRelationshipId = "buddy_relationship_id"
        case senderId = "sender_id"
        case recipientId = "recipient_id"
        case messageType = "message_type"
        case message
        case seenAt = "seen_at"
        case createdAt = "created_at"
        case senderName
    }
}

struct BuddyWidgetData: Codable {
    let buddyName: String
    let buddyStreak: Int
    let hasCompletedToday: Bool
    let lastEncouragement: BuddyEncouragement?
    let needsCheckIn: Bool // Buddy hasn't been active in 2+ days

    var statusMessage: String {
        if hasCompletedToday {
            return "Completed today's quest! 🎉"
        } else if needsCheckIn {
            return "Hasn't checked in recently"
        } else {
            return "\(buddyStreak) day streak"
        }
    }
}
```

**Service Methods** (`Networking/Services/SupabaseDataService.swift`):

```swift
// MARK: - Buddy System

func createBuddyInvite(contact: String, method: BuddyRelationship.InviteMethod) async throws -> BuddyRelationship {
    let userId = try await getCurrentUserId()

    // Generate unique invite code
    let inviteCode = generateBuddyCode()

    let relationship = BuddyRelationship(
        id: UUID(),
        inviterId: userId,
        inviteeId: nil,
        inviteCode: inviteCode,
        inviteMethod: method,
        inviteeContact: contact,
        status: .pending,
        invitedAt: Date(),
        acceptedAt: nil,
        buddyCircleId: nil,
        expiresAt: Date().addingTimeInterval(30 * 24 * 60 * 60)
    )

    let created: BuddyRelationship = try await supabase
        .from("buddy_relationships")
        .insert(relationship)
        .select()
        .single()
        .execute()
        .value

    // Send invite via Edge Function
    try await supabase.functions.invoke("send-buddy-invite", options: .init(body: [
        "relationshipId": created.id.uuidString,
        "contact": contact,
        "method": method.rawValue
    ]))

    return created
}

func acceptBuddyInvite(code: String) async throws -> BuddyRelationship {
    let userId = try await getCurrentUserId()

    let results: [BuddyRelationship] = try await supabase
        .rpc("accept_buddy_invite", params: [
            "p_invite_code": code,
            "p_user_id": userId
        ])
        .execute()
        .value

    guard let relationship = results.first else {
        throw APIError.custom("Failed to accept invite")
    }

    return relationship
}

func getBuddyRelationships() async throws -> [BuddyRelationship] {
    let userId = try await getCurrentUserId()

    return try await supabase
        .from("buddy_relationships")
        .select("*, inviter:profiles!inviter_id(*), invitee:profiles!invitee_id(*)")
        .or("inviter_id.eq.\(userId),invitee_id.eq.\(userId)")
        .eq("status", "accepted")
        .execute()
        .value
}

func getBuddyWidgetData() async throws -> BuddyWidgetData? {
    let userId = try await getCurrentUserId()

    // Get first active buddy relationship
    let relationships = try await getBuddyRelationships()
    guard let relationship = relationships.first else { return nil }

    // Determine buddy
    let buddyId = relationship.inviterId == userId ? relationship.inviteeId : relationship.inviterId
    guard let buddyId = buddyId else { return nil }

    // Get buddy profile and streak
    let buddy: Profile = try await supabase
        .from("profiles")
        .select("display_name, current_streak_days")
        .eq("id", buddyId)
        .single()
        .execute()
        .value

    // Check if buddy completed today
    let today = Calendar.current.startOfDay(for: Date())
    let quests: [Quest] = try await supabase
        .from("quests")
        .select("id")
        .eq("user_id", buddyId)
        .eq("status", "completed")
        .gte("completed_at", today.ISO8601Format())
        .limit(1)
        .execute()
        .value

    let hasCompletedToday = !quests.isEmpty

    // Get last encouragement
    let encouragements: [BuddyEncouragement] = try await supabase
        .from("buddy_encouragements")
        .select()
        .eq("buddy_relationship_id", relationship.id)
        .order("created_at", ascending: false)
        .limit(1)
        .execute()
        .value

    // Check if needs check-in (no activity in 2+ days)
    let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 60 * 60)
    let activity: [Quest] = try await supabase
        .from("quests")
        .select("id")
        .eq("user_id", buddyId)
        .gte("created_at", twoDaysAgo.ISO8601Format())
        .limit(1)
        .execute()
        .value

    return BuddyWidgetData(
        buddyName: buddy.displayName ?? "Buddy",
        buddyStreak: buddy.currentStreakDays ?? 0,
        hasCompletedToday: hasCompletedToday,
        lastEncouragement: encouragements.first,
        needsCheckIn: activity.isEmpty
    )
}

func sendEncouragement(to buddyId: UUID, relationshipId: UUID, type: BuddyEncouragement.MessageType) async throws {
    let userId = try await getCurrentUserId()

    try await supabase
        .from("buddy_encouragements")
        .insert([
            "buddy_relationship_id": relationshipId.uuidString,
            "sender_id": userId.uuidString,
            "recipient_id": buddyId.uuidString,
            "message_type": type.rawValue
        ])
        .execute()

    // Notify buddy
    try await supabase.functions.invoke("send-notification", options: .init(body: [
        "type": "buddy_encouragement",
        "recipientId": buddyId.uuidString,
        "data": ["messageType": type.rawValue]
    ]))
}

private func generateBuddyCode() -> String {
    let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return String((0..<6).map { _ in chars.randomElement()! })
}
```

**New Views**:

```swift
// BuddyInviteOnboardingView.swift (in onboarding flow)
struct BuddyInviteOnboardingView: View {
    @EnvironmentObject var container: DependencyContainer
    @Binding var step: OnboardingStep

    @State private var contact = ""
    @State private var inviteMethod: BuddyRelationship.InviteMethod = .sms
    @State private var isLoading = false
    @State private var showSuccess = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Header
            VStack(spacing: 16) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.accentColor)

                Text("Invite a Wellness Buddy")
                    .font(.title2.bold())

                Text("Having a buddy makes you 3x more likely to stick with your wellness goals!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Invite form
            VStack(spacing: 16) {
                Picker("Method", selection: $inviteMethod) {
                    Text("📱 Text").tag(BuddyRelationship.InviteMethod.sms)
                    Text("📧 Email").tag(BuddyRelationship.InviteMethod.email)
                }
                .pickerStyle(.segmented)

                TextField(inviteMethod == .sms ? "Phone number" : "Email address", text: $contact)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(inviteMethod == .sms ? .phonePad : .emailAddress)
                    .textContentType(inviteMethod == .sms ? .telephoneNumber : .emailAddress)
            }
            .padding(.horizontal)

            Spacer()

            // Actions
            VStack(spacing: 12) {
                Button {
                    Task { await sendInvite() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Send Invite")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(contact.isEmpty ? Color.gray : Color.accentColor)
                .foregroundStyle(.white)
                .cornerRadius(12)
                .disabled(contact.isEmpty || isLoading)

                Button {
                    step = .complete
                } label: {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .alert("Invite Sent! 🎉", isPresented: $showSuccess) {
            Button("Continue") {
                step = .complete
            }
        } message: {
            Text("We'll let you know when they join!")
        }
    }

    func sendInvite() async {
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await container.supabaseDataService.createBuddyInvite(contact: contact, method: inviteMethod)
            showSuccess = true
        } catch {
            print("Failed to send invite: \(error)")
        }
    }
}

// BuddyWidget.swift (for home screen)
struct BuddyWidget: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var buddyData: BuddyWidgetData?
    @State private var isLoading = true
    @State private var showEncouragementOptions = false

    var body: some View {
        Group {
            if let buddy = buddyData {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your Buddy")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(buddy.buddyName)
                                .font(.headline)

                            HStack(spacing: 4) {
                                if buddy.hasCompletedToday {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else if buddy.needsCheckIn {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundStyle(.orange)
                                } else {
                                    Image(systemName: "flame.fill")
                                        .foregroundStyle(.orange)
                                }
                                Text(buddy.statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button {
                            showEncouragementOptions = true
                        } label: {
                            Image(systemName: "hand.wave.fill")
                                .font(.title2)
                                .foregroundStyle(.accentColor)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else if !isLoading {
                // No buddy - prompt to invite
                InviteBuddyPrompt()
            }
        }
        .task { await loadBuddyData() }
        .confirmationDialog("Send Encouragement", isPresented: $showEncouragementOptions) {
            Button("You've got this! 💪") {
                sendEncouragement(.encouragement)
            }
            Button("Amazing work! 🎉") {
                sendEncouragement(.celebration)
            }
            Button("Checking in on you 💙") {
                sendEncouragement(.checkIn)
            }
        }
    }

    func loadBuddyData() async {
        isLoading = true
        defer { isLoading = false }

        buddyData = try? await container.supabaseDataService.getBuddyWidgetData()
    }

    func sendEncouragement(_ type: BuddyEncouragement.MessageType) {
        // Would need buddy ID and relationship ID from context
        Task {
            // try await container.supabaseDataService.sendEncouragement(...)
        }
    }
}

// InviteBuddyPrompt.swift
struct InviteBuddyPrompt: View {
    @State private var showInviteSheet = false

    var body: some View {
        Button {
            showInviteSheet = true
        } label: {
            HStack {
                Image(systemName: "person.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite a Buddy")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text("Support each other on your journey")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .sheet(isPresented: $showInviteSheet) {
            InviteBuddySheet()
        }
    }
}

// InviteBuddySheet.swift
struct InviteBuddySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var container: DependencyContainer

    @State private var contact = ""
    @State private var method: BuddyRelationship.InviteMethod = .sms
    @State private var isLoading = false
    @State private var sentInvite: BuddyRelationship?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let invite = sentInvite {
                    // Success state
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)

                        Text("Invite Sent!")
                            .font(.title2.bold())

                        Text("Share this code with your friend:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(invite.inviteCode)
                            .font(.system(.title, design: .monospaced).bold())
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)

                        Button {
                            UIPasteboard.general.string = invite.inviteCode
                        } label: {
                            Label("Copy Code", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)

                        Button("Done") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    // Input state
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.accentColor)

                        Text("Invite a Wellness Buddy")
                            .font(.title2.bold())

                        Text("You'll both get rewards when they join!")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("Method", selection: $method) {
                            Text("📱 Text").tag(BuddyRelationship.InviteMethod.sms)
                            Text("📧 Email").tag(BuddyRelationship.InviteMethod.email)
                        }
                        .pickerStyle(.segmented)
                        .padding(.top)

                        TextField(
                            method == .sms ? "Phone number" : "Email address",
                            text: $contact
                        )
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(method == .sms ? .phonePad : .emailAddress)

                        Button {
                            Task { await sendInvite() }
                        } label: {
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("Send Invite")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(contact.isEmpty || isLoading)
                    }
                    .padding()
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    func sendInvite() async {
        isLoading = true
        defer { isLoading = false }

        do {
            sentInvite = try await container.supabaseDataService.createBuddyInvite(contact: contact, method: method)
        } catch {
            print("Failed: \(error)")
        }
    }
}

// AcceptBuddyInviteView.swift (deep link handler)
struct AcceptBuddyInviteView: View {
    @EnvironmentObject var container: DependencyContainer
    let inviteCode: String

    @State private var isLoading = true
    @State private var relationship: BuddyRelationship?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            if isLoading {
                ProgressView("Connecting with your buddy...")
            } else if let rel = relationship, let inviter = rel.inviter {
                VStack(spacing: 16) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)

                    Text("You're now buddies!")
                        .font(.title.bold())

                    Text("You and \(inviter.displayName ?? "your friend") are now wellness buddies.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 8) {
                        Label("Starting bonus: Day 2 streak!", systemImage: "flame.fill")
                            .foregroundStyle(.orange)
                        Label("Private buddy circle created", systemImage: "person.2.circle")
                            .foregroundStyle(.blue)
                    }
                    .font(.subheadline)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.red)

                    Text("Invite Not Found")
                        .font(.title2.bold())

                    Text(error ?? "This invite may have expired or already been used.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding()
        .task { await acceptInvite() }
    }

    func acceptInvite() async {
        isLoading = true
        defer { isLoading = false }

        do {
            relationship = try await container.supabaseDataService.acceptBuddyInvite(code: inviteCode)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
```

### Backend Implementation

**Send Buddy Invite Edge Function** (`supabase/functions/send-buddy-invite/index.ts`):

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { relationshipId, contact, method } = await req.json();

  // Get relationship and inviter details
  const { data: relationship } = await supabase
    .from("buddy_relationships")
    .select("*, inviter:profiles!inviter_id(display_name)")
    .eq("id", relationshipId)
    .single();

  if (!relationship) {
    return new Response(JSON.stringify({ error: "Relationship not found" }), {
      status: 404,
    });
  }

  const inviterName = relationship.inviter?.display_name || "Your friend";
  const inviteCode = relationship.invite_code;
  const deepLink = `https://getmindfriend.app/buddy/${inviteCode}`;

  const message = `${inviterName} invited you to be their wellness buddy on MindFriend! Join them: ${deepLink}`;

  if (method === "sms") {
    // Send via SMS provider (Twilio, etc.)
    // await sendSMS(contact, message);
  } else if (method === "email") {
    // Send via email provider (Resend, etc.)
    await supabase.functions.invoke("send-email", {
      body: {
        to: contact,
        subject: `${inviterName} invited you to MindFriend`,
        html: `
          <h2>${inviterName} wants you to be their wellness buddy!</h2>
          <p>Join MindFriend and support each other on your wellness journey.</p>
          <p><strong>Your invite code:</strong> ${inviteCode}</p>
          <p><a href="${deepLink}">Click here to join</a></p>
        `,
      },
    });
  }

  return new Response(JSON.stringify({ success: true }));
});
```

---

## UI/UX

### Onboarding Buddy Invite Step

```
┌─────────────────────────────────────────┐
│                                         │
│              👥                         │
│                                         │
│     Invite a Wellness Buddy             │
│                                         │
│   Having a buddy makes you 3x more      │
│   likely to stick with your goals!      │
│                                         │
│   ┌───────────────┬───────────────┐     │
│   │   📱 Text     │   📧 Email   │     │
│   └───────────────┴───────────────┘     │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │ Phone number                    │   │
│   └─────────────────────────────────┘   │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │         Send Invite             │   │
│   └─────────────────────────────────┘   │
│                                         │
│            Skip for now                 │
│                                         │
└─────────────────────────────────────────┘
```

### Home Screen Buddy Widget

```
┌─────────────────────────────────────────┐
│ Your Buddy                         👋   │
│ Sarah                                   │
│ ✓ Completed today's quest! 🎉          │
└─────────────────────────────────────────┘
```

### Needs Check-In State

```
┌─────────────────────────────────────────┐
│ Your Buddy                         👋   │
│ Sarah                                   │
│ ⚠️ Hasn't checked in recently          │
└─────────────────────────────────────────┘
```

---

## Verification

### Manual Testing

1. **Send Invite (Onboarding):**
   - Complete onboarding to buddy step
   - Enter phone/email
   - Verify invite sent
   - Check `buddy_relationships` table

2. **Accept Invite:**
   - New user uses invite code
   - Verify buddy relationship created
   - Verify buddy circle created
   - Verify both users are members

3. **Buddy Widget:**
   - After buddy joins, verify widget appears
   - Verify streak shows correctly
   - Send encouragement, verify notification

4. **Rewards:**
   - Verify inviter gets XP when buddy joins
   - Verify invitee starts at Day 2
   - After 7 days together, verify badge awarded

---

## Dependencies

- Onboarding flow
- Circles feature
- Push notifications
- Email/SMS sending capability

---

## Risks & Mitigations

| Risk                | Likelihood | Impact | Mitigation                            |
| ------------------- | ---------- | ------ | ------------------------------------- |
| Invite spam         | Low        | Medium | Rate limit invites per user           |
| Privacy concerns    | Medium     | High   | Clear consent, no contact scraping    |
| Buddy goes inactive | High       | Medium | Check-in prompts, don't guilt         |
| Code guessing       | Low        | Low    | 6-char alphanumeric = 2B combinations |

---

## Implementation Estimate

| Task               | Effort       |
| ------------------ | ------------ |
| Database migration | 2 hours      |
| iOS Models         | 1 hour       |
| Service methods    | 3 hours      |
| Onboarding step    | 3 hours      |
| Buddy widget       | 2 hours      |
| Invite sheet       | 2 hours      |
| Accept flow        | 2 hours      |
| Edge Functions     | 3 hours      |
| Testing            | 3 hours      |
| **Total**          | **21 hours** |

---

## Success Metrics

| Metric                           | Current | Target      |
| -------------------------------- | ------- | ----------- |
| Onboarding invite send rate      | N/A     | 25%         |
| Invite acceptance rate           | N/A     | 30%         |
| D30 retention (users with buddy) | N/A     | 3x baseline |
| K-factor contribution            | N/A     | 0.15        |
| Buddy streak maintenance (7d)    | N/A     | 40%         |
