# F017: Peer Mentorship Matching

## Overview

### Summary

Anonymous peer support system that matches users who have successfully navigated specific challenges with those currently facing similar situations, enabling 1:1 mentorship within the app.

### Business Value

- Creates strong community bonds increasing retention
- Reduces support burden through peer assistance
- Premium feature with high engagement value

### User Benefit

- Support from someone who truly understands
- Opportunity to help others and reinforce own growth
- Safe, moderated environment for peer connection

### Dependencies

- F015: Life Transition Pathways (for transition-based matching)
- F004: Companion Memory Enhancement (for matching context)

---

## Requirements

### Functional Requirements

| ID     | Requirement                                                    | Priority    |
| ------ | -------------------------------------------------------------- | ----------- |
| FR-001 | Opt-in to become a mentor after completing relevant challenges | Must Have   |
| FR-002 | Request a mentor for specific challenge areas                  | Must Have   |
| FR-003 | Anonymous matching based on challenge similarity               | Must Have   |
| FR-004 | In-app messaging between matched pairs                         | Must Have   |
| FR-005 | Safety guidelines and conversation monitoring                  | Must Have   |
| FR-006 | Report/block functionality                                     | Must Have   |
| FR-007 | Mentor training/guidelines before activation                   | Should Have |
| FR-008 | Time-limited mentorship periods with renewal option            | Should Have |
| FR-009 | Mentor ratings and feedback (anonymous)                        | Should Have |
| FR-010 | Multiple mentorship types (listener, advisor, accountability)  | Could Have  |

### Non-Functional Requirements

| ID      | Requirement            | Target                       |
| ------- | ---------------------- | ---------------------------- |
| NFR-001 | Match finding time     | < 48 hours                   |
| NFR-002 | Message delivery       | Real-time                    |
| NFR-003 | Content moderation     | < 1 hour for flagged content |
| NFR-004 | Anonymity preservation | Zero personal data exposure  |

### Acceptance Criteria

```gherkin
Feature: Peer Mentorship

Scenario: Become a mentor
  Given user completed "Grief Journey" pathway 3 months ago
  When user opts to become a grief mentor
  Then mentor application should be submitted
  And training guidelines should be presented
  And user should be added to mentor pool after acknowledgment

Scenario: Request a mentor
  Given user is in "Job Loss" transition
  When user requests a career mentor
  Then matching algorithm should find suitable mentors
  And match should be made within 48 hours
  And both parties should be notified
  And anonymous chat should be enabled

Scenario: Mentorship messaging
  Given mentor and mentee are matched
  When mentee sends message "I'm struggling today"
  Then mentor should receive notification
  And message should appear in mentorship chat
  And message should be scanned for safety keywords

Scenario: Report inappropriate behavior
  Given user is in mentorship conversation
  When user reports inappropriate message
  Then conversation should be flagged for review
  And reported user should be temporarily suspended
  And moderation team should be notified
```

---

## Technical Design

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    iOS Application                       │
├─────────────────────────────────────────────────────────┤
│  MentorshipService                                      │
│  ├── Mentor registration                                │
│  ├── Mentee matching requests                           │
│  ├── Messaging interface                                │
│  └── Safety reporting                                   │
├─────────────────────────────────────────────────────────┤
│  MentorshipViews                                        │
│  ├── BecomeMentorFlow                                   │
│  ├── FindMentorFlow                                     │
│  ├── MentorshipChatView                                 │
│  └── MentorshipDashboard                                │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│              Supabase Edge Functions                     │
├─────────────────────────────────────────────────────────┤
│  register-mentor                                        │
│  request-mentor-match                                   │
│  process-mentorship-message (with moderation)           │
│  report-mentorship-issue                                │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                PostgreSQL + Realtime                     │
├─────────────────────────────────────────────────────────┤
│  mentors │ mentorship_matches │ mentorship_messages     │
└─────────────────────────────────────────────────────────┘
```

### Data Models

#### Database Schema

```sql
-- Mentor profiles
CREATE TABLE mentors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
        'pending', 'active', 'paused', 'suspended', 'retired'
    )),

    -- Expertise areas
    expertise_areas TEXT[] NOT NULL,
    completed_pathways TEXT[] DEFAULT ARRAY[],
    experience_description TEXT,

    -- Preferences
    max_active_mentees INTEGER NOT NULL DEFAULT 2,
    availability TEXT DEFAULT 'moderate', -- 'limited', 'moderate', 'high'
    mentorship_style TEXT DEFAULT 'supportive', -- 'supportive', 'advisory', 'accountability'

    -- Training
    training_completed BOOLEAN NOT NULL DEFAULT false,
    training_completed_at TIMESTAMPTZ,
    guidelines_acknowledged BOOLEAN NOT NULL DEFAULT false,

    -- Stats
    total_mentees INTEGER NOT NULL DEFAULT 0,
    avg_rating DECIMAL(3,2),
    total_messages_sent INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Mentorship matches
CREATE TABLE mentorship_matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mentor_id UUID NOT NULL REFERENCES mentors(id) ON DELETE CASCADE,
    mentee_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Matching context
    challenge_area TEXT NOT NULL,
    mentee_context TEXT,

    -- Status
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
        'pending', 'active', 'completed', 'ended_by_mentor',
        'ended_by_mentee', 'suspended'
    )),

    -- Timing
    matched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    duration_weeks INTEGER DEFAULT 4,
    renewed_count INTEGER NOT NULL DEFAULT 0,

    -- Anonymous identifiers
    mentor_alias TEXT NOT NULL,
    mentee_alias TEXT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Mentorship messages
CREATE TABLE mentorship_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id UUID NOT NULL REFERENCES mentorship_matches(id) ON DELETE CASCADE,
    sender_user_id UUID NOT NULL REFERENCES auth.users(id),
    content TEXT NOT NULL,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at TIMESTAMPTZ,

    -- Moderation
    flagged BOOLEAN NOT NULL DEFAULT false,
    flag_reason TEXT,
    reviewed BOOLEAN NOT NULL DEFAULT false,
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES auth.users(id)
);

-- Mentor match requests (queue)
CREATE TABLE mentor_match_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    challenge_area TEXT NOT NULL,
    context TEXT,
    preferred_style TEXT DEFAULT 'any',
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
        'pending', 'matched', 'no_match', 'cancelled'
    )),
    matched_with UUID REFERENCES mentorship_matches(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

-- Mentorship feedback
CREATE TABLE mentorship_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id UUID NOT NULL REFERENCES mentorship_matches(id) ON DELETE CASCADE,
    from_user_id UUID NOT NULL REFERENCES auth.users(id),
    rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    helpful BOOLEAN,
    comments TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(match_id, from_user_id)
);

-- Safety reports
CREATE TABLE mentorship_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    match_id UUID NOT NULL REFERENCES mentorship_matches(id),
    reporter_user_id UUID NOT NULL REFERENCES auth.users(id),
    reported_user_id UUID NOT NULL REFERENCES auth.users(id),
    reason TEXT NOT NULL,
    message_ids UUID[] DEFAULT ARRAY[],
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
        'pending', 'reviewing', 'resolved', 'dismissed'
    )),
    resolution TEXT,
    resolved_at TIMESTAMPTZ,
    resolved_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_mentors_status ON mentors(status) WHERE status = 'active';
CREATE INDEX idx_mentors_expertise ON mentors USING GIN (expertise_areas);
CREATE INDEX idx_mentorship_matches_mentor ON mentorship_matches(mentor_id);
CREATE INDEX idx_mentorship_matches_mentee ON mentorship_matches(mentee_user_id);
CREATE INDEX idx_mentorship_matches_active ON mentorship_matches(status) WHERE status = 'active';
CREATE INDEX idx_mentorship_messages_match ON mentorship_messages(match_id, sent_at DESC);
CREATE INDEX idx_mentor_requests_pending ON mentor_match_requests(status, challenge_area)
    WHERE status = 'pending';

-- RLS Policies
ALTER TABLE mentors ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentorship_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentorship_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentor_match_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentorship_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE mentorship_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own mentor profile" ON mentors
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view own matches" ON mentorship_matches
    FOR SELECT USING (
        mentee_user_id = auth.uid() OR
        mentor_id IN (SELECT id FROM mentors WHERE user_id = auth.uid())
    );

CREATE POLICY "Match participants can view messages" ON mentorship_messages
    FOR SELECT USING (
        match_id IN (
            SELECT id FROM mentorship_matches
            WHERE mentee_user_id = auth.uid()
            OR mentor_id IN (SELECT id FROM mentors WHERE user_id = auth.uid())
        )
    );

CREATE POLICY "Match participants can send messages" ON mentorship_messages
    FOR INSERT WITH CHECK (
        match_id IN (
            SELECT id FROM mentorship_matches
            WHERE status = 'active'
            AND (mentee_user_id = auth.uid()
            OR mentor_id IN (SELECT id FROM mentors WHERE user_id = auth.uid()))
        )
    );

CREATE POLICY "Users can manage own requests" ON mentor_match_requests
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can submit own feedback" ON mentorship_feedback
    FOR INSERT WITH CHECK (auth.uid() = from_user_id);

CREATE POLICY "Users can report issues" ON mentorship_reports
    FOR INSERT WITH CHECK (auth.uid() = reporter_user_id);

-- Function to generate anonymous aliases
CREATE OR REPLACE FUNCTION generate_mentor_alias()
RETURNS TEXT AS $$
DECLARE
    adjectives TEXT[] := ARRAY['Wise', 'Kind', 'Calm', 'Gentle', 'Steady', 'Warm', 'Patient', 'Caring'];
    nouns TEXT[] := ARRAY['Oak', 'River', 'Mountain', 'Star', 'Moon', 'Sun', 'Cloud', 'Wave'];
BEGIN
    RETURN adjectives[1 + floor(random() * array_length(adjectives, 1))] || ' ' ||
           nouns[1 + floor(random() * array_length(nouns, 1))];
END;
$$ LANGUAGE plpgsql;
```

#### Swift Models

```swift
// MARK: - Mentorship Models

struct Mentor: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var status: MentorStatus
    let expertiseAreas: [String]
    let completedPathways: [String]
    let experienceDescription: String?
    var maxActiveMentees: Int
    var availability: MentorAvailability
    var mentorshipStyle: MentorshipStyle
    var trainingCompleted: Bool
    var guidelinesAcknowledged: Bool
    let totalMentees: Int
    let avgRating: Double?
    let totalMessagesSent: Int

    var canAcceptMentee: Bool {
        status == .active && trainingCompleted && activeMenteeCount < maxActiveMentees
    }

    var activeMenteeCount: Int = 0 // Populated from matches
}

enum MentorStatus: String, Codable {
    case pending
    case active
    case paused
    case suspended
    case retired
}

enum MentorAvailability: String, Codable {
    case limited
    case moderate
    case high

    var displayName: String {
        switch self {
        case .limited: return "Limited (1-2 messages/week)"
        case .moderate: return "Moderate (several messages/week)"
        case .high: return "High (daily availability)"
        }
    }
}

enum MentorshipStyle: String, Codable, CaseIterable {
    case supportive
    case advisory
    case accountability

    var displayName: String {
        switch self {
        case .supportive: return "Supportive Listener"
        case .advisory: return "Advice & Guidance"
        case .accountability: return "Accountability Partner"
        }
    }

    var description: String {
        switch self {
        case .supportive: return "Focuses on empathetic listening and emotional support"
        case .advisory: return "Shares experiences and offers practical suggestions"
        case .accountability: return "Helps set and track goals with check-ins"
        }
    }
}

struct MentorshipMatch: Codable, Identifiable {
    let id: UUID
    let mentorId: UUID
    let menteeUserId: UUID
    let challengeArea: String
    let menteeContext: String?
    var status: MatchStatus
    let matchedAt: Date
    var startedAt: Date?
    var endedAt: Date?
    let durationWeeks: Int
    let renewedCount: Int
    let mentorAlias: String
    let menteeAlias: String

    // Joined
    var messages: [MentorshipMessage]?
    var unreadCount: Int = 0

    var isActive: Bool {
        status == .active
    }

    var daysRemaining: Int? {
        guard let started = startedAt, status == .active else { return nil }
        let endDate = Calendar.current.date(byAdding: .weekOfYear, value: durationWeeks, to: started)!
        return Calendar.current.dateComponents([.day], from: Date(), to: endDate).day
    }
}

enum MatchStatus: String, Codable {
    case pending
    case active
    case completed
    case endedByMentor = "ended_by_mentor"
    case endedByMentee = "ended_by_mentee"
    case suspended
}

struct MentorshipMessage: Codable, Identifiable {
    let id: UUID
    let matchId: UUID
    let senderUserId: UUID
    let content: String
    let sentAt: Date
    var readAt: Date?
    var flagged: Bool

    var isFromMentor: Bool = false // Set based on context
    var senderAlias: String = "" // Set based on match
}

struct MentorMatchRequest: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let challengeArea: String
    let context: String?
    let preferredStyle: String
    var status: RequestStatus
    let matchedWith: UUID?
    let createdAt: Date
    let expiresAt: Date
}

enum RequestStatus: String, Codable {
    case pending
    case matched
    case noMatch = "no_match"
    case cancelled
}

struct MentorshipFeedback: Codable {
    let id: UUID
    let matchId: UUID
    let fromUserId: UUID
    let rating: Int
    let helpful: Bool?
    let comments: String?
    let createdAt: Date
}

struct MentorshipReport: Codable, Identifiable {
    let id: UUID
    let matchId: UUID
    let reporterUserId: UUID
    let reportedUserId: UUID
    let reason: String
    let messageIds: [UUID]
    var status: ReportStatus
    let createdAt: Date
}

enum ReportStatus: String, Codable {
    case pending
    case reviewing
    case resolved
    case dismissed
}
```

### API Contracts

#### Register as Mentor

```
POST /functions/v1/register-mentor

Request:
{
  "expertiseAreas": ["grief", "job_loss"],
  "experienceDescription": "I lost my mother 2 years ago and went through the grief pathway...",
  "availability": "moderate",
  "mentorshipStyle": "supportive"
}

Response 201:
{
  "mentor": {
    "id": "uuid",
    "status": "pending",
    "trainingRequired": true
  },
  "trainingContent": {
    "guidelines": [...],
    "acknowledgmentRequired": true
  }
}
```

#### Request Mentor Match

```
POST /functions/v1/request-mentor-match

Request:
{
  "challengeArea": "grief",
  "context": "Lost my father recently, struggling with the grief...",
  "preferredStyle": "supportive"
}

Response 201:
{
  "request": {
    "id": "uuid",
    "status": "pending",
    "estimatedMatchTime": "24-48 hours"
  }
}
```

#### Send Message

```
POST /rest/v1/mentorship_messages

Request:
{
  "match_id": "uuid",
  "content": "Thank you for listening. I'm feeling a bit better today."
}

Response 201:
{
  "id": "uuid",
  "sent_at": "2024-01-15T10:30:00Z",
  "flagged": false
}
```

#### Report Issue

```
POST /functions/v1/report-mentorship-issue

Request:
{
  "matchId": "uuid",
  "reason": "inappropriate_advice",
  "messageIds": ["uuid1", "uuid2"],
  "details": "Mentor suggested I should..."
}

Response 201:
{
  "reportId": "uuid",
  "status": "pending",
  "message": "Thank you for reporting. Our team will review within 24 hours."
}
```

---

## Implementation Details

### Step-by-Step Approach

1. **Mentor Registration**
   - Qualification check (completed pathways)
   - Experience description
   - Preference setting
   - Training and guidelines

2. **Matching System**
   - Request queue processing
   - Compatibility scoring
   - Availability checking
   - Anonymous alias assignment

3. **Messaging System**
   - Real-time chat interface
   - Read receipts
   - Content moderation
   - Safety keyword detection

4. **Safety Framework**
   - Keyword flagging
   - Report handling
   - Suspension mechanism
   - Moderation queue

5. **Match Lifecycle**
   - Initial period (4 weeks default)
   - Renewal option
   - Graceful endings
   - Feedback collection

### File Structure

```
apps/ios/MindFriendApp/
├── Features/
│   └── Mentorship/
│       ├── MentorshipService.swift
│       ├── MentorshipMatchingEngine.swift
│       ├── Views/
│       │   ├── BecomeMentorFlow/
│       │   │   ├── MentorQualificationView.swift
│       │   │   ├── MentorPrefsView.swift
│       │   │   └── MentorTrainingView.swift
│       │   ├── FindMentorFlow/
│       │   │   ├── MentorRequestView.swift
│       │   │   └── MatchPendingView.swift
│       │   ├── MentorshipChatView.swift
│       │   ├── MentorshipDashboard.swift
│       │   └── MentorshipFeedbackView.swift
│       └── Components/
│           ├── AnonymousAvatar.swift
│           ├── MessageBubble.swift
│           └── SafetyBanner.swift
│
supabase/
├── functions/
│   ├── register-mentor/
│   ├── request-mentor-match/
│   ├── process-mentorship-message/
│   └── report-mentorship-issue/
├── migrations/
│   └── YYYYMMDD_mentorship.sql
```

### Key Algorithms

#### Mentor Matching (TypeScript)

```typescript
interface MatchingCriteria {
  challengeArea: string;
  preferredStyle?: string;
  context?: string;
}

async function findBestMentor(
  supabase: SupabaseClient,
  request: MentorMatchRequest,
): Promise<Mentor | null> {
  // Get available mentors with matching expertise
  const { data: mentors } = await supabase
    .from("mentors")
    .select(
      `
      *,
      active_matches:mentorship_matches(count)
    `,
    )
    .eq("status", "active")
    .eq("training_completed", true)
    .contains("expertise_areas", [request.challenge_area]);

  if (!mentors?.length) {
    return null;
  }

  // Filter mentors with capacity
  const availableMentors = mentors.filter(
    (m) => m.active_matches[0].count < m.max_active_mentees,
  );

  if (!availableMentors.length) {
    return null;
  }

  // Score each mentor
  const scored = availableMentors.map((mentor) => {
    let score = 0;

    // Style match
    if (
      !request.preferred_style ||
      request.preferred_style === "any" ||
      mentor.mentorship_style === request.preferred_style
    ) {
      score += 20;
    }

    // Rating bonus
    if (mentor.avg_rating) {
      score += mentor.avg_rating * 5; // Up to 25 points
    }

    // Experience bonus
    if (mentor.completed_pathways.includes(request.challenge_area)) {
      score += 15;
    }

    // Availability bonus
    const availabilityScores = { high: 15, moderate: 10, limited: 5 };
    score += availabilityScores[mentor.availability] || 10;

    // Lower mentor count = more attention available
    const menteeCount = mentor.active_matches[0].count;
    score += (mentor.max_active_mentees - menteeCount) * 5;

    return { mentor, score };
  });

  // Sort by score and return best match
  scored.sort((a, b) => b.score - a.score);
  return scored[0]?.mentor || null;
}

async function createMatch(
  supabase: SupabaseClient,
  mentor: Mentor,
  request: MentorMatchRequest,
): Promise<MentorshipMatch> {
  const mentorAlias = await generateAlias();
  const menteeAlias = await generateAlias();

  const { data: match } = await supabase
    .from("mentorship_matches")
    .insert({
      mentor_id: mentor.id,
      mentee_user_id: request.user_id,
      challenge_area: request.challenge_area,
      mentee_context: request.context,
      status: "pending",
      mentor_alias: mentorAlias,
      mentee_alias: menteeAlias,
      duration_weeks: 4,
    })
    .select()
    .single();

  // Update request
  await supabase
    .from("mentor_match_requests")
    .update({
      status: "matched",
      matched_with: match.id,
    })
    .eq("id", request.id);

  // Notify both parties
  await notifyMatch(supabase, match, mentor, request.user_id);

  return match;
}

async function generateAlias(): Promise<string> {
  const adjectives = [
    "Wise",
    "Kind",
    "Calm",
    "Gentle",
    "Steady",
    "Warm",
    "Patient",
    "Caring",
  ];
  const nouns = [
    "Oak",
    "River",
    "Mountain",
    "Star",
    "Moon",
    "Sun",
    "Cloud",
    "Wave",
  ];

  const adj = adjectives[Math.floor(Math.random() * adjectives.length)];
  const noun = nouns[Math.floor(Math.random() * nouns.length)];

  return `${adj} ${noun}`;
}
```

#### Message Moderation (TypeScript)

```typescript
const SAFETY_KEYWORDS = [
  // Crisis keywords
  "suicide",
  "kill myself",
  "end my life",
  "don't want to live",

  // Inappropriate advice
  "stop taking medication",
  "don't need therapy",

  // Personal info
  /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/, // Phone numbers
  /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/, // Emails
];

async function processMessage(
  supabase: SupabaseClient,
  matchId: string,
  senderUserId: string,
  content: string,
): Promise<{ success: boolean; flagged: boolean; reason?: string }> {
  // Check for crisis keywords
  const crisisDetected = checkForCrisis(content);
  if (crisisDetected) {
    // Don't block, but flag and possibly intervene
    await flagMessage(supabase, matchId, content, "crisis_keywords");
    await triggerCrisisIntervention(supabase, senderUserId);
  }

  // Check for inappropriate content
  const flagged = checkForFlags(content);

  // Insert message
  const { data: message } = await supabase
    .from("mentorship_messages")
    .insert({
      match_id: matchId,
      sender_user_id: senderUserId,
      content: content,
      flagged: flagged.detected,
      flag_reason: flagged.reason,
    })
    .select()
    .single();

  // If flagged, notify moderation
  if (flagged.detected) {
    await notifyModerators(supabase, message, flagged.reason);
  }

  return {
    success: true,
    flagged: flagged.detected,
    reason: flagged.reason,
  };
}

function checkForFlags(content: string): {
  detected: boolean;
  reason?: string;
} {
  const lowerContent = content.toLowerCase();

  for (const keyword of SAFETY_KEYWORDS) {
    if (typeof keyword === "string") {
      if (lowerContent.includes(keyword)) {
        return { detected: true, reason: "safety_keyword" };
      }
    } else if (keyword instanceof RegExp) {
      if (keyword.test(content)) {
        return { detected: true, reason: "personal_info" };
      }
    }
  }

  return { detected: false };
}
```

---

## Dependencies

### Internal Dependencies

- **F015 Life Transition Pathways**: For pathway-based qualification
- **F004 Companion Memory**: For context in matching
- **Notification system**: For match and message alerts

### External Dependencies

- Content moderation API (optional enhancement)

### Infrastructure Requirements

- Supabase Realtime for messaging
- Background job for match processing
- Moderation queue interface

---

## Edge Cases & Error Handling

| Scenario                             | Handling                                        |
| ------------------------------------ | ----------------------------------------------- |
| No available mentors                 | Add to queue; notify when available             |
| Mentor becomes unavailable mid-match | Offer to find new mentor                        |
| Both users report each other         | Suspend match; investigate both                 |
| Message contains personal info       | Flag but deliver; warn users                    |
| Crisis keywords detected             | Deliver message; trigger crisis flow for sender |
| Match expires without renewal        | Graceful end; prompt feedback                   |
| Mentor rating drops below threshold  | Review and potentially suspend                  |
| Mentee ghosts mentor                 | Auto-end after 2 weeks inactive                 |

---

## Testing Requirements

### Unit Tests

```swift
// MentorshipServiceTests.swift

func testMentorQualification() {
    let service = MentorshipService(supabase: mockSupabase)
    mockSupabase.setCompletedPathways(["grief", "job_loss"])

    let qualifies = service.qualifiesForExpertise("grief")

    XCTAssertTrue(qualifies)
}

func testAliasGeneration() {
    let alias1 = MentorshipService.generateAlias()
    let alias2 = MentorshipService.generateAlias()

    XCTAssertFalse(alias1.isEmpty)
    XCTAssertTrue(alias1.contains(" ")) // "Adjective Noun" format
}

func testMessageFlagging() {
    let result1 = MentorshipService.checkForFlags("I'm feeling better today")
    XCTAssertFalse(result1.detected)

    let result2 = MentorshipService.checkForFlags("My email is test@example.com")
    XCTAssertTrue(result2.detected)
    XCTAssertEqual(result2.reason, "personal_info")
}

func testMatchCapacity() {
    let mentor = Mentor(
        maxActiveMentees: 2,
        status: .active,
        trainingCompleted: true
    )
    mentor.activeMenteeCount = 2

    XCTAssertFalse(mentor.canAcceptMentee)
}
```

### Integration Tests

```typescript
// supabase/functions/request-mentor-match/test.ts

Deno.test("match finds compatible mentor", async () => {
  const mentorUserId = await createTestUser();
  await registerMentor(mentorUserId, {
    expertiseAreas: ["grief"],
    mentorshipStyle: "supportive",
  });

  const menteeUserId = await createTestUser();
  const request = await invokeFunction(
    "request-mentor-match",
    {
      challengeArea: "grief",
      preferredStyle: "supportive",
    },
    menteeUserId,
  );

  // Process matching (would normally be async)
  await processMatchQueue();

  const { data: match } = await supabase
    .from("mentorship_matches")
    .select("*")
    .eq("mentee_user_id", menteeUserId)
    .single();

  assertExists(match);
  assertEquals(match.status, "pending");
  assertExists(match.mentor_alias);
  assertExists(match.mentee_alias);
});

Deno.test("message flagging works correctly", async () => {
  const { match, mentorUserId, menteeUserId } = await createTestMatch();

  const result = await invokeFunction(
    "process-mentorship-message",
    {
      matchId: match.id,
      content: "Call me at 555-123-4567",
    },
    menteeUserId,
  );

  assertEquals(result.flagged, true);

  // Moderation should be notified
  const { data: flags } = await supabase
    .from("mentorship_messages")
    .select("*")
    .eq("match_id", match.id)
    .eq("flagged", true);

  assertEquals(flags.length, 1);
});
```
