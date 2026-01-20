# Partner Mode UX

## Step 1: Feature Analysis

### Core purpose and value proposition
- Expose existing partner/buddy capabilities in a cohesive, user-facing experience.
- Drive higher retention through shared goals and encouragement.

### Target users and use cases
- Users who want a partner for accountability and shared wellness.
- Existing buddy/partner relationships already stored in the backend.

### Dependencies / prerequisites
- Buddy relationship data and RPCs (`generate_buddy_code`, `accept_buddy_invite`).
- Couples model structures and any existing partner data tables.
- Notifications for encouragement messages.

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Partner Mode UX
- **Description:** A complete interface for creating a partner link, sharing preferences, completing shared exercises, and sending encouragement. Builds on existing backend support.
- **Business justification and user value:** Makes social support tangible, improving retention and providing a strong premium upsell path.

### 2. Functional Requirements

#### FR1: Partner onboarding flow
- User stories:
  - As a user, I want to invite a partner with a code so we can link accounts.
  - As a user, I want to accept an invite so we can start partnering.
- Acceptance criteria:
  - Users can generate and copy an invite code.
  - Users can enter a code to accept a partner.
  - Errors are surfaced with clear messaging (expired code, self-invite).

#### FR2: Sharing preferences
- User stories:
  - As a user, I want to control what data my partner can see.
- Acceptance criteria:
  - Users can enable/disable sharing of mood, streaks, and quests.
  - Changes take effect immediately in partner views.

#### FR3: Shared activities and encouragement
- User stories:
  - As a user, I want to complete a shared exercise with my partner.
  - As a user, I want to send encouragement messages.
- Acceptance criteria:
  - Shared exercise sessions can be started and completed.
  - Encouragement messages trigger a notification.
  - Partner milestones appear in the shared feed.

### 3. Technical Specifications

#### Architecture and system design considerations
- Reuse existing buddy and couples data models.
- UI layer coordinates with Supabase RPCs and existing endpoints.

#### Data models and schemas (existing + proposed)
- `buddy_relationships` (existing)
- `buddy_encouragements` (existing)
- `partner_links` or couples tables (existing per CouplesModels)
- Optional UI state: `partner_settings` for sharing toggles.

#### API endpoints / interfaces
- Supabase RPC `generate_buddy_code`
- Supabase RPC `accept_buddy_invite`
- Data service `sendEncouragement`

#### Integration points with existing systems
- Home buddy widget.
- Notifications edge function.
- Couples exercise sessions (if available).

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions
- Partner onboarding screen with invite + accept tabs.
- Partner dashboard showing shared stats and streak.
- Shared exercise list with “Start Together” CTAs.

#### User flow diagram (text)
1. User opens Partner Mode.
2. Generates invite or accepts code.
3. Configures sharing preferences.
4. Completes shared activity or sends encouragement.

#### Accessibility requirements
- VoiceOver labels for invite and accept actions.
- Dynamic Type for partner dashboard cards.

### 5. Edge Cases and Error Handling
- If partner already linked, show manage screen instead of onboarding.
- If partner is not sharing a category, display an explanatory placeholder.

### 6. Testing Requirements
- Unit tests: invite code validation, sharing toggle persistence.
- Integration tests: RPC flows, encouragement notification payload.
- UAT: link partner, share data, send encouragement.

### 7. Implementation Notes
- Ensure invite codes are time-limited and single-use.
- Avoid exposing sensitive data without explicit sharing consent.
