# F010: Wellness Time Capsule

## Overview

### Summary

Digital time capsule feature that allows users to record messages, reflections, and goals for their future selves, delivered at scheduled future dates with personalized AI commentary on their journey.

### Business Value

- Unique emotional engagement feature differentiating from competitors
- Creates anticipated future touchpoints driving long-term retention
- Premium feature with emotional value justifying subscription

### User Benefit

- Powerful self-reflection through messages from past self
- Celebration of growth and progress over time
- Emotional connection to wellness journey milestones

### Dependencies

- F004: Companion Memory Enhancement (for AI journey commentary)
- F006: Progress Narrative (for growth analysis)

---

## Requirements

### Functional Requirements

| ID     | Requirement                                                          | Priority    |
| ------ | -------------------------------------------------------------------- | ----------- |
| FR-001 | Create text, audio, and photo time capsules                          | Must Have   |
| FR-002 | Schedule delivery for 1 week to 5 years in the future                | Must Have   |
| FR-003 | AI-generated "letter from your companion" comparing past and present | Must Have   |
| FR-004 | Push notification when capsule is ready to open                      | Must Have   |
| FR-005 | "Unopened capsule" indicator showing pending deliveries              | Must Have   |
| FR-006 | Optional prompt templates for guided capsule creation                | Should Have |
| FR-007 | Capsule themes (milestone, goal, gratitude, advice, encouragement)   | Should Have |
| FR-008 | Premium: video capsules and unlimited storage                        | Could Have  |
| FR-009 | Anniversary capsules (yearly wellness snapshots)                     | Should Have |
| FR-010 | Share opened capsule with circles (privacy-filtered)                 | Could Have  |

### Non-Functional Requirements

| ID      | Requirement                  | Target                     |
| ------- | ---------------------------- | -------------------------- |
| NFR-001 | Capsule creation time (text) | < 2s save                  |
| NFR-002 | Audio/photo upload           | < 30s for 10MB             |
| NFR-003 | Capsule content encryption   | AES-256 at rest            |
| NFR-004 | Delivery time accuracy       | Within 1 hour of scheduled |

### Acceptance Criteria

```gherkin
Feature: Wellness Time Capsule

Scenario: Create text time capsule
  Given user is on the time capsule creation screen
  When user writes a message "Keep going, future me!"
  And user selects delivery date 1 year from now
  And user selects theme "encouragement"
  And user taps "Seal Capsule"
  Then capsule should be saved with encrypted content
  And capsule should appear in "Sealed" capsules list
  And confirmation animation should play

Scenario: Receive time capsule notification
  Given user has a capsule scheduled for today
  When the delivery time arrives
  Then push notification should be sent
  And capsule should move to "Ready to Open" section
  And home screen should show "1 capsule ready" indicator

Scenario: Open time capsule with AI commentary
  Given user has a ready-to-open capsule from 1 year ago
  When user opens the capsule
  Then original message should display
  And AI companion should generate journey reflection
  And comparison of then vs now metrics should show
  And celebratory animation should play

Scenario: Audio time capsule creation
  Given user is creating an audio capsule
  When user records 2-minute voice message
  And user selects delivery date
  And user seals the capsule
  Then audio should be encrypted and uploaded
  And transcription should be generated for search
```

---

## Technical Design

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    iOS Application                       │
├─────────────────────────────────────────────────────────┤
│  TimeCapsuleService                                     │
│  ├── Capsule creation (text/audio/photo)                │
│  ├── Local encryption before upload                     │
│  ├── Delivery notification handling                     │
│  └── AI commentary request                              │
├─────────────────────────────────────────────────────────┤
│  TimeCapsuleViews                                       │
│  ├── CreateCapsuleFlow (multi-step)                     │
│  ├── CapsuleListView (sealed/ready/opened)              │
│  ├── OpenCapsuleExperience (cinematic reveal)           │
│  └── CapsuleDetailView (opened capsule)                 │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│              Supabase Edge Functions                     │
├─────────────────────────────────────────────────────────┤
│  create-capsule                                         │
│  ├── Validate content size limits                       │
│  ├── Store encrypted content                            │
│  └── Schedule delivery notification                     │
├─────────────────────────────────────────────────────────┤
│  deliver-capsule (cron)                                 │
│  ├── Check for due capsules                             │
│  ├── Generate AI companion letter                       │
│  └── Send push notification                             │
├─────────────────────────────────────────────────────────┤
│  open-capsule                                           │
│  ├── Decrypt content                                    │
│  ├── Generate journey comparison                        │
│  └── Mark as opened                                     │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                  PostgreSQL + Storage                    │
├─────────────────────────────────────────────────────────┤
│  time_capsules │ capsule_media │ capsule_snapshots      │
└─────────────────────────────────────────────────────────┘
```

### Data Models

#### Database Schema

```sql
-- Time capsules
CREATE TABLE time_capsules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT,
    content_encrypted TEXT NOT NULL,
    content_type TEXT NOT NULL CHECK (content_type IN ('text', 'audio', 'photo', 'mixed')),
    theme TEXT CHECK (theme IN ('milestone', 'goal', 'gratitude', 'advice', 'encouragement', 'anniversary', 'custom')),

    -- Scheduling
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deliver_at TIMESTAMPTZ NOT NULL,
    delivered_at TIMESTAMPTZ,
    opened_at TIMESTAMPTZ,

    -- Status
    status TEXT NOT NULL DEFAULT 'sealed' CHECK (status IN ('sealed', 'delivered', 'opened')),

    -- AI Commentary
    companion_letter TEXT,
    companion_letter_generated_at TIMESTAMPTZ,

    -- Metadata
    word_count INTEGER,
    media_count INTEGER DEFAULT 0,
    encryption_key_id TEXT NOT NULL,

    -- Snapshot of metrics at creation time
    metrics_snapshot JSONB,

    CONSTRAINT valid_delivery_date CHECK (deliver_at > created_at)
);

-- Media attachments (audio, photos)
CREATE TABLE capsule_media (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    capsule_id UUID NOT NULL REFERENCES time_capsules(id) ON DELETE CASCADE,
    media_type TEXT NOT NULL CHECK (media_type IN ('audio', 'photo', 'video')),
    storage_path TEXT NOT NULL,
    file_size_bytes INTEGER NOT NULL,
    duration_seconds INTEGER, -- For audio/video
    transcription TEXT, -- For audio (searchable)
    thumbnail_path TEXT, -- For video/photo
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Prompt templates for guided creation
CREATE TABLE capsule_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    theme TEXT NOT NULL,
    title TEXT NOT NULL,
    prompts JSONB NOT NULL, -- Array of prompt strings
    suggested_duration TEXT, -- e.g., "6 months", "1 year"
    is_premium BOOLEAN NOT NULL DEFAULT false,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Wellness snapshot at capsule creation
CREATE TABLE capsule_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    capsule_id UUID NOT NULL REFERENCES time_capsules(id) ON DELETE CASCADE,
    current_streak INTEGER NOT NULL DEFAULT 0,
    total_quests_completed INTEGER NOT NULL DEFAULT 0,
    total_exercises INTEGER NOT NULL DEFAULT 0,
    total_moods_logged INTEGER NOT NULL DEFAULT 0,
    average_mood_30d DECIMAL(3,2),
    badges_earned INTEGER NOT NULL DEFAULT 0,
    level INTEGER NOT NULL DEFAULT 1,
    total_xp INTEGER NOT NULL DEFAULT 0,
    top_emotions TEXT[], -- Most common in past 30 days
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(capsule_id)
);

-- Indexes
CREATE INDEX idx_time_capsules_user ON time_capsules(user_id);
CREATE INDEX idx_time_capsules_deliver ON time_capsules(deliver_at) WHERE status = 'sealed';
CREATE INDEX idx_time_capsules_status ON time_capsules(user_id, status);
CREATE INDEX idx_capsule_media_capsule ON capsule_media(capsule_id);

-- RLS Policies
ALTER TABLE time_capsules ENABLE ROW LEVEL SECURITY;
ALTER TABLE capsule_media ENABLE ROW LEVEL SECURITY;
ALTER TABLE capsule_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE capsule_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own capsules" ON time_capsules
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own capsule media" ON capsule_media
    FOR ALL USING (
        capsule_id IN (
            SELECT id FROM time_capsules WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Anyone can view templates" ON capsule_templates
    FOR SELECT USING (true);

CREATE POLICY "Users can view own snapshots" ON capsule_snapshots
    FOR SELECT USING (
        capsule_id IN (
            SELECT id FROM time_capsules WHERE user_id = auth.uid()
        )
    );
```

#### Capsule Template Seed Data

```sql
INSERT INTO capsule_templates (theme, title, prompts, suggested_duration, is_premium, sort_order) VALUES
('encouragement', 'Letter to Future Me',
 '["What are you proud of right now?", "What challenge are you facing?", "What advice would you give yourself?", "What are you grateful for today?"]',
 '1 year', false, 1),

('goal', 'Goals & Dreams',
 '["What goal are you working toward?", "Why is this goal important to you?", "What steps are you taking?", "How will you feel when you achieve it?"]',
 '6 months', false, 2),

('milestone', 'Celebrate This Moment',
 '["What milestone are you celebrating?", "How did you achieve this?", "Who helped you along the way?", "What''s next for you?"]',
 '1 year', false, 3),

('gratitude', 'Gratitude Capsule',
 '["List 5 things you''re grateful for right now", "Who has positively impacted your life recently?", "What simple pleasure brought you joy today?"]',
 '6 months', false, 4),

('advice', 'Wisdom for Tomorrow',
 '["What lesson have you learned recently?", "What would you tell someone going through what you''ve been through?", "What truth do you want to remember?"]',
 '1 year', true, 5),

('anniversary', 'Annual Wellness Snapshot',
 '["How would you describe this past year?", "What was your biggest challenge?", "What was your greatest joy?", "What do you hope for next year?"]',
 '1 year', false, 6);
```

#### Swift Models

```swift
// MARK: - Time Capsule Models

struct TimeCapsule: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var title: String?
    let contentEncrypted: String
    let contentType: CapsuleContentType
    let theme: CapsuleTheme?
    let createdAt: Date
    let deliverAt: Date
    var deliveredAt: Date?
    var openedAt: Date?
    var status: CapsuleStatus
    var companionLetter: String?
    let wordCount: Int?
    let mediaCount: Int
    let encryptionKeyId: String

    var isReady: Bool {
        status == .delivered || (status == .sealed && Date() >= deliverAt)
    }

    var daysUntilDelivery: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: deliverAt).day ?? 0
    }

    var timeAgoCreated: String {
        RelativeDateTimeFormatter().localizedString(for: createdAt, relativeTo: Date())
    }
}

enum CapsuleContentType: String, Codable {
    case text
    case audio
    case photo
    case mixed
}

enum CapsuleTheme: String, Codable, CaseIterable {
    case milestone
    case goal
    case gratitude
    case advice
    case encouragement
    case anniversary
    case custom

    var displayName: String {
        switch self {
        case .milestone: return "Celebrate a Milestone"
        case .goal: return "Goals & Dreams"
        case .gratitude: return "Gratitude Capsule"
        case .advice: return "Wisdom for Tomorrow"
        case .encouragement: return "Letter to Future Me"
        case .anniversary: return "Annual Snapshot"
        case .custom: return "Custom Message"
        }
    }

    var iconName: String {
        switch self {
        case .milestone: return "flag.fill"
        case .goal: return "target"
        case .gratitude: return "heart.fill"
        case .advice: return "lightbulb.fill"
        case .encouragement: return "hand.wave.fill"
        case .anniversary: return "calendar"
        case .custom: return "envelope.fill"
        }
    }

    var color: Color {
        switch self {
        case .milestone: return .yellow
        case .goal: return .blue
        case .gratitude: return .pink
        case .advice: return .purple
        case .encouragement: return .green
        case .anniversary: return .orange
        case .custom: return .gray
        }
    }
}

enum CapsuleStatus: String, Codable {
    case sealed
    case delivered
    case opened
}

struct CapsuleMedia: Codable, Identifiable {
    let id: UUID
    let capsuleId: UUID
    let mediaType: CapsuleMediaType
    let storagePath: String
    let fileSizeBytes: Int
    let durationSeconds: Int?
    let transcription: String?
    let thumbnailPath: String?
    let createdAt: Date
}

enum CapsuleMediaType: String, Codable {
    case audio
    case photo
    case video
}

struct CapsuleTemplate: Codable, Identifiable {
    let id: UUID
    let theme: CapsuleTheme
    let title: String
    let prompts: [String]
    let suggestedDuration: String
    let isPremium: Bool
    let sortOrder: Int
}

struct CapsuleSnapshot: Codable {
    let id: UUID
    let capsuleId: UUID
    let currentStreak: Int
    let totalQuestsCompleted: Int
    let totalExercises: Int
    let totalMoodsLogged: Int
    let averageMood30d: Double?
    let badgesEarned: Int
    let level: Int
    let totalXP: Int
    let topEmotions: [String]?
    let createdAt: Date
}

// MARK: - Journey Comparison

struct JourneyComparison {
    let thenSnapshot: CapsuleSnapshot
    let nowSnapshot: CapsuleSnapshot

    var streakGrowth: Int { nowSnapshot.currentStreak - thenSnapshot.currentStreak }
    var questsCompleted: Int { nowSnapshot.totalQuestsCompleted - thenSnapshot.totalQuestsCompleted }
    var exercisesDone: Int { nowSnapshot.totalExercises - thenSnapshot.totalExercises }
    var levelGrowth: Int { nowSnapshot.level - thenSnapshot.level }
    var xpGained: Int { nowSnapshot.totalXP - thenSnapshot.totalXP }
    var badgesEarned: Int { nowSnapshot.badgesEarned - thenSnapshot.badgesEarned }

    var moodTrend: MoodTrend {
        guard let thenMood = thenSnapshot.averageMood30d,
              let nowMood = nowSnapshot.averageMood30d else {
            return .unchanged
        }
        let diff = nowMood - thenMood
        if diff > 0.5 { return .improved }
        if diff < -0.5 { return .declined }
        return .unchanged
    }

    enum MoodTrend {
        case improved, declined, unchanged
    }
}

// MARK: - Creation Flow

struct CapsuleCreationData {
    var theme: CapsuleTheme = .encouragement
    var title: String = ""
    var textContent: String = ""
    var audioRecording: Data?
    var photos: [UIImage] = []
    var deliverAt: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date())!
    var selectedPrompts: [String] = []

    var isValid: Bool {
        !textContent.isEmpty || audioRecording != nil || !photos.isEmpty
    }

    var contentType: CapsuleContentType {
        let hasText = !textContent.isEmpty
        let hasAudio = audioRecording != nil
        let hasPhotos = !photos.isEmpty

        if (hasText && hasAudio) || (hasText && hasPhotos) || (hasAudio && hasPhotos) {
            return .mixed
        }
        if hasAudio { return .audio }
        if hasPhotos { return .photo }
        return .text
    }
}
```

### API Contracts

#### Create Capsule

```
POST /functions/v1/create-capsule

Request:
{
  "title": "Letter to Future Me",
  "theme": "encouragement",
  "contentEncrypted": "base64_encrypted_content",
  "contentType": "text",
  "deliverAt": "2025-01-15T09:00:00Z",
  "encryptionKeyId": "key_123",
  "wordCount": 250
}

Response 201:
{
  "id": "uuid",
  "status": "sealed",
  "deliverAt": "2025-01-15T09:00:00Z",
  "daysUntilDelivery": 365,
  "snapshot": {
    "currentStreak": 14,
    "level": 5,
    "totalXP": 1250
  }
}
```

#### Upload Capsule Media

```
POST /storage/v1/object/capsule-media/{capsuleId}/{filename}
Content-Type: audio/m4a or image/jpeg

Response 200:
{
  "storagePath": "capsule-media/uuid/recording.m4a",
  "fileSize": 1024000,
  "transcription": "Keep going future me..." // For audio
}
```

#### Open Capsule

```
POST /functions/v1/open-capsule

Request:
{
  "capsuleId": "uuid"
}

Response 200:
{
  "capsule": {
    "id": "uuid",
    "contentDecrypted": "Keep going, future me!...",
    "createdAt": "2024-01-15T10:00:00Z",
    "theme": "encouragement",
    "media": [...]
  },
  "companionLetter": "Dear [Name],\n\nA year ago, you wrote this message during a time of...",
  "journeyComparison": {
    "thenSnapshot": {...},
    "nowSnapshot": {...},
    "highlights": [
      "You've completed 156 more quests",
      "Your streak grew from 14 to 89 days",
      "You earned 12 new badges"
    ]
  }
}
```

#### Get Capsules

```
GET /rest/v1/time_capsules?user_id=eq.{userId}&order=deliver_at

Response 200:
[
  {
    "id": "uuid",
    "title": "Letter to Future Me",
    "status": "sealed",
    "deliver_at": "2025-01-15T09:00:00Z",
    "created_at": "2024-01-15T10:00:00Z",
    "theme": "encouragement",
    "content_type": "text"
  }
]
```

---

## Implementation Details

### Step-by-Step Approach

1. **Database Setup**
   - Create migrations for capsule tables
   - Seed template data
   - Configure Supabase Storage bucket

2. **Encryption Layer**
   - Client-side AES-256 encryption
   - Key derivation from user password + salt
   - Key rotation support

3. **Capsule Creation Flow**
   - Multi-step wizard UI
   - Theme selection with templates
   - Content input (text/audio/photo)
   - Date picker with presets
   - Snapshot capture on seal

4. **Delivery System**
   - Cron job checking for due capsules
   - AI companion letter generation
   - Push notification delivery
   - Status update to 'delivered'

5. **Opening Experience**
   - Cinematic reveal animation
   - Content decryption
   - Journey comparison display
   - AI letter presentation

### File Structure

```
apps/ios/MindFriendApp/
├── Features/
│   └── TimeCapsule/
│       ├── TimeCapsuleService.swift
│       ├── CapsuleEncryption.swift
│       ├── Views/
│       │   ├── TimeCapsuleListView.swift
│       │   ├── CreateCapsuleFlow/
│       │   │   ├── CapsuleThemeStep.swift
│       │   │   ├── CapsuleContentStep.swift
│       │   │   ├── CapsuleDateStep.swift
│       │   │   └── CapsuleSealStep.swift
│       │   ├── OpenCapsuleView.swift
│       │   ├── CapsuleDetailView.swift
│       │   └── JourneyComparisonView.swift
│       └── Components/
│           ├── CapsuleCard.swift
│           ├── AudioRecorderView.swift
│           └── SealAnimation.swift
│
supabase/
├── functions/
│   ├── create-capsule/
│   ├── deliver-capsule/  # Cron triggered
│   ├── open-capsule/
│   └── generate-companion-letter/
├── migrations/
│   └── YYYYMMDD_time_capsules.sql
```

### Key Algorithms

#### Client-Side Encryption (Swift)

```swift
import CryptoKit

class CapsuleEncryption {

    /// Encrypts content with AES-256-GCM
    func encrypt(content: String, userKey: SymmetricKey) throws -> (encrypted: String, keyId: String) {
        let data = Data(content.utf8)

        // Generate per-capsule key
        let capsuleKey = SymmetricKey(size: .bits256)
        let nonce = AES.GCM.Nonce()

        // Encrypt content with capsule key
        let sealed = try AES.GCM.seal(data, using: capsuleKey, nonce: nonce)
        let encryptedContent = sealed.combined!.base64EncodedString()

        // Encrypt capsule key with user key
        let keyData = capsuleKey.withUnsafeBytes { Data($0) }
        let keyNonce = AES.GCM.Nonce()
        let sealedKey = try AES.GCM.seal(keyData, using: userKey, nonce: keyNonce)
        let encryptedKey = sealedKey.combined!.base64EncodedString()

        // Store encrypted key reference (would go to secure storage)
        let keyId = storeEncryptedKey(encryptedKey)

        return (encryptedContent, keyId)
    }

    /// Decrypts content
    func decrypt(encrypted: String, keyId: String, userKey: SymmetricKey) throws -> String {
        // Retrieve and decrypt capsule key
        let encryptedKey = retrieveEncryptedKey(keyId)
        let keyData = try AES.GCM.open(
            try AES.GCM.SealedBox(combined: Data(base64Encoded: encryptedKey)!),
            using: userKey
        )
        let capsuleKey = SymmetricKey(data: keyData)

        // Decrypt content
        let sealedBox = try AES.GCM.SealedBox(combined: Data(base64Encoded: encrypted)!)
        let decrypted = try AES.GCM.open(sealedBox, using: capsuleKey)

        return String(data: decrypted, encoding: .utf8)!
    }

    /// Derives user key from password
    func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(password.utf8)),
            salt: salt,
            info: Data("capsule-encryption".utf8),
            outputByteCount: 32
        )
        return key
    }
}
```

#### AI Companion Letter Generation (TypeScript)

```typescript
async function generateCompanionLetter(
  supabase: SupabaseClient,
  userId: string,
  capsule: TimeCapsule,
  snapshot: CapsuleSnapshot,
): Promise<string> {
  // Get current user metrics
  const nowSnapshot = await captureCurrentSnapshot(supabase, userId);

  // Get user profile for personalization
  const { data: profile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", userId)
    .single();

  // Get companion personality
  const { data: personality } = await supabase
    .from("personality_traits")
    .select("traits")
    .eq("user_id", userId)
    .single();

  // Calculate journey highlights
  const highlights = calculateHighlights(snapshot, nowSnapshot);

  const prompt = `You are the user's wellness companion writing a heartfelt letter to accompany
a time capsule they created for themselves.

Time since creation: ${formatTimeDiff(capsule.createdAt, new Date())}
Theme: ${capsule.theme}
User name: ${profile?.display_name || "friend"}

THEIR ORIGINAL MESSAGE:
${await decryptContent(capsule.contentEncrypted, capsule.encryptionKeyId)}

THEIR JOURNEY SINCE THEN:
- Streak then: ${snapshot.currentStreak} → Now: ${nowSnapshot.currentStreak}
- Quests completed: +${nowSnapshot.totalQuestsCompleted - snapshot.totalQuestsCompleted}
- Exercises done: +${nowSnapshot.totalExercises - snapshot.totalExercises}
- Level: ${snapshot.level} → ${nowSnapshot.level}
- Badges earned: +${nowSnapshot.badgesEarned - snapshot.badgesEarned}
${
  snapshot.averageMood30d && nowSnapshot.averageMood30d
    ? `- Mood trend: ${snapshot.averageMood30d.toFixed(1)} → ${nowSnapshot.averageMood30d.toFixed(1)}`
    : ""
}

KEY HIGHLIGHTS:
${highlights.map((h) => `- ${h}`).join("\n")}

Write a warm, personal letter (200-300 words) that:
1. Acknowledges what they were going through when they wrote this
2. Celebrates their growth and progress
3. Reflects on how far they've come
4. Ends with encouragement for their continued journey

Personality style: ${personality?.traits?.style || "warm and supportive"}
Tone: Warm, celebratory, but not overly effusive. Be genuine.`;

  const response = await callAI(prompt);
  return response;
}

function calculateHighlights(
  then: CapsuleSnapshot,
  now: CapsuleSnapshot,
): string[] {
  const highlights: string[] = [];

  const questsDiff = now.totalQuestsCompleted - then.totalQuestsCompleted;
  if (questsDiff >= 100) {
    highlights.push(`Completed an incredible ${questsDiff} quests!`);
  } else if (questsDiff >= 30) {
    highlights.push(`Completed ${questsDiff} quests`);
  }

  const streakGrowth = now.currentStreak - then.currentStreak;
  if (streakGrowth >= 30) {
    highlights.push(
      `Streak grew from ${then.currentStreak} to ${now.currentStreak} days`,
    );
  }

  const levelGrowth = now.level - then.level;
  if (levelGrowth >= 5) {
    highlights.push(`Leveled up ${levelGrowth} times`);
  }

  const badgesDiff = now.badgesEarned - then.badgesEarned;
  if (badgesDiff >= 5) {
    highlights.push(`Earned ${badgesDiff} new badges`);
  }

  return highlights;
}
```

#### Capsule Delivery Cron (TypeScript)

```typescript
// Runs every hour
Deno.cron("deliver-capsules", "0 * * * *", async () => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Find capsules due for delivery
  const { data: dueCapsules } = await supabase
    .from("time_capsules")
    .select("*, capsule_snapshots(*)")
    .eq("status", "sealed")
    .lte("deliver_at", new Date().toISOString())
    .limit(100);

  for (const capsule of dueCapsules || []) {
    try {
      // Generate companion letter
      const letter = await generateCompanionLetter(
        supabase,
        capsule.user_id,
        capsule,
        capsule.capsule_snapshots[0],
      );

      // Update capsule status
      await supabase
        .from("time_capsules")
        .update({
          status: "delivered",
          delivered_at: new Date().toISOString(),
          companion_letter: letter,
          companion_letter_generated_at: new Date().toISOString(),
        })
        .eq("id", capsule.id);

      // Send push notification
      await supabase.functions.invoke("send-notification", {
        body: {
          userId: capsule.user_id,
          title: "💌 Time Capsule Ready",
          body: capsule.title
            ? `Your capsule "${capsule.title}" is ready to open!`
            : "A message from your past self awaits...",
          data: {
            type: "capsule_ready",
            capsuleId: capsule.id,
          },
        },
      });
    } catch (error) {
      console.error(`Failed to deliver capsule ${capsule.id}:`, error);
    }
  }
});
```

---

## Dependencies

### Internal Dependencies

- **F004 Companion Memory**: For personalized AI letter generation
- **F006 Progress Narrative**: For growth analysis integration
- **Push notification system**: For delivery alerts

### External Dependencies

- Supabase Storage for media files
- AI provider for companion letter generation

### Infrastructure Requirements

- Supabase Storage bucket: `capsule-media`
- Cron job for delivery checking (hourly)
- Encryption key storage system

---

## Edge Cases & Error Handling

| Scenario                                     | Handling                                        |
| -------------------------------------------- | ----------------------------------------------- |
| User deletes account before capsule delivery | Cascade delete capsules and media               |
| Encryption key lost                          | Display recovery options; accept permanent loss |
| Very old capsule (5+ years)                  | Still deliver; AI adapts letter accordingly     |
| Media upload fails mid-creation              | Allow save without media; retry upload later    |
| AI letter generation fails                   | Use template fallback letter                    |
| User opens capsule early (before delivery)   | Prevent; only 'delivered' status allows open    |
| Multiple capsules due same day               | Deliver all; batch notifications                |
| Capsule contains only prompts (no response)  | Prevent sealing empty capsule                   |
| Audio transcription fails                    | Allow capsule without searchable transcript     |
| Large audio file (>10 min)                   | Enforce limit; suggest splitting                |

---

## Testing Requirements

### Unit Tests

```swift
// TimeCapsuleServiceTests.swift

func testEncryptDecryptRoundtrip() throws {
    let encryption = CapsuleEncryption()
    let content = "Hello future me!"
    let password = "testpassword123"
    let salt = Data(repeating: 0, count: 32)

    let userKey = encryption.deriveKey(password: password, salt: salt)
    let (encrypted, keyId) = try encryption.encrypt(content: content, userKey: userKey)
    let decrypted = try encryption.decrypt(encrypted: encrypted, keyId: keyId, userKey: userKey)

    XCTAssertEqual(content, decrypted)
}

func testCapsuleValidation() {
    var data = CapsuleCreationData()
    XCTAssertFalse(data.isValid)

    data.textContent = "Hello future me!"
    XCTAssertTrue(data.isValid)
}

func testContentTypeDetection() {
    var data = CapsuleCreationData()

    data.textContent = "Hello"
    XCTAssertEqual(data.contentType, .text)

    data.audioRecording = Data()
    XCTAssertEqual(data.contentType, .mixed)

    data.textContent = ""
    XCTAssertEqual(data.contentType, .audio)
}

func testJourneyComparison() {
    let then = CapsuleSnapshot(
        id: UUID(), capsuleId: UUID(),
        currentStreak: 14, totalQuestsCompleted: 50,
        totalExercises: 20, totalMoodsLogged: 100,
        averageMood30d: 3.5, badgesEarned: 5,
        level: 3, totalXP: 500, topEmotions: nil,
        createdAt: Date()
    )

    let now = CapsuleSnapshot(
        id: UUID(), capsuleId: UUID(),
        currentStreak: 89, totalQuestsCompleted: 200,
        totalExercises: 100, totalMoodsLogged: 450,
        averageMood30d: 4.2, badgesEarned: 25,
        level: 12, totalXP: 3500, topEmotions: nil,
        createdAt: Date()
    )

    let comparison = JourneyComparison(thenSnapshot: then, nowSnapshot: now)

    XCTAssertEqual(comparison.streakGrowth, 75)
    XCTAssertEqual(comparison.questsCompleted, 150)
    XCTAssertEqual(comparison.moodTrend, .improved)
}
```

### Integration Tests

```typescript
// supabase/functions/deliver-capsule/test.ts

Deno.test("capsule delivered on due date", async () => {
  const userId = await createTestUser();
  const capsuleId = await createTestCapsule(userId, {
    deliverAt: new Date(Date.now() - 1000), // 1 second ago
  });

  await invokeFunction("deliver-capsule");

  const { data: capsule } = await supabase
    .from("time_capsules")
    .select("*")
    .eq("id", capsuleId)
    .single();

  assertEquals(capsule.status, "delivered");
  assertExists(capsule.companion_letter);
  assertExists(capsule.delivered_at);
});

Deno.test("companion letter includes journey stats", async () => {
  const userId = await createTestUser();

  // Set initial metrics
  await setUserStreak(userId, 10);
  await setUserLevel(userId, 3);

  const capsuleId = await createTestCapsule(userId, {
    deliverAt: new Date(Date.now() - 1000),
  });

  // Update metrics
  await setUserStreak(userId, 50);
  await setUserLevel(userId, 10);

  await invokeFunction("deliver-capsule");

  const { data: capsule } = await supabase
    .from("time_capsules")
    .select("companion_letter")
    .eq("id", capsuleId)
    .single();

  assertStringIncludes(capsule.companion_letter, "streak");
});

Deno.test("cannot open sealed capsule", async () => {
  const userId = await createTestUser();
  const capsuleId = await createTestCapsule(userId, {
    deliverAt: new Date(Date.now() + 86400000), // Tomorrow
  });

  const result = await invokeFunction(
    "open-capsule",
    {
      capsuleId,
    },
    userId,
  );

  assertEquals(result.error, "capsule_not_ready");
});
```

### UI Tests

```swift
func testCreateCapsuleFlowSteps() {
    let flow = CreateCapsuleFlow()

    XCTAssertEqual(flow.currentStep, .theme)

    flow.selectTheme(.encouragement)
    flow.next()
    XCTAssertEqual(flow.currentStep, .content)

    flow.data.textContent = "Hello future me!"
    flow.next()
    XCTAssertEqual(flow.currentStep, .date)

    flow.next()
    XCTAssertEqual(flow.currentStep, .seal)
}

func testOpenCapsuleAnimation() async {
    let capsule = MockData.deliveredCapsule
    let view = OpenCapsuleView(capsule: capsule)

    let rendered = try view.inspect()

    // Initial state - sealed appearance
    XCTAssertTrue(rendered.find(SealedCapsuleView.self).exists)
    XCTAssertFalse(rendered.find(CapsuleContentView.self).exists)

    // Trigger open
    try rendered.find(button: "Open Capsule").tap()

    // After animation
    try await Task.sleep(nanoseconds: 2_000_000_000)
    XCTAssertTrue(rendered.find(CapsuleContentView.self).exists)
}
```
