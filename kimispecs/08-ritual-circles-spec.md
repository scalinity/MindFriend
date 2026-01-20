# Ritual Circles (Synchronized Micro-Ceremonies)

## Step 1: Feature Analysis

### Core purpose and value proposition
- Create lightweight, synchronized rituals that deepen circle bonds without long chats.
- Increase daily engagement through shared, time-boxed moments.

### Target users and use cases
- Users with active circles who want a low-effort way to connect.
- Circle owners who want to foster consistency and group accountability.

### Dependencies / prerequisites
- Circles, circle members, and circle posts.
- Push notifications to invite members to ritual start.
- Realtime updates (or polling) for attendance and completion.

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Ritual Circles
- **Description:** Circles can host 3-5 minute rituals with a shared timer, guided prompts, and an automatic recap post.
- **Business justification and user value:** Social ritualization builds emotional connection and habit formation, making MindFriend more sticky and community-oriented.

### 2. Functional Requirements

#### FR1: Create and schedule a ritual
- User stories:
  - As a circle owner, I want to schedule a ritual so that members can join at the same time.
  - As a member, I want to see upcoming rituals so I can plan to attend.
- Acceptance criteria:
  - Rituals can be created with a title, type, start time, and duration.
  - A ritual can be immediate (start now) or scheduled for later.
  - Members receive an invite notification when a ritual is scheduled.

#### FR2: Join and participate
- User stories:
  - As a member, I want to join a ritual and see a shared timer so we are in sync.
  - As a member, I want to respond to prompts so I feel included.
- Acceptance criteria:
  - Members can join up to 2 minutes after start.
  - The ritual view shows a shared countdown and step prompts.
  - Prompts are displayed in a fixed sequence across all members.

#### FR3: Ritual recap post
- User stories:
  - As a circle, I want a recap post so we can see who participated.
  - As a member, I want to add an optional reflection after the ritual.
- Acceptance criteria:
  - A recap post is automatically created when the ritual ends.
  - Recap includes attendance count and an optional highlight line.
  - Each member can add a short reflection (max 140 chars).

### 3. Technical Specifications

#### Architecture and system design considerations
- Ritual lifecycle tracked in database with scheduled start and end.
- Realtime updates or polling for attendance and state transitions.

#### Data models and schemas (proposed)
- `circle_rituals`
  - `id` (uuid, pk)
  - `circle_id` (uuid, fk)
  - `created_by` (uuid, fk)
  - `title` (text)
  - `ritual_type` (text: gratitude | grounding | wins | breathing)
  - `scheduled_for` (timestamptz)
  - `duration_seconds` (int)
  - `status` (text: scheduled | active | completed | cancelled)
  - `created_at` (timestamptz)
- `circle_ritual_attendees`
  - `id` (uuid, pk)
  - `ritual_id` (uuid, fk)
  - `user_id` (uuid, fk)
  - `joined_at` (timestamptz)
  - `left_at` (timestamptz, nullable)
- `circle_ritual_reflections`
  - `id` (uuid, pk)
  - `ritual_id` (uuid, fk)
  - `user_id` (uuid, fk)
  - `body_text` (text, max 140)
  - `created_at` (timestamptz)

#### API endpoints / interfaces
- Edge Function `create-circle-ritual` (POST)
- Edge Function `join-circle-ritual` (POST)
- Edge Function `complete-circle-ritual` (POST) to generate recap post

#### Integration points with existing systems
- Circles feed for recap posts.
- Push notifications via `send-notification` edge function.
- Realtime channel `circle:{id}` for ritual state updates.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions
- Circle detail view shows a “Rituals” card with next ritual and “Start Now.”
- Ritual screen shows shared timer, prompts, and a “Share Reflection” field.
- Recap card appears in the feed with attendance count.

#### User flow diagram (text)
1. Owner creates ritual.
2. Members receive invite notification.
3. Members join ritual and follow prompts.
4. Ritual ends and recap is posted to the feed.

#### Accessibility requirements
- VoiceOver labels for timer and prompt transitions.
- Large button targets and haptic confirmation when joining.

### 5. Edge Cases and Error Handling
- If a user joins late, they jump to the current step.
- If a ritual is cancelled, send a cancellation notice.
- If no one joins, skip recap and mark as completed.

### 6. Testing Requirements
- Unit tests: ritual creation validation, prompt sequencing, recap generation.
- Integration tests: join flow, attendance tracking, notification payload.
- UAT: create ritual, multiple users join, recap post appears.

### 7. Implementation Notes
- Consider server-side cron to activate rituals at scheduled time.
- Use lightweight prompt templates stored in config or database.
- Ensure RLS policies restrict ritual data to circle members.
