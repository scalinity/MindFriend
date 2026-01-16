# Celebration Moments & Social Sharing

## Overview

**Goal:** Amplify emotional payoffs for achievements by creating share-worthy celebration moments that users want to post to their circles and beyond.

**Why it matters:** Achievements feel hollow without recognition. Social sharing serves two purposes: (1) deepens the user's emotional connection to their progress, and (2) drives organic growth through social proof. Users who share milestones have 2x higher retention.

**Impact:** P3 priority - Retention + organic growth

---

## User Stories

- As a user who hit a milestone, I want to celebrate with animated visuals so that the moment feels special
- As a user with an achievement, I want to share with my circle so that my friends can celebrate with me
- As a user, I want to share my progress externally so that I can inspire others
- As a circle member, I want to celebrate friends' achievements so that we support each other

---

## Product Requirements

### Must Have (MVP)

1. **Enhanced Celebration Modals**
   - Full-screen takeover with confetti animation
   - Haptic feedback (medium impact)
   - Optional celebration sound (toggleable)
   - Large achievement icon/badge display
   - "Share to Circle" and "Share Externally" buttons

2. **Shareable Achievement Cards**
   - Generate image card (1080x1920 for Stories, 1200x630 for feed)
   - MindFriend branding (subtle, bottom corner)
   - Dynamic content: streak count, badge name, level
   - Personalized message option
   - QR code linking to app (optional)

3. **Circle Auto-Post Option**
   - "Share this milestone with your circle?"
   - Auto-generates post: "🎉 [Name] just hit a [X]-day streak!"
   - Circle members can react with celebratory emojis
   - Post appears in circle feed immediately

4. **Milestone Triggers**
   - Streak milestones: 7, 14, 30, 60, 100, 365 days
   - Level ups: Every level
   - Badge unlocks: Every new badge
   - Quest milestones: 10, 50, 100, 500 quests
   - Exercise milestones: 10, 50, 100 exercises

5. **Circle Celebration Reactions**
   - When milestone shared, notify circle members
   - Quick-react buttons on milestone posts
   - Reaction animations (emojis fly up)
   - "X people celebrated with you" summary

### Nice to Have (V2)

- Video celebration cards (animated)
- "Year in Review" shareable at year end
- Custom celebration messages
- Achievement comparison with friends
- Social media direct sharing (IG, Twitter API)
- Celebration reminders ("Sarah's about to hit 30 days!")

### Out of Scope

- Public leaderboards
- External social network integration (deep)
- Achievement contests
- Monetary rewards for sharing

---

## Technical Design

### Data Model Changes

```sql
-- Migration: 20260120_celebration_sharing.sql

-- Celebration events tracking
CREATE TABLE celebration_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  celebration_type TEXT NOT NULL CHECK (celebration_type IN (
    'streak_milestone', 'level_up', 'badge_unlock', 'quest_milestone', 'exercise_milestone'
  )),
  value INT NOT NULL, -- streak days, level number, quest count, etc.
  badge_id UUID REFERENCES badges(id),
  shown_at TIMESTAMPTZ DEFAULT NOW(),
  shared_to_circle BOOLEAN DEFAULT FALSE,
  shared_externally BOOLEAN DEFAULT FALSE,
  circle_post_id UUID REFERENCES circle_posts(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_celebrations_user ON celebration_events(user_id, created_at DESC);
CREATE INDEX idx_celebrations_type ON celebration_events(celebration_type, created_at DESC);

-- Shareable card templates
CREATE TABLE share_card_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_type TEXT NOT NULL, -- streak, badge, level, exercise
  background_color TEXT NOT NULL,
  accent_color TEXT NOT NULL,
  icon_name TEXT NOT NULL,
  message_template TEXT NOT NULL, -- "I just hit a {value}-day streak!"
  is_active BOOLEAN DEFAULT TRUE
);

-- Pre-populate templates
INSERT INTO share_card_templates (template_type, background_color, accent_color, icon_name, message_template) VALUES
  ('streak_7', '#FF6B35', '#FFFFFF', 'flame.fill', 'One week strong! 🔥 {value} days of wellness.'),
  ('streak_30', '#FF6B35', '#FFFFFF', 'flame.fill', 'One month! 🎉 {value} days and counting.'),
  ('streak_100', '#FFD700', '#000000', 'flame.fill', '💯 days of dedication. Unstoppable!'),
  ('level_up', '#6B5B95', '#FFFFFF', 'star.fill', 'Level {value} unlocked! ⭐'),
  ('badge_unlock', '#88B04B', '#FFFFFF', 'trophy.fill', 'New badge: {badge_name}! 🏆'),
  ('quest_milestone', '#0072B2', '#FFFFFF', 'checkmark.seal.fill', '{value} quests completed! 💪');

-- Celebration reactions (separate from general circle reactions for analytics)
CREATE TABLE celebration_reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  celebration_event_id UUID NOT NULL REFERENCES celebration_events(id) ON DELETE CASCADE,
  reactor_user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  emoji TEXT NOT NULL CHECK (emoji IN ('🎉', '👏', '🔥', '💪', '❤️', '⭐')),
  created_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(celebration_event_id, reactor_user_id)
);

CREATE INDEX idx_celebration_reactions ON celebration_reactions(celebration_event_id);

-- RLS
ALTER TABLE celebration_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE share_card_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE celebration_reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users see own celebrations" ON celebration_events
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Service can insert celebrations" ON celebration_events
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Anyone can read templates" ON share_card_templates
  FOR SELECT USING (true);

CREATE POLICY "Circle members can react to celebrations" ON celebration_reactions
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM celebration_events ce
      JOIN circle_posts cp ON cp.id = ce.circle_post_id
      JOIN circle_members cm ON cm.circle_id = cp.circle_id
      WHERE ce.id = celebration_reactions.celebration_event_id
        AND cm.user_id = auth.uid()
    )
  );
```

### iOS Implementation

**New Models** (`Core/Models.swift`):

```swift
enum CelebrationType: String, Codable {
    case streakMilestone = "streak_milestone"
    case levelUp = "level_up"
    case badgeUnlock = "badge_unlock"
    case questMilestone = "quest_milestone"
    case exerciseMilestone = "exercise_milestone"

    var confettiColors: [Color] {
        switch self {
        case .streakMilestone: return [.orange, .red, .yellow]
        case .levelUp: return [.purple, .blue, .pink]
        case .badgeUnlock: return [.green, .yellow, .blue]
        case .questMilestone: return [.blue, .cyan, .white]
        case .exerciseMilestone: return [.green, .mint, .cyan]
        }
    }
}

struct CelebrationEvent: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let celebrationType: CelebrationType
    let value: Int
    let badgeId: UUID?
    let shownAt: Date
    var sharedToCircle: Bool
    var sharedExternally: Bool
    var circlePostId: UUID?

    // Joined data
    var badge: Badge?
    var reactions: [CelebrationReaction]?

    var reactionCount: Int {
        reactions?.count ?? 0
    }

    var title: String {
        switch celebrationType {
        case .streakMilestone:
            return "\(value)-Day Streak!"
        case .levelUp:
            return "Level \(value)!"
        case .badgeUnlock:
            return badge?.name ?? "New Badge!"
        case .questMilestone:
            return "\(value) Quests!"
        case .exerciseMilestone:
            return "\(value) Exercises!"
        }
    }

    var subtitle: String {
        switch celebrationType {
        case .streakMilestone:
            return "You've been consistent for \(value) days. Amazing!"
        case .levelUp:
            return "You've reached a new level in your journey!"
        case .badgeUnlock:
            return badge?.description ?? "You unlocked a new achievement!"
        case .questMilestone:
            return "You've completed \(value) quests. Keep going!"
        case .exerciseMilestone:
            return "\(value) exercises completed. Your dedication shows!"
        }
    }

    var shareMessage: String {
        switch celebrationType {
        case .streakMilestone:
            return "I just hit a \(value)-day streak on MindFriend! 🔥"
        case .levelUp:
            return "Just reached Level \(value) on my wellness journey! ⭐"
        case .badgeUnlock:
            return "Unlocked the '\(badge?.name ?? "new")' badge on MindFriend! 🏆"
        case .questMilestone:
            return "Completed \(value) wellness quests! 💪"
        case .exerciseMilestone:
            return "Finished \(value) exercises on MindFriend! 🧘"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case celebrationType = "celebration_type"
        case value
        case badgeId = "badge_id"
        case shownAt = "shown_at"
        case sharedToCircle = "shared_to_circle"
        case sharedExternally = "shared_externally"
        case circlePostId = "circle_post_id"
        case badge, reactions
    }
}

struct CelebrationReaction: Identifiable, Codable {
    let id: UUID
    let celebrationEventId: UUID
    let reactorUserId: UUID
    let emoji: String
    let createdAt: Date

    var reactorName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case celebrationEventId = "celebration_event_id"
        case reactorUserId = "reactor_user_id"
        case emoji
        case createdAt = "created_at"
        case reactorName
    }
}

struct ShareCardTemplate: Codable {
    let id: UUID
    let templateType: String
    let backgroundColor: String
    let accentColor: String
    let iconName: String
    let messageTemplate: String

    enum CodingKeys: String, CodingKey {
        case id
        case templateType = "template_type"
        case backgroundColor = "background_color"
        case accentColor = "accent_color"
        case iconName = "icon_name"
        case messageTemplate = "message_template"
    }
}
```

**Service Methods** (`Networking/Services/SupabaseDataService.swift`):

```swift
// MARK: - Celebrations

func createCelebration(type: CelebrationType, value: Int, badgeId: UUID? = nil) async throws -> CelebrationEvent {
    let userId = try await getCurrentUserId()

    let event = CelebrationEvent(
        id: UUID(),
        userId: userId,
        celebrationType: type,
        value: value,
        badgeId: badgeId,
        shownAt: Date(),
        sharedToCircle: false,
        sharedExternally: false,
        circlePostId: nil,
        badge: nil,
        reactions: nil
    )

    return try await supabase
        .from("celebration_events")
        .insert(event)
        .select()
        .single()
        .execute()
        .value
}

func shareCelebrationToCircle(eventId: UUID) async throws {
    let userId = try await getCurrentUserId()

    // Get celebration event
    let event: CelebrationEvent = try await supabase
        .from("celebration_events")
        .select("*, badges(*)")
        .eq("id", eventId)
        .single()
        .execute()
        .value

    // Get user's circles
    let memberships: [CircleMember] = try await supabase
        .from("circle_members")
        .select("circle_id")
        .eq("user_id", userId)
        .eq("status", "active")
        .execute()
        .value

    // Post to each circle
    for membership in memberships {
        let post: CirclePost = try await supabase
            .from("circle_posts")
            .insert([
                "circle_id": membership.circleId.uuidString,
                "user_id": userId.uuidString,
                "post_type": "milestone",
                "mood_emoji": "🎉",
                "body_text": event.shareMessage
            ])
            .select()
            .single()
            .execute()
            .value

        // Update celebration event with first post id
        if event.circlePostId == nil {
            try await supabase
                .from("celebration_events")
                .update([
                    "shared_to_circle": true,
                    "circle_post_id": post.id.uuidString
                ])
                .eq("id", eventId)
                .execute()
        }
    }
}

func markCelebrationSharedExternally(eventId: UUID) async throws {
    try await supabase
        .from("celebration_events")
        .update(["shared_externally": true])
        .eq("id", eventId)
        .execute()
}

func addCelebrationReaction(eventId: UUID, emoji: String) async throws {
    let userId = try await getCurrentUserId()

    try await supabase
        .from("celebration_reactions")
        .upsert([
            "celebration_event_id": eventId.uuidString,
            "reactor_user_id": userId.uuidString,
            "emoji": emoji
        ])
        .execute()
}

func getCelebrationReactions(eventId: UUID) async throws -> [CelebrationReaction] {
    try await supabase
        .from("celebration_reactions")
        .select("*, profiles!reactor_user_id(display_name)")
        .eq("celebration_event_id", eventId)
        .execute()
        .value
}
```

**New Views**:

```swift
// CelebrationView.swift
struct CelebrationView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    let celebration: CelebrationEvent
    @State private var showConfetti = true
    @State private var isSharing = false
    @State private var showShareSheet = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: celebration.celebrationType.confettiColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.3)
            .ignoresSafeArea()

            // Confetti
            if showConfetti {
                ConfettiView(colors: celebration.celebrationType.confettiColors)
            }

            // Content
            VStack(spacing: 32) {
                Spacer()

                // Icon
                Image(systemName: iconForType)
                    .font(.system(size: 80))
                    .foregroundStyle(.white)
                    .padding(40)
                    .background(
                        Circle()
                            .fill(celebration.celebrationType.confettiColors.first ?? .accentColor)
                    )
                    .shadow(radius: 20)

                // Title
                VStack(spacing: 8) {
                    Text(celebration.title)
                        .font(.largeTitle.bold())

                    Text(celebration.subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // Share buttons
                VStack(spacing: 12) {
                    Button {
                        Task { await shareToCircle() }
                    } label: {
                        HStack {
                            Image(systemName: "person.2.fill")
                            Text("Share with Circle")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }
                    .disabled(celebration.sharedToCircle || isSharing)

                    Button {
                        showShareSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Externally")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.accentColor)
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Continue")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Play sound if enabled
            // SoundManager.shared.playIfEnabled(.celebration)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareCardSheet(celebration: celebration) {
                Task {
                    try? await container.supabaseDataService.markCelebrationSharedExternally(eventId: celebration.id)
                }
            }
        }
    }

    var iconForType: String {
        switch celebration.celebrationType {
        case .streakMilestone: return "flame.fill"
        case .levelUp: return "star.fill"
        case .badgeUnlock: return "trophy.fill"
        case .questMilestone: return "checkmark.seal.fill"
        case .exerciseMilestone: return "figure.mind.and.body"
        }
    }

    func shareToCircle() async {
        isSharing = true
        defer { isSharing = false }

        do {
            try await container.supabaseDataService.shareCelebrationToCircle(eventId: celebration.id)
        } catch {
            print("Share failed: \(error)")
        }
    }
}

// ConfettiView.swift
struct ConfettiView: View {
    let colors: [Color]
    @State private var particles: [ConfettiParticle] = []

    struct ConfettiParticle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        let color: Color
        let size: CGFloat
        let rotation: Double
        var opacity: Double = 1
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .position(x: particle.x, y: particle.y)
                        .rotationEffect(.degrees(particle.rotation))
                        .opacity(particle.opacity)
                }
            }
            .onAppear {
                createParticles(in: geo.size)
                animateParticles()
            }
        }
        .allowsHitTesting(false)
    }

    func createParticles(in size: CGSize) {
        particles = (0..<100).map { _ in
            ConfettiParticle(
                x: CGFloat.random(in: 0...size.width),
                y: -20,
                color: colors.randomElement() ?? .accentColor,
                size: CGFloat.random(in: 6...12),
                rotation: Double.random(in: 0...360)
            )
        }
    }

    func animateParticles() {
        withAnimation(.easeOut(duration: 3)) {
            for i in particles.indices {
                particles[i].y = UIScreen.main.bounds.height + 50
                particles[i].x += CGFloat.random(in: -100...100)
                particles[i].opacity = 0
            }
        }
    }
}

// ShareCardSheet.swift
struct ShareCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let celebration: CelebrationEvent
    let onShare: () -> Void

    @State private var generatedImage: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Preview
                ShareCardPreview(celebration: celebration)
                    .padding()

                // Share options
                if let image = generatedImage {
                    ShareLink(
                        item: Image(uiImage: image),
                        preview: SharePreview(celebration.shareMessage, image: Image(uiImage: image))
                    ) {
                        Label("Share Image", systemImage: "photo")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                }

                ShareLink(item: celebration.shareMessage) {
                    Label("Share Text", systemImage: "text.bubble")
                        .font(.subheadline)
                        .foregroundStyle(.accentColor)
                }
            }
            .padding()
            .navigationTitle("Share Achievement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onShare()
                        dismiss()
                    }
                }
            }
            .task {
                await generateImage()
            }
        }
    }

    func generateImage() async {
        // Generate shareable image from ShareCardPreview
        let renderer = ImageRenderer(content: ShareCardPreview(celebration: celebration))
        renderer.scale = 3.0
        generatedImage = renderer.uiImage
    }
}

// ShareCardPreview.swift
struct ShareCardPreview: View {
    let celebration: CelebrationEvent

    var body: some View {
        VStack(spacing: 16) {
            // Icon
            Image(systemName: iconForType)
                .font(.system(size: 50))
                .foregroundStyle(.white)
                .padding(24)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: celebration.celebrationType.confettiColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )

            // Content
            Text(celebration.title)
                .font(.title.bold())

            Text(celebration.shareMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Branding
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.accentColor)
                Text("MindFriend")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(radius: 10)
        .frame(width: 300, height: 400)
    }

    var iconForType: String {
        switch celebration.celebrationType {
        case .streakMilestone: return "flame.fill"
        case .levelUp: return "star.fill"
        case .badgeUnlock: return "trophy.fill"
        case .questMilestone: return "checkmark.seal.fill"
        case .exerciseMilestone: return "figure.mind.and.body"
        }
    }
}

// CelebrationReactionsBar.swift (for circle feed)
struct CelebrationReactionsBar: View {
    let post: CirclePost
    @EnvironmentObject var container: DependencyContainer
    @State private var reactions: [String: Int] = [:]
    @State private var userReaction: String?

    let availableReactions = ["🎉", "👏", "🔥", "💪", "❤️", "⭐"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(availableReactions, id: \.self) { emoji in
                Button {
                    react(with: emoji)
                } label: {
                    HStack(spacing: 2) {
                        Text(emoji)
                        if let count = reactions[emoji], count > 0 {
                            Text("\(count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(userReaction == emoji ? Color.accentColor.opacity(0.2) : Color(.systemGray6))
                    .cornerRadius(12)
                }
            }
        }
        .task { await loadReactions() }
    }

    func loadReactions() async {
        // Load reactions from post
    }

    func react(with emoji: String) {
        // Toggle reaction
        withAnimation(.spring(response: 0.3)) {
            if userReaction == emoji {
                userReaction = nil
                reactions[emoji] = (reactions[emoji] ?? 1) - 1
            } else {
                if let previous = userReaction {
                    reactions[previous] = (reactions[previous] ?? 1) - 1
                }
                userReaction = emoji
                reactions[emoji] = (reactions[emoji] ?? 0) + 1
            }
        }

        // Save to backend
        Task {
            try? await container.supabaseDataService.addReaction(to: post.id, emoji: ReactionEmoji(rawValue: emoji) ?? .party)
        }
    }
}
```

### Backend Implementation

**Trigger celebrations on milestones** (update relevant functions):

```typescript
// In quest completion handler
async function checkAndTriggerCelebrations(
  supabase: SupabaseClient,
  userId: string,
  questCount: number,
  streak: number,
) {
  const streakMilestones = [7, 14, 30, 60, 100, 365];
  const questMilestones = [10, 50, 100, 500];

  // Check streak milestones
  if (streakMilestones.includes(streak)) {
    await supabase.from("celebration_events").insert({
      user_id: userId,
      celebration_type: "streak_milestone",
      value: streak,
    });

    // Notify circle members
    await notifyCircleOfMilestone(supabase, userId, "streak", streak);
  }

  // Check quest milestones
  if (questMilestones.includes(questCount)) {
    await supabase.from("celebration_events").insert({
      user_id: userId,
      celebration_type: "quest_milestone",
      value: questCount,
    });
  }
}

async function notifyCircleOfMilestone(
  supabase: SupabaseClient,
  userId: string,
  type: string,
  value: number,
) {
  const { data: user } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", userId)
    .single();

  const { data: memberships } = await supabase
    .from("circle_members")
    .select("circle_id, circles(name)")
    .eq("user_id", userId)
    .eq("status", "active");

  for (const membership of memberships || []) {
    // Get other members to notify
    const { data: otherMembers } = await supabase
      .from("circle_members")
      .select("user_id")
      .eq("circle_id", membership.circle_id)
      .neq("user_id", userId)
      .eq("status", "active");

    for (const member of otherMembers || []) {
      await supabase.functions.invoke("send-notification", {
        body: {
          type: "milestone_celebration",
          recipientId: member.user_id,
          data: {
            userName: user?.display_name || "A friend",
            milestoneType: type,
            milestoneValue: value,
          },
        },
      });
    }
  }
}
```

---

## UI/UX

### Celebration Modal

```
┌─────────────────────────────────────────┐
│                                         │
│           🎊 🎉 🎊 🎉 🎊                │
│                                         │
│              ┌─────┐                    │
│              │ 🔥  │                    │
│              └─────┘                    │
│                                         │
│         30-Day Streak!                  │
│                                         │
│   You've been consistent for 30 days.  │
│           Amazing dedication!           │
│                                         │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │    👥 Share with Circle         │   │
│   └─────────────────────────────────┘   │
│                                         │
│         📤 Share Externally             │
│                                         │
│             Continue                    │
│                                         │
└─────────────────────────────────────────┘
```

### Share Card Preview

```
┌─────────────────────────────────────────┐
│                                         │
│              ┌─────┐                    │
│              │ 🔥  │                    │
│              └─────┘                    │
│                                         │
│         30-Day Streak!                  │
│                                         │
│   I just hit a 30-day streak on        │
│   MindFriend! 🔥                        │
│                                         │
│            ❤️ MindFriend                │
│                                         │
└─────────────────────────────────────────┘
```

### Circle Feed Milestone Post

```
┌─────────────────────────────────────────┐
│ 🔥 Sarah just hit 30 days!              │
│ Keep it up!                             │
│                                         │
│ 2h ago                                  │
│                                         │
│ [🎉 5] [👏 3] [🔥 2] [💪 1] + react     │
└─────────────────────────────────────────┘
```

---

## Verification

### Manual Testing

1. **Streak Celebration:**
   - Complete quest to hit 7-day streak
   - Verify celebration modal appears
   - Verify confetti animation plays
   - Verify haptic feedback

2. **Share to Circle:**
   - Tap "Share with Circle"
   - Check all circles for milestone post
   - Verify post appears with reactions

3. **External Share:**
   - Tap "Share Externally"
   - Verify share card generates
   - Verify share sheet appears
   - Test sharing to Messages/Notes

4. **Circle Reactions:**
   - View friend's milestone in circle
   - Add reaction
   - Verify reaction appears
   - Verify original poster sees count

---

## Dependencies

- Level/XP system working
- Badge system working
- Circle posts working
- Push notifications working

---

## Risks & Mitigations

| Risk                       | Likelihood | Impact | Mitigation                            |
| -------------------------- | ---------- | ------ | ------------------------------------- |
| Over-celebration fatigue   | Medium     | Medium | Only celebrate significant milestones |
| Share card generation slow | Low        | Low    | Pre-generate templates, async load    |
| Social pressure to share   | Low        | Medium | All sharing is optional               |

---

## Implementation Estimate

| Task                        | Effort       |
| --------------------------- | ------------ |
| Database migration          | 1 hour       |
| iOS Models                  | 1 hour       |
| Celebration service methods | 2 hours      |
| CelebrationView + confetti  | 4 hours      |
| Share card generation       | 3 hours      |
| Circle integration          | 2 hours      |
| Backend triggers            | 2 hours      |
| Testing                     | 2 hours      |
| **Total**                   | **17 hours** |

---

## Success Metrics

| Metric                             | Current | Target              |
| ---------------------------------- | ------- | ------------------- |
| Celebration share rate (circle)    | N/A     | 30%                 |
| Celebration share rate (external)  | N/A     | 10%                 |
| Circle reaction rate on milestones | N/A     | 50%                 |
| Retention of users who share       | N/A     | +25% vs non-sharers |
| New user signups from shares       | N/A     | Track attribution   |
